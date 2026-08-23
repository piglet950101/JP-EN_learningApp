"""
Verify the 2026-08-19 client review against the FINAL Second Stage data.

This deliberately re-reads the docx independently of the applier, so a bug in
apply_corrections_0820.py cannot mark its own work as correct. For every
instruction it asks one question of the shipped data:

    is the "before" state gone, and the "after" state present?

Categories reported
    SATISFIED   after-state present, before-state absent   -> done
    PENDING     before-state still present                 -> not yet applied
    UI_RULE     handled by an app rendering rule, not data  -> nothing to check
    UNKNOWN     neither state found; needs a human to look

Run AFTER import_second_stage.py + apply_ss_overrides.py.
"""
from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CORRECTIONS = HERE / 'corrections_0820.json'
SS = ROOT / 'assets' / 'content' / 'second_stage.json'
WORDS = ROOT / 'assets' / 'content' / 'words.json'
REPORT = HERE / 'verify_0820_report.txt'

POS = r'[他自名形副動前接]'
ARROW_JUNK = re.compile(r'[↱↳↲⇨→]')
STYLE_WORDS = ('明朝', 'ゴチ', '太', 'ふつう', '小さい字', '黒', '音声')


def norm(s: str | None) -> str:
    if not s:
        return ''
    return re.sub(r'\s+', '', unicodedata.normalize('NFKC', s))


def main() -> None:
    corr = json.loads(CORRECTIONS.read_text(encoding='utf-8'))
    ss = json.loads(SS.read_text(encoding='utf-8'))['entries']
    words = {w['id']: w for w in
             json.loads(WORDS.read_text(encoding='utf-8'))['words']}

    by_word: dict[int, list[dict]] = {}
    for e in ss:
        by_word.setdefault(e['word_id'], []).append(e)

    def haystack(wid: int) -> str:
        """All searchable text for a word, as one normalized blob."""
        parts = []
        for e in by_word.get(wid, []):
            parts += [e['relation'], e['answer'], e['answer_meaning'] or '']
        return norm(''.join(parts))

    counts = {'SATISFIED': 0, 'PENDING': 0, 'UI_RULE': 0, 'UNKNOWN': 0}
    lines: list[str] = []

    for r in corr['records']:
        wid = r['word_id']
        hw = words.get(wid)
        hay = haystack(wid)
        hw_line = norm(hw['pos_raw'] + ''.join(hw['meanings'])) if hw else ''

        for ch in r['changes']:
            b_raw, a_raw = ch['before'], ch['after']
            b, a = norm(b_raw), norm(a_raw)
            if not b:
                continue

            # Rendering rules operate on presentation, not stored data.
            if b == a or any(w in a_raw for w in STYLE_WORDS):
                counts['UI_RULE'] += 1
                continue
            # 「headword POS + meaning ⇨ トル」 is the hide-headword-line rule.
            if a.startswith(('トル', 'カット')) and hw_line and b == hw_line:
                counts['UI_RULE'] += 1
                continue
            # 「POS ⇨ POS <meaning>」 is the same rule seen from the other side.
            if re.fullmatch(POS + r'[２2３3]?', b_raw.strip()) \
                    and re.match(r'^' + POS, a_raw.strip()) \
                    and len(a_raw.strip()) > 2:
                counts['UI_RULE'] += 1
                continue

            a_clean = norm(ARROW_JUNK.sub('', a_raw))
            before_present = b in hay

            if a.startswith(('トル', 'カット')):
                # A deletion is done once the target text is gone.
                if not before_present:
                    counts['SATISFIED'] += 1
                else:
                    counts['PENDING'] += 1
                    lines.append(f'PENDING  {wid}: delete {b_raw!r}')
                continue

            after_present = bool(a_clean) and a_clean in hay
            if after_present and not before_present:
                counts['SATISFIED'] += 1
            elif before_present:
                counts['PENDING'] += 1
                lines.append(f'PENDING  {wid}: {b_raw!r} => {a_raw[:56]!r}')
            else:
                counts['UNKNOWN'] += 1
                lines.append(f'UNKNOWN  {wid}: {b_raw!r} => {a_raw[:56]!r}')

    REPORT.write_text('\n'.join(lines), encoding='utf-8')

    total = sum(counts.values())
    print(f'instructions checked : {total}')
    for k in ('SATISFIED', 'UI_RULE', 'PENDING', 'UNKNOWN'):
        print(f'  {k:10s} {counts[k]:4d}  ({counts[k] / total * 100:5.1f}%)')
    done = counts['SATISFIED'] + counts['UI_RULE']
    print()
    print(f'resolved end-to-end  : {done} / {total} ({done / total * 100:.1f}%)')
    print(f'wrote {REPORT.name}')


if __name__ == '__main__':
    main()
