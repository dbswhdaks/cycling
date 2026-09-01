import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cycling/core/services/cycling_api_service.dart';
import 'package:cycling/core/services/prediction_engine.dart';
import 'package:cycling/models/race_entry.dart';

/// 실제 경주(광명 2026년 200경주)로 예측 엔진의 적중률을 고정한다.
///
/// 픽스처는 `tool/backtest/export_fixture.py`가 공공데이터 API 원본 필드 그대로
/// 뽑아둔 것이라, 출주표 파싱부터 예측까지 실제 경로를 그대로 지난다.
void main() {
  final races = (jsonDecode(
    File('test/fixtures/backtest_races.json').readAsStringSync(),
  ) as List).cast<Map<String, dynamic>>();

  final api = CyclingApiService();

  List<RaceEntry> entriesOf(Map<String, dynamic> race) => api.buildEntriesFromItems(
        (race['entries'] as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );

  Map<String, int> finishOf(Map<String, dynamic> race) =>
      (race['finish'] as Map).map((k, v) => MapEntry(k.toString(), v as int));

  test('픽스처가 충분한 표본을 담고 있다', () {
    expect(races.length, 200);
    expect(entriesOf(races.first).length, greaterThanOrEqualTo(5));
  });

  test('출주표 파싱이 예측용 항목을 채운다', () {
    final entries = entriesOf(races.first);
    expect(entries.map((e) => e.lineNo), [1, 2, 3, 4, 5, 6, 7]);
    expect(entries.every((e) => e.avgScore > 0), isTrue);
    expect(entries.every((e) => e.riderGrade.isNotEmpty), isTrue);
    expect(entries.any((e) => e.recentFinishes.isNotEmpty), isTrue);
    expect(entries.any((e) => e.sprint200m > 0), isTrue);
    expect(entries.any((e) => e.trainingPlace.isNotEmpty), isTrue);
    expect(
      entries.first.recentFinishes.length,
      entries.first.recentClasses.length,
    );
  });

  test('1착 적중률이 백테스트 수준(55% 이상)을 유지한다', () {
    var win = 0;
    var show = 0;
    var trio = 0;

    for (final race in races) {
      final prediction = PredictionEngine.predict(entriesOf(race));
      final finish = finishOf(race);
      int rankOf(int index) =>
          finish[prediction.rankings[index].riderName] ?? 99;

      if (rankOf(0) == 1) win++;
      if (rankOf(0) <= 3) show++;
      if ({rankOf(0), rankOf(1), rankOf(2)}.difference({1, 2, 3}).isEmpty) {
        trio++;
      }
    }

    // 같은 모델을 파이썬 백테스트로 돌린 결과: 단승 57.0% · 복승 84.0% · 삼복승 23.5%
    expect(win / races.length, greaterThanOrEqualTo(0.55));
    expect(show / races.length, greaterThanOrEqualTo(0.80));
    expect(trio / races.length, greaterThanOrEqualTo(0.20));
  });

  test('3착 이내 확률이 실제 복승 적중률과 어긋나지 않는다', () {
    var predicted = 0.0;
    var actual = 0;

    for (final race in races) {
      final prediction = PredictionEngine.predict(entriesOf(race));
      final finish = finishOf(race);
      final top = prediction.rankings.first;
      predicted += top.placeProb;
      if ((finish[top.riderName] ?? 99) <= 3) actual++;
    }

    final predictedRate = predicted / races.length;
    final actualRate = actual / races.length * 100;

    // 보정 후 백테스트 기준 예측 86.5% / 실제 84.4%.
    expect(predictedRate, greaterThan(0));
    expect(predictedRate, lessThanOrEqualTo(100));
    expect((predictedRate - actualRate).abs(), lessThan(5));
  });

  test('예측 승률 합이 100%이고 순위와 정렬이 일치한다', () {
    final prediction = PredictionEngine.predict(entriesOf(races.first));
    final total = prediction.rankings.fold<double>(0, (s, r) => s + r.winProb);

    expect(total, closeTo(100, 0.01));
    for (var i = 1; i < prediction.rankings.length; i++) {
      expect(
        prediction.rankings[i - 1].winProb,
        greaterThanOrEqualTo(prediction.rankings[i].winProb),
      );
      expect(prediction.rankings[i].rank, i + 1);
    }
  });

  test('자료가 통산 득점뿐이어도 득점 순으로 예측한다', () {
    // 창원·부산은 크롤링 자료라 평균득점과 등급만 들어온다.
    const entries = [
      RaceEntry(lineNo: 1, riderName: '가', riderId: '1', grade: 'A3', avgScore: 88.0),
      RaceEntry(lineNo: 2, riderName: '나', riderId: '2', grade: 'A1', avgScore: 95.0),
      RaceEntry(lineNo: 3, riderName: '다', riderId: '3', grade: 'A2', avgScore: 91.0),
    ];

    final prediction = PredictionEngine.predict(entries);

    expect(prediction.rankings.map((r) => r.riderName), ['나', '다', '가']);
    expect(prediction.rankings.first.winProb, greaterThan(40));
  });

  test('출주표가 비면 빈 예측을 돌려준다', () {
    final prediction = PredictionEngine.predict(const []);

    expect(prediction.rankings, isEmpty);
    expect(prediction.winPicks, isEmpty);
    expect(prediction.analysis, contains('없습니다'));
  });
}
