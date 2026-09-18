import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cycling/features/race/providers/race_providers.dart';
import 'package:cycling/features/race/screens/race_detail_screen.dart';
import 'package:cycling/features/race/screens/race_result_screen.dart';
import 'package:cycling/core/services/cycling_api_service.dart';
import 'package:cycling/core/services/kcycle_result_service.dart';
import 'package:cycling/models/odds.dart';
import 'package:cycling/models/prediction.dart';
import 'package:cycling/models/race.dart';
import 'package:cycling/models/race_entry.dart';
import 'package:cycling/models/race_result.dart';

class _EmptyPayoffApi extends CyclingApiService {
  @override
  Future<ApiResult<List<RaceResult>>> fetchRaceResult({
    required int meet,
    required String date,
    int? rcNo,
  }) async {
    return ApiResult.success([
      RaceResult(
        raceNo: rcNo ?? 3,
        first: '선수1',
        firstNo: 1,
        second: '선수2',
        secondNo: 2,
        third: '선수3',
        thirdNo: 3,
        round: 38,
        dayOrd: 1,
      ),
    ]);
  }
}

class _OfficialOddsService extends KcycleResultService {
  @override
  Future<Odds> fetchDecisionOdds({
    required int year,
    required int round,
    required int dayOrd,
    required int meet,
    required int raceNo,
  }) async {
    if (round <= 0 || dayOrd <= 0) return const Odds();
    return const Odds(
      win: {1: 1.5},
      exacta: {'1-2': 4.2},
      trifecta: {'1-2-3': 8.6},
    );
  }
}

class _RankOnlyApi extends CyclingApiService {
  @override
  Future<ApiResult<List<RaceResult>>> fetchRaceResult({
    required int meet,
    required String date,
    int? rcNo,
  }) async {
    return const ApiResult<List<RaceResult>>.failure('결과 미갱신');
  }

  @override
  Future<ApiResult<List<Map<String, dynamic>>>> fetchRaceRank({
    required int meet,
    required String date,
    required int rcNo,
  }) async {
    return ApiResult.success([
      {'rank': 0, 'racer_nm': '선수1', 'round': 38, 'day_ord': 1},
      {'rank': 0, 'racer_nm': '선수2', 'round': 38, 'day_ord': 1},
      {'rank': 0, 'racer_nm': '선수3', 'round': 38, 'day_ord': 1},
    ]);
  }
}

class _ZeroRoundPayoffApi extends _RankOnlyApi {
  @override
  Future<ApiResult<List<RaceResult>>> fetchRaceResult({
    required int meet,
    required String date,
    int? rcNo,
  }) async {
    return ApiResult.success([
      RaceResult(
        raceNo: rcNo ?? 3,
        first: '선수1',
        firstNo: 1,
        second: '선수2',
        secondNo: 2,
        third: '선수3',
        thirdNo: 3,
      ),
    ]);
  }
}

/// 출주표는 공개됐지만 결과·배당이 아직 없는 "예정 경주" 상태를
/// 실제 편성 공개를 기다리지 않고 프로바이더 오버라이드로 재현해 검증한다.
void main() {
  const venue = 1;
  const raceNo = 3;

  // 상세 화면은 "아직 열리지 않은 경주"여야 하므로 항상 미래인 날짜를 만든다.
  final upcoming = DateTime.now().add(const Duration(days: 3));
  final date =
      '${upcoming.year}'
      '${upcoming.month.toString().padLeft(2, '0')}'
      '${upcoming.day.toString().padLeft(2, '0')}';
  final params = (venue: venue, date: date, raceNo: raceNo);

  // 결과 화면은 날짜가 아니라 오류 종류로 상태가 갈리는지 봐야 하므로 지난 날짜를 쓴다.
  const pastDate = '20260601';
  const pastParams = (venue: venue, date: pastDate, raceNo: raceNo);
  const noDataParams = (venue: venue, date: pastDate, raceNo: 4);

  const completedResult = RaceResult(
    raceNo: raceNo,
    first: '선수1',
    firstNo: 1,
    second: '선수2',
    secondNo: 2,
    third: '선수3',
    thirdNo: 3,
  );

  const emptyPrediction = RacePrediction(
    rankings: [],
    confidence: 0,
    winPicks: [],
    placePicks: [],
    quinellaPicks: [],
    analysis: '',
  );

  final entries = [
    for (var i = 1; i <= 7; i++)
      RaceEntry(
        lineNo: i,
        riderName: '선수$i',
        riderId: '2020000$i',
        grade: 'A1',
        avgScore: 90 + i.toDouble(),
      ),
  ];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('공공 API 배당이 비면 KCYCLE 공식 확정배당으로 보강한다', () async {
    final container = ProviderContainer(
      overrides: [
        cyclingApiServiceProvider.overrideWithValue(_EmptyPayoffApi()),
        kcycleResultServiceProvider.overrideWithValue(_OfficialOddsService()),
        raceEntriesProvider(pastParams).overrideWith(
          (ref) async => DataWithSource(data: entries, fromApi: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(raceResultProvider(pastParams).future);

    expect(result.payoff.win, {1: 1.5});
    expect(result.payoff.exacta, {'1-2': 4.2});
  });

  test('경주결과 API가 늦어도 순위와 공식 배당으로 결과를 구성한다', () async {
    final container = ProviderContainer(
      overrides: [
        cyclingApiServiceProvider.overrideWithValue(_RankOnlyApi()),
        kcycleResultServiceProvider.overrideWithValue(_OfficialOddsService()),
        raceEntriesProvider(pastParams).overrideWith(
          (ref) async => DataWithSource(data: entries, fromApi: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(raceResultProvider(pastParams).future);

    expect(result.firstNo, 1);
    expect(result.secondNo, 2);
    expect(result.thirdNo, 3);
    expect(result.payoff.win, {1: 1.5});
  });

  test('회차가 0이면 순위 API 회차로 오늘 공식 배당을 재조회한다', () async {
    final container = ProviderContainer(
      overrides: [
        cyclingApiServiceProvider.overrideWithValue(_ZeroRoundPayoffApi()),
        kcycleResultServiceProvider.overrideWithValue(_OfficialOddsService()),
        raceEntriesProvider(pastParams).overrideWith(
          (ref) async => DataWithSource(data: entries, fromApi: true),
        ),
      ],
    );
    addTearDown(container.dispose);

    final result = await container.read(raceResultProvider(pastParams).future);

    expect(result.round, 38);
    expect(result.dayOrd, 1);
    expect(result.payoff.win, {1: 1.5});
  });

  Widget wrap(Widget child, List<Override> overrides) {
    return ProviderScope(
      overrides: overrides,
      child: MaterialApp(home: child),
    );
  }

  testWidgets('결과 화면: 아직 결과가 없으면 대기 안내를 보여준다', (tester) async {
    await tester.pumpWidget(
      wrap(
        const RaceResultScreen(
          venueCode: venue,
          date: pastDate,
          raceNo: raceNo,
        ),
        [
          raceResultProvider(pastParams).overrideWith(
            (ref) => Future<RaceResult>.error(Exception('NOT_YET')),
          ),
          raceRankProvider(pastParams).overrideWith(
            (ref) =>
                Future<List<Map<String, dynamic>>>.error(Exception('NOT_YET')),
          ),
          raceEntriesProvider(pastParams).overrideWith(
            (ref) async => DataWithSource(data: entries, fromApi: true),
          ),
          predictionProvider(
            pastParams,
          ).overrideWith((ref) async => emptyPrediction),
          raceListProvider((venue: venue, date: pastDate)).overrideWith(
            (ref) async =>
                const DataWithSource<List<Race>>(data: <Race>[], fromApi: true),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('경기 결과 대기 중'), findsOneWidget);
    expect(find.text('지금 확인'), findsOneWidget);
    expect(find.textContaining('결과를 불러올 수 없습니다'), findsNothing);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('결과 화면: 착순 0 데이터가 있어도 오류 없이 표시한다', (tester) async {
    await tester.pumpWidget(
      wrap(
        const RaceResultScreen(
          venueCode: venue,
          date: pastDate,
          raceNo: raceNo,
        ),
        [
          raceResultProvider(
            pastParams,
          ).overrideWith((ref) async => completedResult),
          raceRankProvider(pastParams).overrideWith(
            (ref) async => [
              {
                'rank': 0,
                'back_no': 7,
                'racer_nm': '미확정선수',
                'racer_grd_cd': 'A1',
              },
              {
                'rank': 1,
                'back_no': 1,
                'racer_nm': '선수1',
                'racer_grd_cd': 'A1',
              },
              {
                'rank': 2,
                'back_no': 2,
                'racer_nm': '선수2',
                'racer_grd_cd': 'A1',
              },
              {
                'rank': 3,
                'back_no': 3,
                'racer_nm': '선수3',
                'racer_grd_cd': 'A1',
              },
            ],
          ),
          raceEntriesProvider(pastParams).overrideWith(
            (ref) async => DataWithSource(data: entries, fromApi: true),
          ),
          predictionProvider(
            pastParams,
          ).overrideWith((ref) async => emptyPrediction),
          raceListProvider((venue: venue, date: pastDate)).overrideWith(
            (ref) async =>
                const DataWithSource<List<Race>>(data: <Race>[], fromApi: true),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('미확정선수'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('결과 화면: 편성 자체가 없으면 자료 없음 안내를 보여준다', (tester) async {
    // 지난 날짜라 "시작 전"이 아니고, 두 소스 모두 NO_DATA인 경우.
    await tester.pumpWidget(
      wrap(
        const RaceResultScreen(venueCode: venue, date: pastDate, raceNo: 4),
        [
          raceResultProvider(noDataParams).overrideWith(
            (ref) => Future<RaceResult>.error(Exception('NO_DATA')),
          ),
          raceRankProvider(noDataParams).overrideWith(
            (ref) =>
                Future<List<Map<String, dynamic>>>.error(Exception('NO_DATA')),
          ),
          raceEntriesProvider(noDataParams).overrideWith(
            (ref) async => const DataWithSource<List<RaceEntry>>(
              data: <RaceEntry>[],
              fromApi: true,
            ),
          ),
          predictionProvider(
            noDataParams,
          ).overrideWith((ref) async => emptyPrediction),
          raceListProvider((venue: venue, date: pastDate)).overrideWith(
            (ref) async =>
                const DataWithSource<List<Race>>(data: <Race>[], fromApi: true),
          ),
        ],
      ),
    );
    await tester.pump();

    expect(find.text('공개된 경주 결과가 없습니다'), findsOneWidget);
    expect(find.text('다시 확인'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('상세 화면: 출주표는 있고 배당은 비어 있으면 종료 후 안내', (tester) async {
    await tester.pumpWidget(
      wrap(RaceDetailScreen(venueCode: venue, date: date, raceNo: raceNo), [
        isSubscribedProvider.overrideWithValue(true),
        raceEntriesProvider(params).overrideWith(
          (ref) async => DataWithSource(data: entries, fromApi: true),
        ),
        oddsProvider(params).overrideWith((ref) async => const Odds()),
        predictionProvider(params).overrideWith((ref) async => emptyPrediction),
        raceListProvider((venue: venue, date: date)).overrideWith(
          (ref) async =>
              const DataWithSource<List<Race>>(data: <Race>[], fromApi: true),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('경주 종료 후 확정 배당이 표시됩니다.'), findsOneWidget);
    expect(find.text('출주표가 아직 공개되지 않았습니다.'), findsNothing);
    expect(find.text('선수1'), findsWidgets);

    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('상세 화면: 출주표가 비면 미공개 안내', (tester) async {
    await tester.pumpWidget(
      wrap(RaceDetailScreen(venueCode: venue, date: date, raceNo: raceNo), [
        isSubscribedProvider.overrideWithValue(true),
        raceEntriesProvider(params).overrideWith(
          (ref) async => const DataWithSource<List<RaceEntry>>(
            data: <RaceEntry>[],
            fromApi: true,
          ),
        ),
        oddsProvider(params).overrideWith((ref) async => const Odds()),
        predictionProvider(params).overrideWith((ref) async => emptyPrediction),
        raceListProvider((venue: venue, date: date)).overrideWith(
          (ref) async =>
              const DataWithSource<List<Race>>(data: <Race>[], fromApi: true),
        ),
      ]),
    );
    await tester.pump();

    expect(find.text('출주표가 아직 공개되지 않았습니다.'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
  });
}
