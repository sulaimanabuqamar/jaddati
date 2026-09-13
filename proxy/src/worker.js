/**
 * Jaddati proxy.
 *
 * The app used to carry the ElevenLabs and Groq keys in its own bundle. That is
 * fine while the only phone running it is yours; it stops being fine the moment
 * a build goes to TestFlight, because anyone holding the app holds the keys —
 * and the damage is not only the credits. Every voice a stranger clones takes a
 * slot out of the same account the demo needs.
 *
 * So the keys live here instead. The app authenticates with a token that is
 * ours to rotate, this worker counts what each ACCOUNT spends, and it hands a
 * voice slot to whoever needs it next by taking the one nobody is using.
 *
 * Speaking and cloning need a Google sign-in. Looking around does not: the
 * whole archive, every recording already made, both languages and the handoff
 * all work signed out. The sign-in is asked for at the moment something is
 * about to be spent, and it is the same sign-in the Drive backup already
 * uses, not a second account.
 *
 * It deliberately MIMICS both upstream APIs path-for-path. The app's clients
 * were already written against a configurable base URL, so pointing them here
 * is a settings change rather than a rewrite.
 *
 *   POST /v1/voices/add                  -> ElevenLabs, one voice per account
 *   POST /v1/text-to-speech/{voiceId}    -> ElevenLabs, billed to the account
 *   POST /chat/completions               -> Groq (questions while reading)
 *   POST /audio/transcriptions           -> Groq (speaking instead of typing)
 *   POST /admin/accounts                 -> who has signed in (admin token)
 *   GET  /health                         -> plain OK, for checking a deploy
 *
 * One honest limit: the app still has to prove it is the app, so a token still
 * ships in the bundle. The difference from before is that this one is ours to
 * revoke in thirty seconds, and on its own it can spend nothing at all — the
 * spending needs a verified Google account behind it.
 */

import { refusal } from "./blocked-words.js";

const ELEVEN = "https://api.elevenlabs.io";

// ---------------------------------------------------------------- helpers

const json = (status, detail) =>
  new Response(JSON.stringify({ detail }), {
    status,
    headers: { "content-type": "application/json" },
  });

/** The month a spend counts against. Allowances reset with the calendar. */
const period = () => new Date().toISOString().slice(0, 7); // YYYY-MM

/**
 * The token the app sends. ElevenLabs calls carry it as `xi-api-key`, Groq
 * calls as `Authorization: Bearer` — we accept it in whichever slot the
 * upstream API would have used, so neither client needed a special case.
 */
function appToken(request) {
  const xi = request.headers.get("xi-api-key");
  if (xi) return xi;
  const auth = request.headers.get("authorization") || "";
  return auth.toLowerCase().startsWith("bearer ") ? auth.slice(7).trim() : "";
}

/**
 * Who is spending. `identifierForVendor` on the phone: stable for this app on
 * this device, gone when the app is removed. Not an identity, just a meter
 * reading — we never store anything alongside it.
 */
function deviceId(request) {
  const id = (request.headers.get("x-jaddati-device") || "").trim();
  return /^[A-Za-z0-9-]{8,64}$/.test(id) ? id : "";
}

const num = (value, fallback) => {
  const n = parseInt(value, 10);
  return Number.isFinite(n) ? n : fallback;
};

/**
 * How long a shared voice lives, in seconds.
 *
 * Measured in minutes rather than days because during a demonstration the
 * account has to clear itself between people. KV refuses anything under a
 * minute, so that is the floor whatever the setting says.
 */
const voiceTTL = env => Math.max(60, num(env.VOICE_TTL_MINUTES, 10) * 60);


// ── who is asking ───────────────────────────────────────────────────────
//
// The device header was never an identity. It is a string the caller writes,
// so clearing site data mints a new one, and every per-device limit under it
// was friction rather than a limit. That was fine while the only ceiling that
// mattered was the global one; it stops being fine the moment the allowance
// is meant to belong to a person.
//
// So speaking and cloning now need a Google account. The app already signs in
// with Google for the Drive backup, so this is the same sign-in, not a second
// one — and it is asked for only at the point of generating, never to look
// around.
//
// The token is verified with Google rather than merely decoded. A JWT that is
// only decoded is a JWT anyone can write. Verified once and then cached
// against its own expiry, so this costs one upstream call per sign-in rather
// than one per sentence.

const TOKENINFO = "https://oauth2.googleapis.com/tokeninfo?id_token=";

/** A short, stable key for a token, so the cache is not keyed on the token. */
async function digest(text) {
  const bytes = new TextEncoder().encode(text);
  const hash = await crypto.subtle.digest("SHA-256", bytes);
  return [...new Uint8Array(hash)].slice(0, 16)
    .map(b => b.toString(16).padStart(2, "0")).join("");
}

function audienceAllowed(aud, env) {
  const allowed = [env.GOOGLE_CLIENT_ID, env.GOOGLE_IOS_CLIENT_ID].filter(Boolean);
  return allowed.includes(aud);
}

/**
 * The account behind this request, or null.
 *
 * Null covers every failure the same way on purpose — expired, forged, wrong
 * audience, Google unreachable. The caller turns all of them into "sign in
 * again", because there is nothing a person can do differently for any of
 * them, and naming which one would tell somebody probing the endpoint which
 * part of their forgery to fix.
 */
async function accountFor(request, env) {
  const token = (request.headers.get("x-jaddati-account") || "").trim();
  if (!token || token.length > 4096) return null;

  const key = "tok:" + (await digest(token));
  const cached = await env.JADDATI.get(key);
  if (cached) {
    try { return JSON.parse(cached); } catch { /* fall through and re-verify */ }
  }

  let claims;
  try {
    const r = await fetch(TOKENINFO + encodeURIComponent(token));
    if (!r.ok) return null;
    claims = await r.json();
  } catch {
    return null;
  }

  if (!claims || !claims.sub) return null;
  if (!audienceAllowed(claims.aud, env)) return null;

  const expires = num(claims.exp, 0) * 1000;
  const seconds = Math.floor((expires - Date.now()) / 1000);
  if (seconds <= 0) return null;

  const account = { sub: String(claims.sub), email: String(claims.email || "") };
  // Never cached longer than the token is good for, and never under KV's own
  // one-minute floor.
  await env.JADDATI.put(key, JSON.stringify(account),
                        { expirationTtl: Math.max(60, Math.min(seconds, 3600)) });
  return account;
}

/**
 * The roll of who has signed in, for the admin page.
 *
 * Deliberately thin: the subject id, the email they signed in with, when they
 * first and last appeared, and what they have spent. No text, no recordings,
 * nothing about who they were speaking to. An admin page that can read a
 * family's words would be a worse thing than the problem it solves.
 */
async function noteAccount(env, account, spent) {
  const key = "acct:" + account.sub;
  let record = {};
  try { record = JSON.parse(await env.JADDATI.get(key)) || {}; } catch { record = {}; }
  const now = Date.now();
  const next = {
    sub: account.sub,
    email: account.email || record.email || "",
    firstSeen: record.firstSeen || now,
    lastSeen: now,
    generations: num(record.generations, 0) + (spent > 0 ? 1 : 0),
    characters: num(record.characters, 0) + Math.max(spent, 0),
  };
  // A year, so the roll survives the demo and a month of afterwards.
  await env.JADDATI.put(key, JSON.stringify(next), { expirationTtl: 365 * 86400 });
}

// ---------------------------------------------------------------- routes


/**
 * Hand back the slot that has gone longest without being used.
 *
 * This replaces deleting every voice on a ten-minute timer. The timer was
 * indiscriminate: it took the voice of whoever happened to be mid-sentence
 * just as readily as one nobody had touched for an hour, and during a
 * demonstration that is precisely the wrong person. Least-recently-used takes
 * the one nobody is holding, so the six people actually using the app keep
 * theirs and a seventh still gets in.
 *
 * Returns false if nothing could be freed, and the caller then refuses rather
 * than guessing.
 */
async function evictOldestVoice(env) {
  const listing = await env.JADDATI.list({ prefix: "v:" });
  let oldest = null;
  for (const entry of listing.keys) {
    let record = null;
    try { record = JSON.parse(await env.JADDATI.get(entry.name)); } catch { continue; }
    if (!record) continue;
    const seen = num(record.lastUsed, num(record.created, 0));
    if (!oldest || seen < oldest.seen) {
      oldest = { name: entry.name, seen, account: record.account || "" };
    }
  }
  if (!oldest) return false;

  const voiceId = oldest.name.slice(2);
  try {
    const gone = await fetch(`${ELEVEN}/v1/voices/${voiceId}`, {
      method: "DELETE",
      headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
    });
    // Already gone counts: the slot is free either way.
    if (!gone.ok && gone.status !== 404) return false;
  } catch {
    return false;
  }

  await env.JADDATI.delete(oldest.name);
  if (oldest.account) await env.JADDATI.delete(`voice:acct:${oldest.account}`);
  const live = num(await env.JADDATI.get("voices:live"), 0);
  await env.JADDATI.put("voices:live", String(Math.max(live - 1, 0)));
  return true;
}

/** Touch a voice so eviction knows it is in use. */
async function touchVoice(env, voiceId) {
  const key = `v:${voiceId}`;
  let record = null;
  try { record = JSON.parse(await env.JADDATI.get(key)); } catch { return; }
  if (!record) return;
  record.lastUsed = Date.now();
  await env.JADDATI.put(key, JSON.stringify(record), { expirationTtl: 30 * 86400 });
}

/**
 * Creating a voice. This is the call that can break demo day, so it is the
 * strictest: one voice per ACCOUNT, and a hard ceiling across everyone so the
 * account can never fill up completely.
 */
async function createVoice(request, env) {
  const account = await accountFor(request, env);
  if (!account) return json(401, "sign in to create a voice");

  const perDevice = await env.JADDATI.get(`voice:acct:${account.sub}`);
  if (perDevice) {
    // A lock is only worth honouring while the voice it names still exists.
    // The sweep lifts locks when it runs, but it runs on a timer, and a put
    // that failed halfway through creation can leave a lock with nothing
    // behind it. Either way the person is standing in front of the app being
    // told they have a voice they cannot hear. So: ask upstream, and if the
    // voice is gone, let the lock go and carry on.
    let stillThere = true;
    try {
      const look = await fetch(`${ELEVEN}/v1/voices/${perDevice}`, {
        headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
      });
      stillThere = look.status !== 404;
    } catch {
      // Upstream unreachable is not evidence the voice is gone. Keep the lock
      // rather than handing out a second slot on a guess.
      stillThere = true;
    }

    if (stillThere) {
      // Deliberately worded so the clients can tell this apart from the
      // account being full. Telling someone the account has no room, when in
      // fact their own phone is holding the only slot they are allowed, sends
      // them looking in the wrong place.
      return json(429, "this account already has a voice");
    }

    await env.JADDATI.delete(`voice:acct:${account.sub}`);
    if (await env.JADDATI.get(`v:${perDevice}`)) {
      await env.JADDATI.delete(`v:${perDevice}`);
      const before = num(await env.JADDATI.get("voices:live"), 0);
      await env.JADDATI.put("voices:live", String(Math.max(before - 1, 0)));
    }
  }

  const cap = num(env.MAX_VOICES, 6);
  let live = num(await env.JADDATI.get("voices:live"), 0);
  if (live >= cap) {
    // Make room rather than turning someone away. The person who has not
    // spoken for longest loses their voice; the six people using the app
    // right now do not.
    if (!(await evictOldestVoice(env))) {
      return json(429, "voice limit reached: no slots are free right now");
    }
    live = num(await env.JADDATI.get("voices:live"), 0);
  }

  const upstream = await fetch(`${ELEVEN}/v1/voices/add`, {
    method: "POST",
    headers: {
      "xi-api-key": env.ELEVENLABS_API_KEY,
      "content-type": request.headers.get("content-type") || "",
    },
    body: await request.arrayBuffer(),
  });

  const body = await upstream.text();
  if (!upstream.ok) return new Response(body, { status: upstream.status });

  // Record it so the nightly sweep can hand the slot back.
  try {
    const voiceId = JSON.parse(body).voice_id;
    if (voiceId) {
      const ttl = voiceTTL(env);
      const now = Date.now();
      // The device's lock outlives the voice on purpose, and the sweep lifts it
      // the moment the voice is actually gone. Expiring the lock first would
      // let one person hold two voices at once; expiring it later, with no
      // sweep to lift it, would tell them they still have a voice that has
      // already been deleted. The TTLs here are only the safety net for a
      // sweep that never runs.
      // No short expiry any more. A voice lives until somebody else needs the
      // slot, which is what "it just works" means in a room of six people.
      await env.JADDATI.put(`voice:acct:${account.sub}`, voiceId, { expirationTtl: 30 * 86400 });
      await env.JADDATI.put(
        `v:${voiceId}`,
        JSON.stringify({ account: account.sub, created: now, lastUsed: now }),
        { expirationTtl: 30 * 86400 }
      );
      await env.JADDATI.put("voices:live", String(live + 1));
    }
  } catch {
    // A recording failure must not cost the user a voice they already paid
    // for. Worst case the sweep misses one and a slot is reclaimed by hand.
  }

  return new Response(body, {
    status: upstream.status,
    headers: { "content-type": "application/json" },
  });
}

/**
 * Speaking. Billed by character, because that is how ElevenLabs bills and how
 * the app already quotes it on screen ("≈ 320 credits").
 */
/**
 * Delete a voice, and give the slot back.
 *
 * Only the account that made a voice may delete it — the per-account key is
 * the proof. Without that check any visitor could delete any family's voice,
 * which is a worse failure than not being able to delete at all.
 *
 * A voice that is already gone counts as success: the caller wanted it absent,
 * and it is. The counter only ever moves on a KV record we actually removed,
 * so a repeated delete cannot drive `voices:live` below the real number.
 */
async function deleteVoice(request, env, voiceId) {
  const account = await accountFor(request, env);
  if (!account) return json(401, "sign in to remove a voice");
  const owned = await env.JADDATI.get(`voice:acct:${account.sub}`);
  if (owned !== voiceId) return json(403, "not this account's voice");

  const gone = await fetch(`${ELEVEN}/v1/voices/${voiceId}`, {
    method: "DELETE",
    headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
  });
  if (!gone.ok && gone.status !== 404) {
    return json(gone.status, "the voice service refused the deletion");
  }

  const had = await env.JADDATI.get(`v:${voiceId}`);
  await env.JADDATI.delete(`v:${voiceId}`);
  await env.JADDATI.delete(`voice:acct:${account.sub}`);
  if (had) {
    const live = num(await env.JADDATI.get("voices:live"), 0);
    await env.JADDATI.put("voices:live", String(Math.max(live - 1, 0)));
  }

  return new Response(null, { status: 204 });
}

async function speak(request, env, voiceId) {
  const account = await accountFor(request, env);
  if (!account) return json(401, "sign in to make new audio");
  const raw = await request.text();

  let text = "";
  try { text = String(JSON.parse(raw).text || ""); } catch { return json(400, "malformed request"); }
  if (!text) return json(400, "no text to speak");

  // The clients check the same list before spending anything, and this is why
  // that is not enough: the web build is readable, the token in it is readable
  // with it, and a phone can be pointed at this relay by anyone who reads the
  // repository. A filter that lives only in a client is a suggestion.
  if (refusal(text)) return json(400, "those words will not be spoken here");

  // The fallback has to be at least one full generation, or an unset variable
  // refuses a visitor their first sentence and tells them the month is spent.
  // The break tags are the app's doing, not the person's. They go to the voice
  // service because that is how a pause is asked for, but taking them out of
  // somebody's allowance would be charging them for the app's punctuation.
  const billable = text.replace(/<break\s[^>]*\/?>/gi, "").length;

  const allowance = num(env.CREDITS_PER_ACCOUNT, 1000);
  const key = `used:acct:${account.sub}:${period()}`;
  const spent = num(await env.JADDATI.get(key), 0);

  if (spent + billable > allowance) {
    const left = Math.max(allowance - spent, 0);
    // "credits" in the message is load-bearing: the app reads the wording and
    // shows its own translated "this month's credits are used up" line.
    return json(429, `credit allowance used for this month (${left} of ${allowance} left)`);
  }

  // And a ceiling across EVERYONE. The per-device meter is keyed on a header
  // the caller writes, so clearing site data mints a new meter — it is
  // friction, not a limit, and on its own it does not stop one determined
  // visitor draining the month's credits for the whole account. This is the
  // number that protects the bill.
  const monthKey = `used:all:${period()}`;
  const monthCap = num(env.CREDITS_PER_MONTH, 100000);
  const monthSpent = num(await env.JADDATI.get(monthKey), 0);
  if (monthSpent + billable > monthCap) {
    // Worded so the client does NOT map it to the per-device "this month's
    // allowance is used up" line: that reads as personal, and the person
    // reading it has spent nothing. This is the account, not them.
    return json(503, "the shared allowance for this month is used up");
  }

  const url = new URL(request.url);
  const upstream = await fetch(
    `${ELEVEN}/v1/text-to-speech/${encodeURIComponent(voiceId)}${url.search}`,
    {
      method: "POST",
      headers: {
        "xi-api-key": env.ELEVENLABS_API_KEY,
        "content-type": "application/json",
        accept: "audio/mpeg",
      },
      body: raw,
    }
  );

  // Charge only for audio that arrived. A failed generation is not billed to
  // the person who asked for it.
  if (upstream.ok) {
    await env.JADDATI.put(key, String(spent + billable), { expirationTtl: 70 * 86400 });
    // Eviction takes the voice nobody has used for longest, so a voice being
    // used has to say so.
    await touchVoice(env, voiceId);
    await noteAccount(env, account, billable);
    // Re-read rather than reuse `monthSpent`: the check happened before the
    // upstream call, and on a busy minute several requests will have been in
    // flight since.
    //
    // Still lossy under real concurrency, and the loss goes the UNSAFE way: an
    // undercount means the ceiling is reached later than it should be, so more
    // is spent than the cap allows. It is a backstop against one visitor
    // draining the month, not an accounting system, and the number to watch is
    // the one in the ElevenLabs dashboard.
    const now = num(await env.JADDATI.get(monthKey), monthSpent);
    await env.JADDATI.put(monthKey, String(now + billable), { expirationTtl: 70 * 86400 });
  }

  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": upstream.headers.get("content-type") || "audio/mpeg" },
  });
}

/**
 * Groq, for questions during a story and for dictation.
 *
 * Cheap per call, which is not the same as free: the relay token is published
 * in the web build, so anyone who reads the page source had an unmetered
 * language model on our key. Counted per device per month like speech, with a
 * far looser allowance — the point is a ceiling, not a budget.
 */
async function groq(request, env, path) {
  const device = deviceId(request);
  const askKey = `asks:${device}:${period()}`;
  const askCap = num(env.ASKS_PER_DEVICE, 200);
  const asked = num(await env.JADDATI.get(askKey), 0);
  if (asked >= askCap) {
    return json(429, "question allowance used for this month");
  }
  await env.JADDATI.put(askKey, String(asked + 1), { expirationTtl: 70 * 86400 });

  const upstream = await fetch(`${env.LLM_BASE_URL}${path}`, {
    method: "POST",
    headers: {
      authorization: `Bearer ${env.LLM_API_KEY}`,
      "content-type": request.headers.get("content-type") || "application/json",
    },
    body: await request.arrayBuffer(),
  });
  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": upstream.headers.get("content-type") || "application/json" },
  });
}

// ---------------------------------------------------------------- entry

/**
 * The web build calls this worker from a different origin than it is served
 * from, and it sends `xi-api-key` and `x-jaddati-device` — neither of which a
 * browser will send without asking permission first. So every answer carries
 * that permission, the failures included: without it the browser hides the
 * response body, and the app reports a flat network error instead of the
 * "credits used up" message it has a translation for.
 *
 * The origin is left open on purpose. The token the web build sends is readable
 * in the page by anyone who views source, so turning away unknown origins would
 * inconvenience honest visitors without stopping anyone who meant harm. What
 * actually bounds the damage is the metering below: one voice per account, a
 * hard ceiling across everyone, and a monthly character budget.
 */
const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "GET, POST, DELETE, OPTIONS",
  "access-control-allow-headers": "xi-api-key, authorization, content-type, x-jaddati-device, x-jaddati-account, x-jaddati-admin, accept",
  "access-control-max-age": "86400",
};

function withCors(response) {
  const headers = new Headers(response.headers);
  for (const [name, value] of Object.entries(CORS)) headers.set(name, value);
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}



// ── signing in with Google ──────────────────────────────────────────────
// Optional, and off unless the app is configured for it. The point is a
// backup of your own recordings to your own Drive — NOT a way to share with
// family. Your sister's Drive is a different account and cannot see yours;
// that is what the code handoff above is for.
//
// The exchange happens here rather than in the browser because Google wants a
// client secret for a web client even with PKCE, and a secret in core.js is
// not a secret — core.js is served to everyone who opens the page.
//
// The scope asked for is drive.appdata: a private folder that belongs to this
// app, invisible in the person's own Drive, and no access whatsoever to any
// file they did not put there through us. Asking for anything wider to store
// our own backup would be helping ourselves to their documents.

const GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token";

function googleConfigured(env) {
  return !!(env.GOOGLE_CLIENT_ID && env.GOOGLE_CLIENT_SECRET);
}

async function googleExchange(request, env) {
  if (!googleConfigured(env)) return json(501, "google sign-in is not configured");
  let asked;
  try { asked = await request.json(); } catch { return json(400, "no code"); }

  const form = new URLSearchParams({
    client_id: env.GOOGLE_CLIENT_ID,
    client_secret: env.GOOGLE_CLIENT_SECRET,
    grant_type: "authorization_code",
    code: String(asked.code || ""),
    redirect_uri: String(asked.redirect_uri || ""),
    code_verifier: String(asked.code_verifier || ""),
  });

  const r = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: form,
  });
  const body = await r.text();
  // Passed through as-is. Rewriting Google's refusal into our own words would
  // hide which of a dozen setup mistakes it actually was.
  return new Response(body, { status: r.status, headers: { "content-type": "application/json" } });
}

async function googleRefresh(request, env) {
  if (!googleConfigured(env)) return json(501, "google sign-in is not configured");
  let asked;
  try { asked = await request.json(); } catch { return json(400, "no token"); }

  const form = new URLSearchParams({
    client_id: env.GOOGLE_CLIENT_ID,
    client_secret: env.GOOGLE_CLIENT_SECRET,
    grant_type: "refresh_token",
    refresh_token: String(asked.refresh_token || ""),
  });
  const r = await fetch(GOOGLE_TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: form,
  });
  return new Response(await r.text(), { status: r.status, headers: { "content-type": "application/json" } });
}

/** So the app can tell whether to offer sign-in at all. */
function googleStatus(env) {
  return new Response(JSON.stringify({
    configured: googleConfigured(env),
    clientId: env.GOOGLE_CLIENT_ID || "",
  }), { status: 200, headers: { "content-type": "application/json" } });
}

// ── handing someone to the family ───────────────────────────────────────
// The archive used to leave as a file you had to find, attach and send, and
// arrive as a file the other person had to find again. For a family that is
// three chances to lose her. This holds the same bytes for a day under a
// short code you can read down a phone.
//
// The worker never looks inside. It is the family's archive, not ours: it
// goes in as opaque bytes and comes out the same, and it expires whether or
// not anyone collects it.

/** No 0/O/1/I/L: this gets read aloud and written down. */
const CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
const CODE_LENGTH = 6;
const ARCHIVE_TTL_SECONDS = 24 * 60 * 60;
/** KV stops at 25 MiB. Leave room rather than fail at the very end of a
 *  long upload — the app falls back to the file when it hears this. */
const ARCHIVE_MAX_BYTES = 20 * 1024 * 1024;

function newCode() {
  const bytes = crypto.getRandomValues(new Uint8Array(CODE_LENGTH));
  let out = "";
  for (const b of bytes) out += CODE_ALPHABET[b % CODE_ALPHABET.length];
  return out;
}

const codeKey = code => "arch:" + code;

/** Read aloud, so accept it typed back in any case and with spaces in it. */
function tidyCode(raw) {
  const cleaned = String(raw || "").toUpperCase().replace(/[^A-Z0-9]/g, "");
  return cleaned.length === CODE_LENGTH &&
         [...cleaned].every(c => CODE_ALPHABET.includes(c)) ? cleaned : "";
}

async function putArchive(request, env) {
  const body = await request.text();
  if (!body) return json(400, "nothing to store");
  // Bytes, not characters: the archive is mostly base64 audio.
  const size = new TextEncoder().encode(body).length;
  if (size > ARCHIVE_MAX_BYTES) {
    return json(413, "archive too large to send by code");
  }
  try { JSON.parse(body); } catch { return json(400, "not an archive"); }

  // Three tries before giving up. A collision at 31^6 is remote, but silently
  // overwriting someone else's archive with yours would be unforgivable.
  for (let attempt = 0; attempt < 3; attempt++) {
    const code = newCode();
    if (await env.JADDATI.get(codeKey(code))) continue;
    await env.JADDATI.put(codeKey(code), body, { expirationTtl: ARCHIVE_TTL_SECONDS });
    return new Response(JSON.stringify({ code, hours: ARCHIVE_TTL_SECONDS / 3600 }),
                        { status: 200, headers: { "content-type": "application/json" } });
  }
  return json(503, "could not allocate a code");
}

async function takeArchive(request, env) {
  let asked;
  try { asked = await request.json(); } catch { return json(400, "no code"); }
  const code = tidyCode(asked && asked.code);
  if (!code) return json(400, "that is not a code");

  const stored = await env.JADDATI.get(codeKey(code));
  // Deliberately the same answer for "never existed" and "expired": the
  // difference is not useful to whoever is typing, and telling them which
  // would turn this into something worth guessing at.
  if (!stored) return json(404, "no archive for that code");

  // NOT deleted on collection. A family is more than two phones, and the
  // second person to try should not find it gone.
  return new Response(stored, { status: 200, headers: { "content-type": "application/json" } });
}

/**
 * Who has signed in. Behind its own token, which is a secret and not the app
 * token — the app token ships inside a web page, and a page anyone can read is
 * not a credential for anything that lists people.
 *
 * Returns the roll and the state of the voice slots, and nothing anyone said.
 */
async function adminAccounts(request, env) {
  const given = (request.headers.get("x-jaddati-admin") || "").trim();
  if (!env.ADMIN_TOKEN || given !== env.ADMIN_TOKEN) return json(401, "unauthorised");

  const allowance = num(env.CREDITS_PER_ACCOUNT, 1000);
  const listing = await env.JADDATI.list({ prefix: "acct:" });
  const accounts = [];
  for (const entry of listing.keys) {
    try {
      const record = JSON.parse(await env.JADDATI.get(entry.name));
      if (!record) continue;
      // `characters` is everything this account has ever spent; the meter that
      // actually refuses people is this month's. Standing in a room watching
      // the queue, the useful number is what is LEFT, so it is worked out here
      // rather than left to whoever is reading the screen.
      const used = num(await env.JADDATI.get(`used:acct:${record.sub}:${period()}`), 0);
      accounts.push({ ...record, usedThisMonth: used, leftThisMonth: Math.max(0, allowance - used) });
    } catch { /* one unreadable row must not cost the whole roll */ }
  }
  accounts.sort((a, b) => num(b.lastSeen, 0) - num(a.lastSeen, 0));

  const voices = await env.JADDATI.list({ prefix: "v:" });
  const held = [];
  for (const entry of voices.keys) {
    try {
      const record = JSON.parse(await env.JADDATI.get(entry.name));
      if (record) held.push({ account: record.account || "", lastUsed: num(record.lastUsed, 0) });
    } catch { /* same */ }
  }

  return new Response(JSON.stringify({
    accounts,
    voices: { held: held.length, cap: num(env.MAX_VOICES, 6), slots: held },
    creditsPerAccount: allowance,
    month: period(),
  }), { status: 200, headers: { "content-type": "application/json" } });
}

async function route(request, env) {
  const url = new URL(request.url);

  if (url.pathname === "/health") return new Response("ok");

  // Before the method gate AND before the app token. Its own credential,
  // because the app token is readable by anyone who opens the web build; and
  // above the gate because reading a roll is a GET, and the gate below turns
  // every GET into a 405 — which it did, silently, to the only caller this
  // endpoint has. The relay's own suite drove it with POST and never saw it.
  if (url.pathname === "/admin/accounts") return adminAccounts(request, env);

  // DELETE is allowed through for one route: removing a voice. The app has
  // to be able to answer "how do I get this deleted?", and refusing every
  // non-POST made that promise undeliverable on exactly the builds that go
  // through here.
  const isVoiceDelete =
    request.method === "DELETE" &&
    url.pathname.startsWith("/v1/voices/") &&
    url.pathname !== "/v1/voices/add";
  if (request.method !== "POST" && !isVoiceDelete) {
    return json(405, "method not allowed");
  }

  if (appToken(request) !== env.APP_TOKEN) return json(401, "unauthorised");
  if (!deviceId(request)) return json(400, "missing device identifier");

  if (isVoiceDelete) {
    const voiceId = url.pathname.slice("/v1/voices/".length);
    return voiceId ? deleteVoice(request, env, voiceId) : json(400, "no voice id");
  }

  if (url.pathname === "/google/status") return googleStatus(env);
  if (url.pathname === "/google/exchange") return googleExchange(request, env);
  if (url.pathname === "/google/refresh") return googleRefresh(request, env);

  if (url.pathname === "/archive") return putArchive(request, env);
  if (url.pathname === "/archive/fetch") return takeArchive(request, env);

  if (url.pathname === "/v1/voices/add") return createVoice(request, env);

  if (url.pathname.startsWith("/v1/text-to-speech/")) {
    const voiceId = url.pathname.slice("/v1/text-to-speech/".length);
    return voiceId ? speak(request, env, voiceId) : json(400, "no voice id");
  }

  if (url.pathname.endsWith("/chat/completions")) return groq(request, env, "/chat/completions");
  if (url.pathname.endsWith("/audio/transcriptions")) return groq(request, env, "/audio/transcriptions");

  return json(404, "no such endpoint");
}

export default {
  async fetch(request, env) {
    // The preflight answers before the token is checked, because a browser
    // sends it without one. Checking first would reject every real call behind
    // it, and the rejection would arrive in a shape the page cannot even read.
    if (request.method === "OPTIONS") return withCors(new Response(null, { status: 204 }));
    return withCors(await route(request, env));
  },

  /**
   * Nightly: delete shared voices past their week so the slots come back.
   * Without this the account fills up once and stays full.
   */
  async scheduled(event, env) {
    // No longer the mechanism — eviction is. This is the collector behind it:
    // a voice nobody has spoken with for a day is taking a slot that a person
    // in the room could be using, and its owner is not coming back for it
    // today. Anything newer is left alone, however many slots are in use,
    // because taking a voice from someone mid-session was the whole problem
    // with doing this on a timer.
    const idleFor = Math.max(voiceTTL(env), 24 * 3600) * 1000;
    const cutoff = Date.now() - idleFor;
    const listing = await env.JADDATI.list({ prefix: "v:" });

    for (const entry of listing.keys) {
      const record = await env.JADDATI.get(entry.name);
      if (!record) continue;
      let seen = 0, owner = "";
      try {
        const parsed = JSON.parse(record);
        seen = num(parsed.lastUsed, num(parsed.created, 0));
        owner = parsed.account || "";
      } catch { continue; }
      if (seen > cutoff) continue;

      const voiceId = entry.name.slice(2);
      // One voice the provider will not talk about must not stop the sweep:
      // an unhandled throw here used to abort the whole run, so nothing later
      // in the list was ever cleaned up.
      let gone;
      try {
        gone = await fetch(`${ELEVEN}/v1/voices/${voiceId}`, {
          method: "DELETE",
          headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
        });
      } catch { continue; }
      // 404 means it is already gone, which is the outcome we wanted anyway.
      if (gone.ok || gone.status === 404) {
        await env.JADDATI.delete(entry.name);
        // Lift the owner's lock in the same breath. Without this they are told
        // they already have a voice, for the ten minutes after it was removed.
        if (owner) await env.JADDATI.delete(`voice:acct:${owner}`);
      }
    }

    // Recount rather than adjust.
    //
    // `voices:live` was a read-modify-write with nothing serialising it and
    // nothing ever checking it, so every lost update leaked a slot PERMANENTLY.
    // A `v:` record expiring before a sweep saw it, or any throw inside this
    // loop, left the count above the truth for ever — and once it reached the
    // ceiling every visitor got "no slots are free" with no way back but
    // editing KV by hand. Counting what is actually there makes the number
    // self-correcting: at worst it is wrong until the next sweep.
    const after = await env.JADDATI.list({ prefix: "v:" });
    await env.JADDATI.put("voices:live", String(after.keys.length));
  },
};
