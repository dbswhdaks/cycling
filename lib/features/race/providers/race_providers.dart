import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/iap_constants.dart';
import '../../../core/services/cycling_api_service.dart';
import '../../../core/services/kcycle_result_service.dart';
import '../../../core/services/lepopark_result_service.dart';
import '../../../core/services/prediction_engine.dart';
import '../../../core/services/supabase_backup_service.dart';
import '../../../features/admin/providers/admin_auth_provider.dart';
import '../../../features/subscription/providers/in_app_purchase_provider.dart';
import '../../../models/race.dart';
import '../../../models/race_entry.dart';
import '../../../models/race_result.dart';
import '../../../models/odds.dart';
import '../../../models/prediction.dart';
import '../../../models/rider_detail.dart';

String _venueName(int code) => ApiConstants.venueName(code);

final cyclingApiServiceProvider = Provider<CyclingApiService>((ref) {
  return CyclingApiService();
});

final kcycleResultServiceProvider = Provider<KcycleResultService>((ref) {
  return KcycleResultService();
});

final lepoparkResultServiceProvider = Provider<LepoparkResultService>((ref) {
  return LepoparkResultService();
});

/// 아직 시행되지 않은 경주
class RaceNotYetException implements Exception {
  const RaceNotYetException();

  @override
  String toString() => 'NOT_YET';
}

/// 공개된 데이터를 찾지 못한 경주
class RaceDataUnavailableException implements Exception {
  const RaceDataUnavailableException();

  @override
  String toString() => 'NO_DATA';
}

final supabaseBackupProvider = Provider<SupabaseBackupService>((ref) {
  return SupabaseBackupService();
});

final selectedRiderEntryProvider = StateProvider<RaceEntry?>((ref) => null);

final selectedDateProvider = StateProvider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

/// 인앱결제(Google Play) 기반 구독 활성 여부.
/// 활성 조건: (1) 관리자 로그인 상태이거나, (2) 보유 productId 중 하나가 subscriptionProductIds에 포함.
final isSubscribedProvider = Provider<bool>((ref) {
  final isAdmin = ref.watch(adminAuthProvider);
  if (isAdmin) return true;
  final iapState = ref.watch(inAppPurchaseProvider);
  return iapState.purchasedProductIds.any(
    IapConstants.subscriptionProductIds.contains,
  );
});

/// API 호출 결과와 데이터 소스를 함께 전달
class DataWithSource<T> {
  final T data;
  final bool fromApi;
  final String? apiError;

  const DataWithSource({
    required this.data,
    this.fromApi = false,
    this.apiError,
  });
}

String dateToYmd(DateTime d) {
  return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}

String get todayYmd => dateToYmd(DateTime.now());

bool _isRaceDateNotFinished(String dateStr) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final year = int.tryParse(dateStr.substring(0, 4)) ?? 0;
  final month = int.tryParse(dateStr.substring(4, 6)) ?? 0;
  final day = int.tryParse(dateStr.substring(6, 8)) ?? 0;
  final raceDate = DateTime(year, month, day);
  return raceDate.isAfter(today);
}

/// API 연결 상태 확인
final apiStatusProvider = FutureProvider<ApiResult<String>>((ref) async {
  final api = ref.watch(cyclingApiServiceProvider);
  return api.testConnection();
});

/// 월별 경기 날짜 - 출주표 API 기반
final monthRaceDatesProvider =
    FutureProvider.family<Set<String>, ({int venue, int year, int month})>((
      ref,
      params,
    ) async {
      final api = ref.watch(cyclingApiServiceProvider);
      final backup = ref.watch(supabaseBackupProvider);

      final meet = params.venue > 0 ? params.venue : 1;
      final result = await api.fetchRaceDatesForMonth(
        meet: meet,
        year: params.year,
        month: params.month,
      );

      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[Provider] monthRaceDates: API ${result.data!.length}건');
        }
        return result.data!;
      }

      final cached = await backup.loadRaceDatesForMonth(
        venueCode: params.venue,
        year: params.year,
        month: params.month,
      );
      if (cached.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[Provider] monthRaceDates: Supabase 캐시 ${cached.length}건',
          );
        }
        return cached;
      }

      return {};
    });

/// 경기장별 최근 시행일 (yyyyMMdd). 올해 기록이 없으면 작년까지 거슬러 찾는다.
///
/// 창원·부산은 번갈아 시행해 몇 달씩 경주가 없다. 빈 목록만 보여주면
/// 자료를 못 불러온 것으로 오해하기 쉬워 마지막 시행일을 함께 안내한다.
final lastRaceDateProvider = FutureProvider.family<String?, int>((
  ref,
  venue,
) async {
  final api = ref.watch(cyclingApiServiceProvider);
  final thisYear = DateTime.now().year;

  for (final year in [thisYear, thisYear - 1]) {
    final date = await api.latestRaceDate(meet: venue, year: year);
    if (date != null) return date;
  }
  return null;
});

/// 경주 목록 - API → Supabase 캐시
final raceListProvider =
    FutureProvider.family<
      DataWithSource<List<Race>>,
      ({int venue, String date})
    >((ref, params) async {
      final api = ref.watch(cyclingApiServiceProvider);
      final backup = ref.watch(supabaseBackupProvider);
      final venueName = _venueName(params.venue);

      final meet = params.venue > 0 ? params.venue : 1;
      final result = await api.fetchRaceList(meet: meet, date: params.date);

      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[Provider] raceList($venueName, ${params.date}): '
            'API 데이터 ${result.data!.length}건',
          );
        }
        backup.saveRaces(result.data!);
        return DataWithSource(data: result.data!, fromApi: true);
      }

      // 시행하지 않은 것이 확인된 날은 오래된 캐시를 되살리지 않는다.
      if (await api.venueRaced(meet: meet, date: params.date) == false) {
        if (kDebugMode) {
          debugPrint(
            '[Provider] raceList($venueName, ${params.date}): 미시행 확인',
          );
        }
        return const DataWithSource(data: <Race>[], fromApi: true);
      }

      final cached = await backup.loadRaces(
        venueCode: params.venue,
        date: params.date,
      );
      if (cached.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[Provider] raceList($venueName, ${params.date}): '
            'Supabase 캐시 ${cached.length}건',
          );
        }
        return DataWithSource(data: cached, fromApi: false, apiError: '캐시 데이터');
      }

      if (kDebugMode) {
        debugPrint(
          '[Provider] raceList($venueName, ${params.date}): '
          'API/캐시 없음 → 빈 목록 (${result.errorMessage})',
        );
      }
      return DataWithSource(
        data: <Race>[],
        fromApi: false,
        apiError: result.errorMessage,
      );
    });

/// 출주표 - API·크롤링 → Supabase 캐시
final raceEntriesProvider =
    FutureProvider.family<
      DataWithSource<List<RaceEntry>>,
      ({int venue, String date, int raceNo})
    >((ref, params) async {
      final api = ref.watch(cyclingApiServiceProvider);
      final backup = ref.watch(supabaseBackupProvider);
      final venueName = _venueName(params.venue);

      final organResult = await api.fetchRaceOrgan(
        meet: params.venue,
        date: params.date,
        rcNo: params.raceNo,
      );
      if (organResult.isSuccess &&
          organResult.data != null &&
          organResult.data!.isNotEmpty) {
        if (kDebugMode) {
          final names = organResult.data!.map((e) => e.riderName).toList();
          debugPrint(
            '[Provider] entries($venueName, ${params.date}, R${params.raceNo}): '
            '데이터 ${organResult.data!.length}명 $names',
          );
        }
        backup.saveEntries(
          venueCode: params.venue,
          date: params.date,
          raceNo: params.raceNo,
          entries: organResult.data!,
        );
        return DataWithSource(data: organResult.data!, fromApi: true);
      }

      // 시행하지 않은 것이 확인된 날은 오래된 캐시를 되살리지 않는다.
      if (await api.venueRaced(meet: params.venue, date: params.date) == false) {
        return const DataWithSource(data: <RaceEntry>[], fromApi: true);
      }

      final cached = await backup.loadEntries(
        venueCode: params.venue,
        date: params.date,
        raceNo: params.raceNo,
      );
      if (cached.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '[Provider] entries($venueName, ${params.date}, R${params.raceNo}): '
            'Supabase 캐시 ${cached.length}명',
          );
        }
        return DataWithSource(data: cached, fromApi: false, apiError: '캐시 데이터');
      }

      if (kDebugMode) {
        debugPrint(
          '[Provider] entries($venueName, ${params.date}, R${params.raceNo}): '
          '출주표 없음 (${organResult.errorMessage})',
        );
      }
      return DataWithSource(
        data: const <RaceEntry>[],
        fromApi: false,
        apiError: organResult.errorMessage,
      );
    });

/// 배당률 - 경주결과의 확정 배당
///
/// 확정 배당은 착순과 같은 레코드에서 파싱되므로 경주 결과와 항상 일치한다.
/// 아직 확정되지 않은 경주는 빈 배당을 반환한다.
final oddsProvider =
    FutureProvider.family<Odds, ({int venue, String date, int raceNo})>((
      ref,
      params,
    ) async {
      try {
        return (await ref.watch(raceResultProvider(params).future)).payoff;
      } catch (_) {
        return const Odds();
      }
    });

/// 이름 Set 생성 (trim + 공백 제거로 비교 안정성 확보)
Set<String> _normalizeNames(Iterable<String> names) => names
    .map((n) => n.trim().replaceAll(' ', ''))
    .where((n) => n.isNotEmpty)
    .toSet();

/// 공식 확정배당의 순서형 승식에서 실제 1·2·3착 배번을 복원한다.
List<int> _finishOrderFromOdds(Odds odds) {
  List<int> parse(String key) =>
      key.split('-').map(int.tryParse).whereType<int>().toList();

  if (odds.trifecta.isNotEmpty) {
    return parse(odds.trifecta.keys.first);
  }
  if (odds.exactaTrio.isNotEmpty) {
    return parse(odds.exactaTrio.keys.first);
  }
  if (odds.exacta.isNotEmpty && odds.trio.isNotEmpty) {
    final firstTwo = parse(odds.exacta.keys.first);
    final topThree = parse(odds.trio.keys.first);
    if (firstTwo.length == 2 && topThree.length == 3) {
      final third = topThree.where((no) => !firstTwo.contains(no)).firstOrNull;
      if (third != null) return [...firstTwo, third];
    }
  }
  return const [];
}

/// 경주 결과 - 착순과 확정 배당을 함께 담은 단일 소스
///
/// 출주표가 실제 API 데이터일 때만 선수명 교차 검증을 수행한다.
/// 출주표가 목업이면 검증 자체가 무의미하므로 API 결과를 그대로 신뢰한다.
final raceResultProvider =
    FutureProvider.family<RaceResult, ({int venue, String date, int raceNo})>((
      ref,
      params,
    ) async {
      final api = ref.watch(cyclingApiServiceProvider);
      final entries = await ref.watch(
        raceEntriesProvider((
          venue: params.venue,
          date: params.date,
          raceNo: params.raceNo,
        )).future,
      );
      final entryNames = entries.fromApi
          ? _normalizeNames(entries.data.map((e) => e.riderName))
          : <String>{};
      RaceResult? apiResultWithoutPayoff;

      final result = await api.fetchRaceResult(
        meet: params.venue,
        date: params.date,
        rcNo: params.raceNo,
      );
      if (result.isSuccess && result.data != null) {
        final matched = result.data!
            .where((r) => r.raceNo == params.raceNo && r.hasPlacings)
            .toList();
        if (matched.isNotEmpty) {
          final r = matched.first;
          final names = _normalizeNames({r.first, r.second, r.third});
          if (entryNames.isEmpty || names.intersection(entryNames).isNotEmpty) {
            if (r.payoff.isNotEmpty) return r;

            final officialOdds = await ref
                .watch(kcycleResultServiceProvider)
                .fetchDecisionOdds(
                  year: int.parse(params.date.substring(0, 4)),
                  round: r.round,
                  dayOrd: r.dayOrd,
                  meet: params.venue,
                  raceNo: params.raceNo,
                );
            if (officialOdds.isNotEmpty) {
              return RaceResult(
                raceNo: r.raceNo,
                first: r.first,
                firstNo: r.firstNo,
                second: r.second,
                secondNo: r.secondNo,
                third: r.third,
                thirdNo: r.thirdNo,
                payoff: officialOdds,
                round: r.round,
                dayOrd: r.dayOrd,
              );
            }
            apiResultWithoutPayoff = r;
          } else if (kDebugMode) {
            debugPrint(
              '[Provider] raceResult: API 결과 $names ≠ 출주표 $entryNames',
            );
          }
        }
      }

      // 광명 경주결과 API가 늦게 갱신되더라도 순위 API에는 착순·회차가 먼저
      // 공개되는 경우가 있다. 이때 KCYCLE 공식 확정배당과 합쳐 결과를 만든다.
      if (params.venue == 1) {
        final rankResult = await api.fetchRaceRank(
          meet: params.venue,
          date: params.date,
          rcNo: params.raceNo,
        );
        final rankRows =
            rankResult.data ?? const <Map<String, dynamic>>[];
        if (rankRows.isNotEmpty) {
          final backNoByName = {
            for (final entry in entries.data)
              _nameKey(entry.riderName): entry.lineNo,
          };
          final nameByBackNo = {
            for (final entry in entries.data) entry.lineNo: entry.riderName,
          };
          int backNo(Map<String, dynamic> row) =>
              backNoByName[_nameKey(row['racer_nm']?.toString() ?? '')] ?? 0;
          final round = rankRows.first['round'] as int? ?? 0;
          final dayOrd = rankRows.first['day_ord'] as int? ?? 0;
          final officialOdds = await ref
              .watch(kcycleResultServiceProvider)
              .fetchDecisionOdds(
                year: int.parse(params.date.substring(0, 4)),
                round: round,
                dayOrd: dayOrd,
                meet: params.venue,
                raceNo: params.raceNo,
              );

          final officialOrder = _finishOrderFromOdds(officialOdds);
          if (officialOrder.length >= 3) {
            return RaceResult(
              raceNo: params.raceNo,
              first: nameByBackNo[officialOrder[0]] ?? '',
              firstNo: officialOrder[0],
              second: nameByBackNo[officialOrder[1]] ?? '',
              secondNo: officialOrder[1],
              third: nameByBackNo[officialOrder[2]] ?? '',
              thirdNo: officialOrder[2],
              payoff: officialOdds,
              round: round,
              dayOrd: dayOrd,
            );
          }

          final ranked = rankRows
              .where((row) => (row['rank'] as int? ?? 0) > 0)
              .take(3)
              .toList();
          if (ranked.length == 3) {
            return RaceResult(
              raceNo: params.raceNo,
              first: ranked[0]['racer_nm']?.toString() ?? '',
              firstNo: backNo(ranked[0]),
              second: ranked[1]['racer_nm']?.toString() ?? '',
              secondNo: backNo(ranked[1]),
              third: ranked[2]['racer_nm']?.toString() ?? '',
              thirdNo: backNo(ranked[2]),
              payoff: officialOdds,
              round: round,
              dayOrd: dayOrd,
            );
          }
        }
      }

      final lepopark = await _lepoparkRace(ref, params);
      if (lepopark != null) {
        if (kDebugMode) {
          debugPrint('[Provider] raceResult: lepopark 결과 사용');
        }
        return _raceResultFrom(lepopark);
      }

      if (apiResultWithoutPayoff != null) return apiResultWithoutPayoff;

      if (_isRaceDateNotFinished(params.date)) {
        throw const RaceNotYetException();
      }
      throw const RaceDataUnavailableException();
    });

/// 창원레포츠파크에서 해당 경주의 확정 결과를 찾는다.
///
/// 광명은 공공데이터 API가 전 경주를 싣기 때문에 조회하지 않는다.
Future<LepoparkRaceResult?> _lepoparkRace(
  Ref ref,
  ({int venue, String date, int raceNo}) params,
) async {
  if (params.venue == 1) return null;

  final service = ref.watch(lepoparkResultServiceProvider);
  final race = await service.fetchRace(
    meet: params.venue,
    date: params.date,
    raceNo: params.raceNo,
  );
  return (race != null && race.ranks.isNotEmpty) ? race : null;
}

/// 크롤링한 착순표를 경주 결과 모델로 옮긴다.
///
/// 회차·일차는 KCYCLE 상세 조회에만 쓰이는데 이 경로에서는 필요 없으므로 0으로 둔다.
RaceResult _raceResultFrom(LepoparkRaceResult race) {
  final placings = race.placings;
  ({int backNo, String name}) at(int index) =>
      index < placings.length ? placings[index] : (backNo: 0, name: '');

  return RaceResult(
    raceNo: race.raceNo,
    first: at(0).name,
    firstNo: at(0).backNo,
    second: at(1).name,
    secondNo: at(1).backNo,
    third: at(2).name,
    thirdNo: at(2).backNo,
    payoff: race.payoff,
  );
}

/// 경주 순위 목록
///
/// 1순위: KCYCLE 상세 착순표 (배번·착차·주행시간·승부수까지 제공)
/// 2순위: 공공데이터 순위 API (선수명·착순만 제공, 배번은 출주표로 보강)
final raceRankProvider =
    FutureProvider.family<
      List<Map<String, dynamic>>,
      ({int venue, String date, int raceNo})
    >((ref, params) async {
      final entries = await ref.watch(
        raceEntriesProvider((
          venue: params.venue,
          date: params.date,
          raceNo: params.raceNo,
        )).future,
      );
      final result = await _tryRaceResult(ref, params);

      if (result != null) {
        final details = await _fetchKcycleDetails(ref, params, result);
        if (details.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('[Provider] raceRank: KCYCLE 상세 ${details.length}건 사용');
          }
          return _withGrades(details, entries);
        }
      }

      final lepopark = await _lepoparkRace(ref, params);
      if (lepopark != null) {
        if (kDebugMode) {
          debugPrint('[Provider] raceRank: lepopark 상세 ${lepopark.ranks.length}건 사용');
        }
        return _withGrades(lepopark.ranks, entries);
      }

      final api = ref.watch(cyclingApiServiceProvider);
      final rankResult = await api.fetchRaceRank(
        meet: params.venue,
        date: params.date,
        rcNo: params.raceNo,
      );
      if (rankResult.isSuccess &&
          rankResult.data != null &&
          rankResult.data!.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('[Provider] raceRank: 공공 API ${rankResult.data!.length}건 사용');
        }
        return _withGrades(
          _withBackNumbers(rankResult.data!, entries, result),
          entries,
        );
      }

      if (_isRaceDateNotFinished(params.date)) {
        throw const RaceNotYetException();
      }
      throw const RaceDataUnavailableException();
    });

/// KCYCLE 상세 착순을 회차를 바꿔가며 조회하고, 확정 착순과 일치하는 것만 채택한다.
///
/// KCYCLE URL의 회차는 전국 공통(광명 기준) 번호인 반면 공공 API는 경기장별
/// 회차를 주므로, 창원·부산은 같은 날 광명의 회차를 먼저 시도해야 한다.
Future<List<Map<String, dynamic>>> _fetchKcycleDetails(
  Ref ref,
  ({int venue, String date, int raceNo}) params,
  RaceResult result,
) async {
  final candidates = <({int round, int dayOrd})>[];

  void addCandidate(int round, int dayOrd) {
    if (round <= 0 || dayOrd <= 0) return;
    if (candidates.any((c) => c.round == round && c.dayOrd == dayOrd)) return;
    candidates.add((round: round, dayOrd: dayOrd));
  }

  if (params.venue != 1) {
    final reference = await _tryRaceResult(ref, (
      venue: 1,
      date: params.date,
      raceNo: 1,
    ));
    if (reference != null) addCandidate(reference.round, reference.dayOrd);
  }
  addCandidate(result.round, result.dayOrd);

  final service = ref.watch(kcycleResultServiceProvider);
  final year = int.parse(params.date.substring(0, 4));

  for (final candidate in candidates) {
    final rows = await service.fetchRankDetails(
      year: year,
      round: candidate.round,
      dayOrd: candidate.dayOrd,
      meet: params.venue,
      raceNo: params.raceNo,
    );
    if (_matchesResult(rows, result)) return rows;
    if (kDebugMode && rows.isNotEmpty) {
      debugPrint('[Provider] KCYCLE ${candidate.round}회 ${candidate.dayOrd}일차: '
          '착순 불일치로 폐기');
    }
  }
  return const [];
}

/// 크롤링한 착순표가 확정 결과의 1착(배번·선수명)과 일치하는지 확인한다.
bool _matchesResult(List<Map<String, dynamic>> rows, RaceResult result) {
  if (rows.isEmpty) return false;
  if (result.firstNo <= 0 || result.first.isEmpty) return false;

  return rows.any(
    (r) =>
        r['back_no'] == result.firstNo &&
        _nameKey(r['racer_nm']?.toString() ?? '') == _nameKey(result.first),
  );
}

String _nameKey(String name) => name.trim().replaceAll(' ', '');

/// 착순 데이터에 없는 등급을 출주표에서 채운다.
List<Map<String, dynamic>> _withGrades(
  List<Map<String, dynamic>> ranks,
  DataWithSource<List<RaceEntry>> entries,
) {
  final gradeByName = {
    for (final e in entries.data)
      if (e.grade.isNotEmpty) _nameKey(e.riderName): e.grade,
  };
  if (gradeByName.isEmpty) return ranks;

  return ranks.map((r) {
    if ((r['racer_grd_cd']?.toString() ?? '').isNotEmpty) return r;
    final grade = gradeByName[_nameKey(r['racer_nm']?.toString() ?? '')];
    return {...r, if (grade != null) 'racer_grd_cd': grade};
  }).toList();
}

/// 공공 순위 API는 배번을 주지 않으므로 출주표·경주결과의 선수명으로 배번을 채운다.
List<Map<String, dynamic>> _withBackNumbers(
  List<Map<String, dynamic>> ranks,
  DataWithSource<List<RaceEntry>> entries,
  RaceResult? result,
) {
  final backNoByName = <String, int>{
    for (final e in entries.data) _nameKey(e.riderName): e.lineNo,
  };
  if (result != null) {
    for (final placing in [
      (result.first, result.firstNo),
      (result.second, result.secondNo),
      (result.third, result.thirdNo),
    ]) {
      final name = _nameKey(placing.$1);
      if (name.isNotEmpty && placing.$2 > 0) backNoByName[name] = placing.$2;
    }
  }

  return ranks.map((r) {
    final backNo = backNoByName[_nameKey(r['racer_nm']?.toString() ?? '')];
    return {...r, if (backNo != null) 'back_no': backNo};
  }).toList();
}

Future<RaceResult?> _tryRaceResult(
  Ref ref,
  ({int venue, String date, int raceNo}) params,
) async {
  try {
    return await ref.watch(raceResultProvider(params).future);
  } catch (_) {
    return null;
  }
}

/// AI 예측 결과 - 출주표 기반 로컬 예측 + Supabase 백업
final predictionProvider =
    FutureProvider.family<
      RacePrediction,
      ({int venue, String date, int raceNo})
    >((ref, params) async {
      final backup = ref.watch(supabaseBackupProvider);
      final entriesResult = await ref.watch(
        raceEntriesProvider((
          venue: params.venue,
          date: params.date,
          raceNo: params.raceNo,
        )).future,
      );

      final prediction = PredictionEngine.predict(entriesResult.data);
      backup.savePrediction(
        venueCode: params.venue,
        date: params.date,
        raceNo: params.raceNo,
        prediction: prediction,
      );
      return prediction;
    });

/// 출주표 원시 데이터에서 RiderDetail 집계
RiderDetail _buildRiderProfile({
  required String riderId,
  required String riderName,
  required String grade,
  required String tactic,
  required double avgScore,
  required List<Map<String, dynamic>> records,
}) {
  int brkWins = 0, mrkWins = 0, chaseWins = 0;
  int race1st = 0, race2nd = 0, race3rd = 0;
  final scores = <double>[];
  final raceRecords = <RiderRaceRecord>[];
  final venueAgg = <int, ({int total, int wins, int podiums})>{};

  for (final m in records) {
    brkWins += int.tryParse(m['brk_win_cnt']?.toString() ?? '') ?? 0;
    mrkWins += int.tryParse(m['mrk_win_cnt']?.toString() ?? '') ?? 0;
    chaseWins += int.tryParse(m['win_tot_tcnt']?.toString() ?? '') ?? 0;

    final rank = int.tryParse(
      m['race_rank']?.toString() ?? m['arrv_ordr']?.toString() ?? '',
    );
    if (rank == 1) race1st++;
    if (rank == 2) race2nd++;
    if (rank == 3) race3rd++;

    final scr = double.tryParse(m['tot_tms_avg_scr']?.toString() ?? '');
    if (scr != null && scr > 0) scores.add(scr);

    final date = (m['race_ymd']?.toString() ?? m['race_de']?.toString() ?? '').trim();
    final raceNo = int.tryParse(m['race_no']?.toString() ?? '') ?? 0;
    final rGrade = m['racer_grd_cd']?.toString() ??
        m['racer_grd_cur_cd']?.toString() ??
        '-';
    final venueCode = int.tryParse(m['meet']?.toString() ?? '');
    raceRecords.add(RiderRaceRecord(
      date: date,
      raceNo: raceNo,
      grade: rGrade,
      rank: rank,
      score: scr,
      venueCode: venueCode,
    ));

    if (venueCode != null) {
      final prev = venueAgg[venueCode] ?? (total: 0, wins: 0, podiums: 0);
      venueAgg[venueCode] = (
        total: prev.total + 1,
        wins: prev.wins + (rank == 1 ? 1 : 0),
        podiums: prev.podiums + ((rank != null && rank <= 3) ? 1 : 0),
      );
    }
  }

  // 추입은 전체 우승에서 선행·마크 제외
  final adjustedChase = (chaseWins - brkWins - mrkWins).clamp(0, chaseWins);

  final recentScores = scores.length > 5
      ? scores.sublist(scores.length - 5)
      : scores;
  final recentAvg = recentScores.isNotEmpty
      ? recentScores.reduce((a, b) => a + b) / recentScores.length
      : null;

  // 최근 5경기 상세: records 는 이미 날짜 오름차순 정렬이라 마지막 5개 사용
  final recentRaces = raceRecords.length > 5
      ? raceRecords.sublist(raceRecords.length - 5).reversed.toList()
      : raceRecords.reversed.toList();

  final venueBreakdown = venueAgg.map(
    (k, v) => MapEntry(
      k,
      VenueRecord(total: v.total, wins: v.wins, podiums: v.podiums),
    ),
  );

  // 선수 배경(나이·학교·훈련지·기수·기어·200m·이전등급)은 기록 어느 행에서든 처음 발견되는 값을 사용
  int? age;
  String? school;
  String? trainingBase;
  int? cohort;
  double? gearRatio;
  String? time200m;
  String? previousGrade;
  for (final m in records) {
    age ??= _extractAgeFromMap(m);
    school ??= _extractSchoolFromMap(m);
    trainingBase ??= _extractTrainingBaseFromMap(m);
    cohort ??= _extractCohortFromMap(m);
    gearRatio ??= _extractGearRatioFromMap(m);
    time200m ??= _extractTime200mFromMap(m);
    previousGrade ??= _extractPreviousGradeFromMap(m);
  }
  // API 응답에 나이가 없으면 이름·등급 기반으로 추정(목업과 동일 로직)
  age ??= _estimateRiderAge(riderName, grade);

  return RiderDetail(
    riderId: riderId,
    riderName: riderName,
    grade: grade,
    tactic: tactic,
    avgScore: avgScore,
    breakWins: brkWins,
    markWins: mrkWins,
    chaseWins: adjustedChase,
    yearRaceCount: records.length,
    year1stCount: race1st,
    year2ndCount: race2nd,
    year3rdCount: race3rd,
    recentAvgScore: recentAvg,
    recentScores: recentScores,
    recentRaces: recentRaces,
    venueBreakdown: venueBreakdown,
    age: age,
    school: school,
    trainingBase: trainingBase,
    cohortNo: cohort,
    gearRatio: gearRatio,
    time200m: time200m,
    previousGrade: previousGrade,
  );
}

int? _extractAgeFromMap(Map<String, dynamic> m) {
  final direct = int.tryParse(
    m['age']?.toString() ??
        m['racer_age']?.toString() ??
        m['racr_age']?.toString() ??
        '',
  );
  if (direct != null && direct > 0) return direct;

  final birth = m['brth_dt']?.toString() ??
      m['brth_ymd']?.toString() ??
      m['birthDt']?.toString() ??
      m['birth_ymd']?.toString();
  if (birth != null && birth.length >= 4) {
    final year = int.tryParse(birth.substring(0, 4));
    if (year != null && year > 1900) {
      return DateTime.now().year - year;
    }
  }
  return null;
}

String? _extractSchoolFromMap(Map<String, dynamic> m) {
  final v = _str(m, [
    'schl_nm',
    'school',
    'hakg_nm',
    'schoolNm',
    'grdt_schl',
  ]);
  if (v == null) return null;
  final trimmed = v.trim();
  if (trimmed.isEmpty || trimmed == '-') return null;
  return trimmed;
}

String? _extractTrainingBaseFromMap(Map<String, dynamic> m) {
  final v = _str(m, [
    'train_ym',
    'trainingBase',
    'train_area',
    'trng_area',
    'trng_plc',
  ]);
  if (v == null) return null;
  final trimmed = v.trim();
  if (trimmed.isEmpty || trimmed == '-') return null;
  return trimmed;
}

int _estimateRiderAge(String riderName, String grade) {
  final seed = riderName.hashCode.abs();
  final r = seed % 100;
  final ageBase = switch (grade) {
    'S' || 'A1' => 30,
    'A2' || 'B1' => 27,
    _ => 24,
  };
  return ageBase + (r % 8);
}

int? _extractCohortFromMap(Map<String, dynamic> m) {
  final v = int.tryParse(
    m['cohort']?.toString() ??
        m['entr_no']?.toString() ??
        m['ord_no']?.toString() ??
        m['racr_ord']?.toString() ??
        m['racer_ord']?.toString() ??
        '',
  );
  if (v != null && v > 0 && v < 100) return v;
  return null;
}

double? _extractGearRatioFromMap(Map<String, dynamic> m) {
  final v = double.tryParse(
    m['gear_ratio']?.toString() ??
        m['gear']?.toString() ??
        m['gerbe']?.toString() ??
        '',
  );
  if (v != null && v > 2.5 && v < 5.5) return v;
  return null;
}

String? _extractTime200mFromMap(Map<String, dynamic> m) {
  final v = _str(m, [
    'time_200m',
    'record_200',
    'time200',
    'rec_200m',
    'twoh_rec',
  ]);
  if (v == null) return null;
  final trimmed = v.trim();
  if (trimmed.isEmpty || trimmed == '-' || trimmed == '0') return null;
  return trimmed;
}

String? _extractPreviousGradeFromMap(Map<String, dynamic> m) {
  final v = _str(m, [
    'racer_grd_pre_cd',
    'prev_grade',
    'grd_pre',
    'previousGrade',
  ]);
  if (v == null) return null;
  final trimmed = v.trim();
  if (trimmed.isEmpty || trimmed == '-') return null;
  return trimmed;
}

/// 선수 상세 - riderId만으로 조회 (직접 진입 시 사용)
final riderDetailByIdProvider =
    FutureProvider.family<RiderDetail, ({String riderId, int? venue})>((
      ref,
      params,
    ) async {
      final api = ref.watch(cyclingApiServiceProvider);
      final numericId = params.riderId.replaceAll(RegExp(r'[^0-9]'), '');
      final date = dateToYmd(DateTime.now());

      if (numericId.isNotEmpty && params.venue != null) {
        final result = await api.fetchRacerDetail(
          riderId: numericId,
          meet: params.venue,
          date: date,
        );
        if (result.isSuccess && result.data != null) {
          final m = result.data!;
          final name =
              _str(m, ['racer_nm', 'riderName', 'RIDER_NAME', 'name']) ??
              params.riderId;
          final grade =
              _str(m, ['racer_grd_cd', 'grade', 'GRADE', 'grde']) ?? '-';
          final avg =
              _double(m, [
                'tot_tms_avg_scr',
                'avgScore',
                'AVG_SCORE',
                'avgPt',
              ]) ??
              0.0;

          final allRecords = await api.fetchRacerAllRecords(
            riderName: name,
            meet: params.venue,
            date: date,
          );

          return _buildRiderProfile(
            riderId: params.riderId,
            riderName: name,
            grade: grade,
            tactic: _extractTacticFromMap(m),
            avgScore: avg,
            records: allRecords.data ?? [],
          );
        }
      }

      return RiderDetail(
        riderId: params.riderId,
        riderName: params.riderId,
        grade: '-',
        avgScore: 0,
        age: _estimateRiderAge(params.riderId, '-'),
      );
    });

/// 선수 상세 - entry 기반, API로 보강 시도
final riderDetailProvider =
    FutureProvider.family<RiderDetail, ({RaceEntry entry, int? venue})>((
      ref,
      params,
    ) async {
      final entry = params.entry;
      final api = ref.watch(cyclingApiServiceProvider);
      final date = dateToYmd(DateTime.now());

      final allRecords = await api.fetchRacerAllRecords(
        riderName: entry.riderName,
        meet: params.venue,
        date: date,
      );

      if (allRecords.isSuccess &&
          allRecords.data != null &&
          allRecords.data!.isNotEmpty) {
        final latest = allRecords.data!.last;
        final grade =
            _str(latest, ['racer_grd_cd', 'racer_grd_cur_cd']) ?? entry.grade;
        final avg = _double(latest, ['tot_tms_avg_scr']) ?? entry.avgScore;

        return _buildRiderProfile(
          riderId: entry.riderId,
          riderName: entry.riderName,
          grade: grade,
          tactic: _extractTacticFromMap(latest),
          avgScore: avg,
          records: allRecords.data!,
        );
      }

      return RiderDetail.fromRaceEntryDetailed(entry);
    });

String _extractTacticFromMap(Map<String, dynamic> m) {
  final brkCnt = int.tryParse(m['brk_win_cnt']?.toString() ?? '') ?? 0;
  final mrkCnt = int.tryParse(m['mrk_win_cnt']?.toString() ?? '') ?? 0;
  if (brkCnt > mrkCnt && brkCnt > 0) return '선행';
  if (mrkCnt > brkCnt && mrkCnt > 0) return '마크';
  if (brkCnt > 0 || mrkCnt > 0) return '추입';
  return '';
}

double? _double(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    if (v is double) return v;
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v);
  }
  return null;
}

String? _str(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    if (v is String && v.isNotEmpty) return v;
    return v.toString();
  }
  return null;
}
