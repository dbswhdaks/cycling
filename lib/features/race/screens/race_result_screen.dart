import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api_constants.dart';
import '../../../models/race_entry.dart';
import '../../../models/race_result.dart';
import '../../../models/odds.dart';
import '../../../models/prediction.dart';
import '../providers/race_providers.dart';

class RaceResultScreen extends ConsumerWidget {
  final int venueCode;
  final String date;
  final int raceNo;

  const RaceResultScreen({
    super.key,
    required this.venueCode,
    required this.date,
    required this.raceNo,
  });

  String get venueName => ApiConstants.venueName(venueCode);

  String get displayDate {
    if (date.length >= 8) {
      return '${date.substring(0, 4)}년 ${date.substring(4, 6)}월 ${date.substring(6, 8)}일';
    }
    return date;
  }

  bool get _isNotYetRace {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (date.length < 8) return false;
    final year = int.tryParse(date.substring(0, 4)) ?? 0;
    final month = int.tryParse(date.substring(4, 6)) ?? 0;
    final day = int.tryParse(date.substring(6, 8)) ?? 0;
    final raceDate = DateTime(year, month, day);
    return !raceDate.isBefore(today);
  }

  static bool _isNotYetError(Object error) =>
      error.toString().contains('NOT_YET');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resultAsync = ref.watch(raceResultProvider((
      venue: venueCode,
      date: date,
      raceNo: raceNo,
    )));
    final rankAsync = ref.watch(raceRankProvider((
      venue: venueCode,
      date: date,
      raceNo: raceNo,
    )));
    final predictionAsync = ref.watch(predictionProvider((
      venue: venueCode,
      date: date,
      raceNo: raceNo,
    )));
    final entriesAsync = ref.watch(raceEntriesProvider((
      venue: venueCode,
      date: date,
      raceNo: raceNo,
    )));
    final oddsAsync = ref.watch(oddsProvider((
      venue: venueCode,
      date: date,
      raceNo: raceNo,
    )));

    final isNotYet = _isNotYetRace
        || (_isNotYetError(rankAsync.error ?? '') && _isNotYetError(resultAsync.error ?? ''));

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          _buildAppBar(context),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildDateHeader(context, isNotYet: isNotYet),
                  const SizedBox(height: 24),
                  if (isNotYet)
                    _buildNotYetSection(context)
                  else
                    rankAsync.when(
                      data: (ranks) {
                        final unified = _unifiedResult(ranks, resultAsync.valueOrNull);
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPodium(context, unified),
                            const SizedBox(height: 28),
                            _buildComparisonSection(
                              context, unified, predictionAsync, entriesAsync,
                            ),
                            const SizedBox(height: 28),
                            _buildOddsResult(context, unified, oddsAsync),
                            const SizedBox(height: 28),
                            _buildRankingList(context, ranks),
                          ],
                        );
                      },
                      loading: () => _buildLoadingBox(400),
                      error: (_, __) => resultAsync.when(
                        data: (result) => Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildPodium(context, result),
                            const SizedBox(height: 28),
                            _buildComparisonSection(
                              context, result, predictionAsync, entriesAsync,
                            ),
                            const SizedBox(height: 28),
                            _buildOddsResult(context, result, oddsAsync),
                            const SizedBox(height: 28),
                            _buildRankingFromResult(context, result),
                          ],
                        ),
                        loading: () => _buildLoadingBox(200),
                        error: (_, __) => _buildErrorBox(context, '결과를 불러올 수 없습니다'),
                      ),
                    ),
                  const SizedBox(height: 24),
                  _buildDisclaimer(context),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 전체 순위 데이터를 기준으로 RaceResult를 생성 (단일 데이터 소스)
  RaceResult _unifiedResult(List<Map<String, dynamic>> ranks, RaceResult? fallback) {
    if (ranks.length < 3) return fallback ?? RaceResult(raceNo: raceNo, first: '', firstNo: 0, second: '', secondNo: 0, third: '', thirdNo: 0);

    final r1 = ranks[0];
    final r2 = ranks[1];
    final r3 = ranks[2];

    return RaceResult(
      raceNo: raceNo,
      first: r1['racer_nm']?.toString() ?? '',
      firstNo: (r1['back_no'] is int) ? r1['back_no'] : int.tryParse(r1['back_no']?.toString() ?? '') ?? 0,
      second: r2['racer_nm']?.toString() ?? '',
      secondNo: (r2['back_no'] is int) ? r2['back_no'] : int.tryParse(r2['back_no']?.toString() ?? '') ?? 0,
      third: r3['racer_nm']?.toString() ?? '',
      thirdNo: (r3['back_no'] is int) ? r3['back_no'] : int.tryParse(r3['back_no']?.toString() ?? '') ?? 0,
      winOdds: fallback?.winOdds ?? 0,
      placeOdds: fallback?.placeOdds ?? 0,
      quinellaOdds: fallback?.quinellaOdds ?? 0,
    );
  }

  // ─── AppBar ───

  Widget _buildAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 130,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
      flexibleSpace: FlexibleSpaceBar(
        title: Text('$venueName ${raceNo}R 결과'),
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFFFBBF24),
                Color(0xFFF59E0B),
                Color(0xFFD97706),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDateHeader(BuildContext context, {bool isNotYet = false}) {
    final theme = Theme.of(context);
    final statusColor = isNotYet ? const Color(0xFFF59E0B) : const Color(0xFF22C55E);
    final statusText = isNotYet ? '경기 전' : '확정';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFFBBF24).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.calendar_today_rounded, size: 18, color: Color(0xFFFBBF24)),
          const SizedBox(width: 8),
          Text(
            displayDate,
            style: theme.textTheme.bodyLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: statusColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              statusText,
              style: TextStyle(
                color: statusColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotYetSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 24),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFFF59E0B).withValues(alpha: 0.06)
            : const Color(0xFFF59E0B).withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFF59E0B).withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.schedule_rounded,
              size: 36,
              color: Color(0xFFF59E0B),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            '아직 경기가 진행되지 않았습니다',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$displayDate 경기는 아직 시작 전이므로\n결과를 확인할 수 없습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back_rounded, size: 18),
            label: const Text('돌아가기'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFF59E0B),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 포디움 (1·2·3위) ───

  Widget _buildPodium(BuildContext context, RaceResult result) {
    final theme = Theme.of(context);
    const podiumColors = [Color(0xFFFBBF24), Color(0xFFA3A3A3), Color(0xFFCD7F32)];

    final riders = [
      (name: result.first, no: result.firstNo, rank: 1),
      (name: result.second, no: result.secondNo, rank: 2),
      (name: result.third, no: result.thirdNo, rank: 3),
    ];
    final heights = [100.0, 100.0, 100.0];
    final colors = [podiumColors[0], podiumColors[1], podiumColors[2]];
    final labels = ['1st', '2nd', '3rd'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.emoji_events_rounded, size: 22, color: Color(0xFFFBBF24)),
            const SizedBox(width: 8),
            Text(
              '경주 결과',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.fromLTRB(12, 20, 12, 0),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFFFBBF24).withValues(alpha: 0.08),
                Colors.transparent,
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFBBF24).withValues(alpha: 0.2)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(3, (i) {
              final r = riders[i];
              final color = colors[i];
              final h = heights[i];
              final label = labels[i];

              return Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(color: color, width: 2.5),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        r.no > 0 ? '${r.no}' : '${r.rank}',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      r.name.isNotEmpty ? r.name : (r.no > 0 ? '${r.no}번' : '${r.rank}착'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      height: h,
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            color.withValues(alpha: 0.4),
                            color.withValues(alpha: 0.15),
                          ],
                        ),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        label,
                        style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  // ─── 확정 배당 ───

  Widget _buildOddsResult(BuildContext context, RaceResult result, AsyncValue<Odds> oddsAsync) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final odds = oddsAsync.valueOrNull;

    final f = result.firstNo;
    final s = result.secondNo;
    final t = result.thirdNo;

    final fName = result.first.isNotEmpty ? result.first : '';
    final sName = result.second.isNotEmpty ? result.second : '';
    final tName = result.third.isNotEmpty ? result.third : '';

    String num(int no) => no > 0 ? '$no' : '?';

    // 단승
    final winOdds = result.winOdds > 0 ? result.winOdds : odds?.win[f];

    // 복승
    final placeOdds = result.placeOdds > 0
        ? result.placeOdds
        : (odds?.place['$f-$s'] ?? odds?.place['$s-$f']);

    // 쌍승
    final quinOdds = result.quinellaOdds > 0
        ? result.quinellaOdds
        : (odds?.quinella['$f-$s'] ?? odds?.quinella['$s-$f']);

    // 삼복승
    double? trioOdds;
    if (odds != null) {
      final trioKeys = ['$f-$s-$t', '$f-$t-$s', '$s-$f-$t', '$s-$t-$f', '$t-$f-$s', '$t-$s-$f'];
      for (final k in trioKeys) {
        if (odds.trio.containsKey(k)) { trioOdds = odds.trio[k]; break; }
      }
    }

    // 삼쌍승
    final triOdds = odds?.trifecta['$f-$s-$t'];

    final items = <({String type, String combo, String detail, double? odds, Color color})>[
      (type: '단승', combo: '${num(f)}번 $fName', detail: '1착 맞추기', odds: winOdds, color: const Color(0xFFEF4444)),
      (type: '복승', combo: '${num(f)}-${num(s)}', detail: '1·2착 ${fName.isNotEmpty && sName.isNotEmpty ? "$fName·$sName" : "순서 무관"}', odds: placeOdds, color: const Color(0xFF3B82F6)),
      (type: '쌍승', combo: '${num(f)}→${num(s)}', detail: '1·2착 ${fName.isNotEmpty && sName.isNotEmpty ? "$fName→$sName" : "순서 맞추기"}', odds: quinOdds, color: const Color(0xFF8B5CF6)),
      (type: '삼복승', combo: '${num(f)}-${num(s)}-${num(t)}', detail: '1·2·3착 ${[fName, sName, tName].where((n) => n.isNotEmpty).join("·")}', odds: trioOdds, color: const Color(0xFFF59E0B)),
      (type: '삼쌍승', combo: '${num(f)}→${num(s)}→${num(t)}', detail: '1·2·3착 ${[fName, sName, tName].where((n) => n.isNotEmpty).join("→")}', odds: triOdds, color: const Color(0xFFEC4899)),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.paid_rounded, size: 20, color: Color(0xFF22C55E)),
            const SizedBox(width: 8),
            Text(
              '확정 배당',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...items.map((item) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: item.color.withValues(alpha: isDark ? 0.06 : 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: item.color.withValues(alpha: 0.2)),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: item.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  item.type,
                  style: TextStyle(color: item.color, fontSize: 12, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.combo,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      item.detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Text(
                item.odds != null ? '${item.odds!.toStringAsFixed(1)}배' : '-',
                style: TextStyle(
                  color: item.odds != null ? item.color : theme.colorScheme.onSurface.withValues(alpha: 0.3),
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        )),
      ],
    );
  }

  // ─── 전체 순위 ───

  Widget _buildRankingList(BuildContext context, List<Map<String, dynamic>> ranks) {
    final theme = Theme.of(context);
    if (ranks.isEmpty) return _buildErrorBox(context, '순위 데이터가 없습니다');
    final displayRanks = ranks.take(7).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.format_list_numbered_rounded, size: 20, color: Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            Text(
              '전체 순위',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF30363D)
                  : Colors.grey.withValues(alpha: 0.2),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildRankHeader(theme),
              ...displayRanks.asMap().entries.map((entry) =>
                  _buildRankRow(theme, entry.value, entry.key)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRankHeader(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.08),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: Text('순위', style: _headerStyle(theme)),
          ),
          SizedBox(
            width: 30,
            child: Text('번호', style: _headerStyle(theme)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text('선수', style: _headerStyle(theme))),
          SizedBox(
            width: 40,
            child: Text('등급', style: _headerStyle(theme), textAlign: TextAlign.center),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text('기록', style: _headerStyle(theme), textAlign: TextAlign.right),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text('착차', style: _headerStyle(theme), textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  TextStyle _headerStyle(ThemeData theme) {
    return TextStyle(
      color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
      fontSize: 11,
      fontWeight: FontWeight.w600,
    );
  }

  Widget _buildRankRow(ThemeData theme, Map<String, dynamic> rank, int index) {
    final rankNum = rank['rank'] as int? ?? (index + 1);
    final backNo = rank['back_no'] ?? '';
    final name = rank['racer_nm']?.toString() ?? '';
    final grade = rank['racer_grd_cd']?.toString() ?? '';
    final time = rank['race_time']?.toString() ?? '';
    final diff = rank['arrival_diff']?.toString() ?? '';

    const podiumColors = [Color(0xFFFBBF24), Color(0xFFA3A3A3), Color(0xFFCD7F32)];
    final isTop3 = rankNum <= 3;
    final rankColor = isTop3 ? podiumColors[rankNum - 1] : theme.colorScheme.onSurface.withValues(alpha: 0.4);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isTop3
            ? rankColor.withValues(alpha: isDark ? 0.06 : 0.04)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 36,
            child: isTop3
                ? Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: rankColor.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '$rankNum',
                      style: TextStyle(
                        color: rankColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  )
                : Text(
                    '$rankNum',
                    style: TextStyle(
                      color: rankColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
          ),
          SizedBox(
            width: 30,
            child: Text(
              '$backNo',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isTop3 ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: _gradeColor(grade).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  grade,
                  style: TextStyle(
                    color: _gradeColor(grade),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 60,
            child: Text(
              time,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 48,
            child: Text(
              diff,
              textAlign: TextAlign.right,
              style: theme.textTheme.bodySmall?.copyWith(
                color: rankNum == 1 ? const Color(0xFFFBBF24) : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 추천 비교 ───

  List<({int lineNo, String name})> _comprehensiveTop3(AsyncValue entriesAsync) {
    final val = entriesAsync.valueOrNull;
    if (val == null) return [];
    final entries = (val is DataWithSource ? val.data : val) as List;
    final typed = entries.cast<RaceEntry>();
    if (typed.isEmpty) return [];

    const gradeScores = {'S': 10.0, 'A1': 8.5, 'A2': 7.0, 'B1': 5.5, 'B2': 4.0, 'B3': 2.5};
    final scored = typed.map((e) {
      final g = gradeScores[e.grade] ?? 4.0;
      final a = e.avgScore.clamp(0, 10).toDouble();
      final r = e.recent3Wins * 2.0;
      return (entry: e, score: g * 3.0 + a * 2.5 + r);
    }).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    return scored.take(3).map((s) => (lineNo: s.entry.lineNo, name: s.entry.riderName)).toList();
  }

  Widget _buildComparisonSection(
    BuildContext context,
    RaceResult result,
    AsyncValue<RacePrediction> predictionAsync,
    AsyncValue entriesAsync,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final actual = [
      (lineNo: result.firstNo, name: result.first),
      (lineNo: result.secondNo, name: result.second),
      (lineNo: result.thirdNo, name: result.third),
    ];

    List<({int lineNo, String name})> aiTop3 = [];
    final pred = predictionAsync.valueOrNull;
    if (pred != null) {
      aiTop3 = pred.rankings.take(3).map((r) => (lineNo: r.lineNo, name: r.riderName)).toList();
    }

    final compTop3 = _comprehensiveTop3(entriesAsync);

    if (aiTop3.isEmpty && compTop3.isEmpty) return const SizedBox.shrink();

    int aiHits = 0;
    int compHits = 0;
    for (int i = 0; i < 3; i++) {
      final actualNo = actual[i].lineNo;
      if (aiTop3.length > i && aiTop3.any((r) => r.lineNo == actualNo)) aiHits++;
      if (compTop3.length > i && compTop3.any((r) => r.lineNo == actualNo)) compHits++;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.compare_arrows_rounded, size: 22, color: Color(0xFF8B5CF6)),
            const SizedBox(width: 8),
            Text(
              '추천 vs 실제 비교',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 14),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDark ? const Color(0xFF30363D) : Colors.grey.withValues(alpha: 0.2),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _compHeaderRow(theme, isDark),
              ...List.generate(3, (i) => _compDataRow(
                theme, isDark, i,
                actual: actual[i],
                ai: aiTop3.length > i ? aiTop3[i] : null,
                comp: compTop3.length > i ? compTop3[i] : null,
              )),
              _compSummaryRow(theme, isDark, aiHits: aiHits, compHits: compHits),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compHeaderRow(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.06),
      child: Row(
        children: [
          const SizedBox(width: 30, child: Text('')),
          Expanded(
            child: Center(
              child: Text('실제 결과', style: _compHeaderStyle(theme, const Color(0xFFFBBF24))),
            ),
          ),
          Expanded(
            child: Center(
              child: Text('AI 추천', style: _compHeaderStyle(theme, const Color(0xFF8B5CF6))),
            ),
          ),
          Expanded(
            child: Center(
              child: Text('종합추천', style: _compHeaderStyle(theme, const Color(0xFF22C55E))),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _compHeaderStyle(ThemeData theme, Color color) {
    return TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w700);
  }

  Widget _compDataRow(
    ThemeData theme,
    bool isDark,
    int index, {
    required ({int lineNo, String name}) actual,
    ({int lineNo, String name})? ai,
    ({int lineNo, String name})? comp,
  }) {
    const rankLabels = ['1착', '2착', '3착'];
    const rankColors = [Color(0xFFFBBF24), Color(0xFFA3A3A3), Color(0xFFCD7F32)];
    final color = rankColors[index];

    final aiMatch = ai != null && ai.lineNo == actual.lineNo;
    final compMatch = comp != null && comp.lineNo == actual.lineNo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.grey.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                rankLabels[index],
                style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.w800),
              ),
            ),
          ),
          Expanded(child: _compCell(theme, actual.lineNo, actual.name, color, true)),
          Expanded(
            child: ai != null
                ? _compCell(theme, ai.lineNo, ai.name, const Color(0xFF8B5CF6), aiMatch)
                : Center(child: Text('-', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3)))),
          ),
          Expanded(
            child: comp != null
                ? _compCell(theme, comp.lineNo, comp.name, const Color(0xFF22C55E), compMatch)
                : Center(child: Text('-', style: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3)))),
          ),
        ],
      ),
    );
  }

  Widget _compCell(ThemeData theme, int lineNo, String name, Color color, bool isMatch) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '$lineNo',
                style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                name.isNotEmpty ? name : '$lineNo번',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isMatch) ...[
              const SizedBox(width: 2),
              const Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF22C55E)),
            ],
          ],
        ),
      ],
    );
  }

  Widget _compSummaryRow(ThemeData theme, bool isDark, {required int aiHits, required int compHits}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      color: isDark
          ? const Color(0xFF8B5CF6).withValues(alpha: 0.04)
          : const Color(0xFF8B5CF6).withValues(alpha: 0.03),
      child: Row(
        children: [
          const SizedBox(width: 30, child: Icon(Icons.assessment_rounded, size: 16, color: Color(0xFF8B5CF6))),
          Expanded(
            child: Center(
              child: Text(
                '적중률',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Expanded(
            child: Center(child: _hitsBadge(aiHits, const Color(0xFF8B5CF6))),
          ),
          Expanded(
            child: Center(child: _hitsBadge(compHits, const Color(0xFF22C55E))),
          ),
        ],
      ),
    );
  }

  Widget _hitsBadge(int hits, Color color) {
    final label = '$hits/3 적중';
    final bgAlpha = hits >= 2 ? 0.2 : 0.1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  // ─── 전체 순위 (RaceResult 폴백용) ───

  Widget _buildRankingFromResult(BuildContext context, RaceResult result) {
    final theme = Theme.of(context);
    final entries = [
      if (result.firstNo > 0 || result.first.isNotEmpty)
        {'rank': 1, 'back_no': result.firstNo, 'racer_nm': result.first, 'racer_grd_cd': '', 'race_time': '', 'arrival_diff': '-'},
      if (result.secondNo > 0 || result.second.isNotEmpty)
        {'rank': 2, 'back_no': result.secondNo, 'racer_nm': result.second, 'racer_grd_cd': '', 'race_time': '', 'arrival_diff': ''},
      if (result.thirdNo > 0 || result.third.isNotEmpty)
        {'rank': 3, 'back_no': result.thirdNo, 'racer_nm': result.third, 'racer_grd_cd': '', 'race_time': '', 'arrival_diff': ''},
    ];
    if (entries.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.format_list_numbered_rounded, size: 20, color: Color(0xFF3B82F6)),
            const SizedBox(width: 8),
            Text(
              '전체 순위',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF30363D)
                  : Colors.grey.withValues(alpha: 0.2),
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildRankHeader(theme),
              ...entries.asMap().entries.map((e) => _buildRankRow(theme, e.value, e.key)),
            ],
          ),
        ),
      ],
    );
  }

  // ─── 안내 ───

  Widget _buildDisclaimer(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF3B82F6).withValues(alpha: 0.15)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF3B82F6), size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '경주 결과는 공공데이터 API 기준이며, 확정 배당은 실제와 차이가 있을 수 있습니다.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ─── 공통 ───

  Widget _buildLoadingBox(double height) {
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
      ),
      child: const Center(
        child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2)),
      ),
    );
  }

  Widget _buildErrorBox(BuildContext context, String message) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Text(message, style: theme.textTheme.bodyMedium),
        ],
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
}
