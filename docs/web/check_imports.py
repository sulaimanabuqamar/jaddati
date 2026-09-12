#!/usr/bin/env python3
"""Every name imported between the web modules must actually be exported.

Written after the live site went white with "The requested module './prefs.js'
does not provide an export named 'appearance'". prefs.js had gained that
export locally and the copy in the repo had not, so app.js imported something
that was not there — and a broken ES module import takes the WHOLE app down,
not the feature that needed it.

This reads the files in the repo, which is the copy that actually ships. The
browser suites run against a working tree and cannot see a file that failed to
arrive here.
"""
import pathlib, re, sys

WEB = pathlib.Path(__file__).resolve().parent
problems = []

def exports(path):
    src = path.read_text(encoding="utf-8")
    names = set()
    # export const/let/var/function/class NAME
    names |= set(re.findall(r"^export\s+(?:const|let|var|function\*?|class)\s+(\w+)", src, re.M))
    # export async function NAME
    names |= set(re.findall(r"^export\s+async\s+function\s+(\w+)", src, re.M))
    # export { a, b as c }
    for block in re.findall(r"^export\s*\{([^}]*)\}", src, re.M):
        for piece in block.split(","):
            piece = piece.strip()
            if not piece:
                continue
            names.add(piece.split(" as ")[-1].strip() if " as " in piece else piece)
    return names

cache = {}
for path in sorted(WEB.glob("*.js")):
    src = path.read_text(encoding="utf-8")
    for block, target in re.findall(r"import\s*\{([^}]*)\}\s*from\s*[\"'](\./[\w.]+)[\"']", src):
        dep = (WEB / target.lstrip("./")).resolve()
        if not dep.exists():
            problems.append(f"{path.name}: imports from {target}, which does not exist here")
            continue
        if dep not in cache:
            cache[dep] = exports(dep)
        for piece in block.split(","):
            piece = piece.strip()
            if not piece:
                continue
            wanted = piece.split(" as ")[0].strip()
            if wanted and wanted not in cache[dep]:
                problems.append(f"{path.name}: imports {wanted!r} from {target}, "
                                f"which does not export it")

for p in problems:
    print("IMPORT", p)
print(f"\n{len(list(WEB.glob('*.js')))} modules checked. PROBLEMS: {len(problems)}")
sys.exit(1 if problems else 0)
