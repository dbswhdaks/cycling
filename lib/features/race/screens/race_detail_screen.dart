import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/race_entry.dart';
import '../../../models/odds.dart';
import '../../../core/constants/api_constants.dart';
import '../providers/race_providers.dart';
import '../widgets/entry_card.dart';
import '../widgets/odds_panel.dart';
import '../widgets/prediction_tab.dart';

class RaceDetailScreen extends ConsumerStatefulWidget {
  final int venueCode;
  final String date;
  final int raceNo;

  const RaceDetailScreen({
    super.key,
    required this.venueCode,
    required this.date,
    required this.raceNo,
  });

  @override
  ConsumerState<RaceDetailScreen> createState() => _RaceDetailScreenState();
}

class _RaceDetailScreenState extends ConsumerState<RaceDetailScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  int get venueCode => widget.venueCode;
  String get date => widget.date;
  int get raceNo => widget.raceNo;

  String get venueName => ApiConstants.venueName(venueCode);

  String get displayDate {
    if (date.length >= 8) {
      return '${date.substring(0, 4)}년 ${date.substring(4, 6)}월 ${date.substring(6, 8)}일';
    }
    return date;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entriesAsync = ref.watch(raceEntriesProvider((
      venue: venueCode,
      date: date.length == 8 ? date : _todayYmd,
      raceNo: raceNo,
    )));
    final oddsAsync = ref.watch(oddsProvider((
      venue: venueCode,
      date: date.length == 8 ? date : _todayYmd,
      raceNo: raceNo,
    )));

    return Scaffold(
      body: NestedScrollView(
        headerSliverBuilder: (context, innerBoxIsScrolled) => [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: _buildDateHeader(theme),
          ),
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverTabBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                indicatorColor: theme.colorScheme.primary,
                indicatorWeight: 3,
                labelStyle: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
                tabs: const [
                  Tab(text: '종합추천'),
                  Tab(text: 'AI 추천'),
                ],
              ),
            ),
          ),
        ],
        body: TabBarView(
          controller: _tabController,
          children: [
            _buildComprehensiveInfoTab(context, theme, entriesAsync, oddsAsync),
            _buildAiRecommendationTab(context, theme),
          ],
        ),
      ),
    );
  }

  Widget _buildComprehensiveInfoTab(
    BuildContext context,
    ThemeData theme,
    AsyncValue entriesAsync,
    AsyncValue oddsAsync,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildPopularityRanking(theme, entriesAsync, oddsAsync),
          const SizedBox(height: 24),
          _buildComprehensivePicks(theme, entriesAsync, oddsAsync),
          const SizedBox(height: 24),
          _buildSectionTitleWithAction(
            theme,
            '출주표',
            actionLabel: '결과',
            actionIcon: Icons.emoji_events_rounded,
            actionColor: const Color(0xFFFBBF24),
            onAction: () => context.push('/result/$venueCode/$date/$raceNo'),
          ),
          const SizedBox(height: 12),
          entriesAsync.when(
            data: (result) {
              final entries = result is DataWithSource ? result.data : result;
              return Column(
                children: (entries as List)
                    .cast<RaceEntry>()
                    .map((e) => Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: EntryCard(entry: e, venueCode: venueCode),
                        ))
                    .toList(),
              );
            },
            loading: () => _buildLoadingEntries(),
            error: (_, __) => _buildErrorCard(context),
          ),
          const SizedBox(height: 28),
          _buildSectionTitle(theme, '배당률'),
          const SizedBox(height: 12),
          oddsAsync.when(
            data: (odds) => OddsPanel(odds: odds),
            loading: () => _buildLoadingOdds(),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: 24),
          _buildInfoCard(
            context,
            icon: Icons.info_outline_rounded,
            title: '경주 정보',
            items: [
              '거리: 2025m',
              '출전: 7명',
              '배당은 실시간 변동됩니다',
              '공공데이터 API 연동',
            ],
          ),
        ],
      ),
    );
  }

  // ─── 인기 순위 (배당률 기반) ───

  Widget _buildPopularityRanking(
    ThemeData theme,
    AsyncValue entriesAsync,
    AsyncValue oddsAsync,
  ) {
    return oddsAsync.when(
      data: (odds) {
        final winOdds = (odds as Odds).win;
        if (winOdds.isEmpty) return const SizedBox.shrink();

        final sorted = winOdds.entries.toList()
          ..sort((a, b) => a.value.compareTo(b.value));

        List<RaceEntry> entries = [];
        final entriesVal = entriesAsync.valueOrNull;
        if (entriesVal is DataWithSource) {
          entries = (entriesVal.data as List).cast<RaceEntry>();
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.trending_up_rounded, size: 20, color: Color(0xFFFBBF24)),
                const SizedBox(width: 8),
                Text(
                  '인기 순위',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '단승 배당 기준',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFFFBBF24).withValues(alpha: 0.08),
                    const Color(0xFFF59E0B).withValues(alpha: 0.04),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.2)),
              ),
              child: Column(
                children: sorted.asMap().entries.map((mapEntry) {
                  final rank = mapEntry.key + 1;
                  final lineNo = mapEntry.value.key;
                  final oddsVal = mapEntry.value.value;

                  final entry = entries.cast<RaceEntry?>().firstWhere(
                    (e) => e!.lineNo == lineNo,
                    orElse: () => null,
                  );

                  final Color rankColor;
                  final IconData? rankIcon;
                  switch (rank) {
                    case 1:
                      rankColor = const Color(0xFFFBBF24);
                      rankIcon = Icons.looks_one_rounded;
                      break;
                    case 2:
                      rankColor = const Color(0xFFA3A3A3);
                      rankIcon = Icons.looks_two_rounded;
                      break;
                    case 3:
                      rankColor = const Color(0xFFCD7F32);
                      rankIcon = Icons.looks_3_rounded;
                      break;
                    default:
                      rankColor = theme.colorScheme.onSurface.withValues(alpha: 0.4);
                      rankIcon = null;
                  }

                  return Padding(
                    padding: EdgeInsets.only(bottom: mapEntry.key < sorted.length - 1 ? 8 : 0),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 28,
                          child: rankIcon != null
                              ? Icon(rankIcon, color: rankColor, size: 22)
                              : Text(
                                  '$rank',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    color: rankColor,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                        ),
                        const SizedBox(width: 10),
                        Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: _gradeColor(entry?.grade ?? '').withValues(alpha: 0.15),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '$lineNo',
                            style: TextStyle(
                              color: _gradeColor(entry?.grade ?? ''),
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                entry?.riderName ?? '$lineNo번 선수',
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              if (entry != null)
                                Row(
                                  children: [
                                    _buildMiniChip(entry.grade, _gradeColor(entry.grade)),
                                    const SizedBox(width: 4),
                                    _buildMiniChip(entry.tactic, const Color(0xFF6366F1)),
                                  ],
                                ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: rankColor.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '${oddsVal.toStringAsFixed(1)}배',
                            style: TextStyle(
                              color: rankColor,
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        );
      },
      loading: () => Container(
        height: 160,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // ─── 종합 추천 조합 (출주표 기반 스코어링) ───

  Widget _buildComprehensivePicks(
    ThemeData theme,
    AsyncValue entriesAsync,
    AsyncValue oddsAsync,
  ) {
    return entriesAsync.when(
      data: (result) {
        final entries = (result is DataWithSource ? result.data : result) as List;
        final typed = entries.cast<RaceEntry>();
        if (typed.isEmpty) return const SizedBox.shrink();

        final scored = typed.map((e) {
          const gradeScores = {'S': 10.0, 'A1': 8.5, 'A2': 7.0, 'B1': 5.5, 'B2': 4.0, 'B3': 2.5};
          final g = gradeScores[e.grade] ?? 4.0;
          final a = e.avgScore.clamp(0, 10).toDouble();
          final r = e.recent3Wins * 2.0;
          return (entry: e, score: g * 3.0 + a * 2.5 + r);
        }).toList()
          ..sort((a, b) => b.score.compareTo(a.score));

        Odds? odds;
        final oddsVal = oddsAsync.valueOrNull;
        if (oddsVal is Odds) odds = oddsVal;

        final top3 = scored.take(3).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.star_rounded, size: 20, color: Color(0xFF22C55E)),
                const SizedBox(width: 8),
                Text(
                  '종합 추천',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  '등급·성적·배당 종합',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 추천 선수 TOP 3
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF22C55E).withValues(alpha: 0.08),
                    const Color(0xFF10B981).withValues(alpha: 0.04),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF22C55E).withValues(alpha: 0.2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...top3.asMap().entries.map((mapEntry) {
                    final i = mapEntry.key;
                    final e = mapEntry.value.entry;
                    final score = mapEntry.value.score;
                    final maxScore = top3.first.score;
                    final ratio = (score / maxScore).clamp(0.1, 1.0);

                    final colors = [
                      const Color(0xFFFBBF24),
                      const Color(0xFFA3A3A3),
                      const Color(0xFFCD7F32),
                    ];
                    final color = colors[i];

                    double? winOdds;
                    if (odds != null && odds.win.containsKey(e.lineNo)) {
                      winOdds = odds.win[e.lineNo];
                    }

                    return Padding(
                      padding: EdgeInsets.only(bottom: i < 2 ? 10 : 0),
                      child: Row(
                        children: [
                          Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: color.withValues(alpha: 0.2),
                              shape: BoxShape.circle,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: color,
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        '${e.lineNo}번 ${e.riderName}',
                                        style: theme.textTheme.bodyMedium?.copyWith(
                                          fontWeight: FontWeight.w600,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    _buildMiniChip(e.grade, _gradeColor(e.grade)),
                                    const SizedBox(width: 4),
                                    _buildMiniChip(e.tactic, const Color(0xFF6366F1)),
                                    if (winOdds != null) ...[
                                      const SizedBox(width: 4),
                                      _buildMiniChip('${winOdds.toStringAsFixed(1)}배', const Color(0xFFF59E0B)),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 4),
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: LinearProgressIndicator(
                                    value: ratio,
                                    minHeight: 5,
                                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                                    valueColor: AlwaysStoppedAnimation(color.withValues(alpha: 0.6)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '평균 ${e.avgScore.toStringAsFixed(1)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 14),
                  const Divider(height: 1),
                  const SizedBox(height: 14),
                  _buildPickRow(theme, '단승 추천', '${top3[0].entry.lineNo}번 ${top3[0].entry.riderName}', const Color(0xFFEF4444)),
                  const SizedBox(height: 8),
                  if (top3.length >= 2)
                    _buildPickRow(
                      theme,
                      '복승 추천',
                      '${top3[0].entry.lineNo}-${top3[1].entry.lineNo}',
                      const Color(0xFF3B82F6),
                    ),
                  if (top3.length >= 2) const SizedBox(height: 8),
                  if (top3.length >= 2)
                    _buildPickRow(
                      theme,
                      '쌍승 추천',
                      '${top3[0].entry.lineNo}→${top3[1].entry.lineNo}',
                      const Color(0xFF8B5CF6),
                    ),
                  if (top3.length >= 3) ...[
                    const SizedBox(height: 8),
                    _buildPickRow(
                      theme,
                      '삼복승 추천',
                      '${top3[0].entry.lineNo}-${top3[1].entry.lineNo}-${top3[2].entry.lineNo}',
                      const Color(0xFFF59E0B),
                    ),
                  ],
                ],
              ),
            ),
          ],
        );
      },
      loading: () => Container(
        height: 120,
        decoration: BoxDecoration(
          color: Colors.grey.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Center(
          child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildPickRow(ThemeData theme, String type, String pick, Color color) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            type,
            style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            pick,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  Widget _buildMiniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600),
      ),
    );
  }

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

  Widget _buildAiRecommendationTab(BuildContext context, ThemeData theme) {
    final predictionAsync = ref.watch(predictionProvider((
      venue: venueCode,
      date: date.length == 8 ? date : _todayYmd,
      raceNo: raceNo,
    )));

    return predictionAsync.when(
      data: (prediction) => PredictionTab(
        prediction: prediction,
        venueName: venueName,
        venueCode: venueCode,
        date: date,
        raceNo: raceNo,
      ),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text('예측 데이터를 불러올 수 없습니다.\n$e',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium),
        ),
      ),
    );
  }

  String get _todayYmd {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
  }

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 130,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        title: Text('$venueName ${raceNo}R'),
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

  Widget _buildDateHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.calendar_today_rounded,
            size: 18,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Text(
            displayDate,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(ThemeData theme, String title) {
    return Text(
      title,
      style: theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
      ),
    );
  }

  Widget _buildSectionTitleWithAction(
    ThemeData theme,
    String title, {
    required String actionLabel,
    required IconData actionIcon,
    required Color actionColor,
    required VoidCallback onAction,
  }) {
    return Row(
      children: [
        Text(
          title,
          style: theme.textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        GestureDetector(
          onTap: onAction,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: actionColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: actionColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(actionIcon, size: 16, color: actionColor),
                const SizedBox(width: 4),
                Text(
                  actionLabel,
                  style: TextStyle(
                    color: actionColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingEntries() {
    return Column(
      children: List.generate(
        5,
        (i) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          height: 76,
          decoration: BoxDecoration(
            color: Colors.grey.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOdds() {
    return Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _buildErrorCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              '출주표를 불러올 수 없습니다. 목업 데이터를 표시합니다.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required List<String> items,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: theme.brightness == Brightness.dark
            ? Border.all(color: const Color(0xFF30363D))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 22, color: theme.colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                title,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...items.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '•',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        item,
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}

class _SliverTabBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _SliverTabBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return Container(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(covariant _SliverTabBarDelegate oldDelegate) {
    return tabBar != oldDelegate.tabBar;
  }
}
