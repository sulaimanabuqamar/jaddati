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
 * ours to rotate, this worker counts what each device spends, and it deletes
 * shared voices after a week so slots come back.
 *
 * It deliberately MIMICS both upstream APIs path-for-path. The app's clients
 * were already written against a configurable base URL, so pointing them here
 * is a settings change rather than a rewrite.
 *
 *   POST /v1/voices/add                  -> ElevenLabs, capped per device
 *   POST /v1/text-to-speech/{voiceId}    -> ElevenLabs, billed against the device
 *   POST /chat/completions               -> Groq (questions while reading)
 *   POST /audio/transcriptions           -> Groq (speaking instead of typing)
 *   GET  /health                         -> plain OK, for checking a deploy
 *
 * One honest limit: the app still has to prove it is the app, so a token still
 * ships in the bundle. The difference from before is that this one is ours to
 * revoke in thirty seconds, and it cannot be used to spend more than one
 * device's allowance.
 */

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

// ---------------------------------------------------------------- routes

/**
 * Creating a voice. This is the call that can break demo day, so it is the
 * strictest: one voice per device, and a hard ceiling across everyone so the
 * account can never fill up completely.
 */
async function createVoice(request, env) {
  const device = deviceId(request);
  const perDevice = await env.JADDATI.get(`voice:${device}`);
  if (perDevice) {
    // Phrased to land on the app's existing "no free voice slots" message
    // rather than a raw status code.
    return json(429, "voice limit reached for this device");
  }

  const cap = num(env.MAX_VOICES, 6);
  const live = num(await env.JADDATI.get("voices:live"), 0);
  if (live >= cap) {
    return json(429, "voice limit reached: no slots are free right now");
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
      // The device's lock outlives the voice on purpose, and the sweep lifts it
      // the moment the voice is actually gone. Expiring the lock first would
      // let one person hold two voices at once; expiring it later, with no
      // sweep to lift it, would tell them they still have a voice that has
      // already been deleted. The TTLs here are only the safety net for a
      // sweep that never runs.
      await env.JADDATI.put(`voice:${device}`, voiceId, { expirationTtl: ttl * 2 });
      await env.JADDATI.put(
        `v:${voiceId}`,
        JSON.stringify({ device, created: Date.now() }),
        { expirationTtl: ttl * 3 }
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
 * Only the device that made a voice may delete it — the per-device key is the
 * proof. Without that check any phone could delete any family's voice, which
 * is a worse failure than not being able to delete at all.
 *
 * A voice that is already gone counts as success: the caller wanted it absent,
 * and it is. The counter only ever moves on a KV record we actually removed,
 * so a repeated delete cannot drive `voices:live` below the real number.
 */
async function deleteVoice(request, env, voiceId) {
  const device = deviceId(request);
  const owned = await env.JADDATI.get(`voice:${device}`);
  if (owned !== voiceId) return json(403, "not this device's voice");

  const gone = await fetch(`${ELEVEN}/v1/voices/${voiceId}`, {
    method: "DELETE",
    headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
  });
  if (!gone.ok && gone.status !== 404) {
    return json(gone.status, "the voice service refused the deletion");
  }

  const had = await env.JADDATI.get(`v:${voiceId}`);
  await env.JADDATI.delete(`v:${voiceId}`);
  await env.JADDATI.delete(`voice:${device}`);
  if (had) {
    const live = num(await env.JADDATI.get("voices:live"), 0);
    await env.JADDATI.put("voices:live", String(Math.max(live - 1, 0)));
  }

  return new Response(null, { status: 204 });
}

async function speak(request, env, voiceId) {
  const device = deviceId(request);
  const raw = await request.text();

  let text = "";
  try { text = String(JSON.parse(raw).text || ""); } catch { return json(400, "malformed request"); }
  if (!text) return json(400, "no text to speak");

  const allowance = num(env.CREDITS_PER_DEVICE, 500);
  const key = `used:${device}:${period()}`;
  const spent = num(await env.JADDATI.get(key), 0);

  if (spent + text.length > allowance) {
    const left = Math.max(allowance - spent, 0);
    // "credits" in the message is load-bearing: the app reads the wording and
    // shows its own translated "this month's credits are used up" line.
    return json(429, `credit allowance used for this month (${left} of ${allowance} left)`);
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
    await env.JADDATI.put(key, String(spent + text.length), { expirationTtl: 70 * 86400 });
  }

  return new Response(upstream.body, {
    status: upstream.status,
    headers: { "content-type": upstream.headers.get("content-type") || "audio/mpeg" },
  });
}

/** Groq, for questions during a story and for dictation. Cheap; not metered. */
async function groq(request, env, path) {
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
 * actually bounds the damage is the metering below: one voice per device, a
 * hard ceiling across everyone, and a monthly character budget.
 */
const CORS = {
  "access-control-allow-origin": "*",
  "access-control-allow-methods": "POST, DELETE, OPTIONS",
  "access-control-allow-headers": "xi-api-key, authorization, content-type, x-jaddati-device, accept",
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

async function route(request, env) {
  const url = new URL(request.url);

  if (url.pathname === "/health") return new Response("ok");

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
    const cutoff = Date.now() - voiceTTL(env) * 1000;
    const listing = await env.JADDATI.list({ prefix: "v:" });
    let live = num(await env.JADDATI.get("voices:live"), 0);

    for (const entry of listing.keys) {
      const record = await env.JADDATI.get(entry.name);
      if (!record) continue;
      let created = 0, owner = "";
      try {
        const parsed = JSON.parse(record);
        created = parsed.created || 0;
        owner = parsed.device || "";
      } catch { continue; }
      if (created > cutoff) continue;

      const voiceId = entry.name.slice(2);
      const gone = await fetch(`${ELEVEN}/v1/voices/${voiceId}`, {
        method: "DELETE",
        headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
      });
      // 404 means it is already gone, which is the outcome we wanted anyway.
      if (gone.ok || gone.status === 404) {
        await env.JADDATI.delete(entry.name);
        // Lift the owner's lock in the same breath. Without this they are told
        // they already have a voice, for the ten minutes after it was removed.
        if (owner) await env.JADDATI.delete(`voice:${owner}`);
        live = Math.max(live - 1, 0);
      }
    }
    await env.JADDATI.put("voices:live", String(live));
  },
};
