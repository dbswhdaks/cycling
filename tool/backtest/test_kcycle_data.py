from __future__ import annotations

import sys
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))

from kcycle_data import (
    join_entries,
    normalize_official_race,
    parse_lepopark_entries,
    parse_odds_table,
    parse_rank_table,
)
from context_features import accident_events, board_injury_events, enrich_races
from fetch_fall_injuries import parse_detail, parse_listing

FIXTURES = HERE.parent.parent / "test" / "fixtures"


class KcycleParserTest(unittest.TestCase):
    def test_fall_injury_listing_and_detail(self) -> None:
        listing = """
        <table><tr><td>1219</td><td><a
        onclick="fnMoveDetail(&quot;13575&quot;, 'N')">2026년 낙차부상</a></td>
        <td>2026.09.18</td></tr></table>
        """
        posts = parse_listing(listing)
        self.assertEqual(posts[0]["seq_id"], "13575")
        self.assertEqual(posts[0]["published_date"], "20260918")

        detail = """
        <table><tr><td>출전경주</td><td>선수명</td><td>부상부위</td><td>비고</td></tr>
        <tr><td>38회 1일차 2경주</td><td>최 건 묵</td>
        <td>골반 타박상</td><td>의무실치료(출전불가)</td></tr></table>
        """
        parsed = parse_detail(detail, posts[0])
        self.assertEqual(parsed["injuries"][0]["racer_name_normalized"], "최건묵")
        self.assertEqual(parsed["injuries"][0]["severity"], "unavailable")

    def test_lepopark_parses_secondary_venue_entry_features(self) -> None:
        def section(venue: str, racer_no: str, name: str) -> str:
            cells = [
                f'<td><span>1</span><a href="/racer/{racer_no}">{name}</a> 28기 26세</td>',
                "<td>3.93</td>", '<td>11”07</td>', "<td>동서울</td>",
                "<td>35</td>", "<td>55</td>", "<td>65</td>", "<td>26/40</td>",
                "<td>6</td>", "<td>11</td>", "<td>6</td>", "<td>3</td>",
                "<td>A2</td>", "<td>A2</td>", "<td>93.91</td>",
                "<td>91.64</td>", "<td>244/574</td>",
            ]
            return (
                f"<h3>{venue} 03 경주 [우수] 출발 11:46</h3>"
                f"<table><tr>{''.join(cells)}</tr></table>"
            )

        rows = parse_lepopark_entries(
            section("창원", "20230011", "송정욱")
            + section("부산", "20230012", "홍길동"),
            "20260830",
        )
        self.assertTrue(rows)
        self.assertEqual({row["_meet"] for row in rows}, {2, 3})
        song = next(row for row in rows if row["racer_nm"] == "송정욱")
        self.assertEqual(song["racer_no"], "20230011")
        self.assertEqual(song["back_no"], "1")
        self.assertEqual(song["tot_tms_avg_scr"], "91.64")
        self.assertEqual(song["area_tms3_avg_scr"], "93.91")
        self.assertEqual(song["racer_grd_cur_cd"], "A2")
        self.assertEqual(song["run_day_tcnt"], "40")

    def test_rank_fixture_parses_identity_and_records(self) -> None:
        rows = parse_rank_table(
            (FIXTURES / "kcycle_result_gwangmyeong_16r.html").read_text(encoding="utf-8")
        )
        self.assertEqual(len(rows), 7)
        self.assertEqual([row["rank"] for row in rows], list(range(1, 8)))
        winner = rows[0]
        self.assertEqual(winner["back_no"], 4)
        self.assertEqual(winner["racer_no"], "20220006")
        self.assertEqual(winner["racer_nm"], "김옥철")
        self.assertEqual(winner["tactic"], "추입")
        self.assertEqual(winner["time_200m"], '10"90')

    def test_dead_heat_fixture_preserves_equal_rank(self) -> None:
        rows = parse_rank_table(
            (FIXTURES / "kcycle_result_changwon_3r.html").read_text(encoding="utf-8")
        )
        self.assertEqual([row["rank"] for row in rows[:3]], [1, 1, 3])
        self.assertEqual({row["racer_nm"] for row in rows[:2]}, {"송정욱", "문인재"})

    def test_vertical_odds_table_parses_all_seven_types(self) -> None:
        source = """
        <table><tr><th>승식</th><th>승자</th><th>평균확정배당률</th></tr>
        <tr><td>단승식</td><td>2</td><td>1.0</td></tr>
        <tr><td>연승식</td><td>2</td><td>1.0</td></tr>
        <tr><td>연승식</td><td>6</td><td>2.2</td></tr>
        <tr><td>쌍승식</td><td>2 · 6</td><td>2.4</td></tr>
        <tr><td>복승식</td><td>2 · 6</td><td>2.5</td></tr>
        <tr><td>삼복승식</td><td>2 · 6 · 5</td><td>6.8</td></tr>
        <tr><td>쌍복승식</td><td>2 · 6 · 5</td><td>6.8</td></tr>
        <tr><td>삼쌍승식</td><td>2 · 6 · 5</td><td>11.1</td></tr></table>
        """
        odds = parse_odds_table(source)
        self.assertEqual(odds["win"], {"2": 1.0})
        self.assertEqual(odds["place"], {"2": 1.0, "6": 2.2})
        self.assertEqual(odds["exacta"], {"2-6": 2.4})
        self.assertEqual(odds["quinella"], {"2-6": 2.5})
        self.assertEqual(odds["trio"], {"2-6-5": 6.8})
        self.assertEqual(odds["exacta_trio"], {"2-6-5": 6.8})
        self.assertEqual(odds["trifecta"], {"2-6-5": 11.1})

    def test_horizontal_odds_and_cancelled_status(self) -> None:
        source = """
        <table>
          <tr><th>승식</th><th>단승</th><th>연승</th><th>복승</th></tr>
          <tr><th>승자</th><td>3</td><td>3</td><td>3-1</td></tr>
          <tr><th>배당률(%)</th><td>4.2</td><td>1.6</td><td>1.2</td></tr>
        </table>
        """
        odds = parse_odds_table(source)
        self.assertEqual(odds["win"], {"3": 4.2})
        self.assertEqual(odds["place"], {"3": 1.6})
        self.assertEqual(odds["quinella"], {"3-1": 1.2})

        cancelled = normalize_official_race(
            {"date": "20260918", "year": 2026, "round": 38, "day": 1,
             "meet": 1, "race_no": 1},
            "<html><body>경주취소로 전액환불합니다.</body></html>",
            "https://example.invalid",
        )
        self.assertEqual(cancelled["status"], "cancelled")
        self.assertTrue(cancelled["refund"])


class JoinTest(unittest.TestCase):
    def test_join_uses_venue_race_and_back_number(self) -> None:
        entries = [
            {
                "race_ymd": "2026.09.18",
                "_meet": 2,
                "race_no": "01",
                "back_no": str(back_no),
                "racer_nm": f"출주{back_no}",
            }
            for back_no in (1, 2)
        ]
        official = [
            {
                "date": "20260918",
                "meet": 2,
                "race_no": 1,
                "status": "complete",
                "results": [
                    {"back_no": 2, "rank": 1, "racer_no": "20000002", "racer_nm": "선수2"},
                    {"back_no": 1, "rank": 2, "racer_no": "20000001", "racer_nm": "선수1"},
                ],
                "odds": {"win": {"2": 2.0}},
            }
        ]
        joined, failures = join_entries(entries, official)
        self.assertFalse(failures)
        riders = joined[0]["pre_race"]["riders"]
        self.assertEqual([rider["result"]["rank"] for rider in riders], [2, 1])
        self.assertEqual(riders[0]["racer_no"], "20000001")
        self.assertNotIn("odds", joined[0]["pre_race"])
        self.assertEqual(joined[0]["post_race"]["odds"]["win"], {"2": 2.0})

    def test_context_features_only_use_strictly_prior_events(self) -> None:
        def race(race_date: str, winner: int) -> dict:
            return {
                "date": race_date,
                "year": 2026,
                "meet": 1,
                "race_no": 1,
                "pre_race": {
                    "riders": [
                        {
                            "racer_no": str(number),
                            "racer_nm": f"선수{number}",
                            "pre_race": {},
                            "result": {"rank": 1 if number == winner else 2},
                        }
                        for number in (1, 2)
                    ]
                },
            }

        enriched = enrich_races(
            [race("20260101", 1), race("20260111", 2)],
            {"id:1": ["20260101"]},
        )
        first = enriched[0]["pre_race"]["riders"][0]["pre_race"]
        second = enriched[1]["pre_race"]["riders"][0]["pre_race"]
        self.assertEqual(first["opponent_history_coverage"], 0)
        self.assertEqual(first["days_since_fall"], 365)
        self.assertEqual(second["opponent_history_coverage"], 1)
        self.assertEqual(second["opponent_win_rate"], 1)
        self.assertEqual(second["days_since_fall"], 10)
        self.assertEqual(second["falls_30d"], 1)

    def test_accident_disposition_maps_to_official_racer_number(self) -> None:
        races = [
            {
                "date": "20260111",
                "year": 2026,
                "meet": 1,
                "race_no": 3,
                "pre_race": {
                    "riders": [
                        {
                            "racer_no": "20230011",
                            "racer_nm": "송정욱",
                            "pre_race": {"period_no": "2", "day_tcnt": "3"},
                            "result": {"rank": 1},
                        }
                    ]
                },
            }
        ]
        events, unmatched = accident_events(
            races,
            [
                {
                    "stnd_year": "2026",
                    "tms": "2",
                    "day_ord": "3",
                    "race_no": "3",
                    "racer_no1": "송정욱",
                    "leav1_cd": "후송",
                }
            ],
        )
        self.assertFalse(unmatched)
        self.assertEqual(events, {"id:20230011": ["20260111"]})

        board, severe, unmatched = board_injury_events(
            races,
            [
                {
                    "seq_id": "13575",
                    "published_date": "20260111",
                    "injuries": [
                        {
                            "racer_name_normalized": "송정욱",
                            "severity": "unavailable",
                        }
                    ],
                }
            ],
        )
        self.assertFalse(unmatched)
        self.assertEqual(board, {"id:20230011": ["20260111"]})
        self.assertEqual(severe, board)


if __name__ == "__main__":
    unittest.main()
