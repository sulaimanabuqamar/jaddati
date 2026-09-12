// Small persistent values: the language, the tab, the consent answer, the keys.
//
// Every one of these goes through here rather than touching localStorage
// directly, because localStorage is not always there. A private window with
// site data blocked, a browser with third-party storage off, and an embedded
// frame all throw on the first access — and the consent gate reads back what
// it just wrote to decide whether it has been answered. Writing into a void
// and reading nothing back left the gate on screen forever, with the button
// doing nothing each time it was pressed.
//
// So: use the real thing when it works, and fall back to memory when it does
// not. Memory lasts one visit, which is worse than remembering, but it is a
// working app instead of a locked door.

const memory = new Map();

const available = (() => {
  try {
    const probe = "jaddati.probe";
    localStorage.setItem(probe, "1");
    localStorage.removeItem(probe);
    return true;
  } catch {
    return false;
  }
})();

export const storagePersists = available;

export const prefs = {
  get(key) {
    if (available) {
      try {
        const stored = localStorage.getItem(key);
        if (stored !== null) return stored;
      } catch { /* fall through to memory */ }
    }
    // Not only for the throwing case. Some embedded and partitioned contexts
    // accept a write without complaint and then hand back null on the read,
    // so the probe passes and every value disappears the moment it is asked
    // for. Memory is written on every set, so it is the answer whenever
    // storage has nothing — which covers both "blocked" and "pretending".
    return memory.has(key) ? memory.get(key) : null;
  },

  /**
   * Returns whether the value reached durable storage.
   *
   * It used to swallow the failure and report nothing, which made every caller
   * downstream lie: the store's own try/catch never fired, save() always
   * returned true, the quota message was unreachable, and a letter someone had
   * just sealed was announced as kept and was gone at the next reload. Memory
   * is still written either way — losing the session as well would help nobody
   * — but the caller is now told the difference.
   */
  set(key, value) {
    memory.set(key, String(value));
    if (!available) return false;
    try { localStorage.setItem(key, String(value)); return true; }
    catch { return false; }
  },

  remove(key) {
    memory.delete(key);
    if (!available) return;
    try { localStorage.removeItem(key); } catch {}
  },
};
