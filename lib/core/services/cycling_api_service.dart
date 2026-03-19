import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../constants/api_constants.dart';
import '../network/dio_client.dart';
import '../../models/race.dart';
import '../../models/race_entry.dart';
import '../../models/race_result.dart';
import '../../models/odds.dart';
import 'venue_scraping_service.dart';

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
/// data.go.kr 출주표 API의 `meet` 파라미터가 경기장을 구분하지 못하는 경우가 있다.
/// 따라서 3개 경기장(meet=1,2,3)을 모두 호출하여 합친 뒤,
/// 응답 내 `meet` 필드로 경기장별 분리·캐시한다.
class CyclingApiService {
  final Dio _dio = dioClient;
  final VenueScrapingService _scraper = VenueScrapingService();

  /// 경기장별 출주표 캐시 (key: "year_meet")
  final Map<String, List<Map<String, dynamic>>> _organCache = {};

  /// 연도별 전체 로드 완료 플래그
  final Set<int> _loadedYears = {};

  /// 날짜별 스크래핑 데이터 캐시 (key: "date_meet")
  final Map<String, List<Map<String, dynamic>>> _scrapeCache = {};

  Map<String, dynamic> _baseParams({int pageNo = 1, int numOfRows = 1000}) => {
        'serviceKey': ApiConstants.serviceKey,
        'pageNo': pageNo,
        'numOfRows': numOfRows,
        'resultType': 'json',
      };

  // ─────────────────────────── 전체 출주표 (경기장별 개별 로드) ───────────────────────────

  /// 지정 연도·경기장의 출주표를 반환.
  /// 최초 호출 시 3개 경기장을 각각 개별 호출하여 **섞지 않고** 캐시한다.
  Future<List<Map<String, dynamic>>> fetchAllOrganData({
    required int meet,
    required int year,
  }) async {
    final key = '${year}_$meet';
    if (_organCache.containsKey(key)) return _organCache[key]!;

    if (!_loadedYears.contains(year)) {
      await _loadAllVenues(year);
    }

    return _organCache[key] ?? [];
  }

  /// 광명(meet=1)만 API로 호출하고, 창원·부산은 크롤링 전용으로 전환.
  /// 과거 테스트에서 API가 meet 파라미터를 무시하고 동일 데이터를 반환하므로,
  /// 불필요한 API 호출(meet=2,3)을 제거하여 로딩 속도를 개선한다.
  Future<void> _loadAllVenues(int year) async {
    final sw = Stopwatch()..start();

    // 광명(1)만 API 호출
    final items = await _fetchOrganPages(meet: 1, year: year);
    _organCache['${year}_1'] = items;

    // 창원·부산은 빈 배열 (날짜별 크롤링으로 대체)
    _organCache['${year}_2'] = [];
    _organCache['${year}_3'] = [];

    if (kDebugMode) {
      final sampleNames = items
          .take(10)
          .map((m) => m['racer_nm']?.toString() ?? '?')
          .toSet()
          .toList();
      debugPrint('[API] 광명 API: ${items.length}건 (${sw.elapsedMilliseconds}ms), '
          '선수 샘플=$sampleNames');
      debugPrint('[API] 창원·부산 → 크롤링 대기');
    }

    _loadedYears.add(year);
  }


  /// 페이징 처리하여 출주표 원시 데이터를 반환
  Future<List<Map<String, dynamic>>> _fetchOrganPages({
    required int meet,
    required int year,
  }) async {
    final items = <Map<String, dynamic>>[];
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
        if (kDebugMode && items.isEmpty) {
          debugPrint('[API] _fetchOrganPages(meet=$meet): totalCount=$totalCount');
        }
      }

      final extracted = _extractItems(res.data);
      if (extracted.isEmpty) break;

      for (final item in extracted) {
        if (item is Map) {
          items.add(Map<String, dynamic>.from(item));
        }
      }

      if (items.length >= totalCount || page >= 20) break;
      page++;
    }

    if (kDebugMode && items.isNotEmpty) {
      debugPrint('[API] _fetchOrganPages(meet=$meet): keys=${items.first.keys.toList()}');
    }

    return items;
  }


  /// 크롤링 진행 중 Future (중복 요청 방지)
  Future<Map<int, List<Map<String, dynamic>>>>? _scrapingFuture;

  /// 날짜별 스크래핑 데이터 조회 (캐시 활용, 중복 요청 방지).
  Future<List<Map<String, dynamic>>> _getScrapedData(int meet, String date) async {
    final cacheKey = '${date}_$meet';
    if (_scrapeCache.containsKey(cacheKey)) return _scrapeCache[cacheKey]!;

    try {
      // 이미 같은 날짜를 스크래핑 중이면 기존 Future 재사용
      _scrapingFuture ??= _scraper.scrapeRaceData(date);
      final scraped = await _scrapingFuture!;
      _scrapingFuture = null;

      for (final entry in scraped.entries) {
        _scrapeCache['${date}_${entry.key}'] = entry.value;
      }

      return _scrapeCache[cacheKey] ?? [];
    } catch (e) {
      _scrapingFuture = null;
      if (kDebugMode) debugPrint('[Scrape] _getScrapedData 실패: $e');
      return [];
    }
  }

  /// 캐시를 무효화하여 다음 호출 시 API를 다시 요청하게 한다.
  void invalidateOrganCache({int? year}) {
    if (year != null) {
      for (final m in [1, 2, 3]) {
        _organCache.remove('${year}_$m');
      }
      _loadedYears.remove(year);
    } else {
      _organCache.clear();
      _loadedYears.clear();
    }
    _scrapeCache.clear();
    _scraper.clearCache();
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

      if (matched.isNotEmpty) {
        final races = _buildRacesFromItems(matched, meet, date);
        return ApiResult.success(races);
      }

      // API 캐시가 비어있으면 (창원·부산) 크롤링 시도
      if (meet == 2 || meet == 3) {
        final scraped = await _getScrapedData(meet, date);
        if (scraped.isNotEmpty) {
          final races = _buildRacesFromItems(scraped, meet, date);
          if (kDebugMode) {
            debugPrint('[Scrape] fetchRaceList(${ApiConstants.venueName(meet)}): '
                '${races.length}경주 크롤링 성공');
          }
          return ApiResult.success(races);
        }
      }

      return const ApiResult.success([]);
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

      if (matched.isNotEmpty) {
        final entries = _buildEntriesFromItems(matched);
        return ApiResult.success(entries);
      }

      // API 캐시가 비어있으면 (창원·부산) 크롤링 시도
      if (meet == 2 || meet == 3) {
        final scraped = await _getScrapedData(meet, date);
        final scrapedMatched = scraped.where((m) {
          if (rcNo != null) {
            final rn = int.tryParse(m['race_no']?.toString() ?? '');
            return rn == rcNo;
          }
          return true;
        }).toList();

        if (scrapedMatched.isNotEmpty) {
          final entries = _buildEntriesFromItems(scrapedMatched);
          if (kDebugMode) {
            final names = entries.map((e) => e.riderName).toList();
            debugPrint('[Scrape] fetchRaceOrgan(${ApiConstants.venueName(meet)}, '
                'R$rcNo): ${entries.length}명 $names');
          }
          return ApiResult.success(entries);
        }
      }

      return const ApiResult.success([]);
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

    final sorted = raceMap.keys.toList()
      ..sort((a, b) {
        final timeA = raceMap[a]!.departureTime ?? '';
        final timeB = raceMap[b]!.departureTime ?? '';
        if (timeA.isNotEmpty && timeB.isNotEmpty) return timeA.compareTo(timeB);
        return a.compareTo(b);
      });
    return sorted
        .map((no) => Race(
              venueCode: meet,
              date: dateYmd,
              raceNo: no,
              venueName: ApiConstants.venueName(meet),
              distance: raceMap[no]!.distance ?? 0,
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
