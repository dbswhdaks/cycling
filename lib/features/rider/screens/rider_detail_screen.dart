import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/race_entry.dart';
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

    if (entry != null) {
      return _buildWithEntry(context, ref, entry);
    }

    return _buildWithIdOnly(context, ref);
  }

  Widget _buildWithEntry(BuildContext context, WidgetRef ref, RaceEntry entry) {
    final detailAsync = ref.watch(riderDetailProvider((entry: entry, venue: venueCode)));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, entry.riderName),
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

  Widget _buildWithIdOnly(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(
      riderDetailByIdProvider((riderId: riderId, venue: venueCode)),
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          detailAsync.when(
            data: (detail) => _buildSliverAppBar(context, detail.riderName),
            loading: () => _buildSliverAppBar(context, '선수 정보'),
            error: (_, __) => _buildSliverAppBar(context, '선수 정보'),
          ),
          SliverToBoxAdapter(
            child: detailAsync.when(
              data: (detail) => _buildContent(context, detail),
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, __) => const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: Text('선수 정보를 불러올 수 없습니다.')),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliverAppBar(BuildContext context, String title) {
    return SliverAppBar(
      expandedHeight: 140,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => context.pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        title: Text(title),
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
          const SizedBox(height: 24),
          _buildStatCards(theme, detail),
          const SizedBox(height: 24),
          _buildSection(
            theme,
            icon: Icons.bar_chart_rounded,
            iconColor: const Color(0xFF3B82F6),
            title: '기본 정보',
            children: [
              _buildInfoRow(theme, '등급', detail.grade, valueColor: gradeColor),
              _buildInfoRow(theme, '주 전법', detail.tacticLabel),
              _buildInfoRow(theme, '통산 평균 득점', detail.avgScore.toStringAsFixed(1)),
              if (detail.yearRaceCount > 0)
                _buildInfoRow(theme, '올해 출전', '${detail.yearRaceCount}회'),
            ],
          ),
          if (detail.yearRaceCount > 0) ...[
            const SizedBox(height: 20),
            _buildSection(
              theme,
              icon: Icons.emoji_events_rounded,
              iconColor: const Color(0xFFFBBF24),
              title: '올해 성적',
              children: [
                _buildPlacementBar(theme, detail),
                const SizedBox(height: 12),
                _buildInfoRow(theme, '1착', '${detail.year1stCount}회',
                    valueColor: const Color(0xFFFBBF24)),
                _buildInfoRow(theme, '2착', '${detail.year2ndCount}회',
                    valueColor: const Color(0xFFA3A3A3)),
                _buildInfoRow(theme, '3착', '${detail.year3rdCount}회',
                    valueColor: const Color(0xFFCD7F32)),
                _buildInfoRow(
                  theme,
                  '입상률',
                  '${detail.podiumRate.toStringAsFixed(1)}%',
                  valueColor: detail.podiumRate >= 50
                      ? const Color(0xFF22C55E)
                      : null,
                ),
              ],
            ),
          ],
          if (detail.breakWins > 0 || detail.markWins > 0 || detail.chaseWins > 0) ...[
            const SizedBox(height: 20),
            _buildSection(
              theme,
              icon: Icons.track_changes_rounded,
              iconColor: const Color(0xFF8B5CF6),
              title: '전법별 우승',
              children: [
                _buildTacticBar(theme, detail),
                const SizedBox(height: 12),
                if (detail.breakWins > 0)
                  _buildInfoRow(theme, '선행 (앞에서 끌고 가기)', '${detail.breakWins}회',
                      valueColor: const Color(0xFFEF4444)),
                if (detail.markWins > 0)
                  _buildInfoRow(theme, '마크 (상대 뒤에서 따라가기)', '${detail.markWins}회',
                      valueColor: const Color(0xFF3B82F6)),
                if (detail.chaseWins > 0)
                  _buildInfoRow(theme, '추입 (후반 추월)', '${detail.chaseWins}회',
                      valueColor: const Color(0xFF22C55E)),
              ],
            ),
          ],
          if (detail.recentScores.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildSection(
              theme,
              icon: Icons.trending_up_rounded,
              iconColor: const Color(0xFF22C55E),
              title: '최근 컨디션',
              children: [
                if (detail.recentAvgScore != null)
                  _buildInfoRow(
                    theme,
                    '최근 ${detail.recentScores.length}경기 평균',
                    detail.recentAvgScore!.toStringAsFixed(1),
                    valueColor: _conditionColor(detail),
                  ),
                const SizedBox(height: 8),
                _buildScoreChart(theme, detail),
              ],
            ),
          ],
          if (detail.age != null || detail.school != null || detail.trainingBase != null) ...[
            const SizedBox(height: 20),
            _buildSection(
              theme,
              icon: Icons.person_outline_rounded,
              iconColor: const Color(0xFFF59E0B),
              title: '선수 배경',
              children: [
                if (detail.age != null) _buildInfoRow(theme, '나이', '${detail.age}세'),
                if (detail.school != null) _buildInfoRow(theme, '출신 학교', detail.school!),
                if (detail.trainingBase != null) _buildInfoRow(theme, '훈련지', detail.trainingBase!),
              ],
            ),
          ],
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── 프로필 카드 ───

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
                    if (detail.tacticLabel.isNotEmpty && detail.tacticLabel != '-') ...[
                      const SizedBox(width: 8),
                      _buildChip(
                        context,
                        detail.tacticLabel,
                        theme.colorScheme.primary,
                      ),
                    ],
                    if (detail.yearRaceCount > 0) ...[
                      const SizedBox(width: 8),
                      _buildChip(
                        context,
                        '${detail.yearRaceCount}전',
                        const Color(0xFF22C55E),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── 핵심 지표 카드 ───

  Widget _buildStatCards(ThemeData theme, RiderDetail detail) {
    final isDark = theme.brightness == Brightness.dark;
    final items = <({String label, String value, Color color, IconData icon})>[
      (
        label: '평균 득점',
        value: detail.avgScore.toStringAsFixed(1),
        color: const Color(0xFF3B82F6),
        icon: Icons.score_rounded,
      ),
      (
        label: '승률',
        value: detail.yearRaceCount > 0
            ? '${detail.winRate.toStringAsFixed(0)}%'
            : '-',
        color: const Color(0xFFFBBF24),
        icon: Icons.military_tech_rounded,
      ),
      (
        label: '입상률',
        value: detail.yearRaceCount > 0
            ? '${detail.podiumRate.toStringAsFixed(0)}%'
            : '-',
        color: const Color(0xFF22C55E),
        icon: Icons.leaderboard_rounded,
      ),
    ];

    return Row(
      children: items.map((item) {
        return Expanded(
          child: Container(
            margin: EdgeInsets.only(
              right: item == items.last ? 0 : 10,
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: isDark ? 0.08 : 0.06),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: item.color.withValues(alpha: 0.2)),
            ),
            child: Column(
              children: [
                Icon(item.icon, size: 22, color: item.color),
                const SizedBox(height: 8),
                Text(
                  item.value,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: item.color,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  item.label,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ─── 입상 분포 바 ───

  Widget _buildPlacementBar(ThemeData theme, RiderDetail detail) {
    final total = detail.yearRaceCount;
    if (total == 0) return const SizedBox.shrink();

    final p1 = detail.year1stCount / total;
    final p2 = detail.year2ndCount / total;
    final p3 = detail.year3rdCount / total;
    final pOther = 1.0 - p1 - p2 - p3;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            if (p1 > 0) Expanded(flex: (p1 * 100).round(), child: Container(color: const Color(0xFFFBBF24))),
            if (p2 > 0) Expanded(flex: (p2 * 100).round(), child: Container(color: const Color(0xFFA3A3A3))),
            if (p3 > 0) Expanded(flex: (p3 * 100).round(), child: Container(color: const Color(0xFFCD7F32))),
            if (pOther > 0)
              Expanded(
                flex: (pOther * 100).round(),
                child: Container(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // ─── 전법별 분포 바 ───

  Widget _buildTacticBar(ThemeData theme, RiderDetail detail) {
    final total = detail.totalWins;
    if (total == 0) return const SizedBox.shrink();

    final pB = detail.breakWins / total;
    final pM = detail.markWins / total;
    final pC = detail.chaseWins / total;

    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: SizedBox(
        height: 14,
        child: Row(
          children: [
            if (pB > 0) Expanded(flex: (pB * 100).round(), child: Container(color: const Color(0xFFEF4444))),
            if (pM > 0) Expanded(flex: (pM * 100).round(), child: Container(color: const Color(0xFF3B82F6))),
            if (pC > 0) Expanded(flex: (pC * 100).round(), child: Container(color: const Color(0xFF22C55E))),
          ],
        ),
      ),
    );
  }

  // ─── 최근 득점 차트 ───

  Widget _buildScoreChart(ThemeData theme, RiderDetail detail) {
    final scores = detail.recentScores;
    if (scores.isEmpty) return const SizedBox.shrink();

    final maxScore = scores.reduce((a, b) => a > b ? a : b).clamp(1.0, 20.0);
    final chartHeight = 80.0;

    return SizedBox(
      height: chartHeight + 20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: scores.asMap().entries.map((entry) {
          final i = entry.key;
          final score = entry.value;
          final ratio = score / maxScore;
          final barH = (ratio * chartHeight).clamp(8.0, chartHeight);
          final color = _scoreBarColor(score, detail.avgScore);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    score.toStringAsFixed(1),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: barH,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color, color.withValues(alpha: 0.4)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${scores.length - i}전전',
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ─── 공통 위젯 ───

  Widget _buildSection(
    ThemeData theme, {
    required IconData icon,
    required Color iconColor,
    required String title,
    required List<Widget> children,
  }) {
    final isDark = theme.brightness == Brightness.dark;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: iconColor),
            const SizedBox(width: 8),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(16),
            border: isDark ? Border.all(color: const Color(0xFF30363D)) : null,
          ),
          child: Column(children: children),
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
          Flexible(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
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

  // ─── 색상 유틸 ───

  Color _gradeColor(String grade) {
    return switch (grade) {
      'S' => const Color(0xFFE53935),
      'A1' => const Color(0xFFF57C00),
      'A2' => const Color(0xFFFDD835),
      'B1' => const Color(0xFF43A047),
      'B2' => const Color(0xFF1E88E5),
      'B3' => const Color(0xFF8E24AA),
      _ => const Color(0xFF757575),
    };
  }

  Color _conditionColor(RiderDetail detail) {
    if (detail.recentAvgScore == null) return const Color(0xFF757575);
    final diff = detail.recentAvgScore! - detail.avgScore;
    if (diff > 0.5) return const Color(0xFF22C55E);
    if (diff < -0.5) return const Color(0xFFEF4444);
    return const Color(0xFFF59E0B);
  }

  Color _scoreBarColor(double score, double avg) {
    if (score >= avg + 0.5) return const Color(0xFF22C55E);
    if (score <= avg - 0.5) return const Color(0xFFEF4444);
    return const Color(0xFF3B82F6);
  }
}
