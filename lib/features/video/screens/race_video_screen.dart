import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/race_video.dart';
import '../providers/video_providers.dart';

class RaceVideoScreen extends ConsumerWidget {
  const RaceVideoScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final videosAsync = ref.watch(raceVideoListProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D1117),
        foregroundColor: Colors.white,
        title: const Text(
          '경주 동영상',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, size: 22),
            onPressed: () => ref.invalidate(raceVideoListProvider),
            tooltip: '새로고침',
          ),
        ],
      ),
      body: videosAsync.when(
        data: (videos) {
          if (videos.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.videocam_off_rounded,
                      size: 56, color: Colors.white.withValues(alpha: 0.2)),
                  const SizedBox(height: 16),
                  Text('등록된 영상이 없습니다',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.5),
                          fontSize: 16)),
                ],
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            itemCount: videos.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) =>
                _VideoCard(video: videos[index]),
          );
        },
        loading: () => const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: Color(0xFFFBBF24)),
              SizedBox(height: 16),
              Text('영상 목록 로딩 중...',
                  style: TextStyle(color: Colors.white54, fontSize: 14)),
            ],
          ),
        ),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off_rounded,
                  size: 48,
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text('영상 목록을 불러올 수 없습니다',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.9),
                      fontSize: 16)),
              const SizedBox(height: 8),
              Text('$e',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 12),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => ref.invalidate(raceVideoListProvider),
                icon: const Icon(Icons.refresh, color: Color(0xFFFBBF24)),
                label: const Text('다시 시도',
                    style: TextStyle(color: Color(0xFFFBBF24))),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VideoCard extends StatelessWidget {
  final RaceVideo video;
  const _VideoCard({required this.video});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push('/video/player', extra: video),
      child: Container(
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildThumbnail(),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    video.title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _buildChip(video.venueName, const Color(0xFF3B82F6)),
                      const SizedBox(width: 6),
                      _buildChip('${video.raceNumber}R', const Color(0xFFFBBF24)),
                      const Spacer(),
                      Text(
                        video.date,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.4),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    return AspectRatio(
      aspectRatio: 16 / 9,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (video.thumbnailUrl.isNotEmpty)
            Image.network(
              video.thumbnailUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: const Color(0xFF21262D),
                child: Icon(Icons.videocam_rounded,
                    size: 48, color: Colors.white.withValues(alpha: 0.15)),
              ),
            )
          else
            Container(
              color: const Color(0xFF21262D),
              child: Icon(Icons.videocam_rounded,
                  size: 48, color: Colors.white.withValues(alpha: 0.15)),
            ),
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.6),
                ],
              ),
            ),
          ),
          Center(
            child: Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.9),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.3),
                    blurRadius: 16,
                    spreadRadius: 2,
                  ),
                ],
              ),
              child: const Icon(
                Icons.play_arrow_rounded,
                color: Color(0xFF0D1117),
                size: 32,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
