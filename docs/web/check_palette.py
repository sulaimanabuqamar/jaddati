"""The phone and the web must be the same app, not two that resemble it.

Colour is the easiest thing to let drift: one gets a tweak, the other does
not, and nobody notices until a screenshot goes on a poster. This reads both
palettes and compares them, in both appearances.
"""
import re, sys, pathlib

# docs/web/<this file> -> the repo root, so it works from any checkout
root = pathlib.Path(__file__).resolve().parents[2]
swift = (root / "Jaddati/Design/Theme.swift").read_text(encoding="utf-8")
css   = (root / "docs/web/app.css").read_text(encoding="utf-8")

sw = {m.group(1): (m.group(2).lower(), m.group(3).lower()) for m in re.finditer(
    r"static let (\w+)\s*= Color\.dynamic\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\)", swift)}

def css_block(start, end=None):
    i = css.index(start); j = css.index(end, i) if end else len(css)
    return {k: v.strip().lower() for k, v in re.findall(r"(--[\w-]+):\s*([^;]+);", css[i:j])}

light = css_block(":root {", ":root[dir=")
dark  = {**light, **css_block(':root[data-theme="dark"] {', "\n}")}

PAIRS = {"paper":"--paper","ink":"--ink","inkSoft":"--ink-soft","hairline":"--hairline",
         "wine":"--wine","wineDeep":"--wine-deep","wineInk":"--wine-ink","wineLight":"--wine-light",
         "sage":"--sage","sageLight":"--sage-light","amber":"--amber","amberLight":"--amber-light",
         "danger":"--danger","card":"--card","bar":"--bar","sunk":"--sunk",
         "archWarm":"--arch-warm","archSage":"--arch-sage",
         "coverGreen":"--cover-green","coverRust":"--cover-rust",
         # The ones that were inline in Swift until the person cards stayed
         # cream in dark mode and the names on them disappeared.
         "card2":"--card-2","chevron":"--chevron",
         "artFill":"--art-fill","artEdge":"--art-edge",
         "cream":"--cream","cream2":"--cream-2"}

bad = 0
for name, var in PAIRS.items():
    if name not in sw:
        print(f"DRIFT  {name}: not dynamic in Theme.swift"); bad += 1; continue
    for mode, pal in (("light", light), ("dark", dark)):
        want = sw[name][0 if mode == "light" else 1]
        got = (pal.get(var) or "").lstrip("#")
        if got != want:
            print(f"DRIFT  {name} / {var} [{mode}]: swift #{want}  css #{got or '(missing)'}")
            bad += 1

print(f"\n{len(PAIRS)} colours compared across both appearances. DRIFT: {bad}")
sys.exit(1 if bad else 0)
