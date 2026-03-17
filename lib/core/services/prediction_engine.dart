import 'dart:math';
import '../../models/race_entry.dart';
import '../../models/prediction.dart';

/// 로컬 AI 예측 엔진 (출주표 기반 스코어링)
class PredictionEngine {
  static const _gradeScores = {
    'S': 10.0,
    'A1': 8.5,
    'A2': 7.0,
    'B1': 5.5,
    'B2': 4.0,
    'B3': 2.5,
  };

  static const _tacticLabels = {
    '선행': '초반 주도',
    '젖히기': '중반 치고 올라감',
    '추입': '후반 추월',
    '마크': '선두 견제 후 추월',
  };

  static RacePrediction predict(List<RaceEntry> entries) {
    if (entries.isEmpty) {
      return const RacePrediction(
        rankings: [],
        confidence: 0,
        winPicks: [],
        placePicks: [],
        quinellaPicks: [],
        analysis: '출주표 데이터가 없습니다.',
      );
    }

    final scored = entries.map((e) => _scoreRider(e, entries)).toList();
    final totalRaw = scored.fold<double>(0, (s, r) => s + r.totalScore);

    scored.sort((a, b) => b.totalScore.compareTo(a.totalScore));

    final rankings = <RiderPrediction>[];
    for (int i = 0; i < scored.length; i++) {
      final s = scored[i];
      rankings.add(RiderPrediction(
        lineNo: s.lineNo,
        riderName: s.riderName,
        riderId: s.riderId,
        grade: s.grade,
        tactic: s.tactic,
        winProb: (s.totalScore / totalRaw * 100).clamp(2, 60),
        rank: i + 1,
        totalScore: s.totalScore,
        factors: s.factors,
      ));
    }

    final confidence = _calcConfidence(rankings);
    final winPicks = _generateWinPicks(rankings);
    final placePicks = _generatePlacePicks(rankings);
    final quinellaPicks = _generateQuinellaPicks(rankings);
    final analysis = _generateAnalysis(rankings);

    return RacePrediction(
      rankings: rankings,
      confidence: confidence,
      winPicks: winPicks,
      placePicks: placePicks,
      quinellaPicks: quinellaPicks,
      analysis: analysis,
    );
  }

  static RiderPrediction _scoreRider(RaceEntry e, List<RaceEntry> all) {
    final gradeScore = _gradeScores[e.grade] ?? 4.0;
    final avgNorm = e.avgScore.clamp(0, 10).toDouble();
    final recentBonus = e.recent3Wins * 1.5;

    double tacticScore = 3.0;
    final seonhaengCount = all.where((r) => r.tactic == '선행').length;
    switch (e.tactic) {
      case '선행':
        tacticScore = seonhaengCount <= 2 ? 4.5 : 3.0;
        break;
      case '추입':
        tacticScore = seonhaengCount >= 3 ? 5.0 : 3.5;
        break;
      case '젖히기':
        tacticScore = 4.0;
        break;
      case '마크':
        tacticScore = seonhaengCount >= 2 ? 4.5 : 3.0;
        break;
    }

    final rng = Random(e.lineNo * 31 + e.riderName.hashCode);
    final randomFactor = 0.8 + rng.nextDouble() * 0.4;

    final total = (gradeScore * 3.0 + avgNorm * 2.5 + recentBonus * 2.0 + tacticScore * 1.5) * randomFactor;

    return RiderPrediction(
      lineNo: e.lineNo,
      riderName: e.riderName,
      riderId: e.riderId,
      grade: e.grade,
      tactic: e.tactic,
      winProb: 0,
      rank: 0,
      totalScore: total,
      factors: {
        '등급': gradeScore,
        '평균득점': avgNorm,
        '최근 전적': recentBonus,
        '전법': tacticScore,
      },
    );
  }

  static double _calcConfidence(List<RiderPrediction> rankings) {
    if (rankings.length < 2) return 50;
    final gap = rankings[0].totalScore - rankings[1].totalScore;
    final avg = rankings.fold<double>(0, (s, r) => s + r.totalScore) / rankings.length;
    return (50 + (gap / avg) * 80).clamp(30, 85);
  }

  static List<BettingPick> _generateWinPicks(List<RiderPrediction> rankings) {
    if (rankings.isEmpty) return [];
    final top = rankings.first;
    return [
      BettingPick(
        label: '${top.lineNo}번 ${top.riderName}',
        description: '${top.grade}등급 · ${_tacticLabels[top.tactic] ?? top.tactic} · 승률 ${top.winProb.toStringAsFixed(1)}%',
        confidence: top.winProb,
      ),
      if (rankings.length > 1)
        BettingPick(
          label: '${rankings[1].lineNo}번 ${rankings[1].riderName}',
          description: '대항마 · ${rankings[1].grade}등급 · 승률 ${rankings[1].winProb.toStringAsFixed(1)}%',
          confidence: rankings[1].winProb,
        ),
    ];
  }

  static List<BettingPick> _generatePlacePicks(List<RiderPrediction> rankings) {
    if (rankings.length < 2) return [];
    final top2 = rankings.take(3).toList();
    return [
      BettingPick(
        label: '${top2[0].lineNo}-${top2[1].lineNo}',
        description: '${top2[0].riderName} · ${top2[1].riderName}',
        confidence: (top2[0].winProb + top2[1].winProb) / 2,
      ),
      if (top2.length > 2)
        BettingPick(
          label: '${top2[0].lineNo}-${top2[2].lineNo}',
          description: '${top2[0].riderName} · ${top2[2].riderName}',
          confidence: (top2[0].winProb + top2[2].winProb) / 2,
        ),
    ];
  }

  static List<BettingPick> _generateQuinellaPicks(List<RiderPrediction> rankings) {
    if (rankings.length < 2) return [];
    return [
      BettingPick(
        label: '${rankings[0].lineNo}→${rankings[1].lineNo}',
        description: '${rankings[0].riderName}(1착) → ${rankings[1].riderName}(2착)',
        confidence: (rankings[0].winProb * 0.6 + rankings[1].winProb * 0.4),
      ),
      if (rankings.length > 2)
        BettingPick(
          label: '${rankings[0].lineNo}→${rankings[2].lineNo}',
          description: '${rankings[0].riderName}(1착) → ${rankings[2].riderName}(2착)',
          confidence: (rankings[0].winProb * 0.5 + rankings[2].winProb * 0.3),
        ),
    ];
  }

  static String _generateAnalysis(List<RiderPrediction> rankings) {
    if (rankings.isEmpty) return '';
    final top = rankings.first;
    final buf = StringBuffer();

    buf.writeln('${top.lineNo}번 ${top.riderName} 선수가 ${top.grade}등급의 높은 기량과 ');
    buf.write('${_tacticLabels[top.tactic] ?? top.tactic} 전법으로 가장 유리합니다.');

    if (rankings.length >= 3) {
      buf.writeln();
      buf.writeln();
      final r2 = rankings[1];
      final r3 = rankings[2];
      buf.write('대항마로 ${r2.lineNo}번 ${r2.riderName}(${r2.grade}), ');
      buf.write('${r3.lineNo}번 ${r3.riderName}(${r3.grade}) 선수를 주시하세요.');
    }

    final seonhaeng = rankings.where((r) => r.tactic == '선행').toList();
    if (seonhaeng.length >= 3) {
      buf.writeln();
      buf.writeln();
      buf.write('선행 전법 선수가 ${seonhaeng.length}명으로, 초반 경쟁이 치열할 수 있습니다. 추입/마크 전법 선수에게 유리할 수 있습니다.');
    }

    return buf.toString();
  }
}
