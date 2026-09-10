# Demo day — 16 September 2026

## Before anything else

**Offline test mode must be OFF.** It lives behind the ladybug icon on the home
screen and only exists in Debug builds. With it on, nothing reaches ElevenLabs
and the app plays a placeholder tone. A red banner says so on the home screen —
if you can see that banner, you are not demonstrating the product.

---

## The 30 seconds

Rehearse until it needs no thought. Have the profile already created and the
voice already built — cloning does not fit inside thirty seconds and does not
need to.

| Beat | What you do | What you say |
|---|---|---|
| 0–5s | Open Jaddati. The profile is already there. | "This is my grandmother's profile." |
| 5–10s | Tap an original recording. Let two or three seconds play. | "That's her actual voice. A recording the family already had." |
| 10–15s | Tap **Say something**. Type a short line the judges can see is new. | "Now I'm going to make her say something she never said." |
| 15–25s | Tap **Hear it in their voice**. Let it generate. | *Say nothing.* Let the wait be the wait. |
| 25–30s | The player opens and speaks. Point at the badge. | "AI-recreated voice. The app never lets you confuse the two." |

Suggested line — short, warm, unmistakably new:

> خذي وقتك يا حبيبتي، ما لازم تفهمين كل شي اليوم.
>
> *Take your time. You don't have to figure everything out today.*

**Ask a judge for a word to include.** It costs three seconds and removes any
suspicion that the audio was prepared. It is the single strongest thing you can
do in this demo, and it only works if generation is genuinely live.

### If it fails on stage

Say so plainly and move: *"That's the network, not the app — here's one I
generated earlier, and you can see it's labelled as cached."* Then play a saved
memory. Do not retry more than once. Do not present a saved clip as a live one.

---

## The full run, if you get longer

1. **The problem, in one sentence.** Someone dies and the voice goes first. People keep photographs; almost nobody keeps a voice.
2. **Add a voice.** Show the import screen and the consent wording. Do not skip past it — it is the most defensible thing in the build.
3. **Say something.** The money shot above.
4. **Comfort me.** Tap an affirmation, tap the Arabic line, generate. Shows the presets and the bilingual handling in one move.
5. **A memory, retold.** Add a memory in your own words, build the retelling, and point out the label. Then show what happens with no notes: the app refuses to invent one.
6. **Saved memories.** Show originals and recreated audio side by side, each badged. Turn on Airplane Mode and play one — offline replay works, new generation says so honestly.

## Speaking roles

Split it so all three speak. Judges notice one person doing everything.

- **Voice and product** — the pitch, the money shot, the consent story.
- **Engineering** — architecture, the AI boundary, storage, why no dependencies.
- **Testing and limits** — what was measured, what failed, what is still unknown.

The third role is the strongest one available and the easiest to underrate.
Being specific about what you have not proven is what separates a student project
from a serious one.

---

## Phone checklist — run this the night of the 15th

- [ ] **Rebuild from Xcode on the 15th.** Free provisioning expires seven days after signing. A build made on the 9th will not launch on the 16th.
- [ ] Launch the rebuilt app and play something. Building is not launching.
- [ ] Offline test mode **off**. No red banner on the home screen.
- [ ] `Secrets.plist` present and the key valid — generate one line to prove it.
- [ ] Check remaining credits at elevenlabs.io. Rehearsal eats them.
- [ ] Demo profile created, voice built, at least one original recording imported.
- [ ] Two or three saved memories in the archive as the labelled fallback.
- [ ] Phone charged past 80%, Do Not Disturb **on**, auto-lock set to Never.
- [ ] Volume at maximum. Test through whatever the room actually has.
- [ ] Test the network in the room itself if you can get in. Hall wifi is not home wifi. Have a hotspot ready.
- [ ] Screen mirroring tested with the actual adapter and the actual cable.
- [ ] A backup demo video on the phone, in Photos, findable in five seconds.
