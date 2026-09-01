"""백테스트용 과거 출주표·착순 데이터 수집.

공공데이터포털 경륜 API에서
  - 출주표(RACE_ORGAN): 경주 전 시점에 알 수 있는 선수 정보
  - 경주순위(RACE_RANK): 실제 착순
를 받아 `tool/backtest/data/` 아래에 JSON으로 저장한다.

사용:
    python tool/backtest/fetch_data.py
"""

from __future__ import annotations

import json
import os
import sys
import time
import urllib.parse
import urllib.request
from collections import defaultdict

SERVICE_KEY = os.environ.get(
    "CYCLING_SERVICE_KEY",
    "788d1f62af9d665d2f002057f9526ac8f2776910fef87b0e95d27e232fe0967f",
)
BASE = "https://apis.data.go.kr/B551014"
ORGAN = f"{BASE}/SRVC_OD_API_CRA_RACE_ORGAN/TODZ_API_CRA_RACE_ORGAN_I"
RANK = f"{BASE}/SRVC_CRA_RACE_RANK/TODZ_CRA_RACE_RANK"

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")


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


def fetch_organ(year: int, meet: int) -> list[dict]:
    """연도·경기장 전체 출주표를 페이징으로 모두 받는다."""
    rows: list[dict] = []
    total = 0
    page = 1
    while True:
        payload = _get(ORGAN, stnd_yr=year, meet=meet, pageNo=page, numOfRows=1000)
        if page == 1:
            total = int(payload["response"]["body"].get("totalCount", 0))
            print(f"출주표 {year} meet={meet}: 총 {total}건")
        batch = _items(payload)
        if not batch:
            break
        rows.extend(batch)
        print(f"  page {page}: {len(rows)}/{total}")
        if len(rows) >= total:
            break
        page += 1
    return rows


def fetch_ranks(year: int, dates: list[str]) -> list[dict]:
    """날짜별 착순을 모은다. 한 번의 호출로 그날 전 경기장·전 경주가 온다."""
    rows: list[dict] = []
    for i, date in enumerate(dates, 1):
        payload = _get(RANK, stnd_year=year, race_day=date, pageNo=1, numOfRows=1000)
        batch = [r for r in _items(payload) if r.get("race_day") == date]
        rows.extend(batch)
        print(f"  [{i}/{len(dates)}] {date}: {len(batch)}건")
    return rows


def main() -> None:
    os.makedirs(DATA_DIR, exist_ok=True)
    years = [2025, 2026]

    for year in years:
        organ_path = os.path.join(DATA_DIR, f"organ_{year}.json")
        if os.path.exists(organ_path):
            print(f"{organ_path} 이미 존재 - 건너뜀")
            organ = json.load(open(organ_path, encoding="utf-8"))
        else:
            organ = fetch_organ(year, meet=1)
            json.dump(organ, open(organ_path, "w", encoding="utf-8"), ensure_ascii=False)

        dates = sorted({row["race_ymd"].replace(".", "") for row in organ if row.get("race_ymd")})
        print(f"{year}: 개최일 {len(dates)}일")

        rank_path = os.path.join(DATA_DIR, f"rank_{year}.json")
        if os.path.exists(rank_path):
            print(f"{rank_path} 이미 존재 - 건너뜀")
            continue
        ranks = fetch_ranks(year, dates)
        json.dump(ranks, open(rank_path, "w", encoding="utf-8"), ensure_ascii=False)

        by_race = defaultdict(int)
        for row in ranks:
            by_race[(row.get("meet_nm"), row.get("race_day"), row.get("race_no"))] += 1
        print(f"{year}: 착순 {len(ranks)}건 / 경주 {len(by_race)}개")


if __name__ == "__main__":
    main()
