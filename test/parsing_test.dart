import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cycling/core/services/cycling_api_service.dart';
import 'package:cycling/core/services/kcycle_result_service.dart';
import 'package:cycling/core/services/lepopark_result_service.dart';
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

    test('경기장 코드는 KCYCLE 표기를 따른다', () {
      // 부산은 003이 아니라 004다. 003으로 요청하면 오류 페이지가 돌아온다.
      expect(KcycleResultService.meetCodes[1], '001');
      expect(KcycleResultService.meetCodes[2], '002');
      expect(KcycleResultService.meetCodes[3], '004');
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

    test('예측에 쓰는 지표까지 채운다', () {
      final parsed = VenueScrapingService()
          .parseLepoparkHtml(_fixture('lepopark_entrant.html'), '20260830');

      final song = parsed[2]!.firstWhere((m) => m['racer_nm'] == '송정욱');

      expect(song['racer_grd_cur_cd'], 'A2');
      expect(song['tot_tms_avg_scr'], '91.64');
      expect(song['area_tms3_avg_scr'], '93.91');
      expect(song['win_rate'], '35');
      expect(song['gear_rate'], '3.93');
      expect(song['rec_200m_scr'], '11"07');
      expect(song['trng_plc_nm'], '동서울');
      expect(song['racer_age'], '26');
      expect(song['run_day_tcnt'], '40');
      expect(song['pre_win_cnt'], '6');
      expect(song['mrk_win_cnt'], '3');
      // 직전 회차와 이번 회차의 지난 일차 성적이 모두 담긴다.
      expect(song['bf3_day1_rank'], '우수10-1젖');
      expect(song['bf1_day3_rank'], '우수 5-6');
      expect(song['cur_day1_rank'], '우수 2-3선');
    });

    test('크롤링 자료도 출주표 파싱에서 예측 항목으로 이어진다', () {
      final parsed = VenueScrapingService()
          .parseLepoparkHtml(_fixture('lepopark_entrant.html'), '20260830');
      final race3 =
          parsed[2]!.where((m) => m['race_no'] == '3').toList();

      final entries = CyclingApiService().buildEntriesFromItems(race3);
      final song = entries.firstWhere((e) => e.riderName == '송정욱');

      expect(song.avgScore, 91.64);
      expect(song.areaAvgScore, 93.91);
      expect(song.winRate, 35);
      expect(song.riderGrade, 'A2');
      expect(song.sprint200m, 11.07);
      expect(song.age, 26);
      expect(song.trainingPlace, '동서울');
      expect(song.markWinRatio, closeTo(3 / 40, 1e-9));
      expect(song.tactic, '젖히기');
      // 최신 성적(이번 회차 2일차)부터 담긴다.
      expect(song.recentFinishes.first, 4);
      expect(song.recentFinishes.length, greaterThanOrEqualTo(9));
    });
  });

  group('lepopark 경주결과 파싱', () {
    final parsed = LepoparkResultService()
        .parseResultPage(_fixture('lepopark_result.html'));

    test('경기장별로 경주가 갈린다', () {
      expect(parsed[2]?.keys, [6]);
      expect(parsed[3]?.keys, [1, 6]);
      expect(parsed[1]?.keys, [7]);
    });

    test('부산 1경주 착순표', () {
      final race = parsed[3]![1]!;

      expect(race.grade, '선발');
      expect(race.ranks.length, 7);
      expect(race.ranks.map((r) => r['rank']), [1, 2, 3, 4, 5, 6, 7]);
      expect(race.ranks.first['back_no'], 6);
      expect(race.ranks.first['racer_nm'], '김종재');
      expect(race.ranks.first['racer_no'], '20050019');
      expect(race.ranks.first['race_time'], '2:31:0410');
      expect(race.ranks.first['tactic'], '추입');
      expect(race.ranks.first['time_200m'], '12"11');
      expect(race.ranks.first['avg_speed'], '59.45');

      final second = race.ranks[1];
      expect(second['back_no'], 1);
      expect(second['racer_nm'], '김이남');
      expect(second['arrival_diff'], '3/4W');
    });

    test('부산 1경주 확정배당 - 승식 일곱 가지', () {
      final payoff = parsed[3]![1]!.payoff;

      expect(payoff.win, {6: 2.4});
      // 연승은 1·2착 두 명이 각각 배당을 받는다.
      expect(payoff.place, {1: 2.1, 6: 1.8});
      expect(payoff.exacta, {'6-1': 4.2});
      expect(payoff.quinella, {'1-6': 2.7});
      expect(payoff.trio, {'1-2-6': 3.4});
      expect(payoff.exactaTrio, {'6-1-2': 3.9});
      expect(payoff.trifecta, {'6-1-2': 8.6});
    });

    test('승부수가 없는 선수는 빈 문자열', () {
      final race = parsed[3]![1]!;
      final noTactic = race.ranks.firstWhere((r) => r['back_no'] == 5);

      expect(noTactic['tactic'], '');
    });

    test('착순이 없으면 경주를 만들지 않는다', () {
      expect(
        LepoparkResultService().parseResultPage('<html><body></body></html>'),
        isEmpty,
      );
    });
  });

  group('크롤링 결과 검증', () {
    final scraped = [
      {'race_no': '1', 'racer_nm': '송정욱'},
      {'race_no': '6', 'racer_nm': '김원호'},
    ];

    test('공공 API 편성에 없는 경주도 남긴다', () {
      // 순위 API는 부산을 2026년 6월 이후 싣지 않고 창원도 일부 경주를 빠뜨린다.
      // 편성표를 근거로 버리면 실제로 열린 경주가 통째로 사라진다.
      final kept = CyclingApiService().validateScrapedRaces(
        scraped,
        '20260830',
        3,
      );

      expect(kept.map((m) => m['race_no']), ['1', '6']);
    });

    test('빈 목록은 그대로 빈 목록', () {
      expect(
        CyclingApiService().validateScrapedRaces([], '20260830', 2),
        isEmpty,
      );
    });
  });
}
