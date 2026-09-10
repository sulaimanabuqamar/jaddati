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
