import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cycling/core/services/cycling_api_service.dart';
import 'package:cycling/core/services/kcycle_result_service.dart';
import 'package:cycling/core/services/venue_scraping_service.dart';

/// 실제 응답을 잘라 저장한 픽스처로 파싱을 검증한다.
/// 대상 사이트의 HTML 구조가 바뀌면 이 테스트가 먼저 깨지도록 하는 것이 목적이다.
String _fixture(String name) => File('test/fixtures/$name').readAsStringSync();

void main() {
  group('KCYCLE 상세 착순 파싱', () {
    test('광명 16R - 배번·착차·주행시간·승부수', () {
      final rows = KcycleResultService()
          .parseRankTable(_fixture('kcycle_result_gwangmyeong_16r.html'));

      expect(rows.length, 7);
      expect(rows.map((r) => r['rank']), [1, 2, 3, 4, 5, 6, 7]);
      expect(rows.map((r) => r['back_no']), [4, 1, 3, 6, 2, 7, 5]);

      final winner = rows.first;
      expect(winner['racer_nm'], '김옥철');
      expect(winner['racer_no'], '20220006');
      expect(winner['race_time'], '2:19:6925');
      expect(winner['arrival_diff'], '-');
      expect(winner['tactic'], '추입');
      expect(winner['time_200m'], '10"90');
      expect(winner['avg_speed'], '66.06');

      // 승부수가 없는 선수는 '-'가 아니라 빈 문자열로 정리된다.
      expect(rows.last['tactic'], '');
    });

    test('창원 3R - 동착은 같은 순위로 파싱된다', () {
      final rows = KcycleResultService()
          .parseRankTable(_fixture('kcycle_result_changwon_3r.html'));

      expect(rows.length, 7);
      expect(rows.map((r) => r['rank']).take(3), [1, 1, 3]);

      final tied = rows.take(2).toList();
      expect(tied.map((r) => r['racer_nm']).toSet(), {'송정욱', '문인재'});
      expect(tied.map((r) => r['race_time']).toSet(), {'2:29:4415'});
      expect(tied.map((r) => r['arrival_diff']), contains('동착'));
    });

    test('표가 없으면 빈 목록', () {
      expect(KcycleResultService().parseRankTable('<html></html>'), isEmpty);
    });
  });

  group('lepopark 출주표 파싱', () {
    test('창원 경주의 배번 순서와 등급', () {
      final parsed = VenueScrapingService()
          .parseLepoparkHtml(_fixture('lepopark_entrant.html'), '20260830');

      final changwon = parsed[2]!;
      expect(changwon, isNotEmpty);

      final race3 = changwon.where((m) => m['race_no'] == '3').toList();
      expect(race3.length, 7);
      expect(race3.map((m) => m['back_no']), ['1', '2', '3', '4', '5', '6', '7']);
      expect(
        race3.map((m) => m['racer_nm']),
        ['송정욱', '최근영', '김홍기', '문인재', '신동인', '김환윤', '김용진'],
      );
      expect(race3.first['race_ymd'], '2026.08.30');
      expect(race3.first['race_grd'], '우수');
      expect(race3.first['dptre_tm'], '11:46');
      expect(race3.every((m) => (m['racer_grd_cd'] as String).isNotEmpty), isTrue);
    });
  });

  group('크롤링 결과 편성 검증', () {
    final scraped = [
      {'race_no': '1', 'racer_nm': '송정욱'},
      {'race_no': '6', 'racer_nm': '김원호'},
    ];

    test('편성에 없는 경주는 제외된다', () {
      final kept = CyclingApiService().validateScrapedRaces(
        scraped,
        '20260830',
        2,
        {
          2: {
            1: {'송정욱'},
          },
        },
      );

      expect(kept.map((m) => m['race_no']), ['1']);
    });

    test('시행 기록이 없는 경기장은 전부 폐기된다', () {
      final kept = CyclingApiService().validateScrapedRaces(
        scraped,
        '20260830',
        3,
        {
          1: {
            1: {'김옥철'},
          },
        },
      );

      expect(kept, isEmpty);
    });

    test('편성 자체를 모르면(시행 전) 걸러내지 않는다', () {
      final kept = CyclingApiService().validateScrapedRaces(
        scraped,
        '20260904',
        2,
        const {},
      );

      expect(kept.length, 2);
    });
  });
}
