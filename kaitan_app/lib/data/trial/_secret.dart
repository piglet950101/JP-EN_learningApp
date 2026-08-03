// Trial unlock HMAC secret — mildly obfuscated. This is a *deterrent*, not
// a security boundary: any determined attacker can extract the key from the
// APK. Key rotation via `keyVersion` in the payload is the operational
// mitigation for a leaked key (v1.1 plan §3.6).
//
// The 32-byte v1 key is stored as three XOR'd hex fragments so a casual
// grep of the APK for a byte pattern doesn't reveal it directly.

import 'dart:convert';
import 'dart:typed_data';

class UnlockSecrets {
  UnlockSecrets._();

  // Byte-level obfuscation: raw XOR of three same-length hex strings.
  // Reproducing the key requires all three fragments + XOR order.
  static const _fragA =
      '5c81a70bc94f2d0387b5610cbe9e8d5a3fa8c40b7d1e6a9002f38b57ec4d1a29';
  static const _fragB =
      'a34f92c611080d7b9c40db26feb17109b7423e6c5f1a290187db4e1075acbf12';
  static const _fragC =
      '9b204ec7ee9b3e784fa5b6d21c4f5f18e29b3705a6217a37c68b4bde01e0d16b';

  static Uint8List keyForVersion(int version) {
    if (version != 1) {
      throw StateError('unknown unlock key version: $version');
    }
    return _xorFragments(_fragA, _fragB, _fragC);
  }

  static Uint8List _xorFragments(String a, String b, String c) {
    final ba = _hex(a);
    final bb = _hex(b);
    final bc = _hex(c);
    final out = Uint8List(ba.length);
    for (var i = 0; i < ba.length; i++) {
      out[i] = ba[i] ^ bb[i] ^ bc[i];
    }
    return out;
  }

  static Uint8List _hex(String s) {
    final out = Uint8List(s.length ~/ 2);
    for (var i = 0; i < out.length; i++) {
      out[i] = int.parse(s.substring(i * 2, i * 2 + 2), radix: 16);
    }
    return out;
  }
}

// Kept public only for the audit-trail HMAC recorded on unlock (`recordUnlock`).
String base64EncodeShort(List<int> bytes) => base64Url.encode(bytes).substring(0, 12);
