# Demo day — 16 September 2026

## Read this first — the voice does not survive the night

Voices created through the relay are **swept every ten minutes**. That was
asked for so three judges could each make their own without filling the
account, and it applies to your demo voice exactly as much as to theirs.

A voice built the night before **will not exist in the morning.** Two ways out,
and you have to pick one before Tuesday:

1. **Your demo phone uses your own ElevenLabs key.** `Secrets.plist` is
   gitignored, so your local copy can hold your real key while the committed
   configuration stays on the relay for anything shared. Your voice then lives
   at ElevenLabs untouched by the sweep, and the judges' phones still get the
   metered relay through the web version. This is the safer choice and it needs
   no code.
2. **Build the voice on the day**, minutes before you present, and do not let
   twenty minutes pass between building it and using it.

Option 1 unless you have a reason. Option 2 puts a network call on the critical
path of the morning.

---

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
6. **Ask about them.** Grounded answer, then the refusal. See below — this is
   the one to show if you only add one.
7. **Saved memories.** Show originals and recreated audio side by side, each badged. Turn on Airplane Mode and play one — offline replay works, new generation says so honestly.

## The five things that are new since the poster

Each is a separate screen on the person. Pick **two** for a longer slot — all
five is a feature tour, and a feature tour is what the other team is doing.

**Ask about them** — the strongest one to show, because of what it refuses.
Write a memory under *Words & memories* first ("She made maqluba every Friday").
Then ask "what did she cook on Fridays?" and let it answer. Then ask something
the notes do not cover — where she was born, say — and let the judges watch it
say it does not know. That refusal is the whole argument: the model is given the
family's notes as its only source and is never told whose voice will read the
answer out. Every other product in this category invents that answer warmly.

**Words that arrive later** — the one that lands emotionally. Seal a line for a
date years out. Show that the list gives the occasion and the date and never the
words. Nothing is generated until it is opened, so nothing is paid for either.

**One voice, the whole family** — the answer to "how is this more than a solo
app?", which is the question the theme invites. Export on one phone, import on
another, and the second phone speaks in the same voice immediately — no second
cloning, no second voice slot. Worth rehearsing with two devices if you have
them.

**Recorded before it is needed** — reframes the whole product from grief-tech to
something anyone should do this year. Six specific prompts, nothing leaves the
phone. One line is enough: "most families find they have nothing usable."

**Say it in their language** — strongest with this room. Her Arabic reaching a
grandchild who answers in English. The clip says it is a translation, not her
phrasing, and that honesty is worth pointing at.

---

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
- [ ] Profile shows **"Voice ready"** — not "This voice was made in test mode". A voice minted in test mode does not exist at ElevenLabs and every generation will fail.
- [ ] Leave **"Faster, slightly plainer voice"** alone unless you have already generated with it successfully. It sends a different model id, and if this account cannot reach that model the request fails in a way that has nothing to do with the voice.
- [ ] `Secrets.plist` present and whatever it holds actually works — generate one
      line to prove it. It now carries either the relay address and app token, or
      your own ElevenLabs key. Know which, and know why (see the top of this file).
- [ ] Check remaining credits at elevenlabs.io. Rehearsal eats them.
- [ ] **Use the rehearsal switch while practising.** Voice service screen, key
      icon on the home screen of the web version. Everything behaves as it does
      live, on the browser's own voice, reaching nothing — so twenty run-throughs
      cost no credits and no voice slots. Turn it off before you present, and
      check the DEMO MODE banner is gone.
- [ ] If the judges will scan the QR and try it themselves, each of their phones
      gets 1000 characters a month and there are six voice slots across everyone,
      recycling every ten minutes. Three judges is comfortable. A room is not.
- [ ] Write two or three memories under **Words & memories** before you present,
      or *Ask about them* has nothing to answer from and will only ever refuse.
- [ ] Demo profile created, voice built, at least one original recording imported.
- [ ] Two or three saved memories in the archive as the labelled fallback.
- [ ] Phone charged past 80%, Do Not Disturb **on**, auto-lock set to Never.
- [ ] Volume at maximum. Test through whatever the room actually has.
- [ ] Test the network in the room itself if you can get in. Hall wifi is not home wifi. Have a hotspot ready.
- [ ] Screen mirroring tested with the actual adapter and the actual cable.
- [ ] A backup demo video on the phone, in Photos, findable in five seconds.
