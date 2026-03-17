import 'race_entry.dart';

/// 선수 상세 정보
class RiderDetail {
  final String riderId;
  final String riderName;
  final String grade;
  final String tactic;
  final double avgScore;
  final int recent3Wins;
  final int? age;
  final String? school;
  final String? trainingBase;
  final double? recent10Avg;
  final int? totalWins;
  final int? totalRaces;

  const RiderDetail({
    required this.riderId,
    required this.riderName,
    required this.grade,
    this.tactic = '선행',
    this.avgScore = 0,
    this.recent3Wins = 0,
    this.age,
    this.school,
    this.trainingBase,
    this.recent10Avg,
    this.totalWins,
    this.totalRaces,
  });

  factory RiderDetail.fromRaceEntry(RaceEntry entry) {
    return RiderDetail(
      riderId: entry.riderId,
      riderName: entry.riderName,
      grade: entry.grade,
      tactic: entry.tactic,
      avgScore: entry.avgScore,
      recent3Wins: entry.recent3Wins,
    );
  }
}
