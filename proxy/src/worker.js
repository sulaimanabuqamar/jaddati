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
      const ttl = num(env.VOICE_TTL_DAYS, 7) * 86400;
      await env.JADDATI.put(`voice:${device}`, voiceId, { expirationTtl: ttl });
      await env.JADDATI.put(
        `v:${voiceId}`,
        JSON.stringify({ device, created: Date.now() }),
        { expirationTtl: ttl + 86400 }
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

export default {
  async fetch(request, env) {
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

    if (url.pathname === "/v1/voices/add") return createVoice(request, env);

    if (url.pathname.startsWith("/v1/text-to-speech/")) {
      const voiceId = url.pathname.slice("/v1/text-to-speech/".length);
      return voiceId ? speak(request, env, voiceId) : json(400, "no voice id");
    }

    if (url.pathname.endsWith("/chat/completions")) return groq(request, env, "/chat/completions");
    if (url.pathname.endsWith("/audio/transcriptions")) return groq(request, env, "/audio/transcriptions");

    return json(404, "no such endpoint");
  },

  /**
   * Nightly: delete shared voices past their week so the slots come back.
   * Without this the account fills up once and stays full.
   */
  async scheduled(event, env) {
    const ttl = num(env.VOICE_TTL_DAYS, 7) * 86400 * 1000;
    const cutoff = Date.now() - ttl;
    const listing = await env.JADDATI.list({ prefix: "v:" });
    let live = num(await env.JADDATI.get("voices:live"), 0);

    for (const entry of listing.keys) {
      const record = await env.JADDATI.get(entry.name);
      if (!record) continue;
      let created = 0;
      try { created = JSON.parse(record).created || 0; } catch { continue; }
      if (created > cutoff) continue;

      const voiceId = entry.name.slice(2);
      const gone = await fetch(`${ELEVEN}/v1/voices/${voiceId}`, {
        method: "DELETE",
        headers: { "xi-api-key": env.ELEVENLABS_API_KEY },
      });
      // 404 means it is already gone, which is the outcome we wanted anyway.
      if (gone.ok || gone.status === 404) {
        await env.JADDATI.delete(entry.name);
        live = Math.max(live - 1, 0);
      }
    }
    await env.JADDATI.put("voices:live", String(live));
  },
};
