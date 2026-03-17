/// 출주표 - 선수, 기수, 등급
class RaceEntry {
  final int lineNo;
  final String riderName;
  final String riderId;
  final String grade;
  final String tactic;
  final double avgScore;
  final int recent3Wins;

  const RaceEntry({
    required this.lineNo,
    required this.riderName,
    required this.riderId,
    required this.grade,
    this.tactic = '선행',
    this.avgScore = 0,
    this.recent3Wins = 0,
  });
}
