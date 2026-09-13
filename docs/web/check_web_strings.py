# Every L("...") in the web app has an Arabic translation.
#
# The Swift side has had this check for a while. The web side did not, and two
# strings shipped in English inside an otherwise Arabic screen before anyone
# noticed — L() falls back to the English key, so nothing breaks loudly and
# nothing in the test suites fails. check_parity compares web against Swift, not
# web against its own translation table, so it does not catch this either.
#
# An L() argument is not always one bare literal: the app also writes
# L({ a: "One", b: "Two" }[k]) and L(cond ? "One" : "Two"), and every branch of
# those is a real key that needs Arabic. So the whole argument is read and every
# string literal inside it is checked.
#
# An L() call containing NO literal at all is reported too. Its key is computed
# at run time, which can never match the table — an interpolated key is a bug on
# its own, and that is exactly how an untranslated string hides.

import pathlib, re, sys

HERE = pathlib.Path(__file__).resolve().parent

MODULES = ["app.js", "core.js", "screens.js", "ui.js", "nav.js", "prefs.js"]
TABLE = HERE / "strings.js"

# The table's own English keys, at the start of a line inside the object.
KEY = re.compile(r'^\s*"((?:[^"\\]|\\.)*)"\s*:', re.M)
# Every string literal, so they can be pulled out of whatever the argument is.
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"|\'((?:[^\'\\]|\\.)*)\'')
# The start of an L( call. The argument is then read by balancing brackets.
CALL_START = re.compile(r'\bL\(')


def strip_comments(text):
    """Remove // and /* */ without touching string literals."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if c in "\"'`":
            quote = c
            out.append(c)
            i += 1
            while i < n:
                out.append(text[i])
                if text[i] == "\\":
                    i += 2
                    if i <= n:
                        out.append(text[i - 1])
                    continue
                if text[i] == quote:
                    i += 1
                    break
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "/":
            while i < n and text[i] != "\n":
                i += 1
            continue
        if c == "/" and i + 1 < n and text[i + 1] == "*":
            i += 2
            while i + 1 < n and not (text[i] == "*" and text[i + 1] == "/"):
                i += 1
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)



def calls(src):
    """Yield (offset, argument-text) for every L( ... ) in src.

    Brackets are balanced and quotes respected, so a nested object, a ternary or
    a call inside the argument is read whole rather than cut at the first comma.
    """
    for m in CALL_START.finditer(src):
        i = m.end()
        depth, start, n = 1, i, len(src)
        while i < n and depth:
            c = src[i]
            if c in "\"'`":
                quote = c
                i += 1
                while i < n:
                    if src[i] == "\\":
                        i += 2
                        continue
                    if src[i] == quote:
                        break
                    i += 1
            elif c in "([{":
                depth += 1
            elif c in ")]}":
                depth -= 1
                if not depth:
                    break
            i += 1
        yield m.start(), src[start:i]


def main():
    if not TABLE.exists():
        print(f"no strings table at {TABLE}")
        return 1

    table_src = TABLE.read_text(encoding="utf-8")
    known = set(KEY.findall(table_src))

    missing, dynamic = [], []

    for name in MODULES:
        path = HERE / name
        if not path.exists():
            continue
        # The table itself holds every key as a literal; skip it.
        src = strip_comments(path.read_text(encoding="utf-8"))
        for start, arg in calls(src):
            line_no = src.count("\n", 0, start) + 1
            found = [d or s2 for d, s2 in LITERAL.findall(arg)]
            if not found:
                dynamic.append((name, line_no, arg.strip()[:90]))
                continue
            for key in found:
                if key not in known:
                    missing.append((name, line_no, key))

    for name, line_no, key in missing:
        print(f"NO ARABIC   {name}:{line_no}  {key!r}")
    for name, line_no, snippet in dynamic:
        print(f"NOT LITERAL {name}:{line_no}  {snippet}")

    total = len(missing) + len(dynamic)
    print(f"\n{len(known)} translated keys. PROBLEMS: {total}")
    return 1 if total else 0


if __name__ == "__main__":
    sys.exit(main())
