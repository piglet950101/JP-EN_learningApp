// Store-release guards: the things App Review and Play review check that no
// other test in the project would notice breaking.
//
//   * Guideline 5.1.1(i): the privacy policy is reachable inside the app, and
//     states retention and deletion.
//   * Guidelines 3.1.1 / 3.1.4: an iOS build accepts only codes that come with
//     the physical set, and tells a user without a code that the full app can
//     be bought in-app.
//   * Guideline 2.3.10: nothing an iOS user can read names another platform.
//   * Anti-steering (both stores): nothing in the app leads to a purchase
//     outside it.
//   * Upload validation: the iOS privacy manifest exists and is in the bundle.
//   * The policy's promise that data stays on the device holds on Android 12+.
//   * iPhone only for this release.

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/core/providers.dart';
import 'package:kaitan/core/trial_policy.dart';
import 'package:kaitan/data/progress/progress_repository.dart';
import 'package:kaitan/data/trial/code_series.dart';
import 'package:kaitan/data/trial/purchase_service.dart';
import 'package:kaitan/data/trial/unlock_verifier.dart';
import 'package:kaitan/features/legal/privacy_policy_screen.dart';
import 'package:kaitan/features/legal/privacy_policy_text.dart';
import 'package:kaitan/features/start/start_screen.dart';
import 'package:kaitan/features/trial/presentation/unlock_screen.dart';

import 'support/fake_iap.dart';
import 'trial_unlock_test.dart' show makeCode;

String _wholePolicy() => [
      kPrivacyPolicyTitle,
      kPrivacyPolicyIntro,
      for (final s in kPrivacyPolicySections) ...[s.heading, s.body],
      kPrivacyPolicyEnacted,
    ].join('\n');

List<Override> _startOverrides({required bool unlocked}) => [
      unlockedProvider.overrideWith((ref) async => unlocked),
      lapCountProvider(kStageFirst).overrideWith((ref) async => 0),
      lapCountProvider(kStageSecond).overrideWith((ref) async => 0),
    ];

Widget _unlockScreen({required bool iap}) => ProviderScope(
      overrides: [
        showIapProvider.overrideWithValue(iap),
        standaloneCodesAcceptedProvider.overrideWithValue(!iap),
        purchaseServiceProvider.overrideWithValue(PurchaseService(iap: FakeIap())),
      ],
      child: const MaterialApp(home: UnlockScreen()),
    );

void main() {
  group('privacy policy (Guideline 5.1.1(i))', () {
    testWidgets('the start screen links to it through the app\'s own router',
        (tester) async {
      // The real routerProvider, not a stand-in: removing the /privacy route
      // from the app must make this fail.
      await tester.pumpWidget(ProviderScope(
        overrides: _startOverrides(unlocked: true),
        child: Consumer(
          builder: (context, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(routerProvider)),
        ),
      ));
      await tester.pumpAndSettle();

      final link = find.text('プライバシーポリシー');
      await tester.ensureVisible(link);
      await tester.tap(link);
      await tester.pumpAndSettle();

      expect(find.byType(PrivacyPolicyScreen), findsOneWidget);
      expect(find.textContaining('一般社団法人KAI'), findsWidgets);
    });

    testWidgets('the link is there for a trial user too', (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: _startOverrides(unlocked: false),
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

    test('states retention and how the data is deleted', () {
      final p = _wholePolicy();
      expect(p, contains('保存期間'));
      expect(p, contains('削除'));
    });

    test('contains no link out of the app', () {
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

  group('platform defaults', () {
    // The providers read defaultTargetPlatform, so these exercise the real
    // defaults rather than an override.
    ProviderContainer containerFor(TargetPlatform p) {
      debugDefaultTargetPlatformOverride = p;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final c = ProviderContainer();
      addTearDown(c.dispose);
      return c;
    }

    test('iOS offers the purchase and refuses standalone codes', () {
      final c = containerFor(TargetPlatform.iOS);
      expect(c.read(showIapProvider), isTrue);
      expect(c.read(standaloneCodesAcceptedProvider), isFalse);
    });

    test('Android offers no purchase and accepts standalone codes', () {
      final c = containerFor(TargetPlatform.android);
      expect(c.read(showIapProvider), isFalse);
      expect(c.read(standaloneCodesAcceptedProvider), isTrue);
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
      await tester.pumpWidget(_unlockScreen(iap: true));
      await tester.pump();
      expect(find.text('教材セットに付属のアンロックコードを入力してください。'),
          findsOneWidget);
      expect(find.textContaining('ご購入時'), findsNothing);
    });

    testWidgets('a build that takes both keeps the general wording',
        (tester) async {
      await tester.pumpWidget(_unlockScreen(iap: false));
      await tester.pump();
      expect(find.text('ご購入時にお渡ししたアンロックコードを入力してください。'),
          findsOneWidget);
      expect(find.text('アンロックコード入力'), findsOneWidget);
    });

    testWidgets('a standalone code is refused on a set-only build',
        (tester) async {
      await tester.pumpWidget(_unlockScreen(iap: true));
      await tester.pump();
      await tester.enterText(
          find.byType(TextField), makeCode(kStandaloneSeriesFirstId + 7));
      await tester.tap(find.text('アンロック'));
      await tester.pump();
      expect(find.text(kCodeNotForThisDeviceMessage), findsOneWidget);
    });

    testWidgets('iOS: the purchase is named, and restore survives a product '
        'that failed to load', (tester) async {
      await tester.pumpWidget(_unlockScreen(iap: true));
      await tester.pumpAndSettle();
      expect(find.text('全機能の解放'), findsOneWidget);
      expect(find.textContaining('購入の復元'), findsOneWidget);
      expect(find.textContaining('アプリ内での購入をご利用いただけません'), findsOneWidget);
      expect(find.textContaining('購入やコード入力をしなくても'), findsOneWidget);
    });
  });

  group('iOS wording outside the unlock screen', () {
    testWidgets('the start screen offers the purchase, not only a code',
        (tester) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          ..._startOverrides(unlocked: false),
          showIapProvider.overrideWithValue(true),
        ],
        child: const MaterialApp(home: StartScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.text('全機能を解放する（購入・コード入力）'), findsOneWidget);
      expect(find.text('アンロックコードをお持ちの方'), findsNothing);
    });

    testWidgets('the iOS label adds no overflow on a narrow screen or at a '
        'large text size', (tester) async {
      // 320pt is an iPhone SE (1st gen) or any iPhone with Display Zoom;
      // 21/17 is iOS's largest standard text size before accessibility sizes.
      // Compared against the Android label on the same screen, so anything
      // the rest of the start screen does at these sizes cancels out.
      Future<int> overflowsWith({required bool iap}) async {
        var count = 0;
        final previous = FlutterError.onError;
        FlutterError.onError = (d) {
          if (d.exceptionAsString().contains('overflowed')) count++;
        };
        await tester.pumpWidget(ProviderScope(
          key: UniqueKey(),
          overrides: [
            ..._startOverrides(unlocked: false),
            showIapProvider.overrideWithValue(iap),
          ],
          child: const MaterialApp(home: StartScreen()),
        ));
        await tester.pumpAndSettle();
        FlutterError.onError = previous;
        return count;
      }

      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      for (final (width, scale) in [(320.0, 1.0), (375.0, 21 / 17)]) {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = scale;
        final android = await overflowsWith(iap: false);
        final ios = await overflowsWith(iap: true);
        expect(ios, android,
            reason: 'the iOS label overflows at ${width}pt, text scale $scale');
      }
    });

    test('the iOS trial banners name the in-app purchase', () {
      expect(kTrialBannerLearnIap, contains('アプリ内購入'));
      expect(kTrialBannerVideoIap, contains('アプリ内購入'));
      // Android wording is unchanged.
      expect(kTrialBannerLearn, isNot(contains('購入')));
      expect(kTrialBannerVideo, isNot(contains('購入')));
    });
  });

  group('platform manifests', () {
    test('iOS privacy manifest exists, declares the SQLite APIs, and ships',
        () {
      // App Store Connect refuses an upload (ITMS-91053) that uses
      // required-reason APIs without declaring them. The bundled SQLite calls
      // stat* (file timestamps) and statfs* (disk space).
      final m = File('ios/Runner/PrivacyInfo.xcprivacy').readAsStringSync();
      expect(m, contains('NSPrivacyAccessedAPICategoryFileTimestamp'));
      expect(m, contains('NSPrivacyAccessedAPICategoryDiskSpace'));
      expect(m, matches(RegExp(r'<key>NSPrivacyTracking</key>\s*<false/>')));
      // A manifest that is not in the Resources phase is not in the app.
      final pbx =
          File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
      expect(pbx, contains('PrivacyInfo.xcprivacy in Resources */,'));
    });

    test('Android excludes everything from backup AND device transfer', () {
      final manifest =
          File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(manifest,
          contains('android:dataExtractionRules="@xml/data_extraction_rules"'));
      final rules = File('android/app/src/main/res/xml/data_extraction_rules.xml')
          .readAsStringSync();
      for (final section in ['cloud-backup', 'device-transfer']) {
        final body = RegExp('<$section>(.*?)</$section>', dotAll: true)
            .firstMatch(rules)
            ?.group(1);
        expect(body, isNotNull, reason: '<$section> missing');
        expect(body, contains('<exclude domain="root" path="." />'));
      }
    });
  });

  test('iOS 15 minimum: the purchase plugin is StoreKit 2 only', () {
    // in_app_purchase_storekit registers its StoreKit 2 API only on iOS 15+.
    // Below that the purchase can never load, and Guideline 3.1.4 needs it.
    final pbx =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    final targets = RegExp(r'IPHONEOS_DEPLOYMENT_TARGET = ([\d.]+);')
        .allMatches(pbx)
        .map((m) => double.parse(m.group(1)!))
        .toList();
    expect(targets, isNotEmpty);
    for (final t in targets) {
      expect(t, greaterThanOrEqualTo(15.0));
    }
  });

  test('iPhone only: no build configuration targets iPad', () {
    final pbx =
        File('ios/Runner.xcodeproj/project.pbxproj').readAsStringSync();
    expect(pbx, isNot(contains('TARGETED_DEVICE_FAMILY = "1,2"')));
    expect(RegExp(r'TARGETED_DEVICE_FAMILY = 1;').allMatches(pbx).length, 3);
  });
}
