(() => {
const SITE = window.NSA_CONFIG || {};
const ARC_LEN = 276.46;
const ATTEMPT_KEY = "nsa-csd01-attempts";
const MAX_SEND_TRIES = 4;
const TURNSTILE_SRC = "https://challenges.cloudflare.com/turnstile/v0/api.js?render=explicit";

const $ = id => document.getElementById(id);
const pad = n => String(n).padStart(2, "0");
const sleep = ms => new Promise(r => setTimeout(r, ms));
let BANK = [];
let DURATION = 3000;
let CODE = "CSD-01";
const state = {
  link: "checking",
  turnstile: false,
  tsWidget: null,
  tsToken: null,
  starting: false,
  session: null,
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
  submission: null
};

const relayBase = (() => {
  let u;
  try { u = new URL(String(SITE.relay || "").trim()); } catch (e) { return null; }
  const local = u.hostname === "localhost" || u.hostname === "127.0.0.1";
  if (u.protocol !== "https:" && !(local && u.protocol === "http:")) return null;
  return u.origin + u.pathname.replace(/\/+$/, "");
})();

const fetchWithTimeout = async (url, opts, ms) => {
  const ctl = new AbortController();
  const t = setTimeout(() => ctl.abort(), ms);
  try {
    return await fetch(url, { ...opts, signal: ctl.signal, credentials: "omit", referrerPolicy: "no-referrer" });
  } finally {
    clearTimeout(t);
  }
};

const api = async (path, body, ms) => {
  try {
    const res = await fetchWithTimeout(relayBase + path, body === undefined
      ? { method: "GET", mode: "cors", cache: "no-store" }
      : { method: "POST", mode: "cors", cache: "no-store", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) }, ms || 20000);
    let data = null;
    try { data = await res.json(); } catch (e) {}
    return { ok: res.ok && Boolean(data && data.ok), status: res.status, data: data || {} };
  } catch (e) {
    return { ok: false, status: "network", data: {} };
  }
};

const toast = (msg) => {
  const t = $("toast");
  t.textContent = msg;
  t.classList.add("show");
  clearTimeout(toast.h);
  toast.h = setTimeout(() => t.classList.remove("show"), 3200);
};

const setOffline = msg => {
  state.link = "offline";
  const n = $("offlineNotice");
  n.textContent = msg;
  n.classList.remove("hidden");
  $("startBtn").disabled = true;
  const chip = $("statusChip");
  chip.textContent = "LINK OFFLINE";
  chip.classList.add("off");
};

const setOnline = () => {
  state.link = "ok";
  $("offlineNotice").classList.add("hidden");
  $("startBtn").disabled = false;
  const chip = $("statusChip");
  chip.textContent = "SECURE LINK";
  chip.classList.remove("off");
};

const loadBank = async () => {
  const res = await fetch("assets/data/bank.json", { cache: "no-cache" });
  if (!res.ok) throw new Error("bank " + res.status);
  const d = await res.json();
  if (!d || !Array.isArray(d.items) || !d.items.length) throw new Error("bank shape");
  BANK = d.items;
  DURATION = Number(d.duration) || DURATION;
  CODE = d.code || CODE;
  const domainSet = [...new Set(BANK.map(q => q.t))];
  $("statQ").textContent = BANK.length;
  $("statT").textContent = Math.round(DURATION / 60) + " min";
  $("statP").textContent = (Number(d.passMark) || 80) + "%";
  $("qnumTot").textContent = "/ " + pad(BANK.length);
  $("domains").replaceChildren(...domainSet.map(t => {
    const s = document.createElement("span");
    s.textContent = t;
    return s;
  }));
};

const loadTurnstile = () => new Promise((resolve, reject) => {
  if (window.turnstile) return resolve(window.turnstile);
  const s = document.createElement("script");
  s.src = TURNSTILE_SRC;
  s.async = true;
  s.onload = () => window.turnstile ? resolve(window.turnstile) : reject(new Error("turnstile"));
  s.onerror = () => reject(new Error("turnstile"));
  document.head.appendChild(s);
});

const resetTurnstile = () => {
  state.tsToken = null;
  if (state.tsWidget !== null && window.turnstile) {
    try { window.turnstile.reset(state.tsWidget); } catch (e) {}
  }
};

const mountTurnstile = async () => {
  const key = String(SITE.turnstileSiteKey || "").trim();
  if (!key) throw new Error("sitekey");
  const ts = await loadTurnstile();
  const box = $("turnstileBox");
  box.classList.remove("hidden");
  state.tsWidget = ts.render(box, {
    sitekey: key,
    theme: "dark",
    action: "start",
    callback: token => { state.tsToken = token; },
    "expired-callback": () => { state.tsToken = null; },
    "error-callback": () => { state.tsToken = null; }
  });
};

const checkLink = async () => {
  if (!relayBase) {
    setOffline("Submissions are offline: no submission relay is configured. Contact command before attempting the assessment.");
    return;
  }
  const h = await api("/health", undefined, 10000);
  if (!h.ok) {
    setOffline(h.status === "network" || h.status === 403
      ? "Submissions are offline: the submission relay could not be reached from this site. Contact command before attempting the assessment."
      : "Submissions are offline: the submission relay is not fully configured (" + (h.data.error || "HTTP " + h.status) + "). Contact command before attempting the assessment.");
    return;
  }
  state.turnstile = Boolean(h.data.turnstile);
  if (state.turnstile) {
    try {
      await mountTurnstile();
    } catch (e) {
      setOffline("Submissions are offline: the security check could not load. Disable content blockers for this site or contact command.");
      return;
    }
  }
  setOnline();
};

const init = async () => {
  $("startBtn").disabled = true;
  try {
    await loadBank();
  } catch (e) {
    setOffline("The assessment could not load. Refresh the page or contact command.");
    return;
  }
  await checkLink();
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

const cleanCallsign = () => $("callsign").value.replace(/[\p{Cf}⠀ㅤﾠ]/gu, "").replace(/\s+/g, " ").trim();

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
    ["", "> Randomizing item bank (" + BANK.length + " items, " + new Set(BANK.map(q => q.t)).size + " domains)"],
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

const startError = res => {
  const e = res.data.error;
  if (e === "turnstile") return "SECURITY CHECK FAILED: TRY AGAIN";
  if (e === "rate") return "TOO MANY ATTEMPTS: WAIT A FEW MINUTES";
  if (e === "callsign" || e === "rank") return "INVALID CALLSIGN OR RANK";
  if (res.status === "network") return "RELAY UNREACHABLE: CHECK YOUR CONNECTION";
  return "SUBMISSIONS OFFLINE: CONTACT COMMAND";
};

const start = async () => {
  if (state.running || state.starting || state.link !== "ok") return;
  if (!validate()) {
    toast("ELIGIBILITY CONFIRMATION REQUIRED");
    return;
  }
  if (state.turnstile && !state.tsToken) {
    toast("COMPLETE THE SECURITY CHECK FIRST");
    return;
  }
  state.starting = true;
  $("startBtn").disabled = true;
  const token = state.tsToken;
  const pending = api("/start", { callsign: cleanCallsign(), rank: $("rank").value, turnstile: token });
  show("boot");
  const [, res] = await Promise.all([boot(), pending]);
  if (state.turnstile) resetTurnstile();
  if (!res.ok) {
    state.starting = false;
    $("startBtn").disabled = false;
    show("gate");
    toast(startError(res));
    return;
  }
  state.session = res.data.session;
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
  state.starting = false;
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
  if (state.viewing !== null && !state.away) state.itemTime[state.viewing] += now - state.enteredAt;
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

const fmtDur = ms => {
  const s = Math.max(0, Math.round(ms / 1000));
  return Math.floor(s / 60) + "m " + pad(s % 60) + "s";
};

const failText = res => {
  const e = res.data.error;
  if (e === "expired") return "session expired";
  if (e === "session") return "session rejected";
  if (e === "payload") return "submission rejected";
  if (e === "bank_changed") return "assessment changed during your attempt";
  if (e === "discord") return "Discord rejected delivery";
  if (res.status === "network") return "network error";
  return "HTTP " + res.status;
};

const transmit = async body => {
  let last = { ok: false, status: "network", data: {} };
  for (let i = 1; i <= MAX_SEND_TRIES; i++) {
    last = await api("/submit", body, 45000);
    if (last.ok) return last;
    const upstream = Number(last.data.status);
    const permanent = last.data.error === "discord" && upstream >= 400 && upstream < 500 && upstream !== 429;
    const retryable = !permanent && (last.status === "network" || last.status === 429 || (typeof last.status === "number" && last.status >= 500));
    if (!retryable || i === MAX_SEND_TRIES) return last;
    await sleep(1500 * 2 ** (i - 1) + rand(750));
  }
  return last;
};

const setDelivery = (mode, detail) => {
  state.delivery = mode;
  const st = $("resultStatus");
  const tx = $("tx");
  const fail = $("txFail");
  const chip = $("statusChip");
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
    chip.textContent = "TRANSMITTING";
    chip.classList.remove("off");
  } else if (mode === "sent") {
    tx.classList.add("ok");
    st.textContent = "Response Transmitted";
    $("txBar").style.width = "100%";
    $("resultMsg").textContent = "Your responses have been sealed and delivered to the NSA Cybersecurity Directorate for command review.";
    $("rRef").textContent = detail;
    $("rIntegrity").textContent = "Delivered (confirmed)" + (state.submission.reason === "Time Expired" ? " • window expired" : "");
    fail.classList.add("hidden");
    chip.textContent = "PACKAGE SEALED";
  } else {
    st.classList.add("fail");
    tx.classList.add("fail");
    st.textContent = "Transmission Failed";
    $("txBar").style.width = "100%";
    $("resultMsg").textContent = "Your responses were not delivered. Keep this page open and retry.";
    $("rIntegrity").textContent = "Not delivered (" + detail + ")";
    fail.classList.remove("hidden");
    $("retryBtn").disabled = false;
    chip.textContent = "LINK FAULT";
    chip.classList.add("off");
  }
};

const deliver = async () => {
  if (!state.submission || state.delivery === "sending" || state.delivery === "sent") return;
  setDelivery("sending");
  const res = await transmit(state.submission);
  if (res.ok) setDelivery("sent", res.data.ref || "—");
  else setDelivery("failed", failText(res));
};

const finish = async (reason) => {
  if (!state.running) return;
  state.running = false;
  clearInterval(state.tick);
  const finishedAt = reason === "Time Expired" ? Math.min(Date.now(), state.endAt) : Date.now();
  markTime(finishedAt);
  state.viewing = null;
  if (state.away) closeAway(finishedAt);
  state.submission = {
    session: state.session,
    reason,
    order: state.order,
    optOrder: state.optOrder,
    answers: state.answers,
    flags: state.flags,
    itemTime: state.itemTime.map(t => Math.round(t)),
    focusEvents: state.focusEvents.map(e => ({ at: Math.round(e.at), dur: Math.round(e.dur) })),
    attempt: state.attempt
  };
  $("rCandidate").textContent = cleanCallsign();
  $("rRank").textContent = $("rank").value;
  $("rRef").textContent = "Pending";
  $("rTime").textContent = new Date(finishedAt).toUTCString();
  $("rDur").textContent = fmtDur(finishedAt - state.startedAt);
  show("result");
  await deliver();
};

const openAway = () => {
  if (!state.running || state.away) return;
  markTime();
  state.away = { at: Date.now() - state.startedAt, since: Date.now() };
};

const closeAway = (at) => {
  if (!state.away) return;
  const back = typeof at === "number" ? at : Date.now();
  const ev = { at: state.away.at, dur: Math.max(0, back - state.away.since) };
  state.away = null;
  state.enteredAt = back;
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

init();
})();
