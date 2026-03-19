import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../models/race.dart';
import '../../models/race_entry.dart';
import '../../models/prediction.dart';

class SupabaseBackupService {
  SupabaseClient get _client => Supabase.instance.client;

  // ─── 경주 목록 ───

  Future<void> saveRaces(List<Race> races) async {
    if (races.isEmpty) return;
    try {
      final rows = races
          .map((r) => {
                'meet': r.venueCode.toString(),
                'race_date': r.date,
                'race_no': r.raceNo,
                'venue_name': r.venueName,
                'distance': r.distance,
                'status': r.status,
              })
          .toList();
      await _client
          .from('cycling_races')
          .upsert(rows, onConflict: 'meet,race_date,race_no');
      if (kDebugMode) debugPrint('[Supabase] cycling_races ${rows.length}건 저장');
    } catch (e) {
      if (kDebugMode) debugPrint('[Supabase] cycling_races 저장 실패: $e');
    }
  }

  Future<Set<String>> loadRaceDatesForMonth({
    required int venueCode,
    required int year,
    required int month,
  }) async {
    try {
      final mm = month.toString().padLeft(2, '0');
      final startDate = '$year${mm}01';
      final endDate = '$year${mm}31';
      var query = _client
          .from('cycling_races')
          .select('race_date')
          .gte('race_date', startDate)
          .lte('race_date', endDate);
      if (venueCode > 0) {
        query = query.eq('meet', venueCode.toString());
      }
      final res = await query;
      return (res as List)
          .map((m) => (m as Map<String, dynamic>)['race_date'] as String)
          .toSet();
    } catch (e) {
      if (kDebugMode) debugPrint('[Supabase] 월별 경기 날짜 조회 실패: $e');
      return {};
    }
  }

  Future<List<Race>> loadRaces({required int venueCode, required String date}) async {
    try {
      var query = _client.from('cycling_races').select().eq('race_date', date);
      if (venueCode > 0) {
        query = query.eq('meet', venueCode.toString());
      }
      final res = await query.order('race_no');
      return (res as List).map((m) {
        final row = Map<String, dynamic>.from(m);
        return Race(
          venueCode: int.tryParse(row['meet'] as String) ?? 1,
          date: row['race_date'] as String,
          raceNo: row['race_no'] as int,
          venueName: (row['venue_name'] as String?) ?? '광명',
          distance: (row['distance'] as int?) ?? 2025,
          status: (row['status'] as String?) ?? '예정',
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[Supabase] cycling_races 조회 실패: $e');
      return [];
    }
  }

  /// 특정 날짜의 캐시 데이터를 모두 삭제 (잘못 저장된 데이터 정리)
  Future<void> clearCacheForDate(String date) async {
    try {
      await _client.from('cycling_races').delete().eq('race_date', date);
      await _client.from('cycling_entries').delete().eq('race_date', date);
      await _client.from('cycling_predictions').delete().eq('race_date', date);
      if (kDebugMode) debugPrint('[Supabase] $date 캐시 전체 삭제 완료');
    } catch (e) {
      if (kDebugMode) debugPrint('[Supabase] 캐시 삭제 실패: $e');
    }
  }

  // ─── 출주표 ───

  Future<void> saveEntries({
    required int venueCode,
    required String date,
    required int raceNo,
    required List<RaceEntry> entries,
  }) async {
    if (entries.isEmpty) return;
    try {
      final rows = entries
          .map((e) => {
                'meet': venueCode.toString(),
                'race_date': date,
                'race_no': raceNo,
                'line_no': e.lineNo,
                'rider_name': e.riderName,
                'rider_id': e.riderId,
                'grade': e.grade,
                'tactic': e.tactic,
                'avg_score': e.avgScore,
                'recent3_wins': e.recent3Wins,
              })
          .toList();
      await _client
          .from('cycling_entries')
          .upsert(rows, onConflict: 'meet,race_date,race_no,line_no');
      if (kDebugMode) debugPrint('[Supabase] cycling_entries ${rows.length}건 저장');
    } catch (e) {
      if (kDebugMode) debugPrint('[Supabase] cycling_entries 저장 실패: $e');
    }
  }

  Future<List<RaceEntry>> loadEntries({
    required int venueCode,
    required String date,
    required int raceNo,
  }) async {
    try {
      final res = await _client
          .from('cycling_entries')
          .select()
          .eq('meet', venueCode.toString())
          .eq('race_date', date)
          .eq('race_no', raceNo)
          .order('line_no');
      return (res as List).map((m) {
        final row = Map<String, dynamic>.from(m);
        return RaceEntry(
          lineNo: row['line_no'] as int,
          riderName: row['rider_name'] as String,
          riderId: row['rider_id'] as String,
          grade: row['grade'] as String,
          tactic: (row['tactic'] as String?) ?? '선행',
          avgScore: (row['avg_score'] as num?)?.toDouble() ?? 0,
          recent3Wins: (row['recent3_wins'] as int?) ?? 0,
        );
      }).toList();
    } catch (e) {
      if (kDebugMode) debugPrint('[Supabase] cycling_entries 조회 실패: $e');
      return [];
    }
  }

  // ─── AI 예측 ───

  Future<void> savePrediction({
    required int venueCode,
    required String date,
    required int raceNo,
    required RacePrediction prediction,
  }) async {
    try {
      final rows = prediction.rankings.map((r) => {
        'meet': venueCode.toString(),
        'race_date': date,
        'race_no': raceNo,
        'rider_no': r.lineNo,
        'rider_name': r.riderName,
        'win_probability': r.winProb,
        'place_probability': r.totalScore,
        'rank': r.rank,
        'total_score': r.totalScore,
        'factors': r.factors,
        'analysis': prediction.analysis,
        'confidence': prediction.confidence,
      }).toList();
      await _client
          .from('cycling_predictions')
          .upsert(rows, onConflict: 'meet,race_date,race_no,rider_no');
      if (kDebugMode) debugPrint('[Supabase] cycling_predictions ${rows.length}건 저장');
    } catch (e) {
      if (kDebugMode) debugPrint('[Supabase] cycling_predictions 저장 실패: $e');
    }
  }

  Future<RacePrediction?> loadPrediction({
    required int venueCode,
    required String date,
    required int raceNo,
  }) async {
    try {
      final res = await _client
          .from('cycling_predictions')
          .select()
          .eq('meet', venueCode.toString())
          .eq('race_date', date)
          .eq('race_no', raceNo)
          .order('rank');
      final rows = (res as List).cast<Map<String, dynamic>>();
      if (rows.isEmpty) return null;

      final rankings = rows.map((r) => RiderPrediction(
        lineNo: r['rider_no'] as int,
        riderName: r['rider_name'] as String,
        riderId: '',
        grade: '',
        tactic: '',
        winProb: (r['win_probability'] as num?)?.toDouble() ?? 0,
        rank: (r['rank'] as int?) ?? 0,
        totalScore: (r['total_score'] as num?)?.toDouble() ?? 0,
        factors: r['factors'] != null
            ? Map<String, double>.from(
                (r['factors'] as Map).map((k, v) => MapEntry(k.toString(), (v as num).toDouble())))
            : const {},
      )).toList();

      return RacePrediction(
        rankings: rankings,
        confidence: (rows.first['confidence'] as num?)?.toDouble() ?? 0,
        winPicks: const [],
        placePicks: const [],
        quinellaPicks: const [],
        analysis: (rows.first['analysis'] as String?) ?? '',
      );
    } catch (e) {
      if (kDebugMode) debugPrint('[Supabase] cycling_predictions 조회 실패: $e');
      return null;
    }
  }
}
