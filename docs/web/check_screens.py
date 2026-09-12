#!/usr/bin/env python3
"""Two invariants about getting OUT of a screen.

Both were broken on the phone at once, which is how someone ended up on the
player with no back button and no way home.

1. A screen that draws its own AppBar must put its content in a ScrollView.
   The bar is the first child of a VStack; content laid out with Spacers and
   no scroll view overflows UPWARD when it is taller than the screen and
   takes the bar off the top with it. The web version cannot do this — there
   .screen is a flex column and .scroll takes the remainder — so it is a
   divergence as well as a bug.

2. Only a tab ROOT may hide its back control. Anything reached by a push
   must offer the way back out.
"""
import pathlib, re, sys


def code_only(src: str) -> str:
    """Comments and string literals stripped.

    Without this the check is defeated by a comment: the very comment
    explaining why PlayerView needed a ScrollView contained the word
    "ScrollView", so the broken file passed. Checked that, rather than
    assuming it.
    """
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2); i = n if j < 0 else j + 2
            continue
        if src[i] == '"':
            i += 1
            while i < n and src[i] != '"':
                i += 2 if src[i] == "\\" else 1
            i += 1
            continue
        out.append(src[i]); i += 1
    return "".join(out)

root = pathlib.Path(__file__).resolve().parents[2] / "Jaddati/Features"
TAB_ROOTS = {"AllLettersView.swift", "YouView.swift"}

problems = []
for f in sorted(root.glob("*.swift")):
    raw = f.read_text(encoding="utf-8")
    src = code_only(raw)
    if "AppBar(" not in src:
        continue

    if "ScrollView" not in src:
        problems.append(f"{f.name}: draws an AppBar with no ScrollView — "
                        f"tall content will push the bar off the top")

    # Hiding the chevron is fine in exactly two cases: a tab root, which has
    # nothing to go back TO, and a sheet that offers an explicit close instead.
    # A sheet is not wrong to use an X rather than a back arrow — it is what
    # iOS does — so the rule is "there is a way out", not "there is a chevron".
    # On the RAW text, not the stripped: the close affordance is named in a
    # string literal ("xmark"), and code_only removes those. Stripping is right
    # for the ScrollView rule and wrong for this one — the same mistake that
    # made the first version of this checker pass a broken file.
    closes = "dismiss()" in src and ("xmark" in raw or 'icon("close")' in raw)
    for i, line in enumerate(src.split("\n"), 1):
        if "showsBack: false" not in line:
            continue
        if f.name not in TAB_ROOTS and not closes:
            problems.append(f"{f.name}:{i}: hides its back control, is not a tab "
                            f"root, and offers no explicit close either")

    # A conditional back is fine only where the screen really can be a root.
    for i, line in enumerate(src.split("\n"), 1):
        m = re.search(r"showsBack: !(\w+)", line)
        if m and m.group(1) != "isTabRoot":
            problems.append(f"{f.name}:{i}: back is conditional on {m.group(1)!r}, "
                            f"which is not the tab-root flag")

for p in problems:
    print("SCREEN", p)
print(f"\n{len([f for f in root.glob('*.swift')])} screens checked. PROBLEMS: {len(problems)}")
sys.exit(1 if problems else 0)
