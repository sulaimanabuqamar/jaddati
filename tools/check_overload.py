# Verifies that every call to an OVERLOADED method resolves to a declared
# overload by the argument's type. The gap that let `library.add(letter)`
# reach Xcode: the old checker confirmed `add` exists, not that an overload
# accepts a Letter.
import re, sys, pathlib

# Resolved from this file rather than from a home directory, so the checker
# runs from any clone of the repo.
REPO = pathlib.Path(__file__).resolve().parent.parent
root = REPO / "Jaddati"
files = sorted(root.rglob("*.swift"))
src = {f: f.read_text(encoding="utf-8") for f in files}
whole = "\n".join(src.values())

# 1. declared overloads: name -> {first-param type}
decls = {}
for m in re.finditer(r"func\s+(\w+)\s*\(\s*_\s+\w+\s*:\s*([\w\[\]\.<>]+)", whole):
    decls.setdefault(m.group(1), set()).add(m.group(2))
overloaded = {n: t for n, t in decls.items() if len(t) > 1}

# 2. local types of vars, from `var x = Type(` / `let x = Type(`
problems = []
for f, text in src.items():
    types = {}
    for m in re.finditer(r"\b(?:var|let)\s+(\w+)\s*=\s*([A-Z]\w+)\s*\(", text):
        types[m.group(1)] = m.group(2)
    for m in re.finditer(r"\.(\w+)\(\s*([a-z]\w*)\s*\)", text):
        name, arg = m.group(1), m.group(2)
        if name not in overloaded:
            continue
        t = types.get(arg)
        if t and t not in overloaded[name]:
            line = text[: m.start()].count("\n") + 1
            problems.append(f"{f}:{line}  .{name}({arg}) — {arg} is {t}; "
                            f"{name} accepts {sorted(overloaded[name])}")

for p in problems:
    print("OVERLOAD", p)
print(f"\n{len(overloaded)} overloaded method(s) checked: "
      + ", ".join(sorted(overloaded)))
print("PROBLEMS:", len(problems))
sys.exit(1 if problems else 0)
