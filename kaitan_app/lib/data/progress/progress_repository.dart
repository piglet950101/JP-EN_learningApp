// Thin repository wrapping ProgressDb. Hides drift away from the rest of the app.
// All methods are scoped by `stage` so the same schema serves First and Second.

import 'package:drift/drift.dart';

import 'progress_db.dart';

const String kStageFirst = 'first';

class ProgressRepository {
  ProgressRepository(this._db);
  final ProgressDb _db;

  Future<void> close() => _db.close();

  // ── word_progress ──────────────────────────────────────────────────

  /// Word IDs the learner OK'd on their FIRST attempt (any prior session).
  /// Used by 「初回OKを除く」 to filter the next selection.
  Future<Set<int>> firstRoundOkIds(String stage) async {
    final rows = await (_db.select(_db.wordProgress)
          ..where((t) =>
              t.stage.equals(stage) & t.firstRoundResult.equals('ok')))
        .get();
    return rows.map((r) => r.wordId).toSet();
  }

  /// Set the first-round result for words that don't have one yet.
  /// Subsequent sessions never overwrite this — the spec defines "初回".
  Future<void> recordFirstRoundIfAbsent(
    String stage,
    Map<int, String> results, // wordId → 'ok' | 'recheck'
  ) async {
    if (results.isEmpty) return;
    final existing = await (_db.select(_db.wordProgress)
          ..where((t) =>
              t.stage.equals(stage) & t.wordId.isIn(results.keys.toList())))
        .get();
    final existingIds = existing.map((r) => r.wordId).toSet();
    final toInsert = <WordProgressData>[];
    final toUpdate = <int>[]; // ids to update existing-but-null first_round_result
    for (final e in results.entries) {
      if (existingIds.contains(e.key)) {
        final row = existing.firstWhere((r) => r.wordId == e.key);
        if (row.firstRoundResult == null) toUpdate.add(e.key);
      } else {
        toInsert.add(WordProgressData(
          wordId: e.key,
          stage: stage,
          firstRoundResult: e.value,
          lastResult: e.value,
          attempts: 1,
          updatedAt: DateTime.now(),
        ));
      }
    }
    await _db.batch((b) {
      if (toInsert.isNotEmpty) {
        b.insertAll(_db.wordProgress, toInsert,
            mode: InsertMode.insertOrIgnore);
      }
      for (final id in toUpdate) {
        b.update(
          _db.wordProgress,
          WordProgressCompanion(
            firstRoundResult: Value(results[id]),
            updatedAt: Value(DateTime.now()),
          ),
          where: (t) => t.wordId.equals(id) & t.stage.equals(stage),
        );
      }
    });
  }

  // ── block_state ────────────────────────────────────────────────────

  /// Map block_no → status ('unlearned' / 'completed') for the given stage.
  Future<Map<int, String>> blockStatuses(String stage) async {
    final rows = await (_db.select(_db.blockState)
          ..where((t) => t.stage.equals(stage)))
        .get();
    return {for (final r in rows) r.blockNo: r.status};
  }

  /// Mark the given blocks as completed at the same timestamp.
  Future<void> markBlocksCompleted(String stage, Iterable<int> blockNos) async {
    final now = DateTime.now();
    await _db.batch((b) {
      for (final no in blockNos) {
        b.insert(
          _db.blockState,
          BlockStateCompanion.insert(
            blockNo: no,
            stage: stage,
            status: const Value('completed'),
            completedAt: Value(now),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  /// Reset state and history for the given blocks (the 「リセット」 button).
  /// Removes block_state rows + clears word_progress for those blocks' words.
  Future<void> resetBlocks(String stage, Iterable<int> blockNos,
      List<int> Function(int) wordIdsForBlock) async {
    final allWordIds = <int>[];
    for (final no in blockNos) {
      allWordIds.addAll(wordIdsForBlock(no));
    }
    await _db.batch((b) {
      b.deleteWhere(
        _db.blockState,
        (t) => t.stage.equals(stage) & t.blockNo.isIn(blockNos.toList()),
      );
      if (allWordIds.isNotEmpty) {
        b.deleteWhere(
          _db.wordProgress,
          (t) => t.stage.equals(stage) & t.wordId.isIn(allWordIds),
        );
      }
    });
  }

  // ── stage_progress (lap count / ★ rating) ──────────────────────────

  Future<int> lapCount(String stage) async {
    final row = await (_db.select(_db.stageProgress)
          ..where((t) => t.stage.equals(stage)))
        .getSingleOrNull();
    return row?.lapCount ?? 0;
  }

  Future<void> incrementLap(String stage) async {
    final now = DateTime.now();
    final existing = await (_db.select(_db.stageProgress)
          ..where((t) => t.stage.equals(stage)))
        .getSingleOrNull();
    if (existing == null) {
      await _db.into(_db.stageProgress).insert(
            StageProgressCompanion.insert(
              stage: stage,
              lapCount: const Value(1),
              updatedAt: Value(now),
            ),
          );
    } else {
      await (_db.update(_db.stageProgress)
            ..where((t) => t.stage.equals(stage)))
          .write(StageProgressCompanion(
        lapCount: Value(existing.lapCount + 1),
        updatedAt: Value(now),
      ));
    }
  }
}
