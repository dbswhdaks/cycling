import 'package:dio/dio.dart';
import '../constants/api_constants.dart';
import '../network/dio_client.dart';
import '../../models/race.dart';
import '../../models/race_entry.dart';
import '../../models/race_result.dart';
import '../../models/odds.dart';

/// 공공데이터 API 호출 결과 래퍼
class ApiResult<T> {
  final T? data;
  final String? errorMessage;
  final bool isSuccess;

  const ApiResult.success(this.data)
      : errorMessage = null,
        isSuccess = true;

  const ApiResult.failure(this.errorMessage)
      : data = null,
        isSuccess = false;
}

/// 경륜 공공데이터 API 서비스
///
/// data.go.kr 출주표 API는 `rcDate` 파라미터를 지원하지 않는다.
/// `stnd_yr` + `meet` 로 연도/경기장별 전체 데이터를 받은 뒤
/// 클라이언트에서 `race_ymd` 필드로 날짜를 필터링한다.
class CyclingApiService {
  final Dio _dio = dioClient;

  /// 연도+경기장별 전체 출주표 캐시 (key: "year_meet")
  final Map<String, List<Map<String, dynamic>>> _organCache = {};

  Map<String, dynamic> _baseParams({int pageNo = 1, int numOfRows = 1000}) => {
        'serviceKey': ApiConstants.serviceKey,
        'pageNo': pageNo,
        'numOfRows': numOfRows,
        'resultType': 'json',
      };

  // ─────────────────────────── 전체 출주표 (페이징 + 캐시) ───────────────────────────

  /// 지정 연도·경기장의 출주표 전체를 페이징하여 반환 (캐시 적용).
  Future<List<Map<String, dynamic>>> fetchAllOrganData({
    required int meet,
    required int year,
  }) async {
    final key = '${year}_$meet';
    if (_organCache.containsKey(key)) return _organCache[key]!;

    final allItems = <Map<String, dynamic>>[];
    int page = 1;
    int totalCount = 0;

    while (true) {
      final params = {
        ..._baseParams(pageNo: page),
        'stnd_yr': year.toString(),
        'meet': meet,
      };

      final res = await _dio.get(ApiConstants.raceOrgan, queryParameters: params);
      final error = _checkApiError(res.data);
      if (error != null) break;

      if (page == 1) {
        totalCount = _extractTotalCount(res.data);
      }

      final items = _extractItems(res.data);
      if (items.isEmpty) break;

      for (final item in items) {
        if (item is Map) {
          allItems.add(Map<String, dynamic>.from(item));
        }
      }

      if (allItems.length >= totalCount || page >= 20) break;
      page++;
    }

    _organCache[key] = allItems;
    return allItems;
  }

  /// 캐시를 무효화하여 다음 호출 시 API를 다시 요청하게 한다.
  void invalidateOrganCache({int? meet, int? year}) {
    if (meet != null && year != null) {
      _organCache.remove('${year}_$meet');
    } else {
      _organCache.clear();
    }
  }

  // ─────────────────────────── 경주 목록 (출주표 기반) ───────────────────────────

  Future<ApiResult<List<Race>>> fetchRaceList({
    required int meet,
    required String date,
  }) async {
    try {
      final year = int.parse(date.substring(0, 4));
      final targetYmd = _toApiDateFormat(date);

      final allItems = await fetchAllOrganData(meet: meet, year: year);
      final matched = allItems.where((m) => m['race_ymd']?.toString() == targetYmd).toList();

      if (matched.isEmpty) {
        return const ApiResult.success([]);
      }

      final races = _buildRacesFromItems(matched, meet, date);
      return ApiResult.success(races);
    } on DioException catch (e) {
      return ApiResult.failure(_dioErrorMsg(e));
    } catch (e) {
      return ApiResult.failure('파싱 오류: $e');
    }
  }

  // ─────────────────────────── 월별 경기 날짜 (출주표 기반) ───────────────────────────

  Future<ApiResult<Set<String>>> fetchRaceDatesForMonth({
    required int meet,
    required int year,
    required int month,
  }) async {
    try {
      final allItems = await fetchAllOrganData(meet: meet, year: year);
      final monthPrefix = '$year.${month.toString().padLeft(2, '0')}';
      final dates = <String>{};

      for (final item in allItems) {
        final ymd = item['race_ymd']?.toString() ?? '';
        if (ymd.startsWith(monthPrefix)) {
          dates.add(ymd.replaceAll('.', ''));
        }
      }

      return ApiResult.success(dates);
    } on DioException catch (e) {
      return ApiResult.failure(_dioErrorMsg(e));
    } catch (e) {
      return ApiResult.failure('파싱 오류: $e');
    }
  }

  // ─────────────────────────── 경주 결과 ───────────────────────────

  Future<ApiResult<List<RaceResult>>> fetchRaceResult({
    required int meet,
    required String date,
    int? rcNo,
  }) async {
    try {
      final params = {
        ..._baseParams(),
        'meet': meet,
        'stnd_yr': date.substring(0, 4),
        'stnd_de': date,
        if (rcNo != null) 'rcNo': rcNo,
      };

      final res = await _dio.get(ApiConstants.raceResult, queryParameters: params);
      final error = _checkApiError(res.data);
      if (error != null) return ApiResult.failure(error);

      final items = _extractItems(res.data);
      final all = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final targetYmd = _toApiDateFormat(date);
      final filtered = all.where((m) {
        final ymd = m['race_ymd']?.toString() ?? m['race_de']?.toString() ?? '';
        if (ymd.isEmpty) return true;
        return ymd == targetYmd || ymd == date || ymd.replaceAll('.', '') == date;
      }).toList();

      final source = filtered.isNotEmpty ? filtered : all;
      final results = source.map((e) => _parseRaceResult(e)).toList();
      return ApiResult.success(results);
    } on DioException catch (e) {
      return ApiResult.failure(_dioErrorMsg(e));
    } catch (e) {
      return ApiResult.failure('파싱 오류: $e');
    }
  }

  // ─────────────────────────── 출주표 (캐시 기반) ───────────────────────────

  Future<ApiResult<List<RaceEntry>>> fetchRaceOrgan({
    required int meet,
    required String date,
    int? rcNo,
  }) async {
    try {
      final year = int.parse(date.substring(0, 4));
      final targetYmd = _toApiDateFormat(date);

      final allItems = await fetchAllOrganData(meet: meet, year: year);
      final matched = allItems.where((m) {
        if (m['race_ymd']?.toString() != targetYmd) return false;
        if (rcNo != null) {
          final rn = int.tryParse(m['race_no']?.toString() ?? '');
          return rn == rcNo;
        }
        return true;
      }).toList();

      final entries = _buildEntriesFromItems(matched);
      return ApiResult.success(entries);
    } on DioException catch (e) {
      return ApiResult.failure(_dioErrorMsg(e));
    } catch (e) {
      return ApiResult.failure('파싱 오류: $e');
    }
  }

  // ─────────────────────────── 배당률 ───────────────────────────

  Future<ApiResult<Odds>> fetchPayoff({
    required int meet,
    required String date,
    required int rcNo,
  }) async {
    try {
      final params = {
        ..._baseParams(),
        'meet': meet,
        'stnd_yr': date.substring(0, 4),
        'rcNo': rcNo,
      };

      final res = await _dio.get(ApiConstants.payoff, queryParameters: params);
      final error = _checkApiError(res.data);
      if (error != null) return ApiResult.failure(error);

      final odds = _parseOdds(res.data);
      return ApiResult.success(odds);
    } on DioException catch (e) {
      return ApiResult.failure(_dioErrorMsg(e));
    } catch (e) {
      return ApiResult.failure('파싱 오류: $e');
    }
  }

  // ─────────────────────────── 선수 상세 (연간 전체 기록 집계) ───────────────────────────

  Future<ApiResult<Map<String, dynamic>>> fetchRacerDetail({
    required String riderId,
    int? meet,
    String? date,
  }) async {
    try {
      if (meet == null || date == null) {
        return const ApiResult.failure('경기장·날짜 정보 필요');
      }
      final year = int.parse(date.substring(0, 4));
      final allItems = await fetchAllOrganData(meet: meet, year: year);

      for (final m in allItems) {
        final nm = m['racer_nm']?.toString() ?? '';
        if (nm == riderId || m['back_no']?.toString() == riderId) {
          return ApiResult.success(m);
        }
      }
      return const ApiResult.failure('선수 정보 없음');
    } on DioException catch (e) {
      return ApiResult.failure(_dioErrorMsg(e));
    } catch (e) {
      return ApiResult.failure('파싱 오류: $e');
    }
  }

  /// 선수의 연간 전체 출전 기록을 집계
  Future<ApiResult<List<Map<String, dynamic>>>> fetchRacerAllRecords({
    required String riderName,
    int? meet,
    String? date,
  }) async {
    try {
      if (meet == null || date == null) {
        return const ApiResult.failure('경기장·날짜 정보 필요');
      }
      final year = int.parse(date.substring(0, 4));
      final allItems = await fetchAllOrganData(meet: meet, year: year);

      final normalized = riderName.trim().replaceAll(' ', '');
      final records = allItems.where((m) {
        final nm = (m['racer_nm']?.toString() ?? '').trim().replaceAll(' ', '');
        return nm == normalized;
      }).toList();

      records.sort((a, b) {
        final da = a['race_ymd']?.toString() ?? '';
        final db = b['race_ymd']?.toString() ?? '';
        return da.compareTo(db);
      });

      return ApiResult.success(records);
    } on DioException catch (e) {
      return ApiResult.failure(_dioErrorMsg(e));
    } catch (e) {
      return ApiResult.failure('파싱 오류: $e');
    }
  }

  // ─────────────────────────── 경주 순위 ───────────────────────────

  Future<ApiResult<List<Map<String, dynamic>>>> fetchRaceRank({
    required int meet,
    required String date,
    required int rcNo,
  }) async {
    try {
      final params = {
        ..._baseParams(),
        'meet': meet,
        'stnd_yr': date.substring(0, 4),
        'stnd_de': date,
        'rcNo': rcNo,
      };

      final res = await _dio.get(ApiConstants.raceRank, queryParameters: params);
      final error = _checkApiError(res.data);
      if (error != null) return ApiResult.failure(error);

      final items = _extractItems(res.data);
      final ranks = items.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      final targetYmd = _toApiDateFormat(date);
      final filtered = ranks.where((r) {
        final ymd = r['race_ymd']?.toString() ?? r['race_de']?.toString() ?? '';
        if (ymd.isEmpty) return true;
        return ymd == targetYmd || ymd == date || ymd.replaceAll('.', '') == date;
      }).toList();

      return ApiResult.success(filtered.isNotEmpty ? filtered : ranks);
    } on DioException catch (e) {
      return ApiResult.failure(_dioErrorMsg(e));
    } catch (e) {
      return ApiResult.failure('파싱 오류: $e');
    }
  }

  // ─────────────────────────── API 연결 테스트 ───────────────────────────

  Future<ApiResult<String>> testConnection() async {
    try {
      final params = {..._baseParams(numOfRows: 1)};
      final res = await _dio.get(ApiConstants.raceOrgan, queryParameters: params);

      if (res.statusCode == 200) {
        final error = _checkApiError(res.data);
        if (error != null) return ApiResult.failure(error);
        return const ApiResult.success('연결 성공');
      }
      return ApiResult.failure('HTTP ${res.statusCode}');
    } on DioException catch (e) {
      return ApiResult.failure(_dioErrorMsg(e));
    } catch (e) {
      return ApiResult.failure('$e');
    }
  }

  // ═══════════════════════════ 파싱 헬퍼 ═══════════════════════════

  /// "20260315" → "2026.03.15" (API race_ymd 형식)
  String _toApiDateFormat(String yyyymmdd) {
    if (yyyymmdd.length != 8) return yyyymmdd;
    return '${yyyymmdd.substring(0, 4)}.${yyyymmdd.substring(4, 6)}.${yyyymmdd.substring(6, 8)}';
  }

  int _extractTotalCount(dynamic data) {
    if (data is! Map) return 0;
    final body = (data as Map<String, dynamic>)['response']?['body'];
    if (body is Map) return (body['totalCount'] as num?)?.toInt() ?? 0;
    return 0;
  }

  /// 날짜별로 그룹화된 출주표 아이템에서 Race 목록을 생성
  List<Race> _buildRacesFromItems(
    List<Map<String, dynamic>> items,
    int meet,
    String dateYmd,
  ) {
    final raceMap = <int, _RaceAggregate>{};

    for (final m in items) {
      final rn = int.tryParse(m['race_no']?.toString() ?? '') ?? 0;
      if (rn == 0) continue;

      raceMap.putIfAbsent(rn, () => _RaceAggregate());
      raceMap[rn]!.count++;
      raceMap[rn]!.distance ??= int.tryParse(m['race_len']?.toString() ?? '');
      raceMap[rn]!.departureTime ??= m['dptre_tm']?.toString();
      raceMap[rn]!.roundCount ??= int.tryParse(m['round_cnt']?.toString() ?? '');
    }

    final sorted = raceMap.keys.toList()..sort();
    return sorted
        .map((no) => Race(
              venueCode: meet,
              date: dateYmd,
              raceNo: no,
              venueName: ApiConstants.venueName(meet),
              distance: raceMap[no]!.distance ?? 2025,
              departureTime: raceMap[no]!.departureTime,
              racerCount: raceMap[no]!.count,
              roundCount: raceMap[no]!.roundCount ?? 0,
            ))
        .toList();
  }

  /// 출주표 아이템에서 RaceEntry 목록 생성
  List<RaceEntry> _buildEntriesFromItems(List<Map<String, dynamic>> items) {
    final entries = <RaceEntry>[];
    for (final m in items) {
      final backNo = int.tryParse(m['back_no']?.toString() ?? '') ?? (entries.length + 1);
      entries.add(RaceEntry(
        lineNo: backNo,
        riderName: m['racer_nm']?.toString().trim() ?? '선수$backNo',
        riderId: m['racer_nm']?.toString().trim() ?? 'R$backNo',
        grade: m['racer_grd_cd']?.toString() ?? m['racer_grd_cur_cd']?.toString() ?? '',
        tactic: _extractTactic(m),
        avgScore: double.tryParse(m['tot_tms_avg_scr']?.toString() ?? '') ?? 0,
        recent3Wins: int.tryParse(m['pre_win_cnt']?.toString() ?? '') ?? 0,
      ));
    }
    entries.sort((a, b) => a.lineNo.compareTo(b.lineNo));
    return entries;
  }

  String _extractTactic(Map<String, dynamic> m) {
    final winCnt = int.tryParse(m['win_tot_tcnt']?.toString() ?? '') ?? 0;
    final brkCnt = int.tryParse(m['brk_win_cnt']?.toString() ?? '') ?? 0;
    final mrkCnt = int.tryParse(m['mrk_win_cnt']?.toString() ?? '') ?? 0;
    if (brkCnt > mrkCnt && brkCnt > 0) return '선행';
    if (mrkCnt > brkCnt && mrkCnt > 0) return '마크';
    if (winCnt > 0) return '추입';
    return '';
  }

  Odds _parseOdds(dynamic data) {
    final items = _extractItems(data);
    final win = <int, double>{};
    final place = <String, double>{};
    final quinella = <String, double>{};
    final trio = <String, double>{};
    final trifecta = <String, double>{};

    for (final e in items) {
      if (e is! Map) continue;
      final m = Map<String, dynamic>.from(e);
      final bkno = _intFrom(m, ['bkno', 'BKNO', 'back_no']);
      final winRt = _doubleFrom(m, ['winRt', 'WIN_RT', 'pool1_val']);
      final plcRt = _doubleFrom(m, ['plcRt', 'PLC_RT', 'pool2_val']);

      if (bkno != null && winRt != null) win[bkno] = winRt;

      final combo = _strFrom(m, ['combo', 'COMBO']);
      if (combo != null) {
        if (plcRt != null) place[combo] = plcRt;
      }
    }

    return Odds(win: win, place: place, quinella: quinella, trio: trio, trifecta: trifecta);
  }

  RaceResult _parseRaceResult(Map<String, dynamic> m) {
    return RaceResult(
      raceNo: _intFrom(m, ['race_no', 'rcNo', 'RACE_NO']) ?? 0,
      first: _strFrom(m, ['rank1_nm', 'rank1', 'RANK1_NM', 'first_nm']) ?? '',
      firstNo: _intFrom(m, ['rank1_no', 'rank1_bkno', 'RANK1_NO', 'first_no']) ?? 0,
      second: _strFrom(m, ['rank2_nm', 'rank2', 'RANK2_NM', 'second_nm']) ?? '',
      secondNo: _intFrom(m, ['rank2_no', 'rank2_bkno', 'RANK2_NO', 'second_no']) ?? 0,
      third: _strFrom(m, ['rank3_nm', 'rank3', 'RANK3_NM', 'third_nm']) ?? '',
      thirdNo: _intFrom(m, ['rank3_no', 'rank3_bkno', 'RANK3_NO', 'third_no']) ?? 0,
      winOdds: _doubleFrom(m, ['win_rt', 'winRt', 'WIN_RT', 'pool1_val']) ?? 0,
      placeOdds: _doubleFrom(m, ['plc_rt', 'plcRt', 'PLC_RT', 'pool2_val']) ?? 0,
      quinellaOdds: _doubleFrom(m, ['qnl_rt', 'qnlRt', 'QNL_RT', 'pool3_val']) ?? 0,
    );
  }

  String? _checkApiError(dynamic data) {
    if (data is String) {
      if (data.contains('Unexpected errors')) return 'API 키가 유효하지 않거나 서비스 미신청';
      if (data.contains('SERVICE_KEY_IS_NOT_REGISTERED')) return 'API 키가 등록되지 않음';
      return 'API 응답 형식 오류';
    }
    if (data is! Map) return null;
    final map = data as Map<String, dynamic>;

    final header = map['response']?['header'] ?? map['header'] ?? map['cmmMsgHeader'];
    if (header is Map) {
      final code = header['resultCode']?.toString() ?? header['returnReasonCode']?.toString();
      final msg = header['resultMsg'] ?? header['returnAuthMsg'] ?? header['errMsg'];
      if (code != null && code != '00' && code != '0') {
        return _mapErrorCode(code, msg?.toString() ?? '');
      }
    }
    return null;
  }

  String _mapErrorCode(String code, String msg) {
    return switch (code) {
      '01' => '어플리케이션 에러: $msg',
      '02' => 'DB 에러: $msg',
      '03' => '데이터 없음',
      '04' => 'HTTP 에러: $msg',
      '10' => '잘못된 요청 파라미터: $msg',
      '11' => '필수 파라미터 누락: $msg',
      '12' => 'API 서비스 없음',
      '20' => 'API 키 미등록',
      '21' => 'API 키 만료',
      '22' => 'API 트래픽 초과',
      '30' => '등록되지 않은 API 키',
      '31' => 'API 키 사용 기한 만료',
      '32' => '등록되지 않은 IP',
      _ => '[$code] $msg',
    };
  }

  String _dioErrorMsg(DioException e) {
    return switch (e.type) {
      DioExceptionType.connectionTimeout => '연결 시간 초과',
      DioExceptionType.receiveTimeout => '응답 시간 초과',
      DioExceptionType.connectionError => '네트워크 연결 실패',
      DioExceptionType.badResponse => 'HTTP ${e.response?.statusCode}',
      _ => '네트워크 오류: ${e.message}',
    };
  }

  List<dynamic> _extractItems(dynamic data) {
    if (data == null || data is! Map) return [];
    final map = data as Map<String, dynamic>;

    Map<String, dynamic>? body;
    if (map['response']?['body'] != null) {
      body = Map<String, dynamic>.from(map['response']['body'] as Map);
    } else if (map['body'] != null) {
      body = Map<String, dynamic>.from(map['body'] as Map);
    }

    if (body == null) return [];
    final items = body['items'];
    if (items == null) return [];
    if (items is List) return items;
    if (items is Map) {
      final item = items['item'];
      if (item is List) return item;
      if (item != null) return [item];
    }
    return [];
  }

  int? _intFrom(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) return v;
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
    }
    return null;
  }

  double? _doubleFrom(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is double) return v;
      if (v is num) return v.toDouble();
      if (v is String) return double.tryParse(v);
    }
    return null;
  }

  String? _strFrom(Map<String, dynamic> m, List<String> keys) {
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is String && v.isNotEmpty) return v;
      return v.toString();
    }
    return null;
  }
}

class _RaceAggregate {
  int count = 0;
  int? distance;
  String? departureTime;
  int? roundCount;
}
