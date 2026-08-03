// UnlockVerifier — validates a purchase-issued unlock code.
//
// Code layout (v1, compact 16-char form; plan §3.2):
//   payload      = purchase_id (4 B, big-endian) || key_version (1 B) = 5 B
//   mac          = HMAC-SHA256(secret_for_version, payload)[:5]  = 5 B
//   code_bytes   = payload || mac                                = 10 B
//   code_string  = base32(code_bytes).stripPadding()             = 16 chars
//                  formatted as XXXX-XXXX-XXXX-XXXX
//
// Verification steps mirror the layout in reverse. Constant-time byte
// comparison is used for the HMAC to avoid a timing side-channel — even
// though the attack model doesn't really include timing over a UI, it's
// cheap correctness.

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '_secret.dart';

class UnlockDecision {
  final bool ok;
  final int? purchaseId;
  final int? keyVersion;
  final String? codeHash;
  final String? reason;
  const UnlockDecision._(
      this.ok, this.purchaseId, this.keyVersion, this.codeHash, this.reason);

  const UnlockDecision.fail(String reason)
      : this._(false, null, null, null, reason);
  const UnlockDecision.pass(
      {required int purchaseId, required int keyVersion, required String codeHash})
      : this._(true, purchaseId, keyVersion, codeHash, null);
}

class UnlockVerifier {
  const UnlockVerifier();

  static const int codeCharLen = 16; // after strip('-'), before base32-decode

  UnlockDecision verify(String userInput) {
    final normalized = _normalize(userInput);
    if (normalized.length != codeCharLen) {
      return const UnlockDecision.fail('length');
    }
    final Uint8List bytes;
    try {
      bytes = _base32Decode(normalized);
    } on FormatException {
      return const UnlockDecision.fail('base32');
    }
    if (bytes.length != 10) {
      return const UnlockDecision.fail('bytes');
    }
    final payload = Uint8List.sublistView(bytes, 0, 5);
    final mac = Uint8List.sublistView(bytes, 5, 10);
    final purchaseId = _readUint32BE(payload, 0);
    final keyVersion = payload[4];
    final Uint8List key;
    try {
      key = UnlockSecrets.keyForVersion(keyVersion);
    } catch (_) {
      return const UnlockDecision.fail('key_version');
    }
    final expected = Hmac(sha256, key).convert(payload).bytes.sublist(0, 5);
    if (!_constantTimeEq(expected, mac)) {
      return const UnlockDecision.fail('mac');
    }
    final codeHash = base64Url.encode(bytes).substring(0, 12);
    return UnlockDecision.pass(
      purchaseId: purchaseId,
      keyVersion: keyVersion,
      codeHash: codeHash,
    );
  }

  // ── helpers ────────────────────────────────────────────────────────

  String _normalize(String s) =>
      s.replaceAll(RegExp(r'[\s\-]'), '').toUpperCase();

  bool _constantTimeEq(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  int _readUint32BE(Uint8List b, int off) =>
      (b[off] << 24) | (b[off + 1] << 16) | (b[off + 2] << 8) | b[off + 3];

  // RFC 4648 base32 alphabet.
  static const String _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  Uint8List _base32Decode(String s) {
    // Ambiguity-friendly: map user-common typos to canonical alphabet.
    final canon = s
        .replaceAll('0', 'O')
        .replaceAll('1', 'I')
        .replaceAll('8', 'B');
    var buffer = 0;
    var bits = 0;
    final out = <int>[];
    for (final c in canon.codeUnits) {
      final idx = _alphabet.codeUnits.indexOf(c);
      if (idx < 0) {
        throw const FormatException('invalid base32 char');
      }
      buffer = (buffer << 5) | idx;
      bits += 5;
      if (bits >= 8) {
        bits -= 8;
        out.add((buffer >> bits) & 0xff);
      }
    }
    return Uint8List.fromList(out);
  }
}
