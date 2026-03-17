import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/rider_detail.dart';
import '../../race/providers/race_providers.dart';

class RiderDetailScreen extends ConsumerWidget {
  final String riderId;
  final int? venueCode;

  const RiderDetailScreen({
    super.key,
    required this.riderId,
    this.venueCode,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entry = ref.watch(selectedRiderEntryProvider);
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('선수 정보'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => context.pop(),
          ),
        ),
        body: const Center(child: Text('선수 정보를 불러올 수 없습니다.')),
      );
    }

    final detailAsync = ref.watch(riderDetailProvider((entry: entry, venue: venueCode)));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 140,
            pinned: true,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_rounded),
              onPressed: () => context.pop(),
            ),
            flexibleSpace: FlexibleSpaceBar(
              title: Text(entry.riderName),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF00C853),
                      Color(0xFF00A843),
                      Color(0xFF00897B),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: detailAsync.when(
              data: (detail) => _buildContent(context, detail),
              loading: () => _buildContent(context, RiderDetail.fromRaceEntry(entry)),
              error: (_, __) => _buildContent(context, RiderDetail.fromRaceEntry(entry)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, RiderDetail detail) {
    final theme = Theme.of(context);
    final gradeColor = _gradeColor(detail.grade);

    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildProfileCard(context, theme, detail, gradeColor),
          const SizedBox(height: 20),
          _buildSection(theme, '기본 기록', [
            _buildInfoRow(theme, '등급', detail.grade, valueColor: gradeColor),
            _buildInfoRow(theme, '전법', detail.tactic),
            _buildInfoRow(theme, '평균 득점', detail.avgScore.toStringAsFixed(1)),
            _buildInfoRow(theme, '최근 3회 우승', '${detail.recent3Wins}회'),
          ]),
          if (detail.age != null || detail.school != null || detail.trainingBase != null) ...[
            const SizedBox(height: 20),
            _buildSection(theme, '선수 배경', [
              if (detail.age != null) _buildInfoRow(theme, '나이', '${detail.age}세'),
              if (detail.school != null) _buildInfoRow(theme, '출신 학교', detail.school!),
              if (detail.trainingBase != null) _buildInfoRow(theme, '훈련지', detail.trainingBase!),
            ]),
          ],
          if (detail.totalWins != null || detail.recent10Avg != null) ...[
            const SizedBox(height: 20),
            _buildSection(theme, '통계', [
              if (detail.totalWins != null) _buildInfoRow(theme, '총 우승', '${detail.totalWins}회'),
              if (detail.totalRaces != null) _buildInfoRow(theme, '총 출전', '${detail.totalRaces}회'),
              if (detail.recent10Avg != null)
                _buildInfoRow(theme, '최근 10회 평균', detail.recent10Avg!.toStringAsFixed(1)),
            ]),
          ],
        ],
      ),
    );
  }

  Widget _buildProfileCard(
    BuildContext context,
    ThemeData theme,
    RiderDetail detail,
    Color gradeColor,
  ) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            gradeColor.withValues(alpha: 0.2),
            gradeColor.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: gradeColor.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: gradeColor.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(16),
            ),
            alignment: Alignment.center,
            child: Text(
              detail.grade,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: gradeColor,
              ),
            ),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  detail.riderName,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    _buildChip(context, detail.grade, gradeColor),
                    const SizedBox(width: 8),
                    _buildChip(
                      context,
                      detail.tactic,
                      theme.colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection(ThemeData theme, String title, List<Widget> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: theme.brightness == Brightness.dark
                ? Border.all(color: const Color(0xFF30363D))
                : null,
          ),
          child: Column(children: rows),
        ),
      ],
    );
  }

  Widget _buildInfoRow(ThemeData theme, String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Color _gradeColor(String grade) {
    switch (grade) {
      case 'S':
        return const Color(0xFFE53935);
      case 'A1':
        return const Color(0xFFF57C00);
      case 'A2':
        return const Color(0xFFFDD835);
      case 'B1':
        return const Color(0xFF43A047);
      case 'B2':
        return const Color(0xFF1E88E5);
      case 'B3':
        return const Color(0xFF8E24AA);
      default:
        return const Color(0xFF757575);
    }
  }
}
