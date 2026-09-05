"""
Independent audit: does the SHIPPED content satisfy every instruction the
client has sent since 2026-08-26?

Written because per-batch verifier scores are misleading over time. The client
revises the same word across documents — 1836 observe is 意４～５, then 意５,
then 意４～５ again — so an old batch's score FALLS when a newer instruction
supersedes it, and that looks like a regression when nothing broke.

This walks every instruction in date order, keeps only the last one per word,
and checks the shipped data against that. It also merges the numbering slips
first: observe appears as 1835 in the early documents and 1836 from 09-02, and
without merging, the stale 1835 stream wins the ordering and reports a fault
that does not exist.

Point --content at a directory holding second_stage.json and words.json —
extract those from the APK to audit what actually shipped rather than the
working tree.
"""
from __future__ import annotations

import argparse
import json
import re
import unicodedata
from pathlib import Path

import openpyxl

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT.parent
DOCS = (('08-26', ROOT / 'tool' / 'corrections_0826.json'),
        ('08-31', ROOT / 'tool' / 'corrections_0831.json'),
        ('09-02', ROOT / 'tool' / 'corrections_0902.json'))
SHEET = PROJECT / 'Second Stage 直し 9. 4.xlsx'

# Block numbers the client has corrected; the earlier number and the later one
# describe the same word and must be merged before ordering by date.
SLIP = {723: 733, 754: 750, 1835: 1836, 1916: 1915, 2073: 2074, 2106: 2196}

TARGET = re.compile(
    r'^意\s*[他自名形副動]?\s*[０-９0-9]+\s*(?:[～~]\s*[０-９0-9]+)?\s*(?:以上)?$')


def canon(s: str | None) -> str:
    s = unicodedata.normalize('NFKC', s or '')
    s = re.sub(r'[\s\u3000]', '', s)
    return s.replace('\u301c', '~').replace('\uff5e', '~')


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument('--content', default=str(ROOT / 'assets' / 'content'))
    args = ap.parse_args()
    content = Path(args.content)

    ss = json.loads((content / 'second_stage.json').read_text(encoding='utf-8'))['entries']
    words = {w['id']: w for w in
             json.loads((content / 'words.json').read_text(encoding='utf-8'))['words']}
    by: dict[int, list] = {}
    for e in ss:
        by.setdefault(e['word_id'], []).append(e)

    history: dict[int, list[tuple[str, str]]] = {}

    def add(wid: int, date: str, want: str) -> None:
        history.setdefault(SLIP.get(wid, wid), []).append((date, want))

    for date, path in DOCS:
        for rec in json.loads(path.read_text(encoding='utf-8'))['records']:
            for ch in rec['changes']:
                if ch['before'].strip().startswith('意') \
                        and TARGET.fullmatch(ch['after'].strip()):
                    add(rec['word_id'], date, ch['after'].strip())

    if SHEET.exists():
        sheet = openpyxl.load_workbook(SHEET, data_only=True)['Sheet1']
        for row in sheet.iter_rows(min_row=2, values_only=True):
            if row[1] and str(row[1]).strip() and row[3] is not None \
                    and str(row[3]).strip():
                add(int(row[1]), '09-04', '意' + str(row[3]).strip())

    ok, mismatch, missing = 0, [], []
    for wid, seq in sorted(history.items()):
        date, want = sorted(seq)[-1]
        rows = [e for e in by.get(wid, [])
                if e['relation'].strip().startswith('意')]
        if not rows:
            missing.append((wid, words.get(wid, {}).get('word', '?'), want, date))
        elif any(canon(e['relation']).startswith(canon(want)) for e in rows):
            ok += 1
        else:
            mismatch.append((wid, words.get(wid, {}).get('word', '?'), want,
                             date, [e['relation'].strip() for e in rows], seq))

    print(f'content audited     : {content}')
    print(f'words instructed    : {len(history)}')
    print(f'  matches latest    : {ok}')
    print(f'  mismatch          : {len(mismatch)}')
    print(f'  no 意 row exists  : {len(missing)}')
    for wid, word, want, date, got, seq in mismatch:
        print(f'  MISMATCH {wid} {word}: want({date})={want!r} got={got}')
        print(f'           history={seq}')
    for wid, word, want, date in missing:
        print(f'  NO ROW   {wid} {word}: want({date})={want!r}')


if __name__ == '__main__':
    main()
