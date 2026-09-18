"""낙차 이력과 출전 선수 간 과거 상대전적 피처를 시점 안전하게 생성한다."""

from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict
from datetime import date
from pathlib import Path

from kcycle_data import clean, integer, write_json

DATA_DIR = Path(__file__).resolve().parent / "data"
DOWN_ACCIDENT_URL = (
    "https://apis.data.go.kr/B551014/"
    "SRVC_TODZ_CRA_DOWN_ACDNT/TODZ_CRA_DOWN_ACDNT"
)
SERVICE_KEY = os.environ.get(
    "CYCLING_SERVICE_KEY",
    "788d1f62af9d665d2f002057f9526ac8f2776910fef87b0e95d27e232fe0967f",
)


def parse_years(value: str) -> list[int]:
    years: set[int] = set()
    for part in value.split(","):
        bounds = [int(item) for item in part.strip().split("-", 1)]
        years.update(range(min(bounds), max(bounds) + 1))
    return sorted(years)


def _get(**params) -> dict:
    params.setdefault("serviceKey", SERVICE_KEY)
    params.setdefault("resultType", "json")
    url = f"{DOWN_ACCIDENT_URL}?{urllib.parse.urlencode(params)}"
    for attempt in range(4):
        try:
            with urllib.request.urlopen(url, timeout=40) as response:
                return json.loads(response.read().decode("utf-8"))
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))
    return {}


def _items(payload: dict) -> list[dict]:
    body = payload.get("response", {}).get("body", {})
    items = body.get("items") or {}
    item = items.get("item") if isinstance(items, dict) else items
    if isinstance(item, dict):
        return [item]
    return [row for row in (item or []) if isinstance(row, dict)]


def fetch_accidents(year: int, refresh: bool = False) -> list[dict]:
    path = DATA_DIR / f"down_accidents_{year}.json"
    if path.exists() and not refresh:
        return json.loads(path.read_text(encoding="utf-8"))
    payload = _get(stnd_year=year, pageNo=1, numOfRows=1000)
    rows = _items(payload)
    write_json(path, rows)
    return rows


def _day(value: str) -> date:
    return date(int(value[:4]), int(value[4:6]), int(value[6:8]))


def _name_key(value: object) -> str:
    return clean(value).replace(" ", "")


def _rider_key(rider: dict) -> str:
    racer_no = clean(rider.get("racer_no"))
    return f"id:{racer_no}" if racer_no else f"name:{_name_key(rider.get('racer_nm'))}"


def _schedule(races: list[dict]) -> dict[tuple[int, int, int], str]:
    schedule = {}
    for race in races:
        riders = race.get("pre_race", {}).get("riders", [])
        source = riders[0].get("pre_race", {}) if riders else {}
        year = integer(race.get("year"), integer(str(race.get("date"))[:4]))
        round_no = integer(source.get("period_no") or source.get("tms"))
        day_no = integer(source.get("day_tcnt") or source.get("day_ord"))
        if round_no and day_no:
            schedule[(year, round_no, day_no)] = str(race["date"])
    return schedule


def accident_events(races: list[dict], accidents: list[dict]) -> tuple[dict[str, list[str]], list[dict]]:
    """낙차 API의 이름/배번을 공식 결과 선수번호에 연결한다."""
    schedule = _schedule(races)
    race_index: dict[tuple[str, int], list[dict]] = defaultdict(list)
    for race in races:
        race_index[(str(race["date"]), integer(race["race_no"]))].append(race)

    events: dict[str, list[str]] = defaultdict(list)
    unmatched = []
    for row in accidents:
        year = integer(row.get("stnd_year"))
        round_no = integer(row.get("tms"))
        day_no = integer(row.get("day_ord"))
        race_no = integer(row.get("race_no"))
        race_date = schedule.get((year, round_no, day_no))
        if not race_date:
            unmatched.append({"reason": "date_not_found", "row": row})
            continue
        candidates = race_index.get((race_date, race_no), [])
        by_name = {
            _name_key(rider.get("racer_nm")): rider
            for race in candidates
            for rider in race.get("pre_race", {}).get("riders", [])
        }
        for back_no in range(1, 8):
            # leavN_cd가 있는 선수가 낙차 후 재승 또는 후송된 당사자다.
            disposition = clean(row.get(f"leav{back_no}_cd"))
            if not disposition:
                continue
            name = _name_key(row.get(f"racer_no{back_no}"))
            rider = by_name.get(name)
            if rider is None:
                unmatched.append(
                    {
                        "reason": "rider_not_found",
                        "date": race_date,
                        "race_no": race_no,
                        "back_no": back_no,
                        "racer_nm": name,
                    }
                )
                continue
            events[_rider_key(rider)].append(race_date)
    return {key: sorted(set(values)) for key, values in events.items()}, unmatched


def board_injury_events(
    races: list[dict],
    posts: list[dict],
) -> tuple[dict[str, list[str]], dict[str, list[str]], list[dict]]:
    """게시판 선수명을 고유한 공식 선수번호에 해소한다."""
    keys_by_name: dict[str, set[str]] = defaultdict(set)
    for race in races:
        for rider in race.get("pre_race", {}).get("riders", []):
            keys_by_name[_name_key(rider.get("racer_nm"))].add(_rider_key(rider))

    events: dict[str, list[str]] = defaultdict(list)
    severe: dict[str, list[str]] = defaultdict(list)
    unmatched = []
    for post in posts:
        published = str(post.get("published_date") or "")
        if len(published) != 8:
            continue
        for injury in post.get("injuries", []):
            name = _name_key(injury.get("racer_name_normalized"))
            candidates = keys_by_name.get(name, set())
            if len(candidates) != 1:
                unmatched.append(
                    {
                        "seq_id": post.get("seq_id"),
                        "published_date": published,
                        "racer_nm": name,
                        "reason": "ambiguous_name" if candidates else "rider_not_found",
                    }
                )
                continue
            key = next(iter(candidates))
            events[key].append(published)
            if injury.get("severity") in {"unavailable", "hospital"}:
                severe[key].append(published)
    return (
        {key: sorted(set(values)) for key, values in events.items()},
        {key: sorted(set(values)) for key, values in severe.items()},
        unmatched,
    )


def enrich_races(
    races: list[dict],
    injuries: dict[str, list[str]],
    severe_injuries: dict[str, list[str]] | None = None,
) -> list[dict]:
    """각 경주를 처리한 뒤에만 상대전적을 갱신해 미래 누수를 막는다."""
    pair_stats: dict[tuple[str, str], dict[str, int]] = defaultdict(
        lambda: {"wins": 0, "meetings": 0, "both_top3": 0}
    )
    output = []
    for race in sorted(races, key=lambda item: (item["date"], item["meet"], item["race_no"])):
        riders = race.get("pre_race", {}).get("riders", [])
        race_date = str(race["date"])
        current_day = _day(race_date)
        for rider in riders:
            key = _rider_key(rider)
            opponents = [_rider_key(other) for other in riders if other is not rider]
            known = [pair_stats[(key, opponent)] for opponent in opponents]
            known = [stats for stats in known if stats["meetings"] > 0]
            total_meetings = sum(stats["meetings"] for stats in known)
            row = rider.setdefault("pre_race", {})
            row["opponent_win_rate"] = (
                sum(stats["wins"] for stats in known) / total_meetings
                if total_meetings
                else 0.5
            )
            row["opponent_top3_pair_rate"] = (
                sum(stats["both_top3"] for stats in known) / total_meetings
                if total_meetings
                else 0.0
            )
            row["opponent_history_coverage"] = len(known) / max(len(opponents), 1)

            prior_injuries = [
                value for value in injuries.get(key, []) if value < race_date
            ]
            prior_severe = [
                value
                for value in (severe_injuries or {}).get(key, [])
                if value < race_date
            ]
            elapsed = [(current_day - _day(value)).days for value in prior_injuries]
            severe_elapsed = [(current_day - _day(value)).days for value in prior_severe]
            row["days_since_fall"] = min(elapsed[-1], 365) if elapsed else 365
            row["falls_30d"] = sum(days <= 30 for days in elapsed)
            row["falls_90d"] = sum(days <= 90 for days in elapsed)
            row["severe_injury_30d"] = sum(days <= 30 for days in severe_elapsed)

        # 같은 경주 피처를 모두 만든 후 결과를 누적한다.
        for rider in riders:
            result = rider.get("result") or {}
            rank = integer(result.get("rank"), 99)
            key = _rider_key(rider)
            for opponent in riders:
                if opponent is rider:
                    continue
                opponent_rank = integer((opponent.get("result") or {}).get("rank"), 99)
                stats = pair_stats[(key, _rider_key(opponent))]
                stats["meetings"] += 1
                stats["wins"] += rank < opponent_rank
                stats["both_top3"] += rank <= 3 and opponent_rank <= 3
        output.append(race)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--years", type=parse_years, default=parse_years("2021-2026"))
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()

    races = []
    accidents = []
    for year in args.years:
        path = DATA_DIR / f"joined_{year}.json"
        if not path.exists():
            raise FileNotFoundError(path)
        races.extend(json.loads(path.read_text(encoding="utf-8")))
        accidents.extend(fetch_accidents(year, args.refresh))

    injuries, unmatched = accident_events(races, accidents)
    board_path = DATA_DIR / "fall_injuries.json"
    board_posts = (
        json.loads(board_path.read_text(encoding="utf-8"))
        if board_path.exists()
        else []
    )
    board_events, severe_events, board_unmatched = board_injury_events(races, board_posts)
    for key, values in board_events.items():
        injuries[key] = sorted(set(injuries.get(key, []) + values))
    enriched = enrich_races(races, injuries, severe_events)
    by_year: dict[int, list[dict]] = defaultdict(list)
    for race in enriched:
        by_year[integer(race["year"], int(str(race["date"])[:4]))].append(race)
    for year in args.years:
        write_json(DATA_DIR / f"joined_context_{year}.json", by_year[year])
    report = {
        "years": args.years,
        "accident_rows": len(accidents),
        "injured_riders": len(injuries),
        "injury_events": sum(map(len, injuries.values())),
        "unmatched_accident_rows": len(unmatched),
        "unmatched": unmatched,
        "fall_injury_posts": len(board_posts),
        "severe_injury_events": sum(map(len, severe_events.values())),
        "unmatched_board_injuries": len(board_unmatched),
        "board_unmatched": board_unmatched,
    }
    write_json(DATA_DIR / "reports" / "context_features.json", report, indent=2)
    print(
        f"{len(enriched)}경주 보강: 낙차 {report['injury_events']}건/"
        f"{report['injured_riders']}명, 미결합 {len(unmatched)}건"
    )


if __name__ == "__main__":
    main()
