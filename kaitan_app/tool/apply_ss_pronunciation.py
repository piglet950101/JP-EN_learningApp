"""
Post-import patch: how a Second Stage row's answer should be READ.

Some answers cannot be spoken from their own text. 0242 wind is read ウインド
by the engine but must be ワインド; 0410 prayer is プレア in the 祈り row and
プレイア in the 祈る人 row — same spelling, two readings, so nothing derived
from the text could tell them apart. Others are Japanese answers whose audio
should say the English word (0718 board, 0544 vowel).

Kana hints are spoken by the Japanese voice, which is what forces an English
spelling to a specific sound. Latin hints are read as-is.

An absent entry reads its own answer, which is the behaviour everywhere else.

Run AFTER apply_ss_overrides.py.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SS = ROOT / 'assets' / 'content' / 'second_stage.json'
SPEC = Path(__file__).with_name('ss_pronunciation.json')


def main() -> None:
    doc = json.loads(SS.read_text(encoding='utf-8'))
    spec = json.loads(SPEC.read_text(encoding='utf-8'))['entries']

    applied = 0
    warnings: list[str] = []
    for item in spec:
        wid, ans = item['word_id'], item['answer']
        rel = item.get('relation')
        hits = [e for e in doc['entries']
                if e['word_id'] == wid and e['answer'] == ans
                and (rel is None or e['relation'].strip() == rel)]
        if not hits:
            warnings.append(f'{wid} {ans!r}: no such row')
            continue
        if len(hits) > 1:
            # Two rows sharing a spelling is exactly the 0410 prayer case, so
            # refuse rather than guess which one the reading belongs to.
            warnings.append(
                f'{wid} {ans!r}: {len(hits)} rows match — add a "relation"')
            continue
        if not hits[0].get('tts_enabled'):
            warnings.append(f'{wid} {ans!r}: reading set but audio is off')
        hits[0]['pronunciation_hint'] = item['pronunciation']
        applied += 1

    SS.write_text(json.dumps(doc, ensure_ascii=False, indent=2),
                  encoding='utf-8')
    print(f'pronunciations applied: {applied}/{len(spec)}')
    for w in warnings:
        print(f'  WARN: {w}')


if __name__ == '__main__':
    main()
