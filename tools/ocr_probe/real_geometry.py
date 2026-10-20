"""量真实支付截图的行高，验证「金额是整页最大的字」这个前提到底成不成立。

不需要 OCR 引擎：二值化 → 水平投影切出文字行带 → 量每条行带的实际像素高度和横向范围。
`--montage` 会把每行带按原序裁出来、编号拼成一张 png，
这样就能把「真实行高」和「这一行到底是什么字」对上，再把实测值写进 corpus_check 的用例。

用法：python real_geometry.py <截图路径> [输出png] [--montage]

已量过的一张（1206x2622 支付宝账单详情）：主金额 73px = 0.028，正文 41px = 0.0156，
比例 1.78 —— 过 hero 阈值 1.5，但远没有原先注释里假设的 0.045~0.060 那么大。
"""
import os
import sys

sys.stdout.reconfigure(encoding="utf-8")
from PIL import Image, ImageDraw, ImageOps

args = [a for a in sys.argv[1:] if not a.startswith("--")]
if not args:
    sys.exit("用法：python real_geometry.py <截图路径> [输出png] [--montage]")
PATH = args[0]
OUT = args[1] if len(args) > 1 else "real_bands.png"
MIN_INK = 3            # 一行里至少这么多个暗像素才算有字
GAP = 4                # 行带之间允许的空行数


def row_ink(gray, w, h):
    px = gray.load()
    return [sum(1 for x in range(0, w, 2) if px[x, y] < 128) for y in range(h)]


def row_span(gray, w, h):
    px = gray.load()
    out = []
    for y in range(h):
        left = next((x for x in range(w) if px[x, y] < 128), None)
        right = next((x for x in range(w - 1, -1, -1) if px[x, y] < 128), None)
        out.append((left, right))
    return out


def bands(ink, h):
    runs, y = [], 0
    while y < h:
        if ink[y] >= MIN_INK:
            start = y
            while y < h and ink[y] >= MIN_INK:
                y += 1
            runs.append([start, y - 1])
        else:
            y += 1
    merged = []
    for r in runs:
        if merged and r[0] - merged[-1][1] - 1 < GAP:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    return [(t, b, b - t + 1) for t, b in merged]


im = Image.open(PATH).convert("L")
im = ImageOps.autocontrast(im)
thumb = im.resize((im.width // 3, im.height // 3))
data = list(thumb.getdata())
dark_share = sum(1 for v in data if v < 128) / len(data)
print(f"暗像素占比 = {dark_share:.2f}")
if dark_share > 0.75:
    im = ImageOps.invert(im)
    print("（暗底亮字，已反色）")

w, h = im.width, im.height
ink = row_ink(im, w, h)
spans = row_span(im, w, h)
bs = bands(ink, h)
tallest = max(b[2] for b in bs)
hs = sorted(b[2] for b in bs)
med = hs[len(hs) // 2]
print(f"图片 {w}x{h}，切出 {len(bs)} 条文带；中位 {med}px，最高 {tallest}px，最高/中位 {tallest / med:.2f}")

print(f"\n{'#':>3} {'顶部y':>6} {'高px':>6} {'归一化':>7} {'相对最高':>8}  x范围")
for i, (top, bot, hgt) in enumerate(bs):
    left, right = spans[top]
    print(f"{i:>3} {top:>6} {hgt:>6} {hgt / h:>7.3f} {hgt / tallest:>8.3f}"
          f"  x[{left if left is not None else 0},{right if right is not None else w}]")

print("\n按高度排序：")
for top, bot, hgt in sorted(bs, key=lambda b: -b[2])[:6]:
    print(f"  y={top} 高{hgt}px 相对{hgt / tallest:.3f}")

if "--montage" in sys.argv:
    pad, cell = 8, 80
    sheet = Image.new("RGB", (w + 100, cell * len(bs) + 6), "white")
    dr = ImageDraw.Draw(sheet)
    for i, (top, bot, hgt) in enumerate(bs):
        ls = [spans[y][0] for y in range(top, bot + 1) if spans[y][0] is not None]
        rs = [spans[y][1] for y in range(top, bot + 1) if spans[y][1] is not None]
        if not ls or not rs:
            continue
        left, right = max(0, min(ls) - pad), min(w, max(rs) + pad)
        crop = im.crop((left, max(0, top - pad), right, min(h, bot + pad + 1)))
        scale = min(1.0, (cell - 12) / crop.height)
        if scale < 1.0:
            crop = crop.resize((int(crop.width * scale), int(crop.height * scale)), Image.LANCZOS)
        sheet.paste(crop.convert("RGB"), (100 + left, i * cell + 6))
        dr.text((10, i * cell + cell // 2 - 8), f"{i} h{hgt}", fill="red")
    sheet.save(OUT)
    print(f"\nmontage 已写出：{OUT}")
