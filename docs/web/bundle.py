#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Flatten the app into one HTML file.

GitHub Pages serves the real thing as separate modules, which is how it should
be read and edited. An artifact is one page, so this concatenates the modules
in dependency order and strips the import/export syntax that only makes sense
across files. Nothing else changes — same code, same order.
"""

import pathlib
import re

HERE = pathlib.Path(__file__).resolve().parent
ORDER = ["prefs.js", "strings.js", "core.js", "ui.js", "nav.js", "screens.js", "app.js"]

# `import ... from "./x.js";` in any of its shapes, including across lines.
IMPORT = re.compile(r'^\s*import\s+(?:[\s\S]*?\s+from\s+)?["\'][^"\']+["\']\s*;?\s*$', re.M)
# A re-export list adds nothing once everything is in one scope.
EXPORT_LIST = re.compile(r'^\s*export\s*\{[^}]*\}\s*;?\s*$', re.M)
EXPORT_KW = re.compile(r'^(\s*)export\s+(const|let|var|function|class|async)\b', re.M)


def strip(src: str) -> str:
    src = IMPORT.sub("", src)
    src = EXPORT_LIST.sub("", src)
    src = EXPORT_KW.sub(r"\1\2", src)
    return src


def main() -> None:
    page = (HERE / "index.html").read_text()
    css = (HERE / "app.css").read_text()
    style = re.search(r"<style>(.*?)</style>", page, re.S).group(1)
    body = re.search(r"<body>(.*?)</body>", page, re.S).group(1)
    body = re.sub(r'<script type="module">.*?</script>', "", body, flags=re.S)

    parts = []
    for name in ORDER:
        code = strip((HERE / name).read_text())
        parts.append(f"// ── {name} " + "─" * (66 - len(name)) + "\n" + code.strip())
    bundle = "\n\n".join(parts)

    # setLang runs first so the page is in the right direction before the first
    # render, exactly as the multi-file entry does.
    boot = "\nsetLang(state.lang);\n"
    head = bundle.index("// ── core.js")
    bundle = bundle[:head] + boot + "\n" + bundle[head:]

    out = f"""<title>Jaddati</title>
<style>
html, body {{ height: 100%; margin: 0; }}
body {{ display: flex; flex-direction: column; }}
{css}
{style}</style>
{body.strip()}

<script type="module">
{bundle}
</script>
"""
    (HERE / "artifact.html").write_text(out)
    print(f"artifact.html: {len(out):,} bytes from {len(ORDER)} modules")


if __name__ == "__main__":
    main()
