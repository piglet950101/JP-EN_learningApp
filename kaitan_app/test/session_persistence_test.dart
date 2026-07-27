// Verifies that SessionController correctly persists to drift:
//   • first-round results land in word_progress (and are NOT overwritten on
//     a subsequent session for the same words)
//   • selected blocks are marked completed on session done
//   • completing every block triggers an incrementLap + auto-reset
//
// Uses an in-memory ProgressDb so no real DB file is touched.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/core/providers.dart';
import 'package:kaitan/data/block.dart';
import 'package:kaitan/data/progress/progress_db.dart';
import 'package:kaitan/data/progress/progress_repository.dart';
import 'package:kaitan/features/session/domain/engine.dart';
import 'package:kaitan/features/session/presentation/session_controller.dart';

ProviderContainer _container(ProgressDb db) {
  return ProviderContainer(overrides: [
    progressDbProvider.overrideWithValue(db),
  ]);
}

void main() {
  test('round-1 results are persisted exactly once (no overwrite)', () async {
    final db = ProgressDb.memory();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);

    final repo = c.read(progressRepoProvider);
    final ctrl = c.read(sessionControllerProvider.notifier);

    final ids = [1, 2, 3, 4, 5];
    await ctrl.startFromArgs(SessionArgs(
      wordIds: ids,
      selectedBlocks: const {1},
      stage: kStageFirst,
      seed: 7,
    ));

    // Mark odd IDs OK, even IDs recheck on round 1.
    while (c.read(sessionControllerProvider).isAnswering) {
      final wid = c.read(sessionControllerProvider).currentWordId!;
      ctrl.answer(wid.isOdd ? AnswerResult.ok : AnswerResult.recheck);
    }
    // Round 1 complete → advance to round 2 (flushes round-1).
    await ctrl.advance();

    final okIds = await repo.firstRoundOkIds(kStageFirst);
    expect(okIds, equals({1, 3, 5}));

    // Now ALL-OK the rechecks in round 2 so the session completes.
    while (c.read(sessionControllerProvider).isAnswering) {
      ctrl.answer(AnswerResult.ok);
    }
    await ctrl.advance(); // done
    expect(c.read(sessionControllerProvider).done, true);

    // Start a NEW session with the same words; force everything to RECHECK on
    // round 1. The first_round_result for {1,3,5} must NOT be overwritten.
    await ctrl.startFromArgs(SessionArgs(
      wordIds: ids,
      selectedBlocks: const {1},
      stage: kStageFirst,
      seed: 7,
    ));
    while (c.read(sessionControllerProvider).isAnswering) {
      ctrl.answer(AnswerResult.recheck);
    }
    await ctrl.advance();

    final okIdsAfter = await repo.firstRoundOkIds(kStageFirst);
    expect(okIdsAfter, equals({1, 3, 5}),
        reason: 'first_round_result must be immutable after initial set');
  });

  test('completing all 46 blocks bumps lap_count + auto-resets', () async {
    final db = ProgressDb.memory();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);

    final repo = c.read(progressRepoProvider);

    // Shortcut: just mark all 46 blocks completed via the repo, then advance
    // through a tiny final session — the controller's completion path checks
    // statuses and bumps the lap.
    await repo.markBlocksCompleted(
      kStageFirst,
      kAllBlocks.skip(1).map((b) => b.no), // 45 blocks pre-marked
    );

    final ctrl = c.read(sessionControllerProvider.notifier);
    await ctrl.startFromArgs(SessionArgs(
      wordIds: const [1, 2],
      selectedBlocks: const {1}, // the one remaining block
      stage: kStageFirst,
      seed: 0,
    ));
    while (c.read(sessionControllerProvider).isAnswering) {
      c
          .read(sessionControllerProvider.notifier)
          .answer(AnswerResult.ok);
    }
    await ctrl.advance(); // done → flushes completion → all 46 done → lap+1

    final laps = await repo.lapCount(kStageFirst);
    expect(laps, 1);

    final statuses = await repo.blockStatuses(kStageFirst);
    expect(statuses.values.where((s) => s == 'completed').length, 0,
        reason: 'after a lap, block_state is reset so next lap starts fresh');
  });

  test('retire AFTER round 1 completes ⇒ flushes round-1 results', () async {
    final db = ProgressDb.memory();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);

    final repo = c.read(progressRepoProvider);
    final ctrl = c.read(sessionControllerProvider.notifier);

    final ids = [1, 2, 3, 4, 5];
    await ctrl.startFromArgs(SessionArgs(
      wordIds: ids,
      selectedBlocks: const {1},
      stage: kStageFirst,
      seed: 7,
    ));

    // Complete round 1: odd ids = OK, even ids = recheck.
    while (c.read(sessionControllerProvider).isAnswering) {
      final wid = c.read(sessionControllerProvider).currentWordId!;
      ctrl.answer(wid.isOdd ? AnswerResult.ok : AnswerResult.recheck);
    }
    expect(c.read(sessionControllerProvider).roundComplete, true);

    // User is on the ⑩ result screen and presses「範囲指定画面に戻る」 — that's a
    // retire(). The just-completed round-1 results MUST be preserved.
    await ctrl.retire();

    final okIds = await repo.firstRoundOkIds(kStageFirst);
    expect(okIds, equals({1, 3, 5}),
        reason: 'retire-after-round-complete must persist first-round OKs');
  });

  test('retire MID-round-1 ⇒ partial results discarded (not authoritative)',
      () async {
    final db = ProgressDb.memory();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);

    final repo = c.read(progressRepoProvider);
    final ctrl = c.read(sessionControllerProvider.notifier);

    await ctrl.startFromArgs(SessionArgs(
      wordIds: const [10, 20, 30, 40, 50],
      selectedBlocks: const {1},
      stage: kStageFirst,
      seed: 7,
    ));
    // Answer only the first 2 of 5 words, then retire.
    for (var i = 0; i < 2; i++) {
      ctrl.answer(AnswerResult.ok);
    }
    expect(c.read(sessionControllerProvider).roundComplete, false);
    await ctrl.retire();

    final okIds = await repo.firstRoundOkIds(kStageFirst);
    expect(okIds, isEmpty,
        reason:
            'mid-round-1 retire must not lock in partial answers as authoritative');
  });

  test('「初回OKを除く」 filters word IDs against firstRoundOkIds', () async {
    final db = ProgressDb.memory();
    addTearDown(db.close);
    final c = _container(db);
    addTearDown(c.dispose);

    final repo = c.read(progressRepoProvider);
    await repo.recordFirstRoundIfAbsent(kStageFirst, {1: 'ok', 2: 'recheck', 3: 'ok'});

    final ctrl = c.read(sessionControllerProvider.notifier);
    await ctrl.startFromArgs(SessionArgs(
      wordIds: const [1, 2, 3, 4, 5],
      selectedBlocks: const {1},
      stage: kStageFirst,
      excludeFirstOk: true,
      seed: 0,
    ));
    final queue = c.read(sessionControllerProvider).queue;
    expect(queue.toSet(), equals({2, 4, 5}),
        reason: 'IDs 1 and 3 (first-round OK) must be excluded');
  });
}
