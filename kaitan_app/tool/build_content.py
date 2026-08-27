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

import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent

STEPS = [
    # second_stage.json
    ('import_second_stage.py',    'rebuild Second Stage from the client sheet'),
    ('apply_ss_overrides.py',     'per-word corrections (incl. the 08-19 review)'),
    ('apply_mnemonic_echo.py',    'which run of each ゴロ echoes the English'),
    ('apply_ss_pronunciation.py', 'per-row reading where the spelling misleads'),
    # words.json
    ('import_excel.py',           'rebuild the headword list from the Excel'),
    ('apply_word_overrides.py',   'headword POS / meaning corrections'),
    ('apply_mnemonic_overrides.py', 'headword mnemonic corrections'),
    # videos.json
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
    print('content rebuilt — all steps ok')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
