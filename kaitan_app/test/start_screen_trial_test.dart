// The start screen's two trial affordances, both asked for by the client on
// 2026-09-12:
//
//   • First Stage was the one stage card still advertising the full 2,201
//     words to a trial user; Second Stage and ビデオ解説 already switched on
//     the licence.
//   • The unlock-code screen existed at /unlock but was reachable from exactly
//     one place in the app — tapping a LOCKED video card — so a buyer who had
//     just paid had nowhere to go: 「購入後のアンロックコードの記入画面はどこに
//     あるか分かりません」.
//
// Both are a locked/unlocked branch, which is the easy kind to get backwards.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/core/providers.dart';
import 'package:kaitan/data/progress/progress_repository.dart';
import 'package:kaitan/features/start/start_screen.dart';

Widget _app({required bool unlocked}) => ProviderScope(
      overrides: [
        unlockedProvider.overrideWith((ref) async => unlocked),
        lapCountProvider(kStageFirst).overrideWith((ref) async => 0),
        lapCountProvider(kStageSecond).overrideWith((ref) async => 0),
      ],
      child: const MaterialApp(home: StartScreen()),
    );

void main() {
  testWidgets('trial: every stage card says so, and the code entry is offered',
      (tester) async {
    await tester.pumpWidget(_app(unlocked: false));
    await tester.pumpAndSettle();

    // Two cards, deliberately: First Stage and Second Stage are gated to the
    // same blocks, so they carry the same sentence — which is the wording the
    // client asked First Stage to adopt.
    expect(find.text('体験版：ブロック1〜2のみ学習可能'), findsNWidgets(2));
    expect(find.text('体験版：ブロック1〜2のみ視聴可能'), findsOneWidget);
    expect(find.text('2,201語の見出し語を絶対記憶に'), findsNothing);

    expect(find.text('アンロックコードをお持ちの方'), findsOneWidget);
  });

  testWidgets('unlocked: full subtitles, and no code prompt left over',
      (tester) async {
    await tester.pumpWidget(_app(unlocked: true));
    await tester.pumpAndSettle();

    expect(find.text('2,201語の見出し語を絶対記憶に'), findsOneWidget);
    expect(find.text('派生・類義・反意・活用ドリル'), findsOneWidget);
    expect(find.textContaining('体験版'), findsNothing);

    expect(find.text('アンロックコードをお持ちの方'), findsNothing);
  });
}
