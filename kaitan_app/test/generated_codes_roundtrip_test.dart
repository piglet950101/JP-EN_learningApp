// Verifies that the exact codes we generated via `tool/generate_codes.py`
// for the client's Alpha test round-trip through the on-device
// UnlockVerifier successfully. This is the strongest single-check that
// codes AKAME hands out will actually unlock the app.

import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/data/trial/unlock_verifier.dart';

void main() {
  const verifier = UnlockVerifier();

  // Codes generated on 2026-08-03 for client Alpha review (pid 6, 7, 8).
  const codes = <int, String>{
    6: 'AAAA-ABQB-SLYS-F4UC',
    7: 'AAAA-ABYB-KUB4-G2UI',
    8: 'AAAA-ACAB-MBYW-E6KZ',
  };

  for (final entry in codes.entries) {
    test('client Alpha code for purchase_id=${entry.key} verifies', () {
      final d = verifier.verify(entry.value);
      expect(d.ok, isTrue,
          reason: 'code ${entry.value} rejected: ${d.reason}');
      expect(d.purchaseId, entry.key);
      expect(d.keyVersion, 1);
    });
  }
}
