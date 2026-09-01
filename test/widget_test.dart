import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cycling/core/services/cycling_api_service.dart';
import 'package:cycling/features/race/providers/race_providers.dart';
import 'package:cycling/main.dart';
import 'package:cycling/models/race.dart';

/// 스모크 테스트가 실제 네트워크를 타지 않도록 빈 응답만 돌려주는 서비스.
class _OfflineApiService extends CyclingApiService {
  @override
  Future<ApiResult<List<Race>>> fetchRaceList({
    required int meet,
    required String date,
  }) async => const ApiResult.success(<Race>[]);

  @override
  Future<ApiResult<Set<String>>> fetchRaceDatesForMonth({
    required int meet,
    required int year,
    required int month,
  }) async => const ApiResult.success(<String>{});

  @override
  Future<bool?> venueRaced({required int meet, required String date}) async =>
      null;

  @override
  Future<String?> latestRaceDate({required int meet, required int year}) async =>
      null;
}

void main() {
  testWidgets('앱 스모크 테스트', (WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cyclingApiServiceProvider.overrideWithValue(_OfflineApiService()),
        ],
        child: const CyclingApp(),
      ),
    );
    await tester.pump();

    expect(find.byType(MaterialApp), findsOneWidget);

    // 홈 화면의 주기 타이머가 정리되도록 트리를 해제한다.
    await tester.pumpWidget(const SizedBox());
  });
}
