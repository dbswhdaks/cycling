import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/data/mock_data.dart';
import '../../../core/services/cycling_api_service.dart';
import '../../../core/services/prediction_engine.dart';
import '../../../core/services/supabase_backup_service.dart';
import '../../../models/race.dart';
import '../../../models/race_entry.dart';
import '../../../models/race_result.dart';
import '../../../models/odds.dart';
import '../../../models/prediction.dart';
import '../../../models/rider_detail.dart';

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

/// API 호출 결과와 데이터 소스를 함께 전달
class DataWithSource<T> {
  final T data;
  final bool fromApi;
  final String? apiError;

  const DataWithSource({required this.data, this.fromApi = false, this.apiError});
}

String dateToYmd(DateTime d) {
  return '${d.year}${d.month.toString().padLeft(2, '0')}${d.day.toString().padLeft(2, '0')}';
}

String get todayYmd => dateToYmd(DateTime.now());

/// API 연결 상태 확인
final apiStatusProvider = FutureProvider<ApiResult<String>>((ref) async {
  final api = ref.watch(cyclingApiServiceProvider);
  return api.testConnection();
});

/// 월별 경기 날짜 - 출주표 API 기반
final monthRaceDatesProvider = FutureProvider.family<
    Set<String>,
    ({int venue, int year, int month})>((ref, params) async {
  final api = ref.watch(cyclingApiServiceProvider);
  final backup = ref.watch(supabaseBackupProvider);

  final meet = params.venue > 0 ? params.venue : 1;
  final result = await api.fetchRaceDatesForMonth(
    meet: meet,
    year: params.year,
    month: params.month,
  );

  if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
    if (kDebugMode) debugPrint('[Provider] monthRaceDates: API ${result.data!.length}건');
    return result.data!;
  }

  final cached = await backup.loadRaceDatesForMonth(
    venueCode: params.venue,
    year: params.year,
    month: params.month,
  );
  if (cached.isNotEmpty) {
    if (kDebugMode) debugPrint('[Provider] monthRaceDates: Supabase 캐시 ${cached.length}건');
    return cached;
  }

  return {};
});

/// 경주 목록 - API → Supabase 캐시
final raceListProvider =
    FutureProvider.family<DataWithSource<List<Race>>, ({int venue, String date})>(
        (ref, params) async {
  final api = ref.watch(cyclingApiServiceProvider);
  final backup = ref.watch(supabaseBackupProvider);

  final meet = params.venue > 0 ? params.venue : 1;
  final result = await api.fetchRaceList(
    meet: meet,
    date: params.date,
  );

  if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
    if (kDebugMode) debugPrint('[Provider] raceList: API 데이터 ${result.data!.length}건');
    backup.saveRaces(result.data!);
    return DataWithSource(data: result.data!, fromApi: true);
  }

  final cached = await backup.loadRaces(venueCode: params.venue, date: params.date);
  if (cached.isNotEmpty) {
    if (kDebugMode) debugPrint('[Provider] raceList: Supabase 캐시 ${cached.length}건');
    return DataWithSource(data: cached, fromApi: false, apiError: '캐시 데이터');
  }

  if (kDebugMode) debugPrint('[Provider] raceList: 데이터 없음 (${result.errorMessage})');
  return DataWithSource(data: [], fromApi: false, apiError: result.errorMessage);
});

/// 출주표 - API → Supabase 캐시 → 목업
final raceEntriesProvider = FutureProvider.family<DataWithSource<List<RaceEntry>>,
    ({int venue, String date, int raceNo})>((ref, params) async {
  final api = ref.watch(cyclingApiServiceProvider);
  final backup = ref.watch(supabaseBackupProvider);

  final organResult = await api.fetchRaceOrgan(
    meet: params.venue,
    date: params.date,
    rcNo: params.raceNo,
  );
  if (organResult.isSuccess && organResult.data != null && organResult.data!.isNotEmpty) {
    backup.saveEntries(
      venueCode: params.venue, date: params.date,
      raceNo: params.raceNo, entries: organResult.data!,
    );
    return DataWithSource(data: organResult.data!, fromApi: true);
  }

  final cached = await backup.loadEntries(
    venueCode: params.venue, date: params.date, raceNo: params.raceNo,
  );
  if (cached.isNotEmpty) {
    if (kDebugMode) debugPrint('[Provider] entries: Supabase 캐시 ${cached.length}건');
    return DataWithSource(data: cached, fromApi: false, apiError: '캐시 데이터');
  }

  return DataWithSource(
    data: MockData.entriesFor(params.raceNo),
    fromApi: false,
    apiError: organResult.errorMessage,
  );
});

/// 배당률 - API → 목업
final oddsProvider = FutureProvider.family<Odds, ({int venue, String date, int raceNo})>(
    (ref, params) async {
  final api = ref.watch(cyclingApiServiceProvider);
  final result = await api.fetchPayoff(
    meet: params.venue,
    date: params.date,
    rcNo: params.raceNo,
  );
  if (result.isSuccess && result.data != null) {
    return result.data!;
  }
  return MockData.oddsFor(params.raceNo);
});

/// 경주 결과 - API → 목업
final raceResultProvider = FutureProvider.family<RaceResult,
    ({int venue, String date, int raceNo})>((ref, params) async {
  final api = ref.watch(cyclingApiServiceProvider);
  final result = await api.fetchRaceResult(
    meet: params.venue,
    date: params.date,
    rcNo: params.raceNo,
  );
  if (result.isSuccess && result.data != null) {
    final matched = result.data!.where((r) => r.raceNo == params.raceNo).toList();
    if (matched.isNotEmpty) return matched.first;
  }
  return MockData.raceResultFor(params.raceNo);
});

/// 경주 순위 목록 - API → 목업
final raceRankProvider = FutureProvider.family<List<Map<String, dynamic>>,
    ({int venue, String date, int raceNo})>((ref, params) async {
  final api = ref.watch(cyclingApiServiceProvider);
  final result = await api.fetchRaceRank(
    meet: params.venue,
    date: params.date,
    rcNo: params.raceNo,
  );
  if (result.isSuccess && result.data != null && result.data!.isNotEmpty) {
    return result.data!;
  }
  return MockData.raceRanksFor(params.raceNo);
});

/// AI 예측 결과 - 출주표 기반 로컬 예측 + Supabase 백업
final predictionProvider = FutureProvider.family<RacePrediction,
    ({int venue, String date, int raceNo})>((ref, params) async {
  final backup = ref.watch(supabaseBackupProvider);
  final entriesResult = await ref.watch(raceEntriesProvider((
    venue: params.venue,
    date: params.date,
    raceNo: params.raceNo,
  )).future);

  final prediction = PredictionEngine.predict(entriesResult.data);
  backup.savePrediction(
    venueCode: params.venue,
    date: params.date,
    raceNo: params.raceNo,
    prediction: prediction,
  );
  return prediction;
});

/// 선수 상세 - entry 기반, API로 보강 시도
final riderDetailProvider =
    FutureProvider.family<RiderDetail, ({RaceEntry entry, int? venue})>(
        (ref, params) async {
  final entry = params.entry;
  final base = RiderDetail.fromRaceEntry(entry);
  final api = ref.watch(cyclingApiServiceProvider);
  final numericId = entry.riderId.replaceAll(RegExp(r'[^0-9]'), '');

  if (numericId.isNotEmpty) {
    final result = await api.fetchRacerDetail(
      riderId: numericId,
      meet: params.venue,
    );
    if (result.isSuccess && result.data != null) {
      final m = result.data!;
      return RiderDetail(
        riderId: entry.riderId,
        riderName: _str(m, ['riderName', 'RIDER_NAME', 'name', 'racerNm']) ?? entry.riderName,
        grade: _str(m, ['grade', 'GRADE', 'grde']) ?? entry.grade,
        tactic: _str(m, ['tactic', 'TACTIC', 'tact']) ?? entry.tactic,
        avgScore: _double(m, ['avgScore', 'AVG_SCORE', 'avgPt']) ?? entry.avgScore,
        recent3Wins: _int(m, ['recent3Wins', 'RECENT3', 'lst3WinCnt']) ?? entry.recent3Wins,
        age: _int(m, ['age', 'AGE']),
        school: _str(m, ['school', 'SCHOOL']),
        trainingBase: _str(m, ['trainingBase', 'TRAINING_BASE', 'trnplc']),
      );
    }
  }
  return base;
});

int? _int(Map<String, dynamic> m, List<String> keys) {
  for (final k in keys) {
    final v = m[k];
    if (v == null) continue;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v);
  }
  return null;
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
