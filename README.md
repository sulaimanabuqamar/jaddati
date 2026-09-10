# Jaddati (جدّتي)

*A familiar voice, whenever you need it.*

Jaddati preserves the voice of someone who has died. You add a recording you
have the right to use, and the app can then speak new words in that voice —
words you type, a steadying line when you need one, or a story. Original
recordings and recreated audio are kept visibly separate everywhere in the app.

Built for Khalifa University's Smart Mobile Application Contest 2026,
undergraduate category, theme *AI for Stronger Family Bonds*.

---

## Status — read this first

This build was written in a single session and **has never been compiled or run.**
Expect a round of compiler errors on first open. Nothing in this repository
should be described as working until it has been built and used on the phone.

`docs/verified-vs-unverified.md` lists exactly what has evidence behind it and
what does not. Please keep it accurate — it is the difference between a defensible
project and an embarrassing one.

## Running it

1. Open `Jaddati.xcodeproj` in Xcode 16 or newer.
2. Select the `Jaddati` target → Signing & Capabilities → set **Team** to your
   Apple ID. Bundle identifier is `com.jaddati.Jaddati`; change it if it clashes.
3. Copy the secrets template and add the key:
   ```
   cp Jaddati/Secrets.example.plist Jaddati/Secrets.plist
   ```
   Open `Jaddati/Secrets.plist` and replace `PASTE_YOUR_KEY_HERE`.
   `Secrets.plist` is git-ignored and must never be committed.
4. Build to a physical iPhone. The app is portrait-only, iOS 17+.

Without a key the app still launches, still plays saved audio, and says plainly
that voices are not set up. It does not pretend to work.

## How it is put together

```
Jaddati/
  JaddatiApp.swift          entry point, two shared objects
  Design/Theme.swift        every colour, type ramp and shared control
  Models/Models.swift       Person, AudioAsset, FamilyNote, Intent
  Models/Library.swift      JSON index + audio files on disk
  Services/
    AppConfig.swift         key loading, model ids, hard limits
    VoiceService.swift      the protocol the app depends on
    ElevenLabsClient.swift  the only file that knows about ElevenLabs
    AudioPlayer.swift       AVAudioPlayer, real playback position
    Composer.swift          chooses the WORDS (local, deterministic)
  Features/                 one file per screen
```

Seven source directories, **zero third-party dependencies.** Every file can be
read start to finish in a few minutes.

### The AI boundary

| Runs where | What |
|---|---|
| ElevenLabs (cloud) | Voice cloning from an uploaded sample, and speech generation from new text. This is the AI capability the product rests on. |
| On the phone | Everything else — choosing words, storage, playback, all UI. |

Words are chosen locally and deterministically: affirmations come from a fixed
bank, a retelling is assembled only from sentences a family member actually
typed, and fiction comes from written templates that are always labelled as
invented. **The app never invents personal history and presents it as a real
memory.** A language model could sit behind `Composer` later without changing a
single view, and that rule would still have to hold.

### Storage

One JSON file for metadata, audio files beside it in Application Support.
Filenames are stored **relative** and resolved at read time — iOS gives the app
container a new UUID on every install, so an absolute path saved today is a
dangling path tomorrow.

## Known limitations

- **The key ships inside the app bundle.** It is not in source control, but a
  bundled key is a development shortcut, not a shipping design. The correct
  answer is a small server proxy holding the key and rate-limiting generation.
  `VoiceService` exists precisely so that proxy can be dropped in without
  touching a view. Say this plainly if asked — do not claim the key is secure.
- **Deleting a person does not delete the voice at ElevenLabs.** The app removes
  everything on the phone and says so in the confirmation dialog. Removing the
  provider-side voice is a manual step in the ElevenLabs account.
- **No test target.** Verification so far is manual.
- **Professional Voice Cloning is not usable for this product.** ElevenLabs only
  permits cloning your own voice at that tier and requires a verification
  recording from the speaker. Instant Voice Cloning is the only route, which is
  also the honest one — nobody has thirty minutes of studio audio of a
  grandparent. See the Q&A pack.
- Offline: saved audio plays, browsing works. Anything new needs a connection,
  and the app says which is which rather than failing silently.

## Licence and use of voices

Only upload recordings you have the right to use. For the contest demo the voice
is a consenting team member's own, recorded for the purpose and labelled as
such. This project does not claim that any provider has approved cloning the
voice of a person who has died; that question is unresolved and is discussed
openly in the Q&A pack.
