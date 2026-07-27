// SessionScreen — the ⑥ Question ⇄ ⑦ Answer "hot loop" as a SINGLE screen
// that swaps internal phase (question / answer) without a route push.
// This is the speed-critical core: each word's check must complete in ≤1s.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show SystemNavigator;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../data/word.dart';
import '../domain/engine.dart';
import 'session_controller.dart';
import 'text_format.dart';

enum _Phase { question, answer, roundResult, complete }

class SessionScreen extends ConsumerStatefulWidget {
  const SessionScreen({super.key});

  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  _Phase _phase = _Phase.question;
  bool _startScheduled = false;     // guards the initial start (fires exactly once)
  int? _lastSpokenWordId;           // guards TTS auto-speak (one speak per word)
  bool _busy = false;               // debounces rapid OK/再チェック taps

  @override
  void initState() {
    super.initState();
    // Pick up the pending args set by ②③ RangeScreen and start the session.
    // Fall back to "block 1" if someone deep-links directly into /session
    // (handy for development).
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_startScheduled || !mounted) return;
      final args = ref.read(pendingSessionArgsProvider);
      if (args != null) {
        _startScheduled = true;
        await ref.read(sessionControllerProvider.notifier).startFromArgs(
              SessionArgs(
                wordIds: args.wordIds,
                selectedBlocks: args.selectedBlocks,
                stage: args.stage,
                excludeFirstOk: args.excludeFirstOk,
                seed: DateTime.now().millisecondsSinceEpoch & 0xffff,
              ),
            );
        // Consume the pending args so a subsequent visit doesn't re-fire.
        ref.read(pendingSessionArgsProvider.notifier).value = null;
      } else {
        // Dev fallback: block 1.
        final repo = await ref.read(wordRepoProvider.future);
        if (!mounted) return;
        _startScheduled = true;
        final ids = repo.byBlock(1).map((w) => w.id).toList();
        await ref.read(sessionControllerProvider.notifier).startFromArgs(
              SessionArgs(
                wordIds: ids,
                selectedBlocks: const {1},
                stage: 'first',
                seed: 42,
              ),
            );
      }
    });
  }

  void _speakIfNew(Word w) {
    if (_lastSpokenWordId == w.id) return;
    _lastSpokenWordId = w.id;
    ref.read(ttsProvider).speak(
          w.word,
          pronunciationHint: w.pronunciationHint,
          wordId: w.id,
        );
  }

  void _toStart() {
    // 「スタート画面へ」: leave session state behind and pop back to ①.
    ref.read(sessionControllerProvider.notifier).reset();
    _startScheduled = false;
    _busy = false;
    _lastSpokenWordId = null;
    if (mounted) context.go('/');
  }

  Future<void> _onRetire() async {
    // 「リタイヤ」 — confirm + abort current session, jump back to ①.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('リタイヤしますか？'),
        content: const Text(
            '今回の学習を中止してスタート画面に戻ります。\n'
            '完了済みのブロックや「初回OK」の記録はそのまま残ります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(c).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(c).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFD53F8C),
            ),
            child: const Text('リタイヤ'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(sessionControllerProvider.notifier).retire();
    _startScheduled = false;
    _busy = false;
    _lastSpokenWordId = null;
    if (mounted) context.go('/');
  }

  Future<void> _onResultRangeReselect() async {
    // ⑩「範囲指定画面に戻る」: abort + jump back to ②③.
    // retire() may flush a just-completed round-1 buffer first so the user's
    // 初回判定 isn't discarded.
    await ref.read(sessionControllerProvider.notifier).retire();
    _startScheduled = false;
    _busy = false;
    _lastSpokenWordId = null;
    if (mounted) context.go('/range');
  }

  Future<void> _answer(AnswerResult r) async {
    if (_busy) return;            // ignore double-taps
    _busy = true;
    ref.read(sessionControllerProvider.notifier).answer(r);
    setState(() => _phase = _Phase.question);
    // Tiny debounce window so a stray double-tap on the same frame is dropped.
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _busy = false;
  }

  @override
  Widget build(BuildContext context) {
    final repoAsync = ref.watch(wordRepoProvider);
    final session = ref.watch(sessionControllerProvider);

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: repoAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('データ読込エラー: $e')),
          data: (repo) {
            // While the initial `start` is in-flight, show a loader instead of
            // running the phase switch with an empty session.
            if (session.round == 0 && session.queue.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            // Derive the visible phase from session state for terminal phases;
            // question ⇄ answer is driven by explicit user taps.
            final effectivePhase = session.done
                ? _Phase.complete
                : (session.roundComplete ? _Phase.roundResult : _phase);

            switch (effectivePhase) {
              case _Phase.question:
                final word = repo.byId(session.currentWordId!);
                if (word == null) {
                  return const Center(child: Text('単語データが見つかりません'));
                }
                // Auto-speak when the current word changes (not on every rebuild).
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _speakIfNew(word);
                });
                return _QuestionView(
                  word: word,
                  session: session,
                  onTapMeaning: () => setState(() => _phase = _Phase.answer),
                  onSpeak: () => ref.read(ttsProvider).speak(
                        word.word,
                        pronunciationHint: word.pronunciationHint,
                        wordId: word.id,
                      ),
                  onRetire: _onRetire,
                );
              case _Phase.answer:
                final word = repo.byId(session.currentWordId!);
                if (word == null) {
                  return const Center(child: Text('単語データが見つかりません'));
                }
                final imageIds =
                    ref.watch(imageManifestProvider).value ?? const <int>{};
                return _AnswerView(
                  word: word,
                  session: session,
                  hasImage: imageIds.contains(word.id),
                  onOk: () => _answer(AnswerResult.ok),
                  onRecheck: () => _answer(AnswerResult.recheck),
                  onRetire: _onRetire,
                );
              case _Phase.roundResult:
                return _RoundResultView(
                  session: session,
                  onContinue: () async {
                    await ref.read(sessionControllerProvider.notifier).advance();
                    _lastSpokenWordId = null; // new round → re-speak the next word
                    if (mounted) setState(() => _phase = _Phase.question);
                  },
                  onBackToRange: _onResultRangeReselect,
                );
              case _Phase.complete:
                return _CompleteView(
                  session: session,
                  onGoStart: _toStart,
                  onExit: () {
                    // Spec ⑪B 「終了する」: 初回OK records are already persisted by
                    // _flushFirstRound during advance(), so we can exit safely.
                    SystemNavigator.pop();
                  },
                );
            }
          },
        ),
      ),
    );
  }
}

// ─────────────────────── ⑥ Question view ───────────────────────────

class _QuestionView extends StatelessWidget {
  final Word word;
  final SessionState session;
  final VoidCallback onTapMeaning;
  final VoidCallback onSpeak;
  final VoidCallback onRetire;
  const _QuestionView({
    required this.word,
    required this.session,
    required this.onTapMeaning,
    required this.onSpeak,
    required this.onRetire,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopBar(
          round: session.round,
          wordNum: word.id,
          stageLabel: 'First Stage',
          onRetire: onRetire,
        ),
        const Spacer(),
        // Word first (spec v1.2: word above POS + speaker), large + centered.
        Text(
          word.word,
          style: const TextStyle(
            fontSize: 56,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 20),
        // POS badge(s) + speaker on the row below the word.
        // Spec 2026-06-15 ③: dual-POS words display POS badges stacked
        // vertically (2 rows) instead of a single badge.
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (word.posList.length >= 2)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final p in word.posList)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: _PosBadge(p),
                    ),
                ],
              )
            else
              _PosBadge(word.posRaw),
            const SizedBox(width: 12),
            IconButton(
              iconSize: 36,
              icon: const Icon(Icons.volume_up_rounded, color: Color(0xFF2b6cb0)),
              onPressed: onSpeak,
              tooltip: '発音を再生',
            ),
          ],
        ),
        const Spacer(),
        // 「意味・例文」 button (large, thumb-reachable)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: SizedBox(
            width: double.infinity,
            height: 72,
            child: FilledButton(
              onPressed: onTapMeaning,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2b6cb0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('意味・例文',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _CounterBar(session: session),
        const SizedBox(height: 12),
      ],
    );
  }
}

// ─────────────────────── ⑦ Answer view ─────────────────────────────

class _AnswerView extends StatelessWidget {
  final Word word;
  final SessionState session;
  final bool hasImage;
  final VoidCallback onOk;
  final VoidCallback onRecheck;
  final VoidCallback onRetire;
  const _AnswerView({
    required this.word,
    required this.session,
    required this.hasImage,
    required this.onOk,
    required this.onRecheck,
    required this.onRetire,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _TopBar(
          round: session.round,
          wordNum: word.id,
          stageLabel: 'First Stage',
          onRetire: onRetire,
        ),
        // Header row: POS (left) + meaning (center, large RED) — spec v1.2 ③b.
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          child: _MeaningHeader(word: word),
        ),
        // Spec 2026-07-13 revision: the「(ひとつめの意味が言えればOK)」hint is removed.
        // Both meanings are now displayed at the same size (see _MeaningHeader).
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 覚え方 (with bold pronunciation parsing — spec ⑤)
                if (word.mnemonics.isNotEmpty) ...[
                  _label('覚え方'),
                  for (final m in word.mnemonics) _MnemonicTile(m),
                  const SizedBox(height: 14),
                ],
                // Illustration — spec ③d places it below 覚え方 and above 例文
                if (hasImage) ...[
                  _IllustrationCard(wordId: word.id),
                  const SizedBox(height: 16),
                ],
                if (word.examples.isNotEmpty) ...[
                  _label('例文'),
                  for (var i = 0; i < word.examples.length; i++) ...[
                    if (i > 0) const SizedBox(height: 10),
                    Text(word.examples[i].en,
                        style: const TextStyle(
                            fontSize: 15,
                            fontStyle: FontStyle.italic,
                            color: Colors.black87)),
                    const SizedBox(height: 4),
                    Text(word.examples[i].ja,
                        style: const TextStyle(
                            fontSize: 14, color: Colors.black54)),
                  ],
                ],
                // Padding so the example text never collides with the OK /
                // 再チェック buttons (spec ③d).
                const SizedBox(height: 28),
              ],
            ),
          ),
        ),
        // OK / 再チェック buttons — placed where 「意味・例文」 was on ⑥
        // (client requested this position for rhythm/speed).
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
                      side: const BorderSide(color: Color(0xFFD53F8C), width: 2),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('再チェック',
                        style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
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
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _CounterBar(session: session),
        const SizedBox(height: 12),
      ],
    );
  }

  static Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Text(text,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2b6cb0))),
      );
}

// ─────────────────────── ⑩ Round result ────────────────────────────

class _RoundResultView extends StatelessWidget {
  final SessionState session;
  final VoidCallback onContinue;
  final VoidCallback onBackToRange;
  const _RoundResultView({
    required this.session,
    required this.onContinue,
    required this.onBackToRange,
  });

  @override
  Widget build(BuildContext context) {
    final hasRechecks = session.rechecks.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: 24),
          Text('${session.round}巡目の結果',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
          const SizedBox(height: 32),
          _StatRow('総数', '${session.total}'),
          _StatRow('OK', '${session.ok}', color: const Color(0xFF38A169)),
          _StatRow('再チェック', '${session.recheck}', color: const Color(0xFFD53F8C)),
          const Spacer(),
          // Primary: continue with the same range (spec v1.2 ④ renamed).
          SizedBox(
            height: 72,
            child: FilledButton(
              onPressed: onContinue,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2b6cb0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(hasRechecks ? '同じ範囲を続ける' : '完了',
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          // Secondary (spec v1.2 ④): back to ②③ range-select.
          SizedBox(
            height: 56,
            child: OutlinedButton(
              onPressed: onBackToRange,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('範囲指定画面に戻る',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;
  const _StatRow(this.label, this.value, {this.color});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontSize: 18)),
            Text(value,
                style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    color: color ?? Colors.black87)),
          ],
        ),
      );
}

// ─────────────────────── ⑪ Complete ────────────────────────────────

class _CompleteView extends StatelessWidget {
  final SessionState session;
  final VoidCallback onGoStart;
  final VoidCallback onExit;
  const _CompleteView({
    required this.session,
    required this.onGoStart,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(),
          const Text('🎉  頑張った！おめでとう！',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700)),
          const SizedBox(height: 24),
          Text(
              '${session.round}巡で全単語OKになりました。',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Colors.black54)),
          const Spacer(),
          // Per spec v1.1 ⑪: 2-button manual (no auto-transition).
          SizedBox(
            height: 64,
            child: FilledButton(
              onPressed: onGoStart,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF2b6cb0),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('スタート画面へ',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 64,
            child: OutlinedButton(
              onPressed: onExit,
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('終了する',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ─────────────────────── Shared widgets ─────────────────────────────

class _TopBar extends StatelessWidget {
  final int round;
  final int wordNum;
  final String stageLabel;
  final VoidCallback? onRetire;
  const _TopBar({
    required this.round,
    required this.wordNum,
    required this.stageLabel,
    this.onRetire,
  });

  @override
  Widget build(BuildContext context) {
    // Three-column layout with the round badge dead-centered (spec v1.2):
    //   [stage + №]   [N巡目]   [リタイヤ]
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Row(children: [
              Text(stageLabel,
                  style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF2b6cb0),
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: 8),
              Text('№${wordNum.toString().padLeft(4, '0')}',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ]),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFFEDF2F7),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$round巡目',
                style: const TextStyle(
                    fontSize: 13,
                    color: Colors.black87,
                    fontWeight: FontWeight.w700)),
          ),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: onRetire == null
                  ? const SizedBox.shrink()
                  : TextButton(
                      onPressed: onRetire,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFD53F8C),
                        minimumSize: const Size(0, 32),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      child: const Text('リタイヤ',
                          style: TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w700)),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Meaning header (POS left + meaning center, big bold RED) ───────────
// Spec v1.2 ③b/④: POS is on the left, the meaning takes center stage in
// large red bold. If the meaning has a parenthesized supplement (e.g.
// "現れる（突然）") the supplement is rendered smaller and lighter.
// If the word is multi-meaning (both_required / either_ok) the meanings
// are laid out as side-by-side Wrap chips — each big+bold, never broken
// mid-character, and they fall to a second row only if no horizontal room.

class _MeaningHeader extends StatelessWidget {
  final Word word;
  const _MeaningHeader({required this.word});

  static const _bigStyle = TextStyle(
    fontSize: 30,
    fontWeight: FontWeight.w800,
    color: Color(0xFFC53030),
    height: 1.15,
  );
  static const _smallStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    color: Color(0xFFE53E3E),
    height: 1.3,
  );

  @override
  Widget build(BuildContext context) {
    final posChars = word.posList.isEmpty
        ? [word.posRaw.isEmpty ? '—' : word.posRaw]
        : word.posList;

    // Pattern C — spec 2026-06-15 ③: when there are TWO parts of speech
    // (e.g. "他自"), render the answer screen as 2 stacked rows, each pairing
    // a POS with its corresponding meaning. The 問題 screen handles its own
    // POS stacking already.
    if (posChars.length >= 2) {
      // Pair meanings with POS by index; if not enough meanings, repeat last.
      final pairs = <(String, String)>[];
      for (var i = 0; i < posChars.length; i++) {
        final m = i < word.meanings.length
            ? word.meanings[i]
            : (word.meanings.isNotEmpty ? word.meanings.last : '—');
        pairs.add((posChars[i], m));
      }
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (p, m) in pairs)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _PosBadge(p),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text.rich(
                      TextSpan(children: meaningSingleSpans(
                        m,
                        bigStyle: _bigStyle,
                        smallStyle: _smallStyle,
                      )),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ],
              ),
            ),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final p in posChars)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: _PosBadge(p),
              ),
          ],
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Center(child: _buildMeaningContent()),
        ),
      ],
    );
  }

  Widget _buildMeaningContent() {
    if (word.meanings.isEmpty) {
      return const Text('—', style: _bigStyle);
    }
    // Spec 2026-07-13 revision: for BOTH either_ok and both_required with
    // multiple meanings, render every meaning at the same size, joined by
    // 「、」 on a single line. Parentheticals inside each meaning stay small
    // (handled by meaningSingleSpans).
    if (word.meanings.length > 1 &&
        (word.meaningMode == MeaningMode.eitherOk ||
            word.meaningMode == MeaningMode.bothRequired)) {
      final text = word.meanings.join('、');
      return Text.rich(
        TextSpan(children: meaningSingleSpans(
          text,
          bigStyle: _bigStyle,
          smallStyle: _smallStyle,
        )),
        textAlign: TextAlign.center,
      );
    }
    // Single mode — possibly with parenthesized supplement.
    final text = word.meanings.join('、');
    return Text.rich(
      TextSpan(children: meaningSingleSpans(
        text,
        bigStyle: _bigStyle,
        smallStyle: _smallStyle,
      )),
      textAlign: TextAlign.center,
    );
  }
}

// ─── Mnemonic tile (bold pronunciation, normal-weight brackets) ─────────
// Spec v1.2 ⑤: the pronunciation-linked portion of the mnemonic (everything
// outside the [..] / ［..］ brackets) is rendered bold. The bracketed
// portion — the meaning glossing — is rendered in a lighter weight.

class _MnemonicTile extends StatelessWidget {
  final Mnemonic m;
  const _MnemonicTile(this.m);

  // Bold style sized up a touch + heavier weight for clear visual distinction
  // from the plain (gloss) text. The bold portion is the pronunciation-linked
  // syllables sourced from the Excel's character-level formatting.
  static const _bold = TextStyle(
    fontSize: 17,
    fontWeight: FontWeight.w900,
    color: Color(0xFF1A202C),
    height: 1.4,
  );
  static const _plain = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: Color(0xFF4A5568),
    height: 1.4,
  );

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            margin: const EdgeInsets.only(top: 4, right: 8),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: const Color(0xFFEBF4FF),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(m.type,
                style: const TextStyle(
                    fontSize: 11, color: Color(0xFF2b6cb0))),
          ),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                for (final r in m.runs)
                  TextSpan(text: r.text, style: r.bold ? _bold : _plain),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _IllustrationCard extends StatelessWidget {
  final int wordId;
  const _IllustrationCard({required this.wordId});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320, maxHeight: 220),
        child: AspectRatio(
          aspectRatio: 800 / 560,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              color: const Color(0xFFF7FAFC),
              child: Image.asset(
                imageAssetPath(wordId),
                fit: BoxFit.contain,
                // If the file isn't in the bundle (manifest can disagree with
                // assets for a brief window mid-deploy), degrade quietly.
                errorBuilder: (c, e, st) => const SizedBox.shrink(),
                // Crisp re-scale for high-DPI screens.
                filterQuality: FilterQuality.medium,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PosBadge extends StatelessWidget {
  final String pos;
  const _PosBadge(this.pos);
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFFFFE5B4),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(pos.isEmpty ? '—' : pos,
            style: const TextStyle(
                fontSize: 14, color: Color(0xFF8B4513), fontWeight: FontWeight.w700)),
      );
}

class _CounterBar extends StatelessWidget {
  final SessionState session;
  const _CounterBar({required this.session});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _chip('残/総数', '${session.remaining}/${session.total}'),
            _chip('OK', '${session.ok}', color: const Color(0xFF38A169)),
            _chip('再チェック', '${session.recheck}', color: const Color(0xFFD53F8C)),
          ],
        ),
      );
  static Widget _chip(String label, String value, {Color? color}) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 10, color: Colors.black54)),
          Text(value,
              style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: color ?? Colors.black87)),
        ],
      );
}
