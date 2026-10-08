(() => {
const CFG = window.NSA_ASSESSMENT;
const BANK = CFG.items;
const KEY_B64 = CFG.key;
const SALT_B64 = CFG.salt;
const DURATION = CFG.duration;
const PASS_MARK = CFG.passMark;
const WEBHOOK_URL = "";
const ARC_LEN = 276.46;

const $ = id => document.getElementById(id);
const pad = n => String(n).padStart(2, "0");
const state = {
  running: false,
  order: [],
  optOrder: [],
  answers: [],
  flags: [],
  idx: 0,
  endAt: 0,
  startedAt: 0,
  tick: null,
  focusLoss: 0
};

const domainSet = [...new Set(BANK.map(q => q.t))];
$("statQ").textContent = BANK.length;
$("statT").textContent = Math.round(DURATION / 60) + " min";
$("qnumTot").textContent = "/ " + pad(BANK.length);
$("domains").replaceChildren(...domainSet.map(d => {
  const s = document.createElement("span");
  s.textContent = d;
  return s;
}));

const toast = (msg) => {
  const t = $("toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toast.h);
  toast.h = setTimeout(() => t.classList.remove("show"), 2600);
};

const rand = n => {
  const a = new Uint32Array(1);
  crypto.getRandomValues(a);
  return a[0] % n;
};
const shuffle = arr => {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = rand(i + 1);
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
};

const show = id => {
  ["gate", "boot", "test", "review", "result"].forEach(s => $(s).classList.toggle("hidden", s !== id));
  window.scrollTo({ top: 0, behavior: "smooth" });
};

const validate = () => {
  const cs = $("callsign").value.trim();
  const rk = $("rank").value;
  const pc = $("pc").checked;
  const ack = $("ack").checked;
  $("fCallsign").classList.toggle("err", !cs);
  $("fRank").classList.toggle("err", !rk);
  $("lPc").classList.toggle("err", !pc);
  $("lAck").classList.toggle("err", !ack);
  return cs && rk && pc && ack;
};

const boot = () => new Promise(resolve => {
  const lines = [
    ["gd", "NSA/CSD SECURE ASSESSMENT TERMINAL v4.2"],
    ["", "> Establishing encrypted session ........... "],
    ["ok", "  [OK] TLS 1.3 / X25519MLKEM768 negotiated"],
    ["", "> Verifying candidate credentials ......... "],
    ["ok", "  [OK] " + $("callsign").value.trim().toUpperCase() + " / " + $("rank").value + " cleared for CSD-01"],
    ["", "> Randomizing item bank (" + BANK.length + " items, " + domainSet.length + " domains)"],
    ["ok", "  [OK] Item and option order sealed"],
    ["", "> Arming integrity monitor ................ "],
    ["ok", "  [OK] Focus telemetry active"],
    ["gd", "> Assessment window opens in T-1"]
  ];
  const el = $("boot");
  el.replaceChildren();
  lines.forEach(([cls, txt], i) => {
    const d = document.createElement("div");
    d.className = "ln " + cls;
    d.style.animationDelay = (i * 0.17) + "s";
    d.textContent = txt;
    el.appendChild(d);
  });
  const c = document.createElement("span");
  c.className = "cursor";
  el.appendChild(c);
  setTimeout(resolve, lines.length * 170 + 700);
});

const start = async () => {
  if (state.running) return;
  if (!validate()) {
    toast("ELIGIBILITY CONFIRMATION REQUIRED");
    return;
  }
  $("startBtn").disabled = true;
  show("boot");
  await boot();
  state.order = shuffle(BANK.map((_, i) => i));
  state.optOrder = BANK.map(q => shuffle(q.a.map((_, i) => i)));
  state.answers = Array(BANK.length).fill(null);
  state.flags = Array(BANK.length).fill(false);
  state.idx = 0;
  state.focusLoss = 0;
  state.startedAt = Date.now();
  state.endAt = state.startedAt + DURATION * 1000;
  state.running = true;
  $("candidateMeta").textContent = $("callsign").value.trim() + " • " + $("rank").value;
  buildNav();
  show("test");
  render();
  updateTimer();
  state.tick = setInterval(updateTimer, 250);
};

const updateTimer = () => {
  if (!state.running) return;
  const left = Math.max(0, Math.ceil((state.endAt - Date.now()) / 1000));
  $("timer").textContent = pad(Math.floor(left / 60)) + ":" + pad(left % 60);
  $("arc").style.strokeDashoffset = String(ARC_LEN * (1 - left / DURATION));
  $("clock").classList.toggle("warn", left <= 120);
  if (left <= 0) finish("Time Expired");
};

const buildNav = () => {
  $("nav").replaceChildren(...state.order.map((_, i) => {
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = pad(i + 1);
    b.setAttribute("aria-label", "Item " + (i + 1));
    b.addEventListener("click", () => go(i));
    return b;
  }));
};

const refreshNav = () => {
  const btns = $("nav").children;
  for (let i = 0; i < btns.length; i++) {
    const qi = state.order[i];
    btns[i].className = (state.answers[qi] !== null ? "ans " : "") + (state.flags[qi] ? "flg " : "") + (i === state.idx ? "cur" : "");
  }
  const ans = state.answers.filter(a => a !== null).length;
  const flg = state.flags.filter(Boolean).length;
  $("kAns").textContent = ans;
  $("kFlag").textContent = flg;
  $("kLeft").textContent = BANK.length - ans;
};

const render = () => {
  const qi = state.order[state.idx];
  const q = BANK[qi];
  $("qnumCur").textContent = pad(state.idx + 1);
  $("sectionTitle").textContent = q.t;
  const tier = $("tier");
  tier.textContent = q.d;
  tier.className = "tag " + q.d.toLowerCase();
  $("bar").style.width = ((state.idx + 1) / BANK.length * 100) + "%";
  const qEl = document.createElement("div");
  qEl.className = "question";
  qEl.textContent = q.q;
  const opts = document.createElement("div");
  opts.className = "options";
  opts.setAttribute("role", "radiogroup");
  state.optOrder[qi].forEach((oi, pos) => {
    const btn = document.createElement("button");
    btn.type = "button";
    const sel = state.answers[qi] === oi;
    btn.className = "option" + (sel ? " selected" : "");
    btn.setAttribute("role", "radio");
    btn.setAttribute("aria-checked", sel ? "true" : "false");
    const b = document.createElement("b");
    b.textContent = String.fromCharCode(65 + pos);
    const s = document.createElement("span");
    s.textContent = q.a[oi];
    btn.append(b, s);
    btn.addEventListener("click", () => choose(pos));
    opts.appendChild(btn);
  });
  $("question").replaceChildren(qEl, opts);
  $("prevBtn").disabled = state.idx === 0;
  $("nextBtn").innerHTML = state.idx === BANK.length - 1 ? "Review &amp; Submit &rarr;" : "Continue &rarr;";
  const fb = $("flagBtn");
  fb.classList.toggle("flagged", state.flags[qi]);
  fb.textContent = state.flags[qi] ? "Flagged" : "Flag for Review";
  refreshNav();
};

const choose = pos => {
  const qi = state.order[state.idx];
  const oi = state.optOrder[qi][pos];
  if (oi === undefined) return;
  state.answers[qi] = oi;
  const opts = $("question").querySelectorAll(".option");
  opts.forEach((o, i) => {
    o.classList.toggle("selected", i === pos);
    o.setAttribute("aria-checked", i === pos ? "true" : "false");
  });
  refreshNav();
};

const go = i => {
  if (i < 0 || i >= BANK.length) return;
  state.idx = i;
  if (!$("test").classList.contains("hidden")) {
    render();
  } else {
    show("test");
    render();
  }
};

const next = () => {
  if (state.idx < BANK.length - 1) go(state.idx + 1);
  else openReview();
};

const toggleFlag = () => {
  const qi = state.order[state.idx];
  state.flags[qi] = !state.flags[qi];
  render();
};

const reviewList = (el, pred) => {
  const items = [];
  state.order.forEach((qi, i) => {
    if (!pred(qi)) return;
    const b = document.createElement("button");
    b.type = "button";
    b.textContent = "#" + pad(i + 1) + " " + BANK[qi].t;
    b.addEventListener("click", () => go(i));
    items.push(b);
  });
  el.replaceChildren(...items);
  return items.length;
};

const openReview = () => {
  const ans = state.answers.filter(a => a !== null).length;
  $("rvAns").textContent = ans;
  $("rvOpen").textContent = BANK.length - ans;
  $("rvFlag").textContent = state.flags.filter(Boolean).length;
  $("rvOpenWrap").classList.toggle("hidden", reviewList($("rvOpenList"), qi => state.answers[qi] === null) === 0);
  $("rvFlagWrap").classList.toggle("hidden", reviewList($("rvFlagList"), qi => state.flags[qi]) === 0);
  show("review");
};

const decodeKey = () => {
  const k = Uint8Array.from(atob(KEY_B64), c => c.charCodeAt(0));
  const s = Uint8Array.from(atob(SALT_B64), c => c.charCodeAt(0));
  return Array.from(k, (v, i) => v ^ s[i % s.length]);
};

const makeRef = async (seed) => {
  const data = new TextEncoder().encode(seed);
  const buf = await crypto.subtle.digest("SHA-256", data);
  const hex = Array.from(new Uint8Array(buf), b => b.toString(16).padStart(2, "0")).join("").toUpperCase();
  return "CSD-" + hex.slice(0, 4) + "-" + hex.slice(4, 8) + "-" + hex.slice(8, 12);
};

const fmtDur = ms => {
  const s = Math.max(0, Math.round(ms / 1000));
  return Math.floor(s / 60) + "m " + pad(s % 60) + "s";
};

const finish = async (reason) => {
  if (!state.running) return;
  state.running = false;
  clearInterval(state.tick);
  const key = decodeKey();
  let correct = 0;
  const domainStats = {};
  BANK.forEach((q, i) => {
    const ok = state.answers[i] === key[i];
    if (ok) correct++;
    const d = domainStats[q.t] || (domainStats[q.t] = [0, 0]);
    d[1]++;
    if (ok) d[0]++;
  });
  const answered = state.answers.filter(a => a !== null).length;
  const score = Math.round(correct / BANK.length * 100);
  const qualified = score >= PASS_MARK;
  const finishedAt = Date.now();
  const callsign = $("callsign").value.trim();
  const rank = $("rank").value;
  let ref = "CSD-" + finishedAt.toString(36).toUpperCase();
  try { ref = await makeRef(callsign + "|" + rank + "|" + finishedAt + "|" + state.answers.join(",")); } catch (e) {}
  const breakdown = Object.entries(domainStats).map(([d, [c, t]]) => d + ": " + c + "/" + t).join("\n").slice(0, 1024);

  const payload = {
    embeds: [{
      title: "NSA CSD-01 Cyber Assessment Submission",
      color: qualified ? 3138447 : 16728417,
      fields: [
        { name: "Candidate Callsign", value: callsign || "N/A", inline: true },
        { name: "Current Rank", value: rank || "N/A", inline: true },
        { name: "Submission Ref", value: ref, inline: true },
        { name: "Score", value: score + "% (" + correct + "/" + BANK.length + ")", inline: true },
        { name: "Qualification Status", value: qualified ? "QUALIFIED" : "NOT QUALIFIED", inline: true },
        { name: "Completion", value: answered + "/" + BANK.length + " answered", inline: true },
        { name: "Duration", value: fmtDur(finishedAt - state.startedAt), inline: true },
        { name: "Focus Loss Events", value: String(state.focusLoss), inline: true },
        { name: "End Condition", value: reason, inline: true },
        { name: "Domain Breakdown", value: breakdown || "N/A", inline: false }
      ],
      timestamp: new Date(finishedAt).toISOString()
    }]
  };

  if (WEBHOOK_URL) {
    fetch(WEBHOOK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload)
    }).catch(() => {});
  }

  $("rCandidate").textContent = callsign;
  $("rRank").textContent = rank;
  $("rRef").textContent = ref;
  $("rTime").textContent = new Date(finishedAt).toUTCString();
  $("rDur").textContent = fmtDur(finishedAt - state.startedAt);
  $("rIntegrity").textContent = reason === "Time Expired" ? "Transmitted (window expired)" : "Transmitted";
  $("statusChip").textContent = "PACKAGE SEALED";
  show("result");
  requestAnimationFrame(() => requestAnimationFrame(() => { $("txBar").style.width = "100%"; }));
  setTimeout(() => { $("resultStatus").textContent = "Response Transmitted"; }, 1600);
};

$("startBtn").addEventListener("click", start);
$("prevBtn").addEventListener("click", () => go(state.idx - 1));
$("nextBtn").addEventListener("click", next);
$("flagBtn").addEventListener("click", toggleFlag);
$("reviewBtn").addEventListener("click", openReview);
$("backBtn").addEventListener("click", () => go(state.idx));
$("submitBtn").addEventListener("click", () => finish("Submitted"));
["callsign", "rank"].forEach(id => $(id).addEventListener("input", () => $(id === "callsign" ? "fCallsign" : "fRank").classList.remove("err")));
$("pc").addEventListener("change", () => $("lPc").classList.remove("err"));
$("ack").addEventListener("change", () => $("lAck").classList.remove("err"));

document.addEventListener("keydown", e => {
  if (!state.running || $("test").classList.contains("hidden")) return;
  if (e.ctrlKey || e.metaKey || e.altKey) return;
  const k = e.key.toLowerCase();
  const map = { "1": 0, "2": 1, "3": 2, "4": 3, "a": 0, "b": 1, "c": 2, "d": 3 };
  if (k in map) { e.preventDefault(); choose(map[k]); }
  else if (k === "arrowright" || k === "enter") { e.preventDefault(); next(); }
  else if (k === "arrowleft") { e.preventDefault(); go(state.idx - 1); }
  else if (k === "f") { e.preventDefault(); toggleFlag(); }
});

document.addEventListener("visibilitychange", () => {
  if (!state.running || document.visibilityState !== "hidden") return;
  state.focusLoss++;
  const fc = $("focusCount");
  fc.textContent = state.focusLoss;
  fc.classList.add("bad");
  setTimeout(() => toast("INTEGRITY EVENT LOGGED: WINDOW FOCUS LOST (" + state.focusLoss + ")"), 300);
});

window.addEventListener("beforeunload", e => {
  if (state.running) { e.preventDefault(); e.returnValue = "Assessment in progress."; }
});
})();
