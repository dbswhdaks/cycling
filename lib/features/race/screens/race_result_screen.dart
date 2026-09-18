import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/services/prediction_engine.dart';
import '../../../models/race_entry.dart';
import '../../../models/race_result.dart';
import '../../../models/odds.dart';
import '../../../models/prediction.dart';
import '../providers/race_providers.dart';

class RaceResultScreen extends ConsumerStatefulWidget {
  final int venueCode;
  final String date;
  final int raceNo;

  const RaceResultScreen({
    super.key,
    required this.venueCode,
    required this.date,
    required this.raceNo,
  });

  @override
  ConsumerState<RaceResultScreen> createState() => _RaceResultScreenState();
}

class _RaceResultScreenState extends ConsumerState<RaceResultScreen> {
  Timer? _autoRefreshTimer;
  bool _isRefreshing = false;
  int _refreshCount = 0;

  /// 사용자가 저장한 "나의 선택" 번호 (1~3착까지 비교용).
  List<int?> _userPicks = List.filled(3, null);

  int get venueCode => widget.venueCode;
  String get date => widget.date;
  int get raceNo => widget.raceNo;

  String get _userPicksKey => 'picks_${venueCode}_${date}_$raceNo';

  String get venueName => ApiConstants.venueName(venueCode);

  String get displayDate {
    if (date.length >= 8) {
      return '${date.substring(0, 4)}년 ${date.substring(4, 6)}월 ${date.substring(6, 8)}일';
    }
    return date;
  }

  bool get _isTodayRace {
    if (date.length < 8) return false;
    final now = DateTime.now();
    final todayStr = '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}';
    return date == todayStr;
  }

  bool get _isNotYetRace {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    if (date.length < 8) return false;
    final year = int.tryParse(date.substring(0, 4)) ?? 0;
    final month = int.tryParse(date.substring(4, 6)) ?? 0;
    final day = int.tryParse(date.substring(6, 8)) ?? 0;
    final raceDate = DateTime(year, month, day);
    return raceDate.isAfter(today);
  }

  /// 오늘 경기인데 출발 시간이 아직 안 됐는지 판단.
  /// `departureTime`은 "10:35" 또는 '10"35' 형태.
  /// 결과가 확정되기까지 대략 5분 여유를 둔다.
  bool _isTodayRaceNotStartedYet(String? departureTime) {
    if (!_isTodayRace) return false;
    if (departureTime == null || departureTime.isEmpty) return false;
    final timeStr = departureTime.replaceAll('"', ':');
    final parts = timeStr.split(':');
    if (parts.length < 2) return false;
    final hour = int.tryParse(parts[0]) ?? -1;
    final minute = int.tryParse(parts[1]) ?? -1;
    if (hour < 0 || minute < 0) return false;
    final now = DateTime.now();
    final finishAt = DateTime(now.year, now.month, now.day, hour, minute)
        .add(const Duration(minutes: 5));
    return now.isBefore(finishAt);
  }

  static bool _isNotYetError(Object error) =>
      error.toString().contains('NOT_YET');

  static bool _isNoDataError(Object error) =>
      error.toString().contains('NO_DATA');

  @override
  void initState() {
    super.initState();
    _startAutoRefreshIfNeeded();
    _loadUserPicks();
  }

  Future<void> _loadUserPicks() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList(_userPicksKey);
    if (!mounted) return;
    if (saved == null) return;
    final loaded = List<int?>.filled(3, null);
    for (var i = 0; i < saved.length && i < 3; i++) {
      loaded[i] = int.tryParse(saved[i]);
    }
    setState(() => _userPicks = loaded);
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  void _startAutoRefreshIfNeeded() {
    if (!_isTodayRace) return;
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _refreshData();
    });
  }

  void _stopAutoRefresh() {
    _autoRefreshTimer?.cancel();
    _autoRefreshTimer = null;
  }

  void _refreshData() {
    if (!mounted) return;
    setState(() {
      _isRefreshing = true;
      _refreshCount++;
    });
    final params = (venue: venueCode, date: date, raceNo: raceNo);
    ref.invalidate(raceResultProvider(params));
    ref.invalidate(raceRankProvider(params));
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _isRefreshing = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final params = (venue: venueCode, date: date, raceNo: raceNo);
    final resultAsync = ref.watch(raceResultProvider(params));
    final rankAsync = ref.watch(raceRankProvider(params));
    final predictionAsync = ref.watch(predictionProvider(params));
    final entriesAsync = ref.watch(raceEntriesProvider(params));
    final raceListAsync =
        ref.watch(raceListProvider((venue: venueCode, date: date)));

    final currentRace = raceListAsync.valueOrNull?.data
        .where((r) => r.raceNo == raceNo)
        .firstOrNull;
    final isTodayNotStarted =
        _isTodayRaceNotStartedYet(currentRace?.departureTime);

    final isNotYet = _isNotYetRace
        || isTodayNotStarted
        || (_isNotYetError(rankAsync.error ?? '') && _isNotYetError(resultAsync.error ?? ''));

    if (!isNotYet && _autoRefreshTimer != null && !_isTodayRace) {
      _stopAutoRefresh();
    }

    return Scaffold(
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          slivers: [
            _buildAppBar(context, isNotYet: isNotYet),
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
                              _buildPodium(context, unified, ranks),
                              const SizedBox(height: 28),
                              _buildComparisonSection(
                                context, unified, predictionAsync, entriesAsync,
                              ),
                              const SizedBox(height: 28),
                              _buildOddsResult(context, unified, ranks),
                              const SizedBox(height: 28),
                              _buildRankingList(context, ranks),
                            ],
                          );
                        },
                        loading: () => _buildLoadingBox(400),
                        error: (rankError, __) => resultAsync.when(
                          data: (result) => Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildPodium(context, result),
                              const SizedBox(height: 28),
                              _buildComparisonSection(
                                context, result, predictionAsync, entriesAsync,
                              ),
                              const SizedBox(height: 28),
                              _buildOddsResult(context, result),
                              const SizedBox(height: 28),
                              _buildRankingFromResult(context, result),
                            ],
                          ),
                          loading: () => _buildLoadingBox(200),
                          error: (resultError, __) =>
                              _isNoDataError(resultError) &&
                                  _isNoDataError(rankError)
                              ? _buildNoDataSection(context)
                              : _buildErrorBox(context, '결과를 불러올 수 없습니다'),
                        ),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 착순·배당이 한 레코드에서 오는 경주결과를 우선 사용하고,
  /// 결과가 없을 때만 전체 순위 목록으로 1·2·3착을 구성한다.
  RaceResult _unifiedResult(
    List<Map<String, dynamic>> ranks,
    RaceResult? apiResult,
  ) {
    if (apiResult != null && apiResult.hasPlacings) return apiResult;

    const empty = RaceResult(
      raceNo: 0,
      first: '',
      firstNo: 0,
      second: '',
      secondNo: 0,
      third: '',
      thirdNo: 0,
    );
    if (ranks.length < 3) return apiResult ?? empty;

    int backNo(Map<String, dynamic> r) {
      final v = r['back_no'];
      return v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;
    }

    return RaceResult(
      raceNo: raceNo,
      first: ranks[0]['racer_nm']?.toString() ?? '',
      firstNo: backNo(ranks[0]),
      second: ranks[1]['racer_nm']?.toString() ?? '',
      secondNo: backNo(ranks[1]),
      third: ranks[2]['racer_nm']?.toString() ?? '',
      thirdNo: backNo(ranks[2]),
      payoff: apiResult?.payoff ?? const Odds(),
    );
  }

  // ─── AppBar ───

  Widget _buildAppBar(BuildContext context, {bool isNotYet = false}) {
    return SliverAppBar(
      expandedHeight: 130,
      pinned: true,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => Navigator.of(context).pop(),
      ),
      actions: [
        if (_isRefreshing)
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            ),
          )
        else
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: '새로고침',
            onPressed: _refreshData,
          ),
      ],
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
          GestureDetector(
            onTap: () => context.push('/video'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.play_circle_outline_rounded,
                      size: 14, color: Color(0xFFF59E0B)),
                  SizedBox(width: 4),
                  Text(
                    '경주 영상',
                    style: TextStyle(
                      color: Color(0xFFF59E0B),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
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
    final isAutoRefreshing = _autoRefreshTimer != null && _isTodayRace;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
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
            child: isAutoRefreshing
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 56,
                        height: 56,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
                        ),
                      ),
                      const Icon(
                        Icons.schedule_rounded,
                        size: 30,
                        color: Color(0xFFF59E0B),
                      ),
                    ],
                  )
                : const Icon(
                    Icons.schedule_rounded,
                    size: 36,
                    color: Color(0xFFF59E0B),
                  ),
          ),
          const SizedBox(height: 20),
          Text(
            '경기 결과 대기 중',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            isAutoRefreshing
                ? '경기가 끝나면 결과가 자동으로 표시됩니다.\n30초마다 자동 새로고침 중...'
                : '$displayDate 경기는 아직 시작 전이므로\n결과를 확인할 수 없습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
          if (isAutoRefreshing && _refreshCount > 0) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '새로고침 $_refreshCount회 완료',
                style: const TextStyle(
                  color: Color(0xFF3B82F6),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              FilledButton.icon(
                onPressed: _refreshData,
                icon: _isRefreshing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.refresh_rounded, size: 18),
                label: Text(_isRefreshing ? '확인 중...' : '지금 확인'),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFFBBF24),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                label: const Text('돌아가기'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  side: BorderSide(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildNoDataSection(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        children: [
          Icon(
            Icons.search_off_rounded,
            size: 40,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 16),
          Text(
            '공개된 경주 결과가 없습니다',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$displayDate $venueName ${raceNo}R은\n'
            '공식 자료에서 결과를 찾을 수 없습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: _refreshData,
            icon: const Icon(Icons.refresh_rounded, size: 18),
            label: const Text('다시 확인'),
            style: OutlinedButton.styleFrom(
              foregroundColor: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              side: BorderSide(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.2),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

  Widget _buildPodium(
    BuildContext context,
    RaceResult result, [
    List<Map<String, dynamic>> ranks = const [],
  ]) {
    final theme = Theme.of(context);
    const podiumColors = [Color(0xFFFBBF24), Color(0xFFA3A3A3), Color(0xFFCD7F32)];

    // 동착이면 두 선수가 같은 순위이므로 착순표의 실제 순위를 우선한다.
    final rankByBackNo = {
      for (final r in ranks)
        if (r['back_no'] is int && r['rank'] is int)
          r['back_no'] as int: r['rank'] as int,
    };
    int actualRank(int backNo, int fallback) => rankByBackNo[backNo] ?? fallback;

    final riders = [
      (name: result.first, no: result.firstNo, rank: actualRank(result.firstNo, 1)),
      (name: result.second, no: result.secondNo, rank: actualRank(result.secondNo, 2)),
      (name: result.third, no: result.thirdNo, rank: actualRank(result.thirdNo, 3)),
    ];
    const heights = [100.0, 100.0, 100.0];
    final colors = [
      for (final r in riders) podiumColors[(r.rank - 1).clamp(0, 2)],
    ];
    final labels = [for (final r in riders) _ordinalLabel(r.rank)];

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

  /// 확정 배당을 승식별로 나열한다.
  ///
  /// 동착 경주는 한 승식에 적중 조합이 둘 이상 나오므로 착순 조합 하나만
  /// 골라 쓰지 않고 API가 확정한 조합을 모두 보여준다.
  Widget _buildOddsResult(
    BuildContext context,
    RaceResult result, [
    List<Map<String, dynamic>> ranks = const [],
  ]) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final payoff = result.payoff;

    final nameByNo = <int, String>{
      for (final r in ranks)
        if (r['back_no'] is int) r['back_no'] as int: r['racer_nm']?.toString() ?? '',
      if (result.firstNo > 0) result.firstNo: result.first,
      if (result.secondNo > 0) result.secondNo: result.second,
      if (result.thirdNo > 0) result.thirdNo: result.third,
    };

    String amount(double odds) => '${odds.toStringAsFixed(1)}배';
    List<int> numbers(String key) =>
        key.split('-').map((n) => int.tryParse(n) ?? 0).toList();
    String names(String key, String separator) => numbers(key)
        .map((no) => nameByNo[no] ?? '')
        .where((n) => n.isNotEmpty)
        .join(separator);

    final items = <({String type, String combo, String detail, String value, Color color})>[];

    for (final entry in payoff.win.entries) {
      items.add((
        type: '단승',
        combo: '${entry.key}번 ${nameByNo[entry.key] ?? ''}'.trim(),
        detail: '1착 맞추기',
        value: amount(entry.value),
        color: const Color(0xFFEF4444),
      ));
    }

    if (payoff.place.isNotEmpty) {
      items.add((
        type: '연승',
        combo: payoff.place.keys.map((no) => '$no번').join(' · '),
        detail: '2착 안에 드는 선수 각각',
        value: '${payoff.place.values.map((o) => o.toStringAsFixed(1)).join(' / ')}배',
        color: const Color(0xFF14B8A6),
      ));
    }

    void addCombos(
      String type,
      Map<String, double> pool, {
      required String Function(List<int> nos) format,
      required String detail,
      String? nameSeparator,
      required Color color,
    }) {
      for (final entry in pool.entries) {
        final riders = nameSeparator == null ? '' : names(entry.key, nameSeparator);
        items.add((
          type: type,
          combo: format(numbers(entry.key)),
          detail: riders.isEmpty ? detail : '$detail $riders',
          value: amount(entry.value),
          color: color,
        ));
      }
    }

    addCombos('쌍승', payoff.exacta,
        format: (nos) => nos.join('→'),
        detail: '1·2착',
        nameSeparator: '→',
        color: const Color(0xFF8B5CF6));
    addCombos('복승', payoff.quinella,
        format: (nos) => nos.join('·'),
        detail: '1·2착',
        nameSeparator: '·',
        color: const Color(0xFF3B82F6));
    addCombos('삼복승', payoff.trio,
        format: (nos) => nos.join('·'),
        detail: '1·2·3착 순서 무관',
        color: const Color(0xFFF59E0B));
    addCombos('쌍복승', payoff.exactaTrio,
        format: (nos) => nos.length == 3
            ? '${nos[0]}→${nos[1]}·${nos[2]}'
            : nos.join('·'),
        detail: '1·2착 순서 맞추고 3착 포함',
        color: const Color(0xFF22C55E));
    addCombos('삼쌍승', payoff.trifecta,
        format: (nos) => nos.join('→'),
        detail: '1·2·3착',
        nameSeparator: '→',
        color: const Color(0xFFEC4899));

    if (items.isEmpty) return const SizedBox.shrink();

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
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.5),
                        fontSize: 11,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              Text(
                item.value,
                style: TextStyle(
                  color: item.value == '-'
                      ? theme.colorScheme.onSurface.withValues(alpha: 0.3)
                      : item.color,
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
            width: 32,
            child: Text('순위', style: _headerStyle(theme)),
          ),
          SizedBox(
            width: 26,
            child: Text('번호', style: _headerStyle(theme)),
          ),
          const SizedBox(width: 6),
          Expanded(child: Text('선수', style: _headerStyle(theme))),
          SizedBox(
            width: 42,
            child: Text('등급', style: _headerStyle(theme), textAlign: TextAlign.center),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: Text('기록', style: _headerStyle(theme), textAlign: TextAlign.right),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
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
    final rawRank = rank['rank'];
    final rankNum = rawRank is int
        ? rawRank
        : int.tryParse(rawRank?.toString() ?? '') ?? (index + 1);
    final backNo = rank['back_no'] ?? '';
    final name = rank['racer_nm']?.toString() ?? '';
    final grade = rank['racer_grd_cd']?.toString() ?? '';
    final time = rank['race_time']?.toString() ?? '';
    final diff = rank['arrival_diff']?.toString() ?? '';

    const podiumColors = [Color(0xFFFBBF24), Color(0xFFA3A3A3), Color(0xFFCD7F32)];
    final isTop3 = rankNum >= 1 && rankNum <= 3;
    final rankColor = isTop3 ? podiumColors[rankNum - 1] : theme.colorScheme.onSurface.withValues(alpha: 0.4);
    final isDark = theme.brightness == Brightness.dark;
    final rankLabel = rankNum > 0 ? '$rankNum' : '-';

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
            width: 32,
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
                      rankLabel,
                      style: TextStyle(
                        color: rankColor,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                  )
                : Text(
                    rankLabel,
                    style: TextStyle(
                      color: rankColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
          ),
          SizedBox(
            width: 26,
            child: Text(
              '$backNo',
              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isTop3 ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
          SizedBox(
            width: 42,
            child: Center(
              child: grade.isEmpty
                  ? const SizedBox.shrink()
                  : Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      decoration: BoxDecoration(
                        color: _gradeColor(grade).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        grade,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          color: _gradeColor(grade),
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: Text(
              time,
              textAlign: TextAlign.right,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                fontFamily: 'monospace',
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 44,
            child: Text(
              diff,
              textAlign: TextAlign.right,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 11,
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

    return PredictionEngine.predict(typed).rankings.take(3).map((rider) {
      return (lineNo: rider.lineNo, name: rider.riderName);
    }).toList();
  }

  Widget _buildComparisonSection(
    BuildContext context,
    RaceResult result,
    AsyncValue<RacePrediction> predictionAsync,
    AsyncValue entriesAsync,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isSubscribed = ref.watch(isSubscribedProvider);

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
    final userTop3 = _userTop3(entriesAsync);

    if (aiTop3.isEmpty && compTop3.isEmpty && userTop3.isEmpty) {
      return const SizedBox.shrink();
    }

    int aiHits = 0;
    int compHits = 0;
    int userHits = 0;
    for (int i = 0; i < 3; i++) {
      final actualNo = actual[i].lineNo;
      if (aiTop3.any((r) => r.lineNo == actualNo)) aiHits++;
      if (compTop3.any((r) => r.lineNo == actualNo)) compHits++;
      if (userTop3.any((r) => r != null && r.lineNo == actualNo)) userHits++;
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
        if (!isSubscribed)
          _buildComparisonPaywallCard(theme)
        else
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
                  user: userTop3.length > i ? userTop3[i] : null,
                )),
                _compSummaryRow(
                  theme,
                  isDark,
                  aiHits: aiHits,
                  compHits: compHits,
                  userHits: userHits,
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// SharedPreferences 에 저장된 "나의 선택"을 1~3착 순서로 반환.
  /// 해당 슬롯이 비어있으면 `null`.
  List<({int lineNo, String name})?> _userTop3(AsyncValue entriesAsync) {
    final val = entriesAsync.valueOrNull;
    List<RaceEntry> entries = const [];
    if (val != null) {
      final list = (val is DataWithSource ? val.data : val) as List;
      entries = list.cast<RaceEntry>();
    }

    return List.generate(3, (i) {
      final no = _userPicks.length > i ? _userPicks[i] : null;
      if (no == null) return null;
      final name = entries
              .where((e) => e.lineNo == no)
              .firstOrNull
              ?.riderName ??
          '';
      return (lineNo: no, name: name);
    });
  }

  Widget _buildComparisonPaywallCard(ThemeData theme) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.lock_outline_rounded,
            size: 30,
            color: Color(0xFF8B5CF6),
          ),
          const SizedBox(height: 10),
          Text(
            '추천 vs 실제 비교는 구독 후 이용할 수 있습니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '결제 완료 후 앱으로 돌아오면 자동으로 잠금이 해제됩니다.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: () => context.push('/subscription'),
              icon: const Icon(Icons.workspace_premium_rounded),
              label: const Text('구독하고 비교 보기'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFB45309),
                foregroundColor: Colors.white,
                elevation: 0,
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _compHeaderRow(ThemeData theme, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.06),
      child: Row(
        children: [
          const SizedBox(width: 28, child: Text('')),
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
          Expanded(
            child: Center(
              child: Text('나의 선택', style: _compHeaderStyle(theme, const Color(0xFFFFD700))),
            ),
          ),
        ],
      ),
    );
  }

  TextStyle _compHeaderStyle(ThemeData theme, Color color) {
    return TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w700);
  }

  Widget _compDataRow(
    ThemeData theme,
    bool isDark,
    int index, {
    required ({int lineNo, String name}) actual,
    ({int lineNo, String name})? ai,
    ({int lineNo, String name})? comp,
    ({int lineNo, String name})? user,
  }) {
    const rankLabels = ['1착', '2착', '3착'];
    const rankColors = [Color(0xFFFBBF24), Color(0xFFA3A3A3), Color(0xFFCD7F32)];
    final color = rankColors[index];

    final aiMatch = ai != null && ai.lineNo == actual.lineNo;
    final compMatch = comp != null && comp.lineNo == actual.lineNo;
    final userMatch = user != null && user.lineNo == actual.lineNo;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
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
            width: 28,
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
                : _compEmptyCell(theme),
          ),
          Expanded(
            child: comp != null
                ? _compCell(theme, comp.lineNo, comp.name, const Color(0xFF22C55E), compMatch)
                : _compEmptyCell(theme),
          ),
          Expanded(
            child: user != null
                ? _compCell(theme, user.lineNo, user.name, const Color(0xFFFFD700), userMatch)
                : _compEmptyCell(theme),
          ),
        ],
      ),
    );
  }

  Widget _compEmptyCell(ThemeData theme) {
    return Center(
      child: Text(
        '-',
        style: TextStyle(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.3),
        ),
      ),
    );
  }

  Widget _compCell(ThemeData theme, int lineNo, String name, Color color, bool isMatch) {
    final displayName = name.isNotEmpty ? name : '$lineNo번';
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 20,
          height: 20,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            shape: BoxShape.circle,
          ),
          alignment: Alignment.center,
          child: Text(
            '$lineNo',
            style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w700),
          ),
        ),
        const SizedBox(width: 3),
        Flexible(
          child: Text(
            displayName,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (isMatch) ...[
          const SizedBox(width: 1),
          const Icon(Icons.check_circle_rounded, size: 11, color: Color(0xFF22C55E)),
        ],
      ],
    );
  }

  Widget _compSummaryRow(
    ThemeData theme,
    bool isDark, {
    required int aiHits,
    required int compHits,
    required int userHits,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      color: isDark
          ? const Color(0xFF8B5CF6).withValues(alpha: 0.04)
          : const Color(0xFF8B5CF6).withValues(alpha: 0.03),
      child: Row(
        children: [
          const SizedBox(
            width: 28,
            child: Icon(Icons.assessment_rounded, size: 16, color: Color(0xFF8B5CF6)),
          ),
          Expanded(
            child: Center(
              child: Text(
                '적중률',
                style: TextStyle(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  fontSize: 11,
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
          Expanded(
            child: Center(child: _hitsBadge(userHits, const Color(0xFFFFD700))),
          ),
        ],
      ),
    );
  }

  Widget _hitsBadge(int hits, Color color) {
    final label = '$hits/3';
    final bgAlpha = hits >= 2 ? 0.2 : 0.1;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: bgAlpha),
        borderRadius: BorderRadius.circular(8),
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

  String _ordinalLabel(int rank) => switch (rank) {
    1 => '1st',
    2 => '2nd',
    3 => '3rd',
    _ => '${rank}th',
  };

  Color _gradeColor(String grade) {
    return switch (grade) {
      'S' => const Color(0xFFE53935),
      'A1' => const Color(0xFFF57C00),
      'A2' => const Color(0xFFFDD835),
      'B1' => const Color(0xFF43A047),
      'B2' => const Color(0xFF1E88E5),
      'B3' => const Color(0xFF8E24AA),
      '특선' || '특선급' || '우결' => const Color(0xFFE53935),
      '우수' || '우수급' || '선결' => const Color(0xFFF57C00),
      '선발' || '선발급' || '일반' => const Color(0xFF43A047),
      _ => const Color(0xFF9E9E9E),
    };
  }
}
