import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';
import '../../../models/race_video.dart';
import '../providers/video_providers.dart';

class VideoPlayerScreen extends ConsumerStatefulWidget {
  final RaceVideo video;
  const VideoPlayerScreen({super.key, required this.video});

  @override
  ConsumerState<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends ConsumerState<VideoPlayerScreen> {
  VideoPlayerController? _controller;
  String _selectedMode = 'F';
  bool _isLoading = true;
  String? _error;
  bool _showControls = true;

  static const _modes = [
    (code: 'F', label: '전체재생'),
    (code: 'M', label: '퇴피 후'),
    (code: 'S', label: '느린화면'),
  ];

  @override
  void initState() {
    super.initState();
    _loadVideo('F');
  }

  @override
  void dispose() {
    _controller?.dispose();
    SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _loadVideo(String mode) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _selectedMode = mode;
    });

    _controller?.dispose();
    _controller = null;

    final service = ref.read(kcycleVideoServiceProvider);
    final url = await service.fetchVideoUrl(widget.video, mode: mode);

    if (!mounted) return;

    if (url == null) {
      setState(() {
        _isLoading = false;
        _error = '영상 URL을 가져올 수 없습니다';
      });
      return;
    }

    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    try {
      await controller.initialize();
      if (!mounted) {
        controller.dispose();
        return;
      }

      setState(() {
        _controller = controller;
        _isLoading = false;
      });

      controller.addListener(_onVideoUpdate);
      controller.play();
    } catch (e) {
      if (!mounted) {
        controller.dispose();
        return;
      }
      setState(() {
        _isLoading = false;
        _error = '영상을 재생할 수 없습니다: $e';
      });
    }
  }

  void _onVideoUpdate() {
    if (mounted) setState(() {});
  }

  void _togglePlayPause() {
    final c = _controller;
    if (c == null) return;
    c.value.isPlaying ? c.pause() : c.play();
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  String _formatDuration(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Column(
          children: [
            _buildTopBar(),
            Expanded(child: _buildVideoArea()),
            _buildModeSelector(),
            if (_controller != null) _buildProgressBar(),
            _buildBottomControls(),
          ],
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      color: const Color(0xFF0D1117),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded,
                color: Colors.white, size: 20),
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text(
              widget.video.title,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoArea() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Color(0xFFFBBF24)),
            SizedBox(height: 16),
            Text('영상 로딩 중...',
                style: TextStyle(color: Colors.white54, fontSize: 14)),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline_rounded,
                  size: 48,
                  color: const Color(0xFFEF4444).withValues(alpha: 0.7)),
              const SizedBox(height: 16),
              Text(_error!,
                  style: const TextStyle(color: Colors.white70, fontSize: 14),
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              TextButton.icon(
                onPressed: () => _loadVideo(_selectedMode),
                icon: const Icon(Icons.refresh, color: Color(0xFFFBBF24)),
                label: const Text('다시 시도',
                    style: TextStyle(color: Color(0xFFFBBF24))),
              ),
            ],
          ),
        ),
      );
    }

    final c = _controller;
    if (c == null || !c.value.isInitialized) {
      return const SizedBox.shrink();
    }

    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Center(
            child: AspectRatio(
              aspectRatio: c.value.aspectRatio,
              child: VideoPlayer(c),
            ),
          ),
          Positioned(
            right: 8,
            bottom: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.55),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                '출처: 경륜경정총괄본부',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          if (_showControls)
            AnimatedOpacity(
              opacity: _showControls ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 200),
              child: GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    c.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF0D1117),
      child: Row(
        children: _modes.map((m) {
          final isSelected = _selectedMode == m.code;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (!isSelected) _loadVideo(m.code);
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? const Color(0xFFFBBF24).withValues(alpha: 0.15)
                      : Colors.white.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFFFBBF24).withValues(alpha: 0.5)
                        : Colors.white.withValues(alpha: 0.1),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  m.label,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFFFBBF24)
                        : Colors.white.withValues(alpha: 0.5),
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildProgressBar() {
    final c = _controller!;
    final position = c.value.position;
    final duration = c.value.duration;
    final progress = duration.inMilliseconds > 0
        ? position.inMilliseconds / duration.inMilliseconds
        : 0.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: const Color(0xFF0D1117),
      child: Column(
        children: [
          SliderTheme(
            data: SliderThemeData(
              trackHeight: 3,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
              activeTrackColor: const Color(0xFFFBBF24),
              inactiveTrackColor: Colors.white.withValues(alpha: 0.15),
              thumbColor: const Color(0xFFFBBF24),
            ),
            child: Slider(
              value: progress.clamp(0.0, 1.0),
              onChanged: (value) {
                final target = Duration(
                  milliseconds: (value * duration.inMilliseconds).round(),
                );
                c.seekTo(target);
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDuration(position),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
                Text(
                  _formatDuration(duration),
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomControls() {
    final c = _controller;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      color: const Color(0xFF0D1117),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _controlButton(
            Icons.replay_10_rounded,
            '10초 뒤로',
            onTap: () {
              if (c == null) return;
              final target = c.value.position - const Duration(seconds: 10);
              c.seekTo(target < Duration.zero ? Duration.zero : target);
            },
          ),
          _controlButton(
            c != null && c.value.isPlaying
                ? Icons.pause_circle_filled_rounded
                : Icons.play_circle_fill_rounded,
            c != null && c.value.isPlaying ? '일시정지' : '재생',
            size: 52,
            color: const Color(0xFFFBBF24),
            onTap: _togglePlayPause,
          ),
          _controlButton(
            Icons.forward_10_rounded,
            '10초 앞으로',
            onTap: () {
              if (c == null) return;
              final duration = c.value.duration;
              final target = c.value.position + const Duration(seconds: 10);
              c.seekTo(target > duration ? duration : target);
            },
          ),
        ],
      ),
    );
  }

  Widget _controlButton(
    IconData icon,
    String tooltip, {
    double size = 32,
    Color color = Colors.white,
    VoidCallback? onTap,
  }) {
    return IconButton(
      onPressed: onTap,
      icon: Icon(icon, size: size, color: color),
      tooltip: tooltip,
    );
  }
}
