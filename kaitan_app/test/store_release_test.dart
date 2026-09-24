// Store-release guards: the things App Review and Play review check that no
// other test in the project would notice breaking.
//
//   * Guideline 5.1.1(i): the privacy policy is reachable inside the app.
//   * Guideline 3.1.1 / 3.1.4: an iOS build accepts only codes that come with
//     the physical set; codes sold on their own are refused there.
//   * Guideline 2.3.10: nothing an iOS user can read names another platform.
//   * Anti-steering (both stores): nothing in the app leads to a purchase
//     outside it.
//   * iPhone only for this release: no iPad screenshots were prepared, and
//     the layout has never been checked on an iPad.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:kaitan/core/providers.dart';
import 'package:kaitan/data/progress/progress_repository.dart';
import 'package:kaitan/data/trial/code_series.dart';
import 'package:kaitan/data/trial/unlock_verifier.dart';
import 'package:kaitan/features/legal/privacy_policy_screen.dart';
import 'package:kaitan/features/legal/privacy_policy_text.dart';
import 'package:kaitan/features/start/start_screen.dart';
import 'package:kaitan/features/trial/presentation/unlock_screen.dart';

import 'trial_unlock_test.dart' show makeCode;

String _wholePolicy() => [
      kPrivacyPolicyTitle,
      kPrivacyPolicyIntro,
      for (final s in kPrivacyPolicySections) ...[s.heading, s.body],
      kPrivacyPolicyEnacted,
    ].join('\n');

Widget _unlockScreen({required bool standaloneAccepted}) => ProviderScope(
      overrides: [
        showIapProvider.overrideWithValue(false),
        standaloneCodesAcceptedProvider.overrideWithValue(standaloneAccepted),
      ],
      child: const MaterialApp(home: UnlockScreen()),
    );

void main() {
  group('privacy policy (Guideline 5.1.1(i))', () {
    testWidgets('the start screen links to it, and the link opens it',
        (tester) async {
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (c, s) => const StartScreen()),
        GoRoute(
            path: '/privacy',
            builder: (c, s) => const PrivacyPolicyScreen()),
      ]);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          unlockedProvider.overrideWith((ref) async => true),
          lapCountProvider(kStageFirst).overrideWith((ref) async => 0),
          lapCountProvider(kStageSecond).overrideWith((ref) async => 0),
        ],
        child: MaterialApp.router(routerConfig: router),
      ));
      await tester.pumpAndSettle();

      final link = find.text('プライバシーポリシー');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      expect(find.textContaining('一般社団法人KAI'), findsWidgets);
    });

    testWidgets('the policy is reachable for a trial user too',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          unlockedProvider.overrideWith((ref) async => false),
          lapCountProvider(kStageFirst).overrideWith((ref) async => 0),
          lapCountProvider(kStageSecond).overrideWith((ref) async => 0),
        ],
        child: const MaterialApp(home: StartScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('プライバシーポリシー'), findsOneWidget);
    });

    test('names both the app and the developer (Google requires one)', () {
      final p = _wholePolicy();
      expect(p, contains('快単パーフェクト'));
      expect(p, contains('一般社団法人KAI'));
    });

    test('contains no link out of the app', () {
      // A bundled policy exists partly so it cannot become a route to the
      // website, and from there to a page that sells codes.
      final p = _wholePolicy();
      for (final s in ['http', 'www.', '.jp', '.com', '@']) {
        expect(p, isNot(contains(s)), reason: 'found "$s"');
      }
    });

    test('names no mobile platform or store (Guideline 2.3.10)', () {
      final p = _wholePolicy();
      for (final s in [
        'Android', 'Google', 'iPhone', 'iPad', 'iOS', 'Apple',
        'App Store', 'Play', 'アンドロイド', 'アイフォン',
      ]) {
        expect(p, isNot(contains(s)), reason: 'found "$s"');
      }
    });

    test('mentions no price or place to buy (anti-steering)', () {
      final p = _wholePolicy();
      for (final s in ['円', '価格', 'ショップ', '販売', 'お求め']) {
        expect(p, isNot(contains(s)), reason: 'found "$s"');
      }
    });
  });

  group('code series (Guidelines 3.1.1 / 3.1.4)', () {
    const verifier = UnlockVerifier();

    test('a set code unlocks everywhere', () {
      final d = verifier.verify(makeCode(12));
      expect(unlockRejection(d, standaloneAccepted: false), isNull);
      expect(unlockRejection(d, standaloneAccepted: true), isNull);
    });

    test('a standalone code unlocks only where standalone codes are accepted',
        () {
      final d = verifier.verify(makeCode(kStandaloneSeriesFirstId));
      expect(d.ok, isTrue, reason: 'it is a genuine code');
      expect(unlockRejection(d, standaloneAccepted: true), isNull);
      expect(unlockRejection(d, standaloneAccepted: false),
          kCodeNotForThisDeviceMessage);
    });

    test('the boundary is exact', () {
      final below = verifier.verify(makeCode(kStandaloneSeriesFirstId - 1));
      expect(unlockRejection(below, standaloneAccepted: false), isNull);
    });

    test('an invalid code still reads as invalid on every build', () {
      final d = verifier.verify('AAAA-AAAA-AAAA-AAAA');
      expect(unlockRejection(d, standaloneAccepted: false), kCodeInvalidMessage);
      expect(unlockRejection(d, standaloneAccepted: true), kCodeInvalidMessage);
    });

    test('the refusal names no other platform (Guideline 2.3.10)', () {
      for (final s in ['Android', 'Google', 'アンドロイド']) {
        expect(kCodeNotForThisDeviceMessage, isNot(contains(s)));
      }
    });

    test('the generator numbers the standalone series from the same id', () {
      // tool/generate_codes.py is not shipped in every copy of this project.
      final f = File('tool/generate_codes.py');
      if (!f.existsSync()) {
        markTestSkipped('tool/generate_codes.py is not in this copy');
        return;
      }
      final m = RegExp(r'^STANDALONE_FIRST_ID\s*=\s*([\d_]+)', multiLine: true)
          .firstMatch(f.readAsStringSync());
      expect(m, isNotNull, reason: 'STANDALONE_FIRST_ID not found');
      expect(int.parse(m!.group(1)!.replaceAll('_', '')),
          kStandaloneSeriesFirstId);
    });
  });

  group('unlock screen', () {
    testWidgets('a set-only build says where its codes come from',
        (tester) async {
      await tester.pumpWidget(_unlockScreen(standaloneAccepted: false));
      await tester.pump();
      expect(find.text('教材セットに付属のアンロックコードを入力してください。'),
          findsOneWidget);
      expect(find.textContaining('ご購入時'), findsNothing);
    });

    testWidgets('a build that takes both keeps the general wording',
        (tester) async {
      await tester.pumpWidget(_unlockScreen(standaloneAccepted: true));
      await tester.pump();
      expect(find.text('ご購入時にお渡ししたアンロックコードを入力してください。'),
          findsOneWidget);
    });

    testWidgets('a standalone code is refused on a set-only build',
        (tester) async {
      await tester.pumpWidget(_unlockScreen(standaloneAccepted: false));
      await tester.pump();
      await tester.enterText(
          find.byType(TextField), makeCode(kStandaloneSeriesFirstId + 7));
      await tester.tap(find.text('アンロック'));
      await tester.pump();
      expect(find.text(kCodeNotForThisDeviceMessage), findsOneWidget);
    });
  });

  test('iPhone only: no build configuration targets iPad', () {
    // Turning iPad on commits the listing to a 13-inch iPad screenshot set and
    // puts an untested layout in front of App Review. Do it deliberately.
    final pbx =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbx, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')));
    expect(RegExp(r'TARGETED_DEVICE_FAMILY = 1;').allMatches(pbx).length, 3);
  });
}
