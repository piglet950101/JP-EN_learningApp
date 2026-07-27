// 「満点法」 engine tests — verifies the spec's worked example end-to-end
// (96 → 56 OK + 40 recheck → 26+14 → 10+4 → all OK), plus edge cases.

import 'package:flutter_test/flutter_test.dart';
import 'package:kaitan/features/session/domain/engine.dart';

void main() {
  group('MantenhoEngine.start', () {
    test('initial state for 96 words', () {
      final s = MantenhoEngine.start(List.generate(96, (i) => i + 1), seed: 1);
      expect(s.round, 1);
      expect(s.total, 96);
      expect(s.remaining, 96);
      expect(s.index, 0);
      expect(s.ok, 0);
      expect(s.recheck, 0);
      expect(s.done, false);
      expect(s.roundComplete, false);
      expect(s.isAnswering, true);
      expect(s.currentWordId, isNotNull);
      // Same seed ⇒ same shuffle (deterministic for tests/replay).
      final s2 = MantenhoEngine.start(List.generate(96, (i) => i + 1), seed: 1);
      expect(s2.queue, equals(s.queue));
    });

    test('different seed ⇒ different order', () {
      final a = MantenhoEngine.start(List.generate(96, (i) => i + 1), seed: 1);
      final b = MantenhoEngine.start(List.generate(96, (i) => i + 1), seed: 2);
      expect(a.queue, isNot(equals(b.queue)));
      // …but the set is identical.
      expect(a.queue.toSet(), equals(b.queue.toSet()));
    });
  });

  group('Worked example from 解説書 (blocks 7+8 = 96 words)', () {
    test('96 → 56+40 → 26+14 → 10+4 → all OK', () {
      final ids = List.generate(96, (i) => i + 1);
      var s = MantenhoEngine.start(ids, seed: 42);

      // ── Round 1: 96 words → 56 OK + 40 recheck ──
      expect(s.round, 1);
      expect(s.total, 96);
      for (var i = 0; i < 96; i++) {
        expect(s.remaining, 96 - i);
        s = MantenhoEngine.answer(
            s, i < 56 ? AnswerResult.ok : AnswerResult.recheck);
      }
      expect(s.roundComplete, true);
      expect(s.ok, 56);
      expect(s.recheck, 40);
      expect(s.rechecks.length, 40);
      expect(s.done, false);

      // ── Round 2: 40 words → 26 OK + 14 recheck ──
      s = MantenhoEngine.advance(s, seed: 42);
      expect(s.round, 2);
      expect(s.total, 40);
      expect(s.ok, 0);
      expect(s.recheck, 0);
      for (var i = 0; i < 40; i++) {
        s = MantenhoEngine.answer(
            s, i < 26 ? AnswerResult.ok : AnswerResult.recheck);
      }
      expect(s.roundComplete, true);
      expect(s.ok, 26);
      expect(s.recheck, 14);

      // ── Round 3: 14 words → 10 OK + 4 recheck ──
      s = MantenhoEngine.advance(s, seed: 42);
      expect(s.round, 3);
      expect(s.total, 14);
      for (var i = 0; i < 14; i++) {
        s = MantenhoEngine.answer(
            s, i < 10 ? AnswerResult.ok : AnswerResult.recheck);
      }
      expect(s.ok, 10);
      expect(s.recheck, 4);

      // ── Round 4: 4 words, all OK → done ──
      s = MantenhoEngine.advance(s, seed: 42);
      expect(s.round, 4);
      expect(s.total, 4);
      for (var i = 0; i < 4; i++) {
        s = MantenhoEngine.answer(s, AnswerResult.ok);
      }
      expect(s.ok, 4);
      expect(s.recheck, 0);
      expect(s.roundComplete, true);

      // ── Press 「指定範囲を続ける」 (or auto on all-OK) ⇒ done. ──
      s = MantenhoEngine.advance(s, seed: 42);
      expect(s.done, true);
      expect(s.isAnswering, false);
    });
  });

  group('Round contents (correctness)', () {
    test('next round consists of exactly the recheck IDs in this round', () {
      var s = MantenhoEngine.start([1, 2, 3, 4, 5, 6], seed: 7);
      final answered = <int, AnswerResult>{};
      // Mark even IDs as recheck, odd as OK.
      for (var i = 0; i < 6; i++) {
        final wid = s.currentWordId!;
        final r = wid.isEven ? AnswerResult.recheck : AnswerResult.ok;
        answered[wid] = r;
        s = MantenhoEngine.answer(s, r);
      }
      expect(s.rechecks.toSet(), equals({2, 4, 6}));
      s = MantenhoEngine.advance(s, seed: 7);
      expect(s.queue.toSet(), equals({2, 4, 6}));
      expect(s.round, 2);
    });

    test('each round presents every word exactly once', () {
      var s = MantenhoEngine.start([10, 20, 30, 40, 50], seed: 99);
      final seen = <int>[];
      while (s.isAnswering) {
        seen.add(s.currentWordId!);
        s = MantenhoEngine.answer(s, AnswerResult.ok);
      }
      expect(seen.toSet(), equals({10, 20, 30, 40, 50}));
      expect(seen.length, 5);
    });
  });

  group('Edge cases', () {
    test('answer is a no-op when the round is complete', () {
      var s = MantenhoEngine.start([1, 2], seed: 0);
      s = MantenhoEngine.answer(s, AnswerResult.ok);
      s = MantenhoEngine.answer(s, AnswerResult.ok);
      expect(s.roundComplete, true);
      final before = s.toString();
      s = MantenhoEngine.answer(s, AnswerResult.ok); // no-op
      expect(s.toString(), before);
    });

    test('advance before round-complete is a no-op', () {
      var s = MantenhoEngine.start([1, 2, 3], seed: 0);
      s = MantenhoEngine.answer(s, AnswerResult.ok);
      final before = s.toString();
      s = MantenhoEngine.advance(s); // no-op
      expect(s.toString(), before);
    });

    test('single-word session, OK ⇒ done in one shot', () {
      var s = MantenhoEngine.start([42], seed: 0);
      s = MantenhoEngine.answer(s, AnswerResult.ok);
      s = MantenhoEngine.advance(s);
      expect(s.done, true);
    });

    test('single-word session, recheck loops until OK', () {
      var s = MantenhoEngine.start([42], seed: 0);
      for (var i = 0; i < 5; i++) {
        s = MantenhoEngine.answer(s, AnswerResult.recheck);
        expect(s.roundComplete, true);
        s = MantenhoEngine.advance(s);
        expect(s.done, false);
        expect(s.round, i + 2);
        expect(s.queue, [42]);
      }
      s = MantenhoEngine.answer(s, AnswerResult.ok);
      s = MantenhoEngine.advance(s);
      expect(s.done, true);
    });
  });

  group('「初回OKを除く」 (buildSessionInput)', () {
    test('excludeFirstOk=false ⇒ unchanged list', () {
      final got = buildSessionInput(
        selectedWordIds: [1, 2, 3, 4, 5],
        firstRoundOkIds: {2, 4},
        excludeFirstOk: false,
      );
      expect(got, [1, 2, 3, 4, 5]);
    });

    test('excludeFirstOk=true ⇒ removes IDs marked OK on first round', () {
      final got = buildSessionInput(
        selectedWordIds: [1, 2, 3, 4, 5],
        firstRoundOkIds: {2, 4},
        excludeFirstOk: true,
      );
      expect(got, [1, 3, 5]);
    });

    test('excludeFirstOk=true on a "white" block (no history) ⇒ keep all', () {
      final got = buildSessionInput(
        selectedWordIds: [10, 20, 30],
        firstRoundOkIds: const {},
        excludeFirstOk: true,
      );
      expect(got, [10, 20, 30]);
    });
  });
}
