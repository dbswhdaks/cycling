import 'dart:math';

import '../../models/prediction.dart';
import '../../models/race_entry.dart';

/// 출주표 기반 착순 예측 엔진.
///
/// 광명 2025~2026년 실제 경주 4,169건(출주표 + 확정 착순)으로
/// 경주 단위 소프트맥스(조건부 로짓)를 최대우도 적합해 얻은 모델이다.
/// 학습·검증을 연도로 분리해 교차 확인했고 어느 방향이든 1착 적중률은 59%대였다.
/// (검증 절차와 재현 스크립트는 `tool/backtest/` 참고)
///
/// 점수는 **경주 안에서 표준화한 상대 우열**로만 계산한다.
/// 같은 경주 선수들끼리 비교하는 문제이므로 절대값은 의미가 없고,
/// 자료가 없는 항목은 전원 같은 값이 되어 자동으로 결과에 영향을 주지 않는다.
class PredictionEngine {
  /// 경주 내 표준화(평균 0, 표준편차 1) 기준 가중치.
  static const Map<_Feature, double> _weights = {
    _Feature.totalAvgScore: 0.9284,
    _Feature.areaAvgScore: 0.3156,
    _Feature.riderGrade: 0.1671,
    _Feature.winRate: 0.1613,
    _Feature.recentFinish: -0.1330,
    _Feature.sprint: 0.1273,
    _Feature.age: -0.1651,
    _Feature.lineSize: 0.0566,
    _Feature.markWinRatio: -0.2108,
  };

  /// 최근 성적은 최신 경주일수록 크게 반영한다.
  static const double _recentDecay = 0.85;

  /// 3착 이내 확률을 구할 때 쓰는 효용 배율.
  ///
  /// 1착 확률을 그대로 Plackett-Luce에 넣으면 상위권의 3착 확률이 과대평가된다
  /// (1순위 기준 예측 96% vs 실제 84%). 실제 3착 여부에 대한 로그손실이
  /// 최소가 되도록 적합해 0.6을 얻었고, 이때 예측 86.5% / 실제 84.4%로 맞는다.
  static const double _placeTemperature = 0.6;

  static const Map<String, double> _gradeLevels = {
    'SS': 10, 'S1': 9, 'S2': 8, 'S3': 7,
    'A1': 6, 'A2': 5, 'A3': 4,
    'B1': 3, 'B2': 2, 'B3': 1,
  };

  static const _tacticLabels = {
    '선행': '초반 주도',
    '젖히기': '중반 치고 올라감',
    '추입': '후반 추월',
    '마크': '선두 견제 후 추월',
  };

  /// 화면의 "요소별 분석"에 노출할 항목.
  static const Map<_Feature, String> _factorLabels = {
    _Feature.totalAvgScore: '평균득점',
    _Feature.areaAvgScore: '경기장 적응',
    _Feature.riderGrade: '등급',
    _Feature.winRate: '승률',
    _Feature.recentFinish: '최근 성적',
    _Feature.sprint: '순발력',
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

    final raw = entries.map((e) => _rawFeatures(e, entries)).toList();
    final normalized = _standardize(raw);

    final utilities = [
      for (final features in normalized)
        _weights.entries.fold<double>(
          0,
          (sum, w) => sum + w.value * (features[w.key] ?? 0),
        ),
    ];
    final probabilities = _softmax(utilities);
    final placeProbabilities = _placeProbabilities(
      _softmax([for (final u in utilities) u * _placeTemperature]),
    );

    final order = List.generate(entries.length, (i) => i)
      ..sort((a, b) => utilities[b].compareTo(utilities[a]));

    final rankings = <RiderPrediction>[];
    for (var position = 0; position < order.length; position++) {
      final i = order[position];
      final entry = entries[i];
      rankings.add(
        RiderPrediction(
          lineNo: entry.lineNo,
          riderName: entry.riderName,
          riderId: entry.riderId,
          grade: entry.grade,
          tactic: entry.tactic,
          winProb: probabilities[i] * 100,
          placeProb: placeProbabilities[i] * 100,
          rank: position + 1,
          totalScore: utilities[i],
          factors: _displayFactors(normalized[i]),
        ),
      );
    }

    final sortedProbs = [for (final i in order) probabilities[i]];

    return RacePrediction(
      rankings: rankings,
      confidence: _confidence(sortedProbs),
      winPicks: _winPicks(rankings),
      placePicks: _placePicks(rankings, sortedProbs),
      quinellaPicks: _quinellaPicks(rankings, sortedProbs),
      analysis: _analysis(rankings),
    );
  }

  // ─────────────────────────── 피처 ───────────────────────────

  static Map<_Feature, double> _rawFeatures(
    RaceEntry entry,
    List<RaceEntry> all,
  ) {
    final place = entry.trainingPlace.trim();
    final lineSize = place.isEmpty
        ? 0
        : all
              .where((r) => !identical(r, entry) && r.trainingPlace.trim() == place)
              .length;

    return {
      _Feature.totalAvgScore: entry.avgScore,
      _Feature.areaAvgScore:
          entry.areaAvgScore > 0 ? entry.areaAvgScore : entry.avgScore,
      _Feature.riderGrade: _gradeLevel(entry),
      _Feature.winRate: entry.winRate,
      // 착순은 작을수록 좋으므로 부호를 뒤집어 "클수록 좋음"으로 맞춘다.
      _Feature.recentFinish: -_weightedRecentFinish(entry),
      _Feature.sprint: entry.sprint200m > 0 ? -entry.sprint200m : 0,
      _Feature.age: entry.age.toDouble(),
      _Feature.lineSize: lineSize.toDouble(),
      _Feature.markWinRatio: entry.markWinRatio,
    };
  }

  static double _gradeLevel(RaceEntry entry) {
    final code = entry.riderGrade.trim().toUpperCase();
    if (code.isNotEmpty && _gradeLevels.containsKey(code)) {
      return _gradeLevels[code]!;
    }
    // 크롤링 자료는 선수 등급이 `grade`에 들어오기도 한다.
    return _gradeLevels[entry.grade.trim().toUpperCase()] ?? 5.0;
  }

  /// 최근 착순의 지수가중 평균. 자료가 없으면 중간값 4.5로 둔다.
  static double _weightedRecentFinish(RaceEntry entry) {
    if (entry.recentFinishes.isEmpty) return 4.5;

    var weighted = 0.0;
    var total = 0.0;
    for (var i = 0; i < entry.recentFinishes.length; i++) {
      final weight = pow(_recentDecay, i).toDouble();
      weighted += entry.recentFinishes[i] * weight;
      total += weight;
    }
    return weighted / total;
  }

  /// 경주 안에서 평균 0·표준편차 1로 맞춘다.
  /// 전원 같은 값이면(자료 없음 포함) 0이 되어 결과에 영향을 주지 않는다.
  static List<Map<_Feature, double>> _standardize(
    List<Map<_Feature, double>> raw,
  ) {
    final result = List.generate(raw.length, (_) => <_Feature, double>{});

    for (final feature in _Feature.values) {
      final values = [for (final row in raw) row[feature] ?? 0];
      final mean = values.reduce((a, b) => a + b) / values.length;
      final variance =
          values.fold<double>(0, (sum, v) => sum + (v - mean) * (v - mean)) /
          values.length;
      final deviation = sqrt(variance);

      for (var i = 0; i < raw.length; i++) {
        result[i][feature] =
            deviation == 0 ? 0 : (values[i] - mean) / deviation;
      }
    }

    return result;
  }

  static List<double> _softmax(List<double> utilities) {
    final maxUtility = utilities.reduce(max);
    final weights = [for (final u in utilities) exp(u - maxUtility)];
    final total = weights.reduce((a, b) => a + b);
    return [for (final w in weights) w / total];
  }

  /// 각 선수가 3착 이내에 들 확률.
  ///
  /// 1착 확률에서 순서대로 뽑아 나가는 Plackett-Luce 모형으로,
  /// 앞선 두 자리를 다른 선수가 차지하는 모든 경우를 더한다.
  static List<double> _placeProbabilities(List<double> probs) {
    final count = probs.length;
    if (count <= 3) return List.filled(count, 1.0);

    return [
      for (var target = 0; target < count; target++)
        _topThreeProb(probs, target),
    ];
  }

  static double _topThreeProb(List<double> probs, int target) {
    var total = probs[target];

    for (var first = 0; first < probs.length; first++) {
      if (first == target) continue;
      final afterFirst = 1 - probs[first];
      if (afterFirst <= 0) continue;
      total += probs[first] * probs[target] / afterFirst;

      for (var second = 0; second < probs.length; second++) {
        if (second == first || second == target) continue;
        final afterSecond = afterFirst - probs[second];
        if (afterSecond <= 0) continue;
        total += probs[first] *
            (probs[second] / afterFirst) *
            (probs[target] / afterSecond);
      }
    }

    return total.clamp(0.0, 1.0);
  }

  /// 막대그래프용 표시값. 표준화 점수를 0~10으로 옮긴다.
  static Map<String, double> _displayFactors(Map<_Feature, double> normalized) {
    return {
      for (final entry in _factorLabels.entries)
        entry.value: (5 + (normalized[entry.key] ?? 0) * 2.5).clamp(0.5, 10.0),
    };
  }

  // ─────────────────────────── 확률·추천 ───────────────────────────

  /// 상위 2명의 확률 격차로 예측 신뢰도를 만든다.
  static double _confidence(List<double> sortedProbs) {
    if (sortedProbs.length < 2) return 50;
    final top = sortedProbs[0];
    final gap = top - sortedProbs[1];
    return (35 + top * 60 + gap * 40).clamp(35, 92);
  }

  /// `first`가 1착, `second`가 2착일 확률 (Plackett-Luce).
  static double _exactaProb(List<double> probs, int first, int second) {
    final remaining = 1 - probs[first];
    if (remaining <= 0) return 0;
    return probs[first] * (probs[second] / remaining);
  }

  /// 두 선수가 순서와 무관하게 1·2착을 차지할 확률.
  static double _pairProb(List<double> probs, int a, int b) =>
      _exactaProb(probs, a, b) + _exactaProb(probs, b, a);

  static List<BettingPick> _winPicks(List<RiderPrediction> rankings) {
    final top = rankings.first;
    return [
      BettingPick(
        label: '${top.lineNo}번 ${top.riderName}',
        description: _describe([
          top.grade,
          _tacticLabels[top.tactic] ?? top.tactic,
          '승률 ${top.winProb.toStringAsFixed(1)}%',
        ]),
        confidence: top.winProb,
      ),
      if (rankings.length > 1)
        BettingPick(
          label: '${rankings[1].lineNo}번 ${rankings[1].riderName}',
          description: _describe([
            '대항마',
            rankings[1].grade,
            '승률 ${rankings[1].winProb.toStringAsFixed(1)}%',
          ]),
          confidence: rankings[1].winProb,
        ),
    ];
  }

  /// 비어 있는 항목은 빼고 가운뎃점으로 잇는다.
  static String _describe(List<String> parts) =>
      parts.where((p) => p.trim().isNotEmpty).join(' · ');

  static List<BettingPick> _placePicks(
    List<RiderPrediction> rankings,
    List<double> probs,
  ) {
    if (rankings.length < 2) return [];
    return [
      BettingPick(
        label: '${rankings[0].lineNo}-${rankings[1].lineNo}',
        description: '${rankings[0].riderName} · ${rankings[1].riderName}',
        confidence: _pairProb(probs, 0, 1) * 100,
      ),
      if (rankings.length > 2)
        BettingPick(
          label: '${rankings[0].lineNo}-${rankings[2].lineNo}',
          description: '${rankings[0].riderName} · ${rankings[2].riderName}',
          confidence: _pairProb(probs, 0, 2) * 100,
        ),
    ];
  }

  static List<BettingPick> _quinellaPicks(
    List<RiderPrediction> rankings,
    List<double> probs,
  ) {
    if (rankings.length < 2) return [];
    return [
      BettingPick(
        label: '${rankings[0].lineNo}→${rankings[1].lineNo}',
        description:
            '${rankings[0].riderName}(1착) → ${rankings[1].riderName}(2착)',
        confidence: _exactaProb(probs, 0, 1) * 100,
      ),
      if (rankings.length > 2)
        BettingPick(
          label: '${rankings[0].lineNo}→${rankings[2].lineNo}',
          description:
              '${rankings[0].riderName}(1착) → ${rankings[2].riderName}(2착)',
          confidence: _exactaProb(probs, 0, 2) * 100,
        ),
    ];
  }

  static String _analysis(List<RiderPrediction> rankings) {
    final top = rankings.first;
    final buffer = StringBuffer();

    buffer.write('${top.lineNo}번 ${top.riderName} 선수가 ');
    buffer.write('승률 ${top.winProb.toStringAsFixed(1)}%로 가장 유리합니다.');

    if (rankings.length >= 3) {
      final second = rankings[1];
      final third = rankings[2];
      buffer.writeln();
      buffer.writeln();
      buffer.write('대항마는 ${second.lineNo}번 ${second.riderName}');
      buffer.write('(${second.winProb.toStringAsFixed(1)}%), ');
      buffer.write('${third.lineNo}번 ${third.riderName}');
      buffer.write('(${third.winProb.toStringAsFixed(1)}%)입니다.');
    }

    if (rankings.length >= 2) {
      final gap = top.winProb - rankings[1].winProb;
      buffer.writeln();
      buffer.writeln();
      buffer.write(
        gap >= 20
            ? '1순위와 2순위의 격차가 커 축으로 삼기 좋은 경주입니다.'
            : '상위권 실력차가 크지 않아 이변 가능성을 함께 보셔야 합니다.',
      );
    }

    return buffer.toString();
  }
}

enum _Feature {
  totalAvgScore,
  areaAvgScore,
  riderGrade,
  winRate,
  recentFinish,
  sprint,
  age,
  lineSize,
  markWinRatio,
}
