#!/usr/bin/env python3
"""Are the phone and the web the same app, or two that resemble each other?

Three things are compared. Colour has its own checker (check_palette.py).

1. SCREENS — a declared map of Swift view -> web screen function. Both sides
   must exist. A screen added to one platform and forgotten on the other is
   the most common way these two drift.

2. COPY — every L("...") key each side actually uses. If both show the same
   sentences they are saying the same things; a key on one side only means
   one platform says something the other does not.

3. NAVIGATION — the tab set, read out of each side rather than asserted.
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parents[2]
SWIFT = ROOT / "Jaddati"
WEB = ROOT / "docs/web"

def strip_swift(src):
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j; continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2); i = n if j < 0 else j + 2; continue
        out.append(src[i]); i += 1
    return "".join(out)

swift_src = "\n".join(strip_swift(p.read_text(encoding="utf-8")) for p in SWIFT.rglob("*.swift"))
web_src = "\n".join((WEB / f).read_text(encoding="utf-8")
                    for f in ("app.js", "screens.js", "ui.js", "core.js"))

problems, notes = [], []

# ── 1. screens ─────────────────────────────────────────────────────────
SCREENS = {
    "HomeView": "homeScreen", "PersonView": "personScreen", "SetupView": "setupScreen",
    "CreateView": "createScreen", "PlayerView": "playerScreen", "MemoriesView": "memoriesScreen",
    "BooksView": "booksScreen", "LettersView": "lettersScreen", "CaptureView": "captureScreen",
    "AllLettersView": "allLettersScreen", "YouView": "youScreen", "LanguageView": "languageScreen",
    "AddVoiceView": "openAddVoice", "ConsentGate": "consentGate", "PrivacyScreen": "openPrivacy",
}
for view, fn in SCREENS.items():
    on_swift = re.search(rf"struct {view}\b", swift_src) is not None
    on_web = re.search(rf"function {fn}\b", web_src) is not None
    if on_swift != on_web:
        problems.append(f"screen {view} / {fn}(): "
                        f"{'phone only' if on_swift else 'web only'}")

declared = set(SCREENS)
actual = set(re.findall(r"struct (\w+View|ConsentGate|PrivacyScreen): View", swift_src))
for extra in sorted(actual - declared):
    notes.append(f"Swift view not in the parity map: {extra}")

# ── 2. copy ────────────────────────────────────────────────────────────
def unescape(v):
    return v.replace('\\"', '"').replace("\\n", "\n").replace("\\'", "'")

def keys(src):
    """Every string the UI can show through L().

    Two shapes, and missing the second is how this checker first reported
    sixty sentences as phone-only that the web says perfectly well: the web
    keeps the intent copy as L({ ...map... }[k]), so the literals sit inside
    an object rather than directly in the call.
    """
    found = {unescape(m.group(1))
             for m in re.finditer(r'L\(\s*"((?:[^"\\]|\\.)*)"\s*\)', src)}
    for m in re.finditer(r"L\(\{", src):
        i, depth = m.end() - 1, 0
        while i < len(src):
            if src[i] == "{": depth += 1
            elif src[i] == "}":
                depth -= 1
                if depth == 0: break
            i += 1
        block = src[m.end():i]
        found |= {unescape(v) for v in re.findall(r':\s*"((?:[^"\\]|\\.)*)"', block)}
    return found

sw_keys, web_keys = keys(swift_src), keys(web_src)
# Copy that is legitimately one-sided: the web says browser things the phone
# has no notion of, and the phone says phone things the web cannot do.
WEB_ONLY_OK = {k for k in web_keys if re.search(r"browser|rehears|key|relay|Demo|DEMO", k, re.I)}
SWIFT_ONLY_OK = {k for k in sw_keys if re.search(r"Settings|microphone access|Photos|iOS", k, re.I)}

only_swift = sorted(sw_keys - web_keys - SWIFT_ONLY_OK)
only_web = sorted(web_keys - sw_keys - WEB_ONLY_OK)

# ── 3. tabs ────────────────────────────────────────────────────────────
sw_tabs = re.search(r"enum RootTab[^{]*\{\s*case ([\w, ]+)", swift_src)
sw_tabs = [t.strip() for t in sw_tabs.group(1).split(",")] if sw_tabs else []
web_tabs = re.search(r'export const TABS = \[([^\]]+)\]', (WEB / "nav.js").read_text())
web_tabs = [t.strip().strip('"') for t in web_tabs.group(1).split(",")] if web_tabs else []
if sw_tabs != web_tabs:
    problems.append(f"tabs differ: phone {sw_tabs} vs web {web_tabs}")

# ── report ─────────────────────────────────────────────────────────────
for p in problems: print("PARITY", p)
print(f"\nscreens mapped : {len(SCREENS)}")
print(f"tabs           : {sw_tabs} == {web_tabs}" if not problems or sw_tabs == web_tabs
      else f"tabs           : MISMATCH")
print(f"copy           : {len(sw_keys)} phone, {len(web_keys)} web, "
      f"{len(sw_keys & web_keys)} shared")
print(f"                 {len(only_swift)} phone-only, {len(only_web)} web-only "
      f"(after the allowed one-sided sets)")
if only_swift:
    print("\n  phone says, web does not:")
    for k in only_swift[:40]: print(f"    {k[:96]!r}")
    if len(only_swift) > 40: print(f"    … and {len(only_swift)-40} more")
if only_web:
    print("\n  web says, phone does not:")
    for k in only_web[:40]: print(f"    {k[:96]!r}")
    if len(only_web) > 40: print(f"    … and {len(only_web)-40} more")
for n in notes: print("note:", n)

print(f"\nHARD PROBLEMS: {len(problems)}")
sys.exit(1 if problems else 0)
