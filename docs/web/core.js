// Storage and services.
//
// The shape follows Models.swift and Library.swift deliberately: one index of
// metadata, audio kept beside it, filenames only and never paths. What changes
// is where those live — IndexedDB for the audio blobs, because a browser has no
// application-support directory, and localStorage for the index.

import { L, Counts, state as lang } from "./strings.js";
import { prefs } from "./prefs.js";

export const uuid = () =>
  (crypto.randomUUID ? crypto.randomUUID()
    : "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
        const r = (Math.random() * 16) | 0;
        return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
      }));

// ── the words ───────────────────────────────────────────────────────────
// Ported from Models.swift. Raw values are persisted; never rename one.

export const INTENTS = ["saySomething", "comfort", "storyFiction", "storyFromMemories", "readBook"];

export const Intent = {
  title: k => L({
    saySomething: "Say something", comfort: "Words of comfort",
    storyFiction: "Tell me a story", storyFromMemories: "Words & memories",
    readBook: "Read me a book",
  }[k]),
  subtitle: k => L({
    saySomething: "Words you choose, in a recreated voice",
    comfort: "A short, steadying line you choose",
    storyFiction: "An invented story for a quiet moment",
    storyFromMemories: "The words you have kept, in one place",
    readBook: "Your own text, a page at a time",
  }[k]),
  headline: k => L({
    saySomething: "Words of\nyour choosing.", comfort: "A little\nsteadiness.",
    storyFiction: "A small story.\nA quiet moment.", storyFromMemories: "Words worth\nkeeping.",
    readBook: "A shelf of\nfamiliar pages.",
  }[k]),
  standfirst: k => L({
    saySomething: "Write something new to be spoken in a recreated voice.",
    comfort: "Choose a line, or write what feels right to you.",
    storyFiction: "These are invented stories, not memories or stories told by this person.",
    storyFromMemories: "A place for your memories and the words you have chosen.",
    readBook: "Bring a text. Hear it in a recreated voice, one page at a time.",
  }[k]),
  characterLimit: k => ({
    saySomething: 800, comfort: 400, storyFiction: 2500,
    storyFromMemories: 800, readBook: 1500,
  }[k]),
  icon: k => ({
    saySomething: "pencil", comfort: "leaf", storyFiction: "moon",
    storyFromMemories: "tray", readBook: "book",
  }[k]),
  defaultContent: k => ({
    saySomething: "wordsSuppliedByYou", comfort: "comfortLine",
    storyFiction: "inventedStory", storyFromMemories: "keptWords",
    readBook: "importedText",
  }[k]),
  // Fiction must announce itself. Everything else is words a person typed.
  provenanceNote: k => (k === "storyFiction" ? L("An invented story. Not a real memory.")
    : k === "readBook" ? L("Read from a file you provided.") : null),
};

export const ContentProvenance = {
  label: k => L({
    wordsSuppliedByYou: "Words supplied by you", comfortLine: "Comfort line",
    inventedStory: "Invented story", keptWords: "Saved words",
    importedText: "From an imported file", answerWhileReading: "Answer to a question",
  }[k] || "Words supplied by you"),
  icon: k => ({
    wordsSuppliedByYou: "pencil", comfortLine: "leaf", inventedStory: "sparkles",
    keptWords: "tray", importedText: "doc", answerWhileReading: "question",
  }[k] || "pencil"),
};

export const TUNING = {
  natural:      { stability: 0.45, similarity: 0.80, style: 0.0, speakerBoost: true, speed: 0.88 },
  gentle:       { stability: 0.75, similarity: 0.80, style: 0.0, speakerBoost: true, speed: 0.85 },
  storytelling: { stability: 0.30, similarity: 0.85, style: 0.30, speakerBoost: true, speed: 0.92 },
};
export const sameTuning = (a, b) =>
  a && b && ["stability", "similarity", "style", "speed"].every(k => Math.abs(a[k] - b[k]) < 0.001);
export const presetName = t =>
  sameTuning(t, TUNING.natural) ? L("Natural")
  : sameTuning(t, TUNING.gentle) ? L("Gentle")
  : sameTuning(t, TUNING.storytelling) ? L("Storytelling") : null;

// ── the bank of words ───────────────────────────────────────────────────
// Composer.swift. Local and deterministic: comfort works offline and costs
// nothing, and every line is one a human wrote.

export const AFFIRMATIONS = [
  { id: "words", english: "You do not have to put everything into words.", arabic: "ليس عليك أن تعبّر عن كل شيء بالكلمات." },
  { id: "quiet", english: "One quiet moment is enough for now.", arabic: "تكفي الآن لحظة هدوء واحدة." },
  { id: "pace", english: "There is no right pace for grief.", arabic: "لا وتيرة واحدة صحيحة للحزن." },
  { id: "pause", english: "You can pause. Nothing needs to be decided now.", arabic: "يمكنك التمهّل. لا يلزم أن تحسم شيئًا الآن." },
  { id: "small", english: "Let today be as small as it needs to be.", arabic: "اكتفِ اليوم بما تستطيع." },
  { id: "breath", english: "If it helps, take one slow breath.", arabic: "إن كان ذلك يساعدك، خذ نفسًا بطيئًا." },
];

export const STORIES = [
  {
    id: "moon", title: "The moon’s little garden", titleArabic: "حديقة القمر الصغيرة",
    text: "High above the rooftops, the moon kept a small garden. Nothing grew there but quiet, and the quiet grew very well. Every night the moon watered it, and every night a little of it drifted down to the sleeping town, settling on windowsills and on the backs of cats and on the eyelids of children who were not quite asleep. If you are still awake, that is only because your share is still on its way. It is coming. It always comes.",
    textArabic: "فوق سطوح البيوت، كان للقمر حديقة صغيرة. لم يكن ينبت فيها سوى الهدوء، وكان الهدوء ينمو فيها نموًا جميلًا. في كل ليلة يسقيها القمر، وفي كل ليلة ينزل شيء منها إلى البلدة النائمة، فيستقرّ على حوافّ النوافذ، وعلى ظهور القطط، وعلى جفون الأطفال الذين لم يناموا بعد. وإن كنت ما زلت مستيقظًا، فذلك لأن نصيبك في الطريق. سيصل. إنه يصل دائمًا.",
  },
  {
    id: "lantern", title: "The lantern by the sea", titleArabic: "الفانوس عند البحر",
    text: "There was a lantern at the end of a stone pier who believed her light was too small to matter. The sea was so wide, and she was only one small flame. But every night the fishing boats turned toward her, and every night they came home. She never learned how far her light reached. That is the way with small lights. They do not get to see the whole distance they travel.",
    textArabic: "كان عند طرف رصيف حجري فانوسٌ يظنّ أن ضوءه أصغر من أن يعني شيئًا. فالبحر واسع، وهو شعلة صغيرة واحدة. لكن قوارب الصيد كانت في كل ليلة تلتفت إليه، وفي كل ليلة تعود إلى بيتها. ولم يعرف الفانوس قط إلى أي مدى يصل ضوءه. هكذا هي الأضواء الصغيرة: لا يُتاح لها أن ترى المسافة التي تقطعها كاملة.",
  },
  {
    id: "olive", title: "The sleepy olive tree", titleArabic: "شجرة الزيتون النعسانة",
    text: "An old olive tree on the hill had been standing for four hundred years and had decided, that evening, to have a rest. The wind came to argue with her, as the wind does. She did not argue back. She simply held still, and held her leaves, and held the small brown bird that had chosen her for the night. In the morning the wind had gone somewhere else, and the bird was still there, and so was she.",
    textArabic: "على التلّة شجرة زيتون عتيقة، واقفة منذ أربعمئة عام، قرّرت في ذلك المساء أن تستريح. جاءت الريح لتجادلها، كعادة الريح. فلم تجادلها الشجرة. اكتفت بأن تثبت، وأن تمسك أوراقها، وأن تحمي ذلك الطائر البنيّ الصغير الذي اختارها لليلته. وفي الصباح كانت الريح قد ذهبت إلى مكان آخر، وكان الطائر ما زال هناك، وكانت هي كذلك.",
  },
];

// ── blobs ───────────────────────────────────────────────────────────────
// Audio and photos, keyed by the same filename the index records. A browser has
// no container directory; IndexedDB is the nearest thing that survives a reload
// and holds megabytes without base64 inflating them by a third.

const DB_NAME = "jaddati", DB_VERSION = 1, BLOBS = "blobs";
let dbPromise = null;

function db() {
  if (dbPromise) return dbPromise;
  dbPromise = new Promise((resolve, reject) => {
    let request;
    try { request = indexedDB.open(DB_NAME, DB_VERSION); }
    catch (e) { reject(e); return; }
    request.onupgradeneeded = () => {
      const d = request.result;
      if (!d.objectStoreNames.contains(BLOBS)) d.createObjectStore(BLOBS);
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
    request.onblocked = () => reject(new Error("blocked"));
  });
  return dbPromise;
}

async function tx(mode, fn) {
  const d = await db();
  return new Promise((resolve, reject) => {
    const t = d.transaction(BLOBS, mode);
    const store = t.objectStore(BLOBS);
    let out;
    try { out = fn(store); } catch (e) { reject(e); return; }
    t.oncomplete = () => resolve(out && out.result !== undefined ? out.result : out);
    t.onerror = () => reject(t.error);
    t.onabort = () => reject(t.error || new Error("aborted"));
  });
}

export const Blobs = {
  put: (name, blob) => tx("readwrite", s => s.put(blob, name)),
  get: (name) => tx("readonly", s => s.get(name)),
  del: (name) => tx("readwrite", s => s.delete(name)),
  async has(name) { return (await this.get(name)) != null; },
};

// ── the library ─────────────────────────────────────────────────────────

const INDEX_KEY = "jaddati.library";

class Store extends EventTarget {
  constructor() {
    super();
    this.people = []; this.assets = []; this.notes = []; this.books = [];
    this.storageError = null;
    this.loadFailed = false;
    /** Filenames known to exist, so a list does not hit IndexedDB per row. */
    this.present = new Set();
  }

  async init() {
    this.load();
    await this.refreshPresence();
    await this.sweepAbandonedDrafts();
  }

  load() {
    const raw = prefs.get(INDEX_KEY);
    if (!raw) return;
    try {
      const index = JSON.parse(raw);
      this.people = index.people || [];
      this.assets = index.assets || [];
      this.notes = index.notes || [];
      this.books = index.books || [];
    } catch {
      // Same rule as the app: a corrupt index must not be overwritten by the
      // next save. Move it aside under its own name first, so nothing is lost
      // and the app stays usable.
      prefs.set(INDEX_KEY + ".corrupt-" + Date.now(), raw);
      prefs.remove(INDEX_KEY);
      this.storageError = L("Saved memories could not be read, so they have been set aside rather than overwritten. The audio files are still on this phone.");
    }
  }

  save() {
    if (this.loadFailed) return false;
    try {
      prefs.set(INDEX_KEY, JSON.stringify({
        people: this.people, assets: this.assets, notes: this.notes, books: this.books,
      }));
      this.storageError = null;
      this.changed();
      return true;
    } catch (e) {
      this.storageError = L("Changes could not be saved.") + " " + (e && e.name === "QuotaExceededError"
        ? L("There is no room left in this browser's storage.") : "");
      this.changed();
      return false;
    }
  }

  changed() { this.dispatchEvent(new Event("change")); }

  async refreshPresence() {
    try {
      const d = await db();
      const names = await new Promise((resolve, reject) => {
        const t = d.transaction(BLOBS, "readonly");
        const r = t.objectStore(BLOBS).getAllKeys();
        r.onsuccess = () => resolve(r.result);
        r.onerror = () => reject(r.error);
      });
      this.present = new Set(names);
    } catch { this.present = new Set(); }
  }

  /** Generated audio starts unkept and is removed if the listener leaves
   *  without keeping it. A closed tab skips that, so one pass at startup. */
  async sweepAbandonedDrafts() {
    const doomed = this.assets.filter(a => !a.isSaved && !a.bookId);
    if (!doomed.length) return;
    for (const a of doomed) { try { await Blobs.del(a.filename); } catch {} this.present.delete(a.filename); }
    this.assets = this.assets.filter(a => a.isSaved || a.bookId);
    this.save();
  }

  fileExists(asset) { return asset.demo === true || this.present.has(asset.filename); }

  // reading
  person(id) { return this.people.find(p => p.id === id) || null; }
  book(id) { return this.books.find(b => b.id === id) || null; }

  assetsFor(personId, source = null) {
    return this.assets
      .filter(a => a.personId === personId && (source == null || a.source === source))
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }

  /** Clips the user deliberately kept. Book pages are stored kept so a page is
   *  never paid for twice — that flag means "do not delete", not "chosen". */
  keptClips(personId) {
    return this.assets.filter(a => a.personId === personId && a.source === "generated"
      && a.isSaved && !a.bookId)
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }

  archive(personId) {
    return this.assets.filter(a => a.personId === personId
      && (a.source === "original" || (a.isSaved && !a.bookId)))
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }

  savedAssets(personId, intents) {
    const want = new Set(intents);
    return this.assets.filter(a => a.personId === personId && a.isSaved && !a.bookId
      && a.intentRaw && want.has(a.intentRaw))
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }

  booksFor(personId) {
    return this.books.filter(b => b.personId === personId)
      .sort((a, b) => new Date(b.addedAt) - new Date(a.addedAt));
  }

  affirmations(personId) {
    return this.notes.filter(n => n.personId === personId && n.kind === "affirmation")
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }

  /** A page already generated, found by id and index so it is replayed rather
   *  than paid for a second time. The file check belongs here, not the caller. */
  readPage(bookId, index) {
    const hits = this.assets.filter(a => a.bookId === bookId && a.pageIndex === index
      && this.fileExists(a));
    return hits.length ? hits[hits.length - 1] : null;
  }

  pagesRead(bookId) {
    return new Set(this.assets.filter(a => a.bookId === bookId && this.fileExists(a))
      .map(a => a.pageIndex)).size;
  }

  // writing
  addPerson(p) {
    const person = {
      id: uuid(), name: p.name, fullName: "", relationship: p.relationship || "",
      createdAt: new Date().toISOString(), voiceId: null, voiceCreatedAt: null,
      voiceRequiresVerification: null, consentConfirmedAt: null,
      photoFilename: null, tuning: null,
    };
    this.people.push(person); this.save(); return person;
  }

  updatePerson(p) {
    const i = this.people.findIndex(x => x.id === p.id);
    if (i < 0) return; this.people[i] = p; this.save();
  }

  addNote(n) {
    this.notes.push({ id: uuid(), createdAt: new Date().toISOString(), addedBy: "", ...n });
    this.save();
  }
  removeNote(id) { this.notes = this.notes.filter(n => n.id !== id); this.save(); }

  addBook(b) {
    const book = { id: uuid(), addedAt: new Date().toISOString(), currentPage: 0, ...b };
    this.books.push(book); this.save(); return book;
  }
  updateBook(b) {
    const i = this.books.findIndex(x => x.id === b.id);
    if (i < 0) return; this.books[i] = b; this.save();
  }
  async deleteBook(id) {
    for (const a of this.assets.filter(a => a.bookId === id)) {
      try { await Blobs.del(a.filename); } catch {} this.present.delete(a.filename);
    }
    this.assets = this.assets.filter(a => a.bookId !== id);
    this.books = this.books.filter(b => b.id !== id);
    this.save();
  }

  /** Copy audio into our own storage and record it. Rolls the whole thing back
   *  if the index write fails, rather than handing back a clip that will vanish. */
  async storeAudio(blob, opts) {
    const ext = opts.fileExtension || "mp3";
    const name = `${uuid()}.${ext}`;
    if (blob) {
      try { await Blobs.put(name, blob); }
      catch (e) {
        this.storageError = L("Could not save the audio to this phone.") + " " + (e?.message || "");
        this.changed();
        return null;
      }
      this.present.add(name);
    }
    const asset = {
      id: uuid(), personId: opts.personId, source: opts.source, filename: name,
      text: opts.text || "", createdAt: new Date().toISOString(),
      durationSeconds: opts.duration || 0, modelId: opts.modelId || null,
      isSaved: opts.isSaved !== false, provenance: opts.provenance || null,
      intentRaw: opts.intent || null,
      contentKind: opts.content || (opts.intent ? Intent.defaultContent(opts.intent) : null),
      bookId: opts.bookId || null,
      pageIndex: opts.pageIndex === undefined ? null : opts.pageIndex,
      demo: opts.demo === true || undefined,
    };
    this.assets.push(asset);
    if (!this.save()) {
      this.assets = this.assets.filter(a => a.id !== asset.id);
      if (blob) { try { await Blobs.del(name); } catch {} this.present.delete(name); }
      return null;
    }
    return asset;
  }

  updateAsset(a) {
    const i = this.assets.findIndex(x => x.id === a.id);
    if (i < 0) return; this.assets[i] = a; this.save();
  }

  async deleteAsset(asset) {
    try { await Blobs.del(asset.filename); } catch {}
    this.present.delete(asset.filename);
    this.assets = this.assets.filter(a => a.id !== asset.id);
    this.save();
    return true;
  }

  async pruneDuplicatePages(bookId, index, keepId) {
    const doomed = this.assets.filter(a => a.bookId === bookId && a.pageIndex === index && a.id !== keepId);
    if (!doomed.length) return;
    for (const a of doomed) { try { await Blobs.del(a.filename); } catch {} this.present.delete(a.filename); }
    this.assets = this.assets.filter(a => !doomed.some(d => d.id === a.id));
    this.save();
  }

  async deletePerson(person) {
    for (const a of this.assets.filter(a => a.personId === person.id)) {
      try { await Blobs.del(a.filename); } catch {} this.present.delete(a.filename);
    }
    if (person.photoFilename) { try { await Blobs.del(person.photoFilename); } catch {} }
    this.assets = this.assets.filter(a => a.personId !== person.id);
    this.notes = this.notes.filter(n => n.personId !== person.id);
    this.books = this.books.filter(b => b.personId !== person.id);
    this.people = this.people.filter(p => p.id !== person.id);
    this.save();
  }

  async setPhoto(person, blob) {
    const name = `${uuid()}.jpg`;
    try { await Blobs.put(name, blob); }
    catch { this.storageError = L("That photo could not be saved to this phone."); this.changed(); return; }
    if (person.photoFilename) { try { await Blobs.del(person.photoFilename); } catch {} }
    this.updatePerson({ ...person, photoFilename: name });
  }

  async removePhoto(person) {
    if (person.photoFilename) { try { await Blobs.del(person.photoFilename); } catch {} }
    this.updatePerson({ ...person, photoFilename: null });
  }
}

export const store = new Store();

/** Object URLs, made once each and kept. Minting a fresh one per render leaks
 *  a blob handle on every repaint, which is the browser's version of the bug
 *  that got the iOS app killed for decoding a portrait inside `body`. */
const urlCache = new Map();
export async function blobURL(name) {
  if (!name) return null;
  if (urlCache.has(name)) return urlCache.get(name);
  let blob = null;
  try { blob = await Blobs.get(name); } catch {}
  if (!blob) return null;
  const url = URL.createObjectURL(blob);
  urlCache.set(name, url);
  return url;
}
export function forgetURL(name) {
  const url = urlCache.get(name);
  if (url) { URL.revokeObjectURL(url); urlCache.delete(name); }
}

// ── consent ─────────────────────────────────────────────────────────────
// Consent.swift. The gate is shown on "has not decided" alone; every extra
// condition is a way to ship a disclosure nobody sees.

const C_ANSWER = "jaddati.consent.answer", C_TERMS = "jaddati.consent.terms", C_DATE = "jaddati.consent.date";

export const Consent = {
  get currentTerms() {
    const voice = hostOf(Config.voiceBaseURL), text = hostOf(Config.llmBaseURL);
    return `2026-09-11/${voice}+${text}/voice+text+dictation`;
  },
  get hasDecided() {
    return prefs.get(C_TERMS) === this.currentTerms && prefs.get(C_ANSWER) != null;
  },
  get allowsNetwork() { return this.hasDecided && prefs.get(C_ANSWER) === "true"; },
  get decidedOn() { const d = prefs.get(C_DATE); return d ? new Date(d) : null; },
  record(allowed) {
    prefs.set(C_ANSWER, String(!!allowed));
    prefs.set(C_TERMS, this.currentTerms);
    prefs.set(C_DATE, new Date().toISOString());
  },
  withdraw() { this.record(false); },
};

function hostOf(u) { try { return new URL(u).host; } catch { return "unknown"; } }

export class ConsentMissing extends Error {
  constructor() {
    super(L("This needs to send data to a service outside the phone, and that is currently turned off."));
    this.name = "ConsentMissing";
  }
}

// ── configuration ───────────────────────────────────────────────────────
// The keys are the user's own, held in this browser and sent to nobody but the
// service they belong to. A key shipped inside a web page is a key anyone can
// read out of it, so this app does not carry one.

const K_ELEVEN = "jaddati.key.elevenlabs", K_LLM = "jaddati.key.llm";
const K_VOICE_URL = "jaddati.url.voice", K_LLM_URL = "jaddati.url.llm";

const read = (k, fallback = "") => prefs.get(k) || fallback;
const write = (k, v) => (v ? prefs.set(k, v) : prefs.remove(k));

export const STOCK_VOICE_URL = "https://api.elevenlabs.io";
export const STOCK_LLM_URL = "https://api.groq.com/openai/v1";

export const Config = {
  get elevenKey() { return read(K_ELEVEN); },
  set elevenKey(v) { write(K_ELEVEN, (v || "").trim()); },
  get llmKey() { return read(K_LLM); },
  set llmKey(v) { write(K_LLM, (v || "").trim()); },

  get voiceBaseURL() { return (read(K_VOICE_URL) || STOCK_VOICE_URL).replace(/[\s/]+$/, ""); },
  set voiceBaseURL(v) { write(K_VOICE_URL, (v || "").replace(/[\s/]+$/, "")); },
  get llmBaseURL() { return (read(K_LLM_URL) || STOCK_LLM_URL).replace(/[\s/]+$/, ""); },
  set llmBaseURL(v) { write(K_LLM_URL, (v || "").replace(/[\s/]+$/, "")); },

  /** No key of any kind: the app runs on the browser's own speech, and says so
   *  everywhere it possibly can. This is the mode a QR code lands you in. */
  get isDemo() { return !this.elevenKey; },

  get providerName() { return this.isDemo ? L("Demo voice") : (this.voiceBaseURL === STOCK_VOICE_URL ? "ElevenLabs" : hostOf(this.voiceBaseURL)); },
  get textProviderName() { return this.llmBaseURL === STOCK_LLM_URL ? "Groq" : hostOf(this.llmBaseURL); },

  /** Demo first, consent second — the demo reaches no network at all, so
   *  gating it behind a network answer would switch off something that already
   *  keeps everything here. Real calls stay guarded at their own call sites. */
  get isConfigured() {
    if (this.isDemo) return true;
    return Consent.allowsNetwork;
  },
  get isCompanionConfigured() {
    if (this.isDemo) return true;
    return Consent.allowsNetwork && !!this.llmKey;
  },
  get isTranscriptionConfigured() {
    return !this.isDemo && Consent.allowsNetwork && !!this.llmKey;
  },
  get isOffByChoice() { return !this.isDemo && !Consent.allowsNetwork; },

  get unavailableTitle() { return this.isOffByChoice ? L("Kept on this phone") : L("Voice service not connected"); },
  get unavailableMessage() {
    return this.isOffByChoice
      ? L("Everything is being kept on this phone, so this is switched off. You can change that under Privacy and data.")
      : L("This build has no voice service key, so no new audio can be created. Original recordings still play.");
  },

  defaultModelId: "eleven_multilingual_v2",
  fastModelId: "eleven_flash_v2_5",
  maxCharactersPerGeneration: 2500,
  llmModel: "openai/gpt-oss-120b",
  whisperModel: "whisper-large-v3-turbo",
};

// ── the voice ───────────────────────────────────────────────────────────

export const DEMO_PREFIX = "demo-voice-";
export const isDemoVoice = id => typeof id === "string" && id.startsWith(DEMO_PREFIX);

export class VoiceError extends Error {
  constructor(kind, message) { super(message); this.name = "VoiceError"; this.kind = kind; }
}

function voiceMessage(status, detail) {
  if (status === 401 || status === 403) return L("The key was refused by the voice service.");
  if (status === 429) return L("The voice service is busy right now. Wait a few seconds and try again.");
  if (status === 422) return L("The voice service would not accept that recording.") + (detail ? " " + detail : "");
  return L("The voice service reported a problem.") + ` (${status})` + (detail ? " " + detail : "");
}

export const Voice = {
  async createVoice(name, blob) {
    if (Config.isDemo) {
      await pause(900);
      return { id: DEMO_PREFIX + uuid().slice(0, 8), requiresVerification: false };
    }
    if (!Consent.allowsNetwork) throw new ConsentMissing();

    const form = new FormData();
    form.append("name", name);
    form.append("files", blob, "sample." + (blob.type.includes("wav") ? "wav" : blob.type.includes("mpeg") ? "mp3" : "m4a"));
    const r = await fetch(`${Config.voiceBaseURL}/v1/voices/add`, {
      method: "POST", headers: { "xi-api-key": Config.elevenKey }, body: form,
    }).catch(() => { throw new VoiceError("offline", L("No internet connection.")); });

    const body = await r.text();
    if (!r.ok) throw new VoiceError("provider", voiceMessage(r.status, detailOf(body)));
    let json = {}; try { json = JSON.parse(body); } catch {}
    if (!json.voice_id) throw new VoiceError("bad", L("The voice service replied in a shape the app did not understand."));
    return { id: json.voice_id, requiresVerification: json.requires_verification === true };
  },

  async synthesize(text, voiceId, modelId, tuning) {
    if (Config.isDemo || isDemoVoice(voiceId)) return { demo: true, text };
    if (!Consent.allowsNetwork) throw new ConsentMissing();

    const trimmed = (text || "").trim();
    if (trimmed.length > Config.maxCharactersPerGeneration) {
      throw new VoiceError("tooLong", L("That is longer than one go allows. Shorten it and try again."));
    }
    const url = `${Config.voiceBaseURL}/v1/text-to-speech/${encodeURIComponent(voiceId)}?output_format=mp3_44100_128`;
    const r = await fetch(url, {
      method: "POST",
      headers: { "xi-api-key": Config.elevenKey, "content-type": "application/json", accept: "audio/mpeg" },
      body: JSON.stringify({
        text: trimmed, model_id: modelId,
        voice_settings: {
          stability: tuning.stability, similarity_boost: tuning.similarity,
          style: tuning.style, use_speaker_boost: tuning.speakerBoost, speed: tuning.speed,
        },
      }),
    }).catch(() => { throw new VoiceError("offline", L("No internet connection.")); });

    if (!r.ok) throw new VoiceError("provider", voiceMessage(r.status, detailOf(await r.text())));
    const blob = await r.blob();
    if (blob.size < 500) throw new VoiceError("bad", L("The voice service replied in a shape the app did not understand."));
    return { blob };
  },

  /** A voice that never existed at the provider is decided before anything
   *  else: there is nothing to refuse on consent grounds and nothing a missing
   *  key could have stopped. */
  async deleteVoice(voiceId) {
    if (!voiceId || isDemoVoice(voiceId)) return;
    if (!Consent.allowsNetwork) throw new ConsentMissing();
    if (!Config.elevenKey) throw new VoiceError("notConfigured", L("The key was refused by the voice service."));
    const r = await fetch(`${Config.voiceBaseURL}/v1/voices/${encodeURIComponent(voiceId)}`, {
      method: "DELETE", headers: { "xi-api-key": Config.elevenKey },
    }).catch(() => { throw new VoiceError("offline", L("No internet connection.")); });
    if (r.status === 404) return;                 // already gone is the outcome we wanted
    if (!r.ok) throw new VoiceError("provider", voiceMessage(r.status, detailOf(await r.text())));
  },
};

function detailOf(body) {
  try {
    const j = JSON.parse(body);
    return j?.detail?.message || (typeof j?.detail === "string" ? j.detail : "") || j?.error?.message || "";
  } catch { return ""; }
}

const pause = ms => new Promise(r => setTimeout(r, ms));

// ── answers during a story ──────────────────────────────────────────────

export class CompanionError extends Error {
  constructor(message) { super(message); this.name = "CompanionError"; }
}

/** The page a question was asked about, and nothing else. The model is never
 *  told whose voice will read the answer: a model told that starts claiming
 *  memories the person never had. */
export function storyPrompt(page) {
  return `You are helping read a children's storybook aloud. A child has stopped the story to ask a question. Your answer will be spoken out loud, so write only words that sound natural when someone reads them.

Follow every one of these:
- One or two short sentences. Never more.
- Answer in the same language the page below is written in.
- Warm and simple, pitched at a young child.
- If the answer is in Arabic, use everyday Gulf wording rather than formal newspaper Arabic - the way a grandmother in the Emirates would explain it at home.
- Stay with the story. If the question is not about the story, answer it in one kind sentence and turn back to the page.
- Never say or imply that you are a real person, never claim to remember anything, and never talk about yourself.
- Do not make religious pronouncements about the dead, and do not speak about what has happened to anyone who has died.
- Plain spoken words only. No markdown, no lists, no emoji, no stage directions, and no quotation marks wrapped around the whole answer.

The book is "${page.bookTitle}". This is page ${page.pageNumber}, and it reads:
${page.pageText}`;
}

/** Models leak formatting however firmly the prompt asks them not to, and every
 *  stray asterisk becomes a sound the voice has to make. */
export function tidyAnswer(raw) {
  let t = (raw || "").trim();
  for (const m of ["**", "__", "*", "`", "#"]) t = t.split(m).join("");
  t = t.replace(/\n/g, " ").replace(/ {2,}/g, " ");
  const pairs = [['"', '"'], ["“", "”"]];
  for (const [o, c] of pairs) {
    if (t.length > 2 && t.startsWith(o) && t.endsWith(c)) t = t.slice(1, -1);
  }
  return t.trim();
}

export const Companion = {
  async answer(question, page) {
    if (Config.isDemo) {
      await pause(700);
      return demoAnswer(question, page);
    }
    if (!Consent.allowsNetwork) throw new ConsentMissing();
    if (!Config.llmKey) throw new CompanionError(L("Questions are not set up on this build."));

    const r = await fetch(`${Config.llmBaseURL}/chat/completions`, {
      method: "POST",
      headers: { authorization: `Bearer ${Config.llmKey}`, "content-type": "application/json" },
      body: JSON.stringify({
        model: Config.llmModel,
        messages: [
          { role: "system", content: storyPrompt(page) },
          { role: "user", content: (question || "").slice(0, 300) },
        ],
        max_tokens: 160, temperature: 0.6,
      }),
    }).catch(() => { throw new CompanionError(L("No internet connection.")); });

    if (r.status === 429) throw new CompanionError(L("The question service is busy right now. Wait a few seconds and ask again."));
    if (!r.ok) throw new CompanionError(L("The question service reported a problem.") + ` (${r.status})`);
    const j = await r.json().catch(() => null);
    const content = j?.choices?.[0]?.message?.content;
    if (!content) throw new CompanionError(L("The question service replied in a shape the app did not understand."));
    const cleaned = tidyAnswer(content);
    if (!cleaned) throw new CompanionError(L("No answer came back. Try asking it a different way."));
    return cleaned;
  },
};

/** Demo mode answers from the page itself rather than inventing anything. It
 *  says plainly that it is not a real answer, because a canned line presented
 *  as a model's reply would misrepresent what the app does. */
function demoAnswer(question, page) {
  const first = (page.pageText || "").split(/(?<=[.!?؟])\s+/)[0] || page.pageText || "";
  return L("This is the demo answer. With a question service connected, a short reply about this page would be written here and read aloud.")
    + " " + L("The page says:") + " " + first.slice(0, 160);
}

// ── turning a file into pages ───────────────────────────────────────────
// BookImporter.swift. A PDF's own pages ARE its pages; only plain text and an
// over-long PDF page get re-flowed.

export const PAGE_TARGET = 900, PAGE_MIN = 300, MAX_CHARS = 400000;

export function tidyText(input) {
  let t = (input || "").replace(/\r\n/g, "\n").replace(/­/g, "");
  t = t.replace(/(?<!\n)\n(?!\n)/g, " ");
  t = t.replace(/[ \t]+/g, " ");
  t = t.replace(/\n{3,}/g, "\n\n");
  return t.trim();
}

export function tidyTitle(raw) {
  let n = (raw || "").replace(/^[0-9]{6,}[ _-]+/, "").replace(/_+/g, " ").replace(/ {2,}/g, " ").trim();
  return n || "Untitled";
}

export function stripPageFurniture(input) {
  return (input || "").split("\n").filter(line => {
    const t = line.trim();
    if (!t) return true;
    return !/^[\d\s\p{P}]+$/u.test(t);
  }).join("\n");
}

function hardWrap(sentence) {
  const chunks = []; let cur = "";
  for (const word of sentence.split(" ")) {
    if (!cur) cur = word;
    else if (cur.length + 1 + word.length <= PAGE_TARGET) cur += " " + word;
    else { chunks.push(cur); cur = word; }
  }
  if (cur) chunks.push(cur);
  return chunks;
}

export function splitIntoSentences(text) {
  const terminators = new Set([".", "!", "?", "؟", "۔", "\n"]);
  const out = []; let buf = "";
  for (const ch of text) {
    buf += ch;
    if (terminators.has(ch)) { const t = buf.trim(); if (t) out.push(t); buf = ""; }
  }
  const tail = buf.trim(); if (tail) out.push(tail);
  return out.flatMap(s => (s.length <= PAGE_TARGET ? [s] : hardWrap(s)));
}

export function paginate(text, target = PAGE_TARGET, minimum = PAGE_MIN) {
  const sentences = splitIntoSentences(text);
  const pages = []; let cur = "";
  for (const s of sentences) {
    if (!cur) cur = s;
    else if (cur.length + 1 + s.length <= target) cur += " " + s;
    else if (cur.length < minimum) { cur += " " + s; pages.push(cur.trim()); cur = ""; }
    else { pages.push(cur.trim()); cur = s; }
  }
  if (cur.trim()) pages.push(cur.trim());
  return pages.filter(Boolean);
}

export class ImportError extends Error {}

export async function makeBook(file, personId) {
  const name = file.name.replace(/\.[^.]+$/, "");
  let pages;
  if (/\.pdf$/i.test(file.name) || file.type === "application/pdf") {
    pages = await pdfPages(file);
  } else {
    const cleaned = tidyText(await file.text());
    if (!cleaned) throw new ImportError(L("There was no text in that file."));
    if (cleaned.length > MAX_CHARS) throw new ImportError(L("That file is larger than this app will take. Import a chapter rather than a whole book."));
    pages = paginate(cleaned);
  }
  if (!pages.length) throw new ImportError(L("There was no text in that file."));
  const total = pages.reduce((n, p) => n + p.length, 0);
  if (total > MAX_CHARS) throw new ImportError(L("That file is larger than this app will take. Import a chapter rather than a whole book."));
  return { personId, title: tidyTitle(name), pages };
}

/** PDF.js is not bundled, and a page that fetches a library at import time
 *  stops working the day that CDN does. A PDF is refused with an explanation
 *  instead of failing silently. */
async function pdfPages() {
  throw new ImportError(L("PDF files cannot be read in the browser version. Save the text as a .txt file and import that, or use the iPhone app."));
}
