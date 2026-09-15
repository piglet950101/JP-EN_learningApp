// Two things, and the second is the point of the first.
//
// 1. A code produced the way tool/generate_codes.py produces one must verify
//    on device. This is the strongest single check that a code handed to a
//    customer actually unlocks the app.
//
// 2. The three codes issued to the client on 2026-08-03 must NOT verify any
//    more. They were signed with key version 1, whose key sat in this public
//    repository — in _secret.dart, in generate_codes.py, and in
//    trial_unlock_test.dart. Anyone could read it and mint unlimited codes
//    for a ¥29,800 product, with no server able to revoke them.
//
//    Rotating to v2 on 2026-09-15 is what closed that, and this file is the
//    proof it took. If these three ever pass again, the old key is back in
//    the build and every code minted from the leaked one works.
//
// Live codes are deliberately not pasted in here. The repository is public,
// and a valid code in a test file is a free copy of the product.

import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: implementation_imports — the test needs the key the app compiles in.
import 'package:kaitan/data/trial/_secret.dart';
import 'package:kaitan/data/trial/unlock_verifier.dart';

const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

String _base32NoPad(List<int> bytes) {
  var buffer = 0, bits = 0;
  final buf = StringBuffer();
  for (final b in bytes) {
    buffer = (buffer << 8) | b;
    bits += 8;
    while (bits >= 5) {
      bits -= 5;
      buf.write(_alphabet[(buffer >> bits) & 0x1f]);
    }
  }
  if (bits > 0) buf.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
  return buf.toString();
}

/// Mirrors tool/generate_codes.py byte for byte.
String mintCode(int purchaseId) {
  final version = UnlockSecrets.currentVersion;
  final payload = Uint8List(5)
    ..[0] = (purchaseId >> 24) & 0xff
    ..[1] = (purchaseId >> 16) & 0xff
    ..[2] = (purchaseId >> 8) & 0xff
    ..[3] = purchaseId & 0xff
    ..[4] = version & 0xff;
  final mac = Hmac(sha256, UnlockSecrets.keyForVersion(version))
      .convert(payload)
      .bytes
      .sublist(0, 5);
  final all = <int>[...payload, ...mac];
  final s = _base32NoPad(all);
  return [
    for (var i = 0; i < s.length; i += 4)
      s.substring(i, i + 4 > s.length ? s.length : i + 4)
  ].join('-');
}

void main() {
  const verifier = UnlockVerifier();

  for (final pid in [9, 10, 11, 250, 65535]) {
    test('a freshly minted code for purchase_id=$pid verifies', () {
      final code = mintCode(pid);
      final d = verifier.verify(code);
      expect(d.ok, isTrue, reason: 'code $code rejected: ${d.reason}');
      expect(d.purchaseId, pid);
      expect(d.keyVersion, UnlockSecrets.currentVersion);
    });
  }

  group('the leaked v1 key is retired', () {
    // Issued to the client 2026-08-03 under key version 1.
    const retired = <int, String>{
      6: 'AAAA-ABQB-SLYS-F4UC',
      7: 'AAAA-ABYB-KUB4-G2UI',
      8: 'AAAA-ACAB-MBYW-E6KZ',
    };

    for (final e in retired.entries) {
      test('code for purchase_id=${e.key} no longer unlocks', () {
        final d = verifier.verify(e.value);
        expect(d.ok, isFalse,
            reason: '${e.value} still verifies — the v1 key is back in the '
                'build, and every code minted from the leaked key works');
        expect(d.reason, 'key_version');
      });
    }
  });

  test('the build does not accept key version 1', () {
    expect(UnlockSecrets.currentVersion, greaterThan(1));
    expect(() => UnlockSecrets.keyForVersion(1), throwsStateError);
  });
}
