"""
Apply the 2026-08-19 review's RELATION-LABEL renames.

A large share of that review relabels only the code at the head of a row —
「類義語とその名詞 ⇨ 類 の名詞」 — leaving the row's English and Japanese alone.
Three things stop a naive matcher from seeing these:

  1. The docx abbreviates. It writes 類 where the data stores 類義語, 名 for
     名詞, 他 for 他動詞. So we compare on a canonical form that shortens the
     leading code.
  2. The two-column layout wraps, so ONE rename arrives as two partial rows
     (「類とその名詞 ⇨ 類」 then 「類とそ ⇨ 類 の名詞」). Neither is complete.
  3. Sibling rows share one label but need DIFFERENT new labels — 0181 breathe
     becomes 類 while its noun breath becomes 類 の名詞. Renaming every match
     to one value would corrupt the pair.

So instead of trusting any single row, we collect the distinct new labels the
client gives for a label, in document order, and assign them positionally to
the entries carrying that label, in the same order. When the counts do not
line up we write nothing and leave the change for a human.

Run AFTER apply_ss_overrides.py; merge the output into ss_overrides.json.
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
OUT = HERE / 'ss_overrides_rel.json'

# A label carries no Latin letters — that is what keeps English content from
# ever being mistaken for one.
LABEL_RE = re.compile(r'^[^A-Za-z]{1,24}$')
# Long forms the docx writes in short. Leading position only: 「名詞とその複数形」
# shortens to 「名とその複数形」, but the trailing 複数形 must stay intact.
LONG_TO_SHORT = [('類義語', '類'), ('反意語', '反'), ('反対語', '反'), ('名詞', '名'),
                 ('形容詞', '形'), ('副詞', '副'), ('他動詞', '他'),
                 ('自動詞', '自'), ('動詞', '動')]
STYLE_WORDS = ('明朝', 'ゴチ', '太', 'ふつう', '小さい字', '黒', '音声追加',
               '解答も', '問題も', 'スペルミス', 'スペリングミス', 'アクセント',
               'これを追加', '私のミス', 'つけたまま', 'トル', 'カット', '↳', '↱')


def norm(s: str | None) -> str:
    if not s:
        return ''
    return re.sub(r'\s+', '', unicodedata.normalize('NFKC', s))


def canon(rel: str) -> str:
    """Normalized label with its LEADING long form shortened."""
    n = norm(rel)
    for long, short in LONG_TO_SHORT:
        if n.startswith(long):
            return short + n[len(long):]
    return n


def raw_head(raw: str, n: int) -> str:
    """The prefix of `raw` whose normalized length is `n`, spacing intact."""
    out = ''
    for ch in raw:
        if len(norm(out)) >= n:
            break
        out += ch
    return out.strip()


def main() -> None:
    corr = json.loads(CORRECTIONS.read_text(encoding='utf-8'))
    ss = json.loads(SS.read_text(encoding='utf-8'))

    by_word: dict[int, list[dict]] = {}
    for e in ss['entries']:
        by_word.setdefault(e['word_id'], []).append(dict(e))

    changes: dict[int, list[dict]] = {}
    for r in corr['records']:
        changes.setdefault(r['word_id'], []).extend(r['changes'])

    overrides: dict[str, list[dict]] = {}
    renamed = ambiguous = 0

    for wid in sorted(changes):
        entries = by_word.get(wid)
        if not entries:
            continue

        # old label -> new labels, in document order, de-duplicated.
        proposals: dict[str, list[str]] = {}
        for ch in changes[wid]:
            b_raw, a_raw = ch['before'], ch['after']
            if any(w in a_raw for w in STYLE_WORDS):
                continue
            b, a = norm(b_raw), norm(a_raw)
            # Both sides must be pure labels for this to be a label rename.
            if not b or not a or b == a:
                continue
            if LABEL_RE.match(b) and LABEL_RE.match(a):
                old_key, new_raw = canon(b_raw), a_raw.strip()
            else:
                # The row is written label+content on both sides. Only the head
                # differs, so the two share a tail; split there and keep the
                # heads. A tail is required — without one this is a content
                # edit, not a relabel, and belongs to the other pass.
                tail = 0
                while (tail < min(len(b), len(a))
                       and b[-1 - tail] == a[-1 - tail]):
                    tail += 1
                if tail == 0:
                    continue
                b_head, a_head = b[:len(b) - tail], a[:len(a) - tail]
                if not a_head or not LABEL_RE.match(a_head):
                    continue
                if not b_head or not LABEL_RE.match(b_head):
                    continue
                old_key, new_raw = canon(b_head), raw_head(a_raw, len(a_head))
            lst = proposals.setdefault(old_key, [])
            if new_raw and norm(new_raw) not in {norm(x) for x in lst}:
                lst.append(new_raw)

        touched = False
        for old, news in proposals.items():
            hits = [e for e in entries if canon(e['relation']) == old]
            if not hits:
                continue
            if len(news) == 1:
                for e in hits:
                    e['relation'] = news[0]
                renamed += len(hits)
                touched = True
            elif len(news) == len(hits):
                # Siblings needing different labels — assign in order.
                for e, new in zip(hits, news):
                    e['relation'] = new
                renamed += len(hits)
                touched = True
            else:
                ambiguous += 1

        if touched:
            overrides[str(wid)] = [
                {'relation': e['relation'], 'answer': e['answer'],
                 'answer_meaning': e['answer_meaning'],
                 'tts_enabled': e['tts_enabled']}
                for e in entries]

    OUT.write_text(json.dumps(
        {'schema_version': 1,
         'source': 'アプリ直し Second Stage 8. 20.docx — relation renames',
         'overrides': overrides}, ensure_ascii=False, indent=2),
        encoding='utf-8')
    print(f'relations renamed : {renamed}')
    print(f'ambiguous, skipped: {ambiguous}')
    print(f'words affected    : {len(overrides)}')


if __name__ == '__main__':
    main()
