# App Store submission pack

Everything App Store Connect asks for, written out. Last updated 11 September 2026.

The research behind each decision is in `app-review-research.md`. Where Apple's
own documentation does not answer a question, this file says so rather than
guessing — those are the places to be careful.

---

## 1. Review notes — paste into "App Review Information → Notes"

> Jaddati keeps the voice of a family member who has died. You upload a
> recording you have the right to use, the app creates a voice from it, and
> you can then hear new words spoken in that voice — typed text, or the pages
> of a children's book, with a child able to stop and ask a question that is
> answered aloud in the same voice.
>
> HOW TO TEST WITHOUT A REAL RECORDING
> You do not need audio of anyone. The app can record the sample itself:
> 1. Open the app. The first screen asks about data leaving the phone. Tap
>    "Allow these three things".
> 2. Tap "Add someone", give any name and relationship, Save.
> 3. Tap "Add their voice", then "Record now". Read anything aloud for about
>    60 seconds — your own voice is fine and is the fastest way through.
> 4. Confirm the two checkboxes and tap "Create voice". It takes a few seconds.
> 5. Type a sentence and tap Speak. You will hear it in the recorded voice.
> To see the app with nothing leaving the device, delete and reinstall, and
> choose "Not now — keep everything on this phone" on the first screen.
>
> DATA SENT TO THIRD-PARTY AI — guideline 5.1.2(i)
> The app sends data to two third-party services, and to nothing else:
> · ElevenLabs — receives the audio recording you choose and the text you want
>   spoken. It builds the voice and returns the speech.
> · Groq — receives a question and the text of the book page it is about, and
>   the audio when the user dictates instead of typing. It returns a short
>   answer and a transcript.
> Nothing is sent to either until the user accepts the screen that opens the
> app. That screen names both companies, states what each receives and what
> each does with it, and cannot be dismissed without answering. It is shown
> whenever no answer has been recorded — there is no first-launch flag or
> build condition that could hide it from you. Declining is a full answer: the
> app opens and works, and only the three networked features are switched off.
> Every network call also checks the stored answer at call time, so the
> features cannot run if the answer is no.
>
> The user can withdraw at any time from "Privacy and data" on the home
> screen, which also contains the full privacy notice in the app, in English
> and Arabic. Policy: https://sulaimanabuqamar.github.io/jaddati/privacy/
>
> VOICES OF PEOPLE WHO HAVE DIED — guidelines 5.1.1(viii) and 5.2.2
> Before a voice is created the user must separately confirm (a) that they
> hold the right to use the recording and to create speech in that voice, and
> (b) that they understand the output is machine-generated audio, not a
> recording of words the person said. Both are required; neither is pre-ticked.
> The app states plainly that it cannot verify the authorisation. This carries
> ElevenLabs' own consent requirement through to the person uploading, which
> is what their Prohibited Use Policy requires of us.
>
> Removing a person deletes the cloned voice from ElevenLabs first, and stops
> if that fails rather than orphaning it. There is also a reporting address on
> the support page for voices created without the right to do so.
>
> NO USER-GENERATED CONTENT IN THE SENSE OF GUIDELINE 1.2
> There are no accounts, no server of ours, no sharing, no feed, no messaging,
> and no way for one user to see anything another user created. Audio never
> leaves the device except to the two services above, for the user's own
> request. Nothing is distributed to anyone, so the moderation obligations in
> 1.2 have nothing to attach to.
>
> WHAT IS ON THE DEVICE
> Recordings, generated clips, names, relationships and photos are stored in
> the app's own container. There is no account and no database of ours
> anywhere. Deleting the app removes all of it.
>
> NOT A MEDICAL OR THERAPEUTIC APP
> Jaddati makes no claim to treat grief and is not marketed as therapy,
> counselling or any clinical tool. The support page says so explicitly.
>
> The app is English and Arabic. Arabic is a complete right-to-left interface,
> switchable from the globe on every screen including the first one.
>
> Contact: sulaiman.abuqamar@gmail.com

---

## 2. App Privacy — the nutrition label

Answer these in App Store Connect → App Privacy. Apple's definition of
"collect" is transmitting data off the device in a way that you **or your
third-party partners** can access for longer than is needed to service the
request in real time.

> **Before answering, check one thing.** Whether Audio Data must be declared
> at all depends on whether ElevenLabs and Groq retain what they are sent.
> A cloned voice is unambiguously retained at ElevenLabs — it persists under
> the account until deleted — so Audio Data is declared below on that basis
> and that is the safe answer. Verify the retention terms on both accounts
> before you file, and keep the answer at least as broad as what you find.

| Data type | Collected | Linked to identity | Used for tracking | Purpose |
|---|---|---|---|---|
| **Audio Data** (User Content) | Yes | No | No | App Functionality |
| **Other User Content** (typed text, questions) | Yes | No | No | App Functionality |
| **Device ID** (Identifiers) | Yes | No | No | App Functionality |
| Everything else | No | — | — | — |

Notes for each:
- **Audio Data** — the voice sample to ElevenLabs, dictated audio to Groq.
- **Other User Content** — the text to be spoken, and questions about a page.
- **Device ID** — Apple's identifier for vendor, sent only when the app is
  configured to reach the services through our own relay, to stop one phone
  exhausting a shared allowance. It is *not* sent when the app calls
  ElevenLabs and Groq directly. Declare it: the shipping configuration is
  intended to use the relay.
- **Not Linked**: there are no accounts, so nothing is tied to an identity.
- **Tracking: No** everywhere. Do not implement App Tracking Transparency —
  identifier for vendor used this way is explicitly not tracking under Apple's
  own definition, and there is no advertising identifier and no data broker.

The privacy manifest in the binary (`Jaddati/PrivacyInfo.xcprivacy`) already
matches this table, and declares two required-reason APIs: `UserDefaults`
(CA92.1) and file timestamps (C617.1, for the file-metadata read in
`VoiceRecorder`).

---

## 3. Age rating

Answer the questionnaire honestly and let App Store Connect compute the tier —
a rating set by hand against the answers is itself a rejection ground.

| Question | Answer | Why |
|---|---|---|
| User-Generated Content | **None** | Apple defines this as *broad distribution* of user content. Nothing here is distributed to anyone. |
| Messaging and Chat | None | No messaging of any kind. |
| Unrestricted Web Access | None | The app opens no browser. |
| Advertising | None | None in the app. |
| Medical/Treatment Information | **None** | No guidance on managing any condition. Keep it that way — do not describe the app as helping with grief. |
| Health or Wellness Topics | **Infrequent** | Death and remembrance are the subject matter. |
| Horror/Fear Themes | **None** | The tone is a family keepsake, not a séance. Keep the listing free of "speak to the dead" framing, which would invite this descriptor. |
| Violence, Sexuality, Profanity, Chance-Based | None | — |

Expect **4+ or 9+**. The two closest comparable apps on the store today are
both rated 9+. If it lands at 9+, that is fine and expected.

**Do not put this in the Kids Category.** Kids Category apps may not send any
personal or device information to third parties, which this app does by
design. That is an automatic rejection, not a judgement call.

**Category:** Lifestyle (primary). This matches the comparable apps.

---

## 4. Listing copy

**Name** (30 char max): `Jaddati`
**Subtitle** (30 char max): `Voices, carefully kept.`

**Promotional text**
> Keep the recordings you have of someone you have lost, and hear new words in
> a recreation of their voice.

**Description**
> Jaddati keeps the voice of someone who is gone.
>
> Add the person. Give Jaddati a recording you have the right to use — a voice
> message, an old video, or a minute recorded on the spot. Jaddati builds a
> voice from it, and from then on you can hear new words in that voice.
>
> Type a sentence and hear it read. Bring a children's book and have it read a
> page at a time, in the voice of the person who used to read it — and when a
> child stops to ask what a word means, the answer comes back in the same
> voice, then the story picks up where it stopped.
>
> WHAT JADDATI ASKS OF YOU
> Only upload a recording you have the right to use. Where the person has
> died, that means you are family, or someone otherwise entitled to give that
> permission. Jaddati cannot check this and does not pretend to. And what
> comes out is new audio made by a machine — never something the person
> actually said. Jaddati says both of these before it makes anything.
>
> WHERE YOUR RECORDINGS LIVE
> On your phone, in the app's own storage. There is no account and no Jaddati
> server. Three features need a company outside your phone to do the work, and
> Jaddati names both of them, and says exactly what each one receives, before
> anything is sent. Say no and the app still opens and still works — you keep
> the archive and the playback, and nothing leaves the device. You can change
> your mind either way, whenever you like.
>
> Removing a person deletes their recordings from the phone and their voice
> from the voice service.
>
> ENGLISH AND ARABIC
> Arabic is a whole interface, not English pushed to the right. One tap on any
> screen.
>
> Jaddati is a keepsake, not therapy, and does not claim to treat grief.

**Keywords** (100 char max, comma-separated, no spaces):
`voice,memory,family,remembrance,keepsake,arabic,recording,story,legacy,heritage`

Do not put "ElevenLabs", "Groq", "AI" as a brand, or any other developer's
product name in the app name or icon — guideline 4.1(c), added November 2025.

**URLs**
- Privacy policy: `https://sulaimanabuqamar.github.io/jaddati/privacy/`
- Support: `https://sulaimanabuqamar.github.io/jaddati/support/`
- Marketing: `https://sulaimanabuqamar.github.io/jaddati/`

**Screenshots** must show the app in use, not a splash screen. Use the person
screen and the playing screen — the same two already on the poster. Metadata
including screenshots must suit a 4+ audience regardless of the app's rating.

---

## 5. Before you can submit

Things only you can do, roughly in order.

- [ ] **Enrolment.** The Program License Agreement §3.1(a) requires you to
      certify you are "of the legal age of majority in the jurisdiction in
      which You reside". In the UAE that is 21 and you are 19, so you cannot
      make that certification truthfully on your own behalf. Routes: enrol as
      an organisation whose authorised signatory is of age, or have a parent
      or an of-age teammate be the contracting party with you added as an
      Authorized Developer. Do not mis-certify — §3.1(b) makes inaccurate
      information grounds for termination. Note the university route does not
      solve this: it requires student developers to be of majority too.
- [ ] **Build with Xcode 26 or later against the iOS 26 SDK.** Required for
      every upload since 28 April 2026. The deployment target can stay at
      iOS 17 — that is a separate setting and does not need to change.
- [ ] **Verify `PrivacyInfo.xcprivacy` is actually in the built app.** The
      project uses a synchronised file group so it should be picked up
      automatically, but confirm it: build, then check the app bundle contains
      `PrivacyInfo.xcprivacy` at its root. A missing manifest is rejected at
      upload with ITMS-91053, before review ever sees it.
- [ ] **Turn on GitHub Pages** — Settings → Pages → Deploy from a branch →
      `main` → `/docs`. The privacy policy URL is a required field and a dead
      link is a 2.1 rejection. Push first; the pages are in this commit.
- [ ] **Check the ElevenLabs and Groq retention terms** on the accounts you
      actually use, and widen the App Privacy answers if either retains more
      than the table above assumes.
- [ ] **Deploy the proxy, or accept shipping the keys.** The keys are in
      `Secrets.plist`, which is not in the repo but is in the app bundle. No
      clause of either Apple agreement forbids this — but an extracted key is
      your bill and, under the indemnity in §10, your legal exposure.
- [ ] **Consider your address.** Apple's Exhibit B asks for a name and address
      in the EULA for user claims. The terms page currently carries your name,
      email and country. Add a postal address if you want to match Exhibit B
      exactly.
- [ ] **Test the whole flow on a real device** on a Release build, including
      the decline path and withdrawal, before archiving.

---

## 6. What is still uncertain

Stated plainly, because a confident wrong answer here costs a submission cycle.

- **There is no Apple rule about synthetic voices, likeness, or the dead.**
  The words "voice", "likeness", "deepfake", "synthetic" and "deceased" appear
  nowhere in the App Review Guidelines. The exposure is guideline 1.1's
  discretionary "in exceptionally poor taste, or just plain creepy", which has
  no definition and no appeal in the first instance. The empirical record is
  in your favour: at least three apps that clone the voices of deceased
  relatives are live on the store right now, one of which survived a global
  press cycle calling it demonic. But this is a judgement, not a rule, and a
  reviewer's personal reaction cannot be predicted.
- **Whether a deceased person's voice counts as "personal information from a
  source that is not the user"** under 5.1.1(viii) is not something Apple has
  ruled on. The in-app attestation is the best available answer, not a
  guaranteed one.
- **The 5.1.1(i)/5.1.2(i) disclosure rejection is the one to expect.** It has
  a documented pattern, and at least one developer reported being stuck in a
  rejection loop on it even after adding granular consent. If it comes back,
  the reply is: point at the launch screen, say it is shown on a single
  unconditional check, and offer a screen recording.
- **"For entertainment purposes only" will not rescue anything.** Guideline
  1.1.6 forecloses it explicitly. Do not add it.
