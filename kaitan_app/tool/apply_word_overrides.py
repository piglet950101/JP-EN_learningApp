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
        if field == 'pos':
            new_pos = spec['new_pos_raw']
            w['pos_raw'] = new_pos
            # Rebuild pos_list from the raw POS. Uses the same normalization
            # rule as import_excel.py: strip (2)/2/(N) markers, then split on
            # '・' for multi-POS.
            base = new_pos.replace('(2)', '').replace('（2）', '').rstrip('2')
            base = base.replace('（2', '').replace('(2', '')
            parts = [p.strip() for p in base.split('・') if p.strip()]
            w['pos_list'] = parts
            applied += 1
        else:
            warnings.append(f'id={wid} unsupported field: {field}')

    WORDS.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'word overrides applied: {applied}/{len(ovr)}')
    for w in warnings:
        print(f'  WARN: {w}')


if __name__ == '__main__':
    main()
