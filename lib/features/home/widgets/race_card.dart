import 'dart:async';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../models/race.dart';

class RaceCard extends StatefulWidget {
  final Race race;

  const RaceCard({super.key, required this.race});

  @override
  State<RaceCard> createState() => _RaceCardState();
}

class _RaceCardState extends State<RaceCard> {
  Timer? _timer;

  Race get race => widget.race;

  String get _raceTime {
    if (race.departureTime != null && race.departureTime!.isNotEmpty) {
      final dt = race.departureTime!.replaceAll('"', ':');
      if (dt.contains(':')) return dt;
      return race.departureTime!;
    }
    const times = [
      '10:00', '10:35', '11:10', '11:45',
      '12:20', '12:55', '13:30', '14:05',
    ];
    return times[(race.raceNo - 1) % times.length];
  }

  bool get _isFinished =>
      race.status == '종료' || race.status == '확정' || race.status == '완료';

  DateTime? get _raceDateTime {
    final cleaned = race.date.replaceAll('.', '').replaceAll('-', '');
    if (cleaned.length < 8) return null;
    final dateStr =
        '${cleaned.substring(0, 4)}-${cleaned.substring(4, 6)}-${cleaned.substring(6, 8)}';
    final time = _raceTime;
    final parts = time.split(':');
    if (parts.length < 2) return null;
    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);
    if (hour == null || minute == null) return null;
    final dt = DateTime.tryParse(dateStr);
    if (dt == null) return null;
    return DateTime(dt.year, dt.month, dt.day, hour, minute);
  }

  /// 경기 시작까지 남은 시간 텍스트 (예정 상태일 때만)
  String? get _remainingTimeText {
    if (_isFinished) return null;
    final raceTime = _raceDateTime;
    if (raceTime == null) return null;

    final now = DateTime.now();
    final diff = raceTime.difference(now);

    if (diff.isNegative) return '진행중';

    final totalMinutes = diff.inMinutes;
    if (totalMinutes <= 0) return '곧 시작';

    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;

    if (hours >= 24) return null;
    if (hours > 0 && minutes > 0) return '${hours}시간 ${minutes}분 후';
    if (hours > 0) return '${hours}시간 후';
    return '${minutes}분 후';
  }

  @override
  void initState() {
    super.initState();
    _startTimerIfNeeded();
  }

  @override
  void didUpdateWidget(covariant RaceCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _timer?.cancel();
    _startTimerIfNeeded();
  }

  void _startTimerIfNeeded() {
    if (_isFinished) return;
    final raceTime = _raceDateTime;
    if (raceTime == null) return;
    final diff = raceTime.difference(DateTime.now());
    if (diff.isNegative || diff.inHours >= 24) return;

    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => context.push(
        '/race/${race.venueCode}/${race.date}/${race.raceNo}',
      ),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF30363D)),
        ),
        child: Column(
          children: [
            _buildTopRow(),
            const SizedBox(height: 10),
            _buildBottomRow(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTopRow() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color(0xFF22C55E),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '${race.raceNo}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    '일반',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 8),
                  _statusBadge(),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${race.venueName} · ${race.distance > 0 ? '${race.distance}m' : ''}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),
        Text(
          _raceTime,
          style: const TextStyle(
            color: Color(0xFFFBBF24),
            fontSize: 22,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomRow(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.pedal_bike_rounded,
            size: 14, color: Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 4),
        Text('${race.racerCount > 0 ? race.racerCount : 7}명',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
        const SizedBox(width: 10),
        Icon(Icons.straighten_rounded,
            size: 14, color: Colors.white.withValues(alpha: 0.4)),
        const SizedBox(width: 4),
        Text(race.distance > 0 ? '${race.distance}m' : '--',
            style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5), fontSize: 12)),
        const Spacer(),
        if (_isFinished) ...[
          _actionChip(
            icon: Icons.emoji_events_rounded,
            label: '결과',
            color: const Color(0xFFFBBF24),
            onTap: () => context.push(
              '/result/${race.venueCode}/${race.date}/${race.raceNo}',
            ),
          ),
        ] else ...[
          _actionChip(
            icon: Icons.visibility_rounded,
            label: '상세',
            color: const Color(0xFF3B82F6),
            onTap: () => context.push(
              '/race/${race.venueCode}/${race.date}/${race.raceNo}',
            ),
          ),
        ],
      ],
    );
  }

  Widget _statusBadge() {
    final remaining = _remainingTimeText;
    final bool isCountdown = remaining != null && !_isFinished;
    final bool isInProgress = remaining == '진행중';

    final Color bgColor;
    final Color textColor;
    final String label;

    if (_isFinished) {
      bgColor = Colors.white.withValues(alpha: 0.12);
      textColor = Colors.white.withValues(alpha: 0.7);
      label = race.status;
    } else if (isInProgress) {
      bgColor = const Color(0xFFF97316).withValues(alpha: 0.15);
      textColor = const Color(0xFFF97316);
      label = '진행중';
    } else if (isCountdown) {
      bgColor = const Color(0xFF3B82F6).withValues(alpha: 0.15);
      textColor = const Color(0xFF3B82F6);
      label = remaining;
    } else {
      bgColor = const Color(0xFF22C55E).withValues(alpha: 0.15);
      textColor = const Color(0xFF22C55E);
      label = race.status;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isCountdown && !isInProgress) ...[
            Icon(Icons.schedule_rounded, size: 11, color: textColor),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
