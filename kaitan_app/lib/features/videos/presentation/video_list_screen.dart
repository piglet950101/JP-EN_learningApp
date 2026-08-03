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
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 12),
                  itemCount: repo.all.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final v = repo.all[i];
                    return _VideoCard(
                      video: v,
                      isOnline: isOnline,
                      onTap: isOnline
                          ? () => context.push('/videos/${v.block}')
                          : null,
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
  final VoidCallback? onTap;
  const _VideoCard({
    required this.video,
    required this.isOnline,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
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
                  color: isOnline
                      ? const Color(0xFF2b6cb0)
                      : const Color(0xFFCBD5E0),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Icon(
                  isOnline
                      ? Icons.play_arrow_rounded
                      : Icons.wifi_off_rounded,
                  color: Colors.white,
                  size: 32,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(video.title,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text(
                      '№ ${video.firstWordId ?? '?'}〜${video.lastWordId ?? '?'}'
                      '${video.durationLabel.isNotEmpty ? " ・ ${video.durationLabel}" : ""}',
                      style: const TextStyle(
                          fontSize: 12, color: Colors.black54),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right,
                  color: Color(0xFF2b6cb0), size: 26),
            ],
          ),
        ),
      ),
    );
  }
}
