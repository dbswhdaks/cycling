/// 출주표 - 선수, 기수, 등급
class RaceEntry {
  final int lineNo;
  final String riderName;
  final String riderId;

  /// 화면에 표시하는 등급. 공공 API는 경주 등급(특선·우수·선발),
  /// 크롤링 자료는 선수 등급(A1 등)이 들어온다.
  final String grade;
  final String tactic;

  /// 통산 회차 평균득점.
  final double avgScore;
  final int recent3Wins;

  /// 선수 등급 코드(SS·S1~S3·A1~A3·B1~B3). 예측 모델이 사용한다.
  final String riderGrade;

  /// 해당 경기장 최근 3회차 평균득점. 0이면 자료 없음.
  final double areaAvgScore;

  /// 승률(%). 자료가 없으면 0.
  final double winRate;

  /// 삼연대율(%). 자료가 없으면 0.
  final double top3Rate;

  /// 최근 착순(최신순, 1~9). 결장·미상은 제외한다.
  final List<int> recentFinishes;

  /// 최근 출전 등급값(특선 3 · 우수 2 · 선발 1)을 최신순으로 담는다.
  /// `recentFinishes`와 같은 길이다.
  final List<double> recentClasses;

  /// 200m 기록(초). 0이면 자료 없음.
  final double sprint200m;

  /// 기어배수. 자료가 없으면 0.
  final double gearRatio;

  /// 나이. 0이면 자료 없음.
  final int age;

  /// 훈련지. 같은 훈련지 선수끼리 라인을 형성하는 경향이 있어 예측에 쓴다.
  final String trainingPlace;

  /// 마크 승 비율(마크 승수 / 출주 일수).
  final double markWinRatio;

  /// 전법별 승 비율(각 전법 승수 / 출주 일수).
  final double leadWinRatio;
  final double breakWinRatio;
  final double passWinRatio;

  const RaceEntry({
    required this.lineNo,
    required this.riderName,
    required this.riderId,
    required this.grade,
    this.tactic = '선행',
    this.avgScore = 0,
    this.recent3Wins = 0,
    this.riderGrade = '',
    this.areaAvgScore = 0,
    this.winRate = 0,
    this.top3Rate = 0,
    this.recentFinishes = const [],
    this.recentClasses = const [],
    this.sprint200m = 0,
    this.gearRatio = 0,
    this.age = 0,
    this.trainingPlace = '',
    this.markWinRatio = 0,
    this.leadWinRatio = 0,
    this.breakWinRatio = 0,
    this.passWinRatio = 0,
  });
}
