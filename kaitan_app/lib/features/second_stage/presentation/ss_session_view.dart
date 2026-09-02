// Second Stage question ⇄ answer views (⑥' / ⑦').
//
// Layout (v1.1 plan §2.4):
//   Question:
//     [top bar: 巡目・リタイヤ]
//     [headword] [🔊] [POS] [meaning]
//     - 【類】(prompt hidden until answer)
//     - 【形】(prompt hidden)
//     [大 意味・例文 button → answer]
//   Answer:
//     Same top bar (with word № on the top-left of the bar).
//     [headword] [POS] [meaning]
//     - 【類】variety
//     - 【形】diverse — 様々な
//     [OK]  [再チェック]
//
// The engine's queue holds HEADWORD ids. All SS entries anchored to the
// current headword are shown together on one screen — judgment is per-
// headword.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/second_stage.dart';
import '../../../data/word.dart';
import '../../session/domain/engine.dart';
import '../../session/presentation/session_controller.dart';

class SsQuestionView extends ConsumerWidget {
  final Word headword;
  final List<SecondStageEntry> entries;
  final SessionState session;
  final VoidCallback onTapAnswer;
  final VoidCallback onRetire;

  const SsQuestionView({
    super.key,
    required this.headword,
    required this.entries,
    required this.session,
    required this.onTapAnswer,
    required this.onRetire,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hideLine = _shouldHideHeadwordLine(entries, headword);
    return Column(
      children: [
        _SsTopBar(round: session.round, no: headword.id, onRetire: onRetire),
        _Headword(
          headword: headword,
          hideMeaning: hideLine,
          hidePos: hideLine,
          onSpeak: () => ref.read(ttsProvider).speak(
                headword.word,
                pronunciationHint: headword.pronunciationHint,
                wordId: headword.id,
              ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < entries.length; i++)
                  _EntryRow.hidden(
                    entry: entries[i],
                    showLabel: i == 0 ||
                        entries[i].relation != entries[i - 1].relation,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: SizedBox(
            width: double.infinity,
            height: 72,
            child: FilledButton(
              onPressed: onTapAnswer,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2b6cb0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('意味・答え',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
            ),
          ),
        ),
        _SsCounter(session: session),
      ],
    );
  }
}

class SsAnswerView extends ConsumerStatefulWidget {
  final Word headword;
  final List<SecondStageEntry> entries;
  final SessionState session;
  final VoidCallback onOk;
  final VoidCallback onRecheck;
  final VoidCallback onRetire;

  const SsAnswerView({
    super.key,
    required this.headword,
    required this.entries,
    required this.session,
    required this.onOk,
    required this.onRecheck,
    required this.onRetire,
  });

  @override
  ConsumerState<SsAnswerView> createState() => _SsAnswerViewState();
}

class _SsAnswerViewState extends ConsumerState<SsAnswerView> {
  bool _autoPlayed = false;

  @override
  void initState() {
    super.initState();
    // Auto-play the answer audio sequence once when the view mounts.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _autoPlayed) return;
      _autoPlayed = true;
      final speakable = widget.entries
          .where((e) => e.ttsEnabled && e.answer.trim().isNotEmpty)
          .map((e) => e.answer)
          .toList();
      if (speakable.isNotEmpty) {
        ref.read(ttsProvider).speakSequence(speakable);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final ref = this.ref;
    final headword = widget.headword;
    final entries = widget.entries;
    final session = widget.session;
    final hideMeaning = _shouldHideHeadwordLine(entries, headword);
    return Column(
      children: [
        _SsTopBar(round: session.round, no: headword.id, onRetire: widget.onRetire),
        // Spec 2026-08-12 #2: only one speaker per screen. The headword row
        // no longer shows a speaker on the answer view — the auto-played
        // answer TTS + per-entry inline speaker icons cover playback.
        _Headword(
          headword: headword,
          hideMeaning: hideMeaning,
          onSpeak: null,
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < entries.length; i++)
                  _EntryRow.revealed(
                    entry: entries[i],
                    showLabel: i == 0 ||
                        entries[i].relation != entries[i - 1].relation,
                    onSpeak: entries[i].ttsEnabled &&
                            entries[i].answer.isNotEmpty
                        ? () => ref.read(ttsProvider).speakAnswer(
                              entries[i].answer,
                              pronunciationHint: entries[i].pronunciationHint,
                            )
                        : null,
                  ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 72,
                  child: OutlinedButton(
                    onPressed: widget.onRecheck,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFD53F8C),
                      side: const BorderSide(
                          color: Color(0xFFD53F8C), width: 2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('再チェック',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 72,
                  child: FilledButton(
                    onPressed: widget.onOk,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF38A169),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('OK',
                        style: TextStyle(
                            fontSize: 22, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
            ],
          ),
        ),
        _SsCounter(session: session),
      ],
    );
  }
}

// ─── Common pieces ────────────────────────────────────────────────────

final RegExp _meaningCodePrefix =
    RegExp(r'^意\s*[０-９0-9]*\s*[（(]?\s*[０-９0-9]*\s*[）)]?');
final RegExp _startsLatin = RegExp(r'^[A-Za-z]');

/// True when the whole headword line (POS badge + meaning) must be hidden on
/// the question screen, because an SS entry is asking for exactly that
/// information and showing it would give the answer away.
///
/// Two triggers, both confirmed against the client's 2026-08-19 review, where
/// the instruction is written as e.g.「他　～を訪問する ⇨ トル」— the text being
/// deleted is precisely the headword's own POS + meaning:
///
///   • a 品 entry — the question IS "what part of speech is this?"
///     (0205 visit)
///   • an 意 entry that targets the headword itself, rather than a
///     look-alike word.
///
/// Distinguishing those 意 entries is the subtle part. `意 lark` on headword
/// `lurk` asks about a DIFFERENT word, so the headword line must stay visible
/// (0379 respectable / 0771 discreet / 2172 lurk). But `意３とそれぞれの前置詞`
/// and `意２～３` are Japanese qualifiers describing how many of the
/// HEADWORD's own meanings to give, so the line must be hidden
/// (0237 consist / 0570 degree / 0695 exhaust).
///
/// The reliable signal is whether the text after the 意 code is a Latin-script
/// word: only then is a different English word being asked about.
final _posThenOwnMeaning = RegExp(r'^[他自名形副動前接間]\s*の意味');

bool _shouldHideHeadwordLine(
    List<SecondStageEntry> entries, Word headword) {
  for (final e in entries) {
    // A question can ask for the headword's meaning without using the 意 code
    // at all: 0916 tear carries 他の意味 and 名 の意味と発音, both of which
    // want tear's own meaning, so leaving the headword line up hands over the
    // answer (client 2026-08-26 ①).
    //
    // The POS code must be followed directly by の意味. That is what separates
    // it from 副詞とその意味, which asks for a DERIVED word and its meaning,
    // and from 副詞 fairly の意味, which asks about a different word entirely —
    // in both of those the headword line gives nothing away and must stay.
    if (_posThenOwnMeaning.hasMatch(e.relation.trim())) return true;
    if (e.baseCategory == SsRelationCategory.posMarker) return true;
    if (e.baseCategory != SsRelationCategory.meaning) continue;
    final rest =
        e.relation.trim().replaceFirst(_meaningCodePrefix, '').trim();
    if (rest.isEmpty) return true; // bare 意 / 意２ → asks the headword
    if (rest.toLowerCase() == headword.word.trim().toLowerCase()) return true;
    if (_startsLatin.hasMatch(rest)) continue; // a different English word
    return true; // Japanese qualifier → still about the headword
  }
  return false;
}


class _SsTopBar extends StatelessWidget {
  final int round;
  final int no;
  final VoidCallback onRetire;
  const _SsTopBar(
      {required this.round, required this.no, required this.onRetire});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: [
          SizedBox(
            width: 84,
            child: Text('№ ${no.toString().padLeft(4, "0")}',
                style: const TextStyle(fontSize: 12, color: Colors.black54)),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F4FF),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text('$round巡目',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2b6cb0))),
          ),
          const Spacer(),
          SizedBox(
            width: 84,
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: onRetire,
                style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
                child: const Text('リタイヤ',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Headword extends StatelessWidget {
  final Word headword;
  final bool hideMeaning;
  final bool hidePos;
  final VoidCallback? onSpeak;
  const _Headword({
    required this.headword,
    required this.onSpeak,
    this.hideMeaning = false,
    this.hidePos = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      child: Column(
        children: [
          Text(
            headword.word,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 36,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2b6cb0),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (!hidePos) _MiniPosBadge(headword.posRaw),
              if (!hideMeaning) ...[
                const SizedBox(width: 10),
                Flexible(
                  child: Text(
                    headword.meanings.join('、'),
                    style:
                        const TextStyle(fontSize: 16, color: Colors.black87),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
              if (onSpeak != null) ...[
                const SizedBox(width: 10),
                IconButton(
                  onPressed: onSpeak,
                  icon: const Icon(Icons.volume_up_rounded),
                  color: const Color(0xFF2b6cb0),
                  iconSize: 26,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

/// Counter chip (残/OK/再チェック) matched to the First Stage bottom counter.
/// Client 2026-08-12 #1: SS needs the same live counter as FS.
class _SsCounter extends StatelessWidget {
  final SessionState session;
  const _SsCounter({required this.session});
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFC),
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _chip('残/総数', '${session.remaining}/${session.total}'),
          _chip('OK', '${session.ok}', color: const Color(0xFF38A169)),
          _chip('再チェック', '${session.recheck}',
              color: const Color(0xFFD53F8C)),
        ],
      ),
    );
  }

  Widget _chip(String label, String value, {Color? color}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style:
                  const TextStyle(fontSize: 10, color: Colors.black54)),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color ?? Colors.black87)),
        ],
      );
}

class _MiniPosBadge extends StatelessWidget {
  final String pos;
  const _MiniPosBadge(this.pos);
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFFEDF2F7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(pos,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Color(0xFF2b6cb0))),
    );
  }
}

class _EntryRow extends StatelessWidget {
  final SecondStageEntry entry;
  final bool showAnswer;
  final VoidCallback? onSpeak;
  /// False when this row repeats the label of the row above it. The client
  /// asked for the duplicate to go on 0341 act and 1275 industry, and it is
  /// the same shape 109 times across 86 words: one question, several answers,
  /// the label restated on each. Printing it once reads as the one question
  /// it is.
  final bool showLabel;
  const _EntryRow.hidden({required this.entry, this.showLabel = true})
      : showAnswer = false,
        onSpeak = null;
  const _EntryRow.revealed(
      {required this.entry, this.onSpeak, this.showLabel = true})
      : showAnswer = true;

  @override
  Widget build(BuildContext context) {
    final cat = SsRelationCategory.categoryOf(entry.relation);
    final rest = _promptRest(entry.relation, cat);
    // Free-form long prompts (rest != null && length > 3) span the full
    // width beneath the chip — 0015 encourage / 0006 apparent / 0036
    // literature all fall in this bucket.
    final wide = rest != null && rest.length > 3;

    if (wide) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _CategoryChip(
                    cat: cat,
                    label: cat ?? entry.relation,
                    visible: showLabel),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    showLabel ? rest : '',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Colors.black87,
                      height: 1.25,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _answerOrPlaceholder(context),
          ],
        ),
      );
    }
    // Compact row: chip + answer/placeholder side-by-side.
    // NOTE: the speaker icon lives INSIDE _answerOrPlaceholder — do not add
    // a second one here (client 2026-08-12 #2: only one speaker per row).
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _CategoryChip(cat: cat, label: cat ?? entry.relation),
          const SizedBox(width: 12),
          Expanded(child: _answerOrPlaceholder(context)),
        ],
      ),
    );
  }

  Widget _answerOrPlaceholder(BuildContext context) {
    if (!showAnswer) {
      return Container(
        height: 48,
        decoration: BoxDecoration(
          color: const Color(0xFFF7FAFC),
          border: Border.all(color: const Color(0xFFCBD5E0), width: 1),
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: const Text('？',
            style: TextStyle(
                fontSize: 24,
                color: Colors.black38,
                fontWeight: FontWeight.w700)),
      );
    }
    final cat = SsRelationCategory.categoryOf(entry.relation);
    final rest = _promptRest(entry.relation, cat);
    // Pattern A (client 2026-08-12 #3): when the prompt "rest" is the exact
    // English word being asked for its meaning (e.g. `意 literally` and the
    // SS answer is also `literally`), the answer word would repeat. Hide the
    // red answer text and let the meaning text stand alone in red.
    final hideAnswerText = rest != null &&
        entry.answer.trim().toLowerCase() == rest.trim().toLowerCase();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!hideAnswerText)
                // Client 2026-08-19: multi-sense answers such as
                // 「名 物体、対象、目的（語）　自 反対する」 must break onto one
                // line per part of speech. The same rule the meaning field
                // already used now applies to the answer text as well.
                Text(
                  _breakForReading(entry.answer),
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFC53030),
                    height: 1.25,
                  ),
                ),
              if ((entry.answerMeaning ?? '').isNotEmpty)
                Padding(
                  padding:
                      EdgeInsets.only(top: hideAnswerText ? 0 : 2),
                  child: Text.rich(
                    _mnemonicSpans(
                      _breakForReading(entry.answerMeaning!,
                          breakBeforeQuote: entry.mnemonicEcho.isNotEmpty ||
                              entry.mnemonicBreak),
                      echo: entry.mnemonicEcho,
                      asMnemonic: entry.mnemonicBreak,
                      base: TextStyle(
                        // ゴチ — the meaning itself keeps the gothic face it
                        // has always had (client 2026-08-24 ①②). Only part of
                        // a 「…」 mnemonic turns mincho; see _mnemonicSpans.
                        fontFamily: 'sans-serif',
                        fontSize: hideAnswerText ? 22 : 15,
                        fontWeight: hideAnswerText
                            ? FontWeight.w800
                            : FontWeight.w400,
                        color: hideAnswerText
                            ? const Color(0xFFC53030)
                            : Colors.black87,
                        height: 1.35,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        if (onSpeak != null)
          IconButton(
            onPressed: onSpeak,
            icon: const Icon(Icons.volume_up_outlined),
            iconSize: 22,
            color: const Color(0xFF2b6cb0),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          ),
      ],
    );
  }

  /// Pattern C: insert visual line breaks in a long answer/meaning line.
  ///
  ///   • before ` cf. ` — a "compare" phrase deserves its own line
  ///   • before Japanese POS markers 名/他/自/形/副/動/前/接 when they are
  ///     used as prefix labels for multiple sub-meanings within one line
  ///     (e.g. `形 卑しい、意地悪な 名 中間、平均 他 意味する` → 3 lines)
  static String _breakForReading(String s, {bool breakBeforeQuote = false}) {
    // Break at cf. (both `cf.` and ` cf `)
    var out = s.replaceAll(RegExp(r'\s*cf\.\s*'), '\ncf. ');
    // Break at POS markers that follow whitespace: preserve the marker.
    out = out.replaceAllMapped(
      RegExp(r'\s+([他自名形副動前接])\s'),
      (m) => '\n${m.group(1)} ',
    );
    // A ゴロ starts its own line (client 2026-08-26 ④) — but ONLY a ゴロ.
    // Not every 「…」 is one: 1269 revenge carries oneself「= 自分がやられた
    // こと」を返す and 1761 anxious carries anxious は「やきもき」for は
    // 「求めて」, and for both the client asked for 「１行に」 — one line. They
    // are grammar notes with the quotes mid-sentence, and breaking there would
    // scatter one thought over three lines.
    //
    // mnemonicEcho already distinguishes the two: it is recorded only for a
    // real ゴロ, so the caller passes it through here rather than this trying
    // to tell them apart from the text.
    if (breakBeforeQuote) {
      out = out.replaceAllMapped(
        RegExp(r'([^\n\s])\s*(?=「)'),
        (m) => '${m.group(1)}\n',
      );
    }
    return out.trim();
  }

  /// Style a meaning line, splitting any 「…」 mnemonic three ways.
  ///
  /// Client 2026-08-24 ③, replacing the 08-19 rule. Taking 0007 opaque,
  /// whose meaning reads 不透明な「OPECは不透明」:
  ///
  ///   不透明な   the meaning        → ゴチ, normal   (unchanged from before)
  ///   OPEC       echoes the English → ゴチ, bold
  ///   「…は不透明」the rest of the ゴロ → 明朝
  ///
  /// The earlier rule had this inverted — it set the whole mnemonic in gothic
  /// bold and the meaning in mincho, which is why rows with no correction at
  /// all still changed appearance.
  ///
  /// [echo] carries the runs that echo the English word. It has to be
  /// recorded per entry: the echo is a pun on the sound, and it may be
  /// written in Latin (OPEC/opaque), katakana (プリーズ/priest) or plain
  /// kanji (政治/sage), so no rule over the characters can find it.
  ///
  /// With no echo recorded the line stays entirely gothic — its appearance
  /// before any of this. That default matters: not every 「…」 is a ゴロ. Many
  /// are grammar notes quoting Japanese (「賛成する」は自動詞), and the client
  /// asked for mincho only inside 意味の覚え方. Leaving an entry unmarked is
  /// therefore always safe, never a half-applied rule.
  static final RegExp _quoteRe = RegExp(r'「[^」]*」');

  static InlineSpan _mnemonicSpans(String text,
      {required TextStyle base,
      List<String> echo = const [],
      bool asMnemonic = false}) {
    // No echo AND not flagged means the 「…」 is a grammar note, which keeps
    // the surrounding style. Flagged with no echo means a ゴロ with nothing to
    // emphasise inside it — the whole quote goes mincho.
    if (echo.isEmpty && !asMnemonic) return TextSpan(text: text, style: base);
    // Client 2026-08-26 ③: a ゴロ is 「基本的に黒字で、小さいフォント」. That
    // applies to the whole quoted run — the echoing part included — so it is
    // set on the shared style here and the face/weight split happens below.
    // (These two attributes were in the 08-19 build and I dropped them when
    // rewriting for the 08-24 mincho rule.)
    final quoted = base.copyWith(
      color: Colors.black,
      fontSize: (base.fontSize ?? 15) - 2,
    );
    final mincho = quoted.copyWith(fontFamily: 'serif');
    final echoStyle = quoted.copyWith(fontWeight: FontWeight.w900);

    final children = <InlineSpan>[];
    var cursor = 0;
    for (final q in _quoteRe.allMatches(text)) {
      if (q.start > cursor) {
        children.add(
            TextSpan(text: text.substring(cursor, q.start), style: base));
      }
      children.addAll(_insideQuote(text.substring(q.start, q.end),
          mincho: mincho, echoStyle: echoStyle, echo: echo));
      cursor = q.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: base));
    }
    if (children.isEmpty) return TextSpan(text: text, style: base);
    return TextSpan(children: children);
  }

  /// One 「…」 run: mincho throughout, except the echoing parts.
  static List<InlineSpan> _insideQuote(String quoted,
      {required TextStyle mincho,
      required TextStyle echoStyle,
      required List<String> echo}) {
    // Collect the ranges to emphasise, longest first so that a short echo
    // that happens to be a substring of a longer one cannot split it.
    final hits = <List<int>>[];
    final needles = [...echo]..sort((a, b) => b.length.compareTo(a.length));
    for (final n in needles) {
      if (n.isEmpty) continue;
      var from = 0;
      while (true) {
        final i = quoted.indexOf(n, from);
        if (i < 0) break;
        if (!hits.any((h) => i < h[1] && h[0] < i + n.length)) {
          hits.add([i, i + n.length]);
        }
        from = i + n.length;
      }
    }
    hits.sort((a, b) => a[0].compareTo(b[0]));

    final out = <InlineSpan>[];
    var cursor = 0;
    for (final h in hits) {
      if (h[0] > cursor) {
        out.add(TextSpan(text: quoted.substring(cursor, h[0]), style: mincho));
      }
      out.add(TextSpan(
          text: quoted.substring(h[0], h[1]), style: echoStyle));
      cursor = h[1];
    }
    if (cursor < quoted.length) {
      out.add(TextSpan(text: quoted.substring(cursor), style: mincho));
    }
    return out;
  }

  /// Strip the base code from the front of the relation string, along with
  /// any compound-form suffix. Client 2026-08-12 #8: `副詞とその意味` →
  /// chip "副" + prompt "とその意味". Additionally catches common
  /// Japanese-grammar compounds where the base code is a semantic root:
  ///   類 + 義語 (synonym), 反 + 対語 (antonym), 同音 + 異義語 (homophone).
  static const _compoundSuffixesByCode = <String, List<String>>{
    '副': ['詞'],
    '意': ['味'],
    '名': ['詞'],
    '形': ['容詞'],
    '動': ['詞'],
    '類': ['義語', '義'],
    '反': ['対語', '対'],
    '同音': ['異義語', '異義'],
  };
  static String? _promptRest(String relation, String? cat) {
    if (cat == null || relation == cat) return null;
    var rest = relation.substring(cat.length);
    for (final suffix in _compoundSuffixesByCode[cat] ?? const <String>[]) {
      if (rest.startsWith(suffix)) {
        rest = rest.substring(suffix.length);
        break;
      }
    }
    rest = rest.trim();
    return rest.isEmpty ? null : rest;
  }
}

class _CategoryChip extends StatelessWidget {
  final String? cat;
  final String label;
  /// When false the chip still occupies its slot but draws nothing, so the
  /// answers of a multi-row question stay aligned under the one label.
  final bool visible;
  const _CategoryChip(
      {required this.cat, required this.label, this.visible = true});
  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox(width: 44);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: _chipColor(cat),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          height: 1.0,
        ),
      ),
    );
  }

  Color _chipColor(String? cat) {
    switch (cat) {
      case SsRelationCategory.synonym:
      case SsRelationCategory.adjForm:
      case SsRelationCategory.nounForm:
      case SsRelationCategory.advForm:
      case SsRelationCategory.verbForm:
        return const Color(0xFF3182CE);
      case SsRelationCategory.antonym:
        return const Color(0xFFDD6B20);
      case SsRelationCategory.setPhrase:
      case SsRelationCategory.idiom:
      case SsRelationCategory.preposition:
        return const Color(0xFF805AD5);
      case SsRelationCategory.conjugation:
      case SsRelationCategory.posMarker:
      case SsRelationCategory.usage:
      case SsRelationCategory.plural:
      case SsRelationCategory.homophone:
        return const Color(0xFF38A169);
      case SsRelationCategory.meaning:
        return const Color(0xFFD53F8C);
      default:
        return const Color(0xFF718096);
    }
  }
}
