"""Post-import patch: field-level corrections to individual Second Stage rows.

ss_overrides.json replaces every row of a word at once, which is the right
shape for the big 2026-08-19 review but far too blunt for "put a line break
before 空所には". Restating a word's other four rows just to move one break is
how rows get dropped by accident, so those edits live here instead: each entry
names one row and only the fields that change.

A row is matched on word_id plus `answer` and/or `relation` (whichever the
entry gives, both must match when both are given). `delete: true` removes the
matched row outright; otherwise the named fields are written. Anything that fails to
match is reported rather than skipped silently — a stale key means the client's
correction is not in the build, and that has cost review rounds before.

Run AFTER apply_ss_overrides.py and BEFORE the steps keyed on (word_id,
answer): apply_mnemonic_echo, apply_ss_pronunciation and apply_ss_notes all
look rows up by their answer text, so they must see the edited value.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SS = ROOT / 'assets' / 'content' / 'second_stage.json'
EDITS = Path(__file__).with_name('ss_text_edits.json')

FIELDS = ('relation', 'answer', 'answer_meaning', 'tts_enabled',
          'pronunciation_hint', 'chip_whole')


def main() -> None:
    doc = json.loads(SS.read_text(encoding='utf-8'))
    spec = json.loads(EDITS.read_text(encoding='utf-8'))['entries']

    applied = 0
    warnings: list[str] = []
    for e in spec:
        wid = e['word_id']
        want_answer = e.get('match_answer')
        want_relation = e.get('match_relation')
        hits = []
        for row in doc['entries']:
            if row['word_id'] != wid:
                continue
            if want_answer is not None and row.get('answer') != want_answer:
                continue
            if want_relation is not None \
                    and row.get('relation') != want_relation:
                continue
            hits.append(row)

        if not hits:
            warnings.append(
                f'{wid}: no row matches answer={want_answer!r} '
                f'relation={want_relation!r}')
            continue
        if len(hits) > 1:
            warnings.append(
                f'{wid}: {len(hits)} rows match answer={want_answer!r} '
                f'relation={want_relation!r} — narrow the key')
            continue

        row = hits[0]
        if e.get('delete'):
            # Deleting is spelled out rather than done by restating the word's
            # other rows through ss_overrides, where an empty list already
            # means "drop every row for this word" and is easy to trip over.
            doc['entries'].remove(row)
            applied += 1
            continue
        changed = False
        for field in FIELDS:
            if field not in e:
                continue
            if row.get(field) == e[field]:
                continue
            row[field] = e[field]
            changed = True
        if changed:
            applied += 1
        else:
            warnings.append(f'{wid}: already matches, nothing to change')

    SS.write_text(json.dumps(doc, ensure_ascii=False, indent=2),
                  encoding='utf-8')
    print(f'ss text edits applied: {applied}/{len(spec)}')
    for w in warnings:
        print(f'  WARNING: {w}')


if __name__ == '__main__':
    main()
