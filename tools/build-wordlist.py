#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Generate the refusal wordlist for all three places that need it.

The phone, the web build and the relay each have to make the same decision
about the same sentence, and a list maintained three times is a list that
disagrees with itself within a week — the same reason `build-strings.py`
exists for the Arabic table.

So `tools/blocked-words.json` is the only file anyone edits, and this writes:

    Jaddati/Services/BlockedWords.swift
    docs/web/blocked-words.js
    proxy/src/blocked-words.js

The relay gets its own copy rather than importing the web one, because
`proxy/` is a separate wrangler project and a relative import reaching up out
of it is a deploy-time surprise nobody needs the night before a demo.

Run after editing the JSON:   python3 tools/build-wordlist.py
`tools/check_wordlist.py` fails if the generated files have drifted.
"""

import io, json, os, re

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SOURCE = os.path.join(ROOT, "tools", "blocked-words.json")

REFUSE_PROFANITY = True

# ── how a sentence is compared with the list ───────────────────────────────
#
# Three passes, because there are three ways people get around a word list and
# only one of them can be handled by spelling the word correctly.
#
#   plain      lowercase, Arabic marks and tatweel dropped, alef/ya/ta-marbuta
#              forms unified, the usual digit-for-letter swaps undone, anything
#              that is not a letter turned into a space. Catches the ordinary
#              spelling, "SH1T", and the Arabic written with or without harakat.
#
#   squeezed   as above, plus runs of the same letter collapsed to one, which
#              folds "fuuuuck" onto "fuck". Applied ONLY to list words that have
#              no doubled letter of their own — squeezing "coon" produces "con",
#              and a filter that refuses every sentence containing the word
#              "con" is far worse than one that misses a creative spelling.
#
#   undotted   separators sitting between two letters removed first, so
#              "f.u.c.k" and "f-u-c-k" are read as one word.
#
# Matching is on whole words in every pass. A substring test would refuse
# Scunthorpe and "classic", which is the failure that makes people switch the
# filter off entirely.
#
# Deliberately NOT handled: "f*ck", where a letter has been replaced rather
# than separated. Someone who censors themselves has already made the decision
# this filter exists to make, and guessing the missing letter is how a filter
# starts refusing "duck".

STRIP = set(
    [chr(c) for c in range(0x064B, 0x0660)] +      # harakat
    [chr(0x0670)] +                                # superscript alef
    [chr(c) for c in range(0x06D6, 0x06EE)] +      # quranic marks
    [chr(0x0640)] +                                # tatweel
    [chr(0x200C), chr(0x200D), chr(0x200E), chr(0x200F)]
)

SWAP = {
    "أ": "ا", "إ": "ا", "آ": "ا", "ٱ": "ا",
    "ى": "ي", "ة": "ه", "ؤ": "و", "ئ": "ي",
    "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s",
}

SEPARATORS = ".-_*#%•'’"


def normalise(text, squeeze=False):
    out = []
    previous = " "
    for ch in text.lower():
        ch = SWAP.get(ch, ch)
        if ch in STRIP:
            continue
        if not ch.isalpha():
            ch = " "
        if ch == previous and (squeeze or ch == " "):
            continue
        out.append(ch)
        previous = ch
    return " " + "".join(out).strip() + " "


def undotted(text):
    return re.sub(r"(?<=[^\W\d_])[" + re.escape(SEPARATORS) + r"]+(?=[^\W\d_])", "", text)


def has_double(word):
    letters = word.replace(" ", "")
    return any(a == b for a, b in zip(letters, letters[1:]))


def entries(raw):
    """JSON list -> {"plain": [...], "squeezed": [...]}. `_` means a space."""
    plain, squeezed = [], []
    for word in raw:
        spaced = word.replace("_", " ")
        flat = normalise(spaced).strip()
        if flat and flat not in plain:
            plain.append(flat)
        if flat and not has_double(flat):
            tight = normalise(spaced, squeeze=True).strip()
            if tight and tight not in squeezed:
                squeezed.append(tight)
    return {"plain": sorted(plain), "squeezed": sorted(squeezed)}


def collisions(lists):
    """A squeezed entry that is also an ordinary English word is a trap.

    Checked at generation time rather than discovered by a user who cannot
    send a message because it mentions a con man.
    """
    common = {
        "con", "cons", "cant", "want", "dick", "ass", "hell", "damn", "kill",
        "died", "dead", "death", "god", "sex", "gay", "race", "black", "white",
        "arab", "jew", "muslim", "christian", "queer", "class", "classic",
        "assess", "grass", "pass", "bass", "miss", "kiss", "cuts", "puss",
    }
    bad = []
    for name, group in lists.items():
        for word in group["squeezed"]:
            # Only a trap when squeezing INVENTED the collision. "dick"
            # squeezes to itself and is on the list on purpose; "coon" squeezes
            # to "con", which nobody asked to refuse — that is the one to catch.
            if word in common and word not in group["plain"]:
                bad.append("%s: %r squeezes onto %r, an ordinary word"
                           % (name, word, word))
    return bad


# ── emitters ───────────────────────────────────────────────────────────────

BANNER = ("// Generated by tools/build-wordlist.py from tools/blocked-words.json.\n"
          "// Do not edit this file. Edit the JSON and run the generator.\n")

WHY = """Words this app will not put into a voice that belongs to someone who
is not here to object.

Two lists, because they are two different problems. A slur is not somebody's
grief — it is a weapon, aimed with a voice its owner cannot take back. That one
is not negotiable. Profanity is refused as well, but the case for it is much
weaker: grief is not polite, and "I miss you so fucking much" is a real
sentence a real person writes. It is a separate list behind a separate flag for
exactly that reason."""


def swift(lists):
    def arr(name, words):
        if not words:
            return "    static let %s: [String] = []\n" % name
        body = ",\n        ".join('"%s"' % w for w in words)
        return "    static let %s: [String] = [\n        %s\n    ]\n" % (name, body)

    doc = "\n".join("/// " + line for line in WHY.splitlines())
    out = [BANNER, "\nimport Foundation\n\n", doc, "\nenum BlockedWords {\n\n",
           "    /// Flip this and the slur list is untouched.\n",
           "    static let refuseProfanity = %s\n\n" % ("true" if REFUSE_PROFANITY else "false")]
    for name in ("slurs", "sexual", "profanity"):
        out.append(arr(name, lists[name]["plain"]))
        out.append(arr(name + "Squeezed", lists[name]["squeezed"]))
        out.append("\n")
    out.append('''    private static let strip: Set<Character> = {
        var set: Set<Character> = ["\\u{0640}", "\\u{200C}", "\\u{200D}", "\\u{200E}", "\\u{200F}", "\\u{0670}"]
        for code in 0x064B...0x065F { set.insert(Character(UnicodeScalar(code)!)) }
        for code in 0x06D6...0x06ED { set.insert(Character(UnicodeScalar(code)!)) }
        return set
    }()

    private static let swap: [Character: Character] = [
        "\\u{0623}": "\\u{0627}", "\\u{0625}": "\\u{0627}", "\\u{0622}": "\\u{0627}",
        "\\u{0671}": "\\u{0627}", "\\u{0649}": "\\u{064A}", "\\u{0629}": "\\u{0647}",
        "\\u{0624}": "\\u{0648}", "\\u{0626}": "\\u{064A}",
        "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s",
    ]

    private static let separators: Set<Character> = [".", "-", "_", "*", "#", "%", "\\u{2022}", "'", "\\u{2019}"]

    /// Must agree, character for character, with `normalise` in the JavaScript
    /// copies. tools/check_wordlist.py holds all three to the same vectors.
    static func normalise(_ text: String, squeeze: Bool = false) -> String {
        var out = ""
        out.reserveCapacity(text.count + 2)
        var previous: Character = " "
        for raw in text.lowercased() {
            var character = swap[raw] ?? raw
            if strip.contains(character) { continue }
            if !character.isLetter { character = " " }
            if character == previous && (squeeze || character == " ") { continue }
            out.append(character)
            previous = character
        }
        return " " + out.trimmingCharacters(in: .whitespaces) + " "
    }

    /// "f.u.c.k" and "f-u-c-k" read as one word. A separator only counts when
    /// it sits between two letters, so hyphenated names survive.
    static func undotted(_ text: String) -> String {
        var out = ""
        let characters = Array(text)
        for (index, character) in characters.enumerated() {
            if separators.contains(character),
               index > 0, index + 1 < characters.count,
               characters[index - 1].isLetter, characters[index + 1].isLetter {
                continue
            }
            out.append(character)
        }
        return out
    }

    /// The first refused word, or nil. The caller decides how much to say; the
    /// app deliberately does not repeat the word back on screen.
    static func refusal(in text: String) -> String? {
        for candidate in [text, undotted(text)] {
            let plain = normalise(candidate)
            let tight = normalise(candidate, squeeze: true)
            for (words, squeezed) in groups {
                for word in words where plain.contains(" " + word + " ") { return word }
                for word in squeezed where tight.contains(" " + word + " ") { return word }
            }
        }
        return nil
    }

    private static var groups: [([String], [String])] {
        var all: [([String], [String])] = [(slurs, slursSqueezed), (sexual, sexualSqueezed)]
        if refuseProfanity { all.append((profanity, profanitySqueezed)) }
        return all
    }
}
''')
    return "".join(out)


def javascript(lists, for_worker):
    def arr(name, words):
        body = ",\n  ".join('"%s"' % w for w in words)
        return "export const %s = [\n  %s\n];\n" % (name, body) if words else \
               "export const %s = [];\n" % name

    who = "the relay" if for_worker else "the web build"
    out = [BANNER, "\n", "\n".join("// " + l for l in WHY.splitlines()),
           "\n//\n// This copy is %s's. See tools/blocked-words.json.\n\n" % who,
           "export const REFUSE_PROFANITY = %s;\n\n" % ("true" if REFUSE_PROFANITY else "false")]
    for name in ("slurs", "sexual", "profanity"):
        out.append(arr(name.upper(), lists[name]["plain"]))
        out.append(arr(name.upper() + "_SQUEEZED", lists[name]["squeezed"]))
        out.append("\n")
    out.append('''const STRIP = new Set([
  "\\u0640", "\\u200C", "\\u200D", "\\u200E", "\\u200F", "\\u0670",
  ...Array.from({ length: 0x0660 - 0x064B }, (_, i) => String.fromCharCode(0x064B + i)),
  ...Array.from({ length: 0x06EE - 0x06D6 }, (_, i) => String.fromCharCode(0x06D6 + i)),
]);

const SWAP = {
  "\\u0623": "\\u0627", "\\u0625": "\\u0627", "\\u0622": "\\u0627", "\\u0671": "\\u0627",
  "\\u0649": "\\u064A", "\\u0629": "\\u0647", "\\u0624": "\\u0648", "\\u0626": "\\u064A",
  "0": "o", "1": "i", "3": "e", "4": "a", "5": "s", "7": "t", "@": "a", "$": "s",
};

const SEPARATORS = new Set([".", "-", "_", "*", "#", "%", "\\u2022", "'", "\\u2019"]);
const LETTER = /\\p{L}/u;

/** Must agree, character for character, with BlockedWords.normalise in Swift. */
export function normalise(text, squeeze = false) {
  let out = "";
  let previous = " ";
  for (let ch of String(text || "").toLowerCase()) {
    if (SWAP[ch]) ch = SWAP[ch];
    if (STRIP.has(ch)) continue;
    if (!LETTER.test(ch)) ch = " ";
    if (ch === previous && (squeeze || ch === " ")) continue;
    out += ch;
    previous = ch;
  }
  return " " + out.trim() + " ";
}

export function undotted(text) {
  const chars = Array.from(String(text || ""));
  let out = "";
  for (let i = 0; i < chars.length; i++) {
    if (SEPARATORS.has(chars[i]) && i > 0 && i + 1 < chars.length &&
        LETTER.test(chars[i - 1]) && LETTER.test(chars[i + 1])) continue;
    out += chars[i];
  }
  return out;
}

/** The first refused word, or "" if there is none. */
export function refusal(text) {
  const groups = [[SLURS, SLURS_SQUEEZED], [SEXUAL, SEXUAL_SQUEEZED]];
  if (REFUSE_PROFANITY) groups.push([PROFANITY, PROFANITY_SQUEEZED]);
  for (const candidate of [text, undotted(text)]) {
    const plain = normalise(candidate);
    const tight = normalise(candidate, true);
    for (const [words, squeezed] of groups) {
      for (const word of words) if (plain.includes(" " + word + " ")) return word;
      for (const word of squeezed) if (tight.includes(" " + word + " ")) return word;
    }
  }
  return "";
}
''')
    return "".join(out)


def main():
    raw = json.load(io.open(SOURCE, encoding="utf-8"))
    lists = {name: entries(raw.get(name, [])) for name in ("slurs", "sexual", "profanity")}

    trapped = collisions(lists)
    if trapped:
        print("REFUSING TO GENERATE — a squeezed entry collides with a real word:")
        for line in trapped:
            print("  " + line)
        raise SystemExit(1)

    for path, text in [
        (os.path.join(ROOT, "Jaddati", "Services", "BlockedWords.swift"), swift(lists)),
        (os.path.join(ROOT, "docs", "web", "blocked-words.js"), javascript(lists, False)),
        (os.path.join(ROOT, "proxy", "src", "blocked-words.js"), javascript(lists, True)),
    ]:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        io.open(path, "w", encoding="utf-8").write(text)

    counts = ", ".join("%d %s" % (len(lists[n]["plain"]), n) for n in lists)
    print("blocked-words: %s -> 3 files" % counts)


if __name__ == "__main__":
    main()
