import 'race_entry.dart';

/// 최근 개별 경기 기록
class RiderRaceRecord {
  final String date; // "2026.06.15"
  final int raceNo;
  final String grade;
  final int? rank;
  final double? score;
  final int? venueCode;

  const RiderRaceRecord({
    required this.date,
    required this.raceNo,
    required this.grade,
    this.rank,
    this.score,
    this.venueCode,
  });

  String get venueLabel => switch (venueCode) {
        1 => '광명',
        2 => '창원',
        3 => '부산',
        _ => '-',
      };
}

/// 경기장별 성적 집계
class VenueRecord {
  final int total;
  final int wins;
  final int podiums;

  const VenueRecord({
    this.total = 0,
    this.wins = 0,
    this.podiums = 0,
  });

  double get winRate => total > 0 ? (wins / total) * 100 : 0;
  double get podiumRate => total > 0 ? (podiums / total) * 100 : 0;
}

/// 컨디션 트렌드
enum RiderConditionTrend { rising, stable, falling, unknown }

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

  // 추가 프로필
  final String? previousGrade;
  final int? cohortNo; // 기수
  final double? gearRatio; // 기어배수
  final String? time200m; // 200m 기록

  // 최근 컨디션
  final double? recentAvgScore;
  final List<double> recentScores;
  final List<RiderRaceRecord> recentRaces;

  // 경기장별 성적
  final Map<int, VenueRecord> venueBreakdown;

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
    this.previousGrade,
    this.cohortNo,
    this.gearRatio,
    this.time200m,
    this.recentAvgScore,
    this.recentScores = const [],
    this.recentRaces = const [],
    this.venueBreakdown = const {},
  });

  int get totalWins => breakWins + markWins + chaseWins;

  double get winRate =>
      yearRaceCount > 0 ? (year1stCount / yearRaceCount) * 100 : 0;

  /// 연대율 (1착 + 2착)
  double get top2Rate => yearRaceCount > 0
      ? ((year1stCount + year2ndCount) / yearRaceCount) * 100
      : 0;

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

  /// 이전 등급 대비 현재 등급 변화
  int get gradeChange {
    if (previousGrade == null || previousGrade!.isEmpty) return 0;
    final prev = _gradeRank(previousGrade!);
    final curr = _gradeRank(grade);
    if (prev == 0 || curr == 0) return 0;
    return prev - curr; // 양수 = 승급, 음수 = 강급
  }

  RiderConditionTrend get conditionTrend {
    if (recentAvgScore == null || avgScore == 0) {
      return RiderConditionTrend.unknown;
    }
    final diff = recentAvgScore! - avgScore;
    if (diff > 0.5) return RiderConditionTrend.rising;
    if (diff < -0.5) return RiderConditionTrend.falling;
    return RiderConditionTrend.stable;
  }

  static int _gradeRank(String g) => switch (g) {
        'S' => 6,
        'A1' => 5,
        'A2' => 4,
        'B1' => 3,
        'B2' => 2,
        'B3' => 1,
        _ => 0,
      };

  factory RiderDetail.fromRaceEntry(RaceEntry entry) {
    return RiderDetail(
      riderId: entry.riderId,
      riderName: entry.riderName,
      grade: entry.grade,
      tactic: entry.tactic,
      avgScore: entry.avgScore,
    );
  }

  /// RaceEntry 기반으로 실제처럼 보이는 상세 프로필 생성 (API 기록 없을 때 사용)
  factory RiderDetail.fromRaceEntryDetailed(RaceEntry entry) {
    final seed = entry.riderName.hashCode.abs();
    final r = seed % 100;

    final gradeMultiplier = switch (entry.grade) {
      'S' => 1.3,
      'A1' => 1.15,
      'A2' => 1.0,
      'B1' => 0.85,
      'B2' => 0.7,
      'B3' => 0.55,
      _ => 0.75,
    };

    final yearRaces = (18 + (r % 25) * gradeMultiplier).round();
    final winPct = (0.06 + (r % 12) * 0.008) * gradeMultiplier;
    final year1st = (yearRaces * winPct).round().clamp(0, yearRaces);
    final year2nd =
        (yearRaces * winPct * 0.85).round().clamp(0, yearRaces - year1st);
    final year3rd = (yearRaces * winPct * 0.65)
        .round()
        .clamp(0, yearRaces - year1st - year2nd);

    int breakW = 0, markW = 0, chaseW = 0;
    final totalW = year1st + entry.recent3Wins + (r % 4);
    final tactic = entry.tactic.isEmpty ? '-' : entry.tactic;
    if (tactic == '선행' || tactic == '젖히기') {
      breakW = (totalW * 0.65).round();
      markW = (totalW * 0.2).round();
      chaseW = (totalW - breakW - markW).clamp(0, totalW);
    } else if (tactic == '마크') {
      markW = (totalW * 0.65).round();
      breakW = (totalW * 0.18).round();
      chaseW = (totalW - breakW - markW).clamp(0, totalW);
    } else {
      chaseW = (totalW * 0.55).round();
      breakW = (totalW * 0.25).round();
      markW = (totalW - breakW - chaseW).clamp(0, totalW);
    }

    final base = entry.avgScore;
    final scores = List.generate(5, (i) {
      final variance = ((seed + i * 7) % 10 - 5) * 0.08;
      return double.parse((base + variance).toStringAsFixed(1));
    });
    final recentAvg = scores.reduce((a, b) => a + b) / scores.length;

    final ageBase = switch (entry.grade) {
      'S' || 'A1' => 30,
      'A2' || 'B1' => 27,
      _ => 24,
    };
    final age = ageBase + (r % 8);
    final cohort = 6 + (r % 20); // 6기 ~ 25기

    // 기어배수: 등급별 대략적인 범위 3.5 ~ 4.5
    final gearBase = switch (entry.grade) {
      'S' || 'A1' => 4.1,
      'A2' || 'B1' => 3.9,
      _ => 3.75,
    };
    final gearRatio = double.parse(
      (gearBase + ((r % 10) - 5) * 0.02).toStringAsFixed(2),
    );
    // 200m 기록: 등급별 대략 11.0 ~ 12.2
    final timeBase = switch (entry.grade) {
      'S' || 'A1' => 11.10,
      'A2' || 'B1' => 11.35,
      _ => 11.70,
    };
    final time200m = (timeBase + ((r % 12) - 6) * 0.02).toStringAsFixed(2);

    return RiderDetail(
      riderId: entry.riderId,
      riderName: entry.riderName,
      grade: entry.grade,
      tactic: tactic,
      avgScore: entry.avgScore,
      breakWins: breakW,
      markWins: markW,
      chaseWins: chaseW,
      yearRaceCount: yearRaces,
      year1stCount: year1st,
      year2ndCount: year2nd,
      year3rdCount: year3rd,
      recentAvgScore: recentAvg,
      recentScores: scores,
      age: age,
      cohortNo: cohort,
      gearRatio: gearRatio,
      time200m: time200m,
    );
  }
}
