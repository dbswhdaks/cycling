import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import '../../models/odds.dart';

/// 창원레포츠파크에서 창원·부산 경주결과(착순 + 확정배당)를 수집한다.
///
/// 공공데이터 API와 KCYCLE은 2026년 6월 이후 부산 경주를 전혀 싣지 않고,
/// 창원도 일부 경주를 빠뜨린다. 반면 이 사이트는 세 경기장 결과를 모두
/// 확정 즉시 올리므로 창원·부산 결과의 유일한 출처다.
class LepoparkResultService {
  LepoparkResultService();

  static const String _baseUrl = 'https://www.lepopark.or.kr/race/result';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 15),
      responseType: ResponseType.plain,
      headers: {
        'Accept': 'text/html,application/xhtml+xml',
        'User-Agent':
            'Mozilla/5.0 (Windows NT 10.0; Win64; x64) CyclingApp/1.0',
      },
    ),
  );

  /// 날짜별 파싱 결과  key = yyyyMMdd
  final Map<String, Map<int, Map<int, LepoparkRaceResult>>> _cache = {};

  /// 진행 중인 날짜별 요청 (같은 날짜의 중복 호출을 합친다)
  final Map<String, Future<Map<int, Map<int, LepoparkRaceResult>>>> _inFlight =
      {};

  /// 지정 경주의 결과를 반환. 없으면 null.
  Future<LepoparkRaceResult?> fetchRace({
    required int meet,
    required String date,
    required int raceNo,
  }) async {
    final day = await fetchDay(date);
    return day[meet]?[raceNo];
  }

  /// 하루치 전 경기장 결과를 반환한다. `{경기장코드: {경주번호: 결과}}`
  Future<Map<int, Map<int, LepoparkRaceResult>>> fetchDay(String date) async {
    final cached = _cache[date];
    if (cached != null) return cached;

    try {
      return await (_inFlight[date] ??= _load(date));
    } finally {
      _inFlight.remove(date);
    }
  }

  Future<Map<int, Map<int, LepoparkRaceResult>>> _load(String date) async {
    try {
      final res = await _dio.get('$_baseUrl/$date');
      if (res.statusCode != 200) return const {};

      final parsed = parseResultPage(res.data.toString());
      _cache[date] = parsed;

      if (kDebugMode) {
        final summary = parsed.entries
            .map((e) => '${e.key}=${e.value.length}')
            .join(' ');
        debugPrint('[Lepopark] 결과 $date: $summary');
      }
      return parsed;
    } catch (e) {
      if (kDebugMode) debugPrint('[Lepopark] 결과 $date 실패: $e');
      return const {};
    }
  }

  void clearCache() => _cache.clear();

  // ─────────────────────────── 파싱 ───────────────────────────

  static final RegExp _headerPattern =
      RegExp(r'^(창원|부산|광명)\s*(\d+)\s*경주');

  static const Map<String, int> _meetOf = {'광명': 1, '창원': 2, '부산': 3};

  /// 결과 페이지 전체를 경기장·경주번호별로 나눠 파싱한다.
  ///
  /// 한 경주 구획은 `<h3>부산01 경주 [확정]</h3>` 다음에 오는 표들로 이루어진다.
  /// 표가 구획 안에 감싸여 있지 않아, 문서 순서대로 훑으면서 직전 제목에
  /// 표를 붙이는 방식으로 구획을 만든다.
  @visibleForTesting
  Map<int, Map<int, LepoparkRaceResult>> parseResultPage(String htmlString) {
    final document = html_parser.parse(htmlString);
    final result = <int, Map<int, LepoparkRaceResult>>{};

    _RaceHeader? current;
    final tables = <dom.Element>[];

    void flush() {
      final header = current;
      if (header == null) return;

      final race = _buildRace(header, tables);
      if (race != null) {
        (result[header.meet] ??= {})[header.raceNo] = race;
      }
      tables.clear();
    }

    for (final element in _inDocumentOrder(document.body)) {
      if (element.localName == 'h3') {
        final match = _headerPattern.firstMatch(_clean(element.text));
        if (match == null) continue;

        flush();
        final meet = _meetOf[match.group(1)!];
        final raceNo = int.tryParse(match.group(2)!);
        current = (meet == null || raceNo == null)
            ? null
            : _RaceHeader(meet: meet, raceNo: raceNo);
      } else if (element.localName == 'table' && current != null) {
        tables.add(element);
      }
    }
    flush();

    return result;
  }

  /// 문서에 나타난 순서대로 모든 요소를 훑는다.
  Iterable<dom.Element> _inDocumentOrder(dom.Element? root) sync* {
    if (root == null) return;
    for (final child in root.children) {
      yield child;
      yield* _inDocumentOrder(child);
    }
  }

  LepoparkRaceResult? _buildRace(_RaceHeader header, List<dom.Element> tables) {
    final ranks = _parseRankTable(tables);
    if (ranks.isEmpty) return null;

    return LepoparkRaceResult(
      meet: header.meet,
      raceNo: header.raceNo,
      grade: _parseGrade(tables),
      ranks: ranks,
      payoff: _parsePayoffTable(tables),
    );
  }

  /// 등급·발주시각 표에서 등급만 취한다.
  String _parseGrade(List<dom.Element> tables) {
    for (final table in tables) {
      final headers =
          table.querySelectorAll('th').map((e) => _clean(e.text)).toList();
      if (!headers.contains('등급') || !headers.contains('시간')) continue;

      final cells = table.querySelectorAll('tbody td');
      if (cells.isNotEmpty) return _clean(cells.first.text);
    }
    return '';
  }

  /// 착순표를 KCYCLE 상세와 같은 형식으로 파싱한다.
  ///
  /// 행 구조: 첫 칸에 배번(`span`)과 선수명(`a`)이 함께 들어가고, 이어지는
  /// `td`가 순위 · 착차 · 주행시간 · 승부수 · 실격 · 경고 · 주의 · 기권 ·
  /// 골인 · 200M 기록 · 200M 평균시속 순으로 나열된다.
  List<Map<String, dynamic>> _parseRankTable(List<dom.Element> tables) {
    final table = tables.where((t) {
      final head = t.querySelector('thead')?.text ?? t.text;
      return head.contains('주행시간') && head.contains('착차');
    }).firstOrNull;
    if (table == null) return const [];

    final details = <Map<String, dynamic>>[];
    for (final row in table.querySelectorAll('tr')) {
      final cells = row.querySelectorAll('td');
      if (cells.length < 4) continue;

      final nameCell = cells.first;
      final link = nameCell.querySelector('a');
      if (link == null) continue;

      String cell(int i) =>
          i + 1 < cells.length ? _clean(cells[i + 1].text) : '';

      final backNo = int.tryParse(_clean(nameCell.querySelector('span')?.text ?? ''));
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
        'time_200m': cell(9),
        'avg_speed': cell(10),
        'racer_grd_cd': '',
      });
    }

    details.sort((a, b) => (a['rank'] as int).compareTo(b['rank'] as int));
    return details;
  }

  /// 확정배당률 표를 승식별 배당으로 바꾼다.
  ///
  /// 머리글이 승식 이름이고, 아래 칸마다 `6(2.4)`·`6-1(4.2)` 형태의 `div`가
  /// 하나 이상 들어간다. 동착이면 한 칸에 여러 개가 들어온다.
  Odds _parsePayoffTable(List<dom.Element> tables) {
    final table = tables.where((t) {
      final head = t.querySelector('thead')?.text ?? '';
      return head.contains('승식') && head.contains('단승');
    }).firstOrNull;
    if (table == null) return const Odds();

    final headers =
        table.querySelectorAll('thead th').map((e) => _clean(e.text)).toList();
    final row = table.querySelector('tbody tr');
    if (row == null) return const Odds();

    final cells = row.querySelectorAll('td');
    final win = <int, double>{};
    final place = <int, double>{};
    final exacta = <String, double>{};
    final quinella = <String, double>{};
    final trio = <String, double>{};
    final exactaTrio = <String, double>{};
    final trifecta = <String, double>{};

    for (var i = 0; i < cells.length && i < headers.length; i++) {
      final label = headers[i];
      for (final entry in _payoffEntries(cells[i])) {
        switch (label) {
          case '단승':
            final no = int.tryParse(entry.combination);
            if (no != null) win[no] = entry.value;
          case '연승':
            final no = int.tryParse(entry.combination);
            if (no != null) place[no] = entry.value;
          case '쌍승':
            exacta[entry.combination] = entry.value;
          case '복승':
            quinella[entry.combination] = entry.value;
          case '삼복승':
            trio[entry.combination] = entry.value;
          case '쌍복승':
            exactaTrio[entry.combination] = entry.value;
          case '삼쌍승':
            trifecta[entry.combination] = entry.value;
        }
      }
    }

    return Odds(
      win: win,
      place: place,
      exacta: exacta,
      quinella: quinella,
      trio: trio,
      exactaTrio: exactaTrio,
      trifecta: trifecta,
    );
  }

  static final RegExp _payoffPattern =
      RegExp(r'([\d\-]+)\s*\(\s*([\d.,]+)\s*\)');

  /// `6(2.4)`·`6-1(4.2)`를 조합과 배당으로 분해한다.
  Iterable<({String combination, double value})> _payoffEntries(
    dom.Element cell,
  ) sync* {
    final divs = cell.querySelectorAll('div');
    final texts = divs.isEmpty
        ? [_clean(cell.text)]
        : divs.map((d) => _clean(d.text)).toList();

    for (final text in texts) {
      final match = _payoffPattern.firstMatch(text);
      if (match == null) continue;

      final value = double.tryParse(match.group(2)!.replaceAll(',', ''));
      if (value == null) continue;
      yield (combination: match.group(1)!, value: value);
    }
  }

  /// `<a href="/racer/20010011">` → `20010011`
  String _racerNoFrom(dom.Element link) =>
      RegExp(r'\d{6,}').firstMatch(link.attributes['href'] ?? '')?.group(0) ??
      '';

  String _clean(String raw) =>
      raw.replaceAll('\u00a0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();

  String _blankIfDash(String value) => value == '-' ? '' : value;
}

class _RaceHeader {
  const _RaceHeader({required this.meet, required this.raceNo});

  final int meet;
  final int raceNo;
}

/// 창원레포츠파크에서 읽어온 한 경주의 확정 결과.
class LepoparkRaceResult {
  const LepoparkRaceResult({
    required this.meet,
    required this.raceNo,
    required this.grade,
    required this.ranks,
    required this.payoff,
  });

  final int meet;
  final int raceNo;
  final String grade;

  /// KCYCLE 상세 착순과 같은 형식의 선수별 기록
  final List<Map<String, dynamic>> ranks;

  final Odds payoff;

  /// 순위별 (배번, 선수명). 동착이면 순위가 같은 선수가 여럿이다.
  List<({int backNo, String name})> get placings => [
        for (final r in ranks)
          (backNo: r['back_no'] as int, name: r['racer_nm'] as String),
      ];
}
