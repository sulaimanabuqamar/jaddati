# Judge Q&A pack

Answer notes, not scripts. Say them in your own words — a memorised paragraph is
obvious from the front row, and the follow-up question will expose it.

---

### 1. "Is this just text-to-speech with a family theme?"

No. Ordinary TTS gives you a stock voice reading your words. This clones a
specific person's voice from a recording the family already has, and speaks new
words in *that* voice. The distinction is the whole product: nobody grieves a
stock voice.

Concretely: we upload a sample to ElevenLabs, get back a voice identifier, and
every later generation is bound to that identifier. Two different people give
two different voices from the same typed sentence.

---

### 2. "Whose voice is in the demo, and did you have permission?"

It is a team member's own voice, recorded for this purpose, and it is labelled in
the app as an AI-recreated voice.

Then be straight about the harder half: for a person who has died, the right to
use their voice sits with their family or estate, and the rules differ by
country. ElevenLabs puts that obligation on whoever uploads. **We do not claim
any provider has approved cloning a deceased person's voice.** It is an
unresolved constraint of the product, and the app says so on the upload screen
rather than hiding it behind a checkbox.

This is a strength if you say it first and a wound if a judge finds it.

---

### 3. "Why Instant Voice Cloning and not the professional tier?"

Two reasons, and lead with the second.

Mechanically: ElevenLabs only allows a Professional Voice Clone of *your own*
voice, and requires a verification recording from the speaker. For someone who
has died that is impossible.

More importantly, it would misrepresent our own product. The premise is a
ninety-second voice note from someone who is gone. Nobody has thirty minutes of
studio-clean audio of their grandmother. Instant cloning is what a real family
would actually have, so demoing on anything else would be demoing a product that
does not exist.

---

### 4. "How do you stop it inventing memories?"

By not letting a model write them. Affirmations come from a fixed written bank.
A retelling is assembled only from sentences a family member typed into the app —
if there are no notes, there is no retelling, and the screen says so instead of
producing something plausible. Fiction comes from written templates and is
labelled as invented on the player.

That is a deliberate design constraint, not a limitation we ran into. A fluent,
specific, completely fabricated family memory is the worst possible failure for
this product, so the architecture makes it impossible rather than unlikely.

---

### 5. "Where is your API key?"

Not in the repository — it is in a git-ignored `Secrets.plist`. Be honest about
the rest: it is bundled into the app, which is a development shortcut, not a
shipping design. The correct answer is a small server proxy that holds the key
and rate-limits generation, and the app already talks to a `VoiceService`
protocol so that proxy drops in without touching a screen.

We also cap generation length and allow one request at a time, because the real
cost risk is a loop, not a single call.

---

### Questions to be ready for that have no answer yet

Do not bluff these. "We haven't measured that yet" is a survivable answer;
a confident wrong number is not.

- How long does a generation take? — **measure it, then fill this in**
- How good is the Arabic, and does it handle Emirati dialect? — **untested**
- What does it cost per generation? — Starter is $6 for 40,000 credits, roughly
  one credit per character. Work out the per-sentence figure once you have run it.
- What happens if the network drops mid-generation? — the app keeps your text and
  offers a retry; confirm on device before saying so.
