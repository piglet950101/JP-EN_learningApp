"""
Install the client's app icon on both platforms.

Source: アイコンN-01.png (client, 2026-09-02) — 快 in white with 2~Pre1 in
orange on a navy field, 1024x1024.

Two platform rules shape how it has to be installed.

Android 8+ MASKS the launcher icon. A launcher may crop it to a circle, a
squircle or a rounded square, and only the centre 66% is guaranteed to
survive. Shipping the artwork as a plain square icon loses the 2~Pre1 line
entirely under a circular mask — measured, not guessed: the furthest ink sits
507px from centre where the safe radius is 341px. So the icon is split the way
adaptive icons intend: the navy becomes the BACKGROUND layer and bleeds past
whatever mask is applied, and the 快/2~Pre1 artwork becomes the FOREGROUND
layer, scaled to sit inside the safe circle. The result reads as the client's
design on every launcher, with the navy full-bleed.

iOS does not mask beyond rounding the corners, so it takes the artwork whole —
but the App Store rejects an icon with an alpha channel, so it is flattened.

Run after replacing the source file; it rewrites every density and size.
"""
from __future__ import annotations

import json
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
# Kept beside the tool so a rebuild does not depend on a file
# sitting loose in the project root.
SRC = Path(__file__).with_name('app_icon_source.png')
ANDROID = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
IOS = ROOT / 'ios' / 'Runner' / 'Assets.xcassets' / 'AppIcon.appiconset'

# Android launcher icon sizes, in px, per density bucket.
DENSITIES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}
# Foreground/background drawables are authored at 108dp; 432px covers xxxhdpi.
ADAPTIVE = {'mdpi': 108, 'hdpi': 162, 'xhdpi': 216, 'xxhdpi': 324, 'xxxhdpi': 432}
SAFE_FRACTION = 0.66   # the centre 66% of an adaptive icon is always visible


def ink_only(im: Image.Image) -> tuple[Image.Image, tuple[int, int, int]]:
    """Split the artwork into its background colour and everything else."""
    rgb = im.convert('RGB')
    bg = rgb.getpixel((5, 5))
    out = Image.new('RGBA', im.size, (0, 0, 0, 0))
    src, dst = rgb.load(), out.load()
    for y in range(im.size[1]):
        for x in range(im.size[0]):
            r, g, b = src[x, y]
            if abs(r - bg[0]) + abs(g - bg[1]) + abs(b - bg[2]) > 60:
                dst[x, y] = (r, g, b, 255)
    return out, bg


def cropped_to_ink(layer: Image.Image) -> Image.Image:
    box = layer.getbbox()
    return layer.crop(box) if box else layer


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f'not found: {SRC}')
    art = Image.open(SRC).convert('RGBA')
    ink, bg = ink_only(art)
    ink = cropped_to_ink(ink)

    # ── Android: adaptive background + foreground ────────────────────
    for bucket, size in ADAPTIVE.items():
        d = ANDROID / f'mipmap-{bucket}'
        d.mkdir(parents=True, exist_ok=True)
        Image.new('RGBA', (size, size), bg + (255,)).save(d / 'ic_launcher_background.png')

        fg = Image.new('RGBA', (size, size), (0, 0, 0, 0))
        limit = int(size * SAFE_FRACTION)
        scaled = ink.copy()
        scaled.thumbnail((limit, limit), Image.LANCZOS)
        fg.paste(scaled, ((size - scaled.width) // 2, (size - scaled.height) // 2), scaled)
        fg.save(d / 'ic_launcher_foreground.png')

    # Legacy square icon for anything below Android 8.
    for bucket, size in DENSITIES.items():
        (ANDROID / f'mipmap-{bucket}').mkdir(parents=True, exist_ok=True)
        art.resize((size, size), Image.LANCZOS).save(
            ANDROID / f'mipmap-{bucket}' / 'ic_launcher.png')

    anydpi = ANDROID / 'mipmap-anydpi-v26'
    anydpi.mkdir(parents=True, exist_ok=True)
    xml = ('<?xml version="1.0" encoding="utf-8"?>\n'
           '<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">\n'
           '    <background android:drawable="@mipmap/ic_launcher_background"/>\n'
           '    <foreground android:drawable="@mipmap/ic_launcher_foreground"/>\n'
           '</adaptive-icon>\n')
    (anydpi / 'ic_launcher.xml').write_text(xml, encoding='utf-8')
    (anydpi / 'ic_launcher_round.xml').write_text(xml, encoding='utf-8')

    # ── iOS: whole artwork, no alpha ─────────────────────────────────
    flat = Image.new('RGB', art.size, bg)
    flat.paste(art, mask=art.getchannel('A'))
    spec = json.loads((IOS / 'Contents.json').read_text(encoding='utf-8'))
    written = set()
    for entry in spec['images']:
        w, _, h = entry['size'].partition('x')
        px = int(round(float(w) * float(entry['scale'].rstrip('x'))))
        name = entry['filename']
        flat.resize((px, px), Image.LANCZOS).save(IOS / name)
        written.add(name)

    print(f'Android: adaptive layers + legacy icons for {len(DENSITIES)} densities')
    print(f'iOS    : {len(written)} sizes, alpha removed')
    print(f'background {bg}, ink scaled to {int(SAFE_FRACTION * 100)}% safe zone')


if __name__ == '__main__':
    main()
