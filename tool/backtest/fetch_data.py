"""공공데이터포털의 3개 경기장 과거 출주표·착순 데이터 수집.

페이지/날짜 단위 체크포인트를 저장하므로 중단한 명령을 그대로 다시 실행하면
완료한 요청 다음부터 이어진다.

사용:
    python tool/backtest/fetch_data.py --years 2021-2026
    python tool/backtest/fetch_data.py --years 2026 --refresh
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.parse
import urllib.request
import argparse
from collections import defaultdict
from pathlib import Path

from kcycle_data import MEET_ALIASES, parse_lepopark_entries

SERVICE_KEY = os.environ.get(
    "CYCLING_SERVICE_KEY",
    "788d1f62af9d665d2f002057f9526ac8f2776910fef87b0e95d27e232fe0967f",
)
BASE = "https://apis.data.go.kr/B551014"
ORGAN = f"{BASE}/SRVC_OD_API_CRA_RACE_ORGAN/TODZ_API_CRA_RACE_ORGAN_I"
RANK = f"{BASE}/SRVC_CRA_RACE_RANK/TODZ_CRA_RACE_RANK"

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
MEETS = {1: "광명", 2: "창원", 3: "부산"}
LEPOPARK_URLS = (
    "https://www.lepopark.or.kr/race/entrant/{date}",
    "https://www.lepopark.or.kr/race/entrant-unfix/{date}",
)


def _get(url: str, **params) -> dict:
    params.setdefault("serviceKey", SERVICE_KEY)
    params.setdefault("resultType", "json")
    query = urllib.parse.urlencode(params)
    for attempt in range(4):
        try:
            with urllib.request.urlopen(f"{url}?{query}", timeout=40) as res:
                return json.loads(res.read().decode("utf-8"))
        except Exception as err:  # 공공 API는 간헐적으로 끊긴다.
            if attempt == 3:
                raise
            print(f"  재시도 {attempt + 1}: {err}", file=sys.stderr)
            time.sleep(2 * (attempt + 1))
    return {}


def _items(payload: dict) -> list[dict]:
    body = payload.get("response", {}).get("body", {})
    items = body.get("items")
    if not items:
        return []
    item = items.get("item") if isinstance(items, dict) else items
    if isinstance(item, dict):
        return [item]
    return [row for row in (item or []) if isinstance(row, dict)]


def _get_html(url: str) -> str:
    request = urllib.request.Request(
        url,
        headers={
            "Accept": "text/html,application/xhtml+xml",
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) CyclingBacktest/1.0",
        },
    )
    for attempt in range(4):
        try:
            with urllib.request.urlopen(request, timeout=40) as response:
                charset = response.headers.get_content_charset() or "utf-8"
                return response.read().decode(charset, errors="replace")
        except Exception:
            if attempt == 3:
                raise
            time.sleep(2 * (attempt + 1))
    return ""


def _write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_suffix(path.suffix + ".tmp")
    temporary.write_text(json.dumps(value, ensure_ascii=False), encoding="utf-8")
    temporary.replace(path)


def _load_json(path: Path, default):
    if not path.exists():
        return default
    return json.loads(path.read_text(encoding="utf-8"))


def _years(value: str) -> list[int]:
    years: set[int] = set()
    for part in value.split(","):
        bounds = part.strip().split("-", 1)
        start = int(bounds[0])
        end = int(bounds[-1])
        years.update(range(min(start, end), max(start, end) + 1))
    return sorted(years)


def fetch_organ(
    year: int,
    meet: int,
    checkpoint: Path | None = None,
    request_delay: float = 0.2,
) -> list[dict]:
    """공공 API 출주표를 받되 응답의 실제 경기장명을 신뢰한다."""
    state = _load_json(checkpoint, {}) if checkpoint else {}
    rows: list[dict] = state.get("rows", [])
    total = 0
    page = int(state.get("next_page", 1))
    while True:
        payload = _get(ORGAN, stnd_yr=year, meet=meet, pageNo=page, numOfRows=1000)
        if not total:
            total = int(payload.get("response", {}).get("body", {}).get("totalCount", 0))
            print(f"출주표 {year} meet={meet}: 총 {total}건")
        batch = _items(payload)
        if not batch:
            break
        for row in batch:
            actual_meet = MEET_ALIASES.get(str(row.get("meet_nm") or "").strip(), 0)
            if actual_meet:
                row["_meet"] = actual_meet
                row["_meet_nm"] = MEETS[actual_meet]
        rows.extend(batch)
        print(f"  page {page}: {len(rows)}/{total}")
        if checkpoint:
            _write_json(checkpoint, {"next_page": page + 1, "rows": rows})
        if len(rows) >= total:
            break
        page += 1
        time.sleep(request_delay)
    return rows


def fetch_scraped_entries(
    year: int,
    dates: list[str],
    date_metadata: dict[str, tuple[str, str]],
    checkpoint: Path,
    request_delay: float,
) -> list[dict]:
    """날짜별 레포츠파크 출주표에서 창원·부산을 수집한다."""
    state = _load_json(checkpoint, {})
    rows: list[dict] = state.get("rows", [])
    completed = set(state.get("completed_dates", []))
    pending = [date for date in dates if date not in completed]
    for index, date in enumerate(pending, 1):
        batch = []
        for template in LEPOPARK_URLS:
            try:
                batch = parse_lepopark_entries(_get_html(template.format(date=date)), date)
            except Exception as error:
                print(f"  레포츠파크 {date} 재시도: {error}", file=sys.stderr)
            if batch:
                break
        period, day = date_metadata.get(date, ("", ""))
        for row in batch:
            row["stnd_yr"] = str(year)
            row["period_no"] = period
            row["day_tcnt"] = day
        rows.extend(batch)
        completed.add(date)
        _write_json(checkpoint, {"completed_dates": sorted(completed), "rows": rows})
        counts = {meet: sum(int(row["_meet"]) == meet for row in batch) for meet in (2, 3)}
        print(f"  [{index}/{len(pending)}] {date}: 창원 {counts[2]}명, 부산 {counts[3]}명")
        time.sleep(request_delay)
    return rows


def fetch_ranks(
    year: int,
    dates: list[str],
    checkpoint: Path | None = None,
    request_delay: float = 0.2,
) -> list[dict]:
    """날짜별 착순을 모은다. 한 번의 호출로 그날 전 경기장·전 경주가 온다."""
    state = _load_json(checkpoint, {}) if checkpoint else {}
    rows: list[dict] = state.get("rows", [])
    completed = set(state.get("completed_dates", []))
    pending = [date for date in dates if date not in completed]
    for i, date in enumerate(pending, 1):
        payload = _get(RANK, stnd_year=year, race_day=date, pageNo=1, numOfRows=1000)
        batch = [r for r in _items(payload) if r.get("race_day") == date]
        rows.extend(batch)
        completed.add(date)
        print(f"  [{i}/{len(pending)}] {date}: {len(batch)}건")
        if checkpoint:
            _write_json(
                checkpoint,
                {"completed_dates": sorted(completed), "rows": rows},
            )
        time.sleep(request_delay)
    return rows


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--years", default="2021-2026", type=_years)
    parser.add_argument("--meets", default="1,2,3", type=lambda s: [int(x) for x in s.split(",")])
    parser.add_argument("--delay", default=0.2, type=float)
    parser.add_argument("--refresh", action="store_true")
    args = parser.parse_args()
    data_dir = Path(DATA_DIR)
    checkpoint_dir = data_dir / "checkpoints"
    data_dir.mkdir(parents=True, exist_ok=True)

    for year in args.years:
        organ_path = data_dir / f"organ_{year}.json"
        if organ_path.exists() and not args.refresh:
            print(f"{organ_path} 이미 존재 - 건너뜀")
            organ = _load_json(organ_path, [])
        else:
            # 이 API는 meet=2/3도 광명을 반환한다. 한 번만 받고 실제 meet_nm으로
            # 판별하며 창원·부산은 공식 레포츠파크 출주표로 보완한다.
            public_checkpoint = checkpoint_dir / f"organ_public_{year}.json"
            scrape_checkpoint = checkpoint_dir / f"organ_scraped_{year}.json"
            if args.refresh:
                for checkpoint in (public_checkpoint, scrape_checkpoint):
                    if checkpoint.exists():
                        checkpoint.unlink()
            public = fetch_organ(year, 1, public_checkpoint, args.delay)
            dates = sorted(
                {row["race_ymd"].replace(".", "") for row in public if row.get("race_ymd")}
            )
            date_metadata = {}
            for row in public:
                date = str(row.get("race_ymd") or "").replace(".", "")
                if date:
                    date_metadata[date] = (
                        str(row.get("period_no") or ""),
                        str(row.get("day_tcnt") or ""),
                    )
            scraped = (
                fetch_scraped_entries(
                    year, dates, date_metadata, scrape_checkpoint, args.delay
                )
                if set(args.meets) & {2, 3}
                else []
            )
            organ = [
                row
                for row in public + scraped
                if int(row.get("_meet") or 0) in args.meets
            ]
            unique = {}
            for row in organ:
                key = (
                    row.get("race_ymd"),
                    row.get("_meet"),
                    row.get("race_no"),
                    row.get("back_no"),
                )
                unique[key] = row
            organ = list(unique.values())
            _write_json(organ_path, organ)

        dates = sorted({row["race_ymd"].replace(".", "") for row in organ if row.get("race_ymd")})
        print(f"{year}: 개최일 {len(dates)}일")

        rank_path = data_dir / f"rank_{year}.json"
        if rank_path.exists() and not args.refresh:
            print(f"{rank_path} 이미 존재 - 건너뜀")
            continue
        rank_checkpoint = checkpoint_dir / f"rank_{year}.json"
        if args.refresh and rank_checkpoint.exists():
            rank_checkpoint.unlink()
        ranks = fetch_ranks(year, dates, rank_checkpoint, args.delay)
        _write_json(rank_path, ranks)

        by_race = defaultdict(int)
        for row in ranks:
            by_race[(row.get("meet_nm"), row.get("race_day"), row.get("race_no"))] += 1
        print(f"{year}: 착순 {len(ranks)}건 / 경주 {len(by_race)}개")


if __name__ == "__main__":
    main()
