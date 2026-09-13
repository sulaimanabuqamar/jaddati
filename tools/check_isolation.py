# Two things a compiler would have said instantly, and a move-by-script would
# not: an attribute left with nothing to attach to, and an async method that
# writes @State without being pinned to the main actor.
#
# The second is the one that matters. SE-0338: a nonisolated async method does
# NOT inherit its caller's actor, so its @State writes happen off the main
# thread and SwiftUI may simply lose them. It compiles clean either way.
import pathlib, re, sys

# Resolved from this file rather than from a home directory, so the checker
# runs from any clone of the repo.
REPO = pathlib.Path(__file__).resolve().parent.parent
root = REPO / "Jaddati"
problems = []

DECL = re.compile(r"^\s*(@\w+[\w(): .,]*)?\s*"
                  r"(public |private |internal |fileprivate |static |final |override )*"
                  r"(func|var|let|struct|enum|class|init|subscript|case)\b")

for f in sorted(root.rglob("*.swift")):
    lines = f.read_text(encoding="utf-8").split("\n")
    rel = f.relative_to(root)

    # (a) an attribute line whose next meaningful line is not a declaration
    for i, line in enumerate(lines):
        if not re.fullmatch(r"\s*@\w+(\(.*\))?\s*", line or ""):
            continue
        j = i + 1
        # Attributes stack: `@MainActor` / `@discardableResult` / `func` is
        # ordinary Swift. Skip over any further attribute lines, or the checker
        # reports a false alarm on every stacked pair — and a checker that
        # cries wolf is one nobody reads.
        while j < len(lines) and (
            not lines[j].strip()
            or lines[j].lstrip().startswith("//")
            or re.fullmatch(r"\s*@\w+(\(.*\))?\s*", lines[j] or "")
        ):
            j += 1
        if j >= len(lines) or not DECL.match(lines[j]):
            found = lines[j].strip()[:40] if j < len(lines) else "end of file"
            problems.append(f"{rel}:{i+1}  {line.strip()} attaches to nothing (next: {found!r})")

    # (b) an async func that writes @State but is not @MainActor
    state = set(re.findall(r"@State\s+(?:private\s+)?var\s+(\w+)", "\n".join(lines)))
    for i, line in enumerate(lines):
        m = re.match(r"\s*(?:private |public )?func\s+(\w+)\s*\(.*\)\s*async", line)
        if not m:
            continue
        before = [l.strip() for l in lines[max(0, i-12):i]]
        if any(l.startswith("@MainActor") for l in before):
            continue
        depth, body, j = 0, [], i
        opened = False
        while j < len(lines):
            for ch in lines[j]:
                if ch == "{": depth += 1; opened = True
                elif ch == "}": depth -= 1
            body.append(lines[j])
            if opened and depth == 0: break
            j += 1
        text = "\n".join(body)
        written = sorted(v for v in state if re.search(rf"(?<![\w.]){v}\s*=(?!=)", text))
        if written:
            problems.append(f"{rel}:{i+1}  async {m.group(1)}() writes @State "
                            f"{written} with no @MainActor — SE-0338, those land off-main")

for p in problems:
    print("ISOLATION", p)
print(f"\n{len(list(root.rglob('*.swift')))} files checked. PROBLEMS: {len(problems)}")
sys.exit(1 if problems else 0)
