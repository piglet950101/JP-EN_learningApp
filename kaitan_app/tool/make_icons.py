"""
Generate the four app icons.

Background: what the client had been shown as "the current icon" was the
Flutter framework's own logo, left in place from `flutter create`. It is
Google's trademark and cannot ship on a product, so it had to be replaced —
but the client's design was sound and is kept in full: a K mark, a Century
Gothic numeral, and four colourways.

  快単パーフェクト［2級〜準1級］   Android  水色      2
                                   iPhone   ピンク    2
  快単パーフェクト［1級］          Android  青        1
                                   iPhone   赤        1

The K here is drawn from scratch — an upright stem with two arms meeting at
its middle — so it is a real letterform rather than a trace of the Flutter
mark. The angular banding and the shadow where the lower arm leaves the stem
are kept, because that is the part the client liked.

Century Gothic ships with Microsoft Office as GOTHIC.TTF; pass --font to point
elsewhere. Run with --size to preview at a phone's actual drawing size.
"""
from __future__ import annotations

import argparse
import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

CANVAS = 1024
DEFAULT_FONT = 'C:/Windows/Fonts/GOTHIC.TTF'
OUT = Path(__file__).resolve().parent.parent.parent / 'delivery' / 'icon_proposal'

# light (stem + upper arm), mid (lower arm), dark (the fold)
PALETTES = {
    '2kyu_android_水色':   ((0x4F, 0xC3, 0xF7), (0x35, 0xA8, 0xE0), (0x01, 0x57, 0x9B), '2'),
    '2kyu_iphone_ピンク':  ((0xF7, 0x8F, 0xB5), (0xE5, 0x6E, 0x9B), (0x9B, 0x01, 0x4A), '2'),
    '1kyu_android_青':     ((0x42, 0x8B, 0xE8), (0x2A, 0x66, 0xC8), (0x0D, 0x27, 0x6B), '1'),
    '1kyu_iphone_赤':      ((0xF0, 0x6A, 0x6A), (0xD8, 0x45, 0x45), (0x8B, 0x11, 0x11), '1'),
}


def _band(p, q, w, t0=0.0, t1=1.0):
    """A straight segment of width w as a polygon, optionally a sub-length."""
    (x1, y1), (x2, y2) = p, q
    dx, dy = x2 - x1, y2 - y1
    length = math.hypot(dx, dy)
    nx, ny = -dy / length * w / 2, dx / length * w / 2
    a = (x1 + dx * t0, y1 + dy * t0)
    b = (x1 + dx * t1, y1 + dy * t1)
    return [(a[0] + nx, a[1] + ny), (b[0] + nx, b[1] + ny),
            (b[0] - nx, b[1] - ny), (a[0] - nx, a[1] - ny)]


def draw_icon(light, mid, dark, digit, font_path=DEFAULT_FONT):
    im = Image.new('RGBA', (CANVAS, CANVAS), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    d.ellipse([8, 8, CANVAS - 8, CANVAS - 8], fill=(255, 255, 255, 255),
              outline=(120, 120, 120, 255), width=3)

    stem_x, top, bottom, middle, weight = 250, 210, 815, 512, 104
    d.polygon(_band((stem_x, middle), (620, top), weight), fill=light)
    d.polygon(_band((stem_x, middle), (620, bottom), weight), fill=mid)
    # Shadow where the lower arm passes the stem — drawn before the stem so
    # the stem covers its inner end and the join stays clean.
    d.polygon(_band((stem_x, middle), (620, bottom), weight, 0.0, 0.28), fill=dark)
    d.polygon([(stem_x - weight // 2, top), (stem_x + weight // 2, top),
               (stem_x + weight // 2, bottom), (stem_x - weight // 2, bottom)],
              fill=light)

    font = ImageFont.truetype(font_path, 430)
    box = d.textbbox((0, 0), digit, font=font)
    d.text((760 - (box[2] - box[0]) / 2 - box[0],
            512 - (box[3] - box[1]) / 2 - box[1]),
           digit, font=font, fill=(17, 17, 17, 255))
    return im


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--font', default=DEFAULT_FONT)
    ap.add_argument('--size', type=int, default=CANVAS)
    ap.add_argument('--out', default=str(OUT))
    args = ap.parse_args()

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    made = []
    for name, (light, mid, dark, digit) in PALETTES.items():
        im = draw_icon(light, mid, dark, digit, args.font)
        if args.size != CANVAS:
            im = im.resize((args.size, args.size), Image.LANCZOS)
        path = out / f'{name}.png'
        im.save(path)
        made.append(path)

    sheet = Image.new('RGBA', (CANVAS * 2 + 60, CANVAS * 2 + 60), (245, 245, 245, 255))
    for i, p in enumerate(made):
        im = Image.open(p).resize((CANVAS, CANVAS), Image.LANCZOS)
        sheet.paste(im, (20 + (i % 2) * (CANVAS + 20), 20 + (i // 2) * (CANVAS + 20)), im)
    sheet.resize((820, 820), Image.LANCZOS).save(out / '_4案まとめ.png')

    strip = Image.new('RGBA', (4 * 140 + 100, 180), (245, 245, 245, 255))
    for i, p in enumerate(made):
        im = Image.open(p).resize((120, 120), Image.LANCZOS)
        strip.paste(im, (20 + i * 140, 30), im)
    strip.save(out / '_実寸プレビュー.png')

    print(f'wrote {len(made)} icons + 2 previews to {out}')


if __name__ == '__main__':
    main()
