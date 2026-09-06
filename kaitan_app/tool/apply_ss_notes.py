"""
Post-import patch: where a meaning turns into a supplementary note.

The client keeps asking for the same shape — 「cf. を黒字、小さく」, 「= answer
から改行」, 「epoch-making以下改行、黒字、小さく」. Part of the meaning is the
answer's gloss and the rest is an aside, and the aside wants its own line, in
black, at the smaller ゴロ size.

There is nothing in the text to mark that boundary, so it is recorded here.
The renderer breaks the line at this point and styles everything after it.

Run AFTER apply_ss_pronunciation.py.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SS = ROOT / 'assets' / 'content' / 'second_stage.json'
SPEC = Path(__file__).with_name('ss_notes.json')


def main() -> None:
    doc = json.loads(SS.read_text(encoding='utf-8'))
    spec = json.loads(SPEC.read_text(encoding='utf-8'))['entries']

    applied, warnings = 0, []
    for item in spec:
        hits = [e for e in doc['entries']
                if e['word_id'] == item['word_id'] and e['answer'] == item['answer']]
        if len(hits) != 1:
            warnings.append(
                f'{item["word_id"]} {item["answer"]!r}: {len(hits)} rows match')
            continue
        meaning = hits[0].get('answer_meaning') or ''
        if item['note_from'] not in meaning:
            # A marker that is not in the text would silently do nothing.
            warnings.append(
                f'{item["word_id"]}: {item["note_from"]!r} not in {meaning[:40]!r}')
            continue
        hits[0]['note_from'] = item['note_from']
        applied += 1

    SS.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'meaning notes applied: {applied}/{len(spec)}')
    for w in warnings:
        print(f'  WARN: {w}')


if __name__ == '__main__':
    main()
