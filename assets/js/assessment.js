(() => {
const CFG = window.NSA_ASSESSMENT;
const SITE = window.NSA_CONFIG || {};
const BANK = CFG.items;
const KEY_B64 = CFG.key;
const SALT_B64 = CFG.salt;
const DURATION = CFG.duration;
const PASS_MARK = CFG.passMark;
const CODE = CFG.code || "CSD-01";
const ARC_LEN = 276.46;
const DISCORD_RE = /^https:\/\/(?:(?:canary|ptb)\.)?discord(?:app)?\.com\/api\/(?:v\d+\/)?webhooks\/\d+\/[\w-]+\/?$/;
const ATTEMPT_KEY = "nsa-csd01-attempts";
const MAX_SEND_TRIES = 4;

const $ = id => document.getElementById(id);
const pad = n => String(n).padStart(2, "0");
const sleep = ms => new Promise(r => setTimeout(r, ms));
const state = {
  running: false,
  order: [],
  optOrder: [],
  answers: [],
  flags: [],
  itemTime: [],
  viewing: null,
  enteredAt: 0,
  idx: 0,
  endAt: 0,
  startedAt: 0,
  tick: null,
  away: null,
  focusEvents: [],
  attempt: 1,
  delivery: "idle",
  sendTry: 0,
  report: null
};

const resolveWebhook = raw => {
  const v = String(raw || "").trim();
  if (!v) return null;
  let url = v;
  if (!/^https?:\/\//i.test(v)) {
    try { url = atob(v.replace(/\s+/g, "")).split("").reverse().join(""); } catch (e) { return null; }
  }
  let u;
  try { u = new URL(url); } catch (e) { return null; }
  if (u.protocol !== "https:") return null;
  const discord = DISCORD_RE.test(u.origin + u.pathname);
  if (discord) u.pathname = u.pathname.replace(/^\/api\/(?:v\d+\/)?/, "/api/v10/");
  const post = new URL(u.href);
  if (discord) post.searchParams.set("wait", "true");
  return { base: u.href, post: post.href, discord, transport: discord ? "no-cors" : "cors", status: "unchecked" };
};

const endpoint = resolveWebhook(SITE.webhook);

const fetchWithTimeout = async (url, opts, ms) => {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), ms);
  try {
    return await fetch(url, { ...opts, signal: ctl.signal, credentials: "omit", referrerPolicy: "no-referrer" });
  } finally {
    clearTimeout(t);
  }
};

const probeEndpoint = async () => {
  if (!endpoint) return "missing";
  if (!endpoint.discord) {
    endpoint.status = "ok";
    return "ok";
  }
  try {
    const res = await fetchWithTimeout(endpoint.base, { method: "GET", mode: "cors", cache: "no-store" }, 8000);
    endpoint.transport = "cors";
    if (res.status === 401 || res.status === 404) {
      endpoint.status = "invalid";
      return "invalid";
    }
    endpoint.status = "ok";
    return "ok";
  } catch (e) {
    endpoint.transport = "no-cors";
    endpoint.status = "unverified";
    return "unverified";
  }
};

const probe = probeEndpoint();

const recheck = async first => first === "unverified" ? probeEndpoint() : first;

const setOffline = msg => {
  const n = $("offlineNotice");
  n.textContent = msg;
  n.classList.remove("hidden");
  $("startBtn").disabled = true;
  const chip = $("statusChip");
  chip.textContent = "LINK OFFLINE";
  chip.classList.add("off");
};

probe.then(s => {
  if (s === "missing") setOffline("Submissions are offline: no transmission endpoint is configured. Contact command before attempting the assessment.");
  else if (s === "invalid") setOffline("Submissions are offline: the transmission endpoint was rejected. Contact command before attempting the assessment.");
});

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

const cleanCallsign = () => $("callsign").value.replace(/[\p{Cf}\u2800\u3164\uFFA0]/gu, "").replace(/\s+/g, " ").trim();

const validate = () => {
  const cs = /[\p{L}\p{N}]/u.test(cleanCallsign()) ? cleanCallsign() : "";
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
    ["ok", "  [OK] " + cleanCallsign().toUpperCase() + " / " + $("rank").value + " cleared for " + CODE],
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

const bumpAttempt = () => {
  try {
    const n = (parseInt(localStorage.getItem(ATTEMPT_KEY), 10) || 0) + 1;
    localStorage.setItem(ATTEMPT_KEY, String(n));
    return n;
  } catch (e) {
    return 1;
  }
};

const start = async () => {
  if (state.running || $("startBtn").disabled) return;
  if (!validate()) {
    toast("ELIGIBILITY CONFIRMATION REQUIRED");
    return;
  }
  $("startBtn").disabled = true;
  show("boot");
  const [, first] = await Promise.all([boot(), probe]);
  const link = await recheck(first);
  if (link === "missing" || link === "invalid") {
    show("gate");
    toast("SUBMISSIONS OFFLINE: CONTACT COMMAND");
    return;
  }
  state.order = shuffle(BANK.map((_, i) => i));
  state.optOrder = BANK.map(q => shuffle(q.a.map((_, i) => i)));
  state.answers = Array(BANK.length).fill(null);
  state.flags = Array(BANK.length).fill(false);
  state.itemTime = Array(BANK.length).fill(0);
  state.viewing = null;
  state.idx = 0;
  state.away = null;
  state.focusEvents = [];
  state.attempt = bumpAttempt();
  state.startedAt = Date.now();
  state.endAt = state.startedAt + DURATION * 1000;
  state.running = true;
  if (document.visibilityState === "hidden" || !document.hasFocus()) openAway();
  $("candidateMeta").textContent = cleanCallsign() + " • " + $("rank").value;
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

const markTime = (at) => {
  const now = at || Date.now();
  if (state.viewing !== null) state.itemTime[state.viewing] += now - state.enteredAt;
  state.enteredAt = now;
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
  markTime();
  state.viewing = qi;
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
  if (!state.running || i < 0 || i >= BANK.length) return;
  state.idx = i;
  if ($("test").classList.contains("hidden")) show("test");
  render();
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
  if (!state.running) return;
  markTime();
  state.viewing = null;
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

const fmtClock = ms => {
  const s = Math.max(0, Math.floor(ms / 1000));
  return pad(Math.floor(s / 60)) + ":" + pad(s % 60);
};

const mdEscape = s => String(s).replace(/[\\`*_~|<>#:\[\]()]/g, "\\$&");
const fileSafe = s => String(s).replace(/[^A-Za-z0-9_-]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 24) || "candidate";
const letter = (qi, oi) => String.fromCharCode(65 + state.optOrder[qi].indexOf(oi));

const grade = (reason, finishedAt) => {
  const key = decodeKey();
  const domains = new Map();
  let correct = 0;
  BANK.forEach((q, i) => {
    const ok = state.answers[i] === key[i];
    if (ok) correct++;
    const d = domains.get(q.t) || { c: 0, t: 0 };
    d.t++;
    if (ok) d.c++;
    domains.set(q.t, d);
  });
  const answered = state.answers.filter(a => a !== null).length;
  const score = Math.round(correct / BANK.length * 100);
  const awayMs = state.focusEvents.reduce((a, e) => a + (e.dur || 0), 0);
  const items = state.order.map((qi, pos) => {
    const ans = state.answers[qi];
    return {
      pos: pos + 1,
      qi,
      q: BANK[qi],
      ans,
      key: key[qi],
      result: ans === null ? "UNANSWERED" : ans === key[qi] ? "CORRECT" : "INCORRECT",
      flagged: state.flags[qi],
      time: state.itemTime[qi]
    };
  });
  return {
    callsign: cleanCallsign(),
    rank: $("rank").value,
    reason,
    startedAt: state.startedAt,
    finishedAt,
    duration: finishedAt - state.startedAt,
    correct,
    answered,
    score,
    qualified: score >= PASS_MARK,
    flagged: state.flags.filter(Boolean).length,
    domains,
    items,
    focusEvents: state.focusEvents.slice(),
    awayMs,
    attempt: state.attempt,
    ref: ""
  };
};

const buildSheet = r => {
  const line = "=".repeat(64);
  const thin = "-".repeat(64);
  const L = [];
  L.push("NATIONAL SECURITY AGENCY // CYBERSECURITY DIRECTORATE");
  L.push(CODE + " ASSESSMENT ANSWER SHEET");
  L.push(line);
  L.push("Candidate       : " + r.callsign);
  L.push("Rank            : " + r.rank);
  L.push("Submission Ref  : " + r.ref);
  L.push("Started (UTC)   : " + new Date(r.startedAt).toISOString());
  L.push("Submitted (UTC) : " + new Date(r.finishedAt).toISOString());
  L.push("Duration        : " + fmtDur(r.duration));
  L.push("End Condition   : " + r.reason);
  L.push("Score           : " + r.score + "% (" + r.correct + "/" + BANK.length + ") " + (r.qualified ? "QUALIFIED" : "NOT QUALIFIED"));
  L.push("Answered        : " + r.answered + "/" + BANK.length);
  L.push("Flagged         : " + r.flagged);
  L.push("Focus Loss      : " + r.focusEvents.length + (r.focusEvents.length ? " (" + fmtDur(r.awayMs) + " away)" : ""));
  r.focusEvents.forEach((e, i) => L.push("  #" + (i + 1) + " at " + fmtClock(e.at) + " for " + fmtDur(e.dur || 0)));
  L.push("Device Attempt  : " + r.attempt);
  L.push("");
  L.push("DOMAIN BREAKDOWN");
  L.push(thin);
  const w = Math.max(...[...r.domains.keys()].map(d => d.length));
  r.domains.forEach((v, d) => L.push(d.padEnd(w + 2) + v.c + "/" + v.t));
  L.push("");
  L.push("ITEM RESPONSES (in the order presented to the candidate)");
  L.push(thin);
  r.items.forEach(it => {
    L.push("");
    L.push("#" + pad(it.pos) + "  " + it.result + (it.flagged ? "  [FLAGGED]" : "") + "  [" + it.q.t + " | " + it.q.d + "]  time " + fmtDur(it.time));
    L.push("Q: " + it.q.q);
    L.push("Candidate: " + (it.ans === null ? "(no answer)" : letter(it.qi, it.ans) + ") " + it.q.a[it.ans]));
    if (it.result !== "CORRECT") L.push("Correct:   " + letter(it.qi, it.key) + ") " + it.q.a[it.key]);
  });
  L.push("");
  L.push(line);
  L.push("Roblox milsim roleplay group. Not affiliated with the U.S. Government.");
  return L.join("\n");
};

const fitCodeBlock = (lines, limit) => {
  const out = [];
  let size = 8;
  for (const l of lines) {
    if (size + l.length + 1 > limit) break;
    out.push(l);
    size += l.length + 1;
  }
  return "```\n" + out.join("\n") + "\n```";
};

const buildPayload = (r, tryNo) => {
  const https = location.protocol === "https:";
  const icon = https ? new URL("assets/img/apple-touch-icon.png", location.href).href : null;
  const w = Math.max(...[...r.domains.keys()].map(d => d.length));
  const domainLines = [...r.domains].map(([d, v]) => d.padEnd(w + 2) + v.c + "/" + v.t + (v.c === v.t ? "" : "  -" + (v.t - v.c)));
  const marks = r.items.map(it => it.result === "CORRECT" ? "✅" : it.result === "INCORRECT" ? "❌" : "⬜");
  const gridLines = [];
  for (let i = 0; i < marks.length; i += 10) gridLines.push((pad(i + 1) + " " + marks.slice(i, i + 5).join("") + " " + marks.slice(i + 5, i + 10).join("")).trimEnd());
  const flaggedList = r.items.filter(it => it.flagged).map(it => "#" + pad(it.pos)).join(", ");
  const embed = {
    title: "NSA " + CODE + " Cyber Assessment Submission",
    description: "**" + mdEscape(r.callsign).slice(0, 80) + "** (" + mdEscape(r.rank) + ") " + (r.qualified ? "met" : "did not meet") + " the " + PASS_MARK + "% qualification bar. Full answer sheet attached.",
    color: r.qualified ? 3138447 : 16728417,
    fields: [
      { name: "Candidate", value: mdEscape(r.callsign).slice(0, 200) || "N/A", inline: true },
      { name: "Rank", value: mdEscape(r.rank) || "N/A", inline: true },
      { name: "Submission Ref", value: "`" + r.ref + "`", inline: true },
      { name: "Score", value: r.score + "% (" + r.correct + "/" + BANK.length + ")", inline: true },
      { name: "Status", value: r.qualified ? "QUALIFIED" : "NOT QUALIFIED", inline: true },
      { name: "Answered", value: r.answered + "/" + BANK.length + (r.flagged ? " (" + r.flagged + " flagged)" : ""), inline: true },
      { name: "Duration", value: fmtDur(r.duration), inline: true },
      { name: "Focus Loss", value: r.focusEvents.length + (r.focusEvents.length ? " (" + fmtDur(r.awayMs) + " away)" : ""), inline: true },
      { name: "End Condition", value: r.reason + (r.attempt > 1 ? " • device attempt " + r.attempt : ""), inline: true },
      { name: "Domain Breakdown", value: fitCodeBlock(domainLines, 1024), inline: false },
      { name: "Answer Grid (presentation order)", value: fitCodeBlock(gridLines, 960) + "\n✅ correct  ❌ incorrect  ⬜ unanswered", inline: false }
    ],
    footer: { text: "NSA Cybersecurity Directorate • " + CODE + (tryNo > 1 ? " • delivery attempt " + tryNo : "") },
    timestamp: new Date(r.finishedAt).toISOString()
  };
  if (flaggedList) embed.fields.push({ name: "Flagged Items", value: flaggedList.slice(0, 1024), inline: false });
  if (icon) {
    embed.author = { name: "National Security Agency", icon_url: icon };
    embed.thumbnail = { url: icon };
  }
  const payload = {
    username: String(SITE.botName || "").replace(/discord|clyde/gi, "").replace(/\s+/g, " ").trim().slice(0, 80) || "NSA Recruitment Terminal",
    allowed_mentions: { parse: [] },
    embeds: [embed]
  };
  if (icon) payload.avatar_url = icon;
  return payload;
};

const buildForm = (r, tryNo) => {
  const form = new FormData();
  form.append("payload_json", JSON.stringify(buildPayload(r, tryNo)));
  const name = CODE + "_" + fileSafe(r.callsign) + "_" + r.ref + ".txt";
  form.append("files[0]", new Blob([r.sheet], { type: "text/plain;charset=utf-8" }), name);
  return form;
};

const retryAfterMs = async res => {
  let s = NaN;
  try {
    const j = await res.clone().json();
    s = Number(j.retry_after);
  } catch (e) {}
  const h = res.headers.get("Retry-After");
  if (!Number.isFinite(s) && h !== null && h.trim() !== "") s = Number(h);
  return (Number.isFinite(s) && s >= 0 ? Math.min(60000, Math.ceil(s * 1000) + 250) : 2000) + rand(1000);
};

const sendOnce = async (r, tryNo) => {
  const body = buildForm(r, tryNo);
  if (endpoint.transport === "no-cors") {
    await fetchWithTimeout(endpoint.post, { method: "POST", body, mode: "no-cors" }, 30000);
    return { ok: true, confirmed: false };
  }
  const res = await fetchWithTimeout(endpoint.post, { method: "POST", body, mode: "cors" }, 30000);
  if (res.ok) return { ok: true, confirmed: true };
  if (res.status === 429) return { ok: false, retry: true, wait: await retryAfterMs(res), status: 429 };
  if (res.status >= 500) return { ok: false, retry: true, wait: null, status: res.status };
  let detail = "";
  try { detail = (await res.text()).slice(0, 300); } catch (e) {}
  console.error("Submission rejected", res.status, detail);
  return { ok: false, retry: false, status: res.status };
};

const transmit = async r => {
  if (!endpoint) return { ok: false, status: "unconfigured" };
  let last = { ok: false, status: "network" };
  for (let i = 1; i <= MAX_SEND_TRIES; i++) {
    state.sendTry++;
    try {
      last = await sendOnce(r, state.sendTry);
    } catch (e) {
      last = { ok: false, retry: true, wait: null, status: "network" };
    }
    if (last.ok || !last.retry || i === MAX_SEND_TRIES) return last;
    await sleep(last.wait != null ? last.wait : 1000 * 2 ** (i - 1));
  }
  return last;
};

const setDelivery = (mode, detail) => {
  state.delivery = mode;
  const st = $("resultStatus");
  const tx = $("tx");
  const fail = $("txFail");
  st.classList.remove("pending", "fail");
  tx.classList.remove("ok", "fail");
  if (mode === "sending") {
    st.classList.add("pending");
    st.textContent = "Transmitting Package";
    $("txBar").style.width = "72%";
    $("resultMsg").textContent = "Do not close this page until transmission completes.";
    $("rIntegrity").textContent = "Transmitting…";
    fail.classList.add("hidden");
    $("retryBtn").disabled = true;
    $("statusChip").textContent = "TRANSMITTING";
    $("statusChip").classList.remove("off");
  } else if (mode === "sent") {
    tx.classList.add("ok");
    st.textContent = "Response Transmitted";
    $("txBar").style.width = "100%";
    $("resultMsg").textContent = "Your responses have been sealed and transmitted to the NSA Cybersecurity Directorate for command review.";
    $("rIntegrity").textContent = (detail ? "Delivered (confirmed)" : "Transmitted") + (state.report.reason === "Time Expired" ? " • window expired" : "");
    fail.classList.add("hidden");
    $("statusChip").textContent = "PACKAGE SEALED";
  } else {
    st.classList.add("fail");
    tx.classList.add("fail");
    st.textContent = "Transmission Failed";
    $("txBar").style.width = "100%";
    $("resultMsg").textContent = "Your responses were not delivered. Keep this page open and retry.";
    $("rIntegrity").textContent = "Not delivered" + (detail ? " (" + detail + ")" : "");
    fail.classList.remove("hidden");
    $("retryBtn").disabled = false;
    const chip = $("statusChip");
    chip.textContent = "LINK FAULT";
    chip.classList.add("off");
  }
};

const deliver = async () => {
  if (!state.report || state.delivery === "sending" || state.delivery === "sent") return;
  setDelivery("sending");
  if (endpoint && endpoint.status === "unverified" && await probeEndpoint() === "invalid") {
    setDelivery("failed", "endpoint rejected");
    return;
  }
  const res = await transmit(state.report);
  if (res.ok) {
    setDelivery("sent", res.confirmed);
  } else {
    const d = res.status === "unconfigured" ? "no endpoint configured" : res.status === "network" ? "network error" : "HTTP " + res.status;
    setDelivery("failed", d);
  }
};

const finish = async (reason) => {
  if (!state.running) return;
  state.running = false;
  clearInterval(state.tick);
  const finishedAt = reason === "Time Expired" ? Math.min(Date.now(), state.endAt) : Date.now();
  markTime(finishedAt);
  state.viewing = null;
  if (state.away) closeAway(finishedAt);
  const r = grade(reason, finishedAt);
  r.ref = "CSD-" + finishedAt.toString(36).toUpperCase();
  try { r.ref = await makeRef(r.callsign + "|" + r.rank + "|" + finishedAt + "|" + state.answers.join(",")); } catch (e) {}
  r.sheet = buildSheet(r);
  state.report = r;
  $("rCandidate").textContent = r.callsign;
  $("rRank").textContent = r.rank;
  $("rRef").textContent = r.ref;
  $("rTime").textContent = new Date(finishedAt).toUTCString();
  $("rDur").textContent = fmtDur(r.duration);
  show("result");
  await deliver();
};

const openAway = () => {
  if (!state.running || state.away) return;
  state.away = { at: Date.now() - state.startedAt, since: Date.now() };
};

const closeAway = (at) => {
  if (!state.away) return;
  const ev = { at: state.away.at, dur: Math.max(0, (typeof at === "number" ? at : Date.now()) - state.away.since) };
  state.away = null;
  state.focusEvents.push(ev);
  const fc = $("focusCount");
  fc.textContent = state.focusEvents.length;
  fc.classList.add("bad");
  if (state.running) toast("INTEGRITY EVENT LOGGED: WINDOW FOCUS LOST (" + state.focusEvents.length + ")");
};

$("startBtn").addEventListener("click", start);
$("prevBtn").addEventListener("click", () => go(state.idx - 1));
$("nextBtn").addEventListener("click", next);
$("flagBtn").addEventListener("click", toggleFlag);
$("reviewBtn").addEventListener("click", openReview);
$("backBtn").addEventListener("click", () => go(state.idx));
$("submitBtn").addEventListener("click", () => finish("Submitted"));
$("retryBtn").addEventListener("click", deliver);
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
  if (document.visibilityState === "hidden") openAway();
  else if (document.hasFocus()) closeAway();
});
window.addEventListener("blur", openAway);
window.addEventListener("focus", closeAway);

window.addEventListener("beforeunload", e => {
  if (state.running || state.delivery === "sending" || state.delivery === "failed") {
    e.preventDefault();
    e.returnValue = state.running ? "Assessment in progress." : "Responses not yet delivered.";
  }
});
})();
