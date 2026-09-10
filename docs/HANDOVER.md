# Handover — 10 September 2026

## What exists

A complete SwiftUI app, written but never compiled. 15 Swift files, no
third-party dependencies, iOS 17+, portrait, iPhone only.

Screens: Home → Person → Add voice (import + consent) → Create (four intents) →
Player → Saved memories. Loading, empty and error states are built in, not
deferred. Original recordings and generated audio carry a visible source badge
everywhere they appear.

## Your first four steps, in order

**1. Open it and fix the compiler errors.**
```
open "Jaddati.xcodeproj"
```
It was written without a Swift toolchain, so expect errors. They will be small —
a wrong argument label, a missing import — not structural.

If the project will not open at all, the `.xcodeproj` was hand-written and uses
the Xcode 16 synchronised-folder format. Fall back: File → New → Project → iOS
App named `Jaddati`, then drag the `Jaddati/` source folder in. Three minutes,
and nothing else changes.

**2. Add the key.**
```
cp Jaddati/Secrets.example.plist Jaddati/Secrets.plist
```
Then paste the key into it. It is git-ignored.

**3. Run the spike** to settle what the docs cannot tell us — real latency, real
Arabic quality, which multipart field name the API actually wants:
```
bash spike/voice_spike.sh /path/to/your_sample.m4a
```

**4. Build to the iPhone** and work the failure list in `CONTRIBUTIONS.md`.

## Committing

Nothing has been committed — that is yours alone. When you are ready:

```
git add -A && git commit -m "Jaddati: SwiftUI app skeleton, voice pipeline, and docs

Complete app structure with no third-party dependencies: design system,
JSON-backed local storage with relative audio paths, ElevenLabs client behind a
VoiceService protocol, AVAudioPlayer with real playback position, and the four
listening experiences.

Not yet compiled or run on device. docs/verified-vs-unverified.md records what
has evidence and what does not."
```

## The one thing that would sink this

Describing any of it as working before it has run. `docs/verified-vs-unverified.md`
is the current truth. Move rows from the second table to the first only when you
have watched it happen.


---

# Second session — 10 September, evening

The app built successfully, then went through an adversarial code review that
found **30 defects**. Thirteen were fixed in code. Nothing has been rebuilt
since, so treat this whole section as unverified until it compiles.

## Fixed — the ones that would have shown on stage

1. **The listening screen paused instead of playing.** `onAppear` called the
   play/pause toggle, so opening a clip that was already playing silenced it.
   Added `AudioPlayer.ensurePlaying`, which never pauses.
2. **A corrupt index was overwritten with an empty one**, orphaning every audio
   file permanently and clearing the warning as it did so. The bad file is now
   moved to `library.corrupt-<timestamp>.json` before anything is written.
3. **`requires_verification` was ignored.** The provider can return a voice id
   that cannot speak; the app said "Voice ready" and every generation then
   failed. Now stored on the profile, with its own screen state.
4. **"Out of credits" was reported as "bad key."** ElevenLabs returns credit
   exhaustion as a 401, which short-circuited to `.unauthorised`. Quota and
   voice-slot detection now run before the status switch.
5. **Provenance was a property of the screen, not the audio.** Opening "A memory,
   retold" and typing something new got a "retold from your family's memories"
   label, and a fiction clip lost its disclaimer as soon as you replayed it from
   the archive. The label is now stored with the asset, and the family claim is
   only made when the family's words are what is actually being spoken.
6. **Re-importing silently created a second clone** and orphaned the first,
   burning a voice slot each time with no warning. The button now says Replace
   and the screen says what it costs.
7. **20 filesystem stats per row per 50ms during playback**, plus two unused
   `@EnvironmentObject`s forcing whole-screen rebuilds at 20Hz — visible jank
   during the demo moment.
8. Retelling silently kept only the four **oldest** notes while claiming to be
   the family's complete words.
9. Nested Button inside a NavigationLink label; hardcoded light palette with no
   `preferredColorScheme`; temp files leaked on every abandoned import; "Try
   again" that only cleared the banner; unreachable Save button; Arabic
   affirmations that could be read but not selected; `detail` arrays unparsed;
   a URLSession per request; and a NaN scrub guard.

## New

- **`MockVoiceService`** (Debug only) — exercise the entire app with no API key
  and no voice sample. Toggle it from the ladybug icon on the home screen. It
  plays an obvious tone, never speech, and a red banner shows while it is on.
  Type "fail" in any text to exercise the error path.
- **`JaddatiTests/`** — 13 tests over storage, provenance, voice readiness,
  legacy index decoding, and error wording. **Not yet wired into the project.**
- **`docs/demo-script.md`** — the 30-second beats, the full run, speaking roles,
  and the night-of checklist.

## Two manual steps I did not do for you

Both touch the Xcode project, and I would not risk your working build while you
were away.

**1. Wire up the tests** (2 minutes): File → New → Target → **Unit Testing
Bundle**, name it `JaddatiTests`. Delete the placeholder file Xcode creates, then
drag `JaddatiTests/JaddatiTests.swift` into the new target. ⌘U runs them.

**2. Background audio** (20 seconds): target → Signing & Capabilities → **+
Capability** → Background Modes → tick **Audio, AirPlay, and Picture in
Picture**. Without it, audio stops the moment the app is backgrounded.

## First command when you're back

```
open "Jaddati.xcodeproj"
```
Then ⌘B. If it fails, send me the errors. If you want the previous state back at
any point, `git checkout .` returns you to your commit — nothing tonight was
committed.
