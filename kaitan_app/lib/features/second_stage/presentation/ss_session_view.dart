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
    return Column(
      children: [
        _SsTopBar(round: session.round, no: headword.id, onRetire: onRetire),
        _Headword(
          headword: headword,
          onSpeak: () => ref.read(ttsProvider).speak(
                headword.word,
                pronunciationHint: headword.pronunciationHint,
                wordId: headword.id,
              ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in entries)
                  _EntryRow.hidden(entry: e),
                const SizedBox(height: 16),
                Text(
                  '${entries.length} 個の関連問題',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          child: SizedBox(
            height: 72,
            child: FilledButton(
              onPressed: onTapAnswer,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2b6cb0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('意味・答え',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
            ),
          ),
        ),
      ],
    );
  }
}

class SsAnswerView extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        _SsTopBar(round: session.round, no: headword.id, onRetire: onRetire),
        _Headword(
          headword: headword,
          onSpeak: () => ref.read(ttsProvider).speak(
                headword.word,
                pronunciationHint: headword.pronunciationHint,
                wordId: headword.id,
              ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final e in entries)
                  _EntryRow.revealed(
                    entry: e,
                    onSpeak: e.ttsEnabled && e.answer.isNotEmpty
                        ? () => ref.read(ttsProvider).speak(e.answer)
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
                    onPressed: onRecheck,
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
                    onPressed: onOk,
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
        const SizedBox(height: 12),
      ],
    );
  }
}

// ─── Common pieces ────────────────────────────────────────────────────

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
  final VoidCallback onSpeak;
  const _Headword({required this.headword, required this.onSpeak});

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
              _MiniPosBadge(headword.posRaw),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  headword.meanings.join('、'),
                  style: const TextStyle(fontSize: 16, color: Colors.black87),
                  textAlign: TextAlign.center,
                ),
              ),
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
          ),
        ],
      ),
    );
  }
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
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _RelationChip(entry.relation),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (showAnswer) ...[
                  Text(
                    entry.answer,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFFC53030),
                    ),
                  ),
                  if ((entry.answerMeaning ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        entry.answerMeaning!,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black87),
                      ),
                    ),
                ] else
                  Container(
                    height: 40,
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7FAFC),
                      border: Border.all(
                          color: const Color(0xFFCBD5E0), width: 1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    alignment: Alignment.center,
                    child: const Text('？',
                        style: TextStyle(
                            fontSize: 20,
                            color: Colors.black38,
                            fontWeight: FontWeight.w700)),
                  ),
              ],
            ),
          ),
          if (showAnswer && onSpeak != null)
            IconButton(
              onPressed: onSpeak,
              icon: const Icon(Icons.volume_up_outlined),
              iconSize: 20,
              color: const Color(0xFF2b6cb0),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
        ],
      ),
    );
  }
}

class _RelationChip extends StatelessWidget {
  final String relation;
  const _RelationChip(this.relation);
  @override
  Widget build(BuildContext context) {
    final cat = SsRelationCategory.categoryOf(relation);
    // Chip is compact — 44dp wide, so free-form long labels wrap below via
    // a secondary line beneath the base code.
    final base = cat ?? relation;
    final rest = cat == null || relation == cat ? null : relation.substring(cat.length).trim();
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 48, maxWidth: 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _chipColor(cat),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              base,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Colors.white,
              ),
            ),
          ),
          if (rest != null && rest.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                rest,
                style: const TextStyle(fontSize: 11, color: Colors.black54),
              ),
            ),
        ],
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
        return const Color(0xFF3182CE); // 派生系・類義
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
        return const Color(0xFF718096); // free-form
    }
  }
}
