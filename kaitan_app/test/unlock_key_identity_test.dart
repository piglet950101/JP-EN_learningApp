// Fails the build if the wrong signing key is compiled in.
//
// This exists because of a trap in the setup. `tool/make_secret.py --init`
// mints a NEW random key and writes a perfectly valid _secret.dart. Everything
// downstream then passes: flutter analyze is clean, all tests are green, and a
// release build produces a working app — in which every unlock code printed on
// the physical cards is rejected, because they were signed with a different
// key. Nothing else in the project can tell the difference, since the other
// tests mint their codes with whatever key happens to be present.
//
// So the identity of the key is pinned here. A SHA-256 of 32 random bytes
// discloses nothing and cannot be reversed, but it makes "I ran --init because
// I did not have the key file" impossible to miss.
//
// If this test fails on a new machine, do NOT run --init. Get
// ~/.kaitan/codegen.key from the owner and run `python tool/make_secret.py`.

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

// ignore: implementation_imports — the test needs the key the app compiles in.
import 'package:kaitan/data/trial/_secret.dart';

/// SHA-256 of the production v2 signing key.
const String kExpectedKeyDigest =
    'ccdbc15a61493d5be1fbbf4470fc09f35833ed724ae96fa5be8c213dc4c1ddc1';

void main() {
  test('the compiled-in key is the production key', () {
    final key = UnlockSecrets.keyForVersion(UnlockSecrets.currentVersion);
    final digest = sha256.convert(key).toString();

    expect(digest, kExpectedKeyDigest,
        reason: 'The wrong signing key is compiled in.\n'
            'Codes issued to customers will NOT unlock this build.\n'
            'Most likely `tool/make_secret.py --init` was run without the '
            "owner's key file. Obtain ~/.kaitan/codegen.key and re-run "
            '`python tool/make_secret.py` (no --init).');
  });

  test('the key is 32 bytes and not a placeholder', () {
    final key = UnlockSecrets.keyForVersion(UnlockSecrets.currentVersion);
    expect(key.length, 32);
    expect(key.every((b) => b == key.first), isFalse,
        reason: 'key is a constant byte — placeholder, not a real key');
    expect(base64.encode(key).isNotEmpty, isTrue);
  });
}
