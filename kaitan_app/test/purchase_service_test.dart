// The purchase service must save the unlock itself, before it finishes the
// transaction, with no screen involved. StoreKit never redelivers a finished
// transaction, so finishing one that was not saved means a customer who paid
// and stays locked.

import 'package:flutter_test/flutter_test.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import 'package:kaitan/data/trial/purchase_service.dart';

import 'support/fake_iap.dart';

void main() {
  test('a purchase is saved, then finished, with no screen listening', () async {
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

  test('a restore is saved the same way', () async {
    final iap = FakeIap();
    var saved = 0;
    final s = PurchaseService(iap: iap, onUnlocked: (_) async => saved++);
    s.start();

    iap.push([fakePurchase(PurchaseStatus.restored)]);
    await settle();

    expect(saved, 1);
    expect(iap.completed, hasLength(1));
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

  test('a cancelled purchase is finished without unlocking', () async {
    final iap = FakeIap();
    var saved = 0;
    final s = PurchaseService(iap: iap, onUnlocked: (_) async => saved++);
    s.start();

    iap.push([fakePurchase(PurchaseStatus.canceled)]);
    await settle();

    expect(saved, 0);
    expect(iap.completed, hasLength(1));
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
}
