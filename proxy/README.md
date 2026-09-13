# Jaddati proxy

The app shipped with the ElevenLabs and Groq keys inside its own bundle. That
is survivable while the only phone running it is ours. It stops being
survivable on TestFlight: anyone holding the app holds the keys, and the cost
is not only credits — every voice a stranger clones takes a slot out of the
same account the demo depends on.

This moves the keys off the phone. The app authenticates with a token we can
rotate, and this worker meters what each device spends.

## What it enforces

| Rule | Default | Why |
|---|---|---|
| Characters of speech per device per month | **2500** | `CREDITS_PER_DEVICE` in `wrangler.toml`. Must be at least the app's own 2500-character limit for one generation, or a visitor is refused their first sentence and told the month is spent. There is also `CREDITS_PER_MONTH` across everyone — when THAT trips, speech stops for every visitor until the calendar month rolls, with no reset but editing KV by hand. |
| Voices per device | 1 | Cloning is the expensive, slot-consuming action. The lock is checked against the provider before it is honoured: if the voice it names is already gone, the lock is dropped rather than stranding the phone that made it. The refusal is worded so the client can tell it apart from the account being full — those have different remedies, and telling someone to go free up an account they do not own is the wrong instruction. |
| Shared voices alive at once | 6 | Keep it **below** the plan's real slot count so the demo always has room. |
| Shared voice lifetime | **10 minutes** | Set by `VOICE_TTL_MINUTES` in `wrangler.toml`, swept by a `*/10` cron — so a voice really lives 10–20 minutes depending where in the cycle it was made. Short on purpose: during a demonstration the account has to clear itself between people. A voice built the night before a demo will **not** be there in the morning. Change the variable, not this table, and redeploy. |

A failed generation is not charged. Only audio that actually arrived counts.

## Deploy

```
npm install -g wrangler
wrangler login
wrangler kv namespace create JADDATI      # paste the id into wrangler.toml
wrangler secret put ELEVENLABS_API_KEY
wrangler secret put LLM_API_KEY
wrangler secret put APP_TOKEN             # invent one; it goes in Secrets.plist
wrangler deploy
```

Check it answers: `curl https://jaddati-proxy.<subdomain>.workers.dev/health`

## Point the app at it

In `Jaddati/Secrets.plist` — still git-ignored, still never committed:

```xml
<key>ELEVENLABS_BASE_URL</key><string>https://jaddati-proxy.<subdomain>.workers.dev</string>
<key>ELEVENLABS_API_KEY</key><string>THE_APP_TOKEN</string>
<key>LLM_BASE_URL</key>       <string>https://jaddati-proxy.<subdomain>.workers.dev</string>
<key>LLM_API_KEY</key>        <string>THE_APP_TOKEN</string>
```

Leave `ELEVENLABS_BASE_URL` out entirely and the app talks to ElevenLabs
directly with a real key, exactly as before — which is what a local
development build should keep doing.

## What this does not fix

A token still ships in the bundle, because the app has to prove it is the app.
Someone determined can pull it out. The difference is that this token is ours
to revoke in thirty seconds and cannot spend more than one device's allowance,
where an ElevenLabs key inside a shipped build is permanent and uncapped.

The right end state is a sign-in, so an allowance belongs to a person rather
than to a phone. That is not a demo-week job.

## Deleting a voice

`DELETE /v1/voices/{id}` is the one non-POST route the worker accepts.

The app calls it when a person is removed, because the clone lives under this
account rather than the family's — without it, "how do I get this deleted?"
had no answer anyone could act on, and the app's own privacy notice would be
promising something it could not do.

Only the device that created a voice may delete it: the `voice:{device}` key is
the proof of ownership, and a mismatch is a 403. A voice already gone at the
provider counts as success. `voices:live` is decremented only when a `v:{id}`
record was actually removed, so a repeated delete cannot push the counter below
the true number of live voices.

**If you point a build at this worker, deploy this route with it.** An older
worker rejects every non-POST with a 405, and the app will then tell people
their voice could not be removed.
