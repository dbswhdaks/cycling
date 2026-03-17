import '../../models/race.dart';
import '../../models/race_entry.dart';
import '../../models/race_result.dart';
import '../../models/odds.dart';

/// 데모용 목업 데이터
class MockData {
  static final List<Race> races = [
    const Race(
      venueCode: 1,
      date: '20260316',
      raceNo: 1,
      venueName: '광명스피돔',
      status: '예정',
    ),
    const Race(
      venueCode: 1,
      date: '20260316',
      raceNo: 2,
      venueName: '광명스피돔',
      status: '예정',
    ),
    const Race(
      venueCode: 1,
      date: '20260316',
      raceNo: 3,
      venueName: '광명스피돔',
      status: '예정',
    ),
    const Race(
      venueCode: 2,
      date: '20260316',
      raceNo: 1,
      venueName: '창원경륜장',
      status: '예정',
    ),
    const Race(
      venueCode: 2,
      date: '20260316',
      raceNo: 2,
      venueName: '창원경륜장',
      status: '예정',
    ),
    const Race(
      venueCode: 3,
      date: '20260316',
      raceNo: 1,
      venueName: '부산경륜장',
      status: '예정',
    ),
  ];

  static List<RaceEntry> entriesFor(int raceNo) {
    final names = [
      '김철수', '이영희', '박민수', '최지훈', '정수진', '한동훈', '윤서연',
    ];
    final grades = ['S', 'A1', 'A2', 'B1', 'B2', 'B3'];
    final tactics = ['선행', '젖히기', '추입', '마크'];
    return List.generate(7, (i) => RaceEntry(
      lineNo: i + 1,
      riderName: names[(raceNo + i) % names.length],
      riderId: 'R${1000 + i}',
      grade: grades[i % grades.length],
      tactic: tactics[i % tactics.length],
      avgScore: 7.2 + (i * 0.3),
      recent3Wins: i % 3,
    ));
  }

  static RaceResult raceResultFor(int raceNo) {
    final ranks = raceRanksFor(raceNo);
    final r1 = ranks[0];
    final r2 = ranks[1];
    final r3 = ranks[2];
    return RaceResult(
      raceNo: raceNo,
      first: r1['racer_nm'] as String,
      firstNo: r1['back_no'] as int,
      second: r2['racer_nm'] as String,
      secondNo: r2['back_no'] as int,
      third: r3['racer_nm'] as String,
      thirdNo: r3['back_no'] as int,
      winOdds: 3.2 + raceNo * 0.5,
      placeOdds: 1.8 + raceNo * 0.3,
      quinellaOdds: 8.5 + raceNo * 1.2,
    );
  }

  static List<Map<String, dynamic>> raceRanksFor(int raceNo) {
    final entries = entriesFor(raceNo);
    final shuffled = List.of(entries);
    for (int i = shuffled.length - 1; i > 0; i--) {
      final j = (raceNo * 7 + i * 3) % (i + 1);
      final tmp = shuffled[i];
      shuffled[i] = shuffled[j];
      shuffled[j] = tmp;
    }
    return List.generate(shuffled.length, (i) {
      final e = shuffled[i];
      return {
        'rank': i + 1,
        'back_no': e.lineNo,
        'racer_nm': e.riderName,
        'racer_grd_cd': e.grade,
        'race_time': '2:${(12 + i * 2).toString().padLeft(2, '0')}.${(30 + i * 15) % 100}',
        'arrival_diff': i == 0 ? '-' : '+${(i * 0.3).toStringAsFixed(1)}초',
      };
    });
  }

  static Odds oddsFor(int raceNo) {
    return Odds(
      win: {
        1: 3.2,
        2: 5.1,
        3: 8.4,
        4: 12.0,
        5: 18.5,
        6: 25.0,
        7: 35.0,
      },
      place: {
        '1-2': 2.1,
        '1-3': 4.5,
        '1-4': 5.2,
        '2-3': 6.2,
        '2-4': 8.1,
        '3-4': 12.5,
      },
      quinella: {
        '1-2': 4.8,
        '1-3': 12.2,
        '2-1': 5.1,
        '2-3': 18.5,
        '3-1': 15.0,
        '3-2': 22.0,
      },
      trio: {
        '1-2-3': 8.5,
        '1-2-4': 15.2,
        '1-3-2': 9.0,
        '2-1-3': 12.0,
        '2-3-1': 18.5,
      },
      trifecta: {
        '1-2-3': 25.0,
        '1-2-4': 45.0,
        '1-3-2': 38.0,
        '2-1-3': 52.0,
        '2-3-1': 68.0,
      },
    );
  }
}
