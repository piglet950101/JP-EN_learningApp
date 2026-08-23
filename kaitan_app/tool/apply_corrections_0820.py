"""
Apply the 2026-08-19 client review (アプリ直し Second Stage 8. 20.docx) to the
Second Stage data, emitting per-word override records.

Strategy
--------
`ss_overrides.json` REPLACES every entry for a word, so for each corrected word
we must reconstruct its complete final state — not a diff. We therefore:

  1. start from the word's current entries in second_stage.json,
  2. locate each change's target field by matching the docx "before" text
     against that word's relation / answer / answer_meaning values,
  3. apply the change,
  4. emit the resulting full entry list.

Anything that cannot be matched with confidence is NOT guessed. It is written
to an unresolved report for manual review, so a mis-parse can never silently
corrupt the client's content.

Run AFTER import_second_stage.py, BEFORE apply_ss_overrides.py.

Outputs
    tool/ss_overrides_0820.json   — generated overrides (review, then merge)
    tool/unresolved_0820.txt      — changes needing a human decision
"""
from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CORRECTIONS = HERE / 'corrections_0820.json'
SS = ROOT / 'assets' / 'content' / 'second_stage.json'
OUT_OVERRIDES = HERE / 'ss_overrides_0820.json'
OUT_UNRESOLVED = HERE / 'unresolved_0820.txt'

# Trailing editorial remarks the client appends to the "after" column. These
# describe the edit rather than forming part of the value, so they are stripped.
ANNOTATIONS = [
    'アクセントをトル', 'アクセントを取る',
    'スペリングミス', '音声追加', 'これを追加', '解答も', '問題も',
    '私のミスです', 'タイトルが違っていました',
    '明朝、ふつう', '明朝、太さはふつう', 'ゴチ、太', '明朝', 'ゴチ',
    '黒、小さい字で', '小さい字で', '小さい字', '太字でなく', '黒',
]
ARROW_JUNK = re.compile(r'[↱↳↲⇨→]')
# Latin letters carrying an acute/grave accent, e.g. cómpensate.
ACCENTED = re.compile(r'[À-ɏ]')


def norm(s: str | None) -> str:
    """Whitespace/width-insensitive key for comparing client text to data."""
    if not s:
        return ''
    s = unicodedata.normalize('NFKC', s)
    return re.sub(r'\s+', '', s)


def strip_accents(s: str) -> str:
    out = unicodedata.normalize('NFD', s)
    out = ''.join(c for c in out if unicodedata.category(c) != 'Mn')
    return unicodedata.normalize('NFC', out)


def clean_after(s: str) -> str:
    """Remove editorial annotations, leaving the intended value."""
    out = ARROW_JUNK.sub(' ', s)
    for a in ANNOTATIONS:
        out = out.replace(a, ' ')
    out = re.sub(r'[　 ]{2,}', ' ', out)
    return out.strip(' 　、,')


# Relation codes that can begin a NEW sibling entry when they appear in an
# added tail (「… + 形 illiterate」).
_CODES = ('同音', '類', '反', '前', '熟', '活', '品', '法', '複', 'セ', '意',
          '名', '形', '副', '動')


def _starts_with_code(s: str) -> bool:
    t = s.strip()
    return any(t.startswith(c) for c in _CODES)


def _joined_raw(e: dict) -> str:
    return norm(f"{e['relation']}{e['answer']}{e['answer_meaning'] or ''}")


def _match_joined(entries: list[dict], b: str):
    """Find the entry whose relation+answer+meaning, run together, equals or
    prefixes the client's row. Returns (entry, joined) or (None, '')."""
    if not b:
        return None, ''
    best = None
    for e in entries:
        j = _joined_raw(e)
        if not j:
            continue
        if j == b or b.startswith(j) or j.startswith(b):
            # Prefer the longest overlap so a short entry does not win over
            # the one the row is really describing.
            if best is None or len(_joined_raw(best)) < len(j):
                best = e
    return (best, _joined_raw(best)) if best else (None, '')


def _trim_to(val: str, keep_normalized: int) -> str:
    """Trim `val` so its normalized form is `keep_normalized` chars long."""
    out = val
    while out and len(norm(out)) > keep_normalized:
        out = out[:-1]
    return out.rstrip(' 　、,')


def is_delete(after_raw: str) -> bool:
    # The client uses both 「トル」 and 「カット」 for "remove this".
    a = norm(after_raw)
    return a.startswith('トル') or a.startswith('カット')


def main() -> None:
    corr = json.loads(CORRECTIONS.read_text(encoding='utf-8'))
    ss = json.loads(SS.read_text(encoding='utf-8'))

    by_word: dict[int, list[dict]] = {}
    for e in ss['entries']:
        by_word.setdefault(e['word_id'], []).append(dict(e))

    # Collapse the docx's per-section blocks into one change list per word:
    # 問題 and 解答 describe the same underlying entry from two screens.
    changes_by_word: dict[int, list[dict]] = {}
    for r in corr['records']:
        changes_by_word.setdefault(r['word_id'], []).extend(r['changes'])

    overrides: dict[str, list[dict]] = {}
    unresolved: list[str] = []
    stats = {'delete': 0, 'relation': 0, 'relation_prefix': 0, 'answer': 0,
             'meaning': 0, 'accent': 0, 'strip': 0, 'tts': 0, 'extend': 0, 'shrink': 0, 'already': 0,
             'skipped_style': 0, 'unresolved': 0}

    for wid in sorted(changes_by_word):
        entries = by_word.get(wid)
        if not entries:
            unresolved.append(f'{wid}: no Second Stage entries exist for this word')
            stats['unresolved'] += len(changes_by_word[wid])
            continue

        touched = False
        # Which distinct "after" values each "before" is mapped to, so a
        # positional assignment can be distinguished from a plain rename.
        distinct_after: dict[str, set[str]] = {}
        for ch in changes_by_word[wid]:
            kb = norm(ch['before'])
            if kb:
                distinct_after.setdefault(kb, set()).add(clean_after(ch['after']))
        claimed: set[int] = set()

        for ch in changes_by_word[wid]:
            b_raw, a_raw = ch['before'], ch['after']
            b, a_clean = norm(b_raw), clean_after(a_raw)
            a = norm(a_clean)

            if not b:
                continue

            # Styling-only instruction (before == after) — already handled by
            # the global 「」 / POS-line-break rules in the app.
            if b == a:
                stats['skipped_style'] += 1
                continue

            # --- deletion ------------------------------------------------
            if is_delete(a_raw):
                hit = [e for e in entries
                       if b in (norm(e['relation']), norm(e['answer']),
                                norm(e['answer_meaning']))
                       or b == norm(f"{e['relation']}{e['answer']}")]
                if hit:
                    for e in hit:
                        entries.remove(e)
                    stats['delete'] += 1
                    touched = True
                else:
                    unresolved.append(f'{wid}: DELETE target not found -> {b_raw!r}')
                    stats['unresolved'] += 1
                continue

            # --- 「音声追加」 = enable TTS, do NOT touch the text ----------
            if '音声追加' in a_raw:
                hit = [e for e in entries
                       if b in (norm(e['answer']), norm(e['relation']),
                                norm(e['answer_meaning']))]
                if hit:
                    for e in hit:
                        e['tts_enabled'] = True
                    stats['tts'] += 1
                    touched = True
                else:
                    unresolved.append(
                        f'{wid}: 音声追加 target not found -> {b_raw!r}')
                    stats['unresolved'] += 1
                continue

            # --- accent removal -----------------------------------------
            if 'アクセント' in a_raw:
                done = False
                for e in entries:
                    if ACCENTED.search(e['answer'] or ''):
                        e['answer'] = strip_accents(e['answer'])
                        done = True
                if done:
                    stats['accent'] += 1
                    touched = True
                else:
                    unresolved.append(f'{wid}: ACCENT target not found -> {b_raw!r}')
                    stats['unresolved'] += 1
                continue

            # --- already satisfied? --------------------------------------
            # The docx often restates the same fix in both the 問題 and 解答
            # blocks, and some fixes were already applied by an earlier
            # override round. If nothing matches "before" but something
            # already matches "after", the correction is simply done.
            def field_vals(e: dict) -> tuple[str, ...]:
                return (norm(e['relation']), norm(e['answer']),
                        norm(e['answer_meaning']),
                        norm(f"{e['relation']}{e['answer']}"))

            if a and not any(b in field_vals(e) for e in entries) \
                    and any(a in field_vals(e) for e in entries):
                stats['already'] += 1
                continue

            # --- "Xを取る" — strip a token out of the matched field -------
            m_strip = re.match(r'^(.+?)を取る$', a_clean)
            if m_strip:
                token = norm(m_strip.group(1))
                hit = False
                for e in entries:
                    # 'relation' deliberately excluded: it identifies the
                    # entry, and stripping it to '' orphans the row.
                    # 0030 apology lost its 自 that way.
                    for fld in ('answer', 'answer_meaning'):
                        val = e[fld] or ''
                        if token and token in norm(val):
                            # Remove the token, tidy the leftover spacing.
                            pat = re.escape(m_strip.group(1).strip())
                            new = re.sub(pat, '', val)
                            e[fld] = re.sub(r'\s{2,}', ' ', new).strip()
                            hit = touched = True
                            break
                    if hit:
                        break
                if hit:
                    stats['strip'] += 1
                else:
                    unresolved.append(
                        f'{wid}: STRIP target not found -> {b_raw!r} => {a_raw[:50]!r}')
                    stats['unresolved'] += 1
                continue

            # --- concatenated-row extend / shrink -------------------------
            # Once wrapped rows are rejoined, a row often reads as one entry's
            # fields run together:
            #     反 literacy 読み書きできること
            # and the "after" is the same text plus or minus a tail. That is
            # an ADD or a TRIM of a specific field rather than a replacement.
            ent, joined = _match_joined(entries, b)
            if ent is not None and a != b:
                if a.startswith(b):
                    tail = a_clean[len(_joined_raw(ent)):].strip() \
                        if a_clean.startswith(_joined_raw(ent)) else ''
                    if not tail:
                        tail = a_clean[len(b):].strip() if len(a_clean) > len(b) else ''
                    if tail:
                        if _starts_with_code(tail):
                            # A new sibling entry, e.g. 「+ 形 illiterate」.
                            parts = tail.split(None, 1)
                            entries.append({
                                'id': 0,
                                'word_id': wid,
                                'block': ent['block'],
                                'relation': parts[0],
                                'base_category': None,
                                'answer': parts[1] if len(parts) > 1 else '',
                                'answer_meaning': None,
                                'tts_enabled': True,
                                'notes': None,
                            })
                        elif (ent['answer_meaning'] or '').strip():
                            ent['answer_meaning'] = \
                                (ent['answer_meaning'] or '') + tail
                        else:
                            ent['answer_meaning'] = tail
                        stats['extend'] += 1
                        touched = True
                        continue
                elif b.startswith(a):
                    # The tail is being removed. Only trim a field that ENDS
                    # with it, so a partial word is never left behind.
                    cut = b[len(a):]
                    done = False
                    for fld in ('answer_meaning', 'answer', 'relation'):
                        val = ent[fld] or ''
                        if val and norm(val).endswith(cut):
                            keep = len(norm(val)) - len(cut)
                            if keep <= 0:
                                break
                            ent[fld] = _trim_to(val, keep)
                            done = True
                            break
                    if done:
                        stats['shrink'] += 1
                        touched = True
                        continue

            # --- never write an empty value ------------------------------
            # If cleaning stripped the "after" down to nothing, the
            # instruction was an annotation rather than replacement text.
            # Blanking real content is far worse than leaving it for review.
            if not a_clean:
                unresolved.append(
                    f'{wid}: empty replacement, skipped -> {b_raw!r} => {a_raw[:50]!r}')
                stats['unresolved'] += 1
                continue

            # --- locate the field the "before" text refers to -------------
            matched = False
            rel_hits = [e for e in entries if b == norm(e['relation'])]
            if rel_hits:
                # Pattern B: several entries can share one label. If every
                # instruction for this label asks for the SAME new label it is
                # a plain rename and applies to all of them (0100 abstain).
                # If they ask for DIFFERENT labels the docx is assigning them
                # positionally — 0181 respire wants 類 on breathe and
                # 類 の名詞 on breath — so consume one entry at a time.
                if len(distinct_after.get(b, ())) > 1:
                    target = next((e for e in rel_hits
                                   if id(e) not in claimed), None)
                    if target is not None:
                        target['relation'] = a_clean
                        claimed.add(id(target))
                        stats['relation'] += 1
                        matched = touched = True
                else:
                    for e in rel_hits:
                        e['relation'] = a_clean
                    stats['relation'] += 1
                    matched = touched = True
            for e in ([] if matched else entries):
                if b == norm(e['answer']):
                    e['answer'] = a_clean
                    stats['answer'] += 1
                    matched = touched = True
                    break
                if b == norm(e['answer_meaning']):
                    e['answer_meaning'] = a_clean
                    stats['meaning'] += 1
                    matched = touched = True
                    break
                # "反　literacy" — relation and answer written together.
                if b == norm(f"{e['relation']}{e['answer']}"):
                    parts = a_clean.split(None, 1)
                    if len(parts) == 2:
                        e['relation'], e['answer'] = parts[0], parts[1]
                        stats['relation'] += 1
                        matched = touched = True
                        break

            # --- relation prefix match ------------------------------------
            # The client writes the bare code (動) where the data carries a
            # qualified one (動（品）), and abbreviates 類義語とその名詞 to
            # 類とその名詞. Only applied when exactly one entry is a candidate,
            # so an ambiguous prefix is never guessed at.
            if not matched and len(b) <= 12:
                cands = [e for e in entries
                         if norm(e['relation']).startswith(b)
                         or b.startswith(norm(e['relation']))]
                # All candidates share one label, so renaming them together is
                # unambiguous; a split across DIFFERENT labels is not.
                if cands and len({norm(e['relation']) for e in cands}) == 1:
                    for e in cands:
                        e['relation'] = a_clean
                    stats['relation_prefix'] += 1
                    matched = touched = True

            if not matched:
                unresolved.append(
                    f'{wid}: no field matches -> {b_raw!r} => {a_raw[:60]!r}')
                stats['unresolved'] += 1

        if touched:
            overrides[str(wid)] = [
                {
                    'relation': e['relation'],
                    'answer': e['answer'],
                    'answer_meaning': e['answer_meaning'],
                    'tts_enabled': e['tts_enabled'],
                }
                for e in entries
            ]

    OUT_OVERRIDES.write_text(json.dumps({
        'schema_version': 1,
        'source': 'アプリ直し Second Stage 8. 20.docx (2026-08-19)',
        'note': 'Generated by apply_corrections_0820.py — review before merging '
                'into ss_overrides.json',
        'word_count': len(overrides),
        'overrides': overrides,
    }, ensure_ascii=False, indent=2), encoding='utf-8')

    OUT_UNRESOLVED.write_text('\n'.join(unresolved), encoding='utf-8')

    total = sum(stats.values())
    print(f'changes seen          : {total}')
    for k in ('delete', 'relation', 'relation_prefix', 'answer', 'meaning',
              'accent', 'strip', 'tts', 'extend', 'shrink'):
        print(f'  applied {k:9s}    : {stats[k]}')
    print(f'  already satisfied   : {stats["already"]}')
    print(f'  skipped (styling)   : {stats["skipped_style"]}')
    print(f'  UNRESOLVED          : {stats["unresolved"]}')
    print()
    applied = sum(stats[k] for k in ('delete', 'relation', 'relation_prefix',
                                     'answer', 'meaning', 'accent', 'strip', 'tts',
                                     'extend', 'shrink'))
    print(f'words with overrides  : {len(overrides)}')
    print(f'auto-applied          : {applied} / {total} '
          f'({applied / total * 100:.1f}%)')
    print(f'wrote {OUT_OVERRIDES.name} and {OUT_UNRESOLVED.name}')


if __name__ == '__main__':
    main()
