import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/constants/iap_constants.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/services/cycling_api_service.dart';
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

bool _isRaceDay(String dateStr) {
  if (dateStr.length < 8) return false;
  final year = int.tryParse(dateStr.substring(0, 4)) ?? 0;
  final month = int.tryParse(dateStr.substring(4, 6)) ?? 0;
  final day = int.tryParse(dateStr.substring(6, 8)) ?? 0;
  final weekday = DateTime(year, month, day).weekday;
  return weekday == DateTime.friday ||
      weekday == DateTime.saturday ||
      weekday == DateTime.sunday;
}

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
        if (kDebugMode)
          debugPrint('[Provider] monthRaceDates: API ${result.data!.length}건');
        return result.data!;
      }

      final cached = await backup.loadRaceDatesForMonth(
        venueCode: params.venue,
        year: params.year,
        month: params.month,
      );
      if (cached.isNotEmpty) {
        if (kDebugMode)
          debugPrint(
            '[Provider] monthRaceDates: Supabase 캐시 ${cached.length}건',
          );
        return cached;
      }

      return {};
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

      if (_isRaceDay(params.date)) {
        if (kDebugMode) {
          debugPrint(
            '[Provider] raceList($venueName, ${params.date}): '
            'API/캐시 없음 → 경기일 목업 (${result.errorMessage})',
          );
        }
        return DataWithSource(
          data: MockData.racesFor(params.venue, params.date),
          fromApi: false,
          apiError: result.errorMessage,
        );
      }

      if (kDebugMode) {
        debugPrint(
          '[Provider] raceList($venueName, ${params.date}): '
          'API/캐시 없음 → 비경기일 빈 목록 (${result.errorMessage})',
        );
      }
      return DataWithSource(
        data: <Race>[],
        fromApi: false,
        apiError: result.errorMessage,
      );
    });

/// 출주표 - API → Supabase 캐시 → 목업
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
          '목업 데이터 (${organResult.errorMessage})',
        );
      }
      return DataWithSource(
        data: MockData.entriesFor(params.raceNo, params.venue),
        fromApi: false,
        apiError: organResult.errorMessage,
      );
    });

/// 배당률 - API → 목업
final oddsProvider =
    FutureProvider.family<Odds, ({int venue, String date, int raceNo})>((
      ref,
      params,
    ) async {
      final api = ref.watch(cyclingApiServiceProvider);
      final result = await api.fetchPayoff(
        meet: params.venue,
        date: params.date,
        rcNo: params.raceNo,
      );
      if (result.isSuccess && result.data != null) {
        return result.data!;
      }
      return MockData.oddsFor(params.raceNo, params.venue);
    });

/// 이름 Set 생성 (trim + 공백 제거로 비교 안정성 확보)
Set<String> _normalizeNames(Iterable<String> names) => names
    .map((n) => n.trim().replaceAll(' ', ''))
    .where((n) => n.isNotEmpty)
    .toSet();

/// 경주 결과 - 출주표와 일치하는 결과만 사용, 아니면 출주표 기반 생성
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
      final entryNames = _normalizeNames(entries.data.map((e) => e.riderName));

      final result = await api.fetchRaceResult(
        meet: params.venue,
        date: params.date,
        rcNo: params.raceNo,
      );
      if (result.isSuccess && result.data != null) {
        final matched = result.data!
            .where((r) => r.raceNo == params.raceNo)
            .toList();
        if (matched.isNotEmpty && entryNames.isNotEmpty) {
          final r = matched.first;
          final names = _normalizeNames({
            r.first,
            r.second,
            r.third,
          }).map((n) => n.replaceAll(RegExp(r'[①②③④⑤⑥⑦⑧⑨⑩\s]'), '')).toSet();
          if (names.intersection(entryNames).isNotEmpty) {
            return r;
          }
          if (kDebugMode)
            debugPrint(
              '[Provider] raceResult: API 결과 $names ≠ 출주표 $entryNames',
            );
        }
      }

      if (_isRaceDateNotFinished(params.date)) {
        throw Exception('NOT_YET');
      }
      return MockData.raceResultFor(params.raceNo, entries.data, params.venue);
    });

/// 경주 순위 목록 - 해당 경주 선수만 포함된 결과만 사용, 아니면 출주표 기반 생성
final raceRankProvider =
    FutureProvider.family<
      List<Map<String, dynamic>>,
      ({int venue, String date, int raceNo})
    >((ref, params) async {
      final api = ref.watch(cyclingApiServiceProvider);
      final entries = await ref.watch(
        raceEntriesProvider((
          venue: params.venue,
          date: params.date,
          raceNo: params.raceNo,
        )).future,
      );
      final entryCount = entries.data.length;

      final result = await api.fetchRaceRank(
        meet: params.venue,
        date: params.date,
        rcNo: params.raceNo,
      );

      if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
        final allRanks = result.data!;

        if (allRanks.length <= entryCount + 3) {
          if (kDebugMode)
            debugPrint(
              '[Provider] raceRank: API ${allRanks.length}건 (경주별 데이터) 사용',
            );
          return allRanks;
        }
        if (kDebugMode)
          debugPrint(
            '[Provider] raceRank: API ${allRanks.length}건 (연도 통합) → 출주표 기반 생성',
          );
      }

      if (_isRaceDateNotFinished(params.date)) {
        throw Exception('NOT_YET');
      }
      return MockData.raceRanksFor(params.raceNo, entries.data, params.venue);
    });

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
