#!/usr/bin/env python3
"""WCAG contrast for the colour pairs this app actually puts together.

Eyeballing a dark palette is how you ship 3:1 body text. Wine was picked to
sit on near-white paper; whether it still works as a FOREGROUND on a dark
ground is a number, not an opinion.

AA: 4.5 for normal text, 3.0 for large text (>=18.66px bold / 24px) and for
UI component boundaries.
"""
import re, sys, pathlib

# Beside this file, so it runs from anywhere rather than only from docs/web.
css = (pathlib.Path(__file__).resolve().parent / "app.css").read_text()

def block(after, until=None):
    i = css.index(after)
    j = css.index(until, i) if until else len(css)
    return dict(re.findall(r"(--[\w-]+):\s*([^;]+);", css[i:j]))

light = block(":root {", ":root[dir=")
dark  = {**light, **block("@media (prefers-color-scheme: dark) {", "\n}")}

def rgb(v):
    v = v.strip()
    if v.startswith("#"):
        h = v[1:]
        if len(h) == 3: h = "".join(c*2 for c in h)
        return tuple(int(h[i:i+2], 16) for i in (0, 2, 4)), 1.0
    m = re.match(r"rgba?\(([^)]+)\)", v)
    if not m: return None, None
    parts = [x.strip() for x in m.group(1).replace("/", ",").split(",")]
    a = float(parts[3]) if len(parts) > 3 else 1.0
    return tuple(int(float(x)) for x in parts[:3]), a

def over(fg, bg):
    (fc, fa), (bc, _) = fg, bg
    return tuple(fc[i]*fa + bc[i]*(1-fa) for i in range(3))

def lum(c):
    def ch(x):
        x /= 255
        return x/12.92 if x <= 0.03928 else ((x+0.055)/1.055) ** 2.4
    r, g, b = (ch(v) for v in c)
    return 0.2126*r + 0.7152*g + 0.0722*b

def ratio(fg, bg, pal):
    f, b = rgb(pal[fg] if fg in pal else fg), rgb(pal[bg] if bg in pal else bg)
    if f[0] is None or b[0] is None: return None
    fc = over(f, b) if f[1] < 1 else f[0]
    L1, L2 = sorted((lum(fc), lum(b[0])), reverse=True)
    return (L1 + 0.05) / (L2 + 0.05)

# what the app actually renders: (label, foreground, background, minimum)
PAIRS = [
    ("body text",              "--ink",        "--paper",  4.5),
    ("secondary text",         "--ink-soft",   "--paper",  4.5),
    ("small text (11px)",      "--ink-soft",   "--card",   4.5),
    ("link / .wine-text",      "--wine-ink",       "--paper",  4.5),
    ("selected tab label",     "--wine-ink",       "--paper",  4.5),
    ("card icon",              "--wine-ink",       "--card",   3.0),
    ("voice tag: ready",       "--wine-ink",       "--paper",  4.5),
    ("voice tag: pending",     "--amber",      "--paper",  4.5),
    ("voice tag: test only",   "--danger",     "--paper",  4.5),
    ("voice tag: none",        "--ink-soft",   "--paper",  4.5),
    ("primary button label",   "--cream",      "--wine",   4.5),
    ("quiet button label",     "--wine-ink",       "--sunk",   4.5),
    ("danger button label",    "--danger",     "--paper",  4.5),
    ("sage note",              "--sage",       "--paper",  4.5),
    ("avatar initial",         "--avatar-ink", "--arch-warm", 3.0),
    ("hairline on paper",      "--hairline",   "--paper",  1.0),
    ("card edge",              "--hairline",   "--card",   1.0),
]

bad = 0
for name, pal in (("LIGHT", light), ("DARK", dark)):
    print(f"\n{name}")
    for label, fg, bg, need in PAIRS:
        r = ratio(fg, bg, pal)
        if r is None:
            print(f"  ????  {label:24} (unresolved)"); continue
        ok = r >= need
        if not ok: bad += 1
        print(f"  {'ok  ' if ok else 'FAIL'}  {label:24} {r:5.2f}:1  (needs {need})")
print(f"\n{bad} pair(s) below the bar")
sys.exit(1 if bad else 0)
