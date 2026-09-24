// The purchase service must save the unlock itself, before it finishes the
// transaction, with no screen involved. StoreKit never redelivers a finished
// transaction, so finishing one that was not saved means a customer who paid
// and stays locked.
//
// The fake store behaves like the shipped StoreKit 2 plugin: only `purchased`
// transactions need finishing, and each carries the transaction's JSON.

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:kaitan/core/providers.dart';
import 'package:kaitan/data/progress/progress_db.dart';
import 'package:kaitan/data/trial/purchase_service.dart';
import 'package:kaitan/main.dart';

import 'support/fake_iap.dart';

ProviderContainer _app(FakeIap iap, {bool iapUi = true}) => ProviderContainer(
      overrides: [
        showIapProvider.overrideWithValue(iapUi),
        inAppPurchaseProvider.overrideWithValue(iap),
        progressDbProvider.overrideWith((ref) {
          final db = ProgressDb.memory();
          ref.onDispose(db.close);
          return db;
        }),
      ],
    );

void main() {
  group('PurchaseService', () {
    test('a purchase is saved, then finished, with no screen listening',
        () async {
      final iap = FakeIap();
      final calls = <String>[];
      iap.onComplete = () => calls.add('finish');
      final s = PurchaseService(
          iap: iap, onUnlocked: (marker) async => calls.add('save $marker'));
      s.start();

      iap.push([fakePurchase(PurchaseStatus.purchased)]);
      await settle();

      expect(calls.length, 2);
      expect(calls[0], startsWith('save iap:'));
      expect(calls[1], 'finish');
    });

    test('a restore is saved (StoreKit 2 does not ask for it to be finished)',
        () async {
      final iap = FakeIap();
      var saved = 0;
      final s = PurchaseService(iap: iap, onUnlocked: (_) async => saved++);
      s.start();

      iap.push([fakePurchase(PurchaseStatus.restored)]);
      await settle();

      expect(saved, 1);
      expect(iap.completed, isEmpty);
    });

    test('if saving fails, the transaction is NOT finished', () async {
      final iap = FakeIap();
      final s = PurchaseService(
          iap: iap, onUnlocked: (_) async => throw StateError('disk full'));
      final outcomes = <PurchaseOutcome>[];
      s.updates.listen((u) => outcomes.add(u.outcome));
      s.start();

      iap.push([fakePurchase(PurchaseStatus.purchased)]);
      await settle();

      expect(iap.completed, isEmpty,
          reason: 'left unfinished so StoreKit delivers it again');
      expect(outcomes, [PurchaseOutcome.failed]);
    });

    test('a refunded or revoked transaction is finished but never unlocks',
        () async {
      final iap = FakeIap();
      var saved = 0;
      final s = PurchaseService(iap: iap, onUnlocked: (_) async => saved++);
      s.start();

      iap.push([
        fakePurchase(PurchaseStatus.purchased,
            json: '{"productId":"jp.or.kai.kaitan.unlock_all",'
                '"revocationDate":1758700000000,"revocationReason":0}')
      ]);
      await settle();

      expect(saved, 0);
      expect(iap.completed, hasLength(1));
    });

    test('a cancelled purchase does not unlock', () async {
      final iap = FakeIap();
      var saved = 0;
      final s = PurchaseService(iap: iap, onUnlocked: (_) async => saved++);
      s.start();

      iap.push([fakePurchase(PurchaseStatus.canceled)]);
      await settle();

      expect(saved, 0);
    });

    test('a purchase of some other product does not unlock', () async {
      final iap = FakeIap();
      var saved = 0;
      final s = PurchaseService(iap: iap, onUnlocked: (_) async => saved++);
      s.start();

      iap.push([fakePurchase(PurchaseStatus.purchased, productId: 'other')]);
      await settle();

      expect(saved, 0);
      expect(iap.completed, hasLength(1), reason: 'still finished');
    });
  });

  group('the app\'s own wiring', () {
    test('the real providers save a paid unlock and refresh the lock state',
        () async {
      final iap = FakeIap();
      final c = _app(iap);
      addTearDown(c.dispose);

      expect(await c.read(unlockedProvider.future), isFalse);
      c.read(purchaseServiceProvider).start();
      iap.push([fakePurchase(PurchaseStatus.purchased)]);
      await settle();

      expect(await c.read(unlockedProvider.future), isTrue);
      expect(iap.completed, hasLength(1));
    });

    testWidgets('the app listens from launch: a purchase that completes with '
        'no purchase screen open still unlocks', (tester) async {
      final iap = FakeIap();
      final c = _app(iap);
      addTearDown(c.dispose);

      await tester.pumpWidget(
          UncontrolledProviderScope(container: c, child: const KaitanApp()));
      await tester.pump();

      // Nothing has opened /unlock. Ask to Buy is approved now.
      iap.push([fakePurchase(PurchaseStatus.purchased)]);
      final unlocked = await tester.runAsync(() async {
        await settle();
        return c.read(unlockedProvider.future);
      });

      expect(unlocked, isTrue);
      expect(iap.completed, hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
