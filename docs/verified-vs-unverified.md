# What is actually verified

Kept honest deliberately. If you cannot point at evidence, it belongs in the
second table.

## Verified

| Claim | Evidence |
|---|---|
| ElevenLabs Professional Voice Cloning cannot clone a third party's voice | Official docs: "You can only create a Professional Voice Clone of your own voice. Even with their consent, you cannot clone someone else's voice." |
| Instant Voice Cloning needs ~1 minute of audio and a rights confirmation | Official ElevenLabs product guide, read 10 Sep 2026 |
| Free tier has no voice cloning; Starter is the cheapest tier that does | ElevenLabs pricing page, and the account itself |
| The account is on Starter with 40,000 credits, 0 used | Screenshot of the subscription page, 10 Sep 2026 |
| There is no automatic overage on this plan — credits are topped up manually | Same page: "You can still top up anytime" + a manual Add credits button |
| `eleven_multilingual_v2` supports Arabic (Saudi, UAE variants) | ElevenLabs models documentation |
| API shapes: `POST /v1/voices/add` (multipart `name`, `files`) returns `voice_id`; `POST /v1/text-to-speech/{voice_id}` takes `{text, model_id}` | ElevenLabs API reference, read 10 Sep 2026 |
| **The app compiles** | Clean build in Xcode against a physical iPhone, 10 Sep 2026, reported by Sulaiman. Only failure was an unset `DEVELOPMENT_TEAM`, now set. |

## NOT verified — do not claim these

| Claim | Why not |
|---|---|
| **The app runs on the iPhone** | Never installed. Launch it and confirm. |
| The 30 defects found in review are actually fixed | 13 were corrected in code on 10 Sep, verified only by static review — the app has not been rebuilt since. Rebuild before believing this line. |
| Any request from the app has reached ElevenLabs | Zero requests have been made from this code. |
| The cloned voice sounds recognisably like anyone | No sample has been uploaded yet. |
| Arabic output quality, or Emirati dialect quality | Untested. Do not promise dialect quality. |
| Generation latency | Unmeasured. The UI copy avoids promising a number. |
| The multipart field name is `files` rather than `files[]` | Taken from docs, never exercised. `spike/voice_spike.sh` tries `files` and falls back to `files[]` — run it to settle this. |
| The exact provider error strings the failure mapping matches | Guessed defensively from status codes; never observed live. |
| That a ~1 minute sample is enough for a convincing result | Provider's stated minimum, not our measurement. |

## The fastest way to move rows up

`bash spike/voice_spike.sh <your-sample.m4a>` settles most of the second table
in about a minute: it prints the models this account can reach, whether Arabic
is among them, which multipart field name works, the real latency, and produces
audio you can listen to.
