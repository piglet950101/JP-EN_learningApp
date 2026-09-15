// Trial UnlockVerifier — round-trip and adversarial checks.
//
// The verifier's payload layout must match generate_codes.py exactly:
//   payload (5 B) = purchase_id (4 B BE) || key_version (1 B)
//   code (10 B)   = payload || HMAC-SHA256(key, payload)[:5]
//   string        = base32(code).strip('=')   → 16 chars, dashed as XXXX-…
//
// The key is read from UnlockSecrets at run time rather than pasted in. It
// used to be pasted in — the v1 XOR fragments were copied into this file, a
// third published copy alongside _secret.dart and generate_codes.py, in a
// public repository. Deriving it instead means this file carries no secret
// and keeps working across a key rotation.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: implementation_imports — the test needs the key the app compiles in.
import 'package:kaitan/data/trial/_secret.dart';
import 'package:kaitan/data/trial/unlock_verifier.dart';

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

String makeCode(int purchaseId, {int? keyVersion}) {
  final version = keyVersion ?? UnlockSecrets.currentVersion;
  final payload = Uint8List(5)
    ..[0] = (purchaseId >> 24) & 0xff
    ..[1] = (purchaseId >> 16) & 0xff
    ..[2] = (purchaseId >> 8) & 0xff
    ..[3] = purchaseId & 0xff
    ..[4] = version & 0xff;
  final key = UnlockSecrets.keyForVersion(version);
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
    expect(d.keyVersion, UnlockSecrets.currentVersion);
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
    // A version the build does not carry. This is the mechanism that makes a
    // rotation bite: every code minted under v1 now lands here, because the
    // v1 key was public and had to be retired (2026-09-15).
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
