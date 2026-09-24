// Two rules that are easy to break when the block list changes, as it did
// when the vol.3 medical block (47) was added:
//
//   * A lap is every block a stage offers. First Stage offers 1-46, Second
//     Stage 1-47. Counting 47 for First Stage meant its lap count could never
//     go up (the lap test itself is in session_persistence_test.dart).
//   * The trial is blocks 1-2 everywhere. Block 47 in Second Stage was left
//     ungated, so a trial user could study its 66 words without unlocking.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/core/providers.dart';
import 'package:kaitan/data/block.dart';
import 'package:kaitan/data/progress/progress_repository.dart';
import 'package:kaitan/features/range_select/range_screen.dart';

Widget _secondStageRange({required bool unlocked}) => ProviderScope(
      overrides: [
        unlockedProvider.overrideWith((ref) async => unlocked),
        blockStatusesProvider(kStageSecond)
            .overrideWith((ref) async => const <int, String>{}),
      ],
      child: const MaterialApp(home: RangeScreen(stage: kStageSecond)),
    );

Future<void> _tapBlock(WidgetTester tester, int no) async {
  final tile = find.text('$no');
  await tester.ensureVisible(tile);
  await tester.tap(tile, warnIfMissed: false);
  await tester.pump();
}

void main() {
  group('laps', () {
    test('a First Stage lap is blocks 1-46', () {
      final lap = lapBlocks(secondStage: false).map((b) => b.no).toList();
      expect(lap, [for (var n = 1; n <= 46; n++) n]);
    });

    test('a Second Stage lap includes the medical block 47', () {
      final lap = lapBlocks(secondStage: true).map((b) => b.no).toList();
      expect(lap, [for (var n = 1; n <= 47; n++) n]);
    });
  });

  group('trial gate on the Second Stage medical block', () {
    testWidgets('a trial user cannot select block 47', (tester) async {
      await tester.pumpWidget(_secondStageRange(unlocked: false));
      await tester.pumpAndSettle();

      await _tapBlock(tester, 47);
      expect(find.textContaining('選択中: 0ブロック'), findsOneWidget);
    });

    testWidgets('an unlocked user can', (tester) async {
      await tester.pumpWidget(_secondStageRange(unlocked: true));
      await tester.pumpAndSettle();

      await _tapBlock(tester, 47);
      expect(find.textContaining('選択中: 1ブロック'), findsOneWidget);
    });
  });
}
