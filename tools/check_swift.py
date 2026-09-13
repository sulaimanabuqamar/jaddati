"""Structural checks standing in for a compiler.

Not a parser — it strips strings and comments, then balances the brackets and
cross-references the symbols the new code leans on. It catches the class of
mistake that actually happens when editing Swift without building it.
"""
import pathlib, re, sys

# Resolved from this file rather than from a home directory, so the checker
# runs from any clone of the repo.
REPO = pathlib.Path(__file__).resolve().parent.parent
root = REPO / "Jaddati"

def strip(src):
    """Remove comments and string literals so brackets inside them don't count."""
    out, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c == '"':
            if src.startswith('"""', i):
                j = src.find('"""', i + 3)
                i = n if j < 0 else j + 3
                continue
            i += 1
            while i < n and src[i] != '"':
                i += 2 if src[i] == '\\' else 1
            i += 1
            continue
        if src.startswith("//", i):
            j = src.find("\n", i); i = n if j < 0 else j
            continue
        if src.startswith("/*", i):
            j = src.find("*/", i + 2); i = n if j < 0 else j + 2
            continue
        out.append(c); i += 1
    return "".join(out)

bad = []
# Was a hand-kept list of the files being edited, which meant a brand new file
# — SetupView, YouView, AllLettersView — was never balance-checked at all.
# Everything in the tree is cheap to check and cannot go stale.
TOUCHED = sorted(str(p.relative_to(root)) for p in root.rglob("*.swift"))

for rel in TOUCHED:
    f = root / rel
    if not f.exists():
        bad.append(f"{rel}: MISSING FILE"); continue
    code = strip(f.read_text())
    for open_c, close_c, label in [("{", "}", "braces"), ("(", ")", "parens"), ("[", "]", "brackets")]:
        depth, line = 0, 1
        for ch in code:
            if ch == "\n": line += 1
            elif ch == open_c: depth += 1
            elif ch == close_c:
                depth -= 1
                if depth < 0:
                    bad.append(f"{rel}: extra '{close_c}' near line {line}"); break
        if depth > 0:
            bad.append(f"{rel}: {depth} unclosed {label}")

# Symbols the new Swift leans on must exist somewhere in the tree.
whole = "\n".join(p.read_text() for p in root.rglob("*.swift"))
needed = {
    "FamilyAnswerService": r"struct FamilyAnswerService",
    "TranslatorService":   r"struct TranslatorService",
    "NotInNotes":          r"struct NotInNotes",
    "ChatCalling":         r"protocol ChatCalling",
    "memories(for:)":      r"func memories\(for person: Person\)",
    "LLMClient.tidy":      r"static func tidy",
    "LLMClient.mapError":  r"static func mapError",
    "ConsentMissing":      r"(struct|class) ConsentMissing",
    "AppConfig.deviceId":  r"deviceId",
    "companionTimeout":    r"companionTimeout",
    "sendsTextDeviceHeader": r"sendsTextDeviceHeader",
    "resolveSpokenText":   r"func resolveSpokenText",
    "Intent.askAboutThem": r"case askAboutThem",
    "Intent.bridgeLanguage": r"case bridgeLanguage",
    "ContentProvenance.answerFromNotes": r"case answerFromNotes",
    "ContentProvenance.translatedWords": r"case translatedWords",
    "Letter":              r"struct Letter",
    "LettersView":         r"struct LettersView",
    "library.addLetter":   r"func addLetter\(for person",
    "library.dueLetters":  r"func dueLetters\(for person",
    "library.sealedLetters": r"func sealedLetters\(for person",
    "library.openedLetters": r"func openedLetters\(for person",
    "library.removeLetter":  r"func removeLetter\(",
    "library.update(Letter)": r"func update\(_ letter: Letter\)",
    "CapturePrompt":      r"struct CapturePrompt",
    "CaptureView":        r"struct CaptureView",
    "capturePrompts":     r"static let capturePrompts",
    "AudioAsset.promptId": r"var promptId",
    "LiveMeter":          r"struct LiveMeter",
    "BidiText":           r"struct BidiText",
    "QuietButtonStyle":   r"struct QuietButtonStyle",
    "VoiceRecorder":      r"class VoiceRecorder",
    "RecordingResult":    r"struct RecordingResult",
}
# Static members reached through a known namespace must actually exist on it.
# Added after AppConfig.isDemo was written into a view and sailed past a
# checker reporting "every symbol resolves" — it verified named symbols from a
# fixed list, never the members reached through a type. The real name was
# isUsingMock, and nothing here would have said so.
NAMESPACES = ["AppConfig", "Theme.Palette", "Theme.Font", "Theme.Metric",
              "Theme.Space", "Theme.Radius", "Counts", "Appearance"]
for ns in NAMESPACES:
    owner = ns.split(".")[-1]
    decl = re.search(rf"(?:enum|struct|final class|class)\s+{owner}\b[^{{]*\{{", whole)
    if not decl:
        continue
    declared = set(re.findall(r"(?:static\s+(?:let|var|func)|case)\s+(\w+)", whole[decl.end():]))
    for m in re.finditer(rf"{ns.replace('.', chr(92) + '.')}\.(\w+)", whole):
        if m.group(1) not in declared:
            bad.append(f"{ns}.{m.group(1)} does not exist on {owner}")

for label, pattern in needed.items():
    if not re.search(pattern, whole):
        bad.append(f"UNRESOLVED: {label}  (no match for /{pattern}/)")

# Every L("…") in the new Swift must have an Arabic entry.
table = set()
strings_src = (root / "Design/Strings.swift").read_text()
for m in re.finditer(r'"((?:[^"\\]|\\.)*)"\s*:\s*"', strings_src):
    table.add(m.group(1))
missing = []
# Was a hand-kept list of seven files, so four new L() strings in Archive.swift
# went in with no Arabic at all and this reported "every new L() has Arabic".
# The same stale-list mistake as the brace check. The whole tree is cheap.
for path in sorted(root.rglob("*.swift")):
    rel = path.relative_to(root)
    # NOT strip(): that removes string literals, which is exactly what this
    # rule needs to see. Using it here made the check pass by finding nothing.
    src = path.read_text()
    for m in re.finditer(r'\bL\(\s*"((?:[^"\\]|\\.)*)"\s*\)', src):
        if m.group(1) not in table:
            missing.append(f"{rel}: L(\"{m.group(1)[:60]}\") has no Arabic")
bad += missing

# Duplicate keys in the table silently override each other.
keys = re.findall(r'"((?:[^"\\]|\\.)*)"\s*:\s*"', strings_src)
dupes = {k for k in keys if keys.count(k) > 1}
if dupes:
    bad.append(f"DUPLICATE STRING KEYS: {sorted(dupes)[:5]}")

if bad:
    print("PROBLEMS:"); print("\n".join("  " + b for b in bad)); sys.exit(1)
print(f"structure OK — {len(TOUCHED)} files balanced, every symbol resolves, "
      f"every new L() has Arabic, no duplicate keys ({len(table)} entries)")
