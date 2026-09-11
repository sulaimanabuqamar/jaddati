# What Apple actually requires, and where it says so

The evidence behind `app-review.md`. Every claim here was read from a primary
source on 11 September 2026. Where a question has no authoritative answer, it
says so — an invented rule is worse than a known gap.

Guidelines as at the 8 June 2026 revision. Program License Agreement version
LYL255, 18 August 2026. Developer Agreement LYL207, 18 March 2025.

---

## The rule that decides this submission

**Guideline 5.1.2(i)**, amended 13 November 2025, now reads (emphasis on the
new sentence):

> Unless otherwise permitted by law, you may not use, transmit, or share
> someone's personal data without first obtaining their permission. You must
> provide access to information about how and where the data will be used.
> **You must clearly disclose where personal data will be shared with third
> parties, including with third-party AI, and obtain explicit permission
> before doing so.**

Source: <https://developer.apple.com/app-store/review/guidelines/#data-use-and-sharing>
Announcement: <https://developer.apple.com/news/?id=ey6d8onl>

Apple's rejection notice for this, posted verbatim on its own forums:

> **Guidelines 5.1.1(i) and 5.1.2(i)** — The app appears to share the user's
> personal data with a third-party AI service but the app does not clearly
> explain what data is sent and identify who the data is sent to before
> sharing the data. Apps may only use, transmit, or share personal data after
> they meet all of the following requirements:
> - Disclose what data will be sent
> - Specify who the data is sent to
> - Obtain the user's permission before sending data
> - Identify in the privacy policy what data the app collects, how it collects
>   that data, all uses of that data, and confirm any third party the app
>   shares data with provides the same or equal protection

Source: <https://developer.apple.com/forums/thread/815842>

**The failure mode to avoid.** One developer was rejected repeatedly with a
consent screen that already listed every data item, named the third party, and
required three checkboxes. The reviewer's words were *"We were not presented
with the consent prompt on launch or anywhere else in the app."* The cause was
gating logic — `!hasConsented && !hasSeenConsent` — which suppressed the screen
on the reviewer's device. Source: <https://developer.apple.com/forums/thread/820209>

That is why `Consent.hasDecided` is the only condition on the gate, and why
there is a comment in `JaddatiApp.swift` saying not to add a second one.

A third developer reported being stuck in a rejection loop on the same pair of
guidelines even after adding granular consent and backend consent sync.
Source: <https://developer.apple.com/forums/thread/815100>

---

## Privacy policy — guideline 5.1.1(i)

> All apps must include a link to their privacy policy in the App Store Connect
> metadata field **and within the app in an easily accessible manner.** The
> privacy policy must clearly and explicitly:
> - Identify what data, if any, the app/service collects, how it collects that
>   data, and all uses of that data.
> - Confirm that any third party with whom an app shares user data … will
>   provide the same or equal protection of user data …
> - Explain its data retention/deletion policies and describe how a user can
>   revoke consent and/or request deletion of the user's data.

"Within the app" is why the notice is a screen, not only a link — reachable
from **Privacy and data** on the home screen.

---

## The privacy manifest — a hard upload gate

> Starting May 1, 2024, apps that don't describe their use of required reason
> API in their privacy manifest file aren't accepted by App Store Connect.

Source: <https://developer.apple.com/documentation/bundleresources/privacy-manifest-files/describing-use-of-required-reason-api>

This is not a review outcome — the upload is refused. Having no third-party
SDKs does not exempt the app; `UserDefaults` in first-party code is enough.

What Jaddati uses, audited against Apple's five categories:

| Category | Used? | Declared |
|---|---|---|
| `…CategoryUserDefaults` | Yes — `UserDefaults`, `@AppStorage` | `CA92.1` |
| `…CategoryFileTimestamp` | Yes — `attributesOfItem` in `VoiceRecorder` | `C617.1` |
| `…CategorySystemBootTime` | No — no `systemUptime`, no `mach_absolute_time` | — |
| `…CategoryDiskSpace` | No | — |
| `…CategoryActiveKeyboards` | No — language comes from `Locale`, not `activeInputModes` | — |

`CA92.1` is the right reason: data readable only by this app, no App Group.
`C617.1` covers "the timestamps, **size**, or other metadata of files inside
the app container", which is exactly the file-size read in `VoiceRecorder`.

**Never list `api.elevenlabs.io` or `api.groq.com` in
`NSPrivacyTrackingDomains`.** Apple: *"If the user has not granted tracking
permission through the App Tracking Transparency framework, network requests
to these domains fail"* — it would break the app. `NSPrivacyTracking` is
`false` and the domains array is empty, which is correct: this is not tracking.

---

## Identifier for vendor is not tracking

> The **ID for Vendors (IDFV)** may be used for analytics across apps from the
> same content provider. **In this case, the use of the AppTrackingTransparency
> framework is not required.**

Source: <https://developer.apple.com/app-store/user-privacy-and-data-use/>

Tracking is defined as linking data with *other companies'* data for
advertising, or sharing with data brokers. Rate-limiting against our own relay
is neither. **Do not add an ATT prompt.**

Separately, PLA §3.3.3(B) says *"Neither You nor Your Application will use any
permanent, device-based identifier … for purposes of uniquely identifying a
device."* IDFV is not permanent — it resets when the app is deleted — and Apple
sanctions this use explicitly above. It is also now sent only to our own relay,
not to ElevenLabs or Groq, who have no use for it.

---

## Recording — PLA §3.3.3(A)

> If Your Application captures or makes any video, microphone, screen
> recordings, or camera recordings … a reasonably conspicuous audio, visual or
> other indicator must be displayed to the user as part of the Application to
> indicate that a Recording is taking place. Your Application may not be
> designed to facilitate Recordings of others without their awareness.

Satisfied by `LiveMeter` — a moving level bar and a running clock, on screen
the whole time the microphone is open, in both recording paths.

The second sentence is the one worth understanding. Jaddati does not capture
the deceased person's voice; the user supplies audio they already hold. That is
the defensible reading and the review notes state it. Nothing in either
agreement resolves it expressly.

**PLA §3.3.3(F)(iv)** requires purpose strings to be *"accurate and not
misrepresent the scope of use."* The old microphone string said the microphone
was used only to record a sample. That stopped being true when dictation
shipped, and said nothing about the audio going to Groq. It now says both.

---

## Intellectual property — guideline 5.2.2

> If your app uses, accesses, monetises access to or displays content from a
> third-party service, ensure you are specifically permitted to do so under the
> service's terms of use. **Authorisation must be provided upon request.**

ElevenLabs' Prohibited Use Policy forbids *"creating or using ElevenLabs audio
output to intentionally replicate the voice of another person … without consent
or legal right"*. Their Terms of Use add: *"You may not provide Input or create
Output for which you do not have all the rights necessary."*

Neither document addresses deceased persons. The app therefore passes the
obligation to the uploader through the attestation, which is the only mechanism
available to it. Be ready to produce the account terms if Apple asks.

---

## What Apple does NOT say

Searched across the complete Guidelines PDF and both agreements. **Zero
matches**, in any of them, for: *likeness*, *voice*, *deepfake*, *synthetic*,
*deceased*, *biometric*, *voiceprint*. "AI" appears exactly once in the
Guidelines — the 5.1.2(i) sentence above.

There is no rule about voice cloning. There is no rule about grief or the
dead. There is no published Apple guidance for generative-AI apps. Guideline
4.1(b) on impersonation is about impersonating *other apps*, not people.

The nearest applicable text is the **1.1 preamble** — *"offensive, insensitive,
upsetting, intended to disgust, in exceptionally poor taste, or just plain
creepy"* — which is discretionary. None of 1.1.1 through 1.1.7 fits a
consensual family memorial.

Note **1.1.6**: *"Stating that the app is 'for entertainment purposes' won't
overcome this guideline."* Do not reach for that phrase.

And **1.1.5**, inflammatory religious commentary, is a live surface for an
Arabic app about death. The story prompt in `LLMClient` already forbids the
model from claiming to be a real person or to remember anything; that
constraint is load-bearing and should not be relaxed.

---

## The precedent

Apps functionally equivalent to Jaddati, live on the App Store as at 11
September 2026:

| App | What it does | Rating |
|---|---|---|
| HearThem: Speak to the Dead | Upload a recording of a deceased person, clone it, generate speech | 9+ |
| Dead Talks AI: Loved Ones | Memorial companion with voice synthesis | 9+ |
| Voice & Face Cloning: Clony AI | General voice cloning from audio | 4+ |
| 2wai | Avatars of deceased relatives — drew global backlash in Nov 2025 and stayed up | — |

Two things worth copying. Clony AI puts a consent covenant in its store
description. Dead Talks puts a "not a replacement for professional mental
health therapy or grief counselling" disclaimer in its. Both are reflected in
our listing copy and support page.

I found no documented rejection of any app for voice cloning as such, and none
of a memorial or grief app under 1.1. That is an absence of evidence, not proof
of safety.

---

## Enrolment — the blocker that is not about the app

**PLA §3.1(a)**:

> You certify to Apple and agree that: (a) You are of the legal age of majority
> in the jurisdiction in which You reside (at least 18 years of age in many
> countries or regions) and have the right and authority to enter into this
> Agreement on Your own behalf …

The test is the **age of majority where you live**, not 18. The parenthetical
is descriptive. UAE majority is 21.

**§3.1(b)** requires all information provided to Apple to be *"current, true,
accurate, supportable and complete"*, and says failure *"may be grounds for
disabling or terminating Your Program membership."*

The university route in the same clause does not help: it requires Authorized
Student Developers to be of majority as well. The workable routes are an
organisation enrolment with an of-age authorised signatory, or an of-age person
as the contracting party with you as an Authorized Developer — which is the
same shape as the guardian mechanism Apple itself describes in the Developer
Agreement §6(B).

---

## Build requirements

> Since April 28, 2026 — Apps uploaded to App Store Connect must be built with
> **Xcode 26 or later** using an SDK for **iOS 26** …

Source: <https://developer.apple.com/news/upcoming-requirements/>

Deployment target is a different setting. `IPHONEOS_DEPLOYMENT_TARGET = 17.0`
is fine and does not need to move.

Export compliance: `ITSAppUsesNonExemptEncryption = NO` is correct, because
Apple states that *"the use of encryption that's built into the operating
system — for example, when your app makes HTTPS connections using URLSession —
is exempt."* No French declaration is required for that case, even shipping in
France.

---

## Sources

- App Review Guidelines — <https://developer.apple.com/app-store/review/guidelines/>
- Guidelines PDF (6 Feb 2026) — <https://developer.apple.com/support/downloads/terms/app-review-guidelines/App-Review-Guidelines-English-UK.pdf>
- Guidelines updates — [13 Nov 2025](https://developer.apple.com/news/?id=ey6d8onl) · [6 Feb 2026](https://developer.apple.com/news/?id=d75yllv4) · [8 Jun 2026](https://developer.apple.com/news/?id=a233fmpw)
- Privacy manifests — <https://developer.apple.com/documentation/bundleresources/privacy-manifest-files>
- Required reason API — <https://developer.apple.com/documentation/bundleresources/privacy-manifest-files/describing-use-of-required-reason-api>
- App privacy details — <https://developer.apple.com/app-store/app-privacy-details/>
- User privacy and data use — <https://developer.apple.com/app-store/user-privacy-and-data-use/>
- Encryption export — <https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations>
- Upcoming requirements — <https://developer.apple.com/news/upcoming-requirements/>
- Age ratings — <https://developer.apple.com/news/?id=ks775ehf> · <https://developer.apple.com/help/app-store-connect/reference/app-information/age-ratings-values-and-definitions>
- Apple forums — [815842](https://developer.apple.com/forums/thread/815842) · [820209](https://developer.apple.com/forums/thread/820209) · [815100](https://developer.apple.com/forums/thread/815100)
- ElevenLabs — [Use policy](https://elevenlabs.io/use-policy) · [Terms](https://elevenlabs.io/terms-of-use)
