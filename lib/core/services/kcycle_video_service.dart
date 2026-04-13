import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../models/race_video.dart';

class KcycleVideoService {
  static const _baseUrl = 'https://www.kcycle.or.kr';

  final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 15),
    headers: {
      'Accept': 'text/html,application/xhtml+xml',
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) CyclingApp/1.0',
    },
  ));

  List<RaceVideo>? _cachedVideos;
  DateTime? _cacheTime;

  /// 경주 동영상 목록을 스크래핑하여 반환.
  Future<List<RaceVideo>> fetchRaceVideos({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedVideos != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!).inMinutes < 10) {
      return _cachedVideos!;
    }

    try {
      final response = await _dio.get('/broadcast/racevideo');
      if (response.statusCode != 200) throw Exception('HTTP ${response.statusCode}');

      final html = response.data.toString();
      final videos = _parseVideoList(html);

      _cachedVideos = videos;
      _cacheTime = DateTime.now();

      if (kDebugMode) {
        debugPrint('[KcycleVideo] 영상 ${videos.length}건 로드 완료');
      }
      return videos;
    } catch (e) {
      if (kDebugMode) debugPrint('[KcycleVideo] 영상 목록 로드 실패: $e');
      if (_cachedVideos != null) return _cachedVideos!;
      rethrow;
    }
  }

  /// 팝업 페이지에서 실제 MP4 동영상 URL을 추출.
  Future<String?> fetchVideoUrl(RaceVideo video, {String mode = 'F'}) async {
    try {
      final path = video.popupPath(mode);
      final response = await _dio.get(
        path,
        options: Options(headers: {'X-Requested-With': 'XMLHttpRequest'}),
      );
      if (response.statusCode != 200) return null;

      final html = response.data.toString();
      final urlMatch = RegExp(r'videoUrl\s*=\s*"([^"]+)"').firstMatch(html);
      if (urlMatch == null) return null;

      final videoUrl = urlMatch.group(1)!.replaceAll(r'\/', '/');
      if (kDebugMode) debugPrint('[KcycleVideo] MP4 URL: $videoUrl');
      return videoUrl;
    } catch (e) {
      if (kDebugMode) debugPrint('[KcycleVideo] 영상 URL 추출 실패: $e');
      return null;
    }
  }

  /// HTML에서 경주 동영상 카드 목록 파싱.
  ///
  /// 각 카드 구조:
  ///  - 썸네일: <img src="https://cast.kcycle.or.kr/vod/pds/YYYY/M/D/ID.jpg">
  ///  - 제목: "2026년 광명 15회 3일차 16경주(04월 12일)"
  ///  - 팝업 파라미터: fnVideo.popup('race', "YYYY", "meetNo", "day", "venueCode", "raceNo", 'mode')
  ///  - 날짜: "2026.04.12"
  List<RaceVideo> _parseVideoList(String html) {
    final videos = <RaceVideo>[];

    final popupRegex = RegExp(
      r'fnVideo\.popup\(\s*&#39;race&#39;\s*,'
      r'\s*&quot;(\d+)&quot;\s*,'   // year
      r'\s*&quot;(\d+)&quot;\s*,'   // meetNo
      r'\s*&quot;(\d+)&quot;\s*,'   // day
      r'\s*&quot;(\d+)&quot;\s*,'   // venueCode
      r'\s*&quot;(\d+)&quot;\s*,'   // raceNo
      r"\s*&#39;F&#39;\s*\)",
    );

    final thumbnailRegex = RegExp(
      r'src="(https://cast\.kcycle\.or\.kr/vod/pds/[^"]+\.jpg)"',
    );

    final titleRegex = RegExp(r'(\d{4}년\s+\S+\s+\d+회\s+\d+일차\s+\d+경주\([^)]+\))');
    final dateRegex = RegExp(r'(\d{4}\.\d{2}\.\d{2})');

    final popupMatches = popupRegex.allMatches(html).toList();
    final thumbMatches = thumbnailRegex.allMatches(html).toList();
    final titleMatches = titleRegex.allMatches(html).toList();

    final seenKeys = <String>{};

    for (int i = 0; i < popupMatches.length; i++) {
      final pm = popupMatches[i];
      final year = pm.group(1)!;
      final meetNo = pm.group(2)!;
      final day = pm.group(3)!;
      final venueCode = pm.group(4)!;
      final raceNo = pm.group(5)!;

      final key = '$year-$meetNo-$day-$venueCode-$raceNo';
      if (seenKeys.contains(key)) continue;
      seenKeys.add(key);

      String thumbnailUrl = '';
      if (i < thumbMatches.length) {
        thumbnailUrl = thumbMatches[i].group(1)!;
      }

      String title = '${year}년 $raceNo경주';
      final nearbyHtml = html.substring(
        (pm.start - 500).clamp(0, html.length),
        pm.start,
      );
      final titleMatch = titleRegex.firstMatch(nearbyHtml);
      if (titleMatch != null) {
        title = titleMatch.group(1)!;
      } else if (i < titleMatches.length) {
        title = titleMatches[i].group(1)!;
      }

      String date = '';
      final dateMatch = dateRegex.firstMatch(nearbyHtml);
      if (dateMatch != null) {
        date = dateMatch.group(1)!;
      }

      videos.add(RaceVideo(
        title: title,
        date: date,
        thumbnailUrl: thumbnailUrl,
        year: year,
        meetNo: meetNo,
        day: day,
        venueCode: venueCode,
        raceNo: raceNo,
      ));
    }

    return videos;
  }

  void clearCache() {
    _cachedVideos = null;
    _cacheTime = null;
  }
}
