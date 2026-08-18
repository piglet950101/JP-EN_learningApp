// ②③ Range-select screen — 46-block grid.
// Colors per the v1.0 spec: 白(unlearned) / 青(selected) / 薄色(completed).
// Buttons: 「リセット」, 「vol.1全体」, 「vol.2全体」, 「スタート」, 「初回OKを除く」.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/trial_policy.dart';
import '../../data/block.dart';
import '../../data/progress/progress_repository.dart';

class RangeScreen extends ConsumerStatefulWidget {
  final String stage;
  const RangeScreen({super.key, this.stage = kStageFirst});

  @override
  ConsumerState<RangeScreen> createState() => _RangeScreenState();
}

class _RangeScreenState extends ConsumerState<RangeScreen> {
  final Set<int> _selected = <int>{};

  void _toggle(int no) {
    setState(() {
      if (_selected.contains(no)) {
        _selected.remove(no);
      } else {
        _selected.add(no);
      }
    });
  }

  void _selectVol(int vol, {Set<int>? enabledBlocks}) {
    setState(() {
      for (final b in blocksOfVol(vol)) {
        if (enabledBlocks != null && !enabledBlocks.contains(b.no)) continue;
        _selected.add(b.no);
      }
    });
  }

  Future<void> _reset() async {
    setState(() => _selected.clear());
    final stage = widget.stage;
    // Also clear persistence for the entire stage (acts as "demo reset").
    final repo = ref.read(progressRepoProvider);
    await repo.resetBlocks(
      stage,
      kAllBlocks.map((b) => b.no),
      (no) {
        final b = kAllBlocks.firstWhere((x) => x.no == no);
        return [for (var id = b.firstId; id <= b.lastId; id++) id];
      },
    );
    ref.invalidate(blockStatusesProvider(stage));
    ref.invalidate(lapCountProvider(stage));
  }

  Future<void> _start({required bool excludeFirstOk}) async {
    if (_selected.isEmpty) return;
    // Collect word IDs from selected blocks (in block order).
    final ids = <int>[];
    final sorted = _selected.toList()..sort();
    for (final no in sorted) {
      final b = kAllBlocks.firstWhere((x) => x.no == no);
      for (var id = b.firstId; id <= b.lastId; id++) {
        ids.add(id);
      }
    }
    // Second Stage: keep only headwords that carry at least 1 SS entry,
    // EXCEPT the vol.3 medical block (47) which is FS-style content and
    // has no SS entries by design — those must still be included.
    List<int> effectiveIds = ids;
    if (widget.stage == kStageSecond) {
      final ssRepo = await ref.read(secondStageRepoProvider.future);
      effectiveIds = ids
          .where((id) => id >= 2202 || ssRepo.hasEntriesForWord(id))
          .toList();
    }
    ref.read(pendingSessionArgsProvider.notifier).value = PendingSessionArgs(
      wordIds: effectiveIds,
      selectedBlocks: Set.of(sorted),
      excludeFirstOk: excludeFirstOk,
      stage: widget.stage,
    );
    // SessionScreen reads pendingSessionArgsProvider in initState.
    if (mounted) context.push('/session');
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.stage;
    final isSecond = stage == kStageSecond;
    final statusesAsync = ref.watch(blockStatusesProvider(stage));
    // For Second Stage, gray out blocks that have no SS entries (currently
    // covers exactly one: the medical block 47, which is FS-style content).
    final ssRepoAsync = ref.watch(secondStageRepoProvider);
    final isUnlocked = ref.watch(unlockedProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(isSecond
            ? '範囲指定 / Second Stage'
            : '範囲指定 / First Stage'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2b6cb0),
        elevation: 0,
      ),
      body: SafeArea(
        child: statusesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(child: Text('エラー: $e')),
          data: (statuses) {
            // Second Stage: only blocks that carry SS entries are selectable.
            final ssBlocks = isSecond
                ? ssRepoAsync.maybeWhen(
                    data: (r) => r.allBlocks().toSet(),
                    orElse: () => <int>{},
                  )
                : null;
            // Trial mode (client 2026-08-14): BOTH First and Second Stage
            // expose blocks 1..kTrialBlockMax only.
            final Set<int>? trialBlocks =
                isUnlocked ? null : trialBlockSet();
            // Intersect the two gates when both apply.
            Set<int>? effectiveEnabled;
            if (ssBlocks != null && trialBlocks != null) {
              effectiveEnabled = ssBlocks.intersection(trialBlocks);
            } else {
              effectiveEnabled = ssBlocks ?? trialBlocks;
            }
            return Column(
            children: [
              if (!isUnlocked) const _TrialRangeBanner(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _VolHeader(
                        title: '快単 vol.1（ブロック 1–23）',
                        onSelectAll: () => _selectVol(1, enabledBlocks: effectiveEnabled),
                      ),
                      _BlockGrid(
                        vol: 1,
                        selected: _selected,
                        statuses: statuses,
                        enabledBlocks: effectiveEnabled,
                        onTap: _toggle,
                      ),
                      const SizedBox(height: 8),
                      _VolHeader(
                        title: '快単 vol.2（ブロック 24–46）',
                        onSelectAll: () => _selectVol(2, enabledBlocks: effectiveEnabled),
                      ),
                      _BlockGrid(
                        vol: 2,
                        selected: _selected,
                        statuses: statuses,
                        enabledBlocks: effectiveEnabled,
                        onTap: _toggle,
                      ),
                      // vol.3 medical block (single block, only rendered for
                      // Second Stage — First Stage users reach it via the
                      // regular vol.1/2 grid; the medical block is added to
                      // Second Stage so learners see it inside the SS screen).
                      if (isSecond) ...[
                        const SizedBox(height: 8),
                        _VolHeader(
                          title: '快単 vol.3 医系（第47ブロック）',
                          onSelectAll: () => _selectVol(3),
                        ),
                        _BlockGrid(
                          vol: 3,
                          selected: _selected,
                          statuses: statuses,
                          // Medical block is FS-content in the SS screen;
                          // treat it as always enabled.
                          enabledBlocks: null,
                          onTap: _toggle,
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ),
              _Footer(
                selectedCount: _selected.length,
                wordsCount: _selectedWordsCount(),
                onReset: _reset,
                onStart: () => _start(excludeFirstOk: false),
                onExcludeFirstOk: () => _start(excludeFirstOk: true),
              ),
            ],
            );
          },
        ),
      ),
    );
  }

  int _selectedWordsCount() {
    var n = 0;
    for (final no in _selected) {
      final b = kAllBlocks.firstWhere((x) => x.no == no);
      n += b.count;
    }
    return n;
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────

class _TrialRangeBanner extends StatelessWidget {
  const _TrialRangeBanner();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFE6F4FF),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: const [
            Icon(Icons.info_outline_rounded,
                color: Color(0xFF2b6cb0), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                kTrialBannerLearn,
                style: TextStyle(fontSize: 13, color: Color(0xFF1A365D)),
              ),
            ),
          ],
        ),
      );
}

class _VolHeader extends StatelessWidget {
  final String title;
  final VoidCallback onSelectAll;
  const _VolHeader({required this.title, required this.onSelectAll});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 12, 4, 4),
        child: Row(
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF2b6cb0))),
            const Spacer(),
            TextButton(
              onPressed: onSelectAll,
              style: TextButton.styleFrom(minimumSize: const Size(0, 32)),
              child: const Text('全体選択', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      );
}

class _BlockGrid extends StatelessWidget {
  final int vol;
  final Set<int> selected;
  final Map<int, String> statuses;
  final Set<int>? enabledBlocks; // null = all enabled
  final void Function(int) onTap;
  const _BlockGrid({
    required this.vol,
    required this.selected,
    required this.statuses,
    required this.enabledBlocks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final blocks = blocksOfVol(vol);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: blocks.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 4,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
        childAspectRatio: 1.4,
      ),
      itemBuilder: (c, i) {
        final b = blocks[i];
        final isSel = selected.contains(b.no);
        final isDone = statuses[b.no] == 'completed';
        final isEnabled = enabledBlocks == null || enabledBlocks!.contains(b.no);
        Color bg;
        Color fg;
        BorderSide border;
        if (!isEnabled) {
          bg = const Color(0xFFF5F5F5);
          fg = Colors.black38;
          border = const BorderSide(color: Color(0xFFE0E0E0), width: 1);
        } else if (isSel) {
          bg = const Color(0xFF2b6cb0);
          fg = Colors.white;
          border = BorderSide.none;
        } else if (isDone) {
          bg = const Color(0xFFCBE6FF); // 薄い青 = 完了
          fg = const Color(0xFF1A365D);
          border = BorderSide.none;
        } else {
          bg = Colors.white;
          fg = Colors.black87;
          border = const BorderSide(color: Color(0xFFCBD5E0), width: 1);
        }
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: isEnabled ? () => onTap(b.no) : null,
          child: Container(
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(8),
              border: Border.fromBorderSide(border),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('${b.no}',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: fg)),
                const SizedBox(height: 2),
                Text('${b.firstId}–${b.lastId}',
                    style: TextStyle(fontSize: 11, color: fg.withValues(alpha: 0.85))),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  final int selectedCount;
  final int wordsCount;
  final VoidCallback onReset;
  final VoidCallback onStart;
  final VoidCallback onExcludeFirstOk;
  const _Footer({
    required this.selectedCount,
    required this.wordsCount,
    required this.onReset,
    required this.onStart,
    required this.onExcludeFirstOk,
  });

  @override
  Widget build(BuildContext context) {
    final hasSel = selectedCount > 0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('選択中: $selectedCountブロック / $wordsCount語',
                  style: const TextStyle(fontSize: 12, color: Colors.black54)),
              const Spacer(),
              TextButton(
                onPressed: onReset,
                child: const Text('リセット'),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: hasSel ? onExcludeFirstOk : null,
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('初回OKを除く',
                      style: TextStyle(
                          fontSize: 14, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: hasSel ? onStart : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF2b6cb0),
                    minimumSize: const Size(0, 56),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('スタート',
                      style: TextStyle(
                          fontSize: 18, fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
