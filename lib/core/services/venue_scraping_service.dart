import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/parser.dart' as html_parser;

/// 경륜 공식 사이트 크롤링을 통해 창원·부산 출주표를 수집하는 서비스.
///
/// - 부산: spo1.or.kr  (확정출주표 인쇄 페이지)
/// - 창원/부산 통합: lepopark.or.kr  (출주표 페이지, 모든 경기장 데이터 포함)
///
/// 반환 데이터는 공공 API와 동일한 키 구조를 사용하므로
/// [CyclingApiService]의 파싱 로직과 호환된다.
class VenueScrapingService {
  VenueScrapingService();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 8),
    receiveTimeout: const Duration(seconds: 10),
    headers: {
      'Accept': 'text/html,application/xhtml+xml',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) CyclingApp/1.0',
      'Accept-Encoding': 'gzip, deflate',
    },
  ));

  /// 날짜별 스크래핑 캐시  key = date(yyyyMMdd), value = {meet: items}
  final Map<String, Map<int, List<Map<String, dynamic>>>> _cache = {};

  /// 지정 날짜의 창원(2)·부산(3) 출주표를 스크래핑하여 반환.
  /// API 형식과 동일한 Map 리스트로 반환한다.
  Future<Map<int, List<Map<String, dynamic>>>> scrapeRaceData(String date) async {
    if (_cache.containsKey(date)) return _cache[date]!;

    final result = <int, List<Map<String, dynamic>>>{2: [], 3: []};

    // 1차: lepopark.or.kr (창원+부산 통합)
    try {
      final lepoparkData = await _scrapeLepoparkPage(date);
      if (lepoparkData[2]!.isNotEmpty || lepoparkData[3]!.isNotEmpty) {
        _cache[date] = lepoparkData;
        if (kDebugMode) {
          debugPrint('[Scrape] lepopark 성공: '
              '창원 ${lepoparkData[2]!.length}건, 부산 ${lepoparkData[3]!.length}건');
        }
        return lepoparkData;
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Scrape] lepopark 실패: $e');
    }

    // 2차: spo1.or.kr (부산만)
    try {
      result[3] = await _scrapeSpo1Races(date);
      if (kDebugMode) {
        debugPrint('[Scrape] spo1 부산: ${result[3]!.length}건');
      }
    } catch (e) {
      if (kDebugMode) debugPrint('[Scrape] spo1 실패: $e');
    }

    _cache[date] = result;
    return result;
  }

  void clearCache({String? date}) {
    if (date != null) {
      _cache.remove(date);
    } else {
      _cache.clear();
    }
  }

  // ═══════════════════════════ lepopark.or.kr (창원레포츠파크) ═══════════════════════════

  Future<Map<int, List<Map<String, dynamic>>>> _scrapeLepoparkPage(String date) async {
    final result = <int, List<Map<String, dynamic>>>{2: [], 3: []};

    // 확정·미확정 출주표 동시 요청 (먼저 성공한 것 사용)
    final futures = ['entrant', 'entrant-unfix'].map((pathType) async {
      final url = 'https://www.lepopark.or.kr/race/$pathType/$date';
      try {
        final response = await _dio.get(url);
        if (response.statusCode != 200) return null;
        final html = response.data.toString();
        if (html.length < 500) return null;
        return _parseLepoparkHtml(html, date);
      } catch (e) {
        if (kDebugMode) debugPrint('[Scrape] lepopark $pathType: $e');
        return null;
      }
    });

    final results = await Future.wait(futures);
    for (final parsed in results) {
      if (parsed != null && (parsed[2]!.isNotEmpty || parsed[3]!.isNotEmpty)) {
        return parsed;
      }
    }
    return result;
  }

  /// lepopark HTML을 파싱하여 경기장별 출주표 데이터 추출.
  ///
  /// 페이지 구조:
  /// - 각 경주 섹션이 <div> 또는 <section>으로 구분됨
  /// - 섹션 헤더: "창원 06 경주 [우수] 출발 10:35"
  /// - 선수 링크: <a href="/racer/ID">선수명</a>
  /// - 하단 요약 테이블: 기어배수, 200m기록, 훈련지, 등급, 평균득점 등
  Map<int, List<Map<String, dynamic>>> _parseLepoparkHtml(String htmlString, String date) {
    final result = <int, List<Map<String, dynamic>>>{2: [], 3: []};
    final dateFormatted = _toDateDot(date);

    final doc = html_parser.parse(htmlString);
    final body = doc.body;
    if (body == null) return result;

    // 경주 섹션 헤더를 찾기 위해 텍스트에서 패턴 매칭
    // "창원 NN 경주 [등급] 출발 HH:MM" 또는 "부산 NN 경주 [등급] 출발 HH:MM"
    final raceHeaderRegex = RegExp(
      r'(창원|부산|광명)\s*(\d+)\s*경주\s*\[([^\]]*)\]\s*출발\s*(\d+:\d+)',
    );

    // 모든 <a href="/racer/..."> 링크에서 선수명 추출 (순서 보존)
    final racerLinkRegex = RegExp(r'href="[^"]*?/racer/(\d+)"[^>]*>([^<]+)</a>');

    // 경주 거리·주회수 패턴: "5주회 1691m" 또는 "2025m"
    final distanceRegex = RegExp(r'(\d+)주회\s*(\d+)m');

    // 전체 HTML 텍스트에서 경주 섹션을 분리
    final allText = body.text;
    final headerMatches = raceHeaderRegex.allMatches(allText).toList();
    final linkMatches = racerLinkRegex.allMatches(htmlString).toList();

    if (headerMatches.isEmpty) return result;

    // 각 경주 헤더의 HTML 내 위치 추적
    final raceHeadersInHtml = raceHeaderRegex.allMatches(htmlString).toList();

    for (int i = 0; i < raceHeadersInHtml.length; i++) {
      final hdr = raceHeadersInHtml[i];
      final venue = hdr.group(1)!;
      final raceNo = int.tryParse(hdr.group(2)!) ?? 0;
      final grade = hdr.group(3) ?? '';
      final deptTime = hdr.group(4) ?? '';

      if (venue == '광명') continue;

      final meetCode = venue == '창원' ? 2 : 3;
      final hdrEnd = hdr.end;
      final nextHdrStart = (i + 1 < raceHeadersInHtml.length)
          ? raceHeadersInHtml[i + 1].start
          : htmlString.length;

      // 이 섹션 범위에서 거리·주회수 파싱
      final sectionHtml = htmlString.substring(hdrEnd, nextHdrStart);
      final distMatch = distanceRegex.firstMatch(sectionHtml);
      int? roundCount = distMatch != null ? int.tryParse(distMatch.group(1)!) : null;
      int? distance = distMatch != null ? int.tryParse(distMatch.group(2)!) : null;

      // HTML에 주회·거리 정보가 없으면 등급 기준으로 추정
      if (distance == null || roundCount == null) {
        final estimated = _estimateRaceDistance(venue, grade);
        roundCount ??= estimated['rounds'];
        distance ??= estimated['distance'];
      }

      // 이 섹션 범위에서 선수 링크 추출
      final sectionLinks = linkMatches
          .where((m) => m.start >= hdrEnd && m.start < nextHdrStart)
          .toList();

      // 등급·평균득점 테이블 파싱
      final gradeScores = _extractLepoparkTableData(sectionHtml, venue);

      // 선수별 데이터 생성
      // 선수 링크가 중복 출현할 수 있으므로 첫 번째 출현만 사용
      final seenNames = <String>{};
      int backNo = 0;

      for (final link in sectionLinks) {
        final name = link.group(2)!.trim();
        if (seenNames.contains(name)) continue;
        seenNames.add(name);
        backNo++;

        final scoreData = (backNo - 1 < gradeScores.length)
            ? gradeScores[backNo - 1]
            : <String, String>{};

        result[meetCode]!.add({
          'race_ymd': dateFormatted,
          'race_no': raceNo.toString(),
          'back_no': backNo.toString(),
          'racer_nm': name,
          'racer_grd_cd': scoreData['grade'] ?? grade,
          'racer_grd_cur_cd': scoreData['grade'] ?? grade,
          'race_len': (distance ?? 0).toString(),
          'dptre_tm': deptTime,
          'round_cnt': (roundCount ?? 0).toString(),
          'tot_tms_avg_scr': scoreData['avgScore'] ?? '0',
          'win_tot_tcnt': '0',
          'brk_win_cnt': scoreData['brkWin'] ?? '0',
          'mrk_win_cnt': scoreData['mrkWin'] ?? '0',
          'pre_win_cnt': '0',
          'data_source': 'scrape_lepopark',
        });
      }
    }

    return result;
  }

  /// lepopark 섹션 내 요약 테이블에서 등급·평균득점 추출.
  ///
  /// 테이블 행 구조 (열):
  ///   기어배수 | 200m기록 | 훈련지 | ... | 현재등급 | 이전등급 | 로컬평균 | 종합평균 | 순위
  List<Map<String, String>> _extractLepoparkTableData(String sectionHtml, String venue) {
    final results = <Map<String, String>>[];

    final miniDoc = html_parser.parseFragment(sectionHtml);
    final tables = miniDoc.querySelectorAll('table');

    for (final table in tables) {
      final rows = table.querySelectorAll('tr');
      for (final row in rows) {
        final cells = row.querySelectorAll('td');
        if (cells.length < 6) continue;

        // 등급 패턴 (S1~S3, A1~A3, B1~B3 등)
        final gradeRegex = RegExp(r'^[SA-Z]\d$');
        String? currentGrade;
        String? avgScore;

        for (int c = 0; c < cells.length; c++) {
          final text = cells[c].text.trim();
          if (gradeRegex.hasMatch(text) && currentGrade == null) {
            currentGrade = text;
          }
          // 평균득점은 소수점을 가진 숫자 (80~100 범위)
          final numVal = double.tryParse(text);
          if (numVal != null && numVal >= 60 && numVal <= 120 && text.contains('.')) {
            avgScore ??= text;
          }
        }

        if (currentGrade != null || avgScore != null) {
          results.add({
            'grade': currentGrade ?? '',
            'avgScore': avgScore ?? '0',
          });
        }
      }
    }

    return results;
  }

  // ═══════════════════════════ spo1.or.kr (부산경륜) ═══════════════════════════

  /// 부산경륜 확정출주표를 전 경주 병렬 스크래핑.
  Future<List<Map<String, dynamic>>> _scrapeSpo1Races(String date) async {
    final dateFormatted = _toDateDot(date);

    // 1~8경주를 동시 요청 (일반적으로 6경주 이내)
    final futures = List.generate(8, (i) {
      final raceNo = i + 1;
      final raceNoStr = raceNo.toString().padLeft(2, '0');
      final url = 'https://www.spo1.or.kr/race/racePrint.do'
          '?SELECTDATE=$date&CYCLECD=003&MUTUAL=0&RACENO=$raceNoStr';

      return _dio.get(url).then((response) {
        if (response.statusCode != 200) return <Map<String, dynamic>>[];
        final html = response.data.toString();
        if (!html.contains('racerPopup') && !html.contains('선수명')) {
          return <Map<String, dynamic>>[];
        }
        return _parseSpo1Html(html, raceNo, dateFormatted);
      }).catchError((_) => <Map<String, dynamic>>[]);
    });

    final results = await Future.wait(futures);
    final items = <Map<String, dynamic>>[];
    for (final raceItems in results) {
      items.addAll(raceItems);
    }
    return items;
  }

  /// spo1 확정출주표 인쇄 페이지 HTML 파싱.
  ///
  /// 페이지 구조:
  /// - 경주 헤더: "부산 01경주 선발 5주회 1691m 출발 12:55"
  /// - 선수 테이블: <a href="...racerPopup.do?RACEID=...">선수명</a> 와 통계 열
  List<Map<String, dynamic>> _parseSpo1Html(String htmlString, int raceNo, String dateFormatted) {
    final items = <Map<String, dynamic>>[];
    final doc = html_parser.parse(htmlString);

    // 경주 정보 파싱
    final bodyText = doc.body?.text ?? '';
    final raceInfoRegex = RegExp(
      r'(선발|우수|특선|일반)\s*(\d+)주회\s*(\d+)m\s*출발\s*(\d+:\d+)',
    );
    final raceInfoMatch = raceInfoRegex.firstMatch(bodyText);
    final grade = raceInfoMatch?.group(1) ?? '';
    int? roundCount = raceInfoMatch != null ? int.tryParse(raceInfoMatch.group(2)!) : null;
    int? distance = raceInfoMatch != null ? int.tryParse(raceInfoMatch.group(3)!) : null;
    final deptTime = raceInfoMatch?.group(4);

    if (distance == null || roundCount == null) {
      final estimated = _estimateRaceDistance('부산', grade);
      roundCount ??= estimated['rounds'];
      distance ??= estimated['distance'];
    }

    // racerPopup 링크가 있는 테이블 찾기
    final tables = doc.querySelectorAll('table');
    for (final table in tables) {
      final racerLinks = table.querySelectorAll('a[href*="racerPopup"]');
      if (racerLinks.isEmpty) continue;

      // 이 테이블에서 선수 데이터 행 추출
      final rows = table.querySelectorAll('tr');
      int backNo = 0;
      final seenNames = <String>{};

      for (final row in rows) {
        final link = row.querySelector('a[href*="racerPopup"]');
        if (link == null) continue;

        final name = link.text.trim();
        if (name.isEmpty || seenNames.contains(name)) continue;
        seenNames.add(name);
        backNo++;

        final cells = row.querySelectorAll('td');
        final cellTexts = cells.map((c) => c.text.trim()).toList();

        // 셀에서 데이터 추출 (SPO1 확정출주표 열 순서 기준)
        final parsed = _extractSpo1CellData(cellTexts);

        items.add({
          'race_ymd': dateFormatted,
          'race_no': raceNo.toString(),
          'back_no': backNo.toString(),
          'racer_nm': name,
          'racer_grd_cd': parsed['grade'] ?? '',
          'racer_grd_cur_cd': parsed['grade'] ?? '',
          'race_len': (distance ?? 0).toString(),
          'dptre_tm': deptTime ?? '',
          'round_cnt': (roundCount ?? 0).toString(),
          'tot_tms_avg_scr': parsed['avgScore'] ?? '0',
          'win_tot_tcnt': '0',
          'brk_win_cnt': parsed['brkWin'] ?? '0',
          'mrk_win_cnt': parsed['mrkWin'] ?? '0',
          'pre_win_cnt': '0',
          'data_source': 'scrape_spo1',
        });
      }

      if (items.isNotEmpty) break;
    }

    return items;
  }

  /// SPO1 테이블 셀에서 등급·평균득점·전법 추출.
  ///
  /// 열 순서 (추정):
  ///   선수명 | 기수 | 나이 | 기어배수 | 200M기록 | 훈련지 |
  ///   승률 | 연대율 | 삼연대율 | 입상/출전 |
  ///   선행 | 젖히기 | 추입 | 마크 |
  ///   현재등급 | 이전등급 | 부산평균 | 종합평균 | 순위
  Map<String, String> _extractSpo1CellData(List<String> cells) {
    final result = <String, String>{};
    final gradeRegex = RegExp(r'^[SA-Z]\d$');

    // 등급 찾기: 단일 대문자+숫자 패턴 (S1, A2, B3 등)
    for (int i = cells.length - 1; i >= 0; i--) {
      final stripped = _stripParentheses(cells[i]);
      if (gradeRegex.hasMatch(stripped)) {
        result['grade'] = stripped;
        break;
      }
    }

    // 평균득점 찾기: 80~100 범위 소수점 숫자
    for (int i = cells.length - 1; i >= 0; i--) {
      final val = double.tryParse(cells[i]);
      if (val != null && val >= 60 && val <= 120 && cells[i].contains('.')) {
        result['avgScore'] = cells[i];
        break;
      }
    }

    // 입상전법 (선행·마크) 추출
    // 괄호 제거 후 숫자만 추출하여 선행/마크 우선 전법 결정
    for (int i = 0; i < cells.length; i++) {
      final stripped = _stripParentheses(cells[i]);
      final val = int.tryParse(stripped);
      if (val != null && val >= 0) {
        // 선행 열은 보통 10번째 전후
        if (i >= 10 && i <= 13 && cells.length > 14) {
          if (i == 10) result['brkWin'] = val.toString();
          if (i == 13) result['mrkWin'] = val.toString();
        }
      }
    }

    return result;
  }

  // ═══════════════════════════ 경기 거리 추정 ═══════════════════════════

  /// 경기장·등급으로 주회수와 거리를 추정.
  ///
  /// SPO1 공식 데이터 기반 (출발선 오프셋 포함):
  ///   - 창원/부산 (333m 트랙): 선발/우수 5주회 = 1691m, 특선 6주회 = 2024m
  ///   - 광명 (250m 스피돔):   API에서 제공 (기본 8주회 = 2025m)
  static Map<String, int> _estimateRaceDistance(String venue, String grade) {
    const knownDistances = {
      '창원': {'선발': 1691, '우수': 1691, '특선': 2024, '선결': 2024, '우결': 2024, '일반': 1691},
      '부산': {'선발': 1691, '우수': 1691, '특선': 2024, '선결': 2024, '우결': 2024, '일반': 1691},
      '광명': {'선발': 1275, '우수': 2025, '특선': 2025, '선결': 1275, '우결': 2025, '일반': 1275},
    };
    const knownRounds = {
      '창원': {'선발': 5, '우수': 5, '특선': 6, '선결': 6, '우결': 6, '일반': 5},
      '부산': {'선발': 5, '우수': 5, '특선': 6, '선결': 6, '우결': 6, '일반': 5},
      '광명': {'선발': 5, '우수': 8, '특선': 8, '선결': 5, '우결': 8, '일반': 5},
    };

    final dist = knownDistances[venue]?[grade] ?? knownDistances[venue]?['선발'] ?? 1691;
    final rounds = knownRounds[venue]?[grade] ?? knownRounds[venue]?['선발'] ?? 5;

    return {'rounds': rounds, 'distance': dist};
  }

  // ═══════════════════════════ 유틸리티 ═══════════════════════════

  /// "20260315" → "2026.03.15"
  String _toDateDot(String yyyymmdd) {
    if (yyyymmdd.length != 8) return yyyymmdd;
    return '${yyyymmdd.substring(0, 4)}.${yyyymmdd.substring(4, 6)}.${yyyymmdd.substring(6, 8)}';
  }

  /// "8(8)" → "8"
  String _stripParentheses(String s) {
    final idx = s.indexOf('(');
    return idx >= 0 ? s.substring(0, idx).trim() : s.trim();
  }
}
