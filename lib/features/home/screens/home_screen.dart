import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/widgets/shimmer_loading.dart';
import '../../../models/race.dart';
import '../../race/providers/race_providers.dart';
import '../widgets/month_calendar_sheet.dart';
import '../widgets/race_card.dart';

final selectedVenueProvider = StateProvider<int>((ref) => 1);

final _lastRefreshProvider = StateProvider<DateTime>((ref) => DateTime.now());

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  static const List<({String name, int code})> venues = [
    (name: '광명스피돔', code: 1),
    (name: '창원경륜장', code: 2),
    (name: '부산경륜장', code: 3),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedVenue = ref.watch(selectedVenueProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final dateYmd = _dateToYmd(selectedDate);
    final racesAsync = ref.watch(
      raceListProvider((venue: selectedVenue, date: dateYmd)),
    );

    return Scaffold(
      backgroundColor: const Color(0xFF0D1117),
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(context, ref, racesAsync),
            _buildVenueTabs(ref, selectedVenue),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _buildDateSelector(context, ref),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: _buildUpdateRow(ref, selectedVenue, dateYmd),
            ),
            Expanded(
              child: racesAsync.when(
                data: (result) => result.data.isEmpty
                    ? _buildEmptyState(result.apiError)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: result.data.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) =>
                            RaceCard(race: result.data[index]),
                      ),
                loading: () => const SingleChildScrollView(
                  padding: EdgeInsets.all(20),
                  child: ShimmerRaceList(),
                ),
                error: (_, __) => SingleChildScrollView(
                  child: _buildErrorFallback(
                    context,
                    ref,
                    selectedVenue,
                    dateYmd,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ─── AppBar ───

  Widget _buildAppBar(
    BuildContext context,
    WidgetRef ref,
    AsyncValue<DataWithSource<List<Race>>> racesAsync,
  ) {
    final selectedVenue = ref.watch(selectedVenueProvider);
    final selectedDate = ref.watch(selectedDateProvider);
    final venueName = venues
        .firstWhere(
          (v) => v.code == selectedVenue,
          orElse: () => (name: '경륜', code: 1),
        )
        .name;
    final dateStr =
        '${selectedDate.year}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.day.toString().padLeft(2, '0')}';
    final raceCount = racesAsync.valueOrNull?.data.length ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.emoji_events_rounded,
            color: Color(0xFFFBBF24),
            size: 28,
          ),
          const SizedBox(width: 10),
          const Text(
            '경륜 Plus',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: Icon(
              Icons.share_rounded,
              color: Colors.white.withValues(alpha: 0.8),
              size: 22,
            ),
            onPressed: () {
              Share.share(
                '경륜 Plus - $venueName $dateStr\n'
                '오늘의 경주 $raceCount경기\n\n'
                '경륜 경주 정보를 확인해 보세요!',
                subject: '경륜 Plus - $venueName $dateStr',
              );
            },
          ),
        ],
      ),
    );
  }

  // ─── 경기장 탭 ───

  Widget _buildVenueTabs(WidgetRef ref, int selectedVenue) {
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
        ),
      ),
      child: Row(
        children: venues.map((v) {
          final isSelected = selectedVenue == v.code;
          return Expanded(
            child: GestureDetector(
              onTap: () =>
                  ref.read(selectedVenueProvider.notifier).state = v.code,
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected
                          ? const Color(0xFFFBBF24)
                          : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                alignment: Alignment.center,
                child: Text(
                  v.name,
                  style: TextStyle(
                    color: isSelected
                        ? const Color(0xFFFBBF24)
                        : Colors.white.withValues(alpha: 0.45),
                    fontSize: 15,
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

  // ─── 날짜 선택 ───

  Widget _buildDateSelector(BuildContext context, WidgetRef ref) {
    final selectedDate = ref.watch(selectedDateProvider);
    final today = DateTime.now();
    const weekdays = ['월', '화', '수', '목', '금', '토', '일'];
    final weekday = weekdays[selectedDate.weekday - 1];
    final dateStr =
        '${selectedDate.year}.${selectedDate.month.toString().padLeft(2, '0')}.${selectedDate.day.toString().padLeft(2, '0')} ($weekday)';
    final isToday = _isSameDay(selectedDate, today);

    return Row(
      children: [
        _navButton(Icons.chevron_left_rounded, () {
          ref.read(selectedDateProvider.notifier).state = selectedDate.subtract(
            const Duration(days: 1),
          );
        }),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            onTap: () {
              MonthCalendarSheet.show(
                context,
                selectedDate: selectedDate,
                onDateSelected: (d) {
                  ref.read(selectedDateProvider.notifier).state = DateTime(
                    d.year,
                    d.month,
                    d.day,
                  );
                },
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFBBF24).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.4),
                ),
              ),
              alignment: Alignment.center,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    dateStr,
                    style: const TextStyle(
                      color: Color(0xFFFBBF24),
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (isToday) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFBBF24).withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Text(
                        '오늘',
                        style: TextStyle(
                          color: Color(0xFFFBBF24),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        _navButton(Icons.chevron_right_rounded, () {
          ref.read(selectedDateProvider.notifier).state = selectedDate.add(
            const Duration(days: 1),
          );
        }),
      ],
    );
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.06),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white.withValues(alpha: 0.7), size: 22),
      ),
    );
  }

  // ─── 업데이트 시간 + 새로고침 ───

  Widget _buildUpdateRow(WidgetRef ref, int selectedVenue, String dateYmd) {
    final lastRefresh = ref.watch(_lastRefreshProvider);
    final racesAsync = ref.watch(
      raceListProvider((venue: selectedVenue, date: dateYmd)),
    );
    final diff = DateTime.now().difference(lastRefresh);
    final timeText = diff.inMinutes > 0
        ? '${diff.inMinutes}분 전 업데이트'
        : '${diff.inSeconds}초 전 업데이트';

    final sourceText = racesAsync.whenOrNull(
      data: (result) {
        if (result.fromApi) return 'API';
        if (result.apiError == '캐시 데이터') return '캐시';
        if (result.apiError != null) return '목업';
        return null;
      },
    );

    return Row(
      children: [
        Text(
          timeText,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.4),
            fontSize: 12,
          ),
        ),
        if (sourceText != null) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: sourceText == 'API'
                  ? const Color(0xFF22C55E).withValues(alpha: 0.15)
                  : sourceText == '캐시'
                      ? const Color(0xFF3B82F6).withValues(alpha: 0.15)
                      : const Color(0xFFF59E0B).withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              sourceText,
              style: TextStyle(
                color: sourceText == 'API'
                    ? const Color(0xFF22C55E)
                    : sourceText == '캐시'
                        ? const Color(0xFF3B82F6)
                        : const Color(0xFFF59E0B),
                fontSize: 10,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
        const SizedBox(width: 4),
        GestureDetector(
          onTap: () {
            ref.read(_lastRefreshProvider.notifier).state = DateTime.now();
            ref.read(cyclingApiServiceProvider).invalidateOrganCache();
            ref.read(supabaseBackupProvider).clearCacheForDate(dateYmd);
            for (final v in venues) {
              ref.invalidate(
                raceListProvider((venue: v.code, date: dateYmd)),
              );
            }
          },
          child: Icon(
            Icons.refresh_rounded,
            color: Colors.white.withValues(alpha: 0.4),
            size: 16,
          ),
        ),
      ],
    );
  }

  // ─── 빈 상태 ───

  Widget _buildEmptyState(String? apiError) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.event_busy_rounded,
            size: 56,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            '경기가 없습니다',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (apiError != null) ...[
            const SizedBox(height: 6),
            Text(
              apiError,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.25),
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 에러 상태 ───

  Widget _buildErrorFallback(
    BuildContext context,
    WidgetRef ref,
    int venue,
    String dateYmd,
  ) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_rounded,
            size: 48,
            color: const Color(0xFFFBBF24).withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            'API 연결 실패',
            style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton.icon(
                onPressed: () => ref.invalidate(
                  raceListProvider((venue: venue, date: dateYmd)),
                ),
                icon: const Icon(Icons.refresh, color: Color(0xFFFBBF24)),
                label: const Text(
                  '다시 시도',
                  style: TextStyle(color: Color(0xFFFBBF24)),
                ),
              ),
              TextButton.icon(
                onPressed: () => context.push('/settings'),
                icon: const Icon(Icons.settings, color: Color(0xFF3B82F6)),
                label: const Text(
                  'API 설정',
                  style: TextStyle(color: Color(0xFF3B82F6)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ─── 유틸 ───

  String _dateToYmd(DateTime d) {
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}
