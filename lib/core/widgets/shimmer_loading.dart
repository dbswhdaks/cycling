import 'package:flutter/material.dart';

/// 로딩 시 표시할 Shimmer 위젯
class ShimmerRaceList extends StatelessWidget {
  const ShimmerRaceList({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(5, (i) => _ShimmerCard(key: ValueKey(i))),
    );
  }
}

class _ShimmerCard extends StatefulWidget {
  const _ShimmerCard({super.key});

  @override
  State<_ShimmerCard> createState() => _ShimmerCardState();
}

class _ShimmerCardState extends State<_ShimmerCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = const Color(0xFF30363D);
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, _) {
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF21262D),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF30363D)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: baseColor.withValues(alpha: 0.5 + _animation.value * 0.2),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 60,
                      height: 18,
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.3 + _animation.value * 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: double.infinity,
                      height: 14,
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.25 + _animation.value * 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 80,
                      height: 12,
                      decoration: BoxDecoration(
                        color: baseColor.withValues(alpha: 0.2 + _animation.value * 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 50,
                height: 24,
                decoration: BoxDecoration(
                  color: baseColor.withValues(alpha: 0.4 + _animation.value * 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
