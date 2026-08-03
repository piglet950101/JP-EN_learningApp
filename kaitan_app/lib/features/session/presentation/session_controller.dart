// SessionController — Riverpod wrapper around the pure-Dart MantenhoEngine.
// On round completion it captures first-round results; on session done it
// flushes them + marks the selected blocks completed + increments lap if
// the whole stage is now done.

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers.dart';
import '../../../data/block.dart';
import '../../../data/progress/progress_repository.dart';
import '../../../data/tts_service.dart';
import '../../../data/word.dart';
import '../domain/engine.dart';

final wordRepoProvider = FutureProvider<WordRepository>((ref) async {
  return WordRepository.loadFromAsset();
});

final ttsProvider = Provider<TtsService>((ref) {
  final assets = ref.watch(audioManifestProvider).maybeWhen(
        data: (m) => m,
        orElse: () => const <int, String>{},
      );
  final tts = FlutterTtsService(audioAssets: assets);
  tts.init();
  return tts;
});

class SessionArgs {
  final List<int> wordIds;
  final Set<int> selectedBlocks;
  final String stage;
  final bool excludeFirstOk;
  final int seed;
  const SessionArgs({
    required this.wordIds,
    required this.selectedBlocks,
    required this.stage,
    this.excludeFirstOk = false,
    this.seed = 0,
  });
}

class SessionController extends Notifier<SessionState> {
  int _seed = 0;
  String _stage = kStageFirst;
  Set<int> _selectedBlocks = const {};
  final Map<int, AnswerResult> _firstRound = {}; // captured during round 1

  /// Which stage the current session belongs to (read by the SessionScreen
  /// to decide FS vs SS rendering).
  String get currentStage => _stage;

  @override
  SessionState build() {
    return const SessionState(
      round: 0,
      queue: [],
      index: 0,
      ok: 0,
      recheck: 0,
      rechecks: [],
      done: false,
    );
  }

  /// Start a session. If [excludeFirstOk] is true, words OK'd on a prior
  /// first attempt are filtered out via `word_progress.first_round_result`.
  Future<void> startFromArgs(SessionArgs args) async {
    _seed = args.seed;
    _stage = args.stage;
    _selectedBlocks = Set.of(args.selectedBlocks);
    _firstRound.clear();
    final wordIds = args.excludeFirstOk
        ? buildSessionInput(
            selectedWordIds: args.wordIds,
            firstRoundOkIds:
                await ref.read(progressRepoProvider).firstRoundOkIds(_stage),
            excludeFirstOk: true,
          )
        : args.wordIds;
    state = MantenhoEngine.start(wordIds, seed: _seed);
  }

  void answer(AnswerResult r) {
    if (!state.isAnswering) return;
    // Capture round-1 result for the current word BEFORE applying the answer.
    if (state.round == 1) {
      final wid = state.currentWordId!;
      _firstRound.putIfAbsent(wid, () => r);
    }
    state = MantenhoEngine.answer(state, r);
  }

  Future<void> advance() async {
    // CAPTURE everything we need BEFORE any async gap, so that a concurrent
    // `reset()` (e.g. user tapping 「スタート画面へ」 fast) can't corrupt the flush.
    final wasRound1 = state.round == 1;
    final stage = _stage;
    final blocks = Set<int>.from(_selectedBlocks);
    final round1Snapshot = wasRound1
        ? Map<int, AnswerResult>.from(_firstRound)
        : const <int, AnswerResult>{};

    state = MantenhoEngine.advance(state, seed: _seed);
    final isDoneNow = state.done;

    if (wasRound1 && round1Snapshot.isNotEmpty) {
      await _flushFirstRoundWith(stage, round1Snapshot);
      _firstRound.clear();
    }
    if (isDoneNow) {
      await _flushSessionCompletionWith(stage, blocks);
    }
  }

  Future<void> _flushFirstRoundWith(
      String stage, Map<int, AnswerResult> snapshot) async {
    final repo = ref.read(progressRepoProvider);
    final results = {
      for (final e in snapshot.entries)
        e.key: e.value == AnswerResult.ok ? 'ok' : 'recheck',
    };
    await repo.recordFirstRoundIfAbsent(stage, results);
  }

  Future<void> _flushSessionCompletionWith(
      String stage, Set<int> blocks) async {
    final repo = ref.read(progressRepoProvider);
    if (blocks.isNotEmpty) {
      await repo.markBlocksCompleted(stage, blocks);
    }
    // Bump lap_count when ALL 46 blocks are completed (Q-3 confirmed).
    final statuses = await repo.blockStatuses(stage);
    final completed = statuses.values.where((s) => s == 'completed').length;
    if (completed >= kAllBlocks.length) {
      await repo.incrementLap(stage);
      // After bumping lap, reset block_state so the user can start a new lap.
      await repo.resetBlocks(
        stage,
        kAllBlocks.map((b) => b.no),
        (no) {
          final b = kAllBlocks.firstWhere((x) => x.no == no);
          return [for (var id = b.firstId; id <= b.lastId; id++) id];
        },
      );
    }
    ref.invalidate(blockStatusesProvider(stage));
    ref.invalidate(lapCountProvider(stage));
  }

  void reset() {
    _firstRound.clear();
    _selectedBlocks = const {};
    state = const SessionState(
      round: 0,
      queue: [],
      index: 0,
      ok: 0,
      recheck: 0,
      rechecks: [],
      done: false,
    );
  }

  /// 「リタイヤ」 — abort the current learning session without marking any
  /// blocks completed. Per the spec (2026-06-02): 「初回判定はそのまま残る」.
  ///
  /// Concretely:
  ///   • Already-persisted first-round results — left untouched.
  ///   • If round 1 has JUST completed (we're on the ⑩ result screen, the user
  ///     answered every word, but `advance()` hasn't run yet) the in-memory
  ///     buffer holds an authoritative round-1 snapshot → flush it so the
  ///     user's work isn't silently discarded.
  ///   • If round 1 is still in progress (partial answers in the buffer) —
  ///     discard, since a partial round isn't a meaningful "初回判定".
  Future<void> retire() async {
    if (state.round == 1 &&
        state.roundComplete &&
        _firstRound.isNotEmpty) {
      final stage = _stage;
      final snapshot = Map<int, AnswerResult>.from(_firstRound);
      await _flushFirstRoundWith(stage, snapshot);
    }
    _firstRound.clear();
    _selectedBlocks = const {};
    state = const SessionState(
      round: 0,
      queue: [],
      index: 0,
      ok: 0,
      recheck: 0,
      rechecks: [],
      done: false,
    );
  }
}

final sessionControllerProvider =
    NotifierProvider<SessionController, SessionState>(SessionController.new);
