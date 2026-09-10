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
| **The app compiles** | Clean build in Xcode against a physical iPhone, 10 Sep 2026, twice — before and after the review fixes. Commit `bfba2d7`. |
| The 13 review fixes compile | Same build. Compiling is not the same as behaving: each fix still needs exercising on the phone. |
| **The app installs and runs on the iPhone** | Screenshots from the device, 10 Sep 2026 16:50. Home, profile creation, person detail, and voice import all render and navigate. |
| **The app reaches ElevenLabs and is authenticated** | 10 Sep 2026 16:59, from the device. A text-to-speech request was accepted, authenticated with the key in `Secrets.plist`, and rejected only on the voice id: *"An invalid ID has been received: 'mock-voice-…'"* — the provider's own words, surfaced through the app's error mapping. Not a 401, so the key is valid. |
| The request shape for text-to-speech is correct | Same request. A malformed body would have failed differently. |
| The not-configured state gates correctly | On device: with no key the home screen shows "Voices are not set up on this build"; with offline test mode on, that panel disappears and the red test-mode banner replaces it. |
| **Voice cloning and Arabic speech work end to end** | 10 Sep 2026, on device: a real sample was uploaded, cloned, and the clone spoke Arabic in a recognisable version of the speaker's own voice. Screenshot on file. |
| The clone is recognisable as the speaker | Same run — judged by the speaker himself. |
| **The question model, chosen by measurement** | 10 Sep 2026, `spike/llm_spike.sh` against three candidates on the Groq key. `openai/gpt-oss-120b` wins: one sentence when asked for one, and Gulf wording in Arabic unprompted. `qwen/qwen3.8-27b` second. `allam-2-7b` rejected — its English physics was backwards and its Arabic wandered off the question. |
| **Answer latency is about 1 second** | Same run, all three models, English and Arabic. Fast enough to interrupt a story on stage. |
| **Arabic comes back readable** | Same run. Not a quality judgement on a real storybook question, but it is not garbled. |
| **`whisper-large-v3-turbo` is reachable on this key** | It is in the models list the spike printed. This is the model V1 measured at 16.5% median CER on Emirati dialect, so voice-to-text needs no second account. |
| **A model id in code would already have broken** | `llama-3.3-70b-versatile` was retired before it was ever called. The spike caught it on a laptop instead of on stage. This is the argument for keeping `LLM_MODEL` in Secrets.plist. |

## NOT verified — do not claim these

| Claim | Why not |
|---|---|

| **Emirati dialect** in the output | Tested and **failed**. An Emirati sample produced Egyptian-leaning Arabic and General American English. Instant cloning carries timbre, not accent. Say this plainly if a judge asks; do not promise dialect. |
| Generation latency | Unmeasured. The UI copy avoids promising a number. |
| The multipart field name is `files` rather than `files[]` | Taken from docs, never exercised. `spike/voice_spike.sh` tries `files` and falls back to `files[]` — run it to settle this. |
| The exact provider error strings the failure mapping matches | Guessed defensively from status codes; never observed live. |
| **`eleven_flash_v2_5` exists on this account** | Never called. It is what the "Faster, slightly plainer voice" toggle sends. An unavailable model id returns a 400 that looks nothing like a voice problem. **Do not touch that toggle on stage until one generation has succeeded with it.** |
| That a ~1 minute sample is enough for a convincing result | Provider's stated minimum, not our measurement. |
| The `speed` field is accepted by `voice_settings` | Taken from the API reference, sent but never observed succeeding. If it is rejected the call 400s — generate once after pulling this change, before the demo. |
| The Pace slider audibly slows new generations | Written, not exercised on device. |
| Playback rate slowing works on already-generated clips | `AVAudioPlayer.enableRate` is set before `prepareToPlay`; not yet driven from any control. |
| Profile photos import, shrink and persist across a reinstall | Written, not exercised on device. Photos are stored by filename, like audio, so the container UUID cannot break them — but that is reasoning, not a test. |
| The book Q&A flow end to end | Written, never run. Asking pauses the page, answers, speaks the answer, and resumes from the same second — none of that has been exercised on the phone. |

## The fastest way to move rows up

`bash spike/voice_spike.sh <your-sample.m4a>` settles most of the second table
in about a minute: it prints the models this account can reach, whether Arabic
is among them, which multipart field name works, the real latency, and produces
audio you can listen to.
