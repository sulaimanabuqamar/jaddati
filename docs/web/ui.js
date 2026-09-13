// The pieces every screen is built from. Ported from Design/Components.swift
// and Design/Theme.swift so the two versions stay the same app.

import { L, isAr, isArabicText, dirOf, Counts, toggleLang } from "./strings.js?v=b9e6cc14ce";
import { store, blobURL, ContentProvenance, Config } from "./core.js?v=b9e6cc14ce";

// ── DOM ─────────────────────────────────────────────────────────────────

export function h(tag, props, ...kids) {
  const el = document.createElement(tag);
  if (props) for (const [k, v] of Object.entries(props)) {
    if (v === null || v === undefined || v === false) continue;
    if (k === "class") el.className = v;
    else if (k === "style" && typeof v === "object") Object.assign(el.style, v);
    else if (k === "html") el.innerHTML = v;
    else if (k.startsWith("on") && typeof v === "function") el.addEventListener(k.slice(2).toLowerCase(), v);
    else if (k === "dataset") Object.assign(el.dataset, v);
    else if (v === true) el.setAttribute(k, "");
    else el.setAttribute(k, v);
  }
  add(el, kids);
  return el;
}

function add(el, kids) {
  for (const kid of kids) {
    if (kid === null || kid === undefined || kid === false) continue;
    if (Array.isArray(kid)) { add(el, kid); continue; }
    el.append(kid instanceof Node ? kid : document.createTextNode(String(kid)));
  }
}

export const clear = el => { while (el.firstChild) el.removeChild(el.firstChild); return el; };

/** A run of text whose direction follows its own content rather than the
 *  paragraph around it — a Latin filename inside an Arabic screen otherwise
 *  reads back to front. The equivalent of <bdi dir="auto">. */
export function bidi(value, props = {}) {
  return h("bdi", { ...props, dir: dirOf(value), style: { ...(props.style || {}), textAlign: isArabicText(value) ? "right" : "left" } }, value);
}

// ── icons ───────────────────────────────────────────────────────────────
// Drawn here rather than pulled from an icon font, so the page has no network
// dependency and renders the same offline.

const PATHS = {
  back: "M19 12H5m0 0 7 7m-7-7 7-7",
  chevron: "m9 18 6-6-6-6",
  plus: "M12 5v14M5 12h14",
  globe: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 0c2.5 2.6 3.8 5.7 3.8 9s-1.3 6.4-3.8 9c-2.5-2.6-3.8-5.7-3.8-9S9.5 5.6 12 3ZM3.3 9h17.4M3.3 15h17.4",
  play: "M7 4.5v15l13-7.5-13-7.5Z",
  pause: "M8 4.5h3.5v15H8zM12.5 4.5H16v15h-3.5z",
  house: "M4 10.5 12 4l8 6.5V20a1 1 0 0 1-1 1h-4v-6H9v6H5a1 1 0 0 1-1-1v-9.5Z",
  tray: "M3 13.5h5l1.2 2.2h5.6L16 13.5h5M4.4 5.6 3 13.5V19a1 1 0 0 0 1 1h16a1 1 0 0 0 1-1v-5.5l-1.4-7.9A1 1 0 0 0 18.6 5H5.4a1 1 0 0 0-1 .6Z",
  book: "M4 4.5h6a3 3 0 0 1 3 3v12a2.5 2.5 0 0 0-2.5-2.5H4Zm16 0h-6a3 3 0 0 0-3 3v12a2.5 2.5 0 0 1 2.5-2.5H20Z",
  pencil: "M4 20h4L20 8a2.8 2.8 0 0 0-4-4L4 16v4Z",
  leaf: "M5 19C4 12 8 5 19 5c0 11-7 15-14 14Zm0 0 7-7",
  moon: "M20 14.5A8 8 0 0 1 9.5 4 8.5 8.5 0 1 0 20 14.5ZM17 3l.7 1.8L19.5 5.5 17.7 6.2 17 8l-.7-1.8L14.5 5.5l1.8-.7Z",
  sparkles: "m12 4 1.6 4.4L18 10l-4.4 1.6L12 16l-1.6-4.4L6 10l4.4-1.6Zm6 8 .8 2.2L21 15l-2.2.8L18 18l-.8-2.2L15 15l2.2-.8Z",
  doc: "M6 3h7l5 5v13H6Zm7 0v5h5M9 13h6M9 17h6",
  question: "M21 12a9 9 0 1 1-3.2-6.9M12 17h.01M9.5 9.5a2.5 2.5 0 1 1 3.4 2.3c-.6.3-.9.8-.9 1.4v.3",
  mic: "M12 3a3 3 0 0 0-3 3v6a3 3 0 0 0 6 0V6a3 3 0 0 0-3-3ZM5 11a7 7 0 0 0 14 0M12 18v3",
  trash: "M4 7h16M9 7V5h6v2M6 7l1 13h10l1-13M10 11v6M14 11v6",
  warn: "M12 3 2 20h20L12 3Zm0 6v6m0 3h.01",
  waveform: "M4 11v2M8 7v10M12 4v16M16 8v8M20 11v2",
  lock: "M6 11h12v9H6zM9 11V8a3 3 0 0 1 6 0v3",
  unlock: "M6 11h12v9H6zM9 11V8a3 3 0 0 1 5.6-1.5",
  personSlash: "M4 20c0-3.3 3.6-5 8-5 1.2 0 2.4.1 3.4.4M15 8a3 3 0 1 1-6 0 3 3 0 0 1 6 0ZM3 3l18 18",
  books: "M5 20V5h3v15Zm4 0V5h3v15Zm6.5-14.6 2.9 14.2M4 20h16",
  bookClosed: "M6 4h12v16H6zM6 8h12",
  filter: "M4 7h16M7 12h10M10 17h4",
  check: "m5 12.5 4.5 4.5L19 7.5",
  seal: "m12 3 2.1 1.5 2.6-.2.9 2.4 2.2 1.4-.8 2.5.8 2.5-2.2 1.4-.9 2.4-2.6-.2L12 18.5 9.9 17l-2.6.2-.9-2.4-2.2-1.4.8-2.5-.8-2.5 2.2-1.4.9-2.4 2.6.2Zm-2.4 8 1.9 1.9 3.9-3.9",
  dotted: "M12 3a9 9 0 1 1 0 18 9 9 0 0 1 0-18Zm0 4.5a4.5 4.5 0 1 1 0 9 4.5 4.5 0 0 1 0-9Z",
  back5: "M11 4 7 8l4 4M7 8h5a7 7 0 1 1-7 7",
  fwd5: "m13 4 4 4-4 4m4-4h-5a7 7 0 1 0 7 7",
  info: "M12 3a9 9 0 1 0 0 18 9 9 0 0 0 0-18Zm0 5h.01M11 12h1v5h1",
  key: "M14 7a4 4 0 1 1-3.4 6.1L4 20H2v-2l6.9-6.6A4 4 0 0 1 14 7Zm1.5 3h.01",
  close: "M6 6l12 12M18 6 6 18",
  // Setup lives behind a gear now, because everything under it is done once
  // and the person screen is for the thing you do every day.
  gear: "M12 9a3 3 0 1 1 0 6 3 3 0 0 1 0-6Zm8.4 3c0-.5 0-1-.1-1.4l2-1.6-2-3.4-2.4 1a7.7 7.7 0 0 0-2.4-1.4L15.1 2h-4l-.4 2.6c-.9.3-1.7.8-2.4 1.4l-2.4-1-2 3.4 2 1.6a8.4 8.4 0 0 0 0 2.8l-2 1.6 2 3.4 2.4-1c.7.6 1.5 1.1 2.4 1.4l.4 2.6h4l.4-2.6c.9-.3 1.7-.8 2.4-1.4l2.4 1 2-3.4-2-1.6c.1-.4.1-.9.1-1.4Z",
  person: "M12 12a4 4 0 1 0 0-8 4 4 0 0 0 0 8Zm-7 8.5c0-3.3 3.1-5.5 7-5.5s7 2.2 7 5.5",
};

export function icon(name, cls) {
  const d = PATHS[name] || PATHS.dotted;
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.setAttribute("viewBox", "0 0 24 24");
  svg.setAttribute("fill", "none");
  svg.setAttribute("stroke", "currentColor");
  svg.setAttribute("stroke-width", name === "play" || name === "pause" ? "0" : "1.7");
  svg.setAttribute("stroke-linecap", "round");
  svg.setAttribute("stroke-linejoin", "round");
  svg.setAttribute("aria-hidden", "true");
  if (cls) svg.setAttribute("class", cls);
  const p = document.createElementNS("http://www.w3.org/2000/svg", "path");
  p.setAttribute("d", d);
  if (name === "play" || name === "pause") p.setAttribute("fill", "currentColor");
  svg.append(p);
  return svg;
}


// ── mount lifecycle ─────────────────────────────────────────────────────
// Screens and rows register cleanup with a "jaddati:unmount" listener, which
// only fires if the element is tracked. This lived in app.js, which screens.js
// cannot import without a cycle — so every screen-level listener registered
// there was silently never called, leaking a player subscription per visit and,
// once the capture screen existed, leaving the microphone open after you left.

let mounted = [];

/** Register an element so its cleanup runs when the tree is next rebuilt. */
export const track = el => { mounted.push(el); return el; };

export function unmountAll() {
  for (const el of mounted) el.dispatchEvent(new Event("jaddati:unmount"));
  mounted = [];
}

// ── chrome ──────────────────────────────────────────────────────────────

export function appBar(title, { onBack = null, trailing = null } = {}) {
  return h("header", { class: "appbar" },
    onBack
      ? h("button", { class: "iconbtn", onClick: onBack, "aria-label": L("Back") },
          // A back arrow is directional; it mirrors in Arabic.
          icon("back", isAr() ? "flip" : null))
      : h("div", { class: "iconbtn" }),
    h("div", { class: "appbar__title" }, title || ""),
    trailing || globeButton(),
  );
}

/// The name of the language you would be switching TO, in that language.
export const otherLanguageName = () => (isAr() ? "English" : "العربية");

/// The globe asks first.
///
/// It sits in the corner of nearly every screen, it is one tap, and it
/// changes the whole interface including the direction it is laid out in.
/// Doing that to someone who brushed it while reaching for the back arrow is
/// the definition of too sudden. Choosing a language from the list in You is
/// different — going there is already the deliberate act — so that one does
/// not ask again.
export function globeButton() {
  return h("button", {
    class: "iconbtn",
    onClick: () => confirmDialog({
      title: L("Change the language?"),
      message: L("Everything changes, including what is on screen now."),
      confirm: otherLanguageName(),
      destructive: false,
      onConfirm: () => { toggleLang(); window.dispatchEvent(new Event("jaddati:lang")); },
    }),
    "aria-label": L("Language"),
  }, h("span", { class: "globe" }, icon("globe")));
}

// ── type ────────────────────────────────────────────────────────────────

export const headline = (text, size) =>
  h("h1", { class: "headline" + (size === 30 ? " headline--30" : size === 33 ? " headline--33" : "") }, text);
export const eyebrow = text => h("div", { class: "eyebrow" }, text);
export const sectionLabel = text => h("div", { class: "section-label" }, text);
export const subtext = text => h("p", { class: "subtext", style: { margin: 0 } }, text);
export const caption = text => h("p", { class: "caption", style: { margin: 0 } }, text);

// ── surfaces ────────────────────────────────────────────────────────────

export const panel = (...kids) => h("div", { class: "panel" }, ...kids);
export const panelS = (...kids) => h("div", { class: "panel panel--s" }, ...kids);

export function errorNote(message, onRetry) {
  return h("div", { class: "errornote" }, icon("warn"),
    h("div", { class: "errornote__body" },
      h("span", { style: { whiteSpace: "pre-line" } }, message),
      onRetry && h("button", { class: "wine-text", style: { fontWeight: "600", fontSize: "13px", textAlign: "start" }, onClick: onRetry }, L("Try again")),
    ));
}

export const emptyHint = (ic, title, message) =>
  h("div", { class: "empty" }, icon(ic),
    h("div", { class: "empty__title" }, title),
    h("p", { class: "subtext", style: { margin: 0 } }, message));

// ── the arch ────────────────────────────────────────────────────────────

/** Two quiet fills, chosen from the name so one person keeps the same one.
 *  Summed code points, not a hash: JS string hashing is not stable either. */
function archTint(name) {
  let sum = 0; for (const ch of name || "") sum += ch.codePointAt(0);
  return sum % 2 === 0 ? "" : " avatar--sage";
}

export function avatar(person, size = 52) {
  const name = person?.name || "";
  const el = h("div", {
    class: "avatar arch" + archTint(name),
    style: { width: size + "px", height: (size * 1.14) + "px", fontSize: (size * 0.36) + "px" },
    "aria-hidden": "true",
  }, person?.photoFilename ? "" : (name.trim()[0] || "؟"));
  if (person?.photoFilename) {
    blobURL(person.photoFilename).then(url => {
      if (url) { el.style.backgroundImage = `url("${url}")`; el.textContent = ""; }
      else el.textContent = name.trim()[0] || "؟";
    });
  }
  return el;
}

export function breadcrumb(person) {
  const words = person.relationship ? `${person.name} · ${person.relationship}` : person.name;
  return h("div", { class: "row", style: { gap: "8px" } },
    avatar(person, 22),
    bidi(words, { class: "caption", style: { whiteSpace: "nowrap", overflow: "hidden", textOverflow: "ellipsis" } }));
}

// ── badges ──────────────────────────────────────────────────────────────

/** The label that keeps original recordings and generated audio visibly
 *  distinct. The icon and the words both carry the meaning, so a screenshot
 *  that loses colour still says which one it is. */
export function sourceBadge(isGenerated) {
  const words = L(isGenerated ? "AI-recreated voice" : "Original recording");
  return h("span", { class: "badge " + (isGenerated ? "badge--gen" : "badge--orig"), "aria-label": words },
    icon(isGenerated ? "sparkles" : "mic"), words.toUpperCase());
}

export function contentBadge(kind) {
  const words = ContentProvenance.label(kind);
  return h("span", { class: "badge badge--content", "aria-label": words },
    icon(ContentProvenance.icon(kind)), words);
}

export const badgesFor = asset => h("div", { class: "badges" },
  sourceBadge(asset.source === "generated"),
  asset.source === "generated" && asset.contentKind ? contentBadge(asset.contentKind) : null);

// ── audio ───────────────────────────────────────────────────────────────

/** One player for the whole app.
 *
 *  Two kinds of clip go through it. A real one is an audio file. A demo one has
 *  no file at all — the browser speaks it — and that difference is deliberate:
 *  the demo must never leave behind something that could later be mistaken for
 *  a recording of anyone. The transport reports position for both, so the
 *  screens do not have to know which they are looking at.
 */
class Player extends EventTarget {
  constructor() {
    super();
    this.el = new Audio();
    this.el.preload = "metadata";
    this.assetId = null;
    this.playbackRate = 1;
    this.error = null;
    this.demo = null;          // { started, duration, timer }
    this.el.addEventListener("timeupdate", () => this.changed());
    this.el.addEventListener("loadedmetadata", () => this.changed());
    this.el.addEventListener("ended", () => { this.assetId = null; this.changed(); });
    this.el.addEventListener("error", () => {
      this.error = L("This audio could not be played.");
      this.assetId = null; this.changed();
    });
  }

  changed() { this.dispatchEvent(new Event("change")); }

  get isPlaying() { return this.demo ? true : (!this.el.paused && !!this.assetId); }
  playingThis(id) { return this.assetId === id && this.isPlaying; }

  get currentTime() {
    if (this.demo) return Math.min((Date.now() - this.demo.started) / 1000, this.demo.duration);
    return this.el.currentTime || 0;
  }
  get duration() {
    if (this.demo) return this.demo.duration;
    return Number.isFinite(this.el.duration) ? this.el.duration : 0;
  }
  get progress() { const d = this.duration; return d > 0 ? Math.min(Math.max(this.currentTime / d, 0), 1) : 0; }

  async play(asset) {
    this.error = null;
    if (this.assetId === asset.id && this.isPlaying) { this.pause(); return; }
    this.stop();
    this.assetId = asset.id;

    if (asset.demo) { this.speak(asset); return; }
    const url = await blobURL(asset.filename);
    if (!url) { this.error = L("Audio file missing"); this.assetId = null; this.changed(); return; }
    this.el.src = url;
    this.el.playbackRate = this.playbackRate;
    try { await this.el.play(); } catch { this.error = L("This audio could not be played."); this.assetId = null; }
    this.changed();
  }

  /** Demo clips are spoken by the browser, in whichever voice it has for the
   *  language of the words. Labelled everywhere as a demo voice — it is not a
   *  recreation of anyone, and the app never implies that it is. */
  speak(asset) {
    const synth = window.speechSynthesis;
    if (!synth) { this.error = L("This browser cannot speak the demo voice."); this.assetId = null; this.changed(); return; }
    synth.cancel();
    const u = new SpeechSynthesisUtterance(asset.text || "");
    u.lang = isArabicText(asset.text) ? "ar" : "en-US";
    u.rate = 0.9 * this.playbackRate;
    const duration = Math.max(1.2, (asset.text || "").length / 13 / (0.9 * this.playbackRate));
    u.onend = () => this.stop();
    u.onerror = () => this.stop();
    this.demo = { started: Date.now(), duration, timer: setInterval(() => {
      if (this.demo && this.currentTime >= this.demo.duration) this.stop(); else this.changed();
    }, 200) };
    try { synth.speak(u); } catch { this.stop(); return; }
    this.changed();
  }

  pause() {
    if (this.demo) { this.stop(); return; }
    this.el.pause(); this.changed();
  }

  stop() {
    if (this.demo) { clearInterval(this.demo.timer); this.demo = null; try { window.speechSynthesis?.cancel(); } catch {} }
    try { this.el.pause(); } catch {}
    this.assetId = null;
    this.changed();
  }

  seek(fraction) {
    if (this.demo) return;                         // speech cannot be scrubbed
    const d = this.duration;
    if (d > 0) { this.el.currentTime = Math.min(Math.max(fraction, 0), 1) * d; this.changed(); }
  }

  skip(seconds) {
    if (this.demo) return;
    const d = this.duration;
    if (d > 0) { this.el.currentTime = Math.min(Math.max(this.el.currentTime + seconds, 0), d); this.changed(); }
  }

  setRate(r) {
    this.playbackRate = r;
    if (!this.demo) this.el.playbackRate = r;
    this.changed();
  }
}

export const player = new Player();

/** Estimated length of a demo clip, so a row can show something honest. */
export const demoDuration = text => Math.max(1.2, (text || "").length / 13 / 0.9);

// ── rows ────────────────────────────────────────────────────────────────

export function audioRow(asset, onOpen) {
  const present = store.fileExists(asset);
  const playBtn = h("button", {
    class: "audio-row__play", disabled: !present,
    "aria-label": L("Play"),
    onClick: e => { e.stopPropagation(); if (present) player.play(asset); },
  }, icon(player.playingThis(asset.id) ? "pause" : "play"));

  const row = h("div", { class: "audio-row" + (present ? "" : " audio-row--missing") },
    playBtn,
    h("div", { class: "audio-row__body" },
      badgesFor(asset),
      asset.text
        ? bidi(asset.text, { class: "audio-row__text" })
        : h("div", { class: "audio-row__text" }, new Date(asset.createdAt).toLocaleString(isAr() ? "ar" : "en", { dateStyle: "medium", timeStyle: "short" })),
      !present
        ? h("div", { class: "small danger" }, L("Audio file missing"))
        : asset.durationSeconds > 0
          ? h("div", { class: "small" }, Counts.duration(asset.durationSeconds))
          : null,
    ),
    onOpen && h("button", {
      class: "iconbtn", style: { color: "var(--chevron)" },
      "aria-label": L("View all"), onClick: () => onOpen(asset),
    }, icon("chevron", isAr() ? "flip" : null)),
  );

  const sync = () => { clear(playBtn).append(icon(player.playingThis(asset.id) ? "pause" : "play")); };
  player.addEventListener("change", sync);
  row.addEventListener("jaddati:unmount", () => player.removeEventListener("change", sync));
  return row;
}

// ── dialogs, sheets, toasts ─────────────────────────────────────────────

export function confirmDialog({ title, message, confirm, cancel = L("Cancel"), destructive = true, onConfirm }) {
  const scrim = h("div", { class: "dialog-scrim", onClick: e => { if (e.target === scrim) close(); } },
    h("div", { class: "dialog", role: "dialog", "aria-modal": "true" },
      h("div", { class: "dialog__title" }, title),
      message && h("p", { class: "caption", style: { margin: 0, whiteSpace: "pre-line" } }, message),
      h("button", { class: destructive ? "btn-danger" : "btn-primary", onClick: () => { close(); onConfirm(); } }, confirm),
      h("button", { class: "btn-quiet", onClick: () => close() }, cancel),
    ));
  const close = () => scrim.remove();
  document.body.append(scrim);
  return close;
}

/** `build` is called with (close, scrim). The scrim is there so a sheet that
 *  holds something needing releasing — a microphone, above all — can listen
 *  for "jaddati:closed" and let it go. The close BUTTON is not enough: tapping
 *  the scrim is the commonest way a sheet gets dismissed, and it used to leave
 *  the recorder running with the browser's microphone light still on. */
export function sheet(build) {
  const scrim = h("div", { class: "sheet-scrim", onClick: e => { if (e.target === scrim) close(); } });
  const close = () => { scrim.dispatchEvent(new Event("jaddati:closed")); scrim.remove(); };
  const body = h("div", { class: "sheet", role: "dialog", "aria-modal": "true" });
  body.append(build(close, scrim));
  scrim.append(body);
  document.body.append(scrim);
  return close;
}

let toastTimer = null;
export function toast(message) {
  document.querySelector(".toast")?.remove();
  const el = h("div", { class: "toast" }, h("span", {}, message));
  document.body.append(el);
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.remove(), 3200);
}

// ── recording ───────────────────────────────────────────────────────────

/** MediaRecorder, with a visible level meter and a running clock for the whole
 *  time the microphone is open. That indicator is not decoration: an app that
 *  records without one is a recording nobody consented to. */
export class Recorder {
  constructor() { this.recorder = null; this.chunks = []; this.stream = null; this.ctx = null; }

  get isRecording() { return this.recorder?.state === "recording"; }

  async start(onLevel) {
    this.stream = await navigator.mediaDevices.getUserMedia({ audio: true });
    const mime = ["audio/webm", "audio/mp4", "audio/ogg"].find(t => MediaRecorder.isTypeSupported?.(t)) || "";
    this.recorder = new MediaRecorder(this.stream, mime ? { mimeType: mime } : undefined);
    this.chunks = [];
    this.recorder.ondataavailable = e => { if (e.data.size) this.chunks.push(e.data); };
    this.recorder.start(250);
    this.started = Date.now();

    try {
      this.ctx = new (window.AudioContext || window.webkitAudioContext)();
      const src = this.ctx.createMediaStreamSource(this.stream);
      const analyser = this.ctx.createAnalyser();
      analyser.fftSize = 512;
      src.connect(analyser);
      const data = new Uint8Array(analyser.frequencyBinCount);
      const tick = () => {
        if (!this.isRecording) return;
        analyser.getByteTimeDomainData(data);
        let peak = 0;
        for (const v of data) peak = Math.max(peak, Math.abs(v - 128) / 128);
        onLevel?.(Math.min(1, peak * 1.8), (Date.now() - this.started) / 1000);
        this.raf = requestAnimationFrame(tick);
      };
      tick();
    } catch { /* the meter is a nicety; recording still works without it */ }
  }

  stop() {
    return new Promise(resolve => {
      if (!this.recorder) { resolve(null); return; }
      const seconds = (Date.now() - this.started) / 1000;
      this.recorder.onstop = () => {
        cancelAnimationFrame(this.raf);
        this.stream?.getTracks().forEach(t => t.stop());
        this.release();
        const blob = new Blob(this.chunks, { type: this.recorder.mimeType || "audio/webm" });
        this.recorder = null;
        resolve({ blob, seconds });
      };
      try { this.recorder.stop(); } catch { resolve(null); }
    });
  }

  /// Idempotent teardown. stop() and cancel() both run on a screen that is
  /// left mid-take, and closing an AudioContext twice throws.
  release() {
    cancelAnimationFrame(this.raf);
    this.stream?.getTracks().forEach(t => t.stop());
    this.stream = null;
    const ctx = this.ctx;
    this.ctx = null;
    try { if (ctx && ctx.state !== "closed") ctx.close(); } catch {}
  }

  cancel() {
    try { this.recorder?.stop(); } catch {}
    this.release();
    this.recorder = null;
  }
}

/** Length of an audio blob, read by letting the browser decode its metadata.
 *  Some container/codec pairs report Infinity until seeked, so that is handled. */
export function durationOf(blob) {
  return new Promise(resolve => {
    const url = URL.createObjectURL(blob);
    const a = new Audio();
    let settled = false;
    const done = v => { if (settled) return; settled = true; URL.revokeObjectURL(url); resolve(v || 0); };
    a.addEventListener("loadedmetadata", () => {
      if (Number.isFinite(a.duration)) { done(a.duration); return; }
      a.currentTime = 1e101;                       // forces a real duration
      a.addEventListener("timeupdate", function once() {
        a.removeEventListener("timeupdate", once);
        done(Number.isFinite(a.duration) ? a.duration : 0);
      });
    });
    a.addEventListener("error", () => done(0));
    setTimeout(() => done(0), 4000);
    a.src = url;
  });
}
