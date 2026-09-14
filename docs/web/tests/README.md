# How the web half is checked

There is no compiler between writing this and shipping it, so the checking is
done in two layers: static checkers that read the source, and browser suites
that drive the real app.

## Running them

```sh
npm install -D playwright
npx playwright install chromium

# serve the app — the suites expect it on 8899
python3 -m http.server 8899 --directory ..

# then, from this folder
node test.mjs
```

`test-admin.mjs` is the exception: it serves `docs/` itself on a port of its
own, because the page it drives sits beside `web/` rather than inside it.

The relay has a suite of its own, which needs no browser and no server:

```sh
node ../../../proxy/test-relay.mjs
```

It runs the worker's own code against a fake KV and a fake fetch — who may
spend, what it costs, and which voice loses its slot when a seventh person
arrives — because none of that can be tried against the real relay before demo
day without spending real credits on a real account.

Each suite exits non-zero if anything failed and prints one line per assertion,
so a failure names the behaviour that broke rather than a line number.

## The suites

| File | What it holds the app to |
| --- | --- |
| `test.mjs` | The main path: a person, a voice, words, a clip, keeping it. |
| `test-new.mjs` | A first run from nothing — the consent gate and the empty states. |
| `test-letters.mjs` | Sealing words for a date, and opening them when the day comes. |
| `test-handoff.mjs` | The archive file: what travels, what is left behind, what is said about it. |
| `test-clips.mjs` | What a backup carries that a shared file does not, and the two shapes the two platforms write. |
| `test-code.mjs` | The six-character handoff: the alphabet, the expiry, the identical answer for missing and expired. |
| `test-capture.mjs` | Recording into the app, and the microphone being let go afterwards. |
| `test-cloud.mjs` | Google sign-in: PKCE, state, the code spent once, the scope limited to the private app folder. |
| `test-backup.mjs` | That a backup carries the clips somebody made and not only the recordings they started from. |
| `test-merge.mjs` | Restoring onto somebody who is already here: what a second press of the button adds, and everything it must not add twice or overwrite. |
| `test-speech.mjs` | What happens to the words between typing them and hearing them: a blank line becoming a pause, harakat added to bare Arabic, and the guard that refuses a model which answered the sentence instead of marking it. |
| `test-pdf.mjs` | Importing a PDF with nothing fetched off this origin, and the two kinds it refuses rather than reads wrongly. |
| `test-admin.mjs` | The roll of who has signed in: the token gate, the GET, and an address drawn as text rather than as markup. Starts its own server, because the page it drives lives outside this folder. |
| `test-durability.mjs` | The things that only break the **second** time — see below. |
| `test-nav.mjs` | Where Back goes from every screen, and that no screen is a dead end. |
| `test-rtl.mjs` | Arabic: mirroring, the things that must NOT mirror, and mixed-direction text. |
| `test-theme.mjs` | Light and dark, including the parts that resolve against the window rather than the view. |
| `test-settings.mjs` | The You tab, the language dialog, and the keys screen never showing a credential. |
| `test-regressions.mjs` | Specific bugs that have been fixed once, kept fixed. |
| `test-review.mjs`, `test-review2.mjs` | Findings from two adversarial review passes, each reproduced then closed. |
| `paths.mjs` | Where things live in the navigation. Kept in one file so a change to the app's shape is one edit here rather than fourteen across the suites — and so each suite's assertions about *behaviour* stay untouched, which is the part worth having. |

### Why `test-durability.mjs` exists separately

Everything in it passed a first run and broke on a repeat, or broke only once
something had been discarded: restore standing a second copy of the same
grandmother beside the first, a letter that could no longer be opened and could
not be removed either, a listener registered on every visit and never let go, a
sign-in thrown away because one request returned 500. None of them announce
themselves. Every case there presses the button twice.

One of its own assertions was written wrong first — it filtered for a class name
that never matched, so it passed while measuring nothing. That is worse than not
having the test, and the fixed version now asserts that it is seeing something
before it asserts that the something is not growing.

## The static checkers

These run without a browser and take about a second each.

| File | What it catches |
| --- | --- |
| `check_imports.py` | Every import resolved against what the target file actually exports. |
| `check_screens.py` | Every screen with an app bar has a scroll container, and only a tab root or a sheet with an explicit close may hide Back. |
| `check_parity.py` | The iPhone app and the web version have the same screens, the same tabs, and the same strings. |
| `check_palette.py` | All 26 colours compared between Swift and CSS, in both light and dark. |
| `contrast.py` | Every text-on-background pair against WCAG AA, in both appearances. |
| `stamp.py` | A content hash on every module URL, so a browser can never mix a new `app.js` with a cached `core.js`. |
| `check_web_strings.py` | Every `L("…")` in the web app has Arabic — including the branches of `L(cond ? a : b)`, and calls whose key is computed at run time and so can never match the table. |

The Swift side has its own set — brace balance, symbol resolution, exhaustive
switches, attribute placement, main-actor isolation, `@State` shadowing, and
palette-only colour — in `../../tools/`.

Each checker was verified against deliberately broken code before it was
trusted. Two of them passed the first time they were run and turned out to be
looking at the wrong thing: one matched its own comment, and one had been
widened to the whole tree using a string operation that removed the very
literals it was meant to search. A checker nobody has seen fail is not evidence.
