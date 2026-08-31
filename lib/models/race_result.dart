import 'odds.dart';

/// 경주 결과 (공공데이터 경주결과 API 응답 기반)
///
/// 착순과 확정 배당은 API의 동일 레코드에서 함께 파싱하므로 항상 서로 일치한다.
class RaceResult {
  final int raceNo;
  final String first;
  final int firstNo;
  final String second;
  final int secondNo;
  final String third;
  final int thirdNo;

  /// 해당 경주의 승식별 확정 배당
  final Odds payoff;

  /// 회차 (예: 35회차)
  final int round;

  /// 회차 내 일차 (예: 3일차)
  final int dayOrd;

  const RaceResult({
    required this.raceNo,
    required this.first,
    required this.firstNo,
    required this.second,
    required this.secondNo,
    required this.third,
    required this.thirdNo,
    this.payoff = const Odds(),
    this.round = 0,
    this.dayOrd = 0,
  });

  bool get hasPlacings => firstNo > 0 || first.isNotEmpty;
}
