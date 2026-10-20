"""生成 check_icu.js —— 把移植侧的正则原样嵌进一个 V8 脚本里。

不自动生成的话 check_icu.js 会悄悄过期：改了 parser_check.py 却忘了重跑，
第二引擎复核的就是一份旧模式，等于没复核。
"""
import io
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.stdout.reconfigure(encoding="utf-8")
import contextlib  # noqa: E402

with contextlib.redirect_stdout(io.StringIO()):   # parser_check 在 import 时就把 31 条跑完打印了
    import parser_check as P

PATTERNS = {
    "unitPatterns": P.UNIT_PATTERNS,
    "anchor": [P.ANCHOR],
    "chinese": [P.CHINESE],
    "plain": [P.PLAIN],
    "chineseBare": [P.CHINESE_BARE],
    "noise": P.NOISE,
    "noteMoneyResiduals": P.NOTE_MONEY_RESIDUALS,
}

# 语义抽查：本轮改的就是千分位整体命中，两个引擎必须给同一个捕获结果
CASES = [
    ("unitPatterns", 0, "\u00a55,099.00", "5,099.00"),
    ("unitPatterns", 1, "1,286.50\u5143", "1,286.50"),
    ("plain", 0, "1,286.50", "1,286.50"),
    ("plain", 0, "\u4f59\u989d 286 \u5143", "286"),
    ("noise", 9, "6214****8888", "6214****8888"),
]

# 值必须是「模式列表」而不是裸字符串：写成字符串时 JS 会按字符展开，
# 于是每个字符都被当成一条正则去编译，报出一堆假语法错误。
for k, v in PATTERNS.items():
    assert isinstance(v, list) and all(isinstance(x, str) for x in v), f"{k} 不是 [str]"
    for x in v:
        assert "(" in x or "[" in x or r"\d" in x, f"{k} 里这条不像正则：{x!r}"

BODY = """// 由 gen_icu_check.py 生成，别手改；改完正则重跑：python tools/ocr_probe/gen_icu_check.py
// 用第二个正则引擎（V8/ICU）复核 Swift 侧 NSRegularExpression 用到的模式。
// 语法非法不会让 xcodebuild 失败 —— try? 静默返回 nil，那一档就永远不命中，
// 线上只表现为「金额没识别出来」，查不到根因。
const P = __PATTERNS__;

let bad = 0;
for (const [k, arr] of Object.entries(P)) {
  for (const p of arr) {
    try { new RegExp(p); } catch (e) { bad++; console.log('SYNTAX-FAIL', k, p, e.message); }
  }
}
console.log(bad ? `${bad} 条模式语法非法` : `全部 ${Object.values(P).flat().length} 条模式在 V8 下语法合法`);

for (const [key, idx, input, want] of __CASES__) {
  const m = new RegExp(P[key][idx]).exec(input);
  const got = m ? (m[1] !== undefined ? m[1] : m[0]) : null;
  console.log((got === want ? 'OK   ' : 'DIFF ') + JSON.stringify(input)
    + ` -> ${JSON.stringify(got)} (期望 ${JSON.stringify(want)})`);
}
"""

out = BODY.replace("__PATTERNS__", json.dumps(PATTERNS, ensure_ascii=False)) \
          .replace("__CASES__", json.dumps(CASES, ensure_ascii=False))
path = os.path.join(HERE, "check_icu.js")
io.open(path, "w", encoding="utf-8", newline="\n").write(out)
print("已写出", path, f"（{sum(len(v) for v in PATTERNS.values())} 条模式）")
