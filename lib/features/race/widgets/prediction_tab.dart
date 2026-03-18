import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../models/prediction.dart';

class PredictionTab extends StatelessWidget {
  final RacePrediction prediction;
  final String venueName;
  final int venueCode;
  final String date;
  final int raceNo;

  const PredictionTab({
    super.key,
    required this.prediction,
    required this.venueName,
    required this.venueCode,
    required this.date,
    required this.raceNo,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(theme, isDark),
          const SizedBox(height: 20),
          _buildRankingSection(theme, isDark),
          const SizedBox(height: 24),
          _buildBettingSection(theme, isDark),
          const SizedBox(height: 24),
          _buildAnalysisSection(theme, isDark),
          const SizedBox(height: 24),
          _buildFactorSection(theme, isDark),
          const SizedBox(height: 20),
          _buildDisclaimer(theme),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  // ─── 헤더: 신뢰도 게이지 ───

  Widget _buildHeader(ThemeData theme, bool isDark) {
    final conf = prediction.confidence;
    final confColor = conf >= 65
        ? const Color(0xFF22C55E)
        : conf >= 45
            ? const Color(0xFFFBBF24)
            : const Color(0xFFEF4444);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6366F1).withValues(alpha: 0.15),
            const Color(0xFF8B5CF6).withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6366F1).withValues(alpha: 0.25)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: Color(0xFF8B5CF6), size: 24),
              const SizedBox(width: 10),
              Text(
                '$venueName ${raceNo}R AI 예측',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF8B5CF6),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: confColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '신뢰도 ${conf.toStringAsFixed(0)}%',
                  style: TextStyle(
                    color: confColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: conf / 100,
              minHeight: 8,
              backgroundColor: confColor.withValues(alpha: 0.12),
              valueColor: AlwaysStoppedAnimation(confColor),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 순위 예측 ───

  Widget _buildRankingSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events_rounded, size: 20, color: Color(0xFFFBBF24)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '순위 예측',
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Builder(
              builder: (context) => GestureDetector(
                onTap: () => context.push('/result/$venueCode/$date/$raceNo'),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFBBF24).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.3)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.emoji_events_rounded, size: 16, color: Color(0xFFFBBF24)),
                      SizedBox(width: 4),
                      Text(
                        '결과',
                        style: TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...prediction.rankings.map((r) => _buildRankRow(theme, isDark, r)),
      ],
    );
  }

  Widget _buildRankRow(ThemeData theme, bool isDark, RiderPrediction r) {
    final maxProb = prediction.rankings.first.winProb;
    final barRatio = (r.winProb / maxProb).clamp(0.05, 1.0);

    final Color rankColor;
    final Color bgColor;
    switch (r.rank) {
      case 1:
        rankColor = const Color(0xFFFBBF24);
        bgColor = const Color(0xFFFBBF24).withValues(alpha: 0.08);
        break;
      case 2:
        rankColor = const Color(0xFFA3A3A3);
        bgColor = Colors.white.withValues(alpha: 0.04);
        break;
      case 3:
        rankColor = const Color(0xFFCD7F32);
        bgColor = const Color(0xFFCD7F32).withValues(alpha: 0.06);
        break;
      default:
        rankColor = Colors.white.withValues(alpha: 0.4);
        bgColor = Colors.transparent;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark ? bgColor : bgColor.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: r.rank <= 3
            ? Border.all(color: rankColor.withValues(alpha: 0.25))
            : Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Text(
              '${r.rank}',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: rankColor,
                fontSize: r.rank <= 3 ? 18 : 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: _gradeColor(r.grade).withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${r.lineNo}',
              style: TextStyle(
                color: _gradeColor(r.grade),
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
                Row(
                  children: [
                    Text(
                      r.riderName,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    _chip(r.grade, _gradeColor(r.grade)),
                    const SizedBox(width: 4),
                    _chip(r.tactic, const Color(0xFF6366F1)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: barRatio,
                    minHeight: 5,
                    backgroundColor: Colors.white.withValues(alpha: 0.06),
                    valueColor: AlwaysStoppedAnimation(
                      r.rank <= 3 ? rankColor.withValues(alpha: 0.7) : Colors.white.withValues(alpha: 0.2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            '${r.winProb.toStringAsFixed(1)}%',
            style: TextStyle(
              color: r.rank <= 3 ? rankColor : Colors.white.withValues(alpha: 0.5),
              fontWeight: FontWeight.w700,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  // ─── 베팅 추천 ───

  Widget _buildBettingSection(ThemeData theme, bool isDark) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, Icons.casino_rounded, '추천 베팅', const Color(0xFF22C55E)),
        const SizedBox(height: 12),
        _buildBetGroup(theme, isDark, '단승', prediction.winPicks, const Color(0xFFEF4444)),
        const SizedBox(height: 10),
        _buildBetGroup(theme, isDark, '복승', prediction.placePicks, const Color(0xFF3B82F6)),
        const SizedBox(height: 10),
        _buildBetGroup(theme, isDark, '쌍승', prediction.quinellaPicks, const Color(0xFF8B5CF6)),
      ],
    );
  }

  Widget _buildBetGroup(
    ThemeData theme,
    bool isDark,
    String type,
    List<BettingPick> picks,
    Color accent,
  ) {
    if (picks.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: isDark ? 0.06 : 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  type,
                  style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...picks.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        p.label,
                        style: TextStyle(
                          color: accent,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        p.description,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }

  // ─── 분석 코멘트 ───

  Widget _buildAnalysisSection(ThemeData theme, bool isDark) {
    if (prediction.analysis.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, Icons.analytics_rounded, 'AI 분석', const Color(0xFF3B82F6)),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF3B82F6).withValues(alpha: isDark ? 0.06 : 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.2)),
          ),
          child: Text(
            prediction.analysis,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.7,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.85),
            ),
          ),
        ),
      ],
    );
  }

  // ─── 요소 분석 (상위 3명) ───

  Widget _buildFactorSection(ThemeData theme, bool isDark) {
    final top = prediction.rankings.take(3).toList();
    if (top.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(theme, Icons.bar_chart_rounded, '요소별 분석 (상위 3명)', const Color(0xFFF59E0B)),
        const SizedBox(height: 12),
        ...top.map((r) => _buildFactorCard(theme, isDark, r)),
      ],
    );
  }

  Widget _buildFactorCard(ThemeData theme, bool isDark, RiderPrediction r) {
    final maxVal = r.factors.values.fold<double>(0, (a, b) => a > b ? a : b);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: _gradeColor(r.grade).withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  '${r.lineNo}',
                  style: TextStyle(
                    color: _gradeColor(r.grade),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                r.riderName,
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const Spacer(),
              Text(
                '${r.rank}위',
                style: TextStyle(
                  color: r.rank == 1
                      ? const Color(0xFFFBBF24)
                      : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...r.factors.entries.map((e) {
            final ratio = maxVal > 0 ? (e.value / maxVal).clamp(0.05, 1.0) : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 60,
                    child: Text(
                      e.key,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: ratio,
                        minHeight: 6,
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        valueColor: AlwaysStoppedAnimation(
                          _factorColor(e.key).withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 30,
                    child: Text(
                      e.value.toStringAsFixed(1),
                      textAlign: TextAlign.right,
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ─── 안내 문구 ───

  Widget _buildDisclaimer(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFEF4444).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEF4444).withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFEF4444), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'AI 예측은 참고용이며, 실제 경주 결과와 다를 수 있습니다. '
              '베팅은 본인의 판단과 책임하에 진행하세요.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFFEF4444).withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 공통 위젯 ───

  Widget _sectionTitle(ThemeData theme, IconData icon, String title, Color color) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(width: 8),
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
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

  Color _factorColor(String factor) {
    return switch (factor) {
      '등급' => const Color(0xFFEF4444),
      '평균득점' => const Color(0xFF3B82F6),
      '최근 전적' => const Color(0xFF22C55E),
      '전법' => const Color(0xFF8B5CF6),
      _ => const Color(0xFF6B7280),
    };
  }
}
