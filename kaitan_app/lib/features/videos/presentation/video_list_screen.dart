// Video list — 46 block-解説 videos in block order.
//
// Each card shows the block number, title, duration (if known) and a
// small connectivity-warning banner up top when the device is offline.

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../data/video.dart';

/// Trial mode allows the user to watch the first 2 blocks' videos as a
/// sample; blocks 3-46 stay locked behind an unlock code (spec 2026-08-04 ②).
const int _kTrialAccessibleBlockMax = 2;

final _connectivityProvider = StreamProvider<List<ConnectivityResult>>(
  (ref) => Connectivity().onConnectivityChanged,
);

class VideoListScreen extends ConsumerWidget {
  const VideoListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(videoRepoProvider);
    final connectivityAsync = ref.watch(_connectivityProvider);
    final isOnline = connectivityAsync.maybeWhen(
      data: (results) => results.any((r) => r != ConnectivityResult.none),
      orElse: () => true, // optimistic when unknown
    );
    final isUnlocked = ref.watch(unlockedProvider).maybeWhen(
          data: (v) => v,
          orElse: () => false,
        );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('ビデオ解説'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF2b6cb0),
        elevation: 0,
      ),
      body: videosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('動画一覧の読込エラー: $e')),
        data: (repo) {
          if (repo.count == 0) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('ビデオはまだ登録されていません。',
                    style: TextStyle(color: Colors.black54)),
              ),
            );
          }
          return Column(
            children: [
              if (!isOnline) const _OfflineBanner(),
              if (!isUnlocked) const _TrialBanner(),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  itemCount: repo.all.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final v = repo.all[i];
                    final accessible =
                        isUnlocked || v.block <= _kTrialAccessibleBlockMax;
                    return _VideoCard(
                      video: v,
                      isOnline: isOnline,
                      accessible: accessible,
                      onTap: !isOnline
                          ? null
                          : accessible
                              ? () => context.push('/videos/${v.block}')
                              : () => context.push('/unlock'),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _TrialBanner extends StatelessWidget {
  const _TrialBanner();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFE6F4FF),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: const [
            Icon(Icons.info_outline_rounded, color: Color(0xFF2b6cb0), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '体験版：ブロック1〜2のみ視聴できます。他ブロックはコード入力で解放されます。',
                style: TextStyle(fontSize: 13, color: Color(0xFF1A365D)),
              ),
            ),
          ],
        ),
      );
}

class _OfflineBanner extends StatelessWidget {
  const _OfflineBanner();
  @override
  Widget build(BuildContext context) => Container(
        color: const Color(0xFFFFF5E6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: const [
            Icon(Icons.wifi_off_rounded, color: Color(0xFFDD6B20), size: 20),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                '動画の再生にはインターネット接続が必要です。',
                style: TextStyle(fontSize: 13, color: Color(0xFF7B341E)),
              ),
            ),
          ],
        ),
      );
}

class _VideoCard extends StatelessWidget {
  final VideoEntry video;
  final bool isOnline;
  final bool accessible;
  final VoidCallback? onTap;
  const _VideoCard({
    required this.video,
    required this.isOnline,
    required this.accessible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color bg = !accessible
        ? const Color(0xFFF5F5F5)
        : Colors.white;
    final Color iconBg = !accessible
        ? const Color(0xFFCBD5E0)
        : (isOnline ? const Color(0xFF2b6cb0) : const Color(0xFFCBD5E0));
    final IconData iconData = !accessible
        ? Icons.lock_outline_rounded
        : (isOnline ? Icons.play_arrow_rounded : Icons.wifi_off_rounded);
    return Material(
      color: bg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(iconData, color: Colors.white, size: 32),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(video.title,
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: accessible
                                ? Colors.black87
                                : Colors.black45)),
                    const SizedBox(height: 4),
                    Text(
                      accessible
                          ? '№ ${video.firstWordId ?? '?'}〜${video.lastWordId ?? '?'}'
                              '${video.durationLabel.isNotEmpty ? " ・ ${video.durationLabel}" : ""}'
                          : 'アンロックで視聴可能',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Icon(
                accessible
                    ? Icons.chevron_right
                    : Icons.lock_outline_rounded,
                color: const Color(0xFF2b6cb0),
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
