// Which unlock codes a build may accept.
//
// Codes normally ship inside the physical study set, and on iOS that pairing
// is the only reason a code field is allowed at all. App Review Guideline
// 3.1.1 bans unlocking features with license keys, and 3.1.4 exempts codes
// that work with a physical product, provided an in-app purchase is offered
// too. A code sold on its own, with no set, is not covered by that exemption.
//
// So codes sold on their own are issued from a reserved purchase_id range and
// accepted only by builds whose store permits a consumption-only app. The
// range check lives in the app, not in how codes are handed out, because that
// is what keeps the iOS review notes true: the iOS build accepts only codes
// that come with the set, plus the in-app purchase.
//
// The verifier stays platform-neutral. This file decides what a verified
// code is allowed to do on this build.

import 'unlock_verifier.dart';

/// First purchase_id of the series sold without the physical set.
///
/// Set codes are numbered upward from 1 by tool/generate_codes.py and will
/// never come near this. `generate_codes.py --standalone` numbers from here.
const int kStandaloneSeriesFirstId = 1000000;

bool isStandaloneSeries(int purchaseId) =>
    purchaseId >= kStandaloneSeriesFirstId;

/// Shown for a code that failed verification.
const String kCodeInvalidMessage = 'コードを確認してください。';

/// Shown on a set-only build for a valid code from the standalone series.
///
/// Deliberately names no other platform: Guideline 2.3.10 forbids mentioning
/// other mobile platforms inside an iOS app.
const String kCodeNotForThisDeviceMessage = 'このコードはこの端末ではご利用いただけません。';

/// The message to show for [decision], or null when the code may unlock.
///
/// [standaloneAccepted] is false on a build that accepts only codes that come
/// with the physical set.
String? unlockRejection(UnlockDecision decision,
    {required bool standaloneAccepted}) {
  if (!decision.ok) return kCodeInvalidMessage;
  if (!standaloneAccepted && isStandaloneSeries(decision.purchaseId!)) {
    return kCodeNotForThisDeviceMessage;
  }
  return null;
}
