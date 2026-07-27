// MantenhoEngine — 「満点法」 state machine.
//
// Pure Dart, no Flutter / no drift / no Riverpod. Deterministic given a seed.
// The whole 学習ロジック lives here so it can be unit-tested without a device.

import 'dart:math';

enum AnswerResult { ok, recheck }

class SessionState {
  /// 1-based round number (巡目).
  final int round;

  /// Word IDs queued for this round, in presentation order (already shuffled).
  final List<int> queue;

  /// Index into [queue] of the *next* word to present.
  /// `index == queue.length` ⇒ round complete (show ⑩ result screen).
  final int index;

  /// Counter for the CURRENT round only (resets each round). 「残/総数・OK・再チェック」
  /// are derived from these + queue.
  final int ok;
  final int recheck;

  /// Word IDs that received `recheck` this round; they form the next round's queue.
  final List<int> rechecks;

  /// True once a round completes with zero rechecks ⇒ ⑪ end screen.
  final bool done;

  const SessionState({
    required this.round,
    required this.queue,
    required this.index,
    required this.ok,
    required this.recheck,
    required this.rechecks,
    required this.done,
  });

  int get total => queue.length;
  int get remaining => total - index;
  bool get roundComplete => index >= queue.length;
  bool get isAnswering => !done && !roundComplete;
  int? get currentWordId => isAnswering ? queue[index] : null;

  SessionState copyWith({
    int? round,
    List<int>? queue,
    int? index,
    int? ok,
    int? recheck,
    List<int>? rechecks,
    bool? done,
  }) {
    return SessionState(
      round: round ?? this.round,
      queue: queue ?? this.queue,
      index: index ?? this.index,
      ok: ok ?? this.ok,
      recheck: recheck ?? this.recheck,
      rechecks: rechecks ?? this.rechecks,
      done: done ?? this.done,
    );
  }

  @override
  String toString() =>
      'SessionState(round=$round, ok=$ok/$total, recheck=$recheck, '
      'remaining=$remaining, done=$done)';
}

/// Stateless reducer. Each call returns a NEW SessionState — the Riverpod
/// notifier wraps this and exposes the latest snapshot to the UI.
class MantenhoEngine {
  /// Build the initial session for the given word IDs.
  /// Order is randomized deterministically by [seed] (so tests are stable).
  static SessionState start(List<int> wordIds, {int seed = 0}) {
    final shuffled = [...wordIds]..shuffle(Random(seed));
    return SessionState(
      round: 1,
      queue: List.unmodifiable(shuffled),
      index: 0,
      ok: 0,
      recheck: 0,
      rechecks: const [],
      done: false,
    );
  }

  /// Apply an OK / 再チェック judgement to the current word, advance the index.
  /// No-op if the round is already complete or the session is done.
  static SessionState answer(SessionState s, AnswerResult r) {
    if (!s.isAnswering) return s;
    final wid = s.queue[s.index];
    final nextRechecks =
        r == AnswerResult.recheck ? [...s.rechecks, wid] : s.rechecks;
    return s.copyWith(
      index: s.index + 1,
      ok: r == AnswerResult.ok ? s.ok + 1 : s.ok,
      recheck: r == AnswerResult.recheck ? s.recheck + 1 : s.recheck,
      rechecks: nextRechecks,
    );
  }

  /// User pressed 「指定範囲を続ける」 (or all-OK auto-advance) on the ⑩ result
  /// screen. If there are no rechecks ⇒ done (⑪ end screen).
  /// Otherwise build the next round's queue from this round's rechecks.
  static SessionState advance(SessionState s, {int seed = 0}) {
    if (!s.roundComplete) return s;
    if (s.rechecks.isEmpty) {
      return s.copyWith(done: true);
    }
    final next = [...s.rechecks]..shuffle(Random(seed ^ (s.round + 1)));
    return SessionState(
      round: s.round + 1,
      queue: List.unmodifiable(next),
      index: 0,
      ok: 0,
      recheck: 0,
      rechecks: const [],
      done: false,
    );
  }
}

/// Build the initial set of word IDs to present, applying the「初回OKを除く」mode.
///
/// [selectedWordIds] — every word ID in the selected blocks (in block order).
/// [firstRoundOkIds] — set of word IDs the learner OK'd on their *first* attempt
/// in a prior session (from `word_progress.first_round_result == 'ok'`).
/// [excludeFirstOk] — true when the user pressed 「初回OKを除く」.
List<int> buildSessionInput({
  required List<int> selectedWordIds,
  required Set<int> firstRoundOkIds,
  required bool excludeFirstOk,
}) {
  if (!excludeFirstOk) return [...selectedWordIds];
  return selectedWordIds.where((id) => !firstRoundOkIds.contains(id)).toList();
}
