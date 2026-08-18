// Trial-mode policy — single source of truth for what an un-unlocked
// (体験版) user may access.
//
// Client spec 2026-08-14: First Stage, Second Stage and the video list all
// expose blocks 1–2 only. Entering a valid unlock code lifts every gate.

/// Highest block number reachable without an unlock code, in every stage.
const int kTrialBlockMax = 2;

/// True when [block] is reachable given the current unlock state.
bool trialAllowsBlock(int block, {required bool isUnlocked}) =>
    isUnlocked || block <= kTrialBlockMax;

/// Set of block numbers a trial user may select, for grid gating.
Set<int> trialBlockSet() => {for (var b = 1; b <= kTrialBlockMax; b++) b};

/// Banner copy shown at the top of gated screens.
const String kTrialBannerLearn =
    '体験版：ブロック1〜2のみ学習できます。コード入力で全ブロックが解放されます。';
const String kTrialBannerVideo =
    '体験版：ブロック1〜2のみ視聴できます。コード入力で全ブロックが解放されます。';
