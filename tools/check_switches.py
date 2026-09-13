"""Every switch over Intent / ContentProvenance must still cover every case.

Adding an enum case in Swift turns every exhaustive switch into a compile
error, and there is no compiler on this machine — so this stands in for one.
It reads comma-separated case lists properly: `case .a, .b, .c:` covers three.
"""
import pathlib, re, sys

# Resolved from this file rather than from a home directory, so the checker
# runs from any clone of the repo.
REPO = pathlib.Path(__file__).resolve().parent.parent
root = REPO / "Jaddati"
UNIVERSES = {
  "Intent": ["saySomething","askAboutThem","bridgeLanguage","comfort",
             "storyFiction","storyFromMemories","readBook"],
  "ContentProvenance": ["wordsSuppliedByYou","comfortLine","inventedStory","keptWords",
                        "importedText","answerWhileReading","answerFromNotes","translatedWords"],
}

def switch_bodies(text):
    for m in re.finditer(r'switch\s+([^\{]+)\{', text):
        i, depth = m.end(), 1
        while i < len(text) and depth:
            if text[i] == '{': depth += 1
            elif text[i] == '}': depth -= 1
            i += 1
        yield m.group(1).strip(), text[m.end():i-1], text[:m.start()].count("\n") + 1

def cases_in(body):
    """Names on every `case` line, including `case .a, .b:` lists."""
    found = set()
    for line in re.findall(r'^\s*case\s+([^:\n]+):', body, re.M):
        found |= set(re.findall(r'\.(\w+)', line))
    return found

problems = []
for f in sorted(root.rglob("*.swift")):
    text = f.read_text()
    for subject, body, line in switch_bodies(text):
        present = cases_in(body)
        defaulted = re.search(r'^\s*default\s*:', body, re.M) is not None
        for name, universe in UNIVERSES.items():
            if len(present & set(universe)) < 2: continue
            # A switch naming cases OUTSIDE the universe is over some other
            # enum that merely shares vocabulary — MemoriesView's
            # ExperienceFilter has .all/.story/.kept and is not an Intent.
            if present - set(universe): continue
            missing = [c for c in universe if c not in present]
            if missing and not defaulted:
                problems.append(f"  {f.relative_to(root)}:{line}  switch {subject[:24]}  "
                                f"over {name} — MISSING {missing}")

if problems:
    print("NON-EXHAUSTIVE:"); print("\n".join(problems)); sys.exit(1)
print("every switch over Intent / ContentProvenance is exhaustive or defaulted")
