"""
NOTE: an override mapped to an EMPTY list is an intentional deletion — the
client asked for every row of that word to go (0269 defect, 1304 instead and
twelve others from the 2026-08-19 review). Do not "tidy away" empty entries:
removing one silently brings its rows back.
Post-import patch: apply per-word SS entry overrides from
`ss_overrides.json` on top of `assets/content/second_stage.json`.

For each override, all existing entries for that word_id are removed
and the override entries take their place. Block is inherited from
the first removed entry (SS entries never span blocks for one word).
IDs are re-assigned to keep them contiguous.
"""
from __future__ import annotations
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SS = ROOT / 'assets' / 'content' / 'second_stage.json'
OVERRIDES = Path(__file__).with_name('ss_overrides.json')


def _base_category(relation: str) -> str | None:
    codes = ['同音', '類', '反', '前', '熟', '活', '品', '法', '複', 'セ', '意',
             '名', '形', '副', '動']
    trimmed = relation.strip()
    for code in codes:
        if trimmed.startswith(code):
            return code
    return None


def main() -> None:
    doc = json.loads(SS.read_text(encoding='utf-8'))
    ovr = json.loads(OVERRIDES.read_text(encoding='utf-8'))['overrides']
    entries = doc['entries']

    modified_word_ids: set[int] = set()
    for id_str, replacements in ovr.items():
        wid = int(id_str)
        # Take the block from the FIRST existing entry for this word (they all share)
        existing = [e for e in entries if e['word_id'] == wid]
        if not existing:
            print(f'  WARN: no existing SS entries for word_id {wid}; skipping')
            continue
        block = existing[0]['block']
        # Remove existing entries
        entries[:] = [e for e in entries if e['word_id'] != wid]
        # Add replacements
        for r in replacements:
            entries.append({
                'id': 0,  # reassigned below
                'word_id': wid,
                'block': block,
                'relation': r['relation'],
                'base_category': _base_category(r['relation']),
                'answer': r['answer'],
                'answer_meaning': r.get('answer_meaning'),
                'tts_enabled': r.get('tts_enabled', True),
                'notes': r.get('notes'),
            })
        modified_word_ids.add(wid)

    # Sort by (word_id, then original order) and re-assign IDs 1..N.
    entries.sort(key=lambda e: (e['word_id'], e['id']))
    for i, e in enumerate(entries, start=1):
        e['id'] = i

    doc['count'] = len(entries)
    doc['entries'] = entries
    SS.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding='utf-8')
    print(f'SS overrides applied for {len(modified_word_ids)} word(s): {sorted(modified_word_ids)}')
    print(f'total entries now: {len(entries)}')


if __name__ == '__main__':
    main()
