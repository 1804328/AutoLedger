#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""AutoLedger (自动记账) app icon generator.

Produces a 1024x1024, flat/modern, dark-friendly icon:

    AutoLedger/AutoLedger/Assets.xcassets/AppIcon.appiconset/icon-1024.png

Design
------
* Full-bleed diagonal ink-green gradient  #1F2B33 -> #2D4A3E
* Soft radial glow behind the emblem (depth, no gradients banding)
* Centered minimal wallet: a cream card peeking out of a warm-gold body
* Bold ink checkmark on the wallet body  ("recorded / verified")
* No text, generous padding, reads down to 60x60

Technical
---------
* Rendered at 3x and downsampled with LANCZOS -> clean anti-aliased edges.
* Saved as RGB with NO alpha channel (required by iOS / App Store).
* Deterministic and idempotent: safe to re-run any time.

Usage
-----
    D:\\python3.9\\python.exe AutoLedger/tools/make_icon.py
"""

from __future__ import annotations

import os
import sys

from PIL import Image, ImageChops, ImageDraw, ImageFilter

# --------------------------------------------------------------------------- #
# Paths / constants
# --------------------------------------------------------------------------- #
HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.normpath(os.path.join(HERE, os.pardir))
OUT_PATH = os.path.join(
    PROJECT,
    "AutoLedger",
    "Assets.xcassets",
    "AppIcon.appiconset",
    "icon-1024.png",
)

CANVAS = 1024
SS = 3                    # supersampling factor
S = CANVAS * SS           # working canvas (3072)

# Palette
INK_DARK = (31, 43, 51)       # #1F2B33  top of background
INK_GREEN = (45, 74, 62)      # #2D4A3E  bottom of background
INK_SHADOW = (12, 20, 24)     # soft shadow under emblem
GOLD = (232, 197, 122)        # #E8C57A  primary accent (documented reference)
GOLD_LIGHT = (246, 219, 158)  # top of gold gradient
GOLD_DEEP = (201, 160, 84)    # bottom of gold gradient
CREAM = (247, 241, 227)       # #F7F1E3  card / highlight
INK_MARK = (24, 38, 45)       # checkmark ink


def u(v: float) -> int:
    """Scale a value given in 1024-space to the supersampled canvas."""
    return int(round(v * SS))


# --------------------------------------------------------------------------- #
# Gradient helpers
# --------------------------------------------------------------------------- #
def _diag_gradient(size: int, c0, c1, exponent: float = 1.0) -> Image.Image:
    """Linear gradient along the top-left -> bottom-right diagonal."""
    try:
        import numpy as np  # optional, much faster
    except Exception:
        np = None

    if np is not None:
        y, x = np.mgrid[0:size, 0:size].astype(np.float32)
        t = (x + y) / (2.0 * (size - 1))
        t = np.clip(t, 0.0, 1.0) ** exponent
        arr = np.empty((size, size, 3), dtype=np.uint8)
        for i in range(3):
            arr[..., i] = np.clip(
                c0[i] + (c1[i] - c0[i]) * t, 0, 255
            ).astype(np.uint8)
        return Image.fromarray(arr)

    # Fallback: build a small gradient and upscale (still perfectly smooth).
    small = Image.new("RGB", (256, 256))
    px = small.load()
    for yy in range(256):
        for xx in range(256):
            t = ((xx + yy) / 510.0) ** exponent
            px[xx, yy] = tuple(
                int(round(c0[i] + (c1[i] - c0[i]) * t)) for i in range(3)
            )
    return small.resize((size, size), Image.BICUBIC)


def _vert_gradient(size: int, c0, c1, top: int = 0, bottom: int | None = None):
    """Vertical gradient over [top, bottom) of a size x size image.

    Built as a 1px-wide strip then stretched -> fast and perfectly smooth.
    """
    bottom = size if bottom is None else bottom
    strip = Image.new("RGB", (1, size), c0)
    px = strip.load()
    span = max(1, bottom - top)
    for yy in range(size):
        if yy < top:
            t = 0.0
        elif yy >= bottom:
            t = 1.0
        else:
            t = (yy - top) / span
        px[0, yy] = tuple(int(round(c0[i] + (c1[i] - c0[i]) * t)) for i in range(3))
    return strip.resize((size, size), Image.NEAREST)


def _radial_alpha(size: int, peak: int) -> Image.Image:
    """Radial mask: `peak` (0-255) in the center, 0 at the edges."""
    base = ImageChops.invert(Image.radial_gradient("L"))  # 256x256, 255 center
    base = base.resize((size, size), Image.BICUBIC)
    return base.point(lambda v: int(v * peak / 255.0))


# --------------------------------------------------------------------------- #
# Shape helpers
# --------------------------------------------------------------------------- #
def rounded_mask(size: int, box, radius: int) -> Image.Image:
    """Anti-aliased (via supersampling) rounded-rectangle mask."""
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle(box, radius=radius, fill=255)
    return mask


def rotated_rounded_mask(size: int, box, radius: int, angle: float) -> Image.Image:
    """Rounded-rectangle mask rotated about the box center (degrees, CCW)."""
    mask = rounded_mask(size, box, radius)
    cx = (box[0] + box[2]) / 2.0
    cy = (box[1] + box[3]) / 2.0
    return mask.rotate(angle, resample=Image.BICUBIC, center=(cx, cy))


# --------------------------------------------------------------------------- #
# Build
# --------------------------------------------------------------------------- #
def build_icon() -> Image.Image:
    # ---- background ------------------------------------------------------ #
    img = _diag_gradient(S, INK_DARK, INK_GREEN, exponent=0.95)

    # very soft glow behind the emblem: depth without muddying the field
    glow_size = u(1240)
    glow = Image.new("RGB", (glow_size, glow_size), (74, 112, 94))
    gmask = _radial_alpha(glow_size, 30)
    img.paste(glow, (u(512) - glow_size // 2, u(520) - glow_size // 2), gmask)

    # ---- soft shadow under the emblem ------------------------------------ #
    shadow = Image.new("L", (S, S), 0)
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        (u(262), u(410), u(762), u(742)), radius=u(80), fill=165
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(u(30)))
    img.paste(Image.new("RGB", (S, S), INK_SHADOW), (0, 0), shadow)

    # ---- card peeking out of the wallet (behind the body) ---------------- #
    # tilted card tucked into the wallet: the classic wallet tell, and it
    # survives downscaling better than a straight "tab".
    CARD = (u(306), u(300), u(716), u(452))
    card_mask = rotated_rounded_mask(S, CARD, u(44), -7.0)
    card_fill = _vert_gradient(S, CREAM, (228, 218, 199), u(300), u(452))
    img.paste(card_fill, (0, 0), card_mask)

    # magnetic stripe on the card -> instantly reads as a payment card
    stripe_mask = ImageChops.multiply(
        rotated_rounded_mask(S, (u(306), u(368), u(716), u(390)), 0, -7.0),
        card_mask,
    )
    img.paste(Image.new("RGB", (S, S), GOLD_DEEP), (0, 0),
              stripe_mask.point(lambda v: int(v * 0.38)))

    # ---- wallet body ----------------------------------------------------- #
    BODY = (u(240), u(396), u(784), u(716))
    body_mask = rounded_mask(S, BODY, u(80))
    body_fill = _vert_gradient(S, GOLD_LIGHT, GOLD_DEEP, u(396), u(716))
    img.paste(body_fill, (0, 0), body_mask)

    # ---- wallet fold: a lighter band across the top of the body ---------- #
    fold_h = u(92)
    band = Image.new("L", (S, S), 0)
    ImageDraw.Draw(band).rectangle(
        (BODY[0], BODY[1], BODY[2], BODY[1] + fold_h), fill=255
    )
    fold_mask = ImageChops.multiply(band, body_mask)
    img.paste(Image.new("RGB", (S, S), (252, 231, 186)), (0, 0),
              fold_mask.point(lambda v: int(v * 0.42)))

    # crisp seam line closing the fold
    seam = Image.new("L", (S, S), 0)
    ImageDraw.Draw(seam).rectangle(
        (BODY[0], BODY[1] + fold_h - u(7), BODY[2], BODY[1] + fold_h), fill=255
    )
    seam = ImageChops.multiply(seam, body_mask)
    seam = seam.filter(ImageFilter.GaussianBlur(u(2)))
    img.paste(Image.new("RGB", (S, S), (176, 136, 66)), (0, 0),
              seam.point(lambda v: int(v * 0.55)))

    # ---- checkmark ------------------------------------------------------- #
    mark = Image.new("L", (S, S), 0)
    md = ImageDraw.Draw(mark)
    # sits fully inside the lower panel, clear of the fold seam
    pts = [(u(402), u(592)), (u(474), u(662)), (u(620), u(514))]
    stroke = u(46)
    md.line(pts, fill=255, width=stroke, joint="curve")
    for p in (pts[0], pts[-1]):  # round caps
        md.ellipse(
            (p[0] - stroke // 2, p[1] - stroke // 2,
             p[0] + stroke // 2, p[1] + stroke // 2),
            fill=255,
        )
    img.paste(Image.new("RGB", (S, S), INK_MARK), (0, 0), mark)

    # ---- gentle inner top highlight on the wallet ------------------------ #
    hl = Image.new("L", (S, S), 0)
    ImageDraw.Draw(hl).rounded_rectangle(
        (BODY[0] + u(8), BODY[1] + u(8), BODY[2] - u(8), BODY[3] - u(8)),
        radius=u(72), outline=255, width=u(5),
    )
    hl = hl.filter(ImageFilter.GaussianBlur(u(5)))
    hl = ImageChops.multiply(hl, body_mask)
    hl = hl.point(lambda v: int(v * 0.26))
    img.paste(Image.new("RGB", (S, S), (255, 247, 228)), (0, 0), hl)

    # ---- downscale & flatten to RGB -------------------------------------- #
    icon = img.resize((CANVAS, CANVAS), Image.LANCZOS)
    icon = icon.convert("RGB")  # guarantees no alpha channel
    return icon


def main() -> int:
    icon = build_icon()

    os.makedirs(os.path.dirname(OUT_PATH), exist_ok=True)
    icon.save(OUT_PATH, format="PNG", optimize=True)

    # verify what actually landed on disk
    with Image.open(OUT_PATH) as chk:
        mode, size = chk.mode, chk.size
        has_alpha = "A" in chk.getbands() or chk.info.get("transparency") is not None
    print("wrote   :", OUT_PATH)
    print("size    :", "%dx%d" % size)
    print("mode    :", mode, "| alpha:", has_alpha)
    if size != (CANVAS, CANVAS) or mode != "RGB" or has_alpha:
        print("ERROR: icon is not 1024x1024 RGB without alpha", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
