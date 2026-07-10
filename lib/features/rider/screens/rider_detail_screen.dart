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

    final fallback = RiderDetail.fromRaceEntryDetailed(entry);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildSliverAppBar(context, entry.riderName),
          SliverToBoxAdapter(
            child: detailAsync.when(
              data: (detail) => _buildContent(context, detail),
              loading: () => _buildContent(context, fallback),
              error: (_, __) => _buildContent(context, fallback),
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
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 32 + bottomInset),
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
              _buildGradeRow(theme, detail, gradeColor),
              _buildInfoRow(theme, '주 전법', detail.tacticLabel),
              _buildInfoRow(theme, '통산 평균 득점', detail.avgScore.toStringAsFixed(1)),
              if (detail.yearRaceCount > 0)
                _buildInfoRow(theme, '올해 출전', '${detail.yearRaceCount}회'),
              if (detail.gearRatio != null)
                _buildInfoRow(theme, '기어배수',
                    detail.gearRatio!.toStringAsFixed(2)),
              if (detail.time200m != null)
                _buildInfoRow(theme, '200m 기록', '${detail.time200m}초'),
            ],
          ),
          const SizedBox(height: 20),
          _buildSection(
            theme,
            icon: Icons.person_outline_rounded,
            iconColor: const Color(0xFFF59E0B),
            title: '선수 배경',
            children: [
              if (detail.age != null)
                _buildInfoRow(theme, '나이', '${detail.age}세'),
              if (detail.cohortNo != null)
                _buildInfoRow(theme, '기수', '${detail.cohortNo}기'),
              if (detail.school != null)
                _buildInfoRow(theme, '출신 학교', detail.school!),
              if (detail.trainingBase != null)
                _buildInfoRow(theme, '훈련지', detail.trainingBase!),
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
                  '승률 (1착)',
                  '${detail.winRate.toStringAsFixed(1)}%',
                  valueColor: detail.winRate >= 20
                      ? const Color(0xFFFBBF24)
                      : null,
                ),
                _buildInfoRow(
                  theme,
                  '연대율 (1·2착)',
                  '${detail.top2Rate.toStringAsFixed(1)}%',
                  valueColor: detail.top2Rate >= 35
                      ? const Color(0xFF3B82F6)
                      : null,
                ),
                _buildInfoRow(
                  theme,
                  '삼연대율 (1·2·3착)',
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
                _buildTrendBanner(theme, detail),
                if (detail.recentAvgScore != null) ...[
                  const SizedBox(height: 10),
                  _buildInfoRow(
                    theme,
                    '최근 ${detail.recentScores.length}경기 평균',
                    detail.recentAvgScore!.toStringAsFixed(1),
                    valueColor: _conditionColor(detail),
                  ),
                ],
                const SizedBox(height: 8),
                _buildScoreChart(theme, detail),
              ],
            ),
          ],
          if (detail.recentRaces.isNotEmpty) ...[
            const SizedBox(height: 20),
            _buildSection(
              theme,
              icon: Icons.history_rounded,
              iconColor: const Color(0xFF06B6D4),
              title: '최근 5경기 상세',
              children: [
                _buildRecentRacesTable(theme, detail.recentRaces),
              ],
            ),
          ],
          if (detail.venueBreakdown.length >= 2) ...[
            const SizedBox(height: 20),
            _buildSection(
              theme,
              icon: Icons.location_on_rounded,
              iconColor: const Color(0xFFEC4899),
              title: '경기장별 성적',
              children: [
                _buildVenueBreakdown(theme, detail.venueBreakdown),
              ],
            ),
          ],
          const SizedBox(height: 8),
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
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _buildChip(context, detail.grade, gradeColor),
                    if (detail.tacticLabel.isNotEmpty && detail.tacticLabel != '-')
                      _buildChip(
                        context,
                        detail.tacticLabel,
                        theme.colorScheme.primary,
                      ),
                    if (detail.yearRaceCount > 0)
                      _buildChip(
                        context,
                        '${detail.yearRaceCount}전',
                        const Color(0xFF22C55E),
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

    final rawMax = scores.reduce((a, b) => a > b ? a : b);
    final rawMin = scores.reduce((a, b) => a < b ? a : b);
    final range = rawMax - rawMin;
    final padding = range < 0.5 ? 1.0 : range * 0.3;
    final chartMin = rawMin - padding;
    final chartMax = rawMax + padding * 0.5;
    final chartRange = chartMax - chartMin;
    const chartHeight = 80.0;
    const labelHeight = 16.0;
    const gap = 4.0;

    return SizedBox(
      height: chartHeight + labelHeight * 2 + gap * 2,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: scores.asMap().entries.map((entry) {
          final i = entry.key;
          final score = entry.value;
          final ratio = chartRange > 0
              ? ((score - chartMin) / chartRange).clamp(0.1, 1.0)
              : 1.0;
          final barH = (ratio * chartHeight).clamp(12.0, chartHeight);
          final color = _scoreBarColor(score, detail.avgScore);

          return Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  SizedBox(
                    height: labelHeight,
                    child: Text(
                      score.toStringAsFixed(1),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        color: color,
                      ),
                    ),
                  ),
                  const SizedBox(height: gap),
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
                  const SizedBox(height: gap),
                  SizedBox(
                    height: labelHeight,
                    child: Text(
                      '${scores.length - i}전전',
                      style: TextStyle(
                        fontSize: 9,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
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

  // ─── 신규 위젯 ───

  Widget _buildGradeRow(ThemeData theme, RiderDetail detail, Color gradeColor) {
    final change = detail.gradeChange;
    final hasPrev =
        detail.previousGrade != null && detail.previousGrade!.isNotEmpty;

    Widget valueWidget;
    if (hasPrev) {
      final chevColor = change > 0
          ? const Color(0xFF22C55E)
          : (change < 0 ? const Color(0xFFEF4444) : Colors.white54);
      final chevIcon = change > 0
          ? Icons.arrow_upward_rounded
          : (change < 0 ? Icons.arrow_downward_rounded : Icons.remove_rounded);
      valueWidget = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            detail.previousGrade!,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
              fontWeight: FontWeight.w600,
              decoration: TextDecoration.lineThrough,
            ),
          ),
          const SizedBox(width: 6),
          Icon(chevIcon, size: 14, color: chevColor),
          const SizedBox(width: 6),
          Text(
            detail.grade,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: gradeColor,
            ),
          ),
        ],
      );
    } else {
      valueWidget = Text(
        detail.grade,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: gradeColor,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            '등급',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          valueWidget,
        ],
      ),
    );
  }

  Widget _buildTrendBanner(ThemeData theme, RiderDetail detail) {
    final trend = detail.conditionTrend;
    final (icon, color, label) = switch (trend) {
      RiderConditionTrend.rising => (
        Icons.trending_up_rounded,
        const Color(0xFF22C55E),
        '상승세 · 최근 폼이 좋습니다'
      ),
      RiderConditionTrend.falling => (
        Icons.trending_down_rounded,
        const Color(0xFFEF4444),
        '하락세 · 최근 폼이 저조합니다'
      ),
      RiderConditionTrend.stable => (
        Icons.trending_flat_rounded,
        const Color(0xFFF59E0B),
        '유지 · 통산 평균 수준'
      ),
      RiderConditionTrend.unknown => (
        Icons.help_outline_rounded,
        Colors.white54,
        '데이터 부족'
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentRacesTable(
    ThemeData theme,
    List<RiderRaceRecord> races,
  ) {
    final onSurface = theme.colorScheme.onSurface;
    Widget headerText(String s, {double flex = 1}) => Expanded(
          flex: (flex * 10).round(),
          child: Text(
            s,
            style: TextStyle(
              color: onSurface.withValues(alpha: 0.55),
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          child: Row(
            children: [
              headerText('일자', flex: 1.3),
              headerText('경기', flex: 0.9),
              headerText('등급', flex: 0.7),
              headerText('순위', flex: 0.7),
              Expanded(
                flex: 10,
                child: Text(
                  '득점',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    color: onSurface.withValues(alpha: 0.55),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        Divider(
            height: 1, color: onSurface.withValues(alpha: 0.08)),
        ...races.map((race) {
          final rankColor = switch (race.rank) {
            1 => const Color(0xFFFBBF24),
            2 => const Color(0xFFA3A3A3),
            3 => const Color(0xFFCD7F32),
            _ => onSurface.withValues(alpha: 0.7),
          };
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
            child: Row(
              children: [
                Expanded(
                  flex: 13,
                  child: Text(
                    _formatDate(race.date),
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.85),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Expanded(
                  flex: 9,
                  child: Text(
                    race.raceNo > 0 ? '${race.raceNo}R' : '-',
                    style: TextStyle(
                      color: onSurface.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: Text(
                    race.grade,
                    style: TextStyle(
                      color: _gradeColor(race.grade),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 7,
                  child: Text(
                    race.rank != null ? '${race.rank}착' : '-',
                    style: TextStyle(
                      color: rankColor,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Expanded(
                  flex: 10,
                  child: Text(
                    race.score != null
                        ? race.score!.toStringAsFixed(1)
                        : '-',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: onSurface,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildVenueBreakdown(
    ThemeData theme,
    Map<int, VenueRecord> venues,
  ) {
    final sorted = venues.entries.toList()
      ..sort((a, b) => b.value.total.compareTo(a.value.total));
    const venueColors = {
      1: Color(0xFFFBBF24),
      2: Color(0xFF22C55E),
      3: Color(0xFF3B82F6),
    };
    return Column(
      children: sorted.map((e) {
        final color = venueColors[e.key] ?? Colors.white70;
        final label = switch (e.key) {
          1 => '광명',
          2 => '창원',
          3 => '부산',
          _ => '기타',
        };
        final rec = e.value;
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 28,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${rec.total}전 · ${rec.wins}승 · 입상 ${rec.podiums}회',
                      style: TextStyle(
                        color: theme.colorScheme.onSurface
                            .withValues(alpha: 0.6),
                        fontSize: 11.5,
                      ),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '승률 ${rec.winRate.toStringAsFixed(1)}%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '입상률 ${rec.podiumRate.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: theme.colorScheme.onSurface
                          .withValues(alpha: 0.6),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  String _formatDate(String raw) {
    if (raw.isEmpty) return '-';
    // "2026.06.15" → "06.15"
    if (raw.contains('.') && raw.length >= 10) {
      return raw.substring(5);
    }
    // "20260615" → "06.15"
    if (raw.length == 8 && int.tryParse(raw) != null) {
      return '${raw.substring(4, 6)}.${raw.substring(6, 8)}';
    }
    return raw;
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
