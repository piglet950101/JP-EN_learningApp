"""Post-import patch: apply per-word mnemonic bold-run overrides from
`mnemonic_overrides.json` on top of `assets/content/words.json`.

Client's 2026-07-20 「First Stage 訂正.docx」 boxed items require bold ranges
that the Excel source does not carry. Rather than round-tripping bold into
Excel, we keep the exact rendering intent here.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORDS = ROOT / 'assets' / 'content' / 'words.json'
OVERRIDES = Path(__file__).with_name('mnemonic_overrides.json')


def main() -> None:
    words_doc = json.loads(WORDS.read_text(encoding='utf-8'))
    overrides = json.loads(OVERRIDES.read_text(encoding='utf-8'))['overrides']
    by_id = {w['id']: w for w in words_doc['words']}

    applied = 0
    errors: list[str] = []
    for id_str, spec in overrides.items():
        wid = int(id_str)
        w = by_id.get(wid)
        if w is None:
            errors.append(f'id={wid} not found in words.json')
            continue
        if w['word'] != spec['word']:
            errors.append(f'id={wid} word mismatch: json={w["word"]} vs override={spec["word"]}')
            continue
        mtype = spec['mnemonic_type']
        target = next((m for m in w['mnemonics'] if m['type'] == mtype), None)
        if target is None:
            errors.append(f'id={wid} mnemonic type "{mtype}" not present')
            continue
        target['runs'] = spec['runs']
        # 1993 overwhelming was filed under 語源 but the client reclassified it
        # as イメージ, so the heading has to change too, not only the text.
        if spec.get('new_mnemonic_type'):
            target['type'] = spec['new_mnemonic_type']
        applied += 1

    WORDS.write_text(json.dumps(words_doc, ensure_ascii=False, indent=2),
                     encoding='utf-8')
    print(f'mnemonic overrides applied: {applied}/{len(overrides)}')
    for e in errors:
        print(f'  WARN: {e}')


if __name__ == '__main__':
    main()
