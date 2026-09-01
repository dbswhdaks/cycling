import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

/// KCYCLE 공식 사이트에서 경주별 상세 착순표를 수집한다.
///
/// 공공데이터 순위 API는 선수명과 착순만 제공해 배번·주행시간·착차를 알 수 없다.
/// KCYCLE 통합경주결과 상세는 이 항목을 모두 제공하므로 보강용으로 사용한다.
///
/// 상세 URL 형식:
/// `/race/result/general/{연도}/{회차}/{일차}/{경기장코드}/{경주번호}`
class KcycleResultService {
  KcycleResultService();

  static const String _baseUrl = 'https://www.kcycle.or.kr/race/result/general';

  /// 앱 경기장 코드 → KCYCLE 경기장 코드.
  ///
  /// KCYCLE은 부산에 003이 아니라 004를 쓴다. 003으로 요청하면 오류 페이지가
  /// 돌아와 상세 착순을 한 건도 얻지 못한다.
  @visibleForTesting
  static const Map<int, String> meetCodes = {1: '001', 2: '002', 3: '004'};

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 12),
      responseType: ResponseType.plain,
      headers: {
        'Accept': 'text/html,application/xhtml+xml',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) CyclingApp/1.0',
      },
    ),
  );

  final Map<String, List<Map<String, dynamic>>> _cache = {};

  /// 경주별 상세 착순을 반환. 실패하면 빈 목록.
  Future<List<Map<String, dynamic>>> fetchRankDetails({
    required int year,
    required int round,
    required int dayOrd,
    required int meet,
    required int raceNo,
  }) async {
    if (round <= 0 || dayOrd <= 0) return [];

    final meetCd = meetCodes[meet];
    if (meetCd == null) return [];

    final raceNoStr = raceNo.toString().padLeft(2, '0');
    final key = '$year/$round/$dayOrd/$meetCd/$raceNoStr';
    if (_cache.containsKey(key)) return _cache[key]!;

    try {
      final res = await _dio.get('$_baseUrl/$key');
      if (res.statusCode != 200) return [];

      final details = parseRankTable(res.data.toString());
      _cache[key] = details;

      if (kDebugMode) {
        debugPrint('[KCYCLE] $key: ${details.length}명 상세 수집');
      }
      return details;
    } catch (e) {
      if (kDebugMode) debugPrint('[KCYCLE] $key 실패: $e');
      return [];
    }
  }

  void clearCache() => _cache.clear();

  /// 착차 표를 파싱한다.
  ///
  /// 행 구조: `<th>` 배번 + 선수명, 이어지는 `<td>`가
  /// 순위 · 착차 · 주행시간 · 승부수 · 실격 · 경고 · 주의 · 기권 · 골인 ·
  /// 200M 기록 · 200M 평균시속 순으로 나열된다.
  @visibleForTesting
  List<Map<String, dynamic>> parseRankTable(String htmlString) {
    final document = html_parser.parse(htmlString);

    final table = document.querySelectorAll('table').where((t) {
      final head = t.querySelector('thead')?.text ?? t.text;
      return head.contains('주행시간') && head.contains('착차');
    }).firstOrNull;
    if (table == null) return [];

    final details = <Map<String, dynamic>>[];
    for (final row in table.querySelectorAll('tr')) {
      final header = row.querySelector('th');
      final link = header?.querySelector('a');
      if (header == null || link == null) continue;

      final cells = row.querySelectorAll('td');
      if (cells.length < 3) continue;

      String cell(int i) => i < cells.length ? _clean(cells[i].text) : '';

      final backNo = int.tryParse(_clean(header.querySelector('.sign')?.text ?? ''));
      final rank = int.tryParse(cell(0));
      if (backNo == null || rank == null) continue;

      details.add({
        'rank': rank,
        'back_no': backNo,
        'racer_nm': _clean(link.text),
        'racer_no': _racerNoFrom(link),
        'arrival_diff': cell(1),
        'race_time': cell(2),
        'tactic': _blankIfDash(cell(3)),
        'time_200m': _clean(cell(9)),
        'avg_speed': _clean(cell(10)),
        'racer_grd_cd': '',
      });
    }

    details.sort((a, b) => (a['rank'] as int).compareTo(b['rank'] as int));
    return details;
  }

  /// `fnRacer.popup("20160013", "2026")` → `20160013`
  String _racerNoFrom(dom.Element link) {
    final onclick = link.attributes['onclick'] ?? '';
    return RegExp(r'\d{6,}').firstMatch(onclick)?.group(0) ?? '';
  }

  String _clean(String raw) =>
      raw.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  String _blankIfDash(String value) => value == '-' ? '' : value;
}
