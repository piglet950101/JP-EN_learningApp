"""
Post-import patch: record which run of each ゴロ echoes the English word.

Client 2026-08-24 ③ splits a meaning line three ways — the meaning in gothic,
the part of the 「…」 mnemonic that echoes the English in gothic BOLD, and the
rest of the mnemonic in mincho. Only the author knows which characters carry
the pun: it may be Latin (OPEC/opaque), katakana (プリーズ/priest) or plain
kanji (政治/sage), so it is recorded here rather than guessed at render time.

An entry that is absent stays entirely gothic — its appearance before this
rule existed. That is deliberate: not every 「…」 is a ゴロ. Many are grammar
notes quoting Japanese (「賛成する」は自動詞), and those must not turn mincho.

Run AFTER apply_ss_overrides.py.
"""
from __future__ import annotations

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SS = ROOT / 'assets' / 'content' / 'second_stage.json'
ECHOES = Path(__file__).with_name('mnemonic_echo.json')


def main() -> None:
    doc = json.loads(SS.read_text(encoding='utf-8'))
    spec = json.loads(ECHOES.read_text(encoding='utf-8'))['entries']

    by_key: dict[tuple[int, str], list[str]] = {
        (e['word_id'], e['answer']): e['echo'] for e in spec}

    applied = 0
    warnings: list[str] = []
    seen: set[tuple[int, str]] = set()
    for e in doc['entries']:
        key = (e['word_id'], e['answer'])
        echo = by_key.get(key)
        if not echo:
            e.pop('mnemonic_echo', None)
            continue
        seen.add(key)
        meaning = e.get('answer_meaning') or ''
        missing = [n for n in echo if n not in meaning]
        if missing:
            # A marked run that is not in the text would silently do nothing,
            # so surface it instead of writing a dead marker.
            warnings.append(f'{key[0]} {key[1]}: not in meaning -> {missing}')
            continue
        if '「' not in meaning:
            warnings.append(f'{key[0]} {key[1]}: meaning has no 「…」')
            continue
        e['mnemonic_echo'] = echo
        applied += 1

    for key in by_key.keys() - seen:
        warnings.append(f'{key[0]} {key[1]}: no such entry')

    SS.write_text(json.dumps(doc, ensure_ascii=False, indent=2),
                  encoding='utf-8')
    print(f'mnemonic echoes applied: {applied}/{len(by_key)}')
    for w in warnings:
        print(f'  WARN: {w}')


if __name__ == '__main__':
    main()
