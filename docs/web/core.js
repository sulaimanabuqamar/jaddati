// Storage and services.
//
// The shape follows Models.swift and Library.swift deliberately: one index of
// metadata, audio kept beside it, filenames only and never paths. What changes
// is where those live — IndexedDB for the audio blobs, because a browser has no
// application-support directory, and localStorage for the index.

import { L, Counts, isArabicText, state as lang } from "./strings.js?v=a805f97143";
import { prefs } from "./prefs.js?v=a805f97143";

export const uuid = () =>
  (crypto.randomUUID ? crypto.randomUUID()
    : "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx".replace(/[xy]/g, c => {
        const r = (Math.random() * 16) | 0;
        return (c === "x" ? r : (r & 0x3) | 0x8).toString(16);
      }));

// ── the words ───────────────────────────────────────────────────────────
// Ported from Models.swift. Raw values are persisted; never rename one.

export const INTENTS = ["saySomething", "askAboutThem", "bridgeLanguage",
                        "comfort", "storyFiction", "storyFromMemories", "readBook"];

export const Intent = {
  title: k => L({
    saySomething: "Say something", askAboutThem: "Ask about them",
    bridgeLanguage: "Say it in their language", comfort: "Words of comfort",
    storyFiction: "Tell me a story", storyFromMemories: "Words & memories",
    readBook: "Read me a book",
  }[k]),
  subtitle: k => L({
    saySomething: "Words you choose, in a recreated voice",
    askAboutThem: "A question, answered only from what your family wrote down",
    bridgeLanguage: "Your words, carried across the language they spoke",
    comfort: "A short, steadying line you choose",
    storyFiction: "An invented story for a quiet moment",
    storyFromMemories: "The words you have kept, in one place",
    readBook: "Your own text, a page at a time",
  }[k]),
  headline: k => L({
    saySomething: "Words of\nyour choosing.", askAboutThem: "What the family\nwrote down.",
    bridgeLanguage: "Across the\nlanguage.", comfort: "A little\nsteadiness.",
    storyFiction: "A small story.\nA quiet moment.", storyFromMemories: "Words worth\nkeeping.",
    readBook: "A shelf of\nfamiliar pages.",
  }[k]),
  standfirst: k => L({
    saySomething: "Write something new to be spoken in a recreated voice.",
    askAboutThem: "The answer is assembled only from the memories your family has written here. If the answer is not among them, it says so rather than inventing one.",
    bridgeLanguage: "Write in either language. It is spoken in the other, in a recreated voice.",
    comfort: "Choose a line, or write what feels right to you.",
    storyFiction: "These are invented stories, not memories or stories told by this person.",
    storyFromMemories: "A place for your memories and the words you have chosen.",
    readBook: "Bring a text. Hear it in a recreated voice, one page at a time.",
  }[k]),
  characterLimit: k => ({
    saySomething: 800, askAboutThem: 600, bridgeLanguage: 600, comfort: 400, storyFiction: 2500,
    storyFromMemories: 800, readBook: 1500,
  }[k]),
  icon: k => ({
    saySomething: "pencil", askAboutThem: "question", bridgeLanguage: "globe",
    comfort: "leaf", storyFiction: "moon",
    storyFromMemories: "tray", readBook: "book",
  }[k]),
  defaultContent: k => ({
    saySomething: "wordsSuppliedByYou", askAboutThem: "answerFromNotes",
    bridgeLanguage: "translatedWords", comfort: "comfortLine",
    storyFiction: "inventedStory", storyFromMemories: "keptWords",
    readBook: "importedText",
  }[k]),
  // Fiction must announce itself. Everything else is words a person typed.
  // Each of these is a promise about where the words came from, and the two
  // new ones are the most easily misread in the app: an answer built from
  // family notes is not the person speaking, and a translation is not their
  // phrasing. Both say so on the clip, for as long as the clip exists.
  provenanceNote: k => (k === "storyFiction" ? L("An invented story. Not a real memory.")
    : k === "readBook" ? L("Read from a file you provided.")
    : k === "askAboutThem" ? L("Assembled from your family's notes. Nothing here was invented.")
    : k === "bridgeLanguage" ? L("A translation of your words, not their own phrasing.") : null),
};

export const ContentProvenance = {
  label: k => L({
    wordsSuppliedByYou: "Words supplied by you", comfortLine: "Comfort line",
    inventedStory: "Invented story", keptWords: "Saved words",
    importedText: "From an imported file", answerWhileReading: "Answer to a question",
    answerFromNotes: "From your family's notes", translatedWords: "Translated words",
  }[k] || "Words supplied by you"),
  icon: k => ({
    wordsSuppliedByYou: "pencil", comfortLine: "leaf", inventedStory: "sparkles",
    keptWords: "tray", importedText: "doc", answerWhileReading: "question",
    answerFromNotes: "question", translatedWords: "globe",
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

/**
 * What to ask for, while they are still here to give it.
 *
 * Most families discover too late that they have nothing usable — a few
 * seconds of somebody laughing in the background of a video, and that is all.
 * The hard part is not recording, it is knowing what to ask for, so the app
 * asks for specific things rather than "record a voice sample".
 *
 * Chosen so that each one is a natural thing to say out loud, is worth having
 * for its own sake, and together they cover the range a clone needs: normal
 * speech, names, warmth and length.
 */
export const CAPTURE_PROMPTS = [
  { id: "names",   english: "Say the name of everyone in the family, one by one, the way you always say them.",
                   arabic: "اذكر اسم كل فرد في العائلة، واحدًا واحدًا، بالطريقة التي تناديهم بها دائمًا." },
  { id: "meeting", english: "Tell the story of how you met — take your time with it.",
                   arabic: "احكِ قصة كيف تقابلتما — وخذ وقتك فيها." },
  { id: "home",    english: "Describe the house you grew up in, room by room.",
                   arabic: "صف البيت الذي نشأت فيه، غرفة غرفة." },
  { id: "recipe",  english: "Talk me through making the dish you are known for.",
                   arabic: "اشرح لي طريقة تحضير الأكلة التي تشتهر بها." },
  { id: "advice",  english: "What would you want said at a wedding, years from now?",
                   arabic: "ماذا تودّ أن يُقال في عرس بعد سنوات من الآن؟" },
  { id: "bedtime", english: "Read a page of anything at all, in your ordinary reading voice.",
                   arabic: "اقرأ صفحة من أي شيء، بصوت القراءة المعتاد لديك." },
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

/**
 * fetch, but it gives up.
 *
 * Not one request in this app had a timeout. On a venue's captive portal — a
 * connection that accepts the socket and then says nothing — "Creating audio…"
 * span for ever with no cancel and no way out but a reload, which loses
 * whatever is in the compose box. A request that has not answered in this long
 * is not going to.
 */
const REQUEST_TIMEOUT_MS = 25000;

async function fetchWithTimeout(input, init = {}, ms = REQUEST_TIMEOUT_MS) {
  // A caller that brought its own signal keeps it; we only add one when there
  // is none, so nothing upstream loses the ability to cancel.
  if (init.signal || typeof AbortController === "undefined") return globalThis.fetch(input, init);
  const control = new AbortController();
  const timer = setTimeout(() => control.abort(), ms);
  try {
    return await globalThis.fetch(input, { ...init, signal: control.signal });
  } catch (e) {
    // An abort we caused reads as a timeout, not as "something went wrong".
    if (e && e.name === "AbortError") throw new TimedOut();
    throw e;
  } finally {
    clearTimeout(timer);
  }
}

export class TimedOut extends Error {
  constructor() {
    super(L("That took too long. Your words are still here — try again."));
    this.name = "TimedOut";
  }
}

async function tx(mode, fn) {
  const d = await db();
  return new Promise((resolve, reject) => {
    const t = d.transaction(BLOBS, mode);
    const store = t.objectStore(BLOBS);
    let out;
    try { out = fn(store); } catch (e) { reject(e); return; }
    t.oncomplete = () => {
      // `out` is whatever fn returned — an IDBRequest for get/put/delete.
      // Reading `.result` only when it is defined meant a MISSING key resolved
      // with the IDBRequest itself: truthy, no .size, no .type. Every caller
      // then believed the audio was there. blobURL threw instead of returning
      // null, the export threw instead of counting the file as left behind,
      // and `has()` answered true for a blob that does not exist.
      if (out && typeof out === "object" && "result" in out) {
        resolve(out.result === undefined ? null : out.result);
        return;
      }
      resolve(out === undefined ? null : out);
    };
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
    this.people = []; this.assets = []; this.notes = []; this.books = []; this.letters = [];
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
      // Absent in every library written before sealed letters existed, which
      // must still load rather than being quarantined as corrupt.
      this.letters = index.letters || [];
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
      const wrote = prefs.set(INDEX_KEY, JSON.stringify({
        people: this.people, assets: this.assets, notes: this.notes, books: this.books,
        letters: this.letters,
      }));
      // The write is only real if it reached durable storage. Held in memory
      // alone it survives until the tab closes and then is simply gone, which
      // is worse than an error because the app looked like it worked.
      if (!wrote) {
        this.storageError = L("Changes could not be saved.") + " " +
          L("There is no room left in this browser's storage.");
        this.changed();
        return false;
      }
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

  /** What the family wrote down about this person, as distinct from the comfort
   *  lines they collected. This is the entire source a grounded answer is
   *  allowed to draw on, so it must never widen to other people's notes. */
  memories(personId) {
    return this.notes.filter(n => n.personId === personId && n.kind !== "affirmation")
      .sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt));
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

  // ── words that arrive later ───────────────────────────────────────────
  // A letter holds only the words and the date. The audio is made when it is
  // opened, never in advance: generating early would spend the allowance on
  // something nobody may ever hear, and would freeze a voice that might still
  // be improved before the day comes.

  addLetter(l) {
    const letter = {
      id: uuid(), createdAt: new Date().toISOString(), openedAt: null, assetId: null, ...l,
    };
    this.letters.push(letter);
    if (!this.save()) {
      // Announcing "it will be here on the day" for something that is not on
      // disk is the cruellest possible version of this failing.
      this.letters = this.letters.filter(l => l.id !== letter.id);
      return null;
    }
    return letter;
  }

  updateLetter(l) {
    const i = this.letters.findIndex(x => x.id === l.id);
    if (i < 0) return;
    this.letters[i] = l; this.save();
  }

  removeLetter(id) { this.letters = this.letters.filter(l => l.id !== id); this.save(); }

  lettersFor(personId) {
    return this.letters.filter(l => l.personId === personId)
      .sort((a, b) => new Date(a.deliverAt) - new Date(b.deliverAt));
  }

  /**
   * Sealed, and the day has come — plus any letter whose clip no longer exists.
   *
   * Opening marks the letter and hands the clip to the player, where Discard
   * deletes it. Without the second half of this test the letter then sat in
   * neither list: no way to open it, no way to remove it, and the words
   * unreachable from anywhere in the app.
   */
  dueLetters(personId) {
    const now = Date.now();
    return this.lettersFor(personId).filter(l => {
      if (new Date(l.deliverAt).getTime() > now) return false;
      if (!l.openedAt) return true;
      const asset = l.assetId ? this.assets.find(a => a.id === l.assetId) : null;
      return !asset || !this.fileExists(asset);
    });
  }

  /** Sealed, still waiting. */
  sealedLetters(personId) {
    const now = Date.now();
    return this.lettersFor(personId)
      .filter(l => !l.openedAt && new Date(l.deliverAt).getTime() > now);
  }

  /** Opened, and the clip still exists. */
  openedLetters(personId) {
    return this.lettersFor(personId).filter(l => {
      if (!l.openedAt) return false;
      const asset = l.assetId ? this.assets.find(a => a.id === l.assetId) : null;
      return !!asset && this.fileExists(asset);
    });
  }

  /** Across everyone, for the badge on the home screen. */
  dueLetterCount() {
    const now = Date.now();
    return this.letters.filter(l => !l.openedAt && new Date(l.deliverAt).getTime() <= now).length;
  }

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
      // Which capture prompt produced this, so the list can show what has
      // already been answered rather than asking for it twice.
      promptId: opts.promptId || undefined,
    };
    this.assets.push(asset);
    if (!this.save()) {
      this.assets = this.assets.filter(a => a.id !== asset.id);
      if (blob) { try { await Blobs.del(name); } catch {} this.present.delete(name); }
      return null;
    }
    return asset;
  }

  /// Returns whether the change reached durable storage.
  ///
  /// It used to return nothing, so "Keep this clip" said "Clip saved" whether
  /// or not the save had worked. The sweep for abandoned drafts then deleted
  /// the audio, and a clip the person had explicitly chosen to keep was gone
  /// after a reload, having been told twice that it was safe.
  updateAsset(a) {
    const i = this.assets.findIndex(x => x.id === a.id);
    if (i < 0) return false;
    const before = this.assets[i];
    this.assets[i] = a;
    if (this.save()) return true;
    this.assets[i] = before;
    return false;
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
    // Sealed letters are the most private thing in here and were surviving the
    // deletion that promised to remove them — orphaned in storage, unreachable
    // from any screen, and still counted as due.
    this.letters = this.letters.filter(l => l.personId !== person.id);
    this.books = this.books.filter(b => b.personId !== person.id);
    this.people = this.people.filter(p => p.id !== person.id);
    this.save();

    // And out of Drive, if there is a copy there. Removing someone from the
    // phone while their whole archive — sealed letters included — sits in a
    // backup is not what "delete" means to anyone. Best effort: signed out, or
    // offline, this does nothing and the local deletion still stands.
    const key = person.cloudKey || person.id;
    try { await Cloud.forget(key); } catch {}
  }

  /// Where this person's backup lives in Drive.
  ///
  /// Set once and then carried, so a person who has been restored onto a new
  /// browser still writes over the same file rather than beside it. Without
  /// it, backup and restore multiplied each other: every restore made a new
  /// local id, and every backup after that made a new Drive file for it.
  async setCloudKey(person, key) {
    if (!key || person.cloudKey === key) return;
    this.updatePerson({ ...person, cloudKey: key });
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
// A key shipped inside a web page is a key anyone can read out of it, so this
// version does not carry the real ones. It talks to a relay of ours instead:
// the relay holds the ElevenLabs and Groq keys, and the page carries only a
// token that we can revoke in seconds and that cannot spend more than one
// visitor's allowance.
//
// That token is still readable in the page — there is no way to hide a
// credential the browser itself has to send — so it is not treated as a
// secret. What bounds the damage is the metering at the other end: one voice
// per browser, a ceiling across everyone, and a monthly budget for speech.
//
// Pasting your own key switches the app off the relay and straight to the
// service, because your key and our relay token cannot both be the right thing
// to send.

const K_ELEVEN = "jaddati.key.elevenlabs", K_LLM = "jaddati.key.llm";
const K_VOICE_URL = "jaddati.url.voice", K_LLM_URL = "jaddati.url.llm";
const K_DEMO = "jaddati.demo", K_DEVICE = "jaddati.device";

const read = (k, fallback = "") => prefs.get(k) || fallback;
const write = (k, v) => (v ? prefs.set(k, v) : prefs.remove(k));
const clean = u => (u || "").trim().replace(/[\s/]+$/, "");

export const RELAY_URL = "https://jaddati-proxy.sulaimanabuqamar.workers.dev";
export const STOCK_VOICE_URL = "https://api.elevenlabs.io";
export const STOCK_LLM_URL = "https://api.groq.com/openai/v1";

/** Public by necessity, and metered because of it. See the note above. */
const RELAY_TOKEN = "jd_7cvjRdcDM88CWeY5tjUjuWwqf92u_wTWlCCvlD7ZdqI";

/**
 * Which browser is spending. The relay meters against this so that one visitor
 * cannot use up the allowance everyone else needs. It is a meter reading and
 * nothing more: no name, no account, nothing stored beside it, and it goes when
 * the site's data goes.
 */
export function deviceId() {
  let id = prefs.get(K_DEVICE) || "";
  if (!/^[A-Za-z0-9-]{8,64}$/.test(id)) {
    id = newDeviceId();
    prefs.set(K_DEVICE, id);
  }
  return id;
}

function newDeviceId() {
  // randomUUID needs a secure context and getRandomValues is merely old; both
  // can be missing in an embedded preview. An id that threw would take the
  // whole app down over a meter reading, so the last resort only has to be
  // unique enough to count against.
  try { if (crypto?.randomUUID) return crypto.randomUUID(); } catch {}
  try {
    const bytes = new Uint8Array(16);
    crypto.getRandomValues(bytes);
    return [...bytes].map(n => n.toString(16).padStart(2, "0")).join("");
  } catch {}
  return "w" + Date.now().toString(36) + Math.random().toString(36).slice(2, 12);
}

export const Config = {
  /** What the visitor pasted, if anything at all. Empty means "use the relay",
   *  which is what almost everyone will be doing. */
  get personalVoiceKey() { return read(K_ELEVEN); },
  set personalVoiceKey(v) { write(K_ELEVEN, (v || "").trim()); },
  get personalTextKey() { return read(K_LLM); },
  set personalTextKey(v) { write(K_LLM, (v || "").trim()); },

  /** What actually goes on the wire: their key when they have one, our relay
   *  token when they do not, and nothing at all if they have pointed the app
   *  somewhere else without supplying a key for it. */
  get elevenKey() { return this.personalVoiceKey || (this.usesRelayVoice ? RELAY_TOKEN : ""); },
  set elevenKey(v) { this.personalVoiceKey = v; },
  get llmKey() { return this.personalTextKey || (this.usesRelayText ? RELAY_TOKEN : ""); },
  set llmKey(v) { this.personalTextKey = v; },

  // A pasted key means "go straight to the service"; no key means "go through
  // the relay". Typing either well-known address by hand is not an override at
  // all, it is a request for that same automatic pairing — which matters,
  // because the settings screen shows the current address in the box, so
  // saving an untouched form must not quietly pin it.
  get voiceBaseURL() {
    const override = clean(read(K_VOICE_URL));
    if (override) return override;
    return this.personalVoiceKey ? STOCK_VOICE_URL : RELAY_URL;
  },
  set voiceBaseURL(v) {
    const url = clean(v);
    write(K_VOICE_URL, url === RELAY_URL || url === STOCK_VOICE_URL ? "" : url);
  },
  get llmBaseURL() {
    const override = clean(read(K_LLM_URL));
    if (override) return override;
    return this.personalTextKey ? STOCK_LLM_URL : RELAY_URL;
  },
  set llmBaseURL(v) {
    const url = clean(v);
    write(K_LLM_URL, url === RELAY_URL || url === STOCK_LLM_URL ? "" : url);
  },

  get usesRelayVoice() { return this.voiceBaseURL === RELAY_URL; },
  get usesRelayText() { return this.llmBaseURL === RELAY_URL; },

  /** Rehearsal. Everything behaves as it does live, but on the browser's own
   *  speech, so running through the demo a dozen times costs nothing and
   *  leaves the real allowance for the day itself. */
  get demoOnly() { return prefs.get(K_DEMO) === "1"; },
  set demoOnly(v) { v ? prefs.set(K_DEMO, "1") : prefs.remove(K_DEMO); },

  /** No way to reach a voice service, by choice or by configuration: the app
   *  runs on the browser's own speech and says so everywhere it possibly can. */
  get isDemo() { return this.demoOnly || !this.elevenKey; },

  // The relay is a post office, not the recipient. Naming it here would tell
  // people their recording goes to a workers.dev address and stops there,
  // which is the opposite of what the consent screen has to make plain.
  get providerName() {
    if (this.isDemo) return L("Demo voice");
    if (this.usesRelayVoice || this.voiceBaseURL === STOCK_VOICE_URL) return "ElevenLabs";
    return hostOf(this.voiceBaseURL);
  },
  get textProviderName() {
    if (this.usesRelayText || this.llmBaseURL === STOCK_LLM_URL) return "Groq";
    return hostOf(this.llmBaseURL);
  },

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

/**
 * The relay is told which browser is calling so it can meter; ElevenLabs and
 * Groq are not, because they have no need for it and it is not theirs to hold.
 * Same rule as the phone build, where it hangs off the same "are we going
 * through our own address" test.
 */
function withDevice(headers, viaRelay) {
  return viaRelay ? { ...headers, "x-jaddati-device": deviceId() } : headers;
}

/// For endpoints that are OURS — the archive relay, the Google exchange.
///
/// voiceHeaders sends Config.elevenKey, which is the PERSON'S OWN ElevenLabs
/// key the moment they paste one. Sending that to our relay hands the relay's
/// operator a credential that can spend their account and delete their voices,
/// and it is not even the credential the relay wants: it checks against
/// APP_TOKEN and would refuse it, so the handoff broke outright for anyone
/// using their own key. These endpoints always speak for the app, never for
/// the person.
export const relayHeaders = (extra = {}) => ({
  "xi-api-key": RELAY_TOKEN,
  "x-jaddati-device": deviceId(),
  ...extra,
});

export const voiceHeaders = (extra = {}) =>
  withDevice({ "xi-api-key": Config.elevenKey, ...extra }, Config.usesRelayVoice);

export const textHeaders = (extra = {}) =>
  withDevice({ authorization: `Bearer ${Config.llmKey}`, ...extra }, Config.usesRelayText);

function voiceMessage(status, detail) {
  // The relay answers 403 "not this device's voice" when the sweep has already
  // lifted this device's lock — which, with a ten-minute voice lifetime, is the
  // NORMAL state by the end of a session. Reading it as a rejected key sent
  // people to check a credential that was never the problem.
  if (status === 403 && (detail || "").toLowerCase().includes("not this device")) {
    return L("That voice has already been removed at the voice service. Nothing is left to delete there.");
  }
  if (status === 401 || status === 403) return L("The key was refused by the voice service.");
  if (status === 429) {
    // Going through the relay, 429 covers two different walls, and "wait a few
    // seconds" is wrong advice for both. The wording is matched rather than a
    // code, because upstream sends the same status for genuine busyness.
    const said = (detail || "").toLowerCase();
    // Checked first: the relay says this when THIS browser is holding the
    // slot. "There is no room at the moment" would send them to go free up an
    // account they have no access to, when the thing to remove is on screen.
    if (said.includes("this device already has a voice")) {
      return L("This browser already holds a recreated voice. Remove that person, or the voice on their Setup screen, before making another.");
    }
    if (said.includes("voice limit")) {
      return L("There is no room for another voice at the moment. Remove one you have already made, or try again in a few days.");
    }
    if (said.includes("credit")) {
      return L("This month's allowance for making new speech has been used up.");
    }
    return L("The voice service is busy right now. Wait a few seconds and try again.");
  }
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
    const r = await fetchWithTimeout(`${Config.voiceBaseURL}/v1/voices/add`, {
      method: "POST", headers: voiceHeaders(), body: form,
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
    const r = await fetchWithTimeout(url, {
      method: "POST",
      headers: voiceHeaders({ "content-type": "application/json", accept: "audio/mpeg" }),
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
    const r = await fetchWithTimeout(`${Config.voiceBaseURL}/v1/voices/${encodeURIComponent(voiceId)}`, {
      method: "DELETE", headers: voiceHeaders(),
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

    const r = await fetchWithTimeout(`${Config.llmBaseURL}/chat/completions`, {
      method: "POST",
      headers: textHeaders({ "content-type": "application/json" }),
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

/**
 * Shared plumbing for the two things that ask a model for words. Both send the
 * same shape to the same endpoint; only the instructions differ, so the retry
 * and error handling live here rather than being written twice and drifting.
 */
async function chat(system, user, { maxTokens = 200, temperature = 0.3 } = {}) {
  if (!Consent.allowsNetwork) throw new ConsentMissing();
  if (!Config.llmKey) throw new CompanionError(L("Questions are not set up on this build."));

  const r = await fetchWithTimeout(`${Config.llmBaseURL}/chat/completions`, {
    method: "POST",
    headers: textHeaders({ "content-type": "application/json" }),
    body: JSON.stringify({
      model: Config.llmModel,
      messages: [{ role: "system", content: system }, { role: "user", content: user }],
      max_tokens: maxTokens, temperature,
    }),
  }).catch(() => { throw new CompanionError(L("No internet connection.")); });

  if (r.status === 429) throw new CompanionError(L("The question service is busy right now. Wait a few seconds and ask again."));
  if (!r.ok) throw new CompanionError(L("The question service reported a problem.") + ` (${r.status})`);
  const j = await r.json().catch(() => null);
  const choice = j?.choices?.[0];
  const content = choice?.message?.content;
  if (!content) throw new CompanionError(L("The question service replied in a shape the app did not understand."));
  // Cut off at the token ceiling: half a sentence, which would otherwise be
  // billed at the voice service and stored as the clip. Arabic tokenises
  // poorly enough to reach the ceiling in ordinary use.
  if (choice?.finish_reason === "length") {
    throw new CompanionError(L("The answer came back unfinished. Try again, or shorten what you wrote."));
  }
  const cleaned = tidyAnswer(content);
  if (!cleaned) throw new CompanionError(L("No answer came back. Try asking it a different way."));
  return cleaned;
}

/** The sentinel the grounded answer returns when the notes do not cover it. */
const NOT_IN_NOTES = "NOT_IN_NOTES";

/**
 * A refusal the model wrote in its own words rather than as the token.
 *
 * Deliberately narrow: short AND containing one of these. A long answer that
 * happens to mention "لا أعرف" in passing is a real answer.
 */
function readsAsRefusal(answer) {
  const t = (answer || "").trim();
  if (t.length > 120) return false;
  const lowered = t.toLowerCase();
  return [
    "لا أعرف", "لا اعرف", "غير مذكور", "غير موجود", "لا يوجد",
    "ليس في الملاحظات", "لا تذكر الملاحظات", "لم يُذكر", "لم يذكر",
    "i don't know", "i do not know", "not in the notes", "not mentioned",
    "no information", "the notes do not",
  ].some(p => lowered.includes(p));
}

export class NotInNotesError extends Error {
  constructor() {
    super(L("That is not in the memories your family has written down. Add it under Words & memories and ask again."));
    this.name = "NotInNotesError";
  }
}

/**
 * An answer built ONLY from what the family wrote down.
 *
 * The model is still never told whose voice will read this out — the same rule
 * the book companion follows, and for the same reason. What changes here is the
 * source: instead of a page of a storybook, it is given the family's own notes
 * and forbidden from going outside them. A model allowed to fill a gap will
 * invent a grandmother's favourite dish and say it warmly, and the family will
 * believe it, because it arrived in her voice.
 *
 * So the failure is made explicit rather than smoothed over: when the notes do
 * not answer the question, it returns a sentinel and the app says it does not
 * know. That refusal is the feature.
 */
export const FamilyAnswer = {
  async answer(question, notes) {
    const material = (notes || [])
      .map(n => (n.text || "").trim())
      .filter(Boolean);
    if (!material.length) throw new NotInNotesError();

    if (Config.isDemo) {
      await pause(700);
      const first = material[0];
      return L("This is the demo answer. With a question service connected, a reply drawn only from your family's notes would be written here.")
        + " " + L("Your notes say:") + " " + first.slice(0, 160);
    }

    const numbered = material.map((t, i) => `[${i + 1}] ${t}`).join("\n");
    const system = [
      "You are given a set of notes a family wrote down about someone who has died.",
      "Answer the question using ONLY the information in those notes.",
      "",
      "Rules, all of them:",
      `- If the notes do not contain the answer, reply with exactly ${NOT_IN_NOTES} and nothing else.`,
      "  Write that token in Latin letters even when answering in Arabic — it is a signal to the app,",
      "  not to a reader, and it is the ONLY case where you do not answer in the question's language.",
      "- Never guess, never generalise from what is typical, never fill a gap.",
      "- Do not speak as the person. Do not say 'I'. Do not claim to remember anything.",
      "- One or two short sentences. It will be read out loud, so write words that sound natural spoken.",
      "- Answer in the same language the question is written in.",
      "- Plain words only: no markdown, no lists, no emoji, no quotation marks around the whole answer.",
      "",
      "The notes:",
      numbered,
    ].join("\n");

    // The compose box offers 600 and the clip records all 600 as "You asked:",
    // so cutting to 300 here half-asked the question and then filed the answer
    // against wording the model never saw.
    const answer = await chat(system, String(question || "").slice(0, 600),
                              { maxTokens: 160, temperature: 0.2 });
    // Whitespace-insensitive: models routinely normalise the underscores out of
    // a token they were shown inline in prose, and "NOT IN NOTES" returned as
    // an answer would be billed, captioned "From your family's notes", and read
    // aloud in her voice. The refusal is the feature; it has to be hard to miss.
    if (answer.toUpperCase().replace(/[^A-Z]/g, "").includes("NOTINNOTES")) {
      throw new NotInNotesError();
    }
    // A model told to answer in the question's language will sometimes refuse
    // in Arabic regardless, and a scan for a Latin token cannot see that. So
    // the shape is checked too — a refusal is short and says it does not know.
    if (readsAsRefusal(answer)) throw new NotInNotesError();
    return answer;
  },
};

/**
 * Carrying words across the language a family stopped sharing.
 *
 * Deliberately a translation and nothing more: it does not try to guess how she
 * would have phrased it, because that would be invention wearing her voice. The
 * clip says so — see Intent.provenanceNote for bridgeLanguage.
 */
export const Translator = {
  /** "ar" or "en" — whichever the text is NOT. */
  targetFor(text) { return isArabicText(text) ? "en" : "ar"; },

  async translate(text, target) {
    const source = (text || "").trim();
    if (!source) return "";
    const to = target || this.targetFor(source);

    if (Config.isDemo) {
      await pause(600);
      return (to === "ar" ? "[" + L("Demo translation") + "] " : "[" + L("Demo translation") + "] ") + source;
    }

    const system = to === "ar"
      ? ["Translate the text into Arabic.",
         "Use everyday spoken Gulf wording, the way a grandmother in the Emirates would say it at home,",
         "rather than formal newspaper Arabic.",
         "Return only the translation. No transliteration, no explanation, no quotation marks."].join("\n")
      : ["Translate the text into English.",
         "Use plain, warm, spoken English — the way it would be said aloud to a child, not written formally.",
         "Return only the translation. No explanation, no quotation marks."].join("\n");

    // Roughly proportional to what it was given, with a floor so a short line
    // is never clipped and a ceiling so nothing runs away.
    const budget = Math.max(400, Math.min(1200, source.length));
    return chat(system, source.slice(0, 900), { maxTokens: budget, temperature: 0.2 });
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

// ── one voice, the whole family ─────────────────────────────────────────
// A grandmother belongs to more than one phone. This moves her to another one.
//
// What travels is the person, the family's notes, any sealed letters, the
// original recordings, and the voice identifier. That last one is why this
// works at all: the voice itself lives at the voice service, not on the phone,
// so a second device holding the same identifier can speak in it immediately
// without paying to clone her twice or filling another voice slot.
//
// What does NOT travel is anything generated. Clips are cheap to remake and
// expensive to carry, and a file large enough to choke on is a file that never
// gets sent.

export const ARCHIVE_VERSION = 1;

/** Above this, the recordings are left behind rather than making a file too
 *  large to share. Chosen to clear a WhatsApp document send with room over. */
export const ARCHIVE_MAX_BYTES = 60 * 1024 * 1024;

const toBase64 = blob => new Promise((resolve, reject) => {
  const r = new FileReader();
  r.onerror = () => reject(new Error("unreadable"));
  r.onload = () => resolve(String(r.result).split(",")[1] || "");
  r.readAsDataURL(blob);
});

const fromBase64 = (b64, type) => {
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return new Blob([bytes], { type });
};

export class ArchiveError extends Error {
  constructor(message) { super(message); this.name = "ArchiveError"; }
}


// ── signing in with Google ──────────────────────────────────────────────
// Optional, off by default, and it does exactly one thing: keep a copy of
// your own people in your own Drive so a lost phone is not a lost voice.
//
// It is NOT how you give someone to the family. Your sister's Drive is a
// different account and cannot see yours — the code handoff is for that. The
// two get confused constantly, so the screen says which is which.
//
// The folder asked for is Drive's appDataFolder: private to this app,
// invisible in the person's own Drive, and no access to a single file they
// did not put there through us.

const K_CLOUD_TOKENS = "jaddati.cloud.tokens";
const K_CLOUD_PKCE = "jaddati.cloud.pkce";
const K_CLOUD_ON = "jaddati.cloud.enabled";

const GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth";
const DRIVE_FILES = "https://www.googleapis.com/drive/v3/files";
const DRIVE_UPLOAD = "https://www.googleapis.com/upload/drive/v3/files";
const CLOUD_SCOPES = "openid email https://www.googleapis.com/auth/drive.appdata";

const b64url = bytes => btoa(String.fromCharCode(...new Uint8Array(bytes)))
  .replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");

export class CloudError extends Error {
  constructor(message) { super(message); this.name = "CloudError"; }
}

export const Cloud = {
  /** Whether the relay has been given a client id. No id, no sign-in offered:
   *  a dead button is worse than no button. */
  _configured: null,
  _clientId: "",
  /// Synchronous, for rendering. Null until the relay has been asked, which
  /// happens once at startup — so before the answer is in, nothing is shown
  /// rather than a button that might turn out to be dead.
  get isConfigured() { return this._configured === true; },
  get isUnknown() { return this._configured === null; },
  async configured() {
    // Not even asked when the answer was no. A "Sign in with Google" row on a
    // screen that says "Everything is being kept on this phone" is the app
    // contradicting itself in the space of two rows.
    // Answer false WITHOUT caching it. Cached, allowing the two services from
    // the privacy sheet left the whole Backup section hidden until a full
    // reload — so demonstrating the privacy controls first made the backup
    // disappear for the rest of the session.
    if (!Consent.allowsNetwork) return false;
    if (this._configured !== null) return this._configured;
    try {
      const r = await fetchWithTimeout(RELAY_URL + "/google/status", {
        method: "POST", headers: relayHeaders({ "content-type": "application/json" }),
        body: "{}",
      });
      const j = r.ok ? await r.json() : null;
      this._configured = !!(j && j.configured && j.clientId);
      this._clientId = j ? j.clientId : "";
    } catch { this._configured = false; }
    return this._configured;
  },

  get tokens() {
    try { return JSON.parse(prefs.get(K_CLOUD_TOKENS) || "null"); } catch { return null; }
  },
  set tokens(v) {
    if (v) prefs.set(K_CLOUD_TOKENS, JSON.stringify(v));
    else prefs.remove(K_CLOUD_TOKENS);
  },
  get isSignedIn() { return !!(this.tokens && this.tokens.refresh_token); },
  get email() { return (this.tokens && this.tokens.email) || ""; },

  get enabled() { return prefs.get(K_CLOUD_ON) === "1" && this.isSignedIn; },
  set enabled(on) { prefs.set(K_CLOUD_ON, on ? "1" : "0"); },

  get redirectURI() { return location.origin + location.pathname; },

  /// A full-page redirect, not a popup. Popups are blocked by default in
  /// mobile Safari, which is the browser this has to work in.
  async beginSignIn() {
    if (!Consent.allowsNetwork) throw new ConsentMissing();
    if (!(await this.configured())) throw new CloudError(L("Signing in is not set up on this build."));
    const verifier = b64url(crypto.getRandomValues(new Uint8Array(32)));
    const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(verifier));
    const state = b64url(crypto.getRandomValues(new Uint8Array(16)));
    prefs.set(K_CLOUD_PKCE, JSON.stringify({ verifier, state }));
    // The verifier is the only proof that the browser coming back is the one
    // that left. Private windows and blocked site data make prefs a no-op, and
    // without this check the app sent people all the way to Google's consent
    // screen and then refused them on return, every time, with nothing said
    // about why it could never work.
    if (!prefs.get(K_CLOUD_PKCE)) {
      throw new CloudError(L("This browser is not keeping site data, so signing in cannot finish. Turn that on, or use a normal window."));
    }

    const url = new URL(GOOGLE_AUTH_URL);
    url.search = new URLSearchParams({
      client_id: this._clientId,
      redirect_uri: this.redirectURI,
      response_type: "code",
      scope: CLOUD_SCOPES,
      code_challenge: b64url(digest),
      code_challenge_method: "S256",
      state,
      // Without these two Google hands back no refresh token on a repeat
      // sign-in, and the backup silently stops working an hour later.
      access_type: "offline",
      prompt: "consent",
    }).toString();
    location.assign(url.toString());
  },

  /// Called on load. Returns true when it consumed a redirect, so the caller
  /// knows to re-render rather than guess.
  async completeSignIn() {
    const params = new URLSearchParams(location.search);

    // Google answers a refusal with ?error=, not with a code. Looking only for
    // a code left that answer sitting in the address bar for the rest of the
    // session and told the person nothing at all.
    const refused = params.get("error");
    if (refused) {
      prefs.remove(K_CLOUD_PKCE);
      history.replaceState(null, "", this.redirectURI);
      // Someone closing the consent screen is not a failure, and telling them
      // it was would be the app arguing with them.
      if (refused === "access_denied") return false;
      throw new CloudError(L("Google refused that sign-in.") + " (" + refused + ")");
    }

    const code = params.get("code");
    if (!code) return false;

    let pkce = null;
    try { pkce = JSON.parse(prefs.get(K_CLOUD_PKCE) || "null"); } catch { /* below */ }
    prefs.remove(K_CLOUD_PKCE);
    // Always clear the address bar, whatever happens next: leaving a used
    // authorisation code in the URL means a refresh tries to spend it twice.
    history.replaceState(null, "", this.redirectURI);

    if (!pkce || params.get("state") !== pkce.state) {
      throw new CloudError(L("That sign-in could not be completed. Try again."));
    }

    const r = await fetchWithTimeout(RELAY_URL + "/google/exchange", {
      method: "POST", headers: relayHeaders({ "content-type": "application/json" }),
      body: JSON.stringify({ code, redirect_uri: this.redirectURI, code_verifier: pkce.verifier }),
    });
    if (!r.ok) throw new CloudError(L("That sign-in could not be completed. Try again."));
    const t = await r.json();
    this.tokens = {
      refresh_token: t.refresh_token,
      access_token: t.access_token,
      expires_at: Date.now() + (t.expires_in || 3600) * 1000,
      email: emailFromIdToken(t.id_token),
    };
    return true;
  },

  signOut() {
    this.tokens = null;
    this.enabled = false;
  },

  async accessToken() {
    const t = this.tokens;
    if (!t) throw new CloudError(L("Sign in to Google first."));
    if (t.access_token && Date.now() < t.expires_at - 60000) return t.access_token;

    const r = await fetchWithTimeout(RELAY_URL + "/google/refresh", {
      method: "POST", headers: relayHeaders({ "content-type": "application/json" }),
      body: JSON.stringify({ refresh_token: t.refresh_token }),
    });
    if (!r.ok) {
      // Only one answer means the grant itself is dead. A 500, a 429, a phone
      // that lost signal mid-refresh — none of those mean Google revoked
      // anything, and signing out on them threw away a working connection
      // whose only way back is the whole consent screen again.
      const said = await r.text().catch(() => "");
      if (r.status === 400 || r.status === 401 || said.includes("invalid_grant")) {
        this.signOut();
        throw new CloudError(L("Google access has ended. Sign in again."));
      }
      throw new CloudError(L("Could not reach Google just now. Try again in a moment."));
    }
    const fresh = await r.json();
    // A 200 carrying no token used to be stored anyway, with an hour's life on
    // it. Every later call then sent "Bearer undefined" to Drive, which 401s
    // for ever, and nothing on screen ever said why.
    if (!fresh || !fresh.access_token) {
      throw new CloudError(L("Could not reach Google just now. Try again in a moment."));
    }
    this.tokens = { ...t, access_token: fresh.access_token,
                    expires_at: Date.now() + (fresh.expires_in || 3600) * 1000 };
    return fresh.access_token;
  },

  // ── the backup itself ─────────────────────────────────────────────────
  // One file per person, and the contents are exactly the archive the code
  // handoff sends. Not a second format: a backup that cannot be read by the
  // thing that restores archives is a backup nobody has ever tested.

  async _drive(path, init = {}) {
    if (!Consent.allowsNetwork) throw new ConsentMissing();
    const token = await this.accessToken();
    const r = await fetchWithTimeout(path, {
      ...init,
      headers: { authorization: "Bearer " + token, ...(init.headers || {}) },
    });
    if (!r.ok) throw new CloudError(L("Google Drive refused that. Try again."));
    return r;
  },

  /** What is already up there, by the name we gave it. */
  async _existing() {
    const url = DRIVE_FILES + "?spaces=appDataFolder&fields=files(id,name)&pageSize=200";
    const r = await this._drive(url);
    const out = new Map();
    for (const f of (await r.json()).files || []) out.set(f.name, f.id);
    return out;
  },

  nameFor: personId => "person-" + personId + ".jaddati.json",

  /// Upload every person. Returns how many went up and how many were skipped
  /// because they were too big, because a silent partial backup is the kind
  /// that is discovered to be partial at the worst possible moment.
  async backUp(onProgress) {
    const existing = await this._existing();
    let sent = 0, skipped = 0, atRisk = 0, failed = 0;

    for (const person of store.people) {
      // One person who cannot be exported — deleted while this was running, a
      // blob gone missing — used to throw out of the loop entirely, so the
      // people already uploaded were never reported and the screen said
      // nothing at all.
      let file, carried;
      try {
        ({ file, carried } = await Archive.export(person.id));
      } catch { failed++; continue; }

      // Refuse to overwrite a good backup with an empty one.
      //
      // export() drops any recording whose blob is missing. If IndexedDB has
      // been evicted — Safari does this after seven days — the index still
      // lists her recordings while the audio is gone, so the export carries
      // nothing. Pressing "Back up now" then, which is the natural reaction
      // to seeing "Audio file missing", would PATCH the last good copy in
      // Drive with one containing no audio at all.
      // Fewer than expected, not only none. Losing two recordings of three and
      // uploading the third replaces the one complete copy in Drive with an
      // incomplete one — the exact loss this guard exists to prevent, and the
      // commoner shape of it.
      const expected = store.assetsFor(person.id, "original").length;
      if (expected > 0 && carried < expected) { atRisk++; continue; }

      const body = JSON.stringify(file);
      if (new TextEncoder().encode(body).length > 24 * 1024 * 1024) { skipped++; continue; }

      // Key the file by where this person ORIGINALLY came from, not by the
      // id this device happens to hold. A restored person arrives with a
      // fresh local id, so backing up after a restore wrote a SECOND file for
      // the same grandmother, and the next restore brought back both.
      const key = person.cloudKey || person.id;
      if (!person.cloudKey) await store.setCloudKey(person, key);
      const name = this.nameFor(key);
      const id = existing.get(name);
      const metadata = id ? { name } : { name, parents: ["appDataFolder"] };
      const boundary = "jaddati" + Math.random().toString(36).slice(2);
      const multipart =
        `--${boundary}\r\ncontent-type: application/json; charset=UTF-8\r\n\r\n` +
        JSON.stringify(metadata) +
        `\r\n--${boundary}\r\ncontent-type: application/json\r\n\r\n` +
        body + `\r\n--${boundary}--`;

      try {
        await this._drive(
          DRIVE_UPLOAD + (id ? "/" + id : "") + "?uploadType=multipart&fields=id",
          { method: id ? "PATCH" : "POST",
            headers: { "content-type": `multipart/related; boundary=${boundary}` },
            body: multipart });
      } catch { failed++; continue; }
      sent++;
      if (onProgress) onProgress(sent, store.people.length);
    }
    return { sent, skipped, atRisk, failed };
  },

  /// Remove one person's backup from Drive.
  ///
  /// Quiet by design: it is called from the delete path, where the local
  /// removal has already happened and must stand whatever happens here. Not
  /// signed in, no backup, or no connection all mean "nothing to do".
  async forget(key) {
    if (!this.isSignedIn || !Consent.allowsNetwork) return false;
    const existing = await this._existing();
    const id = existing.get(this.nameFor(key));
    if (!id) return false;
    await this._drive(DRIVE_FILES + "/" + id, { method: "DELETE" });
    return true;
  },

  /// Bring back whatever is up there. Each file goes through Archive.import,
  /// so a restored person arrives by the identical path a person from a code
  /// arrives by — same validation, same refusals, same fresh local ids.
  async restore() {
    const existing = await this._existing();
    let brought = 0, failed = 0, already = 0;

    for (const [name, id] of existing) {
      if (!name.startsWith("person-")) continue;
      // The file name carries the key. Someone already here under that key is
      // the same person, and importing again would stand a second copy of her
      // next to the first — every time the button was pressed.
      const key = name.slice("person-".length).replace(/\.jaddati\.json$/, "");
      if (store.people.some(p => (p.cloudKey || p.id) === key)) { already++; continue; }
      try {
        const r = await this._drive(DRIVE_FILES + "/" + id + "?alt=media");
        const arrived = await Archive.import(await r.text());
        // `saved` is whether the index write actually reached durable storage.
        // Counting the import as a success without it told people she was back
        // when a reload would show she had never arrived.
        if (arrived && arrived.saved === false) { failed++; continue; }
        // Remember where she came from, so backing up again writes over the
        // same file rather than beside it.
        if (arrived && arrived.person) await store.setCloudKey(arrived.person, key);
        brought++;
      } catch { failed++; }
    }
    return { brought, failed, already };
  },
};

/** The address, read out of the id token without verifying it. That is fine
 *  for a label — it came straight from the relay's own exchange — and it is
 *  never used to decide anything. */
function emailFromIdToken(idToken) {
  try {
    const body = String(idToken || "").split(".")[1];
    return JSON.parse(atob(body.replace(/-/g, "+").replace(/_/g, "/"))).email || "";
  } catch { return ""; }
}

export const Archive = {
  /**
   * Everything one person is, as a single object ready to be written to a file.
   * Originals are carried as base64 until the budget runs out, and the result
   * says plainly whether they made it — a silent partial export would have the
   * family believing the recordings are safe on the other phone.
   */
  async export(personId) {
    const person = store.person(personId);
    if (!person) throw new ArchiveError(L("That person could not be found."));

    const originals = store.assets
      .filter(a => a.personId === personId && a.source === "original" && store.fileExists(a));

    const recordings = [];
    let carried = 0, leftBehind = 0;
    for (const asset of originals) {
      const blob = await Blobs.get(asset.filename).catch(() => null);
      if (!blob) { leftBehind++; continue; }
      if (carried + blob.size > ARCHIVE_MAX_BYTES) { leftBehind++; continue; }
      carried += blob.size;
      recordings.push({
        asset: { ...asset, id: undefined, personId: undefined },
        type: blob.type || "audio/mpeg",
        data: await toBase64(blob),
      });
    }

    return {
      file: {
        jaddati: ARCHIVE_VERSION,
        exportedAt: new Date().toISOString(),
        person: { ...person, id: undefined, photoFilename: null },
        notes: store.memories(personId).map(n => ({ ...n, id: undefined, personId: undefined })),
        // Only unopened letters: an opened one is already a clip, and its day
        // has been and gone.
        letters: store.lettersFor(personId)
          .filter(l => !l.openedAt)
          .map(l => ({ ...l, id: undefined, personId: undefined, assetId: null })),
        recordings,
      },
      carried: recordings.length,
      leftBehind,
    };
  },

  /**
   * The other side. The person arrives with fresh local ids — two phones must
   * never share one — but keeps the voice identifier, which is the part that
   * makes her speak here.
   */
  /// Hand her over by code rather than by file.
  ///
  /// A file has to be found, attached, sent, found again and opened — five
  /// places a family can lose her. This puts the same bytes on the relay for
  /// a day and gives back six characters you can read down a phone.
  ///
  /// The archive is NOT smaller than the file version: it is the same bytes.
  /// When it will not fit, that is said plainly and the file is still there.
  async send(personId) {
    // The guard every other network client here carries. Without it someone
    // who answered "keep everything on this phone" could tap Give this to the
    // family and post a dead relative's recordings, their private notes and
    // their sealed letters to a server — while the privacy screen two taps
    // away still said nothing leaves the phone.
    if (!Consent.allowsNetwork) throw new ConsentMissing();
    const { file, carried, leftBehind } = await this.export(personId);
    const body = JSON.stringify(file);

    const r = await fetchWithTimeout(RELAY_URL + "/archive", {
      method: "POST",
      headers: relayHeaders({ "content-type": "application/json" }),
      body,
    });
    if (!r.ok) {
      const detail = await r.json().catch(() => null);
      throw new ArchiveError(
        r.status === 413
          ? L("This archive is too large to send by code. Use the file instead.")
          : (detail && detail.detail) || L("The code could not be created. Try again."));
    }
    const { code, hours } = await r.json();
    return { code, hours, carried, leftBehind };
  },

  /// The other side of it. Anything the relay refuses comes back as the same
  /// sentence whether the code was never real or has simply expired — the
  /// difference is no use to the person typing, and telling them which would
  /// make the codes worth guessing at.
  async fetchByCode(code) {
    // The guard every other network client here carries. Without it someone
    // who answered "keep everything on this phone" could tap Give this to the
    // family and post a dead relative's recordings, their private notes and
    // their sealed letters to a server — while the privacy screen two taps
    // away still said nothing leaves the phone.
    if (!Consent.allowsNetwork) throw new ConsentMissing();
    const r = await fetchWithTimeout(RELAY_URL + "/archive/fetch", {
      method: "POST",
      headers: relayHeaders({ "content-type": "application/json" }),
      body: JSON.stringify({ code }),
    });
    if (!r.ok) {
      throw new ArchiveError(r.status === 404
        ? L("No archive for that code. Codes last a day.")
        : L("That code could not be checked. Try again."));
    }
    return this.import(await r.text());
  },

  async import(text) {
    let file;
    try { file = JSON.parse(text); }
    catch { throw new ArchiveError(L("That file is not a Jaddati archive.")); }

    if (!file || typeof file !== "object" || !file.jaddati) {
      throw new ArchiveError(L("That file is not a Jaddati archive."));
    }
    if (file.jaddati > ARCHIVE_VERSION) {
      throw new ArchiveError(L("That archive was made by a newer version of Jaddati. Update this one first."));
    }
    if (!file.person || !file.person.name) {
      throw new ArchiveError(L("That archive has no one in it."));
    }

    const personId = uuid();
    const voiceId = typeof file.person.voiceId === "string" ? file.person.voiceId : null;
    const person = {
      ...file.person,
      name: String(file.person.name),
      fullName: typeof file.person.fullName === "string" ? file.person.fullName : "",
      relationship: typeof file.person.relationship === "string" ? file.person.relationship : "",
      // A non-string here would be concatenated straight into a request URL.
      voiceId,
      id: personId,
      photoFilename: null,
      // Carried, deliberately. Each person's Drive is their own, so there is
      // no slot to collide with — and without it, someone who arrived by code
      // is invisible to the restore check, so restoring the same archive from
      // Drive stands a second copy of her beside the first and the next backup
      // writes a second file. Only a string is accepted: this comes out of a
      // file we did not write.
      cloudKey: typeof file.person.cloudKey === "string" ? file.person.cloudKey : null,
      createdAt: file.person.createdAt || new Date().toISOString(),
      // The whole point of the handoff is that every phone speaks in the SAME
      // clone. That makes the voice shared property, so this device must not
      // delete it at the service when tidying up — whoever tidied first would
      // silently destroy it for the rest of the family, including the phone
      // that recorded and paid for it, and the others would keep reporting
      // "voice ready" until a generation failed.
      voiceIsShared: true,
    };
    store.people.push(person);

    // Everything below is shaped, not trusted. A file this app wrote is
    // well-formed; a file that reached a phone through four apps and a laptop
    // may not be, and a screen builder that throws leaves the app blank with no
    // way back but a reload — paintRoot has already cleared the root by then.
    const str = v => (typeof v === "string" ? v : "");
    const when = v => {
      const d = new Date(typeof v === "string" || typeof v === "number" ? v : NaN);
      return Number.isNaN(d.getTime()) ? null : d.toISOString();
    };
    const list = v => (Array.isArray(v) ? v : []);

    for (const n of list(file.notes)) {
      const body = str(n?.text).trim();
      if (!body) continue;
      store.notes.push({
        id: uuid(), personId, text: body,
        addedBy: str(n?.addedBy),
        createdAt: when(n?.createdAt) || new Date().toISOString(),
        kind: n?.kind === "affirmation" ? "affirmation" : undefined,
      });
    }
    for (const l of list(file.letters)) {
      const body = str(l?.text).trim();
      const deliverAt = when(l?.deliverAt);
      // A letter with no words or no date is not a letter, and carrying it
      // through would crash the screen that lists it.
      if (!body || !deliverAt) continue;
      store.letters.push({
        id: uuid(), personId, text: body,
        occasion: str(l?.occasion),
        deliverAt,
        createdAt: when(l?.createdAt) || new Date().toISOString(),
        openedAt: null, assetId: null,
      });
    }

    let restored = 0;
    for (const rec of list(file.recordings)) {
      try {
        const blob = fromBase64(rec.data, rec.type);
        const stored = await store.storeAudio(blob, {
          personId, source: "original", text: rec.asset?.text || "",
          duration: rec.asset?.durationSeconds || 0, isSaved: true,
          fileExtension: (rec.type || "").includes("wav") ? "wav"
            : (rec.type || "").includes("webm") ? "webm" : "mp3",
        });
        if (stored) restored++;
      } catch {
        // One unreadable recording must not cost the family the whole import.
      }
    }

    // The caller has to be able to tell the family what actually arrived.
    const saved = store.save();
    return {
      person,
      notes: store.memories(personId).length,
      letters: store.lettersFor(personId).length,
      recordingsOffered: list(file.recordings).length,
      restored,
      saved,
    };
  },
};
