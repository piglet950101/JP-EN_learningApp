"""
Rebuild every bundled content asset, in the one order that is correct.

The steps are not interchangeable. Each importer OVERWRITES its asset from
source, so every patch that follows has to be re-applied afterwards or it is
silently lost — and a lost patch does not look broken on screen, it just
quietly stops obeying the client. apply_mnemonic_echo.py is the easiest to
forget, because without it the ゴロ simply render as they always used to.

Run this rather than the individual scripts.
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent


def reseal_second_stage() -> None:
    """Rewrite second_stage.json's header so it matches its own rows.

    import_second_stage stamps count/stats, and every later step edits entries
    underneath them, so the header drifts. It had drifted to 1974 while the
    file held 1972 — the two rows an over-broad 2026-09-10 correction deleted —
    and nothing noticed, because only doc['entries'] is ever read at runtime.
    Resealing makes the header a canary: the delta printed below is the row
    count moving when it should not have.
    """
    ss = HERE.parent / 'assets' / 'content' / 'second_stage.json'
    doc = json.loads(ss.read_text(encoding='utf-8'))
    rows = doc['entries']
    was = doc.get('count')
    doc['count'] = len(rows)
    doc.setdefault('stats', {})['unique_word_ids'] = len({r['word_id'] for r in rows})
    ss.write_text(json.dumps(doc, ensure_ascii=False, indent=2), encoding='utf-8')
    note = '' if was == len(rows) else f'  <- header said {was}'
    print(f'second_stage.json resealed: {len(rows)} entries, '
          f'{doc["stats"]["unique_word_ids"]} words{note}')


STEPS = [
    # second_stage.json
    ('import_second_stage.py',    'rebuild Second Stage from the client sheet'),
    ('apply_ss_overrides.py',     'per-word corrections (incl. the 08-19 review)'),
    ('apply_ss_text_edits.py',    'field-level row corrections (09-08 review)'),
    ('apply_mnemonic_echo.py',    'which run of each ゴロ echoes the English'),
    ('apply_ss_pronunciation.py', 'per-row reading where the spelling misleads'),
    ('apply_ss_notes.py',        'where a meaning turns into a smaller aside'),
    # words.json
    ('import_excel.py',           'rebuild the headword list from the Excel'),
    ('apply_word_overrides.py',   'headword POS / meaning corrections'),
    ('apply_mnemonic_overrides.py', 'headword mnemonic corrections'),
    ('apply_hide_headword.py',    'words whose meaning SS must not show'),
    # media
    ('import_ss_audio.py',        'client recordings, level-matched, per SS row'),
    ('import_videos.py',          'video manifest incl. footage aspect ratio'),
]


def main() -> int:
    failed: list[str] = []
    for script, why in STEPS:
        path = HERE / script
        if not path.exists():
            print(f'!! missing: {script}')
            failed.append(script)
            continue
        print(f'\n── {script}  ({why})')
        r = subprocess.run([sys.executable, '-X', 'utf8', str(path)],
                           capture_output=True, text=True, encoding='utf-8')
        out = (r.stdout or '').strip()
        if out:
            print('   ' + out.replace('\n', '\n   '))
        if r.returncode != 0:
            print('   ' + (r.stderr or '').strip().replace('\n', '\n   '))
            failed.append(script)

    print()
    if failed:
        print(f'FAILED: {", ".join(failed)}')
        return 1
    reseal_second_stage()
    print('content rebuilt — all steps ok')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
