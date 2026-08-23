"""
Parse 「アプリ直し Second Stage 8. 20.docx」 (client review, 2026-08-19) into
structured per-word correction records.

The document is written as a VISUAL two-column layout — the "before" state on
the left, an arrow, then the "after" state on the right — and long entries
wrap across several lines. That means a naive line-by-line before/after split
loses information, so this parser deliberately keeps the whole block of raw
lines for each word and only extracts the arrow pairs it can see clearly.
Everything else is preserved verbatim for manual review.

Output: tool/corrections_0820.json
    {
      "source": "...docx",
      "word_count": N,
      "records": [
        {"word_id": 7, "word": "transparent", "section": "解答",
         "raw": ["...", "..."],           # every line in the block
         "changes": [{"before": "...", "after": "..."}],
         "notes": ["明朝、ふつう", ...]     # font/style annotations
        }, ...
      ]
    }
"""
from __future__ import annotations

import json
import re
from pathlib import Path

from docx import Document

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / 'アプリ直し Second Stage 8. 20.docx'
OUT = Path(__file__).with_name('corrections_0820.json')

# `0007 transparent　解答` / `0845  object　　問題` / `0843  subject`
# Also `0143 defer 問題、解答` — a single block covering BOTH screens.
HEADER_RE = re.compile(
    r'^(\d{3,4})\s+([A-Za-z][A-Za-z0-9/\-\'’ ]*?)'
    r'\s*(問題\s*[、・]\s*解答|解答\s*[、・]\s*問題|問題|解答|問|解)?\s*$'
)
ARROW_RE = re.compile(r'\s*[⇨→]\s*')
# Font/style annotations travel on their own line, flagged by ↱ / ↳ / ↲.
NOTE_RE = re.compile(r'[↱↳↲]')
# A run of padding that separates the two visual columns on a wrapped line.
COLUMN_GAP_RE = re.compile(r'[　]{3,}|[ ]{6,}')
# A continuation line indented far enough to belong to the right column only.
INDENTED_RE = re.compile(r'^(?:[　]{4,}|[ ]{8,})\S')
STYLE_WORDS = ('明朝', 'ゴチ', '太', 'ふつう', '小さい字', '黒')


def parse() -> dict:
    doc = Document(str(SRC))
    lines = [p.text.rstrip() for p in doc.paragraphs]

    records: list[dict] = []
    cur: dict | None = None
    open_change: dict | None = None

    for raw in lines:
        t = raw.strip()
        if not t:
            continue

        m = HEADER_RE.match(t)
        if m:
            # New word block begins.
            if cur is not None:
                records.append(cur)
            open_change = None
            cur = {
                'word_id': int(m.group(1)),
                'word': m.group(2).strip(),
                'section': m.group(3),
                'raw': [],
                'changes': [],
                'notes': [],
            }
            continue

        if cur is None:
            # Preamble (document title, "First Stage" / "Second Stage" banners).
            continue

        cur['raw'].append(t)

        if NOTE_RE.search(t) or any(w in t for w in STYLE_WORDS):
            cur['notes'].append(t)

        if ARROW_RE.search(t):
            parts = ARROW_RE.split(t, 1)
            if len(parts) == 2:
                before, after = parts[0].strip(), parts[1].strip()
                if before or after:
                    cur['changes'].append({'before': before, 'after': after})
                    open_change = cur['changes'][-1]
            continue

        # ---- wrapped column continuation --------------------------------
        # The document is a visual two-column layout, and long entries wrap:
        #
        #     ひばり「ラーク（たばこの銘  ⇨  ひばり
        #     柄」                           「スカイラーク」
        #
        # The second line continues BOTH columns, separated by a run of
        # padding spaces. Without rejoining them the real "after" is lost and
        # the instruction looks like a deletion rather than a replacement.
        if open_change is not None and not NOTE_RE.search(t):
            gap = COLUMN_GAP_RE.search(raw.rstrip())
            if gap:
                left = raw[:gap.start()].strip()
                right = raw[gap.end():].strip()
                if left or right:
                    open_change['before'] += left
                    open_change['after'] += right
                    continue
            elif INDENTED_RE.match(raw):
                # Heavily indented with no gap: continues the "after" only.
                open_change['after'] += t
                continue
        open_change = None

    if cur is not None:
        records.append(cur)

    return {
        'source': SRC.name,
        'word_count': len({r['word_id'] for r in records}),
        'record_count': len(records),
        'records': records,
    }


def main() -> None:
    if not SRC.exists():
        raise SystemExit(f'not found: {SRC}')
    doc = parse()
    OUT.write_text(json.dumps(doc, ensure_ascii=False, indent=2),
                   encoding='utf-8')

    recs = doc['records']
    with_changes = [r for r in recs if r['changes']]
    no_changes = [r for r in recs if not r['changes']]
    print(f'wrote {OUT.name}')
    print(f'  blocks parsed     : {len(recs)}')
    print(f'  unique words      : {doc["word_count"]}')
    print(f'  blocks w/ changes : {len(with_changes)}')
    print(f'  blocks w/o changes: {len(no_changes)}  (context-only)')
    print(f'  total changes     : {sum(len(r["changes"]) for r in recs)}')
    print(f'  blocks w/ style   : {sum(1 for r in recs if r["notes"])}')

    ids = sorted({r['word_id'] for r in recs})
    print(f'  id range          : {ids[0]}..{ids[-1]}')


if __name__ == '__main__':
    main()
