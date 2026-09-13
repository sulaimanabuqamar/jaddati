# A colour written inline cannot follow the appearance. This is the check that
# would have caught the person cards staying cream in dark mode while the
# names on them went near-white and disappeared.
#
# The rule: Color(hex:) belongs in Theme.swift's Palette and nowhere else.
import pathlib, re, sys

# Resolved from this file rather than from a home directory, so the checker
# runs from any clone of the repo.
REPO = pathlib.Path(__file__).resolve().parent.parent
root = REPO / "Jaddati"
bad = []
for f in sorted(root.rglob("*.swift")):
    for i, line in enumerate(f.read_text(encoding="utf-8").split("\n"), 1):
        if "Color(hex:" not in line: continue
        # the Palette's own definitions and the helper that implements them
        if f.name == "Theme.swift" and ("Color.dynamic" in line
                                        or "static func dynamic" in line
                                        or "trait.userInterfaceStyle" in line
                                        or "init(hex:" in line
                                        or line.strip().startswith(("///", "//"))):
            continue
        bad.append(f"{f.relative_to(root)}:{i}  {line.strip()[:72]}")

for b in bad: print("INLINE", b)
print(f"\nPALETTE-ONLY COLOUR: {len(bad)} inline use(s)")
sys.exit(1 if bad else 0)
