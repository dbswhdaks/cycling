import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycling/core/services/cycling_api_service.dart';
import 'package:cycling/core/services/prediction_engine.dart';
import 'package:cycling/features/race/widgets/prediction_tab.dart';
import 'package:cycling/models/prediction.dart';

/// 실제 경주 자료로 만든 예측이 AI 예측 화면에서 제대로 그려지는지 확인한다.
void main() {
  late RacePrediction prediction;

  setUpAll(() {
    final races = (jsonDecode(
      File('test/fixtures/backtest_races.json').readAsStringSync(),
    ) as List).cast<Map<String, dynamic>>();

    final entries = CyclingApiService().buildEntriesFromItems(
      (races.first['entries'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(),
    );
    prediction = PredictionEngine.predict(entries);
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(),
        home: Scaffold(
          body: PredictionTab(
            prediction: prediction,
            venueName: '광명스피돔',
            venueCode: 1,
            date: '20260101',
            raceNo: 1,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('신뢰도와 순위·승률이 화면에 나온다', (tester) async {
    await pump(tester);

    expect(find.text('광명스피돔 1R AI 예측'), findsOneWidget);
    expect(
      find.text('신뢰도 ${prediction.confidence.toStringAsFixed(0)}%'),
      findsOneWidget,
    );

    final top = prediction.rankings.first;
    expect(find.text(top.riderName), findsWidgets);
    expect(find.text('${top.winProb.toStringAsFixed(1)}%'), findsWidgets);
  });

  testWidgets('요소별 분석 막대가 모두 표시된다', (tester) async {
    await pump(tester);

    for (final label in ['평균득점', '경기장 적응', '등급', '승률', '최근 성적', '순발력']) {
      expect(find.text(label), findsWidgets);
    }

    // 막대 폭 계산이 음수/0으로 깨지지 않도록 표시값은 항상 양수다.
    for (final rider in prediction.rankings.take(3)) {
      expect(rider.factors.values.every((v) => v > 0), isTrue);
    }
  });

  testWidgets('신뢰도 게이지가 0~1 범위를 벗어나지 않는다', (tester) async {
    await pump(tester);

    final gauge = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator).first,
    );

    expect(gauge.value, isNotNull);
    expect(gauge.value, inInclusiveRange(0, 1));
  });

  testWidgets('추천 조합 확률이 100%를 넘지 않는다', (tester) async {
    await pump(tester);

    final picks = [
      ...prediction.winPicks,
      ...prediction.placePicks,
      ...prediction.quinellaPicks,
    ];

    expect(picks, isNotEmpty);
    for (final pick in picks) {
      expect(pick.confidence, inInclusiveRange(0, 100));
    }
    // 순서를 지정하는 쌍승은 순서 무관인 복승보다 확률이 낮아야 한다.
    expect(
      prediction.quinellaPicks.first.confidence,
      lessThan(prediction.placePicks.first.confidence),
    );
  });
}
