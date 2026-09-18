"""2021~2026 KCYCLE 공식 상세 결과와 확정배당 수집기.

출주표의 회차·일차·경기장·경주번호를 사용하며 경주 단위 체크포인트 덕분에
중단 후 같은 명령으로 재개할 수 있다.
"""

from __future__ import annotations

import argparse
import json
import random
import time
import urllib.error
import urllib.request
from pathlib import Path

from kcycle_data import MEETS, enumerate_races, normalize_official_race, write_json

ROOT = Path(__file__).resolve().parent
DATA_DIR = ROOT / "data"
BASE_URL = "https://www.kcycle.or.kr/race/result/general"
USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) CyclingBacktest/1.0"


def parse_years(value: str) -> list[int]:
    years: set[int] = set()
    for part in value.split(","):
        bounds = [int(item) for item in part.strip().split("-", 1)]
        years.update(range(min(bounds), max(bounds) + 1))
    return sorted(years)


def race_url(race: dict) -> str:
    meet = MEETS[race["meet"]]["kcycle_code"]
    return (
        f"{BASE_URL}/{race['year']}/{race['round']}/{race['day']}/"
        f"{meet}/{race['race_no']:02d}"
    )


def download(url: str, timeout: float, retries: int) -> str:
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "text/html,application/xhtml+xml"},
    )
    for attempt in range(retries + 1):
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                charset = response.headers.get_content_charset() or "utf-8"
                return response.read().decode(charset, errors="replace")
        except (urllib.error.URLError, TimeoutError, OSError):
            if attempt >= retries:
                raise
            time.sleep(min(2 ** attempt, 16) + random.random())
    raise RuntimeError("unreachable")


def collect_year(
    year: int,
    *,
    delay: float,
    timeout: float,
    retries: int,
    keep_html: bool,
    retry_missing: bool,
    limit: int | None,
) -> dict:
    organ_path = DATA_DIR / f"organ_{year}.json"
    if not organ_path.exists():
        raise FileNotFoundError(
            f"{organ_path} 없음: 먼저 python tool/backtest/fetch_data.py --years {year} 실행"
        )
    entries = json.loads(organ_path.read_text(encoding="utf-8"))
    races = enumerate_races(entries)
    checkpoint_path = DATA_DIR / "checkpoints" / f"kcycle_{year}.json"
    state = (
        json.loads(checkpoint_path.read_text(encoding="utf-8"))
        if checkpoint_path.exists()
        else {"completed": {}, "failures": {}}
    )
    completed: dict[str, dict] = state.setdefault("completed", {})
    failures: dict[str, str] = state.setdefault("failures", {})
    attempted = 0

    for index, race in enumerate(races, 1):
        key = f"{race['date']}/{race['meet']}/{race['race_no']:02d}"
        previous = completed.get(key)
        if previous and not (retry_missing and previous.get("status") in {"missing", "odds_missing"}):
            continue
        if limit is not None and attempted >= limit:
            break
        url = race_url(race)
        try:
            html_text = download(url, timeout, retries)
            normalized = normalize_official_race(race, html_text, url)
            completed[key] = normalized
            failures.pop(key, None)
            if keep_html:
                raw_path = DATA_DIR / "raw" / str(year) / f"{key.replace('/', '_')}.html"
                raw_path.parent.mkdir(parents=True, exist_ok=True)
                raw_path.write_text(html_text, encoding="utf-8")
            label = normalized["status"]
        except Exception as error:
            failures[key] = f"{type(error).__name__}: {error}"
            label = "error"
        attempted += 1
        write_json(checkpoint_path, state)
        print(f"[{index}/{len(races)}] {key}: {label}")
        time.sleep(max(delay, 0))

    output = sorted(
        completed.values(),
        key=lambda race: (race["date"], race["meet"], race["race_no"]),
    )
    write_json(DATA_DIR / f"kcycle_results_{year}.json", output)
    report = {
        "year": year,
        "expected_races": len(races),
        "collected_races": len(output),
        "failed_requests": len(failures),
        "status": dict(sorted(_counts(race["status"] for race in output).items())),
        "failures": failures,
    }
    write_json(DATA_DIR / "reports" / f"collection_{year}.json", report, indent=2)
    return report


def _counts(values) -> dict[str, int]:
    counts: dict[str, int] = {}
    for value in values:
        counts[value] = counts.get(value, 0) + 1
    return counts


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--years", type=parse_years, default=parse_years("2021-2026"))
    parser.add_argument("--delay", type=float, default=0.35)
    parser.add_argument("--timeout", type=float, default=20)
    parser.add_argument("--retries", type=int, default=3)
    parser.add_argument("--keep-html", action="store_true")
    parser.add_argument("--retry-missing", action="store_true")
    parser.add_argument("--limit", type=int)
    args = parser.parse_args()

    for year in args.years:
        report = collect_year(
            year,
            delay=args.delay,
            timeout=args.timeout,
            retries=args.retries,
            keep_html=args.keep_html,
            retry_missing=args.retry_missing,
            limit=args.limit,
        )
        print(
            f"{year}: {report['collected_races']}/{report['expected_races']}경주, "
            f"요청 실패 {report['failed_requests']}건"
        )


if __name__ == "__main__":
    main()
