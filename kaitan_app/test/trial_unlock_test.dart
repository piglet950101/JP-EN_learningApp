// Trial UnlockVerifier — round-trip and adversarial checks.
//
// The verifier's payload layout must match generate_codes.py exactly:
//   payload (5 B) = purchase_id (4 B BE) || key_version (1 B)
//   code (10 B)   = payload || HMAC-SHA256(key, payload)[:5]
//   string        = base32(code).strip('=')   → 16 chars, dashed as XXXX-…
//
// We can't call the Python generator from a Dart test, so we hand-generate
// codes using the exposed secret key XOR fragments (matches Dart layout).

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/data/trial/unlock_verifier.dart';

const String _fragA =
    '5c81a70bc94f2d0387b5610cbe9e8d5a3fa8c40b7d1e6a9002f38b57ec4d1a29';
const String _fragB =
    'a34f92c611080d7b9c40db26feb17109b7423e6c5f1a290187db4e1075acbf12';
const String _fragC =
    '9b204ec7ee9b3e784fa5b6d21c4f5f18e29b3705a6217a37c68b4bde01e0d16b';

Uint8List _hex(String s) {
  final out = Uint8List(s.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

Uint8List _secretV1() {
  final a = _hex(_fragA);
  final b = _hex(_fragB);
  final c = _hex(_fragC);
  final out = Uint8List(a.length);
  for (var i = 0; i < a.length; i++) {
    out[i] = a[i] ^ b[i] ^ c[i];
  }
  return out;
}

/// Base32 alphabet (RFC 4648).
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
  if (bits > 0) {
    buf.write(_alphabet[(buffer << (5 - bits)) & 0x1f]);
  }
  return buf.toString();
}

String _formatCode(String s) {
  final chunks = <String>[];
  for (var i = 0; i < s.length; i += 4) {
    chunks.add(s.substring(i, i + 4 > s.length ? s.length : i + 4));
  }
  return chunks.join('-');
}

String makeCode(int purchaseId, {int keyVersion = 1}) {
  final payload = Uint8List(5)
    ..[0] = (purchaseId >> 24) & 0xff
    ..[1] = (purchaseId >> 16) & 0xff
    ..[2] = (purchaseId >> 8) & 0xff
    ..[3] = purchaseId & 0xff
    ..[4] = keyVersion & 0xff;
  final key = _secretV1();
  final mac = Hmac(sha256, key).convert(payload).bytes.sublist(0, 5);
  final all = Uint8List.fromList([...payload, ...mac]);
  return _formatCode(_base32NoPad(all));
}

void main() {
  const verifier = UnlockVerifier();

  test('honestly-generated code with pid=1 verifies successfully', () {
    final code = makeCode(1);
    final d = verifier.verify(code);
    expect(d.ok, isTrue, reason: 'code=$code, reason=${d.reason}');
    expect(d.purchaseId, 1);
    expect(d.keyVersion, 1);
  });

  test('sample purchase ids all round-trip', () {
    for (final pid in [1, 2, 100, 65535, 1 << 20]) {
      final d = verifier.verify(makeCode(pid));
      expect(d.ok, isTrue, reason: 'pid=$pid failed');
      expect(d.purchaseId, pid);
    }
  });

  test('rejects wrong-length input', () {
    expect(verifier.verify('').ok, isFalse);
    expect(verifier.verify('ABCD').ok, isFalse);
    expect(
        verifier.verify('AAAA-AAAA-AAAA-AAAA-EXTRA-BITS').ok, isFalse);
  });

  test('rejects tampered MAC', () {
    final code = makeCode(42);
    // Flip the last non-dash character.
    final plain = code.replaceAll('-', '');
    final chars = plain.split('');
    chars[chars.length - 1] =
        chars.last == 'A' ? 'B' : 'A';
    final tampered = chars.join();
    final result = verifier.verify(tampered);
    expect(result.ok, isFalse);
    expect(result.reason, 'mac');
  });

  test('rejects unknown key version', () {
    // Build a valid-length code with key_version=99 (deliberately fake).
    final payload = Uint8List(5)
      ..[0] = 0
      ..[1] = 0
      ..[2] = 0
      ..[3] = 5
      ..[4] = 99;
    // Bogus MAC — key version rejection happens before HMAC check.
    final all = Uint8List.fromList([...payload, 0, 0, 0, 0, 0]);
    final code = _formatCode(_base32NoPad(all));
    final result = verifier.verify(code);
    expect(result.ok, isFalse);
    expect(result.reason, 'key_version');
  });

  test('dash and case normalisation', () {
    final code = makeCode(7);
    // Same code stripped of dashes should still verify.
    expect(verifier.verify(code.replaceAll('-', '')).ok, isTrue);
    // Lowercased should also verify.
    expect(verifier.verify(code.toLowerCase()).ok, isTrue);
  });

  test('codeHash is populated on success (audit trail)', () {
    final d = verifier.verify(makeCode(9));
    expect(d.ok, isTrue);
    expect(d.codeHash, isNotNull);
    expect(base64Url.decode(base64Url.normalize(d.codeHash!)).length,
        greaterThan(0));
  });
}
