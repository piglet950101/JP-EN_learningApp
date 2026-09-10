"""Bundle the Japanese faces the app asks for, instead of hoping the device has them.

Why this exists (client 2026-09-08, and every 太字/ゴチ/明朝 report before it):
the SS renderer distinguishes three faces — the meaning in gothic, the run of a
ゴロ that echoes the English in gothic BOLD, and the rest of the quote in 明朝.
Until now those were requested as the bare family names 'sans-serif', 'serif'
and even 'Yu Gothic' (a Windows font that does not exist on Android), so what
the user actually saw was whatever their device's Japanese fallback chain did:

  • 'serif' commonly falls back to Noto Sans CJK for Japanese glyphs, so 明朝
    rendered identically to ゴチ — the client kept re-reporting rows whose data
    was already correct (2003 sigh, 2098 corporation, 2137 obvious all shipped
    in 1.0.15 with exactly the echo he asked for again on 09-08).
  • a FontWeight applied to a *fallback* font is not reliably honoured, so
    w900 on kana rendered at regular weight. Every 太字 complaint he has filed
    lands on a pure-Japanese run; none has ever landed on a Latin one (OPEC).

So we ship the faces. Noto Sans JP / Noto Serif JP are OFL-1.1, which permits
bundling. The full variable fonts are ~23MB together, which is why this script
subsets them to the characters the app can actually display and instances the
variable weight axis down to the static weights the code asks for.

Run:  python tool/build_fonts.py           (downloads sources to build/font_src)
      python tool/build_fonts.py --src DIR (uses DIR/sans.ttf, DIR/serif.ttf)

Output: assets/fonts/*.ttf + OFL.txt. Re-run after content changes, since the
subset is driven by the content JSON.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CONTENT = ROOT / 'assets' / 'content'
LIB = ROOT / 'lib'
DEST = ROOT / 'assets' / 'fonts'
CACHE = ROOT / 'build' / 'font_src'

RAW = 'https://raw.githubusercontent.com/google/fonts/main/ofl'
SOURCES = {
    'sans': RAW + '/notosansjp/NotoSansJP%5Bwght%5D.ttf',
    'serif': RAW + '/notoserifjp/NotoSerifJP%5Bwght%5D.ttf',
}
LICENCE_URL = RAW + '/notosansjp/OFL.txt'

# The faces the Dart code names, and the weights it asks for. Flutter resolves
# an unbundled weight to the nearest bundled one, so w500/w600/w800 land on
# these sensibly. 900 exists because the ゴロ echo is set in w900 and has to be
# visibly heavier than the w700 used for ordinary headings. 300 exists because
# the client separated the supplementary note from the ゴロ on 2026-09-10 —
# 「細字で小さく」 on nine rows — and w400 is not thin enough to read as 細字
# beside a ゴロ that is set at the same size and colour.
FACES = {
    'KaitanSans': ('sans', [300, 400, 700, 900]),
    'KaitanSerif': ('serif', [400, 700]),
}

STYLE_NAMES = {300: 'Light', 400: 'Regular', 700: 'Bold', 900: 'Black'}

# Always keep these regardless of content: ASCII, the full kana blocks, the
# punctuation the renderer itself injects, and the marker glyphs used in
# relation codes. A missing glyph renders as tofu, and the content changes
# almost daily, so the safety margin is deliberate.
ALWAYS = (
    ''.join(chr(c) for c in range(0x20, 0x7F))
    + ''.join(chr(c) for c in range(0x3040, 0x3100))    # hiragana + katakana
    + ''.join(chr(c) for c in range(0xFF01, 0xFF60))    # fullwidth forms
    + ''.join(chr(c) for c in range(0x2010, 0x2028))    # dashes / quotes
    + '　、。「」『』（）〔〕【】〈〉《》〜～…‥・￥※〒'
    + '←→↑↓⇒⇔⇨★☆○●◎△▲□■◇◆♪†‡§¶'
    + '±×÷≠≦≧∞∴♂♀°′″℃¢£¤'
    + '①②③④⑤⑥⑦⑧⑨⑩⑪⑫⑬⑭⑮'
    + 'ⅠⅡⅢⅣⅤⅥⅦⅧⅨⅩ'
)

STR_LIT = re.compile(r"'((?:[^'\\\n]|\\.)*)'|\"((?:[^\"\\\n]|\\.)*)\"")


def collect_chars() -> set[str]:
    chars: set[str] = set(ALWAYS)

    def walk(node) -> None:
        if isinstance(node, str):
            chars.update(node)
        elif isinstance(node, dict):
            for v in node.values():
                walk(v)
        elif isinstance(node, list):
            for v in node:
                walk(v)

    for p in sorted(CONTENT.glob('*.json')):
        walk(json.loads(p.read_text(encoding='utf-8')))

    # Anything hardcoded in the UI (button labels, dialogs, error copy).
    for p in sorted(LIB.rglob('*.dart')):
        for m in STR_LIT.finditer(p.read_text(encoding='utf-8')):
            chars.update(m.group(1) or m.group(2) or '')

    chars.discard('\n')
    chars.discard('\r')
    chars.discard('\t')
    return chars


def fetch(name: str, url: str) -> Path:
    CACHE.mkdir(parents=True, exist_ok=True)
    dest = CACHE / (name + '.ttf')
    if dest.exists() and dest.stat().st_size > 1_000_000:
        return dest
    print('  downloading ' + name + ' ...')
    with urllib.request.urlopen(url, timeout=300) as r:
        dest.write_bytes(r.read())
    return dest


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument('--src', type=Path, default=None,
                    help='directory holding sans.ttf / serif.ttf')
    args = ap.parse_args()

    try:
        from fontTools import subset
        from fontTools.ttLib import TTFont
        from fontTools.varLib import instancer
    except ImportError:
        print('ERROR: pip install fonttools brotli', file=sys.stderr)
        return 1

    chars = collect_chars()
    text = ''.join(sorted(chars))
    print('characters to keep: %d' % len(chars))

    DEST.mkdir(parents=True, exist_ok=True)
    for old in DEST.glob('*.ttf'):
        old.unlink()

    total = 0
    for family, (src_name, weights) in FACES.items():
        src = (args.src / (src_name + '.ttf')) if args.src \
            else fetch(src_name, SOURCES[src_name])
        for wght in weights:
            font = TTFont(src)
            axes = {a.axisTag: (a.minValue, a.maxValue)
                    for a in font['fvar'].axes}
            lo, hi = axes['wght']
            # Noto Serif JP's axis starts at 200 and Sans' at 100; clamp so a
            # requested weight outside the axis instances at its extreme
            # rather than raising.
            instancer.instantiateVariableFont(
                font, {'wght': max(lo, min(hi, wght))}, inplace=True,
                updateFontNames=False)

            opts = subset.Options()
            opts.layout_features = ['*']
            opts.name_IDs = ['*']
            opts.notdef_outline = True
            opts.recalc_bounds = True
            opts.drop_tables += ['BASE', 'DSIG']
            subsetter = subset.Subsetter(options=opts)
            subsetter.populate(text=text)
            subsetter.subset(font)

            style = STYLE_NAMES[wght]
            font['name'].setName(family, 1, 3, 1, 0x409)
            font['name'].setName(style, 2, 3, 1, 0x409)
            font['name'].setName(family + ' ' + style, 4, 3, 1, 0x409)
            font['name'].setName(family + '-' + style, 6, 3, 1, 0x409)
            if 'OS/2' in font:
                font['OS/2'].usWeightClass = wght

            out = DEST / (family + '-' + style + '.ttf')
            font.save(out)
            font.close()
            size = out.stat().st_size
            total += size
            print('  %-28s %8.1f KB' % (out.name, size / 1024))

    lic = DEST / 'OFL.txt'
    if not lic.exists():
        try:
            with urllib.request.urlopen(LICENCE_URL, timeout=60) as r:
                lic.write_bytes(r.read())
        except Exception as e:  # noqa: BLE001 - licence fetch is best-effort
            print('  WARNING: could not fetch OFL.txt (%s) — add it manually' % e)
    print('total bundled: %.2f MB' % (total / 1024 / 1024))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
