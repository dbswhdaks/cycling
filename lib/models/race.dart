/// 경주 계획 모델
class Race {
  final int venueCode;
  final String date;
  final int raceNo;
  final String venueName;
  final int distance;
  final String _rawStatus;
  final String? departureTime;
  final int racerCount;
  final int roundCount;

  const Race({
    required this.venueCode,
    required this.date,
    required this.raceNo,
    required this.venueName,
    this.distance = 2025,
    String status = '예정',
    this.departureTime,
    this.racerCount = 0,
    this.roundCount = 0,
  }) : _rawStatus = status;

  /// 확정/종료/완료 등 명시적 상태가 있으면 그대로 사용하고,
  /// 그 외에는 날짜 기반으로 과거면 '종료', 오늘 이후면 '예정' 반환
  String get status {
    if (_rawStatus == '종료' || _rawStatus == '확정' || _rawStatus == '완료') {
      return _rawStatus;
    }
    final cleaned = date.replaceAll('.', '').replaceAll('-', '');
    if (cleaned.length >= 8) {
      final raceDate = DateTime.tryParse(
        '${cleaned.substring(0, 4)}-${cleaned.substring(4, 6)}-${cleaned.substring(6, 8)}',
      );
      if (raceDate != null) {
        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        if (raceDate.isBefore(today)) return '종료';
      }
    }
    return _rawStatus;
  }

  String get displayDate {
    if (date.length >= 8) {
      return '${date.substring(4, 6)}/${date.substring(6, 8)}';
    }
    return date;
  }
}
