import '../../models/race.dart';
import '../../models/race_entry.dart';
import '../../models/race_result.dart';
import '../../models/odds.dart';
import '../../core/constants/api_constants.dart';

/// 데모용 목업 데이터
class MockData {
  static const _defaultRaceCount = 5;

  static const _venueStartTimes = <int, List<String>>{
    1: ['10:00', '10:35', '11:10', '11:45', '12:20'],
    2: ['10:10', '10:45', '11:20', '11:55', '12:30'],
    3: ['10:20', '10:55', '11:30', '12:05', '12:40'],
  };

  static List<Race> racesFor(int venue, String date, {int count = _defaultRaceCount}) {
    final venueName = ApiConstants.venueName(venue);
    final times = _venueStartTimes[venue] ?? _venueStartTimes[1]!;
    return List.generate(count, (i) => Race(
      venueCode: venue,
      date: date,
      raceNo: i + 1,
      venueName: venueName,
      distance: 2025,
      departureTime: times[i % times.length],
      racerCount: 7,
    ));
  }

  static const _venueNames = <int, List<String>>{
    1: ['김철수', '이영희', '박민수', '최지훈', '정수진', '한동훈', '윤서연'],
    2: ['오성빈', '장태영', '나윤호', '문재혁', '임수현', '배진우', '허승범'],
    3: ['송기현', '강민석', '서준혁', '안세훈', '조하진', '권태우', '류동현'],
  };

  static List<RaceEntry> entriesFor(int raceNo, [int venue = 1]) {
    final names = _venueNames[venue] ?? _venueNames[1]!;
    final grades = ['S', 'A1', 'A2', 'B1', 'B2', 'B3'];
    final tactics = ['선행', '젖히기', '추입', '마크'];
    return List.generate(7, (i) => RaceEntry(
      lineNo: i + 1,
      riderName: names[(raceNo + i) % names.length],
      riderId: 'R${venue * 1000 + raceNo * 10 + i}',
      grade: grades[(i + venue) % grades.length],
      tactic: tactics[(i + raceNo) % tactics.length],
      avgScore: 7.2 + (i * 0.3) + venue * 0.1,
      recent3Wins: (i + venue) % 3,
    ));
  }

  static RaceResult raceResultFor(int raceNo, [List<RaceEntry>? realEntries, int venue = 1]) {
    final ranks = raceRanksFor(raceNo, realEntries, venue);
    final r1 = ranks[0];
    final r2 = ranks[1];
    final r3 = ranks[2];
    final seed = raceNo * 13 + venue * 7;
    return RaceResult(
      raceNo: raceNo,
      first: r1['racer_nm'] as String,
      firstNo: r1['back_no'] as int,
      second: r2['racer_nm'] as String,
      secondNo: r2['back_no'] as int,
      third: r3['racer_nm'] as String,
      thirdNo: r3['back_no'] as int,
      winOdds: 3.2 + raceNo * 0.5 + venue * 0.7,
      placeOdds: 1.8 + raceNo * 0.3 + venue * 0.4,
      quinellaOdds: 8.5 + seed * 0.3,
    );
  }

  static List<Map<String, dynamic>> raceRanksFor(int raceNo, [List<RaceEntry>? realEntries, int venue = 1]) {
    final entries = (realEntries != null && realEntries.isNotEmpty)
        ? realEntries
        : entriesFor(raceNo, venue);
    final shuffled = List.of(entries);
    final seed = raceNo * 7 + venue * 11;
    for (int i = shuffled.length - 1; i > 0; i--) {
      final j = (seed + i * 3) % (i + 1);
      final tmp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = tmp;
    }
    final baseSec = 12 + venue * 2;
    return List.generate(shuffled.length, (i) {
      final e = shuffled[i];
      return {
        'rank': i + 1,
        'back_no': e.lineNo,
        'racer_nm': e.riderName,
        'racer_grd_cd': e.grade,
        'race_time': '2:${(baseSec + i * 2).toString().padLeft(2, '0')}.${(30 + i * 15 + venue * 5) % 100}',
        'arrival_diff': i == 0 ? '-' : '+${(i * 0.3).toStringAsFixed(1)}초',
      };
    });
  }

  static Odds oddsFor(int raceNo, [int venue = 1]) {
    final v = venue * 0.3;
    final r = raceNo * 0.2;
    return Odds(
      win: {
        1: 3.2 + v,
        2: 5.1 + r,
        3: 8.4 + v + r,
        4: 12.0 + v,
        5: 18.5 + r,
        6: 25.0 + v + r,
        7: 35.0 + v,
      },
      place: {
        '1-2': 2.1 + v,
        '1-3': 4.5 + r,
        '1-4': 5.2 + v,
        '2-3': 6.2 + r,
        '2-4': 8.1 + v + r,
        '3-4': 12.5 + v,
      },
      quinella: {
        '1-2': 4.8 + v,
        '1-3': 12.2 + r,
        '2-1': 5.1 + v + r,
        '2-3': 18.5 + v,
        '3-1': 15.0 + r,
        '3-2': 22.0 + v + r,
      },
      trio: {
        '1-2-3': 8.5 + v,
        '1-2-4': 15.2 + r,
        '1-3-2': 9.0 + v + r,
        '2-1-3': 12.0 + v,
        '2-3-1': 18.5 + r,
      },
      trifecta: {
        '1-2-3': 25.0 + v + r,
        '1-2-4': 45.0 + v,
        '1-3-2': 38.0 + r,
        '2-1-3': 52.0 + v + r,
        '2-3-1': 68.0 + v,
      },
    );
  }
}
