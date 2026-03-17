import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:table_calendar/table_calendar.dart';
import '../../race/providers/race_providers.dart';
import '../screens/home_screen.dart';

/// 월별 달력 BottomSheet - 날짜 클릭 시 표시
class MonthCalendarSheet {
  MonthCalendarSheet._();

  static Future<void> show(
    BuildContext context, {
    required DateTime selectedDate,
    required Function(DateTime) onDateSelected,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF161B22),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => _MonthCalendarSheetContent(
        selectedDate: selectedDate,
        onDateSelected: (d) {
          onDateSelected(d);
          Navigator.of(context).pop();
        },
      ),
    );
  }
}

class _MonthCalendarSheetContent extends ConsumerStatefulWidget {
  final DateTime selectedDate;
  final void Function(DateTime) onDateSelected;

  const _MonthCalendarSheetContent({
    required this.selectedDate,
    required this.onDateSelected,
  });

  @override
  ConsumerState<_MonthCalendarSheetContent> createState() =>
      _MonthCalendarSheetContentState();
}

class _MonthCalendarSheetContentState
    extends ConsumerState<_MonthCalendarSheetContent> {
  late DateTime _focusedDay;
  late DateTime _selectedDay;

  @override
  void initState() {
    super.initState();
    _focusedDay = widget.selectedDate;
    _selectedDay = widget.selectedDate;
  }

  String _dateToYmd(DateTime d) {
    return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final venue = ref.watch(selectedVenueProvider);
    final raceDatesAsync = ref.watch(monthRaceDatesProvider((
      venue: venue,
      year: _focusedDay.year,
      month: _focusedDay.month,
    )));
    final raceDates = raceDatesAsync.valueOrNull ?? {};

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${_focusedDay.year}년',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                IconButton(
                  icon: Icon(
                    Icons.close_rounded,
                    color: Colors.white.withValues(alpha: 0.8),
                  ),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TableCalendar(
              firstDay: DateTime(2020, 1, 1),
              lastDay: DateTime(2030, 12, 31),
              focusedDay: _focusedDay,
              selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
              calendarFormat: CalendarFormat.month,
              headerStyle: HeaderStyle(
                formatButtonVisible: false,
                titleCentered: true,
                titleTextFormatter: (date, _) => '${date.month}월',
                leftChevronIcon: Icon(
                  Icons.chevron_left_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                rightChevronIcon: Icon(
                  Icons.chevron_right_rounded,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
                headerPadding: const EdgeInsets.symmetric(vertical: 12),
                titleTextStyle: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              daysOfWeekStyle: DaysOfWeekStyle(
                weekdayStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
                weekendStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
              calendarStyle: CalendarStyle(
                defaultTextStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.9),
                  fontSize: 14,
                ),
                weekendTextStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.7),
                  fontSize: 14,
                ),
                outsideTextStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3),
                  fontSize: 14,
                ),
                selectedDecoration: const BoxDecoration(
                  color: Color(0xFFFBBF24),
                  shape: BoxShape.circle,
                ),
                selectedTextStyle: const TextStyle(
                  color: Colors.black87,
                  fontWeight: FontWeight.w700,
                ),
                todayDecoration: BoxDecoration(
                  color: const Color(0xFFFBBF24).withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: const Color(0xFFFBBF24),
                    width: 1.5,
                  ),
                ),
                todayTextStyle: const TextStyle(
                  color: Color(0xFFFBBF24),
                  fontWeight: FontWeight.w700,
                ),
                markerDecoration: const BoxDecoration(
                  color: Color(0xFF22C55E),
                  shape: BoxShape.circle,
                ),
                markerSize: 6,
              ),
              calendarBuilders: CalendarBuilders(
                dowBuilder: (context, day) {
                  const koreanDays = ['월', '화', '수', '목', '금', '토', '일'];
                  return Center(
                    child: Text(
                      koreanDays[day.weekday - 1],
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.6),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
                markerBuilder: (context, date, events) {
                  if (events.isEmpty) return null;
                  return Positioned(
                    left: 10,
                    right: 10,
                    bottom: 0,
                    child: Container(
                      height: 2,
                      color: Colors.white,
                    ),
                  );
                },
              ),
              eventLoader: (day) =>
                  raceDates.contains(_dateToYmd(day)) ? ['race'] : [],
              onDaySelected: (selectedDay, focusedDay) {
                setState(() {
                  _selectedDay = selectedDay;
                  _focusedDay = focusedDay;
                });
                widget.onDateSelected(selectedDay);
              },
              onPageChanged: (focusedDay) {
                setState(() => _focusedDay = focusedDay);
              },
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 14,
                  height: 2,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  '경기 있는 날',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
