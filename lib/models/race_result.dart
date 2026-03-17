/// 경주 결과 모델 (공공데이터 API 응답 기반)
class RaceResult {
  final int raceNo;
  final String first;
  final int firstNo;
  final String second;
  final int secondNo;
  final String third;
  final int thirdNo;
  final double winOdds;
  final double placeOdds;
  final double quinellaOdds;

  const RaceResult({
    required this.raceNo,
    required this.first,
    required this.firstNo,
    required this.second,
    required this.secondNo,
    required this.third,
    required this.thirdNo,
    this.winOdds = 0,
    this.placeOdds = 0,
    this.quinellaOdds = 0,
  });
}
