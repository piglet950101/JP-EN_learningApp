"""
Post-import patch: words whose headword meaning must not be shown in Second
Stage.

The app works most of these out on its own — a bare 意 code asks for the
headword's own meaning, and so does a prompt that quotes it. Two cases defeat
that. 0572 disagree is asked as 「彼と意見が合わない」 while its meaning reads
「不賛成である」: the same idea in different words, with nothing in the text to
connect them. No rule over the strings can find that.

So the client's own column is kept as the record and wins outright. Deriving
it stays as the default for everything they have not listed.

Run AFTER apply_word_overrides.py.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORDS = ROOT / 'assets' / 'content' / 'words.json'
SPEC = Path(__file__).with_name('ss_hide_headword.json')


def main() -> None:
    doc = json.loads(WORDS.read_text(encoding='utf-8'))
    spec = json.loads(SPEC.read_text(encoding='utf-8'))['word_ids']
    by_id = {w['id']: w for w in doc['words']}

    applied, warnings = 0, []
    for item in spec:
        w = by_id.get(item['id'])
        if w is None:
            warnings.append(f'id={item["id"]} not in words.json')
            continue
        if item.get('word') and w['word'] != item['word']:
            warnings.append(
                f'id={item["id"]} is {w["word"]}, list says {item["word"]}')
            continue
        w['hide_meaning_in_ss'] = True
        applied += 1

    WORDS.write_text(json.dumps(doc, ensure_ascii=False, indent=2),
                     encoding='utf-8')
    print(f'headword-meaning hides applied: {applied}/{len(spec)}')
    for w in warnings:
        print(f'  WARN: {w}')


if __name__ == '__main__':
    main()
