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
# 「(from) をトル」「(in), (on) をカット」「(to) を取る」 — delete verb at the end.
STRIP_TAIL_RE = re.compile(
    r'^([（(].+?[）)](?:\s*[,、]\s*[（(].+?[）)])*)\s*を?\s*(?:トル|カット|取る)\s*$')
STYLE_WORDS = ('明朝', 'ゴチ', '太', 'ふつう', '小さい字', '黒', '音声',
                '小さく', 'ちいさく', '字を小さく')


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

    def fields(wid: int) -> list[str]:
        """Every individual field value for a word, normalized.

        Covers BOTH datasets. Some instructions edit the headword's own POS
        and meaning, which live in words.json — e.g.「自　控える(from) ⇨
        (from) をトル」. Searching only the Second Stage entries made those
        look unresolvable when they had in fact been applied.
        """
        out = []
        for e in by_word.get(wid, []):
            out += [norm(e['relation']), norm(e['answer']),
                    norm(e['answer_meaning'])]
        hw = words.get(wid)
        if hw:
            out.append(norm(hw['pos_raw']))
            out += [norm(m) for m in hw['meanings']]
            out.append(norm(hw['pos_raw'] + ''.join(hw['meanings'])))
        return [f for f in out if f]

    def present(needle: str, vals: list[str]) -> bool:
        """Is this text present in the word's data?

        Short needles (意 / 法 / 類 …) must match a WHOLE field. Testing them
        as substrings makes them match almost anything — 意 occurs inside
        意２, 意 lark, 意３とそれぞれの前置詞 — which previously made ~45
        instructions look permanently unapplied.
        """
        if not needle:
            return False
        if len(needle) <= 3:
            return any(needle == v for v in vals)
        return any(needle in v for v in vals)

    counts = {'SATISFIED': 0, 'PENDING': 0, 'UI_RULE': 0, 'UNKNOWN': 0}
    lines: list[str] = []

    for r in corr['records']:
        wid = r['word_id']
        hw = words.get(wid)
        vals = fields(wid)
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

            # Pattern C: the "before" carries two or more POS-labelled senses
            # and the "after" is its first sense — a line-break request, which
            # the app's rendering rule handles. The docx column wrap often
            # truncates these mid-phrase, so compare on the leading sense.
            multi_pos = len(re.findall(POS + r'\s', b_raw)) >= 2
            if multi_pos and a and (b.startswith(a) or a in b):
                counts['UI_RULE'] += 1
                continue

            # 「(from) をトル」 — a strip instruction, with the delete verb at
            # the END rather than the start. The target is the bracketed text,
            # and it is done once that text no longer appears anywhere for
            # this word.
            m_strip = STRIP_TAIL_RE.match(a_raw.strip())
            if m_strip:
                targets = re.findall(r'[（(].+?[）)]', m_strip.group(1))
                if targets and not any(norm(t) in ''.join(vals) for t in targets):
                    counts['SATISFIED'] += 1
                else:
                    counts['PENDING'] += 1
                    lines.append(f'PENDING  {wid}: strip {m_strip.group(1)!r}')
                continue

            a_clean = norm(ARROW_JUNK.sub('', a_raw))
            before_present = present(b, vals)

            if a.startswith(('トル', 'カット')):
                # A deletion is done once the target text is gone.
                if not present(b, vals):
                    counts['SATISFIED'] += 1
                else:
                    counts['PENDING'] += 1
                    lines.append(f'PENDING  {wid}: delete {b_raw!r}')
                continue

            after_present = present(a_clean, vals)
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
