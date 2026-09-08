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
# 09-06 keeps the per-rule columns; 09-07 drops them for one free-form column,
# and a revision hiding in there still supersedes everything before it —
# 1221 akin went 意 kin, then 意２ kin on 09-02, then back to 意 kin on 09-07.
SHEETS = ((PROJECT / 'Second Stage 直し 9. 6.xlsx', '09-06'),
          (PROJECT / 'Second Stage 直し 9. 7.xlsx', '09-07'),
          (PROJECT / 'Second Stage 直し 9. 8.xlsx', '09-08'))
# 「意２kin を 意 kin に」 — the target sits between を and に.
FREEFORM = re.compile(r'を\s*(意[^\s　]*(?:[\s　]+[^\s　]+)?)[\s　]*に')
# A count marker and nothing else — ２, ２～３, ３以上, １～２.
COUNT_ONLY = re.compile(r'[０-９0-9()（）～~〜、,，・]+(?:以上)?')

# Instructions the client has since withdrawn in a later sheet, where the
# replacement is not itself an 意 instruction and so cannot supersede the
# earlier one on its own. Recorded rather than deleted, so the reason
# survives: without this the audit reports them open every single round.
SUPERSEDED = {
    1186: ('09-08', '意2 withdrawn — 「見出し語の下の意味を削除する」 instead'),
    1125: ('09-09', '意2 withdrawn — 「dismayは意味１つで大丈夫です」'),
}

# Block numbers the client has corrected; the earlier number and the later one
# describe the same word and must be merged before ordering by date.
SLIP = {723: 733, 754: 750, 1256: 1526, 1835: 1836, 1916: 1915,
        2073: 2074, 2106: 2196}

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

    for path, date in SHEETS:
        if not path.exists():
            continue
        sheet = openpyxl.load_workbook(path, data_only=True).worksheets[0]
        for row in sheet.iter_rows(min_row=2, values_only=True):
            if not row[1] or not str(row[1]).strip():
                continue
            wid = int(row[1])
            # A dedicated 意 column, when the sheet still has one. It must be
            # a bare count and nothing else: the 09-07 and 09-08 sheets put
            # free-form text in the same position, and 0773 lead's entry opens
            # 「１．問題の 活 の…」, which a leading-digit test read as 意１.
            if len(row) > 3 and row[3] is not None                     and COUNT_ONLY.fullmatch(str(row[3]).strip()):
                add(wid, date, '意' + str(row[3]).strip())
            # otherwise dig the target out of the free-form text
            for cell in row[3:]:
                if cell is None:
                    continue
                m = FREEFORM.search(str(cell))
                if m:
                    add(wid, date, m.group(1).strip())

    retired = []
    for wid, (date, why) in SUPERSEDED.items():
        if wid in history:
            del history[wid]
            retired.append((wid, date, why))

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
    for wid, date, why in retired:
        print(f'  superseded {wid} ({date}): {why}')
    for wid, word, want, date, got, seq in mismatch:
        print(f'  MISMATCH {wid} {word}: want({date})={want!r} got={got}')
        print(f'           history={seq}')
    for wid, word, want, date in missing:
        print(f'  NO ROW   {wid} {word}: want({date})={want!r}')


if __name__ == '__main__':
    main()
