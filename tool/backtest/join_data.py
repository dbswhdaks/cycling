"""3개 경기장 출주표와 KCYCLE 공식 결과를 경주 전/후 영역으로 결합한다."""

from __future__ import annotations

import argparse
import json
from collections import Counter
from pathlib import Path

from kcycle_data import join_entries, write_json

DATA_DIR = Path(__file__).resolve().parent / "data"


def parse_years(value: str) -> list[int]:
    years: set[int] = set()
    for part in value.split(","):
        bounds = [int(item) for item in part.strip().split("-", 1)]
        years.update(range(min(bounds), max(bounds) + 1))
    return sorted(years)


def join_year(year: int) -> dict:
    organ_path = DATA_DIR / f"organ_{year}.json"
    result_path = DATA_DIR / f"kcycle_results_{year}.json"
    if not organ_path.exists() or not result_path.exists():
        missing = [str(path) for path in (organ_path, result_path) if not path.exists()]
        raise FileNotFoundError("필요한 입력 파일 없음: " + ", ".join(missing))

    entries = json.loads(organ_path.read_text(encoding="utf-8"))
    official = json.loads(result_path.read_text(encoding="utf-8"))
    joined, failures = join_entries(entries, official)
    write_json(DATA_DIR / f"joined_{year}.json", joined)
    write_json(DATA_DIR / "reports" / f"join_failures_{year}.json", failures, indent=2)

    by_meet = Counter(race["meet_nm"] for race in joined)
    report = {
        "year": year,
        "races": len(joined),
        "riders": sum(len(race["pre_race"]["riders"]) for race in joined),
        "join_failures": len(failures),
        "races_by_meet": dict(sorted(by_meet.items())),
        "failure_reasons": dict(sorted(Counter(row["reason"] for row in failures).items())),
    }
    write_json(DATA_DIR / "reports" / f"join_{year}.json", report, indent=2)
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--years", type=parse_years, default=parse_years("2021-2026"))
    args = parser.parse_args()
    for year in args.years:
        report = join_year(year)
        print(
            f"{year}: {report['races']}경주/{report['riders']}명, "
            f"매칭 실패 {report['join_failures']}건, {report['races_by_meet']}"
        )


if __name__ == "__main__":
    main()
