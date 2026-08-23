"""Post-import patch: apply per-word field overrides from `word_overrides.json`
to `assets/content/words.json` (POS corrections, etc. not yet reflected in
the source Excel).
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORDS = ROOT / 'assets' / 'content' / 'words.json'
OVERRIDES = Path(__file__).with_name('word_overrides.json')


def main() -> None:
    doc = json.loads(WORDS.read_text(encoding='utf-8'))
    ovr = json.loads(OVERRIDES.read_text(encoding='utf-8'))['overrides']
    by_id = {w['id']: w for w in doc['words']}

    applied = 0
    warnings: list[str] = []
    for id_str, spec in ovr.items():
        wid = int(id_str)
        w = by_id.get(wid)
        if w is None:
            warnings.append(f'id={wid} not in words.json')
            continue
        if w['word'] != spec['word']:
            warnings.append(
                f'id={wid} word mismatch: json={w["word"]} vs override={spec["word"]}')
            continue
        field = spec['field']
        if field in ('pos', 'both'):
            new_pos = spec['new_pos_raw']
            w['pos_raw'] = new_pos
            # Rebuild pos_list from the raw POS. Uses the same normalization
            # rule as import_excel.py: strip (2)/2/(N) markers, then split on
            # '・' for multi-POS.
            base = new_pos.replace('(2)', '').replace('（2）', '').rstrip('2')
            base = base.replace('（2', '').replace('(2', '')
            parts = [p.strip() for p in base.split('・') if p.strip()]
            w['pos_list'] = parts
            # meaning_mode is derived from the POS marker, so it must be
            # recomputed — 0146 refer goes 自(２) -> 自２, i.e. from "either
            # meaning is acceptable" to "both meanings required".
            if '(2)' in new_pos or '（2）' in new_pos or '（２）' in new_pos:
                w['meaning_mode'] = 'either_ok'
            elif new_pos.rstrip().endswith(('2', '２')):
                w['meaning_mode'] = 'both_required'
            else:
                w['meaning_mode'] = 'single'
            if field == 'pos':
                applied += 1
                continue
        if field in ('meanings', 'both'):
            # Full replacement of the meaning list. Used by the 2026-08-19
            # review, where instructions like 「自　控える(from) ⇨ (from) をトル」
            # ask for a trailing preposition to be dropped from the headword's
            # own meaning — that text lives in words.json, not in the Second
            # Stage entries.
            new_meanings = spec['new_meanings']
            if not isinstance(new_meanings, list) or not new_meanings:
                warnings.append(f'id={wid} new_meanings must be a non-empty list')
                continue
            if any(not str(m).strip() for m in new_meanings):
                warnings.append(f'id={wid} refusing to write an empty meaning')
                continue
            w['meanings'] = [str(m) for m in new_meanings]
            applied += 1
            continue
        if field not in ('pos', 'meanings', 'both'):
            warnings.append(f'id={wid} unsupported field: {field}')

    WORDS.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'word overrides applied: {applied}/{len(ovr)}')
    for w in warnings:
        print(f'  WARN: {w}')


if __name__ == '__main__':
    main()
