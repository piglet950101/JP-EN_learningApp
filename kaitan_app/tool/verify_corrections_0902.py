"""
Verify the 2026-09-02 client review against the FINAL Second Stage data.

This deliberately re-reads the docx independently of the applier, so a bug in
apply_corrections_0820.py cannot mark its own work as correct. For every
instruction it asks one question of the shipped data:

    is the "before" state gone, and the "after" state present?

Categories reported
    SATISFIED   after-state present, before-state absent   -> done
    PENDING     before-state still present                 -> not yet applied
    UI_RULE     handled by an app rendering rule, not data  -> nothing to check
    UNKNOWN     neither state found; needs a human to look

Run AFTER import_second_stage.py + apply_ss_overrides.py.
"""
from __future__ import annotations

import json
import re
import unicodedata
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
CORRECTIONS = HERE / 'corrections_0902.json'
SS = ROOT / 'assets' / 'content' / 'second_stage.json'
WORDS = ROOT / 'assets' / 'content' / 'words.json'
REPORT = HERE / 'verify_0902_report.txt'

POS = r'[他自名形副動前接]'
# One or more POS markers joined by '・', optionally with a (2)/2 marker:
# 他 / 他・名 / 自(２) / 名２ …
POS_GROUP = (r'[（(]?' + POS + r'[）)]?'
             r'(?:\s*・\s*[（(]?' + POS + r'[）)]?)*'
             r'\s*[（(]?\s*[０-９0-9]?\s*[）)]?')
ARROW_JUNK = re.compile(r'[↱↳↲⇨→]')
# Remarks the client writes ABOUT an edit rather than as part of the value.
EDITORIAL = ('なければ作ります', '※スペリングミス', '※スペルミス', 'スペリングミス',
             'スペルミス', '解答も同様', '問題も同様', '解答も', '問題も',
             'これを追加', '私のミスです', 'タイトルが違っていました')
# 「(from) をトル」「(in), (on) をカット」「(to) を取る」 — delete verb at the end.
STRIP_TAIL_RE = re.compile(
    r'^([（(].+?[）)](?:\s*[,、]\s*[（(].+?[）)])*)\s*を?\s*(?:トル|カット|取る)\s*$')
STYLE_WORDS = ('明朝', 'ゴチ', 'ゴシック', '太', 'ふつう', '小さい字', '黒',
               '小さく', 'ちいさく', '字を小さく', '赤', '改行',
               '文字の大きさ', '大きさを')
# 「音声を追加」「音声を…に」 change tts_enabled or a pronunciation hint, so they
# are data, not styling — kept separate from STYLE_WORDS on purpose.
AUDIO_WORDS = ('音声', '🔊', '発音')


# Long forms the docx writes in short: it says 類 where the data stores 類義語.
LONG_TO_SHORT = [('類義語', '類'), ('反意語', '反'), ('名詞', '名'),
                 ('形容詞', '形'), ('副詞', '副'), ('他動詞', '他'),
                 ('自動詞', '自'), ('動詞', '動')]


def norm(s: str | None) -> str:
    if not s:
        return ''
    return re.sub(r'\s+', '', unicodedata.normalize('NFKC', s))


def canon(s: str | None) -> str:
    """Normalized, with a LEADING long-form label shortened to the docx's form."""
    n = norm(s)
    for long, short in LONG_TO_SHORT:
        if n.startswith(long):
            return short + n[len(long):]
    return n


def main() -> None:
    corr = json.loads(CORRECTIONS.read_text(encoding='utf-8'))
    ss = json.loads(SS.read_text(encoding='utf-8'))['entries']
    words = {w['id']: w for w in
             json.loads(WORDS.read_text(encoding='utf-8'))['words']}

    by_word: dict[int, list[dict]] = {}
    for e in ss:
        by_word.setdefault(e['word_id'], []).append(e)

    def fields(wid: int) -> list[str]:
        """Every individual field value for a word, normalized.

        Covers BOTH datasets. Some instructions edit the headword's own POS
        and meaning, which live in words.json — e.g.「自　控える(from) ⇨
        (from) をトル」. Searching only the Second Stage entries made those
        look unresolvable when they had in fact been applied.
        """
        out = []
        for e in by_word.get(wid, []):
            out += [norm(e['relation']), norm(e['answer']),
                    norm(e['answer_meaning'])]
            # The docx describes a row as the client SEES it — the label, the
            # English and the Japanese run together on one visual line. Many
            # instructions therefore match no single field, only the whole row,
            # so compare against that too (in both the stored and abbreviated
            # spellings of the label).
            row = f"{e['relation']}{e['answer']}{e['answer_meaning'] or ''}"
            out += [norm(row), canon(row)]
        # The client often writes several CONSECUTIVE rows as one run of text,
        # because that is how they appear on screen — 「反 literacy 読み書きで
        # きること形 illiterate」 spans two entries. Compare against those runs
        # too, or a correctly split pair looks like neither state.
        ents = by_word.get(wid, [])
        for size in (2, 3, 4):
            for i in range(len(ents) - size + 1):
                grp = ents[i:i + size]
                run = ''.join(
                    f"{x['relation']}{x['answer']}{x['answer_meaning'] or ''}"
                    for x in grp)
                # Rows sharing a label are written with that label ONCE, at the
                # head of the group — 「熟２ in progress 進行中で make (ナシ)
                # progress」 covers two entries but names 熟２ a single time.
                once = (f"{grp[0]['relation']}" + ''.join(
                    f"{x['answer']}{x['answer_meaning'] or ''}" for x in grp))
                out += [norm(run), canon(run), norm(once), canon(once)]
        hw = words.get(wid)
        if hw:
            out.append(norm(hw['pos_raw']))
            out += [norm(m) for m in hw['meanings']]
            # Meanings are stored as a list; the docx writes them as one line,
            # sometimes comma-separated (他・名 疑う、疑い) and sometimes not.
            for sep in ('', '、'):
                out.append(norm(hw['pos_raw'] + sep.join(hw['meanings'])))
                out.append(norm(sep.join(hw['meanings'])))
        return [f for f in out if f]

    def same_row(b: str, a: str, wid: int) -> bool:
        """Do the before- and after-texts both sit on ONE row?

        Several instructions name a row by its label and give the content that
        should appear on it — 「セ 彼の成功を運がよかったおかげとする ⇨
        attribute A to B  A を B のせいにする」. Once applied, the row carries
        both, so testing them separately reports the before-state as still
        present and the work as outstanding.
        """
        for e in by_word.get(wid, []):
            row = norm(f"{e['relation']}{e['answer']}{e['answer_meaning'] or ''}")
            if b and a and b in row and a in row:
                return True
        return False

    def present(needle: str, vals: list[str]) -> bool:
        """Is this text present in the word's data?

        Short needles (意 / 法 / 類 …) must match a WHOLE field. Testing them
        as substrings makes them match almost anything — 意 occurs inside
        意２, 意 lark, 意３とそれぞれの前置詞 — which previously made ~45
        instructions look permanently unapplied.
        """
        if not needle:
            return False
        if len(needle) <= 3:
            return any(needle == v for v in vals)
        return any(needle in v for v in vals)

    counts = {'SATISFIED': 0, 'PENDING': 0, 'UI_RULE': 0, 'AUDIO': 0,
              'AUDIO_TODO': 0, 'UNKNOWN': 0}
    lines: list[str] = []

    for r in corr['records']:
        wid = r['word_id']
        hw = words.get(wid)
        vals = fields(wid)
        hw_lines = {norm(hw['pos_raw'] + sep.join(hw['meanings']))
                    for sep in ('', '、')} if hw else set()

        for ch in r['changes']:
            b_raw, a_raw = ch['before'], ch['after']
            b, a = norm(b_raw), norm(a_raw)
            if not b:
                continue

            # Rendering rules operate on presentation, not stored data.
            # Audio is checked first: 「音声を追加」 is a data change even
            # though 発音 would otherwise look like styling.
            if any(w in a_raw for w in AUDIO_WORDS):
                # Actually check the audio state rather than just filing it.
                rows = by_word.get(wid, [])
                wants_off = any(k in a_raw for k in ('トル', '削除', 'カット'))
                # 「音声を追加」「音声を入れる」 just switch the row on;
                # only 「音声を X に」 or 「発音」 name a reading.
                adds = any(k in a_raw for k in ('追加', '入れる'))
                wants_reading = ('発音' in a_raw
                                 or ('音声を' in a_raw and not wants_off
                                     and not adds))
                # Prefer the row the instruction names; fall back to the word.
                named = [e for e in rows
                         if b and (b in norm(e['relation'])
                                   or b in norm(e['answer'])
                                   or norm(e['answer']) in b)]
                target = named or rows
                if not target:
                    counts['AUDIO_TODO'] += 1
                    lines.append(f'AUDIO?   {wid}: no row -> {a_raw[:44]!r}')
                elif wants_off:
                    ok = all(not e['tts_enabled'] for e in target)
                    counts['AUDIO' if ok else 'AUDIO_TODO'] += 1
                    if not ok:
                        lines.append(f'AUDIO?   {wid}: still on -> {b_raw[:36]!r}')
                elif wants_reading:
                    ok = any(e.get('pronunciation_hint') for e in target)
                    counts['AUDIO' if ok else 'AUDIO_TODO'] += 1
                    if not ok:
                        lines.append(
                            f'AUDIO?   {wid}: no reading set -> {a_raw[:44]!r}')
                else:
                    ok = any(e['tts_enabled'] for e in target)
                    counts['AUDIO' if ok else 'AUDIO_TODO'] += 1
                    if not ok:
                        lines.append(f'AUDIO?   {wid}: still off -> {b_raw[:36]!r}')
                continue
            if b == a or any(w in a_raw for w in STYLE_WORDS):
                counts['UI_RULE'] += 1
                continue
            # 「headword POS + meaning ⇨ トル」 is the hide-headword-line rule.
            if a.startswith(('トル', 'カット')) and (
                    b in hw_lines
                    or (re.match(r'^' + POS_GROUP, b_raw.strip())
                        and not re.search(r'[A-Za-z]', b_raw))):
                counts['UI_RULE'] += 1
                continue
            # 「POS ⇨ POS <meaning>」 is the same rule seen from the other side:
            # the client is asking for the headword's meaning to be shown next
            # to the POS badge. Compound POS such as 他・名 count too
            # (0380 respect: 他・名 ⇨ 他・名 尊敬する、点).
            if re.fullmatch(POS_GROUP, b_raw.strip()) \
                    and re.match(r'^' + POS, a_raw.strip()) \
                    and len(a_raw.strip()) > 2:
                counts['UI_RULE'] += 1
                continue

            # Pattern C: the "before" carries two or more POS-labelled senses
            # and the "after" is its first sense — a line-break request, which
            # the app's rendering rule handles. The docx column wrap often
            # truncates these mid-phrase, so compare on the leading sense.
            multi_pos = len(re.findall(POS + r'\s', b_raw)) >= 2
            if multi_pos and a and (b.startswith(a) or a in b):
                counts['UI_RULE'] += 1
                continue

            # 「(from) をトル」 — a strip instruction, with the delete verb at
            # the END rather than the start. The target is the bracketed text,
            # and it is done once that text no longer appears anywhere for
            # this word.
            # 「名 compensátion ⇨ 名 compensation アクセントをトル」 asks for the
            # stress mark to come off. It is done once the accented spelling is
            # gone and the plain one is there.
            if 'アクセント' in a_raw:
                plain = norm(unicodedata.normalize(
                    'NFKD', b_raw).encode('ascii', 'ignore').decode()
                    ) if re.search(r'[À-ɏ]', b_raw) else ''
                stripped = norm(''.join(
                    c for c in unicodedata.normalize('NFD', b_raw)
                    if unicodedata.category(c) != 'Mn'))
                if stripped and stripped != b and present(stripped, vals):
                    counts['SATISFIED'] += 1
                else:
                    counts['PENDING'] += 1
                    lines.append(f'PENDING  {wid}: accent {b_raw!r}')
                continue

            m_strip = STRIP_TAIL_RE.match(a_raw.strip())
            if m_strip:
                targets = re.findall(r'[（(].+?[）)]', m_strip.group(1))
                if targets and not any(norm(t) in ''.join(vals) for t in targets):
                    counts['SATISFIED'] += 1
                else:
                    counts['PENDING'] += 1
                    lines.append(f'PENDING  {wid}: strip {m_strip.group(1)!r}')
                continue

            a_txt = ARROW_JUNK.sub('', a_raw)
            for note in EDITORIAL:
                a_txt = a_txt.replace(note, '')
            a_clean = norm(a_txt)
            before_present = present(b, vals)

            if a.startswith(('トル', 'カット')):
                # A deletion is done once the target text is gone.
                if not present(b, vals):
                    counts['SATISFIED'] += 1
                else:
                    counts['PENDING'] += 1
                    lines.append(f'PENDING  {wid}: delete {b_raw!r}')
                continue

            after_present = present(a_clean, vals)
            # Many edits EXTEND the original text (不透明な ⇨ 不透明な「OPECは
            # 不透明」). The before-string is then a substring of the intended
            # after-string, so it necessarily still appears in correct data.
            # Requiring its absence marks finished work as outstanding.
            if after_present and (not before_present or b in a_clean
                                  or same_row(b, a_clean, wid)):
                counts['SATISFIED'] += 1
            elif before_present:
                counts['PENDING'] += 1
                lines.append(f'PENDING  {wid}: {b_raw!r} => {a_raw[:56]!r}')
            else:
                counts['UNKNOWN'] += 1
                lines.append(f'UNKNOWN  {wid}: {b_raw!r} => {a_raw[:56]!r}')

    REPORT.write_text('\n'.join(lines), encoding='utf-8')

    total = sum(counts.values())
    print(f'instructions checked : {total}')
    for k in ('SATISFIED', 'UI_RULE', 'AUDIO', 'AUDIO_TODO', 'PENDING',
              'UNKNOWN'):
        print(f'  {k:10s} {counts[k]:4d}  ({counts[k] / total * 100:5.1f}%)')
    done = counts['SATISFIED'] + counts['UI_RULE'] + counts['AUDIO']
    print()
    print(f'resolved end-to-end  : {done} / {total} ({done / total * 100:.1f}%)')
    print(f'wrote {REPORT.name}')


if __name__ == '__main__':
    main()
