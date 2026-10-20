"""用真正的 OCR 引擎跑真机截图，看识别框高度会把「主角数字」规则推向哪一边。

之前 real_geometry.py 量的是墨迹投影行高，那是「字本身有多高」；
OCR 引擎给的是「识别框有多高」，框会带上行距/留白，比值一定会被压小。
ReceiptOCR 的 hero 阈值是 1.5 倍，这个压小幅度到底有多大，只能拿真引擎量。

RapidOCR（onnxruntime，本机推理，不联网）不是 Vision，
但两者同为「检测框 + 行文本」这一类输出，用它做几何量级判断比墨迹投影近一层。

用法：python real_ocr.py [图片路径 ...]
"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from datetime import date
from PIL import Image, ImageOps
from parser_check import extract_amount
import receipt_logic as L

DEFAULT = [r"E:\新建文件夹\qq\IMG_1996.JPG"]

# 人工核对过的真值：金额 / 商户 / 日期（见 real_bands.png 逐行核对）
EXPECT = {
    r"E:\新建文件夹\qq\IMG_1996.JPG": (18.00, "伊清烧烤", date(2026, 10, 18)),
}

_engine = None


def ocr_lines(path):
    """返回 [(文本, 归一化字高, 归一化midY, 归一化minX)]，按阅读顺序。"""
    global _engine
    if _engine is None:
        from rapidocr_onnxruntime import RapidOCR
        _engine = RapidOCR()
    img = Image.open(path)
    img = ImageOps.exif_transpose(img)
    w, h = img.size
    result, _ = _engine(os.path.abspath(path))
    rows = []
    for box, text, conf in (result or []):
        xs = [p[0] for p in box]
        ys = [p[1] for p in box]
        rows.append((text, (max(ys) - min(ys)) / h, ((max(ys) + min(ys)) / 2) / h, min(xs) / w, conf))
    # 同一行两个词的 midY 差很小，0.02 容差后按 x 排（对位 ReceiptOCR.lines 的排序）
    rows.sort(key=lambda r: (round(r[2], 2), r[3]))
    return rows, (w, h)


def heights(cs):
    hs = sorted((c["height"] for c in cs), reverse=True)
    return hs[0] / hs[1] if len(hs) > 1 else float("inf")


def report(path, expect=None):
    print("=" * 72)
    print(path)
    rows, size = ocr_lines(path)
    if not rows:
        print("  引擎没识别出任何文字")
        return None
    print(f"  尺寸 {size[0]}x{size[1]}，共 {len(rows)} 个识别框")
    for text, hh, midy, minx, conf in rows:
        print(f"    {hh:.4f}  距顶={midy:.3f} x={minx:.3f} p={conf:.2f}  {text}")

    lines = [(t, hh, top) for (t, hh, top, _x, _c) in rows]
    dropped = [c[0] for c in lines if L.is_status_bar_number(c)]
    joined = " ".join(c[0] for c in L.drop_status(lines))
    p_amt = extract_amount(joined)[0]
    amount, why, note, merchant, d, cands, need = L.scan(lines, p_amt, joined, extract_amount)

    print(f"  扔掉的状态栏：{'、'.join(dropped) or '无'}")
    print(f"  最高字/次高字 = {heights(L.rank(lines, extract_amount)):.2f}（状态栏留着）"
          f" vs {heights(cands):.2f}（扔掉后），hero 阈值 1.5")
    print(f"  候选 {len(cands)} 个：")
    for c in cands:
        print(f"    {L.money(c['amount']):>10}  h={c['height']:.4f} "
              f"{'锚' if c['anchor'] else '  '}  score={c['score']:.3f}  {c['line']}")
    print(f"  解析器直取 {p_amt}  ->  最终金额 {amount}  依据 {why}")
    print(f"  备注 {note!r}  商户 {merchant!r}  需人工确认 {need}")
    print(f"  日期 {d}")

    if expect:
        want_amt, want_merchant, want_day = expect
        got_day = d[0] if d else None
        ok = (amount == want_amt and merchant == want_merchant and got_day == want_day)
        print(f"  {'通过' if ok else '不通过'}：期望 金额={want_amt} 商户={want_merchant!r} 日期={want_day}")
        return ok
    return None


def main():
    cases = [(p, EXPECT.get(p)) for p in (sys.argv[1:] or DEFAULT)]
    results = []
    for p, exp in cases:
        if not os.path.exists(p):
            print(f"跳过（不存在）：{p}")
            continue
        r = report(p, exp)
        if r is not None:
            results.append(r)
    if results:
        print("=" * 72)
        print(f"真引擎断言：{sum(results)}/{len(results)} 通过")
        if len(results) != sum(results):
            sys.exit(1)


if __name__ == "__main__":
    main()
