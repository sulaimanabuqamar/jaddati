// Screens and navigation. The structure follows the app: People, Saved and
// Books are the three places you can be, the rail is visible from all of them,
// and Saved and Books are scoped to one person because a pile of clips with no
// name on it is not an archive.

import { L, isAr, isArabicText, dirOf, Counts, state as lang, setLang, toggleLang } from "./strings.js?v=d12ee3c9ab";
import {
  store, Consent, ConsentMissing, Config, Voice, Companion, VoiceError, CompanionError,
  Intent, INTENTS, ContentProvenance, TUNING, sameTuning, presetName,
  AFFIRMATIONS, STORIES, makeBook, ImportError, isDemoVoice, uuid, blobURL,
  STOCK_VOICE_URL, STOCK_LLM_URL, Archive, ArchiveError, Cloud, CloudError,
} from "./core.js?v=d12ee3c9ab";
import {
  h, clear, bidi, icon, appBar, globeButton, headline, eyebrow, sectionLabel,
  subtext, caption, panel, panelS, errorNote, emptyHint, avatar, breadcrumb,
  sourceBadge, contentBadge, badgesFor, audioRow, player, confirmDialog, sheet,
  toast, Recorder, durationOf, demoDuration, track, unmountAll,
} from "./ui.js?v=d12ee3c9ab";
import { nav, remember, setRenderer, render, push, pop, popTo, goTab } from "./nav.js?v=d12ee3c9ab";
import { appearance } from "./prefs.js?v=d12ee3c9ab";
import {
  createScreen, booksScreen, readerScreen, memoriesScreen, playerScreen, openAddVoice,
  personHasVoice, lettersScreen, captureScreen,
} from "./screens.js?v=d12ee3c9ab";

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
    : nav.tab === "letters" ? allLettersScreen()
    : nav.tab === "you" ? youScreen()
    : homeScreen();
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

/** Every tab works from a cold start now, so the rail carries no dead ends.
 *  Letters is the one thing in the app that is about a DATE rather than about
 *  a person, which is exactly why it earns a place of its own: a sealed letter
 *  whose day has come has to find you without your remembering whose it was. */
function tabRail() {
  const due = store.people.reduce((n, p) => n + store.dueLetters(p.id).length, 0);
  const tabs = [["people", L("People"), "house"], ["letters", L("Letters"), "lock"], ["you", L("You"), "person"]];
  return h("nav", { class: "tabrail" }, tabs.map(([key, title, ic]) =>
    h("button", {
      "aria-selected": String(nav.tab === key), onClick: () => goTab(key),
    },
      h("span", { class: "tabrail__icon" }, icon(ic),
        key === "letters" && due ? h("span", { class: "tabrail__dot" }) : null),
      h("span", {}, title))));
}

/// True while a backup or restore is running.
///
/// Those loops write to the store as they go — setting a person's cloud key —
/// and every write fires "change", which used to rebuild the whole tree from
/// under them. The spinner vanished mid-run, the button became clickable
/// again, and a second tap wrote a SECOND Drive file for the same person. The
/// screen repaints once at the end instead.
let cloudBusy = false;
export const setCloudBusy = on => { cloudBusy = on; };

store.addEventListener("change", () => {
  if (cloudBusy) return;
  if (!document.querySelector(".sheet-scrim")) render();
});
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
    h("div", { style: { fontSize: "11px", fontWeight: "600", textTransform: "uppercase", letterSpacing: isAr() ? "0" : ".6px", color: "var(--wine-ink)" } }, title),
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
      h("span", { style: { width: "4px", height: "4px", borderRadius: "50%", background: "var(--wine-ink)", marginTop: "8px", flex: "none" } }),
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
    // The key moved to You. An unlabelled key on the first screen of the app
    // asked a first-time user to wonder what it wanted from them.
    h("header", { class: "appbar" }, h("div", { class: "grow" }), globeButton()),

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
            h("div", { style: { marginTop: "4px" } }, importPersonRow()))));
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

// ── letters, across everyone ────────────────────────────────────────────
// The only part of this app that is about a DATE rather than about a person.
// A letter whose day has come has to find you without your having remembered
// whose it was, which is why it earns a tab instead of sitting one level down
// inside whichever person you happened to open.

function allLettersScreen() {
  const dateLine = iso => new Date(iso).toLocaleDateString(isAr() ? "ar" : "en", { dateStyle: "medium" });

  const due = [], sealed = [];
  for (const p of store.people) {
    for (const l of store.dueLetters(p.id)) due.push([p, l]);
    for (const l of store.sealedLetters(p.id)) sealed.push([p, l]);
  }
  const soonest = (a, b) => new Date(a[1].deliverAt) - new Date(b[1].deliverAt);
  due.sort(soonest); sealed.sort(soonest);

  const row = (entry, isDue) => {
    const [person, letter] = entry;
    return h("button", {
      class: "feature-row",
      onClick: () => { nav.personId = person.id; push(lettersScreen, { personId: person.id }); },
    },
      avatar(person, 40),
      h("span", { class: "grow stack", style: { gap: "3px", textAlign: "start" } },
        bidi(letter.occasion || L("A letter"), { class: "feature-row__title" }),
        h("span", { class: "caption" }, person.name + " · " + dateLine(letter.deliverAt))),
      isDue ? h("span", { class: "badge badge--orig" }, L("Ready"))
            : icon("lock"));
  };

  const body = !store.people.length
    ? h("div", {},
        emptyHint("lock", L("No letters yet"), L("Words you seal now and hear on a day you choose.")),
        h("button", { class: "btn-quiet", onClick: () => goTab("people") }, L("Go to People")))
    : !due.length && !sealed.length
      ? emptyHint("lock", L("No letters yet"),
          L("Open someone and write words for a day that has not come yet."))
      : h("div", { class: "stack" },
          due.length ? h("div", { class: "mt-22" }, sectionLabel(L("Waiting for you"))) : null,
          ...due.map(e => row(e, true)),
          sealed.length ? h("div", { class: "mt-22" }, sectionLabel(L("Sealed"))) : null,
          ...sealed.map(e => row(e, false)));

  return h("div", { class: "screen" },
    appBar(L("Letters"), { trailing: globeButton() }),
    h("div", { class: "scroll" }, body));
}

/// Language as its own screen, reached from You.
///
/// A row that silently flipped the language the instant it was touched gave
/// no sense of what the choice even was. A list shows both, marks the one in
/// use, and makes the change a thing you pick rather than a thing that
/// happens to you. No confirmation here — coming to this screen IS the
/// deliberate act; the globe in the corner is the one that has to ask.
function languageScreen() {
  const current = isAr() ? "ar" : "en";

  const row = (name, code) => h("button", {
    class: "feature-row",
    "aria-current": code === current ? "true" : null,
    onClick: () => {
      if (code === current) return;
      setLang(code);
      window.dispatchEvent(new Event("jaddati:lang"));
    },
  },
    h("span", { class: "grow stack", style: { gap: "3px", textAlign: "start" } },
      h("span", { class: "feature-row__title" }, name)),
    code === current ? icon("check") : null);

  return h("div", { class: "screen" },
    // No globe here: it would be a second, quieter control for the one thing
    // this screen exists to do.
    appBar(L("Language"), { onBack: pop, trailing: h("div", { class: "iconbtn" }) }),
    h("div", { class: "scroll" },
      // No section label: the bar already says Language, and saying it twice
      // on a screen with two rows on it is noise.
      h("div", { class: "mt-16" }),
      row("English", "en"),
      h("div", { class: "divider" }),
      row("العربية", "ar"),
      h("div", { class: "mt-16" },
        subtext(L("Arabic lays the whole app out right to left.")))));
}

// ── you ─────────────────────────────────────────────────────────────────
// Everything that is about the app rather than about a person. There was no
// settings screen at all before: the key lived behind an unlabelled icon on
// the home screen and privacy behind a row at the bottom of it.

function youScreen() {
  const row = (ic, title, note, onClick) =>
    h("button", { class: "feature-row", onClick },
      h("span", { class: "feature-row__icon" }, icon(ic)),
      h("span", { class: "grow stack", style: { gap: "3px", textAlign: "start" } },
        h("span", { class: "feature-row__title" }, title),
        h("span", { class: "caption" }, note)),
      icon("chevron", isAr() ? "flip" : null));

  return h("div", { class: "screen" },
    appBar(L("You")),
    h("div", { class: "scroll" },
      Config.isDemo ? h("div", { class: "mt-16" }, demoBanner()) : null,
      store.storageError ? h("div", { class: "mt-16" }, errorNote(store.storageError)) : null,

      h("div", { class: "mt-16" }, sectionLabel(L("This app"))),
      row("globe", L("Language"), isAr() ? "العربية" : "English",
        () => push(languageScreen, {})),
      h("div", { class: "divider" }),

      row(Consent.allowsNetwork ? "unlock" : "lock", L("Privacy and data"),
        Consent.allowsNetwork ? L("Two services outside this phone are in use.")
                              : L("Everything is being kept on this phone."),
        () => openPrivacy(true)),
      h("div", { class: "divider" }),

      // A switch, not a row that opens something: there are two states and
      // the control should BE the answer rather than lead to it.
      h("label", { class: "switch", style: { paddingBlock: "10px" } },
        h("input", {
          type: "checkbox", checked: appearance.isDark,
          onChange: e => { appearance.set(e.target.checked); render(); },
        }),
        h("span", { class: "grow stack", style: { gap: "3px" } },
          h("span", { class: "feature-row__title" }, L("Dark mode")),
          h("span", { class: "caption" }, L("The app opens light. This keeps it dark.")))),
      h("div", { class: "divider" }),
      row("key", L("Voice service"), L("Leave as it is unless you run a relay of your own."),
        openSettings),

      cloudSection(),

      h("div", { class: "quiet-divider" }),
      h("div", { class: "stack", style: { gap: "6px" } },
        h("div", { class: "row between", style: { alignItems: "baseline" } },
          h("span", { class: "serif", style: { fontSize: "26px" } }, "Jaddati"),
          h("span", { class: "serif wine-text", dir: "rtl", style: { fontSize: "22px" } }, "جدّتي")),
        subtext(L("A place for a familiar voice.")),
        h("div", { class: "row gap-s", style: { marginTop: "8px" } }, icon("seal"),
          h("span", { class: "small" }, L("Original and recreated. Always distinct."))))));
}


/// Backing your own people up to your own Drive.
///
/// Hidden entirely until the relay has a client id: an unfinished setup must
/// not put a dead button in front of anyone.
///
/// The sentence about this NOT being how you share matters more than it
/// looks. "Sign in with Google" next to "give this to the family" reads like
/// the same thing, and someone who believes their sister can now see the
/// archive will not find out they were wrong until they need it.
function cloudSection() {
  // Asked the first time someone opens You, not at every cold start. Whether
  // Google is configured matters only on this screen, and making every launch
  // pay for a network round trip — one that fails loudly with no connection —
  // to answer a question most people never ask is the wrong trade.
  if (Cloud.isUnknown) {
    Cloud.configured().then(known => { if (known) render(); });
    return null;
  }
  if (!Cloud.isConfigured) return null;

  const note = h("div", {});
  const busy = h("div", {});

  const run = (label, work) => h("button", {
    class: "btn-quiet",
    onClick: async e => {
      const b = e.currentTarget;
      // Raised first and cleared in a finally that covers everything after it.
      // Set outside the try, a throw while building the spinner would strand
      // the flag and leave the app unable to repaint for the rest of the
      // session.
      setCloudBusy(true);
      try {
        b.disabled = true; clear(note); clear(busy);
        busy.append(h("div", { class: "row gap-s mt-xs" }, h("span", { class: "spinner" }),
          h("span", { class: "caption" }, L("Working…"))));
        note.append(h("p", { class: "caption sage-text", style: { margin: 0 } }, await work()));
      } catch (err) {
        note.append(errorNote(err instanceof CloudError ? err.message
          : L("That did not work. Try again.")));
      } finally {
        setCloudBusy(false);
        b.disabled = false;
        clear(busy);
      }
      // Deliberately NOT a render() here. Repainting would rebuild this whole
      // section and throw away the note the result was just written into —
      // which is the bug the restore path already had once. The result is
      // toasted as well, so it survives whatever repaints later.
    },
  }, label);

  const signedIn = Cloud.isSignedIn;

  return h("div", { class: "stack", style: { gap: "8px" } },
    h("div", { class: "quiet-divider" }),
    sectionLabel(L("Backup")),
    h("p", { class: "caption", style: { margin: "8px 0 0" } },
      L("Keep a copy of the people you hold here in your own Google Drive, so a lost phone is not a lost voice.")),
    h("p", { class: "small", style: { margin: 0 } },
      L("This is not how you give someone to the family — that is the code on their Setup screen. A backup goes to your Drive and nobody else's.")),

    signedIn
      ? h("div", { class: "stack", style: { gap: "8px" } },
          h("div", { class: "row gap-s" }, icon("check"),
            h("span", { class: "caption" }, Cloud.email || L("Signed in"))),
          // Every person who did not make it has to be accounted for here.
          // "Backed up." over a silent failure is worse than no backup at
          // all, because it is the sentence someone remembers when they go
          // looking a year later and find nothing.
          run(L("Back up now"), async () => {
            const { sent, skipped, atRisk, failed } = await Cloud.backUp();
            // "Backed up. 0" over a run where every single upload was refused
            // is the sentence someone remembers a year later. `failed` is a
            // counter like the others and has to be said out loud like them.
            const lines = sent > 0
              ? [L("Backed up.") + " " + Counts.number(sent)]
              : [L("Nothing was backed up.")];
            if (skipped) lines.push(L("Some were too large and were left out."));
            if (atRisk) lines.push(L("Some recordings could not be read, so those people were left as they were rather than overwritten."));
            if (failed) lines.push(L("Some could not be sent to Drive. Try again in a moment."));
            const said = lines.join(" ");
            toast(said);
            return said;
          }),
          run(L("Bring everything back"), async () => {
            const { brought, failed, already } = await Cloud.restore();
            const lines = [L("Brought back.") + " " + Counts.number(brought)];
            if (already) lines.push(L("Some were already here and were left alone."));
            if (failed) lines.push(L("Some could not be read and were left in Drive."));
            const said = lines.join(" ");
            // Said in a toast, not in the note below the button. Bringing
            // people back changes the screen, so render() rebuilds this whole
            // tree — and the note the result was being written into had
            // already been thrown away by the time it was written. The result
            // of the restore was never once displayed.
            toast(said);
            render();
            return said;
          }),
          h("button", { class: "small", style: { textDecoration: "underline", minHeight: "var(--touch)" },
            onClick: () => { Cloud.signOut(); render(); } }, L("Sign out of Google")))
      : h("button", { class: "btn-quiet", onClick: async () => {
          try { await Cloud.beginSignIn(); }
          catch (err) { clear(note); note.append(errorNote(err.message)); }
        } }, L("Sign in with Google")),

    busy, note);
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
      : hasVoice ? [L("Recreated voice ready"), "var(--wine-ink)"]
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
    appBar(person.name, { onBack: pop, trailing:
      // The class is the stable handle: the label is translated, so anything
      // keying on "Setup" finds nothing the moment the app is in Arabic.
      h("button", { class: "iconbtn setup-btn", onClick: () => push(setupScreen, { personId: person.id }),
                    "aria-label": L("Setup") }, icon("gear")) }),
    h("div", { class: "scroll" },
      photoInput,

      // Centred, because this screen now has one thing to say and one thing to
      // offer. Left-aligned was right when it was a header above a list of
      // seven rows. It is not a header any more.
      h("div", { class: "person-hero" },
        h("button", { class: "person-hero__photo", onClick: () => photoInput.click(),
          "aria-label": person.photoFilename ? L("Change photo") : L("Add photo") },
          avatar(person, 104),
          h("span", { class: "person-hero__edit" }, person.photoFilename ? "✎" : "+")),
        bidi(person.name, { class: "serif person-hero__name" }),
        person.relationship ? bidi(person.relationship, { class: "caption" }) : null,
        voiceTag()),

      !Config.isConfigured ? h("div", { class: "mt-21" }, unavailableNote()) : null,

      primaryAction(person, { hasVoice, placeholder, pending }),

      // The sweep is announced when the voice is CREATED, which is the wrong
      // moment: ten minutes later you are back on this screen wondering where
      // she went. It belongs where the disappearance is noticed. Only on the
      // shared relay — a phone using its own key keeps its voices.
      hasVoice && Config.usesRelayVoice && !Config.isDemo
        ? h("p", { class: "caption amber-text", style: { margin: "14px 0 0", textAlign: "center" } },
            L("Voices made here are removed automatically about every ten minutes, so that everyone seeing the demonstration gets a turn. The recording you add stays on this device."))
        : null,

      hasVoice ? personCards(person) : null));
}

/** One button, and which button depends entirely on where this person is.
 *
 *  The screen used to show all four voice states' worth of copy plus seven
 *  things to do, and a first-time user had to read the lot to work out which
 *  one applied to them. There is only ever one sensible next move here, so
 *  that is the only one offered. */
function primaryAction(person, { hasVoice, placeholder, pending }) {
  const wrap = (button, note, extra) =>
    h("div", { class: "primary-action" }, button,
      note ? h("p", { class: "primary-action__note" }, note) : null, extra || null);

  if (placeholder) {
    return wrap(
      h("button", { class: "btn-primary", onClick: () => openAddVoice(person.id) }, L("Create a real voice")),
      L("Created in offline test mode. This is not a usable voice."));
  }

  if (pending) {
    const note = h("div", {});
    const btn = h("button", { class: "btn-primary", onClick: async () => {
      btn.disabled = true; btn.textContent = L("Checking…"); clear(note);
      try {
        // There is no "is it ready" endpoint. The only honest test is to use
        // the voice: if the service speaks, it is available.
        await Voice.synthesize(L("Hello"), person.voiceId, Config.defaultModelId, person.tuning || TUNING.natural);
        store.updatePerson({ ...person, voiceRequiresVerification: false });
      } catch (e) {
        btn.disabled = false; btn.textContent = L("Check if it is ready");
        note.append(h("p", { class: "caption danger", style: { margin: 0 } },
          e instanceof ConsentMissing ? Config.unavailableMessage
            : (e?.message || L("The service has not made this voice available yet."))));
      }
    } }, L("Check if it is ready"));
    return wrap(btn, L("The voice has been created, but the service has not made it available yet."), note);
  }

  if (!hasVoice) {
    // Capturing someone who is still alive is the one other thing worth
    // offering here, and it matters MOST before a voice exists — which is
    // exactly when it used to be buried furthest down the screen.
    return wrap(
      h("button", { class: "btn-primary", onClick: () => openAddVoice(person.id) }, L("Add their voice")),
      L("About a minute. One voice. A quiet room."),
      h("button", { class: "primary-action__aside", onClick: () => push(captureScreen, { personId: person.id }) },
        icon("mic"), h("span", {}, L("They are still here? Record them now"))));
  }

  return wrap(
    h("button", { class: "btn-primary", onClick: () =>
      push(createScreen, { personId: person.id, intent: "saySomething" }) }, L("Say something")),
    L("Type the words. Hear them in their voice."));
}

/** Three cards, not seven rows. Each one is a place, and each says how much is
 *  in it so nobody has to open an empty room to find out it is empty. */
function personCards(person) {
  const kept = store.keptClips(person.id).length;
  const books = store.booksFor(person.id).length;
  const due = store.dueLetters(person.id).length;
  const sealed = store.sealedLetters(person.id).length;

  const card = (ic, title, note, onClick, badge) =>
    h("button", { class: "bigcard", onClick },
      h("span", { class: "bigcard__icon" }, icon(ic),
        badge ? h("span", { class: "bigcard__badge" }, String(badge)) : null),
      h("span", { class: "bigcard__title" }, title),
      h("span", { class: "bigcard__note" }, note));

  return h("div", { class: "cardgrid" },
    card("tray", L("Saved"), kept ? Counts.savedClips(kept) : L("Nothing saved yet"),
      () => push(memoriesScreen, { personId: person.id })),
    card("book", L("Books"), books ? Counts.books(books) : L("Bring them a text"),
      () => push(booksScreen, { personId: person.id })),
    card(due ? "unlock" : "lock", L("Letters"),
      due ? L("Waiting for you") : sealed ? Counts.sealed(sealed) : L("For a day you choose"),
      () => push(lettersScreen, { personId: person.id }), due || null));
}

/** Everything you do once: give them a voice, record them while you still can,
 *  hand the archive to the family, remove them.
 *
 *  All of this used to sit inline on the person screen, which meant the rare
 *  and the daily competed for the same attention every time you opened
 *  someone. Behind a gear it is still one tap away and no longer in the way. */
function setupScreen({ personId }) {
  const person = store.person(personId);
  if (!person) return h("div", { class: "screen" }, appBar(L("Setup"), { onBack: pop }),
    h("div", { class: "scroll" }, emptyHint("personSlash", L("No people yet"),
      L("A place for voices you want to keep."))));

  const originals = store.assetsFor(person.id, "original");
  const hasVoice = personHasVoice(person);

  const row = (ic, title, note, onClick) =>
    h("button", { class: "feature-row", onClick },
      h("span", { class: "feature-row__icon" }, icon(ic)),
      h("span", { class: "grow stack", style: { gap: "3px", textAlign: "start" } },
        h("span", { class: "feature-row__title" }, title),
        h("span", { class: "caption" }, note)),
      icon("chevron", isAr() ? "flip" : null));

  return h("div", { class: "screen" },
    appBar(L("Setup"), { onBack: pop }),
    h("div", { class: "scroll" },
      h("div", { class: "mt-16" }, sectionLabel(L("Their voice"))),
      row("waveform", hasVoice ? L("Replace their voice") : L("Add their voice"),
        L("About a minute. One voice. A quiet room."), () => openAddVoice(person.id)),
      h("div", { class: "divider" }),
      row("mic", L("Recorded before it is needed"),
        L("Ask for the recording while they are still here to give it"),
        () => push(captureScreen, { personId: person.id })),

      h("div", { class: "quiet-divider" }),
      sectionLabel(L("Original recordings")),
      originals.length
        ? originals.map(a => track(audioRow(a, asset => push(playerScreen, { assetId: asset.id }))))
        : h("div", { style: { marginTop: "10px" } }, subtext(L("No recordings yet"))),

      person.photoFilename
        ? h("button", { class: "small", style: { marginTop: "18px", textAlign: "start", textDecoration: "underline", minHeight: "var(--touch)" },
            onClick: () => store.removePhoto(person) }, L("Remove photo"))
        : null,

      personFooter(person)));
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

// Startup, in the order the screen needs it.
//
// completeSignIn runs before the first paint because Google sends the browser
// back to this page with ?code= in the address bar, and a used code left in
// the URL gets spent a second time on the next refresh.
store.init()
  .then(async () => {
    // Before the first paint, because Google sends the browser back here with
    // ?code= in the address bar and a used code left in the URL gets spent a
    // second time on the next refresh.
    try { await Cloud.completeSignIn(); }
    catch (e) { console.warn("sign-in did not complete", e); }
  })
  .catch(() => {})
  .finally(render);

// ── one voice, the whole family ─────────────────────────────────────────
// The voice lives at the voice service, not on this phone, so handing another
// family member the identifier lets them speak in it immediately — without
// paying to clone her twice or taking a second voice slot for the same person.

function handoffRow(person) {
  const busy = h("span", { class: "caption hidden" }, L("Preparing…"));
  const out = h("div", {});

  const asFile = async () => {
    const { file, carried, leftBehind } = await Archive.export(person.id);
    const blob = new Blob([JSON.stringify(file)], { type: "application/json" });
    const url = URL.createObjectURL(blob);
    const a = h("a", {
      href: url,
      download: (person.name || "jaddati").replace(/[^\w؀-ۿ -]/g, "") + ".jaddati.json",
    });
    document.body.append(a); a.click(); a.remove();
    // Revoked on the next turn of the loop: revoking immediately can beat the
    // browser to starting the download.
    setTimeout(() => URL.revokeObjectURL(url), 10000);
    toast(leftBehind
      ? L("Sent without some recordings — the file would have been too large.")
      : carried ? L("Ready to send.") : L("Ready to send. No original recordings were included."));
  };

  const give = h("button", {
    class: "btn-quiet",
    onClick: async () => {
      clear(out);
      busy.classList.remove("hidden");
      give.disabled = true;
      try {
        const { code, carried, leftBehind } = await Archive.send(person.id);
        // The file path has always said what actually travelled. This one
        // threw the counts away, so a family could be handed a code for an
        // archive with none of the recordings in it and told nothing — and
        // the recordings are the part that cannot be made again.
        const missing = leftBehind > 0
          ? L("Sent without some recordings — they would have made it too large.")
          : carried === 0 ? L("No original recordings were included.") : "";
        out.append(h("div", { class: "codecard" },
          h("div", { class: "caption" }, L("Read them this:")),
          h("div", { class: "code" }, code),
          h("div", { class: "small" }, L("They open Jaddati, choose Bring someone from another phone, and type it.")),
          h("div", { class: "small" }, L("The code works for a day.")),
          missing ? h("div", { class: "small amber-text" }, missing) : null));
      } catch (e) {
        out.append(errorNote(e?.message || L("Something went wrong. Try again.")));
      } finally {
        busy.classList.add("hidden");
        give.disabled = false;
      }
    },
  }, L("Give this to the family"));

  // Still here, and not buried: a code needs the internet and has a size
  // ceiling the file does not. When either of those bites, this is the answer,
  // and someone who has just been told "too large" should not have to go
  // looking for it.
  const file = h("button", {
    class: "small", style: { textDecoration: "underline", minHeight: "var(--touch)" },
    onClick: async () => {
      clear(out);
      busy.classList.remove("hidden");
      try { await asFile(); }
      catch (e) { out.append(errorNote(e?.message || L("Something went wrong. Try again."))); }
      finally { busy.classList.add("hidden"); }
    },
  }, L("Save it as a file instead"));

  return h("div", { class: "stack mt-18", style: { gap: "6px" } },
    h("div", { class: "divider" }),
    h("div", { class: "label mt-16" }, L("One voice, the whole family")),
    h("p", { class: "caption", style: { margin: 0 } },
      L("Give another family member a short code. It carries this person, your notes, anything still sealed, and the recreated voice itself — so they can hear them straight away without making the voice a second time.")),
    h("p", { class: "small", style: { margin: 0 } },
      L("Clips already created are not included. They can be made again on the other phone.")),
    give, busy, out, file);
}

function importPersonRow() {
  // Kept, but no longer the front door. A file is still the only way in when
  // the archive is too big for a code or there is no connection.
  const input = h("input", { type: "file", accept: ".json,application/json", class: "hidden",
    onChange: async e => {
      const f = e.target.files?.[0];
      e.target.value = "";
      if (!f) return;
      try { arrived(await Archive.import(await f.text())); }
      catch (err) { toast(err instanceof ArchiveError ? err.message : L("That file could not be read.")); }
    } });

  /// Say what actually arrived. "Brought in Teta" while the irreplaceable
  /// original recordings silently failed is the wrong thing to tell a family,
  /// and the one thing they cannot find out later.
  const arrived = result => {
    nav.personId = result.person.id;
    const lost = result.recordingsOffered - result.restored;
    toast(!result.saved
      ? (store.storageError || L("Changes could not be saved."))
      : lost > 0
        ? L("Brought in") + " " + result.person.name + " — " +
          L("some original recordings could not be saved.")
        : L("Brought in") + " " + result.person.name);
    render();
  };

  const openCode = () => sheet(close => {
    const field = h("input", {
      type: "text", inputmode: "latin", autocapitalize: "characters",
      autocomplete: "off", spellcheck: "false", placeholder: "K7M2Q4",
      style: { textAlign: "center", letterSpacing: "6px", fontSize: "26px",
               fontFamily: "var(--serif)", textTransform: "uppercase" },
    });
    const problem = h("div", {});
    const bring = h("button", { class: "btn-primary", disabled: true }, L("Bring them in"));

    // Read aloud, so accept it typed back however it arrives — spaces,
    // lower case, the lot.
    const tidy = () => field.value.toUpperCase().replace(/[^A-Z0-9]/g, "");
    field.addEventListener("input", () => { bring.disabled = tidy().length !== 6; clear(problem); });

    bring.onclick = async () => {
      bring.disabled = true;
      bring.textContent = L("Looking…");
      clear(problem);
      try {
        const result = await Archive.fetchByCode(tidy());
        close();
        arrived(result);
      } catch (err) {
        bring.disabled = false;
        bring.textContent = L("Bring them in");
        problem.append(errorNote(err instanceof ArchiveError ? err.message
          : L("That code could not be checked. Try again.")));
      }
    };

    return h("div", { class: "screen" },
      appBar(L("Bring someone from another phone"), {
        trailing: h("button", { class: "iconbtn", onClick: close, "aria-label": L("Cancel") }, icon("close")),
      }),
      h("div", { class: "scroll" },
        h("div", { class: "stack gap-m" },
          subtext(L("On the phone that has them, open that person, tap the gear, and choose Give this to the family. Type the code it shows here.")),
          h("label", { class: "field" },
            h("div", { class: "field__title" }, L("Their code")), field),
          problem,
          bring,
          h("div", { class: "divider mt-16" }),
          h("button", { class: "small", style: { textDecoration: "underline", minHeight: "var(--touch)" },
            onClick: () => { close(); input.click(); } },
            L("Bring them in from a file instead")))));
  });

  return h("div", { class: "stack", style: { gap: "6px" } },
    input,
    h("button", { class: "btn-outline", onClick: openCode },
      icon("plus"), h("span", {}, L("Bring someone from another phone"))));
}

export { handoffRow, importPersonRow };
