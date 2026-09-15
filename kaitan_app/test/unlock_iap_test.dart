// The in-app purchase is an iOS-only addition, and that boundary is a promise
// made to the client in writing on 2026-09-14:
//
//   「Android：変更は一切不要です。今のままでストアに出せます。」
//
// Apple 3.1.4 requires the in-app option to exist beside the code; Google Play
// explicitly permits a consumption-only app, so Android keeps the code-only
// flow. If showIapProvider ever leaks true on Android, the client gets a
// purchase button he was told would not appear — and on a store that does not
// require it.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/core/providers.dart';
import 'package:kaitan/data/trial/purchase_service.dart';
import 'package:kaitan/features/trial/presentation/unlock_screen.dart';

void main() {
  testWidgets('code entry stands alone when the IAP is not offered',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [showIapProvider.overrideWithValue(false)],
      child: const MaterialApp(home: UnlockScreen()),
    ));
    await tester.pump();

    // The code path is intact...
    expect(find.text('アンロックコード入力'), findsOneWidget);
    expect(find.text('アンロック'), findsOneWidget);

    // ...and nothing about buying appears.
    expect(find.textContaining('アプリ内で購入'), findsNothing);
    expect(find.textContaining('購入の復元'), findsNothing);
    expect(find.text('または'), findsNothing);
  });

  test('the product id is the one that must exist in App Store Connect', () {
    // Hardcoded on purpose: this string has to match the NON-CONSUMABLE
    // created in App Store Connect exactly, and a silent rename would show up
    // only as "the button never appears" on a real device.
    expect(kUnlockProductId, 'jp.or.kai.kaitan.unlock_all');
  });

  test('every purchase outcome the UI must handle is enumerated', () {
    // A missed case in the switch means a purchase that never unlocks, or a
    // spinner that never stops. Pinning the set makes adding one deliberate.
    expect(PurchaseOutcome.values, [
      PurchaseOutcome.unlocked,
      PurchaseOutcome.pending,
      PurchaseOutcome.cancelled,
      PurchaseOutcome.failed,
    ]);
  });
}
