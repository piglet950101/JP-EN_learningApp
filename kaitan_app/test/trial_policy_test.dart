// Trial-mode gating policy (client spec 2026-08-14):
// First Stage, Second Stage and the video list each expose blocks 1–2 only
// until a valid unlock code is entered.

import 'package:flutter_test/flutter_test.dart';

import 'package:kaitan/core/trial_policy.dart';

void main() {
  test('trial exposes exactly blocks 1-2', () {
    expect(kTrialBlockMax, 2);
    expect(trialBlockSet(), {1, 2});
  });

  test('locked user: blocks 1-2 allowed, 3+ blocked', () {
    for (final b in [1, 2]) {
      expect(trialAllowsBlock(b, isUnlocked: false), isTrue,
          reason: 'block $b must be free in trial');
    }
    for (final b in [3, 4, 23, 46, 47]) {
      expect(trialAllowsBlock(b, isUnlocked: false), isFalse,
          reason: 'block $b must be locked in trial');
    }
  });

  test('unlocked user: every block allowed, medical block 47 included', () {
    for (var b = 1; b <= 47; b++) {
      expect(trialAllowsBlock(b, isUnlocked: true), isTrue,
          reason: 'block $b must be open once unlocked');
    }
  });

  test('banner copy states the 1-2 range', () {
    expect(kTrialBannerLearn, contains('1〜2'));
    expect(kTrialBannerVideo, contains('1〜2'));
  });
}
