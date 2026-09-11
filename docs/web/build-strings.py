#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Regenerate docs/web/strings.js from the app's own string table.

The web version must not drift from the phone. Every English string in
Jaddati/Design/Strings.swift is the lookup key, so this reads that table
directly rather than keeping a second copy by hand.

Strings that exist only on the web — demo mode, the key screen, anything about
a browser — live in `_strings.json` and are merged on top. Run this after
changing either side:

    python3 docs/web/build-strings.py

It refuses to write if a web-only entry has started colliding with one in the
Swift table, because at that point there are two answers to the same question.
"""

import json
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
REPO = HERE.parent.parent
SWIFT = REPO / "Jaddati" / "Design" / "Strings.swift"
EXTRA = HERE / "_strings.json"
OUT = HERE / "strings.js"


def unswift(literal: str) -> str:
    """A Swift string literal's escapes, resolved to real characters."""
    out, i = [], 0
    while i < len(literal):
        if literal[i] == "\\":
            nxt = literal[i + 1]
            if nxt == "u":                       # \u{XXXX}
                end = literal.index("}", i)
                out.append(chr(int(literal[i + 3:end], 16)))
                i = end + 1
                continue
            out.append({"n": "\n", "t": "\t", "\\": "\\", '"': '"'}.get(nxt, nxt))
            i += 2
            continue
        out.append(literal[i])
        i += 1
    return "".join(out)


def swift_table() -> dict:
    lines = SWIFT.read_text().split("\n")
    start = next(i for i, l in enumerate(lines) if l.startswith("let arabicStrings"))
    end = next(i for i, l in enumerate(lines) if i > start and l == "]")
    region = "\n".join(lines[start + 1:end])
    pair = re.compile(r'"((?:[^"\\]|\\.)*)"\s*:\s*"((?:[^"\\]|\\.)*)"')
    return {unswift(m.group(1)): unswift(m.group(2)) for m in pair.finditer(region)}


def main() -> int:
    if not SWIFT.exists():
        print(f"cannot find {SWIFT}", file=sys.stderr)
        return 1

    table = swift_table()
    extra = json.loads(EXTRA.read_text()) if EXTRA.exists() else {}

    # Entries the web adds on top of the app's own. A key present in both with
    # different Arabic means the two versions would say different things.
    clashes = [k for k, v in extra.items() if k in table and table[k] != v]
    if clashes:
        print("web-only strings collide with the app's table:", file=sys.stderr)
        for k in clashes:
            print(f"  {k!r}", file=sys.stderr)
        return 1

    merged = {**table, **extra}
    body = json.dumps(merged, ensure_ascii=False, indent=1, sort_keys=True)

    js = OUT.read_text()
    head = js.index("export const AR = ")
    tail = js.index(";\n", head)
    OUT.write_text(js[:head] + "export const AR = " + body + js[tail:])

    print(f"strings.js: {len(table)} from the app + {len(extra)} web-only = {len(merged)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
