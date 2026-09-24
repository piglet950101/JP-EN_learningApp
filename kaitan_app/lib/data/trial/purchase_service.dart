// The in-app purchase path to a full unlock.
//
// Why this exists: App Store Review Guideline 3.1.1 forbids unlocking app
// features with "license keys", and names them explicitly. 快単's whole
// distribution model is a code printed on a card in a 教材セット, so on the
// face of it the app is exactly what that rule prohibits.
//
// The exemption is 3.1.4:
//
//   "App features that work in combination with an approved physical product
//    (such as a toy) on an optional basis may unlock functionality without
//    using in-app purchase, PROVIDED THAT AN IN-APP PURCHASE OPTION IS
//    AVAILABLE AS WELL."
//
// 快単 ships with three physical 単語集 carrying the same 2,267-word corpus,
// and blocks 1-2 work standalone, so the pairing is optional and the books
// are not "unrelated products". The one condition is the clause in capitals:
// the same unlock has to be buyable inside the app. That is this file.
//
// Google Play needs none of it — Play explicitly permits a consumption-only
// app — so the buy button is shown on iOS only (see showIapProvider). The
// plugin still compiles into the Android build; it simply goes unused.
//
// The price must be a real one. 菊地様 set it at ¥29,800 on 2026-09-15, which
// is the app's own line in his 教材セット breakdown (アプリ 27,090円 税別).
// A deterrent price nobody could buy is the gaming reviewers look for.

import 'dart:async';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

import 'package:in_app_purchase/in_app_purchase.dart';

/// The non-consumable product that unlocks every block.
///
/// This exact string has to be created in App Store Connect as a
/// NON-CONSUMABLE in-app purchase before any build can sell anything. Until
/// it exists, [PurchaseService.loadProduct] returns null and the UI simply
/// hides the button — which is the state today, since KAI's Apple
/// organisation enrolment is still pending.
const String kUnlockProductId = 'jp.or.kai.kaitan.unlock_all';

/// What a purchase attempt did, in terms the UI can act on.
enum PurchaseOutcome {
  /// Bought or restored — the caller should record the unlock.
  unlocked,

  /// Awaiting an external step (Ask to Buy, SCA, a slow payment sheet).
  /// Not an error: the result arrives later on the same stream.
  pending,

  /// The user backed out. Say nothing.
  cancelled,

  /// Anything else. The UI shows one generic line.
  failed,
}

class PurchaseUpdate {
  const PurchaseUpdate(this.outcome, {this.receiptHash});

  final PurchaseOutcome outcome;

  /// A short marker stored alongside the unlock for audit, mirroring what the
  /// code path keeps. Never the raw receipt.
  final String? receiptHash;
}

class PurchaseService {
  PurchaseService({InAppPurchase? iap, this.onUnlocked})
      : _iap = iap ?? InAppPurchase.instance;

  final InAppPurchase _iap;

  /// Saves the unlock for a purchased or restored transaction.
  ///
  /// Called BEFORE the transaction is finished, and from the service rather
  /// than a screen: a purchase can complete when no purchase screen is open
  /// (Ask to Buy approved later, a slow payment, a transaction left over from
  /// the last run), and StoreKit never redelivers a finished transaction.
  /// Throwing leaves the transaction unfinished, so it is delivered again on
  /// the next launch.
  final Future<void> Function(String marker)? onUnlocked;
  StreamSubscription<List<PurchaseDetails>>? _sub;
  final _controller = StreamController<PurchaseUpdate>.broadcast();

  /// Purchase results, including ones that arrive long after `buy()` returned
  /// (a pending konbini-style payment, or a restore on a fresh device).
  Stream<PurchaseUpdate> get updates => _controller.stream;

  /// Begin listening. Safe to call more than once.
  void start() {
    _sub ??= _iap.purchaseStream.listen(
      _onPurchases,
      onError: (_) => _controller.add(
          const PurchaseUpdate(PurchaseOutcome.failed)),
    );
  }

  Future<void> dispose() async {
    await _sub?.cancel();
    _sub = null;
    await _controller.close();
  }

  /// Whether the store is reachable at all. False on a device with purchases
  /// disabled, and false on Android where we never offer the button.
  Future<bool> isAvailable() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return false;
    try {
      return await _iap.isAvailable();
    } catch (_) {
      return false;
    }
  }

  /// The product as the store describes it — crucially [ProductDetails.price]
  /// is already localised and tax-inclusive, so the UI must show THAT rather
  /// than a hardcoded ¥29,800. Null when the product is not configured yet,
  /// which is not an error condition.
  Future<ProductDetails?> loadProduct() async {
    if (!await isAvailable()) return null;
    try {
      final resp = await _iap.queryProductDetails({kUnlockProductId});
      if (resp.productDetails.isEmpty) return null;
      return resp.productDetails.first;
    } catch (_) {
      return null;
    }
  }

  /// Start a purchase. The outcome arrives on [updates], not here — StoreKit
  /// can take minutes, or resume after the app is killed.
  Future<void> buy(ProductDetails product) async {
    start();
    await _iap.buyNonConsumable(
        purchaseParam: PurchaseParam(productDetails: product));
  }

  /// Apple requires a visible restore control for non-consumables; an app
  /// without one is rejected even when buying works.
  Future<void> restore() async {
    start();
    await _iap.restorePurchases();
  }

  Future<void> _onPurchases(List<PurchaseDetails> purchases) async {
    for (final p in purchases) {
      var finish = true;
      switch (p.status) {
        case PurchaseStatus.pending:
          _controller.add(const PurchaseUpdate(PurchaseOutcome.pending));
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          if (p.productID != kUnlockProductId) break;
          final marker = _marker(p);
          try {
            await onUnlocked?.call(marker);
          } catch (_) {
            // Not saved. Leave the transaction unfinished: StoreKit delivers
            // it again on the next launch, and that is the retry.
            finish = false;
            _controller.add(const PurchaseUpdate(PurchaseOutcome.failed));
            break;
          }
          _controller.add(
              PurchaseUpdate(PurchaseOutcome.unlocked, receiptHash: marker));
          break;

        case PurchaseStatus.canceled:
          _controller.add(const PurchaseUpdate(PurchaseOutcome.cancelled));
          break;

        case PurchaseStatus.error:
          _controller.add(const PurchaseUpdate(PurchaseOutcome.failed));
          break;
      }

      // Every purchase must be completed or StoreKit redelivers it on every
      // launch, forever. This is outside the switch deliberately: it applies
      // to errors and cancellations too, and skipping it is the single most
      // common way an IAP integration breaks in the field.
      if (finish && p.pendingCompletePurchase) {
        try {
          await _iap.completePurchase(p);
        } catch (_) {
          // Nothing useful to do; the next launch retries.
        }
      }
    }
  }

  /// A short, non-reversible marker for the audit column. The unlock itself
  /// is local and permanent either way, so this is for support questions
  /// ("which purchase unlocked this device?"), not for verification.
  static String _marker(PurchaseDetails p) {
    final id = p.purchaseID ?? p.productID;
    final h = id.hashCode.toUnsigned(32).toRadixString(16).padLeft(8, '0');
    return 'iap:$h';
  }
}
