const RANKS = ["O5", "O6", "O7", "O8", "O9", "O10"];
const REASONS = ["Submitted", "Time Expired"];
const DISCORD_RE = /^https:\/\/(?:(?:canary|ptb)\.)?discord(?:app)?\.com\/api\/(?:v\d+\/)?webhooks\/\d+\/[\w-]+\/?$/;
const MAX_BODY = 65536;
const BANK_TTL_MS = 300000;
const SESSION_GRACE_MS = 900000;
const START_WINDOW_MS = 600000;
const START_LIMIT = 8;
const DEFAULT_BOT = "NSA Recruitment Terminal";
const enc = new TextEncoder();

let bankCache = null;
const delivered = new Map();
const inflight = new Map();
const startHits = new Map();

const pad = n => String(n).padStart(2, "0");
const sleep = ms => new Promise(r => setTimeout(r, ms));
const hex = bytes => Array.from(bytes, b => b.toString(16).padStart(2, "0")).join("");
const b64u = bytes => btoa(String.fromCharCode(...bytes)).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
const b64uDecode = s => Uint8Array.from(atob(s.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((s.length + 3) % 4)), c => c.charCodeAt(0));

const json = (body, status, headers) => new Response(JSON.stringify(body), {
  status,
  headers: { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", ...headers }
});

const allowedOrigins = env => String(env.ALLOWED_ORIGIN || "").split(",").map(s => s.trim().replace(/\/+$/, "")).filter(Boolean);

const corsFor = (origin, ok) => ok ? {
  "Access-Control-Allow-Origin": origin,
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type",
  "Access-Control-Max-Age": "86400",
  "Vary": "Origin"
} : { "Vary": "Origin" };

const siteBase = env => {
  const s = String(env.SITE_URL || "").trim();
  return s.endsWith("/") ? s : s + "/";
};

const webhookUrl = env => {
  let u;
  try { u = new URL(String(env.DISCORD_WEBHOOK || "").trim()); } catch (e) { return null; }
  if (!DISCORD_RE.test(u.origin + u.pathname)) return null;
  u.pathname = u.pathname.replace(/^\/api\/(?:v\d+\/)?/, "/api/v10/");
  u.searchParams.set("wait", "true");
  return u;
};

const validBank = d => d && typeof d.code === "string" && Number.isFinite(d.duration) && d.duration > 0 &&
  Number.isFinite(d.passMark) && Array.isArray(d.items) && d.items.length > 0 &&
  d.items.every(it => it && typeof it.t === "string" && typeof it.d === "string" && typeof it.q === "string" &&
    Array.isArray(it.a) && it.a.length === 4 && it.a.every(x => typeof x === "string"));

const loadBank = async env => {
  const src = new URL("assets/data/bank.json", siteBase(env)).href;
  if (bankCache && bankCache.src === src && Date.now() - bankCache.at < BANK_TTL_MS) return bankCache.data;
  try {
    const res = await fetch(src, { cf: { cacheTtl: 300, cacheEverything: true } });
    if (!res.ok) throw new Error("bank " + res.status);
    const data = await res.json();
    if (!validBank(data)) throw new Error("bank shape");
    bankCache = { src, at: Date.now(), data };
    return data;
  } catch (e) {
    if (bankCache && bankCache.src === src) return bankCache.data;
    throw e;
  }
};

const answerKey = env => String(env.ANSWER_KEY || "").replace(/\s+/g, "");

const configError = async env => {
  if (!webhookUrl(env)) return "webhook";
  if (!String(env.SITE_URL || "").trim()) return "site_url";
  if (!allowedOrigins(env).length) return "allowed_origin";
  let bank;
  try { bank = await loadBank(env); } catch (e) { return "bank"; }
  const key = answerKey(env);
  if (!/^[0-3]+$/.test(key) || key.length !== bank.items.length) return "answer_key";
  return null;
};

const cleanCallsign = v => {
  if (typeof v !== "string") return null;
  const s = v.replace(/[\p{Cf}⠀ㅤﾠ]/gu, "").replace(/\s+/g, " ").trim();
  if (!s || s.length > 40 || !/[\p{L}\p{N}]/u.test(s)) return null;
  return s;
};

const readJson = async request => {
  const len = Number(request.headers.get("Content-Length") || 0);
  if (len > MAX_BODY) return null;
  const text = await request.text();
  if (text.length > MAX_BODY) return null;
  try {
    const v = JSON.parse(text);
    return v && typeof v === "object" && !Array.isArray(v) ? v : null;
  } catch (e) {
    return null;
  }
};

const rateOk = ip => {
  const now = Date.now();
  if (startHits.size > 5000) startHits.clear();
  const hits = (startHits.get(ip) || []).filter(t => now - t < START_WINDOW_MS);
  if (hits.length >= START_LIMIT) {
    startHits.set(ip, hits);
    return false;
  }
  hits.push(now);
  startHits.set(ip, hits);
  return true;
};

const verifyTurnstile = async (env, token, ip) => {
  if (!env.TURNSTILE_SECRET) return true;
  if (typeof token !== "string" || !token || token.length > 2048) return false;
  const form = new FormData();
  form.append("secret", env.TURNSTILE_SECRET);
  form.append("response", token);
  if (ip) form.append("remoteip", ip);
  let out;
  try {
    const res = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", { method: "POST", body: form });
    if (!res.ok) return false;
    out = await res.json();
  } catch (e) {
    return false;
  }
  if (!out || out.success !== true) return false;
  if (!out.hostname) return true;
  const hosts = allowedOrigins(env).map(o => { try { return new URL(o).hostname; } catch (e) { return ""; } });
  return hosts.includes(out.hostname);
};

const hmacKey = env => crypto.subtle.importKey(
  "raw",
  enc.encode("nsa-session:" + (env.SESSION_SECRET || env.DISCORD_WEBHOOK || "")),
  { name: "HMAC", hash: "SHA-256" },
  false,
  ["sign", "verify"]
);

const signSession = async (env, payload) => {
  const body = b64u(enc.encode(JSON.stringify(payload)));
  const sig = new Uint8Array(await crypto.subtle.sign("HMAC", await hmacKey(env), enc.encode(body)));
  return body + "." + b64u(sig);
};

const openSession = async (env, token) => {
  if (typeof token !== "string" || token.length > 2048) return null;
  const parts = token.split(".");
  if (parts.length !== 2) return null;
  try {
    const ok = await crypto.subtle.verify("HMAC", await hmacKey(env), b64uDecode(parts[1]), enc.encode(parts[0]));
    if (!ok) return null;
    const s = JSON.parse(new TextDecoder().decode(b64uDecode(parts[0])));
    if (!s || s.v !== 1 || typeof s.sid !== "string" || !Number.isFinite(s.t) || typeof s.cs !== "string" || !RANKS.includes(s.rk) || !Number.isInteger(s.n)) return null;
    return s;
  } catch (e) {
    return null;
  }
};

const isPerm = (arr, n) => {
  if (!Array.isArray(arr) || arr.length !== n) return false;
  const seen = new Uint8Array(n);
  for (const v of arr) {
    if (!Number.isInteger(v) || v < 0 || v >= n || seen[v]) return false;
    seen[v] = 1;
  }
  return true;
};

const num = (v, max) => Number.isFinite(v) ? Math.min(Math.max(0, Math.round(v)), max) : 0;

const validateSubmission = (b, n, limitMs) => {
  if (!isPerm(b.order, n)) return null;
  if (!Array.isArray(b.optOrder) || b.optOrder.length !== n || !b.optOrder.every(o => isPerm(o, 4))) return null;
  if (!Array.isArray(b.answers) || b.answers.length !== n || !b.answers.every(a => a === null || (Number.isInteger(a) && a >= 0 && a <= 3))) return null;
  if (!REASONS.includes(b.reason)) return null;
  const flags = Array.isArray(b.flags) && b.flags.length === n ? b.flags.map(f => f === true) : Array(n).fill(false);
  const itemTime = Array.isArray(b.itemTime) && b.itemTime.length === n ? b.itemTime.map(t => num(t, limitMs)) : Array(n).fill(0);
  const focusEvents = (Array.isArray(b.focusEvents) ? b.focusEvents.slice(0, 200) : [])
    .filter(e => e && typeof e === "object")
    .map(e => ({ at: num(e.at, limitMs), dur: num(e.dur, limitMs) }));
  const attempt = Number.isInteger(b.attempt) && b.attempt >= 1 && b.attempt <= 9999 ? b.attempt : 1;
  return { order: b.order, optOrder: b.optOrder, answers: b.answers, reason: b.reason, flags, itemTime, focusEvents, attempt };
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

const makeRef = async sid => {
  const h = hex(new Uint8Array(await crypto.subtle.digest("SHA-256", enc.encode("ref:" + sid)))).toUpperCase();
  return "CSD-" + h.slice(0, 4) + "-" + h.slice(4, 8) + "-" + h.slice(8, 12);
};

const grade = (bank, key, sess, sub, receivedAt) => {
  const domains = new Map();
  let correct = 0;
  bank.items.forEach((q, i) => {
    const ok = sub.answers[i] === key[i];
    if (ok) correct++;
    const d = domains.get(q.t) || { c: 0, t: 0 };
    d.t++;
    if (ok) d.c++;
    domains.set(q.t, d);
  });
  const letter = (qi, oi) => String.fromCharCode(65 + sub.optOrder[qi].indexOf(oi));
  const items = sub.order.map((qi, pos) => {
    const ans = sub.answers[qi];
    return {
      pos: pos + 1,
      q: bank.items[qi],
      ans: ans === null ? null : letter(qi, ans) + ") " + bank.items[qi].a[ans],
      key: letter(qi, key[qi]) + ") " + bank.items[qi].a[key[qi]],
      result: ans === null ? "UNANSWERED" : ans === key[qi] ? "CORRECT" : "INCORRECT",
      flagged: sub.flags[qi],
      time: sub.itemTime[qi]
    };
  });
  const score = Math.round(correct / bank.items.length * 100);
  const duration = receivedAt - sess.t;
  return {
    callsign: sess.cs,
    rank: sess.rk,
    reason: sub.reason,
    startedAt: sess.t,
    receivedAt,
    duration,
    overtime: duration > bank.duration * 1000 + 60000,
    correct,
    total: bank.items.length,
    answered: sub.answers.filter(a => a !== null).length,
    score,
    qualified: score >= bank.passMark,
    flagged: sub.flags.filter(Boolean).length,
    domains,
    items,
    focusEvents: sub.focusEvents,
    awayMs: sub.focusEvents.reduce((a, e) => a + e.dur, 0),
    attempt: sub.attempt,
    ref: ""
  };
};

const buildSheet = (bank, r) => {
  const line = "=".repeat(64);
  const thin = "-".repeat(64);
  const L = [];
  L.push("NATIONAL SECURITY AGENCY // CYBERSECURITY DIRECTORATE");
  L.push(bank.code + " ASSESSMENT ANSWER SHEET");
  L.push(line);
  L.push("Candidate       : " + r.callsign);
  L.push("Rank            : " + r.rank);
  L.push("Submission Ref  : " + r.ref);
  L.push("Started (UTC)   : " + new Date(r.startedAt).toISOString() + "  (relay clock)");
  L.push("Received (UTC)  : " + new Date(r.receivedAt).toISOString() + "  (relay clock)");
  L.push("Duration        : " + fmtDur(r.duration) + (r.overtime ? "  OVER TIME LIMIT" : ""));
  L.push("End Condition   : " + r.reason);
  L.push("Score           : " + r.score + "% (" + r.correct + "/" + r.total + ") " + (r.qualified ? "QUALIFIED" : "NOT QUALIFIED"));
  L.push("Answered        : " + r.answered + "/" + r.total);
  L.push("Flagged         : " + r.flagged);
  L.push("Focus Loss      : " + r.focusEvents.length + (r.focusEvents.length ? " (" + fmtDur(r.awayMs) + " away)" : ""));
  r.focusEvents.forEach((e, i) => L.push("  #" + (i + 1) + " at " + fmtClock(e.at) + " for " + fmtDur(e.dur)));
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
    L.push("Candidate: " + (it.ans === null ? "(no answer)" : it.ans));
    if (it.result !== "CORRECT") L.push("Correct:   " + it.key);
  });
  L.push("");
  L.push(line);
  L.push("Graded by the submission relay. Item timing and focus data are reported by the candidate's browser.");
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

const buildPayload = (env, bank, r, tryNo) => {
  const icon = new URL("assets/img/apple-touch-icon.png", siteBase(env)).href;
  const w = Math.max(...[...r.domains.keys()].map(d => d.length));
  const domainLines = [...r.domains].map(([d, v]) => d.padEnd(w + 2) + v.c + "/" + v.t + (v.c === v.t ? "" : "  -" + (v.t - v.c)));
  const marks = r.items.map(it => it.result === "CORRECT" ? "✅" : it.result === "INCORRECT" ? "❌" : "⬜");
  const gridLines = [];
  for (let i = 0; i < marks.length; i += 10) gridLines.push((pad(i + 1) + " " + marks.slice(i, i + 5).join("") + " " + marks.slice(i + 5, i + 10).join("")).trimEnd());
  const flaggedList = r.items.filter(it => it.flagged).map(it => "#" + pad(it.pos)).join(", ");
  const embed = {
    title: "NSA " + bank.code + " Cyber Assessment Submission",
    description: "**" + mdEscape(r.callsign) + "** (" + r.rank + ") " + (r.qualified ? "met" : "did not meet") + " the " + bank.passMark + "% qualification bar. Full answer sheet attached.",
    color: r.qualified ? 3138447 : 16728417,
    fields: [
      { name: "Candidate", value: mdEscape(r.callsign), inline: true },
      { name: "Rank", value: r.rank, inline: true },
      { name: "Submission Ref", value: "`" + r.ref + "`", inline: true },
      { name: "Score", value: r.score + "% (" + r.correct + "/" + r.total + ")", inline: true },
      { name: "Status", value: r.qualified ? "QUALIFIED" : "NOT QUALIFIED", inline: true },
      { name: "Answered", value: r.answered + "/" + r.total + (r.flagged ? " (" + r.flagged + " flagged)" : ""), inline: true },
      { name: "Duration", value: fmtDur(r.duration) + (r.overtime ? " ⚠ over limit" : ""), inline: true },
      { name: "Focus Loss", value: r.focusEvents.length + (r.focusEvents.length ? " (" + fmtDur(r.awayMs) + " away)" : ""), inline: true },
      { name: "End Condition", value: r.reason + (r.attempt > 1 ? " • device attempt " + r.attempt : ""), inline: true },
      { name: "Domain Breakdown", value: fitCodeBlock(domainLines, 1024), inline: false },
      { name: "Answer Grid (presentation order)", value: fitCodeBlock(gridLines, 960) + "\n✅ correct  ❌ incorrect  ⬜ unanswered", inline: false }
    ],
    author: { name: "National Security Agency", icon_url: icon },
    thumbnail: { url: icon },
    footer: { text: "Verified session • graded by relay • " + bank.code + (tryNo > 1 ? " • delivery attempt " + tryNo : "") },
    timestamp: new Date(r.receivedAt).toISOString()
  };
  if (flaggedList) embed.fields.push({ name: "Flagged Items", value: flaggedList.slice(0, 1024), inline: false });
  const name = String(env.BOT_NAME || "").replace(/discord|clyde/gi, "").replace(/\s+/g, " ").trim().slice(0, 80) || DEFAULT_BOT;
  return { username: name, avatar_url: icon, allowed_mentions: { parse: [] }, embeds: [embed] };
};

const retryAfterMs = async res => {
  let s = NaN;
  try { s = Number((await res.clone().json()).retry_after); } catch (e) {}
  const h = res.headers.get("Retry-After");
  if (!Number.isFinite(s) && h !== null && h.trim() !== "") s = Number(h);
  return Number.isFinite(s) && s >= 0 ? Math.min(8000, Math.ceil(s * 1000) + 250) : 2000;
};

const postDiscord = async (env, bank, r) => {
  const target = webhookUrl(env).href;
  const sheet = buildSheet(bank, r);
  const fileName = bank.code + "_" + fileSafe(r.callsign) + "_" + r.ref + ".txt";
  let last = 0;
  for (let i = 1; i <= 3; i++) {
    const form = new FormData();
    form.append("payload_json", JSON.stringify(buildPayload(env, bank, r, i)));
    form.append("files[0]", new Blob([sheet], { type: "text/plain;charset=utf-8" }), fileName);
    let res = null;
    try { res = await fetch(target, { method: "POST", body: form }); } catch (e) { res = null; }
    if (res && res.ok) return { ok: true };
    last = res ? res.status : 0;
    if (res && res.status === 429) { await sleep(await retryAfterMs(res)); continue; }
    if (res && res.status < 500) return { ok: false, status: res.status };
    if (i < 3) await sleep(500 * 2 ** (i - 1));
  }
  return { ok: false, status: last };
};

const handleHealth = async (env, cors) => {
  const err = await configError(env);
  if (err) return json({ ok: false, error: err }, 503, cors);
  return json({ ok: true, turnstile: Boolean(env.TURNSTILE_SECRET) }, 200, cors);
};

const handleStart = async (request, env, cors) => {
  if (await configError(env)) return json({ ok: false, error: "offline" }, 503, cors);
  const ip = request.headers.get("CF-Connecting-IP") || "";
  if (!rateOk(ip)) return json({ ok: false, error: "rate" }, 429, cors);
  const body = await readJson(request);
  if (!body) return json({ ok: false, error: "payload" }, 400, cors);
  const callsign = cleanCallsign(body.callsign);
  if (!callsign) return json({ ok: false, error: "callsign" }, 400, cors);
  if (!RANKS.includes(body.rank)) return json({ ok: false, error: "rank" }, 400, cors);
  if (!await verifyTurnstile(env, body.turnstile, ip)) return json({ ok: false, error: "turnstile" }, 403, cors);
  const bank = await loadBank(env);
  const session = await signSession(env, {
    v: 1,
    sid: hex(crypto.getRandomValues(new Uint8Array(12))),
    t: Date.now(),
    cs: callsign,
    rk: body.rank,
    n: bank.items.length
  });
  return json({ ok: true, session }, 200, cors);
};

const handleSubmit = async (request, env, cors) => {
  if (await configError(env)) return json({ ok: false, error: "offline" }, 503, cors);
  const body = await readJson(request);
  if (!body) return json({ ok: false, error: "payload" }, 400, cors);
  const sess = await openSession(env, body.session);
  if (!sess) return json({ ok: false, error: "session" }, 401, cors);
  const bank = await loadBank(env);
  if (sess.n !== bank.items.length) return json({ ok: false, error: "bank_changed" }, 409, cors);
  const now = Date.now();
  const limitMs = bank.duration * 1000;
  if (now < sess.t || now - sess.t > limitMs + SESSION_GRACE_MS) return json({ ok: false, error: "expired" }, 401, cors);
  const prior = delivered.get(sess.sid);
  if (prior) return json({ ok: true, ref: prior.ref, duplicate: true }, 200, cors);
  if (inflight.has(sess.sid)) {
    const r = await inflight.get(sess.sid);
    return r.ok ? json({ ok: true, ref: r.ref, duplicate: true }, 200, cors) : json({ ok: false, error: "discord", status: r.status }, 502, cors);
  }
  const sub = validateSubmission(body, bank.items.length, limitMs + SESSION_GRACE_MS);
  if (!sub) return json({ ok: false, error: "payload" }, 400, cors);
  const run = (async () => {
    const key = answerKey(env).split("").map(Number);
    const report = grade(bank, key, sess, sub, now);
    report.ref = await makeRef(sess.sid);
    const res = await postDiscord(env, bank, report);
    return { ...res, ref: report.ref };
  })();
  inflight.set(sess.sid, run);
  let result;
  try {
    result = await run;
  } finally {
    inflight.delete(sess.sid);
  }
  if (!result.ok) return json({ ok: false, error: "discord", status: result.status }, 502, cors);
  if (delivered.size > 5000) delivered.clear();
  delivered.set(sess.sid, { ref: result.ref, at: now });
  return json({ ok: true, ref: result.ref }, 200, cors);
};

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const origin = request.headers.get("Origin") || "";
    const allowed = allowedOrigins(env).includes(origin);
    const cors = corsFor(origin, allowed);
    if (request.method === "OPTIONS") return new Response(null, { status: allowed ? 204 : 403, headers: cors });
    if (!allowed) return json({ ok: false, error: "origin" }, 403, cors);
    try {
      if (url.pathname === "/health" && request.method === "GET") return await handleHealth(env, cors);
      if (url.pathname === "/start" && request.method === "POST") return await handleStart(request, env, cors);
      if (url.pathname === "/submit" && request.method === "POST") return await handleSubmit(request, env, cors);
      return json({ ok: false, error: "not_found" }, 404, cors);
    } catch (e) {
      return json({ ok: false, error: "server" }, 500, cors);
    }
  }
};
