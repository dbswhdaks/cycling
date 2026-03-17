/// 선수별 AI 예측 결과
class RiderPrediction {
  final int lineNo;
  final String riderName;
  final String riderId;
  final String grade;
  final String tactic;
  final double winProb;
  final int rank;
  final double totalScore;
  final Map<String, double> factors;

  const RiderPrediction({
    required this.lineNo,
    required this.riderName,
    required this.riderId,
    required this.grade,
    required this.tactic,
    required this.winProb,
    required this.rank,
    required this.totalScore,
    required this.factors,
  });
}

/// 경주 전체 AI 예측
class RacePrediction {
  final List<RiderPrediction> rankings;
  final double confidence;
  final List<BettingPick> winPicks;
  final List<BettingPick> placePicks;
  final List<BettingPick> quinellaPicks;
  final String analysis;

  const RacePrediction({
    required this.rankings,
    required this.confidence,
    required this.winPicks,
    required this.placePicks,
    required this.quinellaPicks,
    required this.analysis,
  });
}

/// 베팅 추천
class BettingPick {
  final String label;
  final String description;
  final double confidence;

  const BettingPick({
    required this.label,
    required this.description,
    required this.confidence,
  });
}
