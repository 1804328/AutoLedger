"""比对 Swift 侧常量表与 Python 移植侧，确认「测试过的就是仓库里的」。
只抽取 + 逐条比对，不改任何文件。
"""
import io
import os
import re
import sys

sys.stdout.reconfigure(encoding="utf-8")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO = os.path.join(ROOT, "AutoLedger", "Parser")
PROBE = os.path.join(ROOT, "tools", "ocr_probe")
sys.path.insert(0, PROBE)
import contextlib                                  # noqa: E402
with contextlib.redirect_stdout(io.StringIO()):   # parser_check 在 import 时就把 31 条跑完打印了
    import parser_check as P          # noqa: E402
    import receipt_logic as L         # noqa: E402

LIT = re.compile(r'#"(?P<raw>[^"]*)"#|"(?P<q>(?:[^"\\]|\\.)*)"')


def read(name):
    with io.open(os.path.join(REPO, name), encoding="utf-8") as f:
        return f.read()


def swift_array(src, name):
    """取出 `static let NAME ... = [ ... ]` 数组里的每个字符串字面量内容。
    逐字符扫描：惰性正则会跨过 `]` 吞掉下一个数组，正则里的 `[` 又会撑破括号计数，
    所以遇到字符串字面量整段消费掉、不参与括号计数。
    """
    m = re.search(r"static let " + name + r"\b", src)
    if not m:
        return None
    rest = src[m.end():]
    eq = rest.find("=")
    if eq < 0:
        return None
    tail = rest[eq + 1:].lstrip()
    if tail.startswith("["):
        start = rest.find("[", eq)
    else:
        single = LIT.match(tail) or LIT.search(tail[:400])
        return [single.group("raw") or unescape(single.group("q"))] if single else None
    out, depth, i = [], 1, start + 1
    while i < len(rest) and depth > 0:
        if rest.startswith("#\"", i):
            g = LIT.match(rest, i)
            if g:
                out.append(g.group("raw"))
                i = g.end() + 2        # 跳过 "#
                continue
        if rest[i] == '"':
            g = LIT.match(rest, i)
            if g:
                out.append(unescape(g.group("q")))
                i = g.end()
                continue
        if rest[i] == "[" and not rest.startswith("//", i):
            depth += 1
        elif rest[i] == "]":
            depth -= 1
            if depth == 0:
                break
        i += 1
    return out


def lit_contents(lit):
    g = LIT.fullmatch(lit.strip())
    return [g.group("raw") or unescape(g.group("q"))] if g else []


def unescape(s):
    return s.replace('\\"', '"').replace("\\\\", "\\")


def cmp(name, got, exp, order_matters=True):
    if got is None:
        print("MISS  " + name + "  —— Swift 侧没抓到，检查命名/写法")
        return False
    if order_matters:
        ok = got == exp
    else:
        ok = len(got) == len(exp) and set(got) == set(exp)
    print(("same  " if ok else "DIFF  ") + name + f"  swift={len(got)} py={len(exp)}"
          + ("" if ok or got is None else ""))
    if not ok:
        only_swift = [x for x in got if x not in exp]
        only_py = [x for x in exp if x not in got]
        if only_swift:
            print("    只在 Swift:", only_swift)
        if only_py:
            print("    只在 Python:", only_py)
        if not only_swift and not only_py:
            print("    成员一致、顺序不同（顺序影响剥离结果时必须一致）")
    return ok


ocr = read("ReceiptOCR.swift")
np = read("NaturalParser.swift")
r = []
# 词表：成员比对即可（都是 contains 判定，命中集合不变）
r.append(cmp("anchorWords", swift_array(ocr, "anchorWords"), L.ANCHOR_WORDS, order_matters=False))
r.append(cmp("rejectWords", swift_array(ocr, "rejectWords"), L.REJECT_WORDS, order_matters=False))
r.append(cmp("unpaidWords", swift_array(ocr, "unpaidWords"), L.UNPAID_WORDS, order_matters=False))
r.append(cmp("pageLabels", swift_array(ocr, "pageLabels"), L.PAGE_LABELS, order_matters=False))
r.append(cmp("summaryPatterns", swift_array(ocr, "summaryPatterns"), L.SUMMARY_PATTERNS,
             order_matters=False))
r.append(cmp("nameSuffixBlock", swift_array(ocr, "nameSuffixBlock"), L.NAME_SUFFIX_BLOCK,
             order_matters=False))
r.append(cmp("fieldPrefixes", swift_array(ocr, "fieldPrefixes"), L.FIELD_PREFIXES))
# 剥离表：长词必须排在短词前面，顺序严格比对
r.append(cmp("noteNoise", swift_array(np, "noteNoise"), P.NOTE_NOISE))
print("SKIP  dateStrip —— Swift 侧不是数组而是 stripDateExpressions() 里逐个 firstMatch，"
      "形态不同，行为由 corpus 用例覆盖")
r.append(cmp("noiseNumberPatterns", swift_array(np, "noiseNumberPatterns"), P.NOISE))
r.append(cmp("unitPatterns", swift_array(np, "unitPatterns"), P.UNIT_PATTERNS))
r.append(cmp("noteMoneyResiduals", swift_array(np, "noteMoneyResiduals"), P.NOTE_MONEY_RESIDUALS))
r.append(cmp("anchorPattern", swift_array(np, "anchorPattern"), [P.ANCHOR]))
r.append(cmp("plainPattern", swift_array(np, "plainPattern"), [P.PLAIN]))
r.append(cmp("chinesePattern", swift_array(np, "chinesePattern"), [P.CHINESE]))
r.append(cmp("chineseBarePattern", swift_array(np, "chineseBarePattern"), [P.CHINESE_BARE]))
r.append(cmp("ABS_DATE", swift_array(np, "absoluteDatePattern"), [P.ABS_DATE.pattern])
         if hasattr(P, "ABS_DATE") else
         cmp("绝对日期正则（DateExtractor 内联）",
             [L.ABS_DATE.pattern] if L.ABS_DATE.pattern in np.replace('#"', '"').replace('"#', '"') else None,
             [L.ABS_DATE.pattern]))

rel = re.findall(r'\("([^"]+)",\s*(-?\d+)\)', np)
r.append(cmp("relative 词表", [w for w, _ in rel], P.RELATIVE, order_matters=False))


def cmp_num(name, got, exp):
    ok = got is not None and abs(got - exp) < 1e-9
    print(("same  " if ok else "DIFF  ") + name + f"  swift={got} py={exp}")
    return ok


def swift_const(name):
    m = re.search(r"static let " + name + r"\s*:\s*CGFloat\s*=\s*([\d.]+)", ocr)
    return float(m.group(1)) if m else None


def swift_inline(pattern):
    m = re.search(pattern, ocr)
    return float(m.group(1)) if m else None


# 阈值是写在 Swift 表达式里的字面量，改一个数字两边就悄悄分叉，逐条比数值
r.append(cmp_num("statusBarBand", swift_const("statusBarBand"), L.STATUS_BAR_BAND))
r.append(cmp_num("hero 比例（scan 里 byHeight[1].height * N）",
                 swift_inline(r"byHeight\[1\]\.height \* ([\d.]+)"), L.HERO_RATIO))
r.append(cmp_num("歧义比例（ambiguous 里 cands[1].height * N）",
                 swift_inline(r"cands\[1\]\.height \* ([\d.]+)"), L.AMBIG_RATIO))
r.append(cmp_num("锚点加权（score = relative + N if anchor）",
                 swift_inline(r"relative \+ \([\w.]+ \? ([\d.]+) : 0\)"), L.ANCHOR_WEIGHT))

print()
print("全部一致：Python 绿的这套逻辑确实就是 Swift 里的那套"
      if all(r) else "存在差异：Python 侧全绿不代表 Swift 侧全绿")
sys.exit(0 if all(r) else 1)
