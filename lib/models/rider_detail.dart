import 'race_entry.dart';

/// 선수 상세 정보 (연간 출전 기록 집계 기반)
class RiderDetail {
  final String riderId;
  final String riderName;
  final String grade;
  final String tactic;
  final double avgScore;

  // 전법별 우승 분포
  final int breakWins;
  final int markWins;
  final int chaseWins;

  // 연간 통계
  final int yearRaceCount;
  final int year1stCount;
  final int year2ndCount;
  final int year3rdCount;
  final double? yearAvgRank;

  // 기본 정보
  final int? age;
  final String? school;
  final String? trainingBase;

  // 최근 컨디션 (최근 5경기 평균 득점)
  final double? recentAvgScore;
  final List<double> recentScores;

  const RiderDetail({
    required this.riderId,
    required this.riderName,
    required this.grade,
    this.tactic = '',
    this.avgScore = 0,
    this.breakWins = 0,
    this.markWins = 0,
    this.chaseWins = 0,
    this.yearRaceCount = 0,
    this.year1stCount = 0,
    this.year2ndCount = 0,
    this.year3rdCount = 0,
    this.yearAvgRank,
    this.age,
    this.school,
    this.trainingBase,
    this.recentAvgScore,
    this.recentScores = const [],
  });

  int get totalWins => breakWins + markWins + chaseWins;

  double get winRate =>
      yearRaceCount > 0 ? (year1stCount / yearRaceCount) * 100 : 0;

  double get podiumRate => yearRaceCount > 0
      ? ((year1stCount + year2ndCount + year3rdCount) / yearRaceCount) * 100
      : 0;

  String get tacticLabel {
    if (tactic.isNotEmpty) return tactic;
    if (breakWins > markWins && breakWins > chaseWins) return '선행';
    if (markWins > breakWins && markWins > chaseWins) return '마크';
    if (chaseWins > 0) return '추입';
    return '-';
  }

  factory RiderDetail.fromRaceEntry(RaceEntry entry) {
    return RiderDetail(
      riderId: entry.riderId,
      riderName: entry.riderName,
      grade: entry.grade,
      tactic: entry.tactic,
      avgScore: entry.avgScore,
    );
  }
}
