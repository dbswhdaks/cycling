"""수집/결합 데이터의 누락·중복·착순·배당 무결성을 검사한다."""

from __future__ import annotations

import argparse
import json
from collections import Counter, defaultdict
from pathlib import Path

from kcycle_data import MEETS, ODDS_FIELDS, enumerate_races, write_json

DATA_DIR = Path(__file__).resolve().parent / "data"


def parse_years(value: str) -> list[int]:
    years: set[int] = set()
    for part in value.split(","):
        bounds = [int(item) for item in part.strip().split("-", 1)]
        years.update(range(min(bounds), max(bounds) + 1))
    return sorted(years)


def validate_year(year: int) -> dict:
    organ_path = DATA_DIR / f"organ_{year}.json"
    result_path = DATA_DIR / f"kcycle_results_{year}.json"
    joined_path = DATA_DIR / f"joined_{year}.json"
    for path in (organ_path, result_path, joined_path):
        if not path.exists():
            raise FileNotFoundError(path)

    organ = json.loads(organ_path.read_text(encoding="utf-8"))
    results = json.loads(result_path.read_text(encoding="utf-8"))
    joined = json.loads(joined_path.read_text(encoding="utf-8"))
    expected = {
        (race["date"], race["meet"], race["race_no"]) for race in enumerate_races(organ)
    }
    actual = {
        (race["date"], int(race["meet"]), int(race["race_no"])) for race in results
    }
    issues = []
    race_keys = Counter(
        (race["date"], int(race["meet"]), int(race["race_no"])) for race in results
    )
    for key, count in race_keys.items():
        if count > 1:
            issues.append({"type": "duplicate_race", "key": key, "count": count})

    status = Counter()
    by_meet = defaultdict(lambda: Counter(races=0, riders=0, missing=0))
    for race in results:
        key = (race["date"], int(race["meet"]), int(race["race_no"]))
        meet_stats = by_meet[MEETS[int(race["meet"])]["name"]]
        meet_stats["races"] += 1
        rows = race.get("results", [])
        meet_stats["riders"] += len(rows)
        status[race.get("status", "unknown")] += 1
        back_numbers = [int(row.get("back_no") or 0) for row in rows]
        if len(back_numbers) != len(set(back_numbers)):
            issues.append({"type": "duplicate_back_no", "key": key})
        if rows and not 5 <= len(rows) <= 9:
            issues.append({"type": "unexpected_rider_count", "key": key, "count": len(rows)})
        ranks = [int(row.get("rank") or 0) for row in rows]
        if rows and not {1, 2, 3}.issubset(ranks):
            issues.append({"type": "top3_missing", "key": key, "ranks": ranks})
        odds = race.get("odds", {})
        unknown = sorted(set(odds) - set(ODDS_FIELDS))
        if unknown:
            issues.append({"type": "unknown_odds_type", "key": key, "fields": unknown})
        for field in ODDS_FIELDS:
            for winner, value in odds.get(field, {}).items():
                if float(value) <= 0 or not all(part.isdigit() for part in winner.split("-")):
                    issues.append(
                        {"type": "invalid_odds", "key": key, "field": field,
                         "winner": winner, "value": value}
                    )

    missing_keys = sorted(expected - actual)
    for _, meet, _ in missing_keys:
        by_meet[MEETS[meet]["name"]]["missing"] += 1

    joined_keys = Counter(
        (race["date"], int(race["meet"]), int(race["race_no"])) for race in joined
    )
    for key, count in joined_keys.items():
        if count > 1:
            issues.append({"type": "duplicate_joined_race", "key": key, "count": count})
    unmatched = 0
    unique_riders = set()
    for race in joined:
        key = (race["date"], int(race["meet"]), int(race["race_no"]))
        for rider in race.get("pre_race", {}).get("riders", []):
            rider_key = (*key, int(rider.get("back_no") or 0))
            if rider_key in unique_riders:
                issues.append({"type": "duplicate_rider", "key": rider_key})
            unique_riders.add(rider_key)
            unmatched += rider.get("result") is None

    report = {
        "year": year,
        "expected_races": len(expected),
        "collected_races": len(actual),
        "missing_races": len(missing_keys),
        "missing_rate": len(missing_keys) / max(len(expected), 1),
        "joined_races": len(joined),
        "unmatched_riders": unmatched,
        "status": dict(sorted(status.items())),
        "by_meet": {name: dict(values) for name, values in sorted(by_meet.items())},
        "integrity_issue_count": len(issues),
        "missing_keys": missing_keys,
        "issues": issues,
    }
    write_json(DATA_DIR / "reports" / f"integrity_{year}.json", report, indent=2)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--years", type=parse_years, default=parse_years("2021-2026"))
    parser.add_argument(
        "--max-missing-rate",
        type=float,
        default=0.02,
        help="이 비율을 넘으면 종료 코드 1",
    )
    args = parser.parse_args()
    failed = False
    for year in args.years:
        report = validate_year(year)
        print(
            f"{year}: {report['collected_races']}/{report['expected_races']}경주, "
            f"누락 {report['missing_rate']:.2%}, 매칭 실패 {report['unmatched_riders']}명, "
            f"무결성 오류 {report['integrity_issue_count']}건"
        )
        failed |= (
            report["missing_rate"] > args.max_missing_rate
            or report["integrity_issue_count"] > 0
            or report["unmatched_riders"] > 0
        )
    raise SystemExit(1 if failed else 0)


if __name__ == "__main__":
    main()
