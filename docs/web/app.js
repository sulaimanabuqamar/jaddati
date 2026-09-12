// Screens and navigation. The structure follows the app: People, Saved and
// Books are the three places you can be, the rail is visible from all of them,
// and Saved and Books are scoped to one person because a pile of clips with no
// name on it is not an archive.

import { L, isAr, isArabicText, dirOf, Counts, state as lang, setLang } from "./strings.js";
import {
  store, Consent, ConsentMissing, Config, Voice, Companion, VoiceError, CompanionError,
  Intent, INTENTS, ContentProvenance, TUNING, sameTuning, presetName,
  AFFIRMATIONS, STORIES, makeBook, ImportError, isDemoVoice, uuid, blobURL,
  STOCK_VOICE_URL, STOCK_LLM_URL, Archive, ArchiveError,
} from "./core.js";
import {
  h, clear, bidi, icon, appBar, globeButton, headline, eyebrow, sectionLabel,
  subtext, caption, panel, panelS, errorNote, emptyHint, avatar, breadcrumb,
  sourceBadge, contentBadge, badgesFor, audioRow, player, confirmDialog, sheet,
  toast, Recorder, durationOf, demoDuration, track, unmountAll,
} from "./ui.js";
import { nav, remember, setRenderer, render, push, pop, popTo, goTab } from "./nav.js";
import {
  createScreen, booksScreen, readerScreen, memoriesScreen, playerScreen, openAddVoice,
  personHasVoice, lettersScreen, captureScreen,
} from "./screens.js";

const root = document.getElementById("app");

function selectedPerson() {
  if (nav.personId) { const p = store.person(nav.personId); if (p) return p; }
  return store.people.length === 1 ? store.people[0] : null;
}

// ── render ──────────────────────────────────────────────────────────────


function paintRoot() {
  unmountAll();
  clear(root);
  remember();

  if (!Consent.hasDecided) { root.append(consentGate()); return; }

  // The rail is furniture, not content: it stays put while screens push and
  // pop above it, exactly as the pager does in the app.
  const top = nav.stack[nav.stack.length - 1];
  // clear(root) has already run, so a screen builder that throws leaves an
  // empty page with no way back but a reload. Falling back to the root of the
  // tab keeps the app usable and says what happened.
  let screen;
  try {
    screen = top ? top.screen(top.props)
    : nav.tab === "people" ? homeScreen()
    : nav.tab === "saved" ? personScoped(p => memoriesScreen({ personId: p.id, isTabRoot: true }),
        L("Open a person to see what is kept for them."), L("Saved"))
    : personScoped(p => booksScreen({ personId: p.id, isTabRoot: true }),
        L("Open a person to bring them a text."), L("Books"));
  } catch (e) {
    console.error("screen failed to build", e);
    nav.stack.length = 0;
    screen = h("div", { class: "screen" },
      appBar(L("Jaddati")),
      h("div", { class: "scroll" },
        errorNote(L("That screen could not be opened. Nothing has been deleted."))));
  }

  root.append(screen, tabRail());
}

function personScoped(build, emptyMessage, title) {
  const person = selectedPerson();
  if (person) return build(person);
  return h("div", { class: "screen" },
    appBar(title),
    h("div", { class: "scroll", style: { display: "flex", flexDirection: "column", justifyContent: "center" } },
      emptyHint("personSlash", L("Choose someone first"), emptyMessage),
      h("button", { class: "btn-quiet", onClick: () => goTab("people") }, L("Go to People"))));
}

function tabRail() {
  const tabs = [["people", L("People"), "house"], ["saved", L("Saved"), "tray"], ["books", L("Books"), "book"]];
  return h("nav", { class: "tabrail" }, tabs.map(([key, title, ic]) =>
    h("button", {
      "aria-selected": String(nav.tab === key), onClick: () => goTab(key),
    }, icon(ic), h("span", {}, title))));
}

store.addEventListener("change", () => { if (!document.querySelector(".sheet-scrim")) render(); });
window.addEventListener("jaddati:lang", () => render());

// ── the gate ────────────────────────────────────────────────────────────
// Three features send something to a company outside this device, and the
// wording of the refusal that catches apps like this one is specific: say what
// is sent, say who it is sent to, and ask before sending it.

function consentGate() {
  const recipient = (name, role, sends, why) =>
    h("div", { class: "stack gap-xs" },
      h("div", { class: "row", style: { gap: "6px", flexWrap: "wrap" } },
        h("span", { class: "serif", style: { fontSize: "22px", fontWeight: "700" } }, name),
        h("span", { style: { color: "var(--hairline)" } }, "·"),
        h("span", { class: "caption" }, role)),
      labelled(L("What is sent"), sends),
      labelled(L("What they do with it"), why));

  const labelled = (title, detail) => h("div", { class: "stack", style: { gap: "2px" } },
    h("div", { style: { fontSize: "11px", fontWeight: "600", textTransform: "uppercase", letterSpacing: isAr() ? "0" : ".6px", color: "var(--wine)" } }, title),
    h("p", { class: "caption", style: { margin: 0 } }, detail));

  return h("div", { class: "screen" },
    h("div", { class: "scroll", style: { paddingTop: "var(--l)" } },
      h("div", { class: "stack gap-m" },
        h("div", { class: "stack gap-s" },
          h("div", { class: "row between" }, eyebrow(L("Before you begin")), globeButton()),
          headline(L("Some of this\nleaves the phone."), 33),
          subtext(L("Jaddati can work entirely on this phone. Three things cannot, because they are done by companies outside it. Here is exactly what they are."))),

        panel(h("div", { class: "stack gap-m" },
          recipient("ElevenLabs", L("Voice service"),
            L("The recording you choose, and the words you ask to be spoken."),
            L("It builds the voice and reads your words in it. The voice it builds is kept on their servers, not only here.")),
          h("div", { class: "divider" }),
          recipient("Groq", L("Questions and dictation"),
            L("A question typed or spoken during a story, with the page it is about — and the audio itself when you speak instead of typing."),
            L("It writes the answer, and turns speech into text. It is never told whose voice will read the answer out.")))),

        h("p", { class: "caption", style: { margin: 0 } },
          L("Both are reached through a relay Jaddati runs. It passes your request on and keeps no copy of it.")),

        h("div", { class: "stack gap-s" },
          h("button", { class: "btn-primary", onClick: () => { Consent.record(true); render(); } }, L("Allow these three things")),
          h("button", { class: "btn-quiet", onClick: () => { Consent.record(false); render(); } }, L("Not now — keep everything on this phone"))),

        h("div", { class: "stack gap-s" },
          h("p", { class: "small", style: { margin: 0 } },
            L("Choosing to keep everything here still opens the app. You can play recordings, add people, and keep an archive. Creating a new voice, asking questions and speaking instead of typing stay switched off until you change this.")),
          h("button", { class: "wine-text", style: { fontWeight: "600", fontSize: "13px", minHeight: "var(--touch)", textAlign: "start" }, onClick: () => openPrivacy(false) },
            L("Read the full privacy notice"))))));
}

// ── privacy ─────────────────────────────────────────────────────────────

function openPrivacy(showControls = true) {
  sheet(close => {
    const bullet = words => h("div", { class: "row row--top", style: { gap: "var(--xs)" } },
      h("span", { style: { width: "4px", height: "4px", borderRadius: "50%", background: "var(--wine)", marginTop: "8px", flex: "none" } }),
      h("p", { class: "caption", style: { margin: 0 } }, words));

    const status = () => {
      const answer = Consent.allowsNetwork
        ? L("You allowed the app to use the two services above.")
        : L("Everything is being kept on this phone. Nothing is sent anywhere.");
      const d = Consent.decidedOn;
      if (!d) return answer;
      return answer + " " + L("You chose this on") + " " +
        d.toLocaleString(isAr() ? "ar" : "en", { dateStyle: "medium", timeStyle: "short" });
    };

    return h("div", { class: "screen" },
      appBar(L("Privacy and data"), { trailing: h("button", { class: "iconbtn", onClick: close, "aria-label": L("Close") }, icon("close")) }),
      h("div", { class: "scroll" }, h("div", { class: "stack gap-m" },
        headline(L("What Jaddati\ndoes with data."), 30),

        panel(h("div", { class: "stack gap-xs" }, sectionLabel(L("Stays on this phone")),
          bullet(L("Recordings you add, and every clip the app creates.")),
          bullet(L("Names, relationships and photos.")),
          bullet(L("Which language you read the app in.")),
          h("p", { class: "caption", style: { marginTop: "2px" } },
            L("These are held in this browser's own storage. There is no account and no sign-in, and none of it is uploaded to us.")))),

        panel(h("div", { class: "stack gap-xs" }, sectionLabel(L("Sent to others, only if you allow it")),
          bullet(L("ElevenLabs receives the recording you choose and the words you want spoken. The voice it builds is stored under this app's account there.")),
          bullet(L("Groq receives a question and the page it is about, and the audio when you speak instead of typing.")),
          bullet(L("Both are reached through a relay Jaddati runs, so that the keys are not sitting inside this web page for anyone to take. It passes the request on and keeps no copy of it. It does count how much each browser has asked for, so that one visitor cannot use up what everyone else needs — a count, against a random code, with no name attached.")),
          h("p", { class: "caption", style: { marginTop: "2px" } },
            L("Both are bound by their own terms, which require them to protect what they are sent. Jaddati does not send them anything else, and does not send anything anywhere else.")))),

        panel(h("div", { class: "stack gap-xs" }, sectionLabel(L("Keeping and deleting")),
          bullet(L("Deleting a person here deletes their recordings and clips from this phone straight away.")),
          bullet(L("Removing a person also deletes the voice built for them at the voice service. That happens first, and if it fails nothing here is removed, so it can be tried again.")),
          bullet(L("Neither service is asked to keep anything for Jaddati, and Jaddati keeps no copy of what it sends.")))),

        showControls ? panel(h("div", { class: "stack gap-s" }, sectionLabel(L("Your answer")),
          h("p", { style: { margin: 0 } }, status()),
          Consent.allowsNetwork
            ? h("button", { class: "btn-quiet", onClick: () => { Consent.withdraw(); close(); render(); } }, L("Stop sending anything off this phone"))
            : h("button", { class: "btn-quiet", onClick: () => { Consent.record(true); close(); render(); } }, L("Allow the three things above")))) : null,

        h("div", { class: "stack", style: { gap: "4px" } },
          h("div", { class: "label" }, L("Questions about any of this")),
          h("a", { class: "caption wine-text", href: "mailto:sulaiman.abuqamar@gmail.com" }, "sulaiman.abuqamar@gmail.com"),
          h("a", { class: "caption", href: "../privacy/" }, L("Read the full privacy notice"))),
      )));
  });
}

// ── voice service ───────────────────────────────────────────────────────
// A key shipped inside a web page is a key anyone can read out of it, so this
// version carries none of the real ones and goes through a relay instead.
// There is nothing to fill in here. What is left is for two people: whoever
// would rather spend their own allowance than ours, and whoever is about to
// rehearse this in front of a room and does not want to spend either.

function openSettings() {
  sheet(close => {
    // The boxes show what the visitor typed, never our relay token. Seeding
    // them from the effective key would put a credential on screen and, worse,
    // saving an untouched form would pin it as if they had chosen it.
    const eleven = h("input", { type: "password", value: Config.personalVoiceKey, placeholder: "sk_…", autocomplete: "off", spellcheck: "false" });
    const llm = h("input", { type: "password", value: Config.personalTextKey, placeholder: "gsk_…", autocomplete: "off", spellcheck: "false" });
    const voiceURL = h("input", { type: "url", value: Config.voiceBaseURL, placeholder: STOCK_VOICE_URL, autocomplete: "off", spellcheck: "false" });
    const llmURL = h("input", { type: "url", value: Config.llmBaseURL, placeholder: STOCK_LLM_URL, autocomplete: "off", spellcheck: "false" });
    const demoSwitch = h("input", { type: "checkbox", checked: Config.demoOnly });

    const field = (title, input, note) => h("label", { class: "field" },
      h("div", { class: "field__title" }, title), input,
      note ? h("p", { class: "small", style: { marginTop: "6px" } }, note) : null);

    return h("div", { class: "screen" },
      appBar(L("Voice service"), { trailing: h("button", { class: "iconbtn", onClick: close, "aria-label": L("Close") }, icon("close")) }),
      h("div", { class: "scroll" }, h("div", { class: "stack gap-m" },
        headline(L("Ready as it is."), 30),
        subtext(L("Jaddati for the web reaches the voice service through a relay we run, so there is no key to find and nothing to paste. Each browser gets a share of the allowance rather than a key of its own.")),

        panel(h("div", { class: "stack gap-xs" },
          h("label", { class: "switch" }, demoSwitch,
            h("span", { class: "label", style: { flex: "1" } }, L("Rehearse without using the allowance"))),
          h("p", { class: "caption", style: { margin: 0 } },
            L("Everything works as it does live, but the app speaks with this browser's own voice and reaches no service at all. That is not a recreation of anyone, and every clip made this way says so.")))),

        // The flex container sits inside the <details> rather than on it:
        // Safari lays a flexed <details> out wrongly, marker and all.
        h("details", {},
          h("summary", { class: "label", style: { minHeight: "var(--touch)", display: "flex", alignItems: "center", cursor: "pointer" } },
            L("Use my own keys instead")),
          h("div", { class: "stack gap-s", style: { paddingTop: "var(--xs)" } },
            subtext(L("With your own key the app goes straight to the service and our relay is not involved. Keys stay in this browser and go only to the service they belong to.")),
            field("ElevenLabs " + L("key"), eleven, L("Used to create the voice and to speak your words.")),
            field("Groq " + L("key"), llm, L("Used for questions during a story, and for speaking instead of typing. Optional.")),
            field(L("Voice service") + " URL", voiceURL, L("Leave as it is unless you run a relay of your own.")),
            field(L("Questions and dictation") + " URL", llmURL))),

        h("button", { class: "btn-primary", onClick: () => {
          Config.demoOnly = demoSwitch.checked;
          Config.personalVoiceKey = eleven.value; Config.personalTextKey = llm.value;
          Config.voiceBaseURL = voiceURL.value; Config.llmBaseURL = llmURL.value;
          close(); toast(L("Saved")); render();
        } }, L("Save")),

        Config.personalVoiceKey || Config.personalTextKey
          ? h("button", { class: "btn-quiet", onClick: () => {
              Config.personalVoiceKey = ""; Config.personalTextKey = "";
              close(); toast(L("Keys removed from this browser.")); render();
            } }, L("Remove the keys from this browser")) : null,
      )));
  });
}

// ── people ──────────────────────────────────────────────────────────────

function homeScreen() {
  const people = store.people;

  const addButton = h("button", { class: "btn-outline", onClick: openAddPerson },
    icon("plus"), h("span", {}, L("Add someone")));

  return h("div", { class: "screen" },
    h("header", { class: "appbar" }, h("div", { class: "grow" }),
      h("button", { class: "iconbtn", onClick: openSettings, "aria-label": L("Voice service") }, icon("key")),
      globeButton()),

    h("div", { class: "scroll" },
      h("div", { class: "stack", style: { paddingTop: "8px" } },
        eyebrow(L("A family archive")),
        h("div", { class: "row between", style: { alignItems: "baseline", marginTop: "6px" } },
          h("span", { class: "serif", style: { fontSize: "37px", letterSpacing: isAr() ? "0" : "-1.3px" } }, "Jaddati"),
          h("span", { class: "serif wine-text", dir: "rtl", style: { fontSize: "28px" } }, "جدّتي")),
        h("div", { style: { marginTop: "6px" } }, subtext(L("A place for a familiar voice.")))),

      h("div", { class: "hero" },
        icon("dotted"),
        h("p", { class: "hero__lede" }, L("The recordings you have. The words you choose.")),
        h("div", { class: "hero__rule" }),
        h("div", { class: "hero__foot" }, icon("seal"), h("span", {}, L("Original and recreated. Always distinct.")))),

      store.storageError ? h("div", { class: "mt-16" }, errorNote(store.storageError)) : null,
      Config.isDemo ? h("div", { class: "mt-16" }, demoBanner()) : null,
      !Config.isConfigured ? h("div", { class: "mt-16" }, unavailableNote()) : null,

      people.length === 0
        ? h("div", {}, emptyHint("waveform", L("No people yet"), L("Start with a name. Add a recording when you are ready.")),
            addButton, h("div", { class: "mt-16" }, importPersonRow()))
        : h("div", { class: "stack" },
            h("div", { class: "mt-26" }, sectionLabel(L("People you keep here"))),
            people.map(personCard),
            h("div", { style: { marginTop: "4px" } }, addButton),
            h("div", { style: { marginTop: "4px" } }, importPersonRow())),

      privacyRow()));
}

/** Loud on purpose. A demo that looks like the real thing is how a browser's
 *  own voice ends up presented as a recreation of somebody's grandmother. */
function demoBanner() {
  return panel(h("div", { class: "stack", style: { gap: "4px" } },
    h("div", { style: { fontSize: "12px", fontWeight: "800", color: "var(--danger)", letterSpacing: isAr() ? "0" : ".5px" } },
      L("DEMO MODE")),
    // Two different roads lead here now, and telling someone to add a key when
    // they simply left rehearsal on would send them hunting for a problem that
    // is not there.
    h("p", { class: "caption", style: { margin: 0 } },
      Config.demoOnly
        ? L("Rehearsal is switched on, so nothing is sent anywhere and the app speaks with this browser's own voice. It is not a recreation of anyone.")
        : L("No voice service key is set, so nothing is sent anywhere and the app speaks with this browser's own voice. It is not a recreation of anyone.")),
    Config.demoOnly
      ? h("button", { class: "wine-text", style: { fontWeight: "600", fontSize: "13px", textAlign: "start", minHeight: "var(--touch)" },
                      onClick: () => { Config.demoOnly = false; toast(L("Rehearsal is off. The app is live again.")); render(); } },
          L("Switch rehearsal off"))
      : h("button", { class: "wine-text", style: { fontWeight: "600", fontSize: "13px", textAlign: "start", minHeight: "var(--touch)" }, onClick: openSettings },
          L("Add a key"))));
}

const unavailableNote = () => panel(h("div", { class: "stack", style: { gap: "6px" } },
  h("div", { class: "label" }, Config.unavailableTitle), subtext(Config.unavailableMessage)));

function personCard(person) {
  const originals = store.assetsFor(person.id, "original").length;
  const saved = store.keptClips(person.id).length;
  const parts = [];
  if (originals) parts.push(Counts.originals(originals));
  if (saved) parts.push(Counts.savedClips(saved));
  const collection = parts.length ? parts.join(" · ")
    : (person.relationship || L("No recordings yet"));

  const hasVoice = personHasVoice(person);
  const status = isDemoVoice(person.voiceId) && !Config.isDemo
    ? h("div", { class: "small danger" }, L("Test voice · No real voice was created."))
    : hasVoice
      ? h("div", { class: "row", style: { gap: "6px" } },
          h("span", { style: { width: "5px", height: "5px", borderRadius: "50%", background: "var(--sage)" } }),
          h("span", { class: "small sage-text" }, L("Recreated voice ready")))
      : h("div", { class: "small" }, L("No recreated voice yet"));

  return h("button", {
    class: "person-card",
    onClick: () => { nav.personId = person.id; push(personScreen, { personId: person.id }); },
  },
    avatar(person, 54),
    h("div", { class: "person-card__body" },
      bidi(person.name, { class: "person-card__name" }),
      h("div", { class: "small" }, collection), status),
    icon("chevron", isAr() ? "flip" : null));
}

function privacyRow() {
  return h("button", { class: "privacy-row", onClick: () => openPrivacy(true) },
    icon(Consent.allowsNetwork ? "unlock" : "lock"),
    h("div", { class: "grow" },
      h("div", { class: "label" }, L("Privacy and data")),
      h("div", { class: "small" }, Consent.allowsNetwork
        ? L("Two services outside this phone are in use.")
        : L("Everything is being kept on this phone."))),
    icon("chevron", isAr() ? "flip" : null));
}

function openAddPerson() {
  sheet(close => {
    const name = h("input", { type: "text", placeholder: "جدّتي" });
    const rel = h("input", { type: "text", placeholder: L("Grandmother") });
    const submit = h("button", { class: "btn-primary", disabled: true, onClick: () => {
      const trimmed = name.value.trim();
      if (!trimmed) return;
      const p = store.addPerson({ name: trimmed, relationship: rel.value.trim() });
      nav.personId = p.id;
      close(); render();
    } }, L("Add person"));
    name.addEventListener("input", () => { submit.disabled = !name.value.trim(); });

    return h("div", { class: "screen" },
      appBar(L("Add a person"), { trailing: h("button", { class: "iconbtn", onClick: close, "aria-label": L("Cancel") }, icon("close")) }),
      h("div", { class: "scroll" },
        h("div", { class: "serif", style: { fontSize: "28px", marginBottom: "13px" } }, L("Add a person")),
        subtext(L("Start with a name. Add a recording when you are ready.")),
        h("label", { class: "field" }, h("div", { class: "field__title" }, L("Name")), name),
        h("label", { class: "field" }, h("div", { class: "field__title" }, L("Relationship")), rel),
        h("div", { class: "mt-l" }, submit)));
  });
}

// ── one person ──────────────────────────────────────────────────────────

function personScreen({ personId }) {
  const person = store.person(personId);
  if (!person) return h("div", { class: "screen" }, appBar(L("Jaddati"), { onBack: pop }),
    h("div", { class: "scroll" }, emptyHint("personSlash", L("No people yet"), L("A place for voices you want to keep."))));

  const hasVoice = personHasVoice(person);
  const placeholder = isDemoVoice(person.voiceId) && !Config.isDemo;
  const pending = person.voiceId && person.voiceRequiresVerification === true;
  const originals = store.assetsFor(person.id, "original");
  const kept = store.keptClips(person.id);

  const voiceTag = () => {
    const [words, tint] = placeholder ? [L("Test voice only"), "var(--danger)"]
      : hasVoice ? [L("Recreated voice ready"), "var(--wine)"]
      : pending ? [L("Voice is being prepared"), "var(--amber)"]
      : [L("No recreated voice yet"), "var(--ink-soft)"];
    return h("span", { class: "voicetag", style: { color: tint, background: "color-mix(in srgb, " + tint + " 10%, transparent)" } }, words.toUpperCase());
  };

  const photoInput = h("input", { type: "file", accept: "image/*", class: "hidden", onChange: async e => {
    const file = e.target.files?.[0]; if (!file) return;
    const shrunk = await downscale(file).catch(() => null);
    if (shrunk) await store.setPhoto(person, shrunk);
    e.target.value = "";
  } });

  return h("div", { class: "screen" },
    appBar(person.name, { onBack: pop }),
    h("div", { class: "scroll" },
      photoInput,
      h("div", { class: "row", style: { gap: "16px", marginTop: "16px" } },
        h("button", { style: { position: "relative", background: "none", padding: 0 }, onClick: () => photoInput.click(),
          "aria-label": person.photoFilename ? L("Change photo") : L("Add photo") },
          avatar(person, 88),
          h("span", { style: { position: "absolute", insetInlineEnd: "-2px", bottom: "-2px", width: "22px", height: "22px", borderRadius: "50%", background: "var(--wine)", color: "var(--paper)", display: "grid", placeItems: "center", border: "2px solid var(--paper)", fontSize: "12px", fontWeight: "700" } },
            person.photoFilename ? "✎" : "+")),
        h("div", { class: "grow stack", style: { gap: "5px" } },
          bidi(person.name, { class: "serif", style: { fontSize: "33px" } }),
          person.relationship ? bidi(person.relationship, { class: "caption" }) : null,
          voiceTag())),

      person.photoFilename ? h("button", { class: "small", style: { marginTop: "10px", textAlign: "start" },
        onClick: () => store.removePhoto(person) }, L("Remove photo")) : null,

      !Config.isConfigured ? h("div", { class: "mt-21" }, unavailableNote()) : null,

      hasVoice ? intentList(person)
        : placeholder ? h("div", { class: "mt-21" }, panel(h("div", { class: "stack gap-s" },
            h("div", { class: "serif", style: { fontSize: "22px", fontWeight: "700" } }, L("Test voice only")),
            h("p", { style: { margin: 0 } }, L("Created in offline test mode. This is not a usable voice.")),
            h("button", { class: "btn-primary", onClick: () => openAddVoice(person.id) }, L("Create a real voice")))))
        : pending ? h("div", { class: "mt-21" }, pendingPanel(person))
        : h("div", { class: "mt-21" }, panel(h("div", { class: "stack gap-s" },
            h("div", { class: "serif", style: { fontSize: "22px", fontWeight: "700" } }, L("No recreated voice yet")),
            h("p", { style: { margin: 0 } }, L("Add an original recording to create a voice.") + " " + L("About a minute. One voice. A quiet room.")),
            h("button", { class: "btn-primary", onClick: () => openAddVoice(person.id) }, L("Add their voice"))))),

      h("div", { class: "quiet-divider" }),
      h("div", { class: "row between" }, sectionLabel(L("Original recordings")),
        h("button", { class: "wine-text", style: { fontSize: "13px", fontWeight: "500" }, onClick: () => openAddVoice(person.id) }, L("Add their voice"))),
      originals.length
        ? originals.map(a => track(audioRow(a, asset => push(playerScreen, { assetId: asset.id }))))
        : h("div", { style: { marginTop: "10px" } }, subtext(L("No recordings yet"))),

      h("button", { class: "list-link mt-22", onClick: () => push(memoriesScreen, { personId: person.id }) },
        h("span", { class: "grow" }, L("Everything saved")),
        h("span", { class: "small" }, kept.length ? Counts.savedClips(kept.length) : L("Nothing saved yet"))),

      captureRow(person),

      personFooter(person)));
}

function pendingPanel(person) {
  const note = h("div", {});
  const btn = h("button", { class: "btn-primary", onClick: async () => {
    btn.disabled = true; btn.textContent = L("Checking…"); clear(note);
    try {
      // There is no "is it ready" endpoint. The only honest test is to use the
      // voice: if the service speaks, it is available.
      await Voice.synthesize(L("Hello"), person.voiceId, Config.defaultModelId, person.tuning || TUNING.natural);
      store.updatePerson({ ...person, voiceRequiresVerification: false });
    } catch (e) {
      btn.disabled = false; btn.textContent = L("Check availability");
      note.append(h("p", { class: "caption danger", style: { margin: 0 } },
        e instanceof ConsentMissing ? Config.unavailableMessage
          : (e?.message || L("The service has not made this voice available yet."))));
    }
  } }, L("Check availability"));

  return panel(h("div", { class: "stack gap-s" },
    h("div", { class: "serif", style: { fontSize: "22px", fontWeight: "700" } }, L("Voice is being prepared")),
    h("p", { style: { margin: 0 } }, L("The voice has been created, but the service has not made it available yet.")),
    btn, note,
    h("p", { class: "small", style: { margin: 0 } }, L("Checking asks the service to say one short word."))));
}

/// Capturing someone who is still alive is a different act from everything the
/// rest of this screen does, all of which is about someone who is not — and it
/// is most useful BEFORE a voice exists, which is exactly when the experience
/// list is hidden. So it renders on its own, either way.
function captureRow(person) {
  return h("div", { class: "mt-18" },
    h("div", { class: "divider" }),
    h("button", {
      class: "feature-row",
      onClick: () => push(captureScreen, { personId: person.id }),
    },
      h("span", { class: "feature-row__icon" }, icon("mic")),
      h("span", { class: "grow stack", style: { gap: "3px", textAlign: "start" } },
        h("span", { class: "feature-row__title" }, L("Recorded before it is needed")),
        h("span", { class: "caption" }, L("Ask for the recording while they are still here to give it"))),
      icon("chevron", isAr() ? "flip" : null)));
}

function intentList(person) {
  const dueCount = store.dueLetters(person.id).length;

  // The letters row sits with the experiences but is not one of them: it has a
  // date, so it does not fit the compose screen's shape. A letter whose day has
  // come says so here, because a sealed letter nobody is told about is a letter
  // that never arrives.
  const lettersRow = h("div", {},
    h("div", { class: "divider" }),
    h("button", {
      class: "feature-row",
      onClick: () => push(lettersScreen, { personId: person.id }),
    },
      h("span", { class: "feature-row__icon" }, icon(dueCount ? "unlock" : "lock")),
      h("span", { class: "grow stack", style: { gap: "3px", textAlign: "start" } },
        h("span", { class: "feature-row__title" }, L("Words that arrive later")),
        h("span", { class: "caption" }, dueCount
          ? L("Waiting for you")
          : L("Sealed now, heard on a day you choose"))),
      dueCount ? h("span", { class: "badge badge--orig" }, String(dueCount)) : null,
      icon("chevron", isAr() ? "flip" : null)));


  return h("div", { class: "stack mt-22" }, INTENTS.map((key, i) => {
    const row = h("button", {
      class: "feature-row" + (i === 0 ? " feature-row--hero" : ""),
      onClick: () => key === "readBook"
        ? push(booksScreen, { personId: person.id })
        : push(createScreen, { personId: person.id, intent: key }),
    },
      h("span", { class: "feature-row__icon" }, icon(Intent.icon(key))),
      h("span", { class: "grow stack", style: { gap: "3px", textAlign: "start" } },
        h("span", { class: "feature-row__title" }, Intent.title(key)),
        h("span", { class: "caption" }, Intent.subtitle(key))),
      icon("chevron", isAr() ? "flip" : null));
    return h("div", {}, row,
      i > 0 && i < INTENTS.length - 1 ? h("div", { class: "divider" }) : null);
  }), lettersRow);
}

function personFooter(person) {
  return h("div", {}, handoffRow(person), deleteRow(person));
}

function deleteRow(person) {
  const problem = h("div", {});
  const busy = h("div", { class: "hidden row gap-s mt-xs" }, h("span", { class: "spinner" }),
    h("span", { class: "caption" }, L("Removing the voice from the voice service…")));

  const remove = async () => {
    clear(problem);
    // A voice that arrived with a family archive belongs to everyone holding
    // that archive. Removing this copy must not reach the service.
    if (!person.voiceId || person.voiceIsShared) {
      await store.deletePerson(person); popTo(0); return;
    }
    busy.classList.remove("hidden");
    try {
      await Voice.deleteVoice(person.voiceId);
    } catch (e) {
      busy.classList.add("hidden");
      const message = (e instanceof ConsentMissing ? Config.unavailableMessage
        : e?.message || L("The voice could not be removed from the voice service."));
      problem.append(h("div", { class: "stack gap-xs mt-xs" },
        errorNote(message + "\n\n" + L("The voice will stay at the voice service and this app will no longer know its name, so it cannot be removed from here later.")),
        h("button", { class: "btn-quiet", onClick: async () => { await store.deletePerson(person); popTo(0); } }, L("Remove from this phone")),
        h("button", { class: "btn-quiet", onClick: () => clear(problem) }, L("Keep for now"))));
      return;
    }
    busy.classList.add("hidden");
    await store.deletePerson(person);
    popTo(0);
  };

  return h("div", { class: "stack mt-18" },
    h("button", { class: "small", style: { textDecoration: "underline", minHeight: "var(--touch)" }, onClick: () =>
      confirmDialog({
        title: L("Delete this person?"),
        message: L("This removes their profile, original recordings, saved clips and imported books from Jaddati.") + "\n\n" +
          (person.voiceIsShared
            ? L("This person came from another family member's phone, so the voice is shared. It is left alone at the voice service — removing it here would take it from everyone who has them.")
            : person.voiceId
              ? L("The voice built for them is deleted from the voice service first. If that fails, nothing here is removed, so you can try again.")
              : L("Nothing was ever sent to the voice service for this person.")),
        confirm: L("Delete permanently"), onConfirm: remove,
      }) }, L("Remove this person")),
    busy, problem);
}

/** A picture off a phone is many times larger than an 88px arch needs, and
 *  decoding one at full size is what got the iOS app killed. The decoder is
 *  told the size we want and never materialises the original. */
async function downscale(file, maxSide = 600) {
  const bitmap = await createImageBitmap(file).catch(() => null);
  if (!bitmap) return file;
  const scale = Math.min(1, maxSide / Math.max(bitmap.width, bitmap.height));
  const w = Math.round(bitmap.width * scale), hgt = Math.round(bitmap.height * scale);
  const canvas = document.createElement("canvas");
  canvas.width = w; canvas.height = hgt;
  canvas.getContext("2d").drawImage(bitmap, 0, 0, w, hgt);
  bitmap.close?.();
  return new Promise(r => canvas.toBlob(b => r(b || file), "image/jpeg", 0.85));
}

setRenderer(paintRoot);

export { openAddPerson, openSettings, openPrivacy, unavailableNote, demoBanner, downscale };

store.init().then(render).catch(() => render());

// ── one voice, the whole family ─────────────────────────────────────────
// The voice lives at the voice service, not on this phone, so handing another
// family member the identifier lets them speak in it immediately — without
// paying to clone her twice or taking a second voice slot for the same person.

function handoffRow(person) {
  const busy = h("span", { class: "caption hidden" }, L("Preparing…"));

  const give = h("button", {
    class: "btn-quiet",
    onClick: async () => {
      busy.classList.remove("hidden");
      try {
        const { file, carried, leftBehind } = await Archive.export(person.id);
        const blob = new Blob([JSON.stringify(file)], { type: "application/json" });
        const url = URL.createObjectURL(blob);
        const a = h("a", {
          href: url,
          download: (person.name || "jaddati").replace(/[^\w؀-ۿ -]/g, "") + ".jaddati.json",
        });
        document.body.append(a); a.click(); a.remove();
        // Revoked on the next turn of the loop: revoking immediately can beat
        // the browser to starting the download.
        setTimeout(() => URL.revokeObjectURL(url), 10000);
        busy.classList.add("hidden");
        toast(leftBehind
          ? L("Sent without some recordings — the file would have been too large.")
          : carried ? L("Ready to send.") : L("Ready to send. No original recordings were included."));
      } catch (e) {
        busy.classList.add("hidden");
        toast(e?.message || L("Something went wrong. Try again."));
      }
    },
  }, L("Give this to the family"));

  return h("div", { class: "stack mt-18", style: { gap: "6px" } },
    h("div", { class: "divider" }),
    h("div", { class: "label mt-16" }, L("One voice, the whole family")),
    h("p", { class: "caption", style: { margin: 0 } },
      L("Make a file another family member can open on their own phone. It carries this person, your notes, anything still sealed, and the recreated voice itself — so they can hear them straight away without making the voice a second time.")),
    h("p", { class: "small", style: { margin: 0 } },
      L("Clips already created are not included. They can be made again on the other phone.")),
    give, busy);
}

function importPersonRow() {
  const input = h("input", { type: "file", accept: ".json,application/json", class: "hidden",
    onChange: async e => {
      const f = e.target.files?.[0];
      e.target.value = "";
      if (!f) return;
      try {
        const result = await Archive.import(await f.text());
        nav.personId = result.person.id;
        // Say what actually arrived. "Brought in Teta" while the irreplaceable
        // original recordings silently failed is the wrong thing to tell a
        // family, and the one thing they cannot find out later.
        const lost = result.recordingsOffered - result.restored;
        toast(!result.saved
          ? (store.storageError || L("Changes could not be saved."))
          : lost > 0
            ? L("Brought in") + " " + result.person.name + " — " +
              L("some original recordings could not be saved.")
            : L("Brought in") + " " + result.person.name);
        render();
      } catch (err) {
        toast(err instanceof ArchiveError ? err.message : L("That file could not be read."));
      }
    } });

  return h("div", { class: "stack", style: { gap: "6px" } },
    input,
    h("button", { class: "btn-outline", onClick: () => input.click() },
      icon("plus"), h("span", {}, L("Bring someone from another phone"))));
}

export { handoffRow, importPersonRow };
