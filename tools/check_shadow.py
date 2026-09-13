"""Shorthand `if let x` shadows the property with an immutable binding.

Assigning to that bare name inside the branch is a compile error when the
property is @State. `self.x = ...` is fine — it reaches past the shadow — and
that is how the rest of this codebase already does it.

Written after Xcode rejected exactly this in PersonView: two errors,
"Cannot assign to value: 'exported' is a 'let' constant" and "'nil' cannot be
assigned to type 'URL'", from one shadowed binding. Nothing structural catches
it, so this does.
"""
import pathlib, re, sys

# Resolved from this file rather than from a home directory, so the checker
# runs from any clone of the repo.
REPO = pathlib.Path(__file__).resolve().parent.parent
root = REPO / "Jaddati"
problems = []

for f in sorted(root.rglob("*.swift")):
    src = f.read_text()
    states = set(re.findall(r'@(?:State|StateObject|Binding)[^\n]*\bvar\s+(\w+)', src))
    if not states:
        continue
    for m in re.finditer(r'\bif\s+let\s+(\w+)\s*\{', src):
        name = m.group(1)
        if name not in states:
            continue
        i, depth = m.end(), 1
        while i < len(src) and depth:
            if src[i] == '{': depth += 1
            elif src[i] == '}': depth -= 1
            i += 1
        body = src[m.end():i - 1]
        # A bare assignment only — `self.x =` reaches the real property.
        bare = re.search(r'(?<![.\w=!<>])\b' + name + r'\s*=(?!=)', body)
        if bare:
            line = src[:m.start()].count("\n") + 1
            problems.append(f"  {f.relative_to(root)}:{line}  `if let {name}` shadows the "
                            f"@State, and the branch assigns to the bare name")

if problems:
    print("SHADOWED ASSIGNMENT:")
    print("\n".join(problems))
    sys.exit(1)
print("no shorthand `if let` assigns to a @State it has shadowed")
