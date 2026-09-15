// The relay's own logic, without Cloudflare.
//
// Everything interesting the worker does now — who may spend, what it costs,
// and which voice loses its slot when a seventh person arrives — is decided
// before any upstream call, so it can be driven with a fake KV and a fake
// fetch. That matters here because none of it can be tried in production
// before demo day without spending real credits on a real account.
//
//   node proxy/test-relay.mjs

import worker from "./src/worker.js";

const problems = [];
const log = (ok, what, extra = "") => {
  console.log(`${ok ? "PASS" : "FAIL"}  ${what}${extra ? "  — " + extra : ""}`);
  if (!ok) problems.push(what);
};

// ── a KV that behaves like the real one for the parts we use ────────────
function makeKV(seed = {}) {
  const store = new Map(Object.entries(seed));
  return {
    store,
    async get(key) { return store.has(key) ? store.get(key) : null; },
    async put(key, value) { store.set(key, String(value)); },
    async delete(key) { store.delete(key); },
    async list({ prefix = "" } = {}) {
      return { keys: [...store.keys()].filter(k => k.startsWith(prefix)).map(name => ({ name })) };
    },
  };
}

const ENV = kv => ({
  JADDATI: kv,
  APP_TOKEN: "app-token",
  ADMIN_TOKEN: "admin-token",
  ELEVENLABS_API_KEY: "sk-upstream",
  LLM_BASE_URL: "https://llm.example",
  LLM_API_KEY: "gsk-upstream",
  GOOGLE_CLIENT_ID: "web.apps.googleusercontent.com",
  GOOGLE_IOS_CLIENT_ID: "ios.apps.googleusercontent.com",
  GOOGLE_CLIENT_SECRET: "shh",
  MAX_VOICES: "2",            // small, so eviction is reachable in a test
  CREDITS_PER_ACCOUNT: "100",
  CREDITS_PER_MONTH: "100000",
});

// ── a fetch that never leaves the process ───────────────────────────────
let upstream = [];
const TOKENS = {
  "tok-amal": { sub: "amal", email: "amal@example.com", aud: "web.apps.googleusercontent.com" },
  "tok-bilal": { sub: "bilal", email: "bilal@example.com", aud: "ios.apps.googleusercontent.com" },
  "tok-carol": { sub: "carol", email: "carol@example.com", aud: "web.apps.googleusercontent.com" },
  "tok-wrong-aud": { sub: "mallory", email: "m@example.com", aud: "somebody-elses-client-id" },
};
globalThis.fetch = async (url, init = {}) => {
  const href = String(url);
  upstream.push({ href, method: init.method || "GET" });
  if (href.startsWith("https://oauth2.googleapis.com/tokeninfo")) {
    const token = decodeURIComponent(href.split("id_token=")[1] || "");
    const claims = TOKENS[token];
    if (!claims) return new Response("no", { status: 400 });
    return Response.json({ ...claims, exp: Math.floor(Date.now() / 1000) + 3600 });
  }
  if (href.includes("/v1/voices/add")) return Response.json({ voice_id: "v-" + (upstream.length) });
  if (href.includes("/v1/text-to-speech/")) return new Response("audiobytes", { status: 200, headers: { "content-type": "audio/mpeg" } });
  if (/\/v1\/voices\/[^/]+$/.test(href)) return new Response(null, { status: init.method === "DELETE" ? 204 : 200 });
  return new Response("{}", { status: 200 });
};

const call = (kv, path, { token, admin, body = {}, method = "POST", device = "device-aaaaaaaa" } = {}) => {
  const headers = { "content-type": "application/json", "x-jaddati-device": device, "xi-api-key": "app-token" };
  if (token) headers["x-jaddati-account"] = token;
  if (admin) headers["x-jaddati-admin"] = admin;
  return worker.fetch(new Request("https://relay.example" + path, {
    method, headers, body: method === "POST" ? JSON.stringify(body) : undefined,
  }), ENV(kv));
};

const say = (kv, token, text, voice = "v-1") =>
  call(kv, "/v1/text-to-speech/" + voice, { token, body: { text } });

// ── signing in is required to spend, and not to look ────────────────────
{
  const kv = makeKV();
  const anon = await say(kv, null, "hello");
  log(anon.status === 401, "speaking without an account is refused", String(anon.status));

  const forged = await say(kv, "tok-wrong-aud", "hello");
  log(forged.status === 401, "a token minted for someone else's client id is refused",
      String(forged.status));

  const ok = await say(kv, "tok-amal", "hello");
  log(ok.status === 200, "a verified account may speak", String(ok.status));
  log(kv.store.has("acct:amal"), "and the account is written to the roll");
}

// ── signing in is enough to appear on the roll ──────────────────────────
// The page is called "who has signed in". It used to record only the accounts
// that had GENERATED, so somebody who signed in and made a voice — or signed
// in and stopped — was missing from the one page that claims to list them.
{
  const kv = makeKV({ "voices:live": "0" });
  await call(kv, "/v1/voices/add", { token: "tok-carol" });
  const row = JSON.parse(kv.store.get("acct:carol") || "null");
  log(!!row, "making a voice puts the account on the roll, without speaking");
  log(!!row && row.generations === 0 && row.characters === 0,
      "and nothing is counted against it yet",
      row && `${row.generations} clips, ${row.characters} characters`);
  log(!!row && !!row.firstSeen && !!row.lastSeen, "with when it was first and last seen");
}

// Even a refusal leaves them on the roll: they signed in, which is what the
// page is about.
{
  const kv = makeKV();
  const r = await say(kv, "tok-bilal", "fuck this");
  log(r.status === 400, "a refused word is still a 400", String(r.status));
  log(kv.store.has("acct:bilal"), "and the person who typed it is still on the roll");
}

// ── the token is verified once, not once per sentence ───────────────────
{
  const kv = makeKV();
  upstream = [];
  await say(kv, "tok-amal", "one");
  await say(kv, "tok-amal", "two");
  await say(kv, "tok-amal", "three");
  const checks = upstream.filter(u => u.href.includes("tokeninfo")).length;
  log(checks === 1, "the id token is verified once and then cached", checks + " upstream checks");
}

// ── credits belong to the account ───────────────────────────────────────
{
  const kv = makeKV();
  const first = await say(kv, "tok-amal", "x".repeat(80));
  log(first.status === 200, "80 characters of a 100 allowance goes through");
  const second = await say(kv, "tok-amal", "x".repeat(80));
  log(second.status === 429, "the next 80 does not", String(second.status));
  const other = await say(kv, "tok-bilal", "x".repeat(80));
  log(other.status === 200, "and a different account still has its own allowance",
      String(other.status));
}

// ── the app's own punctuation is not charged to anyone ───────────────────
{
  const kv = makeKV();
  await say(kv, "tok-amal", 'ab<break time="0.9s" />cd');
  const spent = Number(kv.store.get([...kv.store.keys()].find(k => k.startsWith("used:acct:amal"))));
  log(spent === 4, "break tags are sent but not billed", spent + " charged for 4 letters");
}

// ── refused words never reach the voice service ─────────────────────────
{
  const kv = makeKV();
  upstream = [];
  const r = await say(kv, "tok-amal", "fuck this");
  log(r.status === 400, "a refused word is a 400", String(r.status));
  log(!upstream.some(u => u.href.includes("text-to-speech")),
      "and nothing was sent upstream for it");
}

// ── slots: the seventh person takes the quietest voice, not a live one ──
{
  const kv = makeKV({
    "voices:live": "2",
    "v:v-old": JSON.stringify({ account: "amal", created: 1000, lastUsed: 1000 }),
    "v:v-busy": JSON.stringify({ account: "bilal", created: 2000, lastUsed: 9_000_000_000 }),
    "voice:acct:amal": "v-old",
    "voice:acct:bilal": "v-busy",
  });
  const made = await call(kv, "/v1/voices/add", { token: "tok-carol" });
  log(made.status === 200, "at the cap, a new voice is still made", String(made.status));
  log(!kv.store.has("v:v-old"), "the least recently used voice lost its slot");
  log(kv.store.has("v:v-busy"), "and the one in active use kept it");
  log(!kv.store.has("voice:acct:amal"), "the evicted account's lock was lifted with it");
}

// ── one voice per account, not per device ───────────────────────────────
{
  const kv = makeKV({ "voices:live": "0" });
  const first = await call(kv, "/v1/voices/add", { token: "tok-amal", device: "phone-aaaaaaa" });
  log(first.status === 200, "an account may make a voice");
  const again = await call(kv, "/v1/voices/add", { token: "tok-amal", device: "laptop-bbbbbbb" });
  log(again.status === 429, "and not a second one from another device", String(again.status));
}

// ── the roll ────────────────────────────────────────────────────────────
{
  const kv = makeKV();
  await say(kv, "tok-amal", "hello there");
  await say(kv, "tok-bilal", "hi");

  // GET, not POST. The first version of this test drove the roll with POST
  // because that is what the helper defaults to, and the roll passed every
  // check while being completely unreachable from a browser: the method gate
  // above it turned every GET into a 405, and the only caller this endpoint
  // has reads it with GET.
  const roll = (admin) => call(kv, "/admin/accounts", { admin, method: "GET" });

  const shut = await roll();
  log(shut.status === 401, "the admin roll refuses a caller with no admin token", String(shut.status));

  const wrong = await roll("guess");
  log(wrong.status === 401, "and a wrong one", String(wrong.status));

  const open = await roll("admin-token");
  log(open.status === 200, "and answers the right one, to a GET", String(open.status));
  const seen = await open.json();
  log(seen.accounts.length === 2, "both accounts are listed", String(seen.accounts.length));
  log(seen.accounts.every(a => a.email && a.sub), "with who they are");
  log(seen.accounts.every(a => !("text" in a) && !("words" in a)),
      "and nothing about what anyone said");

  // What is left, not only what was spent: "82 used" means nothing to someone
  // watching a queue unless they also know the allowance by heart.
  const amal = seen.accounts.find(a => a.sub === "amal");
  log(!!amal && amal.usedThisMonth === 11, "each row carries this month's spend",
      amal && String(amal.usedThisMonth));
  log(!!amal && amal.leftThisMonth === 89, "and what is left of the allowance",
      amal && String(amal.leftThisMonth));
  log(seen.voices.cap === 2 && typeof seen.voices.held === "number",
      "and the roll says how many voice slots are in use against the cap");
}

// ── the provider is full even though our own counter says it is not ─────
//
// The counter drifts: voices made before any of this existed, voices made by
// hand in the dashboard, an add that succeeded while the put after it failed.
// Every time it drifts low the relay forwards a request the account cannot
// serve, and somebody demonstrating the app is told to go and upgrade a
// subscription they do not own. Nobody should ever see that sentence.
{
  const kv = makeKV({ "voices:live": "0" });        // we think the account is empty
  const real = [];                                  // the provider knows it is full
  for (let i = 1; i <= 10; i++) {
    real.push({ voice_id: "old-" + i, category: "cloned", created_at_unix: 1000 + i });
  }

  const plain = globalThis.fetch;
  let adds = 0;
  const deleted = [];
  globalThis.fetch = async (url, init = {}) => {
    const href = String(url);
    if (href.includes("/v1/voices/add")) {
      adds += 1;
      if (adds === 1) {
        return new Response(JSON.stringify({
          detail: { message: "You have reached your maximum amount of custom voices (10 / 10)." },
        }), { status: 400 });
      }
      return Response.json({ voice_id: "v-new" });
    }
    if (href.endsWith("/v1/voices")) return Response.json({ voices: real });
    if (/\/v1\/voices\/[^/]+$/.test(href) && init.method === "DELETE") {
      deleted.push(href.split("/").pop());
      return new Response(null, { status: 204 });
    }
    return plain(url, init);
  };

  const made = await call(kv, "/v1/voices/add", { token: "tok-amal" });
  globalThis.fetch = plain;

  log(made.status === 200, "a full account frees a slot and the voice is still made",
      String(made.status));
  log(adds === 2, "the add was tried exactly once more, not in a loop", adds + " attempts");
  log(deleted.length === 1 && deleted[0] === "old-1",
      "and what it gave back was the oldest voice nobody here is holding",
      deleted.join(",") || "nothing");
  log(kv.store.get("voices:live") === "10",
      "the drifted counter is repaired from the provider's own list",
      kv.store.get("voices:live"));
}

console.log(problems.length
  ? `\n${problems.length} failed:\n  ` + problems.join("\n  ")
  : "\nall relay checks passed");
process.exit(problems.length ? 1 : 0);
