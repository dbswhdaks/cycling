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

  /// 진행 중인 연도별 출주표 로드 (동시 호출이 API를 중복 요청하지 않도록)
  final Map<int, Future<void>> _organLoadFutures = {};

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
      try {
        await (_organLoadFutures[year] ??= _loadAllVenues(year));
      } finally {
        _organLoadFutures.remove(year);
      }
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
          final m = Map<String, dynamic>.from(item);
          m.putIfAbsent('meet', () => meet.toString());
          items.add(m);
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


  /// 진행 중인 날짜별 크롤링 Future (같은 날짜의 중복 요청만 합친다)
  final Map<String, Future<Map<int, List<Map<String, dynamic>>>>>
      _scrapingFutures = {};

  /// 날짜별 스크래핑 데이터 조회 (캐시 활용, 중복 요청 방지).
  Future<List<Map<String, dynamic>>> _getScrapedData(int meet, String date) async {
    final cacheKey = '${date}_$meet';
    if (_scrapeCache.containsKey(cacheKey)) return _scrapeCache[cacheKey]!;

    try {
      final scraped = await (_scrapingFutures[date] ??=
          _scraper.scrapeRaceData(date));
      final roster = await _fetchDayRoster(date);

      for (final entry in scraped.entries) {
        _scrapeCache['${date}_${entry.key}'] =
            validateScrapedRaces(entry.value, date, entry.key, roster);
      }

      return _scrapeCache[cacheKey] ?? [];
    } catch (e) {
      if (kDebugMode) debugPrint('[Scrape] _getScrapedData 실패: $e');
      return [];
    } finally {
      _scrapingFutures.remove(date);
    }
  }

  /// 날짜별 실제 편성 (경기장 → 경주번호 → 선수명)
  final Map<String, Map<int, Map<int, Set<String>>>> _dayRosterCache = {};

  /// 해당 날짜에 실제로 시행된 경주 편성을 순위 API에서 가져온다.
  ///
  /// 순위 API는 `meet_nm`을 서버에서 걸러주지 않으므로 한 번의 호출로
  /// 그날 전 경기장 편성을 얻을 수 있다. 미시행(미래) 날짜는 빈 맵을 반환한다.
  Future<Map<int, Map<int, Set<String>>>> _fetchDayRoster(String date) async {
    if (_dayRosterCache.containsKey(date)) return _dayRosterCache[date]!;

    final roster = <int, Map<int, Set<String>>>{};
    try {
      final res = await _dio.get(ApiConstants.raceRank, queryParameters: {
        ..._baseParams(numOfRows: 1000),
        'stnd_year': date.substring(0, 4),
        'race_day': date,
      });

      if (_checkApiError(res.data) == null) {
        for (final item in _extractItems(res.data)) {
          if (item is! Map) continue;
          if (item['race_day']?.toString() != date) continue;

          final meet = _meetCodeOf(item['meet_nm']?.toString() ?? '');
          final raceNo = int.tryParse(item['race_no']?.toString() ?? '');
          final name = _normalizeName(item['racer_nm']?.toString() ?? '');
          if (meet == null || raceNo == null || name.isEmpty) continue;

          ((roster[meet] ??= {})[raceNo] ??= <String>{}).add(name);
        }
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[API] 편성 조회 실패($date): $e');
    }

    _dayRosterCache[date] = roster;
    return roster;
  }

  /// 해당 날짜에 이 경기장이 실제로 경주를 시행했는지 확인한다.
  ///
  /// 아직 시행 전이라 편성 기록 자체가 없으면 판단할 수 없으므로 null을 반환한다.
  Future<bool?> venueRaced({required int meet, required String date}) async {
    final roster = await _fetchDayRoster(date);
    if (roster.isEmpty) return null;
    return roster.containsKey(meet);
  }

  int? _meetCodeOf(String venueName) {
    final name = venueName.trim();
    for (final code in [1, 2, 3]) {
      if (ApiConstants.venueApiName(code) == name) return code;
    }
    return null;
  }

  /// 크롤링 결과를 실제 편성과 대조해 존재하지 않는 경주를 제거한다.
  ///
  /// 크롤링 원본에는 그날 시행되지 않은 경주가 섞여 들어오는 사례가 있다.
  /// 시행 기록이 있으면 그것을 기준으로 삼고, 아직 시행 전이라 기록이 없으면
  /// 광명 출주표와 대조하는 최소 검증만 적용한다.
  @visibleForTesting
  List<Map<String, dynamic>> validateScrapedRaces(
    List<Map<String, dynamic>> scraped,
    String date,
    int meet,
    Map<int, Map<int, Set<String>>> roster,
  ) {
    if (scraped.isEmpty || roster.isEmpty) {
      return _dropMislabeledRaces(scraped, date, meet);
    }

    final venueName = ApiConstants.venueName(meet);
    final held = roster[meet];
    if (held == null || held.isEmpty) {
      if (kDebugMode) {
        debugPrint('[Scrape] $venueName $date: 시행 기록 없음 → 크롤링 결과 폐기');
      }
      return const [];
    }

    final kept = scraped
        .where((m) => held.containsKey(int.tryParse(m['race_no']?.toString() ?? '')))
        .toList();

    if (kDebugMode && kept.length != scraped.length) {
      debugPrint('[Scrape] $venueName $date: 편성에 없는 경주 제외 '
          '(${scraped.length} → ${kept.length}명분)');
    }
    return kept;
  }

  /// 크롤링 원본이 광명 경주를 창원·부산으로 잘못 표기하는 경우가 있어,
  /// 같은 날 광명 출주표에 있는 선수로 채워진 경주는 제외한다.
  ///
  /// 한 선수가 하루에 두 경기장에서 뛸 수 없으므로 선수 명단이 곧 검증 수단이 된다.
  /// 광명 출주표를 아직 받지 못했다면 걸러내지 않는다.
  List<Map<String, dynamic>> _dropMislabeledRaces(
    List<Map<String, dynamic>> scraped,
    String date,
    int meet,
  ) {
    if (scraped.isEmpty) return scraped;

    final year = int.tryParse(date.substring(0, 4));
    final gwangmyeong = _organCache['${year}_1'];
    if (gwangmyeong == null || gwangmyeong.isEmpty) return scraped;

    final targetYmd = _toApiDateFormat(date);
    final gwangmyeongNames = <String>{
      for (final m in gwangmyeong)
        if (m['race_ymd']?.toString() == targetYmd)
          _normalizeName(m['racer_nm']?.toString() ?? ''),
    }..remove('');
    if (gwangmyeongNames.isEmpty) return scraped;

    final byRaceNo = <String, List<Map<String, dynamic>>>{};
    for (final item in scraped) {
      byRaceNo.putIfAbsent(item['race_no']?.toString() ?? '', () => []).add(item);
    }

    final kept = <Map<String, dynamic>>[];
    final dropped = <String>[];
    for (final entry in byRaceNo.entries) {
      final names = entry.value
          .map((m) => _normalizeName(m['racer_nm']?.toString() ?? ''))
          .where((n) => n.isNotEmpty)
          .toList();
      final overlap = names.where(gwangmyeongNames.contains).length;
      if (names.isNotEmpty && overlap * 2 > names.length) {
        dropped.add(entry.key);
        continue;
      }
      kept.addAll(entry.value);
    }

    if (kDebugMode && dropped.isNotEmpty) {
      debugPrint('[Scrape] ${ApiConstants.venueName(meet)} $date: '
          '광명 선수로 채워진 ${dropped.join(",")}경주 제외');
    }
    return kept;
  }

  String _normalizeName(String name) => name.trim().replaceAll(' ', '');

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
    _organLoadFutures.clear();
    _scrapeCache.clear();
    _scrapingFutures.clear();
    _dayRosterCache.clear();
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

  /// 경주결과(착순 + 확정배당)를 조회한다.
  ///
  /// 이 API는 `stnd_de`·`rcNo`·`meet` 파라미터를 인식하지 못하고
  /// `meet_nm`·`race_no`만 서버 필터로 동작한다. 또한 응답의 `race_ymd`가
  /// "MMDD" 형식이므로 날짜는 클라이언트에서 직접 걸러야 한다.
  Future<ApiResult<List<RaceResult>>> fetchRaceResult({
    required int meet,
    required String date,
    int? rcNo,
  }) async {
    try {
      final items = await _fetchResultPages(
        year: date.substring(0, 4),
        meet: meet,
        rcNo: rcNo,
      );

      final targetMmdd = _toMmdd(date);
      final venue = ApiConstants.venueApiName(meet);
      final matched = items.where((m) {
        if (_toMmdd(m['race_ymd']?.toString() ?? '') != targetMmdd) return false;
        final nm = m['meet_nm']?.toString().trim() ?? '';
        return nm.isEmpty || nm == venue;
      }).toList();

      if (kDebugMode) {
        debugPrint('[API] fetchRaceResult($venue, $date, R$rcNo): '
            '${items.length}건 중 ${matched.length}건 일치');
      }

      return ApiResult.success(matched.map(_parseRaceResult).toList());
    } on DioException catch (e) {
      return ApiResult.failure(_dioErrorMsg(e));
    } catch (e) {
      return ApiResult.failure('파싱 오류: $e');
    }
  }

  /// 경주결과 원시 데이터를 페이징 조회 (연도·경기장·경주번호 기준)
  Future<List<Map<String, dynamic>>> _fetchResultPages({
    required String year,
    required int meet,
    int? rcNo,
  }) async {
    final items = <Map<String, dynamic>>[];
    int page = 1;
    int totalCount = 0;

    while (true) {
      final params = {
        ..._baseParams(pageNo: page),
        'stnd_yr': year,
        'meet_nm': ApiConstants.venueApiName(meet),
        if (rcNo != null) 'race_no': rcNo.toString().padLeft(2, '0'),
      };

      final res = await _dio.get(ApiConstants.raceResult, queryParameters: params);
      if (_checkApiError(res.data) != null) break;

      if (page == 1) totalCount = _extractTotalCount(res.data);

      final extracted = _extractItems(res.data);
      if (extracted.isEmpty) break;

      for (final item in extracted) {
        if (item is Map) items.add(Map<String, dynamic>.from(item));
      }

      if (items.length >= totalCount || page >= 20) break;
      page++;
    }

    return items;
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
        final entries = buildEntriesFromItems(matched);
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
          final entries = buildEntriesFromItems(scrapedMatched);
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

  /// 확정 배당을 조회한다.
  ///
  /// 배당률 API(`SRVC_OD_API_CRA_PAYOFF`)는 경기장·조합 번호 없이 금액만 제공해
  /// 착순과 대조할 수 없으므로, 착순과 같은 레코드에서 배당을 파싱하는
  /// 경주결과 API를 사용한다.
  Future<ApiResult<Odds>> fetchPayoff({
    required int meet,
    required String date,
    required int rcNo,
  }) async {
    final result = await fetchRaceResult(meet: meet, date: date, rcNo: rcNo);
    if (!result.isSuccess) return ApiResult.failure(result.errorMessage);

    final matched = result.data!.where((r) => r.raceNo == rcNo);
    if (matched.isEmpty) return const ApiResult.success(Odds());
    return ApiResult.success(matched.first.payoff);
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

  /// 경주별 전체 착순을 조회한다.
  ///
  /// 파라미터명이 다른 API와 달라(`stnd_year`·`race_day`·`race_no`)
  /// 잘못 지정하면 서버가 필터를 무시하고 전 연도 데이터를 반환한다.
  /// `meet_nm`은 서버 필터로 동작하지 않아 여러 경기장이 섞여 오므로
  /// 경기장 구분은 클라이언트에서 처리한다.
  Future<ApiResult<List<Map<String, dynamic>>>> fetchRaceRank({
    required int meet,
    required String date,
    required int rcNo,
  }) async {
    try {
      final venue = ApiConstants.venueApiName(meet);
      final params = {
        ..._baseParams(numOfRows: 100),
        'stnd_year': date.substring(0, 4),
        'race_day': date,
        'meet_nm': venue,
        'race_no': rcNo.toString().padLeft(2, '0'),
      };

      final res = await _dio.get(ApiConstants.raceRank, queryParameters: params);
      final error = _checkApiError(res.data);
      if (error != null) return ApiResult.failure(error);

      final items = _extractItems(res.data);
      final ranks = <Map<String, dynamic>>[];
      for (final item in items) {
        if (item is! Map) continue;
        final m = Map<String, dynamic>.from(item);
        if ((m['race_day']?.toString() ?? date) != date) continue;
        if ((m['meet_nm']?.toString().trim() ?? venue) != venue) continue;
        final raceNo = int.tryParse(m['race_no']?.toString() ?? '');
        if (raceNo != null && raceNo != rcNo) continue;
        ranks.add({
          'rank': int.tryParse(m['race_rank']?.toString() ?? '') ?? 0,
          'racer_nm': m['racer_nm']?.toString().trim() ?? '',
          'racer_no': m['racer_no']?.toString() ?? '',
          'back_no': '',
          'racer_grd_cd': '',
          'race_time': '',
          'arrival_diff': '',
        });
      }

      // 실격·기권(착순 0)은 뒤로 보내고 나머지는 착순 오름차순 정렬
      ranks.sort((a, b) {
        final ra = (a['rank'] as int) == 0 ? 99 : a['rank'] as int;
        final rb = (b['rank'] as int) == 0 ? 99 : b['rank'] as int;
        return ra.compareTo(rb);
      });

      if (kDebugMode) {
        debugPrint('[API] fetchRaceRank(${ApiConstants.venueApiName(meet)}, '
            '$date, R$rcNo): ${ranks.length}명');
      }

      return ApiResult.success(ranks);
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

  /// "20260315" → "2026.03.15" (출주표 API race_ymd 형식)
  String _toApiDateFormat(String yyyymmdd) {
    if (yyyymmdd.length != 8) return yyyymmdd;
    return '${yyyymmdd.substring(0, 4)}.${yyyymmdd.substring(4, 6)}.${yyyymmdd.substring(6, 8)}';
  }

  /// "20260830"·"2026.08.30"·"0830" → "0830" (경주결과 API race_ymd 형식)
  String _toMmdd(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) return digits;
    return digits.substring(digits.length - 4);
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
      raceMap[rn]!.grade ??= _raceGrade(m);
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
              grade: raceMap[no]!.grade ?? '',
            ))
        .toList();
  }

  /// 출주표 항목에서 경주 등급(특선·우수·선발)을 뽑는다.
  ///
  /// 크롤링 데이터는 `race_grd`에 경주 등급을, `racer_grd_cd`에 선수 등급을 담고
  /// 공공 API는 `racer_grd_cd`에 경주 등급을 담아 필드 의미가 다르다.
  String? _raceGrade(Map<String, dynamic> item) {
    const raceGrades = {'특선', '우수', '선발', '일반'};
    for (final key in ['race_grd', 'racer_grd_cd']) {
      final value = item[key]?.toString().trim() ?? '';
      if (value.isEmpty) continue;
      if (raceGrades.any(value.startsWith)) return value;
    }
    return null;
  }

  /// 출주표 아이템에서 RaceEntry 목록 생성
  @visibleForTesting
  List<RaceEntry> buildEntriesFromItems(List<Map<String, dynamic>> items) {
    final entries = <RaceEntry>[];
    for (final m in items) {
      final backNo = int.tryParse(m['back_no']?.toString() ?? '') ?? (entries.length + 1);
      final runDays = _numFrom(m, 'run_day_tcnt');
      final recent = _recentOutings(m);
      entries.add(RaceEntry(
        lineNo: backNo,
        riderName: m['racer_nm']?.toString().trim() ?? '선수$backNo',
        riderId: m['racer_nm']?.toString().trim() ?? 'R$backNo',
        grade: m['racer_grd_cd']?.toString() ?? m['racer_grd_cur_cd']?.toString() ?? '',
        tactic: _extractTactic(m),
        avgScore: _numFrom(m, 'tot_tms_avg_scr'),
        recent3Wins: int.tryParse(m['pre_win_cnt']?.toString() ?? '') ?? 0,
        riderGrade: m['racer_grd_cur_cd']?.toString().trim() ?? '',
        areaAvgScore: _numFrom(m, 'area_tms3_avg_scr'),
        winRate: _numFrom(m, 'win_rate'),
        recentFinishes: [for (final outing in recent) outing.finish],
        recentClasses: [for (final outing in recent) outing.raceClass],
        sprint200m: _parseSeconds(m['rec_200m_scr']?.toString()),
        age: int.tryParse(m['racer_age']?.toString() ?? '') ?? 0,
        trainingPlace: m['trng_plc_nm']?.toString().trim() ?? '',
        markWinRatio:
            runDays > 0 ? _numFrom(m, 'mrk_win_cnt') / runDays : 0,
      ));
    }
    entries.sort((a, b) => a.lineNo.compareTo(b.lineNo));
    return entries;
  }

  double _numFrom(Map<String, dynamic> m, String key) =>
      double.tryParse(m[key]?.toString().trim() ?? '') ?? 0;

  /// `12"00` 형식의 기록을 초 단위로 변환한다. 값이 없으면 0.
  double _parseSeconds(String? raw) {
    final matched = RegExp(r'(\d+)"(\d+)').firstMatch(raw ?? '');
    if (matched == null) return 0;
    return double.tryParse('${matched.group(1)}.${matched.group(2)}') ?? 0;
  }

  /// 최근 성적을 최신순으로 (등급값, 착순)으로 반환한다.
  ///
  /// 값은 `우수 3-5`(등급 · 경주번호-착순) 형태이고, 결장은 `결 장`으로 온다.
  /// 공공 API는 직전 3회차만 주지만, 크롤링 자료에는 이번 회차의 지난 일차
  /// (`cur_day*`)도 있어 더 최신 성적부터 반영한다.
  List<({double raceClass, int finish})> _recentOutings(
    Map<String, dynamic> m,
  ) {
    const classValues = {'특선': 3.0, '우수': 2.0, '선발': 1.0};
    final pattern = RegExp(r'(특선|우수|선발)?\s*(\d+)\s*-\s*(\d+)');
    final outings = <({double raceClass, int finish})>[];

    final keys = [
      'cur_day2_rank',
      'cur_day1_rank',
      for (final tms in [1, 2, 3])
        for (final day in [3, 2, 1]) 'bf${tms}_day${day}_rank',
    ];

    for (final key in keys) {
      final matched = pattern.firstMatch(m[key]?.toString() ?? '');
      if (matched == null) continue;
      final finish = int.tryParse(matched.group(3) ?? '') ?? 0;
      if (finish < 1 || finish > 9) continue;
      outings.add((
        raceClass: classValues[matched.group(1)] ?? 2.0,
        finish: finish,
      ));
    }
    return outings;
  }

  /// 각질별 승수 중 가장 많은 쪽을 주 전법으로 본다.
  String _extractTactic(Map<String, dynamic> m) {
    final counts = {
      '선행': _numFrom(m, 'pre_win_cnt'),
      '젖히기': _numFrom(m, 'brk_win_cnt'),
      '마크': _numFrom(m, 'mrk_win_cnt'),
      '추입': _numFrom(m, 'pas_win_cnt'),
    };
    final best = counts.entries.reduce((a, b) => b.value > a.value ? b : a);
    if (best.value <= 0) return '';
    return best.key;
  }

  RaceResult _parseRaceResult(Map<String, dynamic> m) {
    // 동착이면 한 필드에 두 선수가 들어오므로(예: "④문인재①송정욱")
    // rank1~rank3을 펼친 뒤 앞에서부터 1·2·3착으로 배정한다.
    final placings = [
      ..._parsePlacings(m['rank1']?.toString()),
      ..._parsePlacings(m['rank2']?.toString()),
      ..._parsePlacings(m['rank3']?.toString()),
    ];
    ({int no, String name}) at(int i) =>
        i < placings.length ? placings[i] : (no: 0, name: '');

    return RaceResult(
      raceNo: _intFrom(m, ['race_no', 'rcNo', 'RACE_NO']) ?? 0,
      first: at(0).name,
      firstNo: at(0).no,
      second: at(1).name,
      secondNo: at(1).no,
      third: at(2).name,
      thirdNo: at(2).no,
      round: _intFrom(m, ['week_tcnt']) ?? 0,
      dayOrd: _intFrom(m, ['day_tcnt']) ?? 0,
      payoff: Odds(
        win: _parseSingleOdds(m['pool1_val']?.toString()),
        place: _parseSingleOdds(m['pool2_val']?.toString()),
        exacta: _parseComboOdds(m['pool4_val']?.toString()),
        quinella: _parseComboOdds(m['pool5_val']?.toString()),
        trio: _parseComboOdds(m['pool6_val']?.toString()),
        trifecta: _parseComboOdds(m['pool7_val']?.toString()),
        exactaTrio: _parseComboOdds(m['pool8_val']?.toString()),
      ),
    );
  }

  /// 착순 필드를 (선수번호, 이름) 목록으로 변환.
  /// 선수번호는 원문자(①~⑳)로 이름 앞에 붙어 있다.
  List<({int no, String name})> _parsePlacings(String? raw) {
    if (raw == null || raw.trim().isEmpty) return [];

    final placings = <({int no, String name})>[];
    var currentNo = 0;
    final name = StringBuffer();

    void flush() {
      final trimmed = name.toString().trim();
      if (currentNo > 0 || trimmed.isNotEmpty) {
        placings.add((no: currentNo, name: trimmed));
      }
      currentNo = 0;
      name.clear();
    }

    for (final rune in raw.runes) {
      final no = _circledNumber(rune);
      if (no == null) {
        name.writeCharCode(rune);
        continue;
      }
      if (currentNo > 0 || name.isNotEmpty) flush();
      currentNo = no;
    }
    flush();

    return placings;
  }

  /// 원문자 숫자(①~⑳)를 정수로 변환. 일반 숫자도 허용한다.
  int? _circledNumber(int rune) {
    if (rune >= 0x2460 && rune <= 0x2473) return rune - 0x2460 + 1;
    if (rune >= 0x31 && rune <= 0x39) return rune - 0x30;
    return null;
  }

  static final _oddsPattern = RegExp(r'\(\s*([0-9]+(?:\s*-\s*[0-9]+)*)\s*\)\s*([0-9.]+)');

  /// "(4)2.1 (1)1.9" → {4: 2.1, 1: 1.9}
  Map<int, double> _parseSingleOdds(String? raw) {
    final result = <int, double>{};
    if (raw == null) return result;
    for (final match in _oddsPattern.allMatches(raw)) {
      final no = int.tryParse(match.group(1)!.replaceAll(' ', ''));
      final value = double.tryParse(match.group(2)!);
      if (no != null && value != null) result[no] = value;
    }
    return result;
  }

  /// "(1-4)47.5(4-1)149.6" → {"1-4": 47.5, "4-1": 149.6}
  Map<String, double> _parseComboOdds(String? raw) {
    final result = <String, double>{};
    if (raw == null) return result;
    for (final match in _oddsPattern.allMatches(raw)) {
      final combo = match.group(1)!.replaceAll(' ', '');
      final value = double.tryParse(match.group(2)!);
      if (combo.contains('-') && value != null) result[combo] = value;
    }
    return result;
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

}

class _RaceAggregate {
  int count = 0;
  int? distance;
  String? departureTime;
  int? roundCount;
  String? grade;
}
