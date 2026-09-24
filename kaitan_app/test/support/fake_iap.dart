// A stand-in for the App Store connection, for tests that must drive purchase
// updates without a device.

import 'dart:async';

import 'package:in_app_purchase/in_app_purchase.dart';

class FakeIap implements InAppPurchase {
  final _stream = StreamController<List<PurchaseDetails>>.broadcast();

  /// Every transaction the service finished, in order.
  final completed = <PurchaseDetails>[];

  /// Called when a transaction is finished, so tests can record ordering.
  void Function()? onComplete;

  void push(List<PurchaseDetails> purchases) => _stream.add(purchases);

  @override
  Stream<List<PurchaseDetails>> get purchaseStream => _stream.stream;

  @override
  Future<void> completePurchase(PurchaseDetails purchase) async {
    completed.add(purchase);
    onComplete?.call();
  }

  @override
  Future<bool> isAvailable() async => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PurchaseDetails fakePurchase(PurchaseStatus status,
    {String productId = 'jp.or.kai.kaitan.unlock_all', String id = 'tx-1'}) {
  return PurchaseDetails(
    purchaseID: id,
    productID: productId,
    verificationData: PurchaseVerificationData(
      localVerificationData: '',
      serverVerificationData: '',
      source: 'test',
    ),
    transactionDate: '0',
    status: status,
  )..pendingCompletePurchase = true;
}

/// Lets queued stream events and the awaits they trigger run to completion.
Future<void> settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}
