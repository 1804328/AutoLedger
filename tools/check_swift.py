import sys

FILES = [
    "AutoLedger/Views/ReceiptScanSheet.swift",
    "AutoLedger/Parser/ReceiptOCR.swift",
    "AutoLedger/Parser/NaturalParser.swift",
    "AutoLedger/Store/LedgerStore.swift",
    "AutoLedger/Views/ShortcutGuideView.swift",
]

BS = chr(92)


def strip(src):
    out = []
    i, n = 0, len(src)
    state = None
    while i < n:
        c = src[i]
        if state is None:
            if c == "/" and i + 1 < n and src[i + 1] == "/":
                state = "line"; i += 2; continue
            if c == "/" and i + 1 < n and src[i + 1] == "*":
                state = "block"; i += 2; continue
            if c == '"':
                if src[i:i + 3] == '"""':
                    state = "raw3"; i += 3; continue
                state = "str"; i += 1; continue
            out.append(c); i += 1
        elif state == "line":
            if c == "\n":
                state = None; out.append(c)
            i += 1
        elif state == "block":
            if c == "*" and i + 1 < n and src[i + 1] == "/":
                state = None; i += 2; continue
            i += 1
        elif state == "str":
            if c == BS:
                i += 2; continue
            if c == '"':
                state = None
            i += 1
        elif state == "raw3":
            if c == BS:
                i += 2; continue
            if src[i:i + 3] == '"""':
                state = None; i += 3; continue
            i += 1
    return "".join(out)


PAIRS = {"(": ")", "{": "}", "[": "]"}
CLOSE = set(PAIRS.values())

for f in FILES:
    raw = open(f, "rb").read()
    bom = raw[:3] == b"\xef\xbb\xbf"
    src = raw.decode("utf-8")
    code = strip(src)
    stack = []
    bad = None
    for ch in code:
        if ch in PAIRS:
            stack.append(ch)
        elif ch in CLOSE:
            if not stack or PAIRS[stack[-1]] != ch:
                bad = ch
                break
            stack.pop()
    status = "balanced" if bad is None and not stack else "UNBALANCED %s open=%s" % (bad, len(stack))
    print("%-46s %-6s %-28s lines=%d" % (f, "BOM" if bom else "noBOM", status, src.count("\n") + 1))
