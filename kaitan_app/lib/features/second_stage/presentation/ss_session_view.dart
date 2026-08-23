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
                for (final e in entries) _EntryRow.hidden(entry: e),
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
                for (final e in entries)
                  _EntryRow.revealed(
                    entry: e,
                    onSpeak: e.ttsEnabled && e.answer.isNotEmpty
                        ? () => ref.read(ttsProvider).speakAnswer(e.answer)
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
bool _shouldHideHeadwordLine(
    List<SecondStageEntry> entries, Word headword) {
  for (final e in entries) {
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
  const _EntryRow.hidden({required this.entry})
      : showAnswer = false,
        onSpeak = null;
  const _EntryRow.revealed({required this.entry, this.onSpeak})
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
                _CategoryChip(cat: cat, label: cat ?? entry.relation),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    rest,
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
                    _quotedMnemonicSpans(
                      _breakForReading(entry.answerMeaning!),
                      base: TextStyle(
                        // 明朝（セリフ）・ふつうの太さ — client 2026-08-19.
                        fontFamily: 'serif',
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
  static String _breakForReading(String s) {
    // Break at cf. (both `cf.` and ` cf `)
    var out = s.replaceAll(RegExp(r'\s*cf\.\s*'), '\ncf. ');
    // Break at POS markers that follow whitespace: preserve the marker.
    out = out.replaceAllMapped(
      RegExp(r'\s+([他自名形副動前接])\s'),
      (m) => '\n${m.group(1)} ',
    );
    return out.trim();
  }

  /// 「...」-quoted text inside a meaning is a ゴロ (mnemonic), and the client
  /// wants it visually distinct from the meaning itself.
  ///
  /// Client 2026-08-19 refined the 2026-08-12 rule:
  ///   • the meaning text  → 明朝（serif）, normal weight
  ///   • the 「...」ゴロ部分 → ゴチ（sans-serif）, bold, one size smaller, black
  ///
  /// [base] already carries the serif/normal styling, so only the quoted runs
  /// are overridden here.
  static InlineSpan _quotedMnemonicSpans(String text,
      {required TextStyle base}) {
    final re = RegExp(r'「[^」]*」');
    final quoted = base.copyWith(
      fontFamily: 'sans-serif',
      fontWeight: FontWeight.w900,
      fontSize: (base.fontSize ?? 15) - 2,
      color: Colors.black,
    );
    final children = <InlineSpan>[];
    var cursor = 0;
    for (final m in re.allMatches(text)) {
      if (m.start > cursor) {
        children.add(TextSpan(
            text: text.substring(cursor, m.start), style: base));
      }
      children.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: quoted,
      ));
      cursor = m.end;
    }
    if (cursor < text.length) {
      children.add(TextSpan(text: text.substring(cursor), style: base));
    }
    if (children.isEmpty) {
      return TextSpan(text: text, style: base);
    }
    return TextSpan(children: children);
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
  const _CategoryChip({required this.cat, required this.label});
  @override
  Widget build(BuildContext context) {
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
