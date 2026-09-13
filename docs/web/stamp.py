#!/usr/bin/env python3
"""Put one version on every module URL, so a browser cannot mix old with new.

The site went white twice with "does not provide an export named X" — once
because a file never reached the repo, and once because the browser had a
fresh app.js and a cached core.js at the same time. Separate files are cached
separately, so any push can leave a visitor holding a mismatched pair, and an
ES module that fails to resolve takes the WHOLE app down rather than the one
feature that needed it.

A single hash of every module's content is appended to every import. Change
any file and every URL changes together, so the set a browser holds is always
one coherent set.

Idempotent: existing stamps are stripped before the hash is computed, so
running it twice gives the same answer.

    python3 docs/web/stamp.py
"""
import hashlib
import pathlib
import re
import sys

HERE = pathlib.Path(__file__).resolve().parent
MODULES = ["prefs.js", "strings.js", "blocked-words.js", "core.js", "ui.js",
           "nav.js", "screens.js", "app.js"]
FILES = MODULES + ["index.html"]

# [\w.-] and not [\w.]: blocked-words.js has a hyphen in it, and a module the
# stamper cannot see is a module a browser can cache out of step with the rest.
STAMPED = re.compile(r'(["\'])(\.\/[\w.-]+\.js)\?v=[0-9a-f]+(["\'])')
BARE = re.compile(r'(["\'])(\.\/[\w.-]+\.js)(["\'])')
# Also written onto <html>, so anything needing to reach the SAME module
# instance the app loaded can find the URL it was loaded under. An import
# without the stamp resolves to a second, separate copy of the module — a
# whole duplicate app with its own empty store.
HTML_TAG = re.compile(r'<html([^>]*)>')
DATA_V = re.compile(r'\s*data-v="[0-9a-f]*"')

def unstamped(text):
    return STAMPED.sub(r"\1\2\3", text)

def main(check_only=False):
    raw = {}
    for name in FILES:
        text = unstamped((HERE / name).read_text(encoding="utf-8"))
        if name == "index.html":
            text = HTML_TAG.sub(lambda m: f"<html{DATA_V.sub('', m.group(1))}>", text, count=1)
        raw[name] = text

    digest = hashlib.sha256()
    for name in MODULES:
        digest.update(raw[name].encode("utf-8"))
    version = digest.hexdigest()[:10]

    changed = []
    for name in FILES:
        wanted = BARE.sub(rf"\1\2?v={version}\3", raw[name])
        if name == "index.html":
            wanted = HTML_TAG.sub(
                lambda m: f'<html{DATA_V.sub("", m.group(1))} data-v="{version}">', wanted, count=1)
        current = (HERE / name).read_text(encoding="utf-8")
        if wanted != current:
            changed.append(name)
            if not check_only:
                (HERE / name).write_text(wanted, encoding="utf-8")

    if check_only:
        if changed:
            print(f"STALE STAMP: {', '.join(changed)} — run: python3 docs/web/stamp.py")
            return 1
        print(f"every module URL carries the current version ({version})")
        return 0

    print(f"version {version} — {'updated ' + ', '.join(changed) if changed else 'already current'}")
    return 0

if __name__ == "__main__":
    raise SystemExit(main(check_only="--check" in sys.argv))
