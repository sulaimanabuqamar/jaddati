// Compose, shelf, reader, archive, player — and the one screen the whole
// product rests on, where a voice is created.

import { L, isAr, isArabicText, dirOf, Counts } from "./strings.js";
import {
  store, Consent, ConsentMissing, Config, Voice, Companion,
  Intent, INTENTS, TUNING, sameTuning, presetName,
  AFFIRMATIONS, STORIES, makeBook, ImportError, isDemoVoice, blobURL, DEMO_PREFIX,
  FamilyAnswer, Translator, NotInNotesError, CAPTURE_PROMPTS,
} from "./core.js";
import {
  h, clear, bidi, icon, appBar, headline, eyebrow, sectionLabel, subtext,
  panel, panelS, errorNote, emptyHint, avatar, breadcrumb, sourceBadge,
  contentBadge, badgesFor, audioRow, player, confirmDialog, sheet, toast,
  Recorder, durationOf, demoDuration, track,
} from "./ui.js";
import { nav, push, pop, popTo, render } from "./nav.js";

const trimmedOf = s => (s || "").trim();

/** Ready to speak. Stricter than "a voice id exists": a voice can exist and
 *  still be unusable, and claiming otherwise produces a profile that says
 *  "Voice ready" while every generation fails. */
export function personHasVoice(person) {
  if (!person?.voiceId) return false;
  if (person.voiceRequiresVerification === true) return false;
  if (isDemoVoice(person.voiceId) && !Config.isDemo) return false;
  return true;
}

/** Whatever the provider returned, stored with the right extension. */
async function keepAudio(result, opts) {
  if (result.demo) {
    return store.storeAudio(null, { ...opts, demo: true, duration: demoDuration(result.text) });
  }
  const duration = await durationOf(result.blob);
  return store.storeAudio(result.blob, { ...opts, duration, fileExtension: "mp3" });
}

// ── adding a voice ──────────────────────────────────────────────────────
// The consent step is not decoration. The provider requires the uploader to
// hold the rights to the voice, and this product is about someone who cannot
// be asked. The wording says exactly that.

export function openAddVoice(personId) {
  sheet(close => {
    const person = store.person(personId);
    const replacing = !!person?.voiceId;

    let picked = null;              // { blob, name, seconds }
    let rights = false, synthetic = false, working = false;

    const fileInput = h("input", { type: "file", accept: "audio/*", class: "hidden", onChange: async e => {
      const f = e.target.files?.[0]; if (!f) return;
      const seconds = await durationOf(f);
      picked = { blob: f, name: f.name, seconds };
      e.target.value = ""; sync();
    } });

    const fileName = h("div", { class: "caption" }, L("No recording chosen"));
    const fileNote = h("div", { class: "small" }, "");

    // A bar that moves is the only honest signal that the microphone is
    // actually capturing. A spinner would look identical over silence.
    const meterFill = h("i");
    const clockEl = h("span", { class: "caption", style: { fontVariantNumeric: "tabular-nums" } }, "0:00");
    const meterRow = h("div", { class: "row gap-s hidden" }, h("div", { class: "meter" }, meterFill), clockEl);
    const hint = h("div", { class: "small hidden" }, "");

    const recorder = new Recorder();
    let recording = false;

    const recordBtn = h("button", { class: "btn-quiet", onClick: async () => {
      if (recording) {
        const out = await recorder.stop();
        recording = false;
        if (out?.blob?.size) {
          picked = { blob: out.blob, name: L("Recorded just now"), seconds: out.seconds };
        }
        sync(); return;
      }
      try {
        await recorder.start((level, elapsed) => {
          meterFill.style.width = Math.max(3, level * 100) + "%";
          clockEl.textContent = Counts.clock(elapsed);
          hint.textContent = elapsed < 60
            ? L("Keep going — about a minute is what the voice needs.")
            : L("That is enough. Stop whenever you like.");
          hint.className = "small " + (elapsed < 60 ? "amber-text" : "sage-text");
        });
        recording = true; sync();
      } catch {
        problem.textContent = L("The microphone is not available. Check the browser's permission for this page.");
      }
    } }, L("Record now"));

    const problem = h("div", { class: "caption danger" }, "");

    const toggle = (checked, words, onChange) => {
      const input = h("input", { type: "checkbox", checked, onChange: e => { onChange(e.target.checked); sync(); } });
      return h("label", { class: "switch" }, input, h("span", { style: { flex: "1" } }, words));
    };

    const submit = h("button", { class: "btn-primary", disabled: true });
    const reason = h("div", { class: "caption center" }, "");
    const errorSlot = h("div", {});

    function durationIsUnusable() { return picked && picked.seconds > 0 && picked.seconds < 20; }
    function durationIsShort() { return picked && picked.seconds > 0 && picked.seconds < 45; }

    function canSubmit() {
      return !!picked && rights && synthetic && !working && !durationIsUnusable()
        && Config.isConfigured && !store.loadFailed;
    }

    function disabledReason() {
      if (working || canSubmit()) return "";
      if (!Config.isConfigured) return "";
      if (!picked) return (rights && synthetic) ? L("Choose a recording") : L("Choose a recording, then review both permissions.");
      if (durationIsUnusable()) return L("This recording may be too short.");
      return L("Both permissions are needed before upload.");
    }

    function sync() {
      fileName.textContent = picked ? picked.name : L("No recording chosen");
      fileNote.textContent = picked && picked.seconds > 0
        ? Counts.duration(picked.seconds) + (durationIsUnusable() ? " · " + L("This recording may be too short.")
            : durationIsShort() ? " · " + L("Longer is better. About a minute.") : "")
        : "";
      meterRow.classList.toggle("hidden", !recording);
      hint.classList.toggle("hidden", !recording);
      recordBtn.textContent = recording ? L("Stop recording") : L("Record now");
      submit.disabled = !canSubmit();
      submit.textContent = working ? L("Creating voice…") : L("Create voice");
      reason.textContent = disabledReason();
    }

    async function create() {
      const p = store.person(personId);
      if (!p || !picked || working) return;
      working = true; clear(errorSlot); sync();
      try {
        const made = await Voice.createVoice(p.name || "Jaddati", picked.blob);
        // The original recording is kept too — it is the one thing here that
        // cannot be made again.
        await store.storeAudio(picked.blob, {
          personId: p.id, source: "original", text: "",
          duration: picked.seconds, isSaved: true,
          fileExtension: (picked.blob.type.includes("wav") ? "wav" : picked.blob.type.includes("mpeg") ? "mp3" : "webm"),
        });
        store.updatePerson({
          ...p, voiceId: made.id, voiceCreatedAt: new Date().toISOString(),
          voiceRequiresVerification: made.requiresVerification,
          consentConfirmedAt: new Date().toISOString(),
        });
        working = false;
        close(); render();
        toast(made.requiresVerification ? L("Voice is being prepared") : L("Recreated voice ready"));
      } catch (e) {
        working = false; sync();
        errorSlot.append(errorNote(e instanceof ConsentMissing ? Config.unavailableMessage
          : (e?.message || L("The voice could not be created. Try again."))));
      }
    }
    submit.addEventListener("click", create);

    sync();

    return h("div", { class: "screen" },
      appBar(L("Add their voice"), { trailing: h("button", { class: "iconbtn", onClick: () => { recorder.cancel(); close(); }, "aria-label": L("Cancel") }, icon("close")) }),
      h("div", { class: "scroll" }, h("div", { class: "stack gap-m" },
        headline(picked ? L("A voice deserves\ncareful permission.") : L("Begin with\na recording."), 33),

        !Config.isConfigured ? errorNote(Config.unavailableMessage) : null,

        replacing ? panel(h("div", { class: "stack gap-xs" },
          h("div", { class: "label" }, L("This person already has a voice")),
          h("p", { class: "caption", style: { margin: 0 } },
            L("This creates another voice. The previous voice is not deleted.") + " " +
            L("It keeps occupying a voice slot at the voice service until you delete it there.")))) : null,

        panel(h("div", { class: "stack gap-s" },
          fileInput,
          h("div", { class: "stack", style: { gap: "2px" } }, fileName, fileNote),
          h("div", { class: "row gap-s" },
            h("button", { class: "btn-quiet", onClick: () => fileInput.click() }, L("Choose a recording")),
            recordBtn),
          meterRow, hint, problem)),

        panel(h("div", { class: "stack gap-s" },
          h("div", { class: "serif", style: { fontSize: "22px", fontWeight: "700" } }, L("Before you create this voice")),
          h("div", { class: "stack", style: { gap: "3px" } },
            h("div", { class: "label" }, L("This recording will be uploaded to a third-party voice service.")),
            h("p", { class: "caption", style: { margin: 0 } },
              Config.isDemo
                ? L("In demo mode nothing is uploaded anywhere. The app speaks with this browser's own voice.")
                : L("The recording is sent to") + " " + Config.providerName + ". " +
                  L("It does not stay on this phone only. Deleting this person removes it from there as well."))),

          // Only on the relay: someone using their own key keeps their voices
          // until they remove them, and telling them otherwise would be a lie
          // about their own account.
          Config.usesRelayVoice && !Config.isDemo
            ? h("p", { class: "caption amber-text", style: { margin: 0 } },
                L("Voices made here are removed automatically about every ten minutes, so that everyone seeing the demonstration gets a turn. The recording you add stays on this device."))
            : null,
          h("div", { class: "stack", style: { gap: "3px" } },
            h("div", { class: "label" }, L("Voice service") + ": " + Config.providerName),
            h("p", { class: "caption", style: { margin: 0 } },
              L("If the person has died, this app requires authorization from the family or the representative responsible for granting it. Jaddati cannot verify that authorization."))),
          h("div", { class: "divider" }),
          toggle(rights, L("I have the right to use this recording and to create new speech in this voice."), v => { rights = v; }),
          toggle(synthetic, L("I understand that this creates new AI audio, not a recording of words this person actually said."), v => { synthetic = v; }))),

        errorSlot, submit, reason,
      )));
  });
}

// ── compose ─────────────────────────────────────────────────────────────

export function createScreen({ personId, intent }) {
  const person = store.person(personId);
  const limit = Intent.characterLimit(intent);

  let text = "";
  let tuning = { ...(person?.tuning || TUNING.natural) };
  let fast = false, generating = false;

  const area = h("textarea", {
    class: "textarea", rows: 4,
    placeholder: intent === "askAboutThem" ? L("What do you want to ask?")
      : intent === "bridgeLanguage" ? L("Write in either language…")
      : L("Write the words here…"),
  });
  const count = h("span", { class: "caption" }, Counts.characters(0, limit));
  const errorSlot = h("div", {});
  const reason = h("div", { class: "caption center" }, "");
  const submit = h("button", { class: "btn-primary" }, L("Create audio"));
  const saveLine = h("button", { class: "btn-quiet hidden", onClick: () => {
    const t = trimmedOf(area.value); if (!t || !person) return;
    store.addNote({ personId: person.id, text: t, kind: "affirmation" });
    toast(L("Saved")); sync();
  } }, L("Save this line"));

  // The same affordance for memories, which nothing else in the app offered.
  // "Ask about them" draws only on these, so with no way to write one down the
  // feature could only ever refuse — and its refusal pointed at this screen.
  const saveMemory = h("button", { class: "btn-quiet hidden", onClick: () => {
    const t = trimmedOf(area.value); if (!t || !person) return;
    store.addNote({ personId: person.id, text: t });
    area.value = "";
    toast(L("Kept as a memory."));
    sync();
  } }, L("Keep this as a memory"));

  function canSpeak() {
    const t = trimmedOf(area.value);
    return !!t && t.length <= limit && !generating && personHasVoice(person)
      && Config.isConfigured && !store.loadFailed;
  }

  function disabledReason() {
    const t = trimmedOf(area.value);
    if (generating || canSpeak()) return "";
    if (!Config.isConfigured) return "";
    if (isDemoVoice(person?.voiceId) && !Config.isDemo) return L("The test voice is not a real voice. Create one to continue.");
    if (!personHasVoice(person)) return L("Add a voice before creating audio.");
    if (t.length > limit) return L("Shorten the text to fit the limit.");
    if (intent === "comfort") return L("Choose a line, or write what feels right to you.");
    if (intent === "storyFiction") return L("Choose a story, or write your own.");
    if (intent === "askAboutThem") return L("Ask a question about them.");
    if (intent === "bridgeLanguage") return L("Write something to carry across.");
    return L("Type something for them to say.");
  }

  function sync() {
    const t = trimmedOf(area.value);
    count.textContent = Counts.characters(t.length, limit);
    count.className = "caption" + (t.length > limit ? " danger" : "");
    area.dir = dirOf(area.value);
    area.style.textAlign = isArabicText(area.value) ? "right" : "left";
    submit.disabled = !canSpeak();
    submit.textContent = generating
      ? (intent === "askAboutThem" ? L("Looking through the notes…")
         : intent === "bridgeLanguage" ? L("Translating…") : L("Creating audio…"))
      : (intent === "askAboutThem" ? L("Ask")
         : intent === "bridgeLanguage" ? L("Say it across") : L("Create audio"));
    reason.textContent = disabledReason();
    const already = person && store.affirmations(person.id).some(n => trimmedOf(n.text) === t);
    saveLine.classList.toggle("hidden", !(intent === "comfort" && person && t && !already));
    const kept = person && store.memories(person.id).some(n => trimmedOf(n.text) === t);
    saveMemory.classList.toggle("hidden", !(intent === "storyFromMemories" && person && t && !kept));
    quote.textContent = "$" + Math.max(t.length * 0.00011, 0.01).toFixed(2);
  }
  area.addEventListener("input", sync);

  const quote = h("span", { style: { fontSize: "14px", fontWeight: "600" } }, "$0.01");

  /**
   * What actually gets spoken.
   *
   * For most experiences it is exactly what was typed. Two of them put a step
   * in between: a question becomes an answer drawn from the family's notes, and
   * a sentence becomes its translation. Both return the SPOKEN words, because
   * that is what the clip has to be labelled with — storing the question and
   * playing the answer would leave an archive whose captions do not match its
   * audio.
   */
  async function resolve(typed, p) {
    if (intent === "askAboutThem") {
      return FamilyAnswer.answer(typed, store.memories(p.id));
    }
    if (intent === "bridgeLanguage") {
      return Translator.translate(typed);
    }
    return typed;
  }

  async function speak() {
    const p = store.person(personId);
    if (!p || !canSpeak()) return;
    generating = true; clear(errorSlot); sync();
    const typed = trimmedOf(area.value);
    let words;
    try {
      words = await resolve(typed, p);
    } catch (e) {
      generating = false; sync();
      // Not knowing is the designed outcome here, not a fault: it is what
      // stops the app inventing a grandmother nobody had. So it reads as an
      // answer rather than as an error with a retry button.
      const gentle = e instanceof NotInNotesError;
      errorSlot.append(errorNote(
        e instanceof ConsentMissing ? Config.unavailableMessage
          : (e?.message || L("Something went wrong. Try again.")),
        gentle || e instanceof ConsentMissing ? null : () => { clear(errorSlot); speak(); }));
      return;
    }
    if (!words) { generating = false; sync(); return; }
    try {
      const result = await Voice.synthesize(words, p.voiceId,
        fast ? Config.fastModelId : Config.defaultModelId, tuning);
      const asset = await keepAudio(result, {
        personId: p.id, source: "generated", text: words,
        modelId: fast ? Config.fastModelId : Config.defaultModelId,
        // The words that were typed, kept beside the words that were spoken,
        // so an answer or a translation can still be traced back to what was
        // actually asked for months later.
        provenance: intent === "storyFiction"
          ? L("These are invented stories, not memories or stories told by this person.")
          : intent === "askAboutThem" ? L("You asked:") + " " + typed
          : intent === "bridgeLanguage" ? L("You wrote:") + " " + typed
          : null,
        intent, content: Intent.defaultContent(intent), isSaved: false,
      });
      generating = false;
      if (!sameTuning(p.tuning || TUNING.natural, tuning)) store.updatePerson({ ...p, tuning });
      if (asset) push(playerScreen, { assetId: asset.id });
      else { sync(); errorSlot.append(errorNote(L("The audio arrived but could not be saved to this phone."))); }
    } catch (e) {
      generating = false; sync();
      const consent = e instanceof ConsentMissing;
      errorSlot.append(errorNote(
        consent ? Config.unavailableMessage : (e?.message || L("Something went wrong. Try again.")),
        consent ? null : () => { clear(errorSlot); speak(); }));
    }
  }
  submit.addEventListener("click", speak);

  const pick = value => { area.value = value; sync(); area.focus(); };

  // Seed the comfort screen, as the app does.
  if (intent === "comfort") area.value = isAr() ? AFFIRMATIONS[0].arabic : AFFIRMATIONS[0].english;

  const note = Intent.provenanceNote(intent);
  const shelved = intent === "storyFromMemories" ? ["storyFromMemories", "saySomething"] : [intent];
  /// What the family has written down, listed where it is written — and the
  /// only material "Ask about them" is allowed to draw on.
  const memoryList = () => {
    if (!person || intent !== "storyFromMemories") return null;
    const mine = store.memories(person.id);
    if (!mine.length) return null;
    return h("div", { class: "stack gap-s mt-s" }, h("div", { class: "divider" }),
      h("div", { class: "label" }, L("What your family has written down")),
      h("p", { class: "caption", style: { margin: 0 } },
        L("These are what an answer is built from, and nothing else is.")),
      mine.map(n => panelS(h("div", { class: "row between", style: { gap: "var(--s)" } },
        bidi(n.text, { style: { flex: "1" } }),
        h("button", {
          class: "iconbtn", "aria-label": L("Remove"),
          onClick: () => confirmDialog({
            title: L("Remove this memory?"),
            message: L("It will no longer be used to answer questions about them."),
            confirm: L("Remove"),
            onConfirm: () => { store.removeNote(n.id); render(); },
          }),
        }, icon("trash"))))));
  };

  const shelfTitle = intent === "comfort" ? L("Comfort you have kept")
    : intent === "storyFiction" ? L("Stories you have kept")
    : intent === "storyFromMemories" ? L("Words you have kept") : L("Previously kept");

  const shelf = () => {
    if (!person) return null;
    const mine = store.savedAssets(person.id, shelved);
    if (!mine.length) return null;
    return h("div", { class: "stack gap-s mt-s" }, h("div", { class: "divider" }),
      h("div", { class: "label" }, shelfTitle),
      mine.map(a => audioRow(a, asset => push(playerScreen, { assetId: asset.id }))));
  };

  const screen = h("div", { class: "screen" },
    appBar(Intent.title(intent), { onBack: pop }),
    h("div", { class: "scroll" }, h("div", { class: "stack gap-m" },
      person ? breadcrumb(person) : null,
      headline(Intent.headline(intent)),
      subtext(Intent.standfirst(intent)),
      !Config.isConfigured ? errorNote(Config.unavailableMessage) : null,
      memoryList(),
      intent === "storyFromMemories" ? shelf() : null,
      intent === "comfort" ? comfortPicker(person, pick) : null,
      intent === "storyFiction" ? fictionPicker(pick) : null,

      panel(h("div", { class: "stack gap-xs" }, area,
        h("div", { class: "row between" },
          h("span", { class: "small" }, Config.isTranscriptionConfigured ? "" : ""), count))),

      note ? h("div", { class: "row gap-xs amber-text" }, icon("info"), h("span", { class: "caption" }, note)) : null,

      h("div", { class: "row between", style: { padding: "12px 0", borderTop: "1px solid var(--hairline)" } },
        h("span", { class: "small" }, L("This clip · example quote")),
        h("span", { class: "row", style: { gap: "4px" } }, quote, h("span", { class: "small" }, L("USD")))),

      errorSlot, submit, saveLine, saveMemory, reason,

      h("label", { class: "switch switch--amber" },
        h("input", { type: "checkbox", onChange: e => { fast = e.target.checked; } }),
        h("span", { class: "caption" }, L("Faster, slightly plainer voice"))),

      tuningSection(tuning, t => { tuning = t; }),

      intent !== "storyFromMemories" ? shelf() : null,
    )));

  sync();
  return screen;
}

function comfortPicker(person, pick) {
  const mine = person ? store.affirmations(person.id) : [];
  return h("div", { class: "stack gap-s" },
    h("div", { class: "label" }, L("Choose a line")),
    mine.length ? h("div", { class: "caption amber-text" }, L("Your lines")) : null,
    mine.map(line => panelS(h("div", { class: "row row--top gap-s" },
      h("button", { class: "grow", style: { textAlign: "start" }, onClick: () => pick(line.text) },
        bidi(line.text, {})),
      h("button", { class: "iconbtn", "aria-label": L("Remove line"), onClick: () =>
        confirmDialog({ title: L("Remove this line?"), confirm: L("Remove line"),
          onConfirm: () => store.removeNote(line.id) }) }, icon("trash"))))),
    mine.length ? h("div", { class: "caption" }, L("Ready-made lines")) : null,
    AFFIRMATIONS.map(a => panelS(h("div", { class: "stack gap-xs" },
      h("button", { style: { textAlign: "start" }, onClick: () => pick(a.english) }, a.english),
      // The masthead is جدّتي — there has to be a one-tap route to Arabic, not
      // just a preview of it.
      h("button", { class: "row gap-xs amber-text", style: { textAlign: "start" }, onClick: () => pick(a.arabic) },
        h("span", { class: "caption", dir: "rtl" }, a.arabic))))));
}

function fictionPicker(pick) {
  return h("div", { class: "stack gap-s" },
    h("div", { class: "label" }, L("Choose a story")),
    STORIES.map(s => panelS(h("div", { class: "stack gap-xs" },
      h("button", { class: "stack", style: { gap: "3px", textAlign: "start" }, onClick: () => pick(s.text) },
        h("span", { class: "row between" }, h("span", { class: "label" }, s.title),
          h("span", { class: "wine-text", style: { fontSize: "11px", fontWeight: "600" } }, L("Load in English"))),
        h("span", { class: "caption", style: { display: "-webkit-box", WebkitLineClamp: "2", WebkitBoxOrient: "vertical", overflow: "hidden" } }, s.text)),
      h("div", { class: "divider" }),
      h("button", { class: "stack", style: { gap: "3px", textAlign: "end" }, onClick: () => pick(s.textArabic) },
        h("span", { class: "row between" },
          h("span", { class: "amber-text", style: { fontSize: "11px", fontWeight: "600" } }, L("Load in Arabic")),
          h("span", { class: "label" }, s.titleArabic)),
        h("span", { class: "caption", dir: "rtl", style: { display: "-webkit-box", WebkitLineClamp: "2", WebkitBoxOrient: "vertical", overflow: "hidden" } }, s.textArabic))))));
}

/** The only fine-tuning an instant clone has. The clone itself is fixed once
 *  created; what can change is how it performs. */
function tuningSection(tuning, onChange) {
  const body = h("div", { class: "stack gap-s hidden", style: { paddingTop: "var(--xs)" } });
  const name = h("span", { class: "amber-text", style: { fontSize: "11px", fontWeight: "600" } }, presetName(tuning) || "");

  const preset = (label, value) => h("button", {
    class: "grow", style: { minHeight: "34px", borderRadius: "var(--r-control)", fontSize: "12px", fontWeight: "600" },
    onClick: () => { Object.assign(tuning, value); onChange({ ...tuning }); paint(); },
  }, label);

  const presets = h("div", { class: "row gap-xs" },
    preset(L("Gentle"), TUNING.gentle), preset(L("Natural"), TUNING.natural), preset(L("Storytelling"), TUNING.storytelling));

  const slider = (title, help, key, min, max, step, format) => {
    const out = h("span", { class: "caption", style: { fontVariantNumeric: "tabular-nums" } }, format(tuning[key]));
    const input = h("input", { class: "slider", type: "range", min, max, step, value: tuning[key],
      "aria-label": title, onInput: e => { tuning[key] = parseFloat(e.target.value); out.textContent = format(tuning[key]); onChange({ ...tuning }); paint(); } });
    return h("div", { class: "stack", style: { gap: "2px" } },
      h("div", { class: "row between" }, h("span", { class: "caption" }, title), out),
      input, h("div", { class: "small" }, help));
  };

  body.append(
    sectionLabel(L("How it is spoken")), presets,
    slider(L("Steadiness"), L("More expressive") + " ↔ " + L("More steady"), "stability", 0, 1, 0.01, v => Math.round(v * 100) + "%"),
    slider(L("Likeness to the original"), L("Source quality and language both affect the result. A high likeness value is not a guarantee."), "similarity", 0, 1, 0.01, v => Math.round(v * 100) + "%"),
    slider(L("Pace"), L("Slower") + " ↔ " + L("Faster"), "speed", 0.7, 1.2, 0.01, v => v.toFixed(2) + "×"),
    h("div", { class: "caption" }, L("Results may differ from the original recording.")));

  function paint() {
    name.textContent = presetName(tuning) || "";
    [...presets.children].forEach((b, i) => {
      const values = [TUNING.gentle, TUNING.natural, TUNING.storytelling][i];
      const on = sameTuning(tuning, values);
      b.style.background = on ? "var(--wine)" : "var(--sunk)";
      b.style.color = on ? "var(--paper)" : "var(--wine)";
    });
  }
  paint();

  const toggle = h("button", { class: "row between", style: { width: "100%", minHeight: "var(--touch)" },
    onClick: () => body.classList.toggle("hidden") },
    h("span", { class: "row gap-xs" }, h("span", { class: "caption" }, L("Voice delivery")), name),
    icon("chevron"));

  return h("div", { class: "stack" }, toggle, body);
}

// ── the shelf ───────────────────────────────────────────────────────────

export function booksScreen({ personId, isTabRoot = false }) {
  const person = store.person(personId);
  const books = person ? store.booksFor(person.id) : [];
  const errorSlot = h("div", {});

  const fileInput = h("input", { type: "file", accept: ".txt,text/plain", class: "hidden", onChange: async e => {
    const f = e.target.files?.[0]; e.target.value = "";
    if (!f || !person) return;
    clear(errorSlot);
    importBtn.disabled = true; importBtn.textContent = L("Importing…");
    try {
      const made = await makeBook(f, person.id);
      store.addBook(made);
    } catch (err) {
      errorSlot.append(errorNote(err instanceof ImportError ? err.message : L("That file could not be turned into pages.")));
    }
    importBtn.disabled = false; importBtn.textContent = L("Import book");
  } });

  const importBtn = h("button", { class: "btn-primary", onClick: () => fileInput.click() }, L("Import book"));

  return h("div", { class: "screen" },
    appBar(L("Books"), { onBack: isTabRoot ? null : pop }),
    h("div", { class: "scroll" }, h("div", { class: "stack gap-m", style: { paddingTop: "var(--s)" } },
      person ? breadcrumb(person) : null,
      h("div", { class: "stack", style: { gap: "4px" } },
        headline(L("A shelf of\nfamiliar pages.")),
        subtext(L("Bring a text. Hear it in a recreated voice, one page at a time."))),
      errorSlot, fileInput,

      books.length === 0
        ? emptyHint("books", L("No books yet"), L("Your first book belongs here."))
        : h("div", { class: "stack" }, books.map((book, i) => bookRow(book, i))),

      importBtn,
      h("p", { class: "caption", style: { margin: 0 } }, L("Only import text you have the right to have read aloud.")),
      h("p", { class: "small", style: { margin: 0 } }, L("Plain text files only in the browser version.")),
    )));
}

function bookRow(book, index) {
  const read = store.pagesRead(book.id);
  const left = Math.max(0, Math.floor(book.pages.reduce((n, p) => n + p.length, 0)
    * Math.max(book.pages.length - read, 0) / Math.max(book.pages.length, 1)));

  return h("div", { class: "row row--top", style: { gap: "16px", padding: "12px 0" } },
    h("div", { class: "book-cover" + (index % 2 ? " book-cover--rust" : "") },
      h("span", { class: "book-cover__mark" }, L("JADDATI")),
      h("span", { class: "book-cover__title" }, book.title),
      h("span", { class: "book-cover__shelf" }, L("FAMILY SHELF"))),
    h("div", { class: "grow stack", style: { gap: "7px" } },
      bidi(book.title, { class: "serif", style: { fontSize: "22px" } }),
      h("div", { class: "divider" }),
      h("div", { class: "small" }, Counts.pagesRead(read, book.pages.length)),
      h("div", { class: "small" }, L("Roughly") + " " + Counts.number(left) + " " + L("credits left to read")),
      h("div", { class: "row between" },
        h("button", { class: "wine-text", style: { fontSize: "13px", fontWeight: "600" },
          onClick: () => push(readerScreen, { bookId: book.id, personId: book.personId }) }, L("Open book")),
        h("button", { class: "iconbtn", "aria-label": L("Delete book"), onClick: () =>
          confirmDialog({ title: L("Delete this book?"), message: L("This removes the imported text and its generated page audio."),
            confirm: L("Delete book and its audio"),
            onConfirm: async () => { player.stop(); await store.deleteBook(book.id); } }) }, icon("trash")))));
}

// ── the reader ──────────────────────────────────────────────────────────

export function readerScreen({ bookId, personId }) {
  const book = store.book(bookId);
  const person = store.person(personId);
  if (!book) return h("div", { class: "screen" }, appBar(L("Untitled book"), { onBack: pop }),
    h("div", { class: "scroll" }, emptyHint("bookClosed", L("Book removed"), L("This book is no longer on the phone."))));

  let pageIndex = Math.max(0, Math.min(book.currentPage, Math.max(book.pages.length - 1, 0)));
  let generating = false, answering = false, resumeAt = null;
  const answerIds = [];

  const container = h("div", { class: "stack gap-m" });
  const screen = h("div", { class: "screen" }, appBar(book.title, { onBack: () => { discardAnswers(); pop(); } }),
    h("div", { class: "scroll" }, container));

  const pageText = () => book.pages[pageIndex] || "";
  const alreadyRead = () => store.readPage(book.id, pageIndex);
  const canRead = () => personHasVoice(person) && Config.isConfigured && !generating
    && !!pageText() && !store.loadFailed;

  async function discardAnswers() {
    for (const id of answerIds.splice(0)) {
      const a = store.assets.find(x => x.id === id);
      if (a) await store.deleteAsset(a);
    }
  }

  function move(delta) {
    player.stop();
    pageIndex = Math.max(0, Math.min(pageIndex + delta, book.pages.length - 1));
    store.updateBook({ ...book, currentPage: pageIndex });
    discardAnswers();
    paint();
  }

  async function readPage() {
    const p = store.person(personId);
    if (!p || !canRead()) return;
    // A row whose audio went missing used to bring this button back and bill
    // the page again. Play what exists instead.
    const existing = alreadyRead();
    if (existing) { player.play(existing); return; }

    generating = true; paint();
    const words = pageText(), index = pageIndex;
    try {
      const result = await Voice.synthesize(words, p.voiceId, Config.defaultModelId, p.tuning || TUNING.natural);
      const asset = await keepAudio(result, {
        personId: p.id, source: "generated", text: words, modelId: Config.defaultModelId,
        provenance: L("From your imported text") + " · " + Counts.pagePosition(index + 1, book.pages.length),
        intent: "readBook", content: "importedText", bookId: book.id, pageIndex: index, isSaved: true,
      });
      generating = false;
      if (asset) { await store.pruneDuplicatePages(book.id, index, asset.id); player.play(asset); }
      paint(asset ? null : { message: L("The page was read but the audio could not be saved to this phone."), retry: false });
    } catch (e) {
      generating = false;
      paint({ message: e instanceof ConsentMissing ? Config.unavailableMessage : (e?.message || L("That page could not be read. Try again.")),
        retry: !(e instanceof ConsentMissing) });
    }
  }

  let question = "", answer = null, answerAsset = null, questionError = null;

  function pauseForQuestion() {
    const a = alreadyRead();
    if (a && player.playingThis(a.id)) {
      resumeAt = player.duration > 0 ? player.currentTime / player.duration : 0;
      player.pause();
    }
  }

  async function ask() {
    const p = store.person(personId);
    const asked = trimmedOf(question);
    if (!asked || !p || answering) return;
    pauseForQuestion();
    answering = true; questionError = null; answer = null; answerAsset = null; paint();
    try {
      const reply = await Companion.answer(asked, {
        bookTitle: book.title, pageText: pageText().slice(0, 1200), pageNumber: pageIndex + 1,
      });
      answer = reply;
      const result = await Voice.synthesize(reply, p.voiceId, Config.defaultModelId, p.tuning || TUNING.natural);
      // bookId and pageIndex stay null deliberately: readPage matches on
      // exactly those two, and an answer filed against the page would later be
      // handed back as the page's own reading.
      const asset = await keepAudio(result, {
        personId: p.id, source: "generated", text: reply, modelId: Config.defaultModelId,
        provenance: L("A question asked while reading"),
        intent: "saySomething", content: "answerWhileReading", isSaved: false,
      });
      answering = false;
      if (asset) { answerAsset = asset; answerIds.push(asset.id); player.play(asset); }
      else questionError = L("The answer was written but the audio could not be saved to this phone.");
      paint();
    } catch (e) {
      answering = false;
      questionError = e instanceof ConsentMissing ? Config.unavailableMessage
        : (e?.message || L("That question could not be answered. Try again."));
      paint();
    }
  }

  function paint(pageError) {
    clear(container);
    const existing = alreadyRead();

    container.append(
      h("div", { class: "row between" },
        h("span", { class: "label" }, Counts.pagePosition(pageIndex + 1, book.pages.length)),
        existing ? h("span", { class: "caption amber-text" }, L("Page already read"))
          : h("span", { class: "caption" }, "≈ " + Counts.number(pageText().length) + " " + L("credits"))),

      panel(h("p", { dir: dirOf(pageText()), style: { margin: 0, textAlign: isArabicText(pageText()) ? "right" : "left" } }, pageText())),

      pageError ? errorNote(pageError.message, pageError.retry ? () => readPage() : null) : null,

      existing
        ? h("button", { class: "btn-primary", onClick: () => player.play(existing) },
            player.playingThis(existing.id) ? L("Pause") : L("Replay this page"))
        : h("div", { class: "stack gap-xs" },
            h("button", { class: "btn-primary", disabled: !canRead(), onClick: readPage },
              generating ? L("Creating audio…") : L("Read this page")),
            !canRead() && !generating
              ? h("p", { class: "caption", style: { margin: 0 } },
                  !Config.isConfigured ? Config.unavailableMessage
                    : personHasVoice(person) ? L("There is nothing on this page to read.")
                    : L("Add a voice before creating audio."))
              : null),

      h("div", { class: "row gap-s" },
        h("button", { class: "btn-quiet", disabled: pageIndex === 0, onClick: () => move(-1) }, L("Previous page")),
        h("button", { class: "btn-quiet", disabled: pageIndex >= book.pages.length - 1, onClick: () => move(1) }, L("Next page"))),

      h("p", { class: "caption center", style: { margin: 0 } },
        L("Page audio is an AI recreation of the voice.") + " " + L("Only import text you have the right to have read aloud.")),

      questionSection());
  }

  function questionSection() {
    if (!personHasVoice(person)) return null;
    if (!Config.isCompanionConfigured) {
      return panel(h("div", { class: "stack gap-xs" },
        h("div", { class: "label" }, L("Stop and ask")),
        h("p", { class: "caption", style: { margin: 0 } },
          Config.isOffByChoice ? Config.unavailableMessage : L("Questions are not set up on this build."))));
    }

    const input = h("textarea", { class: "ask-input", rows: 1, placeholder: L("What do you want to ask?"),
      disabled: answering, onInput: e => {
        // First keystroke stops the story. Waiting until Ask is tapped meant
        // the page carried on talking over the child.
        if (!question && e.target.value) pauseForQuestion();
        question = e.target.value;
        askBtn.disabled = !trimmedOf(question) || answering;
      } });
    input.value = question;

    const askBtn = h("button", { class: "btn-primary", disabled: !trimmedOf(question) || answering, onClick: ask },
      answering ? L("Thinking…") : L("Ask"));

    return panel(h("div", { class: "stack gap-xs" },
      h("div", { class: "label" }, L("Stop and ask")),
      h("p", { class: "small", style: { margin: 0 } },
        L("Answers are written by AI. They are not their words and not their memories.")),
      input, askBtn,

      answer ? h("div", { class: "stack gap-xs", style: { paddingTop: "var(--xs)" } },
        h("div", { class: "badges" }, sourceBadge(true), contentBadge("answerWhileReading")),
        h("p", { class: "spoken", dir: dirOf(answer), style: { margin: 0, textAlign: isArabicText(answer) ? "right" : "left" } }, answer),
        h("div", { class: "row gap-s" },
          answerAsset ? h("button", { class: "btn-quiet", onClick: () => player.play(answerAsset) },
            player.playingThis(answerAsset.id) ? L("Pause") : L("Hear it again")) : null,
          alreadyRead() ? h("button", { class: "btn-quiet", onClick: () => {
            question = ""; answer = null; answerAsset = null;
            const a = alreadyRead(); if (!a) return;
            player.play(a);
            if (resumeAt > 0 && resumeAt < 1) setTimeout(() => player.seek(resumeAt), 250);
            resumeAt = null; paint();
          } }, L("Continue the story")) : null)) : null,

      questionError ? errorNote(questionError) : null));
  }

  paint();
  const sync = () => paint();
  player.addEventListener("change", sync);
  screen.addEventListener("jaddati:unmount", () => player.removeEventListener("change", sync));
  return track(screen);
}

// ── the archive ─────────────────────────────────────────────────────────

export function memoriesScreen({ personId, isTabRoot = false }) {
  const person = store.person(personId);
  let origin = "all", experience = "all";

  const list = h("div", { class: "stack" });
  const filters = h("div", { class: "stack gap-s" });

  const everything = () => (person ? store.archive(person.id) : []);
  const matchesOrigin = (a, o) => o === "all" || (o === "original" ? a.source === "original" : a.source === "generated");
  const matchesExperience = (a, e) => e === "all" || a.intentRaw === e;

  const originTitle = o => o === "all" ? L("All") : o === "original" ? L("Original recording") : L("AI recreated");
  const expTitle = e => e === "all" ? L("All") : Intent.title(e);

  function paint() {
    const all = everything();
    const items = all.filter(a => matchesOrigin(a, origin) && matchesExperience(a, experience));
    const filtered = origin !== "all" || experience !== "all";

    const origins = ["all", "original", "recreated"].filter(o => o === "all" || all.some(a => matchesOrigin(a, o)));
    const exps = ["all", ...INTENTS].filter(e => e === "all" || all.some(a => matchesExperience(a, e)));

    // Only offer a control that would change anything.
    clear(filters);
    if (origins.length > 2) filters.append(chipRow(L("Origin"), origins, origin, originTitle, v => {
      origin = v; if (v === "original") experience = "all"; paint();
    }));
    // Real recordings are stored with no experience, so every chip but All
    // would be guaranteed empty and still tappable.
    if (origin !== "original" && exps.length > 2)
      filters.append(chipRow(L("Experience"), exps, experience, expTitle, v => { experience = v; paint(); }));

    clear(list);
    if (!items.length) {
      list.append(filtered
        ? h("div", { class: "stack gap-s" },
            emptyHint("filter", L("No clips match this filter"),
              [origin !== "all" ? L("Origin") + ": " + originTitle(origin) : null,
               experience !== "all" ? L("Experience") + ": " + expTitle(experience) : null]
                .filter(Boolean).join(" · ") + "\n" + L("Try another filter or show all clips.")),
            h("button", { class: "btn-quiet", onClick: () => { origin = "all"; experience = "all"; paint(); } }, L("Clear filters")))
        : emptyHint("tray", L("Nothing saved yet"), L("Clips you choose to keep will appear here.")));
      return;
    }
    for (const asset of items) {
      const row = audioRow(asset, a => push(playerScreen, { assetId: a.id }));
      row.addEventListener("contextmenu", e => {
        e.preventDefault();
        confirmDialog({
          title: asset.source === "original" ? L("Delete this recording?") : L("Discard this clip?"),
          message: asset.source === "original"
            ? L("This is a real recording of them and the only copy on this phone. It cannot be recovered.")
            : L("The audio is deleted from this phone. Creating it again costs credits."),
          confirm: L("Delete permanently"),
          onConfirm: async () => { if (player.assetId === asset.id) player.stop(); await store.deleteAsset(asset); },
        });
      });
      list.append(row);
    }
  }

  function chipRow(label, options, selected, title, choose) {
    return h("div", { class: "stack", style: { gap: "6px" } },
      h("div", { style: { fontSize: "12px", fontWeight: "600", color: "var(--ink-soft)" } }, label),
      h("div", { class: "chiprow" }, options.map(o => h("button", {
        class: "chip", "aria-selected": String(o === selected),
        "aria-label": label + ", " + title(o), onClick: () => choose(o),
      }, title(o)))));
  }

  paint();

  return h("div", { class: "screen" },
    appBar(L("Saved"), { onBack: isTabRoot ? null : pop }),
    h("div", { class: "scroll" }, h("div", { class: "stack gap-m" },
      person ? breadcrumb(person) : null,
      headline(L("Carefully kept.")),
      subtext(L("Original recordings and the new words you chose to save.")),
      filters, list)));
}

// ── listening ───────────────────────────────────────────────────────────
// The moment the whole product exists for, so it holds nothing but the words,
// the voice, and the truth about its source.

export function playerScreen({ assetId }) {
  const asset = store.assets.find(a => a.id === assetId);
  if (!asset) return h("div", { class: "screen" }, appBar(L("Playing"), { onBack: pop }),
    h("div", { class: "scroll" }, emptyHint("tray", L("Nothing saved yet"), L("Clips you choose to keep will appear here."))));

  let kept = asset.isSaved;
  const present = store.fileExists(asset);

  const fill = h("div", { class: "track__fill", style: { width: "0%" } });
  const knob = h("div", { class: "track__knob", style: { insetInlineStart: "0px" } });
  const elapsed = h("span", {}, "0:00");
  const total = h("span", {}, Counts.clock(asset.durationSeconds));
  const track = h("div", { class: "track", role: "slider", "aria-label": L("Playing") },
    h("div", { class: "track__bg" }), fill, knob);

  const playBtn = h("button", { class: "bigplay", "aria-label": L("Play"), onClick: () => player.play(asset) }, icon("play"));

  const clipLength = () => (player.assetId === asset.id && player.duration > 0 ? player.duration : asset.durationSeconds);
  const skipInterval = () => { const d = clipLength(); return d < 60 ? 5 : d < 180 ? 10 : 15; };
  const showsSkip = () => clipLength() >= 12 && !asset.demo;

  const back = h("button", { class: "skip", "aria-label": L("Back"), onClick: () => player.skip(-skipInterval()) }, icon("back5"));
  const fwd = h("button", { class: "skip", "aria-label": L("Next"), onClick: () => player.skip(skipInterval()) }, icon("fwd5"));

  const keepBtn = h("button", { class: "btn-quiet grow", disabled: kept, onClick: () => {
    if (kept) return;
    store.updateAsset({ ...asset, isSaved: true });
    kept = true; keepBtn.textContent = L("Clip saved"); keepBtn.disabled = true;
    warning.classList.add("hidden");
  } }, kept ? L("Clip saved") : L("Keep this clip"));

  const warning = h("p", { class: "caption amber-text center" + (kept ? " hidden" : ""), style: { margin: 0 } },
    L("Not kept yet. This clip is removed when you leave."));

  const speeds = [0.75, 1, 1.25];
  const speedRow = h("div", { class: "row", style: { gap: "4px", minHeight: "44px" } },
    speeds.map(rate => h("button", {
      class: "chip", "aria-selected": String(Math.abs(player.playbackRate - rate) < 0.01),
      "aria-label": L("Playback speed"), onClick: () => { player.setRate(rate); sync(); },
    }, rate === 1 ? L("Normal") : rate + "×")));

  function sync() {
    const isCurrent = player.assetId === asset.id;
    const p = isCurrent ? player.progress : 0;
    fill.style.width = (p * 100) + "%";
    knob.style.insetInlineStart = `calc(${p * 100}% - ${p * 16}px)`;
    elapsed.textContent = Counts.clock(isCurrent ? player.currentTime : 0);
    total.textContent = Counts.clock(isCurrent && player.duration > 0 ? player.duration : asset.durationSeconds);
    clear(playBtn).append(icon(player.playingThis(asset.id) ? "pause" : "play"));
    playBtn.classList.toggle("bigplay--on", player.playingThis(asset.id));
    back.disabled = !isCurrent; fwd.disabled = !isCurrent;
    back.classList.toggle("hidden", !showsSkip()); fwd.classList.toggle("hidden", !showsSkip());
    [...speedRow.children].forEach((b, i) =>
      b.setAttribute("aria-selected", String(Math.abs(player.playbackRate - speeds[i]) < 0.01)));
    errorSlot.classList.toggle("hidden", !player.error);
    errorSlot.textContent = player.error || "";
  }

  const errorSlot = h("p", { class: "caption danger center hidden", style: { margin: 0 } });

  track.addEventListener("pointerdown", e => {
    const move = ev => {
      const r = track.getBoundingClientRect();
      let f = (ev.clientX - r.left) / r.width;
      if (isAr()) f = 1 - f;
      player.seek(Math.min(Math.max(f, 0), 1));
    };
    move(e);
    const up = () => { window.removeEventListener("pointermove", move); window.removeEventListener("pointerup", up); };
    window.addEventListener("pointermove", move); window.addEventListener("pointerup", up);
  });

  const screen = h("div", { class: "screen" },
    appBar(L("Playing"), { onBack: pop }),
    h("div", { class: "player" },
      h("div", { style: { flex: "1" } }),
      // Provenance first, words second. Which of the two things this is has to
      // be settled before anyone reads a single word of it.
      h("div", { class: "badges", style: { justifyContent: "center" } },
        sourceBadge(asset.source === "generated"),
        asset.source === "generated" && asset.contentKind ? contentBadge(asset.contentKind) : null),

      h("div", { class: "player-art" },
        h("i", { style: { inset: "11px" } }), h("i", { style: { inset: "22px" } }),
        h("i", { style: { inset: "33px" } }), h("i", { style: { inset: "44px" } }), h("b")),

      asset.text ? h("p", { class: "player__words", dir: dirOf(asset.text), style: { margin: 0 } }, asset.text) : null,
      asset.provenance ? h("p", { class: "caption wine-text center", style: { margin: 0 } }, asset.provenance) : null,
      asset.demo ? h("p", { class: "small center", style: { margin: 0 } },
        L("Spoken by this browser in demo mode. Not a recreation of anyone.")) : null,

      h("div", { style: { flex: "1" } }),

      present
        ? h("div", { class: "stack gap-s", style: { width: "100%" } },
            track, h("div", { class: "clock" }, elapsed, total),
            h("div", { class: "transport" }, back, playBtn, fwd),
            speedRow)
        : errorNote(L("This audio file is not available. Playback is unavailable.")),

      errorSlot,

      asset.source === "generated"
        ? h("div", { class: "stack gap-s", style: { width: "100%" } }, warning,
            h("div", { class: "row gap-s" }, keepBtn,
              h("button", { class: "btn-danger grow", onClick: () =>
                confirmDialog({ title: L("Discard this clip?"),
                  message: L("The audio is deleted from this phone. Creating it again costs credits."),
                  confirm: L("Discard"),
                  onConfirm: async () => { player.stop(); await store.deleteAsset(asset); pop(); } }) }, L("Discard"))))
        : null));

  sync();
  player.addEventListener("change", sync);
  screen.addEventListener("jaddati:unmount", () => player.removeEventListener("change", sync));
  if (present) setTimeout(() => player.play(asset), 60);
  return screen;
}

// ── words that arrive later ─────────────────────────────────────────────
// A letter is words plus a date. The audio is made when the letter is opened
// and never in advance: generating early would spend the allowance on
// something nobody may ever hear, and would fix a voice that might still be
// improved before the day arrives.
//
// There is no background delivery on either platform, and pretending otherwise
// would be the dishonest version of this feature. What actually happens is that
// the letter becomes openable on its day, and the app says so plainly.

/** Unsent letter drafts, held across rebuilds. The whole tree is rebuilt on any
 *  store change, so without this, removing one letter — or a clip finishing
 *  anywhere — silently discarded a letter someone was still writing. */
const letterDrafts = new Map();

export function lettersScreen({ personId }) {
  const draft = letterDrafts.get(personId) || { text: "", occasion: "" };
  const person = store.person(personId);
  const errorSlot = h("div", {});
  let working = false;
  /** Letters with a generation in flight, so a second tap cannot pay twice. */
  const opening = new Set();

  const area = h("textarea", {
    class: "textarea", rows: 4,
    placeholder: L("Write what they should say when the day comes…"),
  });
  area.value = draft.text;

  // Tomorrow, as the gentlest possible default: a letter dated today is not a
  // letter, it is just words.
  const tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
  const when = h("input", { type: "date", value: tomorrow, min: tomorrow });
  const occasion = h("input", { type: "text", placeholder: L("A birthday, a graduation, a wedding…") });
  occasion.value = draft.occasion;
  const remember = () => letterDrafts.set(personId, { text: area.value, occasion: occasion.value });
  occasion.addEventListener("input", remember);

  const count = h("span", { class: "caption" }, Counts.characters(0, 800));
  const seal = h("button", { class: "btn-primary", disabled: true }, L("Seal it"));

  area.addEventListener("input", () => {
    area.dir = dirOf(area.value);
    area.style.textAlign = isArabicText(area.value) ? "right" : "left";
    remember();
    sync();
  });
  when.addEventListener("change", sync);

  seal.addEventListener("click", () => {
    const t = trimmedOf(area.value);
    if (!t || !when.value) return;
    // Noon, not midnight: a letter dated for a birthday should arrive during
    // that day rather than in the small hours of it.
    const sealed = store.addLetter({
      personId, text: t, occasion: trimmedOf(occasion.value),
      deliverAt: new Date(when.value + "T12:00:00").toISOString(),
    });
    if (!sealed) {
      // The draft is deliberately left in the box: it is the only copy.
      clear(errorSlot);
      errorSlot.append(errorNote(store.storageError || L("Changes could not be saved.")));
      return;
    }
    area.value = ""; occasion.value = "";
    letterDrafts.delete(personId);
    toast(L("Sealed. It will be here on the day."));
    render();
  });

  async function open(letter) {
    const p = store.person(personId);
    // The guard has to survive the click that follows it. Calling render() here
    // rebuilt this screen with working = false and a detached errorSlot, so the
    // button never disabled, a second tap generated the same letter a second
    // time — billed twice — and every failure was appended to a node that was
    // no longer on screen. Local state, local update.
    if (!p || working || opening.has(letter.id) || letter.openedAt) return;
    opening.add(letter.id);
    working = true; clear(errorSlot); sync();
    try {
      const result = await Voice.synthesize(letter.text, p.voiceId,
        Config.defaultModelId, p.tuning || TUNING.natural);
      const asset = await keepAudio(result, {
        personId: p.id, source: "generated", text: letter.text,
        modelId: Config.defaultModelId,
        provenance: L("Sealed on") + " " + new Date(letter.createdAt)
          .toLocaleDateString(isAr() ? "ar" : "en", { dateStyle: "medium" }),
        intent: "saySomething", content: "wordsSuppliedByYou", isSaved: true,
      });
      working = false; opening.delete(letter.id);
      if (asset) {
        store.updateLetter({ ...letter, openedAt: new Date().toISOString(), assetId: asset.id });
        push(playerScreen, { assetId: asset.id });
      } else {
        sync();
        errorSlot.append(errorNote(L("The audio arrived but could not be saved to this phone.")));
      }
    } catch (e) {
      working = false; opening.delete(letter.id); sync();
      const consent = e instanceof ConsentMissing;
      errorSlot.append(errorNote(consent ? Config.unavailableMessage
        : (e?.message || L("Something went wrong. Try again.")),
        consent ? null : () => { clear(errorSlot); open(letter); }));
    }
  }

  const openButtons = [];
  function sync() {
    const t = trimmedOf(area.value);
    count.textContent = Counts.characters(t.length, 800);
    count.className = "caption" + (t.length > 800 ? " danger" : "");
    seal.disabled = !(t && t.length <= 800 && when.value && !working);
    for (const { id, button } of openButtons) {
      button.disabled = working || !personHasVoice(person) || !Config.isConfigured;
      button.textContent = opening.has(id) ? L("Opening…") : L("Open it");
    }
  }

  const dateLine = iso => new Date(iso).toLocaleDateString(isAr() ? "ar" : "en",
    { year: "numeric", month: "long", day: "numeric" });

  const due = store.dueLetters(personId);
  const sealed = store.sealedLetters(personId);
  const opened = store.openedLetters(personId);

  const dueCard = letter => panel(h("div", { class: "stack gap-s" },
    h("div", { class: "row between" },
      h("div", { class: "label" }, letter.occasion || L("A letter for today")),
      h("span", { class: "caption sage-text" }, L("Ready"))),
    h("p", { class: "caption", style: { margin: 0 } }, L("Sealed on") + " " + dateLine(letter.createdAt)),
    (() => {
      const button = h("button", { class: "btn-primary", onClick: () => open(letter) }, L("Open it"));
      openButtons.push({ id: letter.id, button });
      return button;
    })()));

  // A sealed letter shows its date and its occasion, never its words. Being
  // able to read it early is the same as not having sealed it.
  const sealedCard = letter => panelS(h("div", { class: "stack", style: { gap: "4px" } },
    h("div", { class: "row between" },
      h("div", { class: "label" }, letter.occasion || L("Sealed words")),
      h("span", { class: "caption" }, dateLine(letter.deliverAt))),
    h("p", { class: "caption", style: { margin: 0 } },
      Counts.characters(letter.text.length, 800) + " · " + L("Sealed until the day")),
    h("button", {
      class: "wine-text", style: { fontSize: "13px", fontWeight: "600", textAlign: "start", minHeight: "var(--touch)" },
      onClick: () => confirmDialog({
        title: L("Remove this letter?"),
        message: L("The words are deleted from this phone. This cannot be undone."),
        confirm: L("Remove"),
        onConfirm: () => { store.removeLetter(letter.id); render(); },
      }),
    }, L("Remove"))));

  // Built first, synced second: the open buttons are created inside this tree,
  // so settling their state before it exists left them enabled on a person with
  // no voice at all.
  const screen = h("div", { class: "screen" },
    appBar(L("Words that arrive later"), { onBack: pop }),
    h("div", { class: "scroll" }, h("div", { class: "stack gap-m" },
      person ? breadcrumb(person) : null,
      headline(L("Sealed now.\nHeard later."), 30),
      subtext(L("Write something now and choose the day it can be heard. Nothing is created until you open it, and until then the words stay sealed on this phone.")),

      errorSlot,
      !Config.isConfigured ? errorNote(Config.unavailableMessage) : null,

      due.length ? h("div", { class: "stack gap-s" },
        sectionLabel(L("Waiting for you")), due.map(dueCard)) : null,

      panel(h("div", { class: "stack gap-s" },
        sectionLabel(L("Seal something new")),
        h("label", { class: "field" },
          h("div", { class: "field__title" }, L("The occasion")), occasion),
        h("label", { class: "field" },
          h("div", { class: "field__title" }, L("The day it can be heard")), when),
        area,
        h("div", { class: "row between" }, count, h("span", {})),
        seal)),

      sealed.length ? h("div", { class: "stack gap-s" },
        sectionLabel(L("Sealed")), sealed.map(sealedCard)) : null,

      opened.length ? h("div", { class: "stack gap-s" },
        sectionLabel(L("Already opened")),
        opened.map(l => h("div", { class: "stack", style: { gap: "2px" } },
          h("div", { class: "caption" }, (l.occasion || L("Sealed words")) + " · " + dateLine(l.deliverAt)),
          bidi(l.text)))) : null,

      !due.length && !sealed.length && !opened.length
        ? emptyHint("lock", L("Nothing sealed yet"), L("Write something for a day that has not come.")) : null,
    )));

  sync();
  return screen;
}

// ── recorded before it is needed ────────────────────────────────────────
// The hard part is not recording. It is knowing what to ask for — so this asks
// for specific things rather than "record a voice sample", and saves each one
// as an original recording, which is the one kind of audio in this app that
// cannot be made again.

export function captureScreen({ personId }) {
  const person = store.person(personId);
  const recorder = new Recorder();
  let recordingId = null;

  const errorSlot = h("div", {});
  const meterFill = h("i");
  const clockEl = h("span", { class: "caption", style: { fontVariantNumeric: "tabular-nums" } }, "0:00");
  const meterRow = h("div", { class: "row gap-s hidden" }, h("div", { class: "meter" }, meterFill), clockEl);

  const answered = new Set(
    store.assets.filter(a => a.personId === personId && a.source === "original")
      .map(a => a.promptId).filter(Boolean));

  // One card per prompt, built once and mutated in place.
  //
  // Calling render() here instead would rebuild this whole screen from
  // scratch — a new Recorder, a new recordingId of null, new buttons — while
  // the old recorder kept running with nothing pointing at it. The stop branch
  // became unreachable, every take was lost, and the microphone stayed open.
  // Local state belongs to a local update; render() is for navigation and for
  // changes that came from the store.
  const cards = CAPTURE_PROMPTS.map(prompt => {
    const words = isAr() ? prompt.arabic : prompt.english;
    const mark = h("span", { class: "caption sage-text" + (answered.has(prompt.id) ? "" : " hidden") }, L("Recorded"));
    const button = h("button", { class: "btn-quiet" }, L("Record this"));
    button.addEventListener("click", () => toggle(prompt));
    const panelEl = panel(h("div", { class: "stack gap-s" },
      h("div", { class: "row between" }, h("div", { class: "label" }, ""), mark),
      bidi(words),
      button));
    return { prompt, button, mark, panelEl };
  });

  function sync() {
    for (const c of cards) {
      const mine = recordingId === c.prompt.id;
      c.button.textContent = mine ? L("Stop recording") : L("Record this");
      c.button.disabled = recordingId !== null && !mine;
      c.mark.classList.toggle("hidden", !answered.has(c.prompt.id));
    }
    meterRow.classList.toggle("hidden", recordingId === null);
  }

  async function toggle(prompt) {
    clear(errorSlot);

    if (recordingId === prompt.id) {
      recordingId = null;
      sync();
      const out = await recorder.stop();
      if (!out?.blob?.size) {
        errorSlot.append(errorNote(L("That recording came out silent. Nothing reached the microphone — check nothing is covering it and try again.")));
        return;
      }
      const saved = await store.storeAudio(out.blob, {
        personId, source: "original", text: isAr() ? prompt.arabic : prompt.english,
        duration: out.seconds, isSaved: true, promptId: prompt.id, fileExtension: "webm",
      });
      if (saved) { answered.add(prompt.id); sync(); }
      else errorSlot.append(errorNote(L("The audio arrived but could not be saved to this phone.")));
      return;
    }

    if (recordingId !== null) return;              // one at a time, always
    try {
      await recorder.start((level, elapsed) => {
        meterFill.style.width = Math.max(3, level * 100) + "%";
        clockEl.textContent = Counts.clock(elapsed);
      });
      recordingId = prompt.id;
      sync();
    } catch {
      errorSlot.append(errorNote(L("The microphone is not available. Check the browser's permission for this page.")));
    }
  }

  // Leaving the screen mid-take must release the microphone, or the browser
  // keeps its recording indicator lit for the rest of the session.
  const screen = h("div", { class: "screen" },
    appBar(L("Recorded before it is needed"), { onBack: pop }),
    h("div", { class: "scroll" }, h("div", { class: "stack gap-m" },
      person ? breadcrumb(person) : null,
      headline(L("While they are\nstill here."), 30),
      subtext(L("Most families find they have nothing usable — a few seconds of someone laughing behind a video, and that is all. These are worth having whatever happens, and together they are what a voice needs.")),
      errorSlot,
      meterRow,
      h("p", { class: "small", style: { margin: 0 } },
        L("Nothing here is sent anywhere. These are recordings, kept on this phone like any other.")),
      cards.map(c => c.panelEl),
    )));
  screen.addEventListener("jaddati:unmount", () => { try { recorder.cancel(); } catch {} });
  sync();
  return track(screen);
}
