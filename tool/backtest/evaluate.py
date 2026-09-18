"""출주표 기반 예측 모델의 적중률을 과거 경주로 측정한다.

- 입력: `fetch_data.py`가 저장한 출주표·착순 JSON
- 출력: 모델별 단승/연대/삼복승 적중률

사용:
    python tool/backtest/evaluate.py
"""

from __future__ import annotations

import json
import os
import re
from collections import defaultdict

DATA_DIR = os.path.join(os.path.dirname(__file__), "data")
MEET_NAMES = {1: "광명", 2: "창원", 3: "부산"}


# ─────────────────────────── 데이터 적재 ───────────────────────────


def _load_joined(year: int, context: bool = False) -> list[dict]:
    prefix = "joined_context" if context else "joined"
    path = os.path.join(DATA_DIR, f"{prefix}_{year}.json")
    if not os.path.exists(path):
        return []
    payload = json.load(open(path, encoding="utf-8"))
    races = []
    for race in payload:
        riders = []
        for rider in race.get("pre_race", {}).get("riders", []):
            result = rider.get("result")
            if not result:
                continue
            rank = int(result.get("rank") or 99)
            riders.append(
                {
                    "row": rider.get("pre_race", {}),
                    "name": rider.get("racer_nm", ""),
                    "racer_no": rider.get("racer_no", ""),
                    "back_no": int(rider.get("back_no") or 0),
                    "rank": rank if rank > 0 else 99,
                }
            )
        placed = {rider["rank"] for rider in riders}
        if len(riders) >= 5 and {1, 2, 3} <= placed:
            races.append(
                {
                    "date": race["date"],
                    "race_no": int(race["race_no"]),
                    "year": year,
                    "meet": int(race["meet"]),
                    "meet_nm": race.get("meet_nm") or MEET_NAMES.get(int(race["meet"]), ""),
                    "odds": race.get("post_race", {}).get("odds", {}),
                    "riders": riders,
                }
            )
    return races


def load_races(
    years: list[int],
    meets: set[int] | None = None,
    context: bool = False,
) -> list[dict]:
    """3개 경기장의 출주 전 피처와 실제 착순을 합친 경주 목록."""
    races: list[dict] = []

    for year in years:
        joined = _load_joined(year, context)
        if joined:
            races.extend(race for race in joined if meets is None or race["meet"] in meets)
            continue
        organ = json.load(open(f"{DATA_DIR}/organ_{year}.json", encoding="utf-8"))
        ranks = json.load(open(f"{DATA_DIR}/rank_{year}.json", encoding="utf-8"))

        actual: dict[tuple[str, int], dict[str, int]] = defaultdict(dict)
        for row in ranks:
            key = (row["race_day"], int(row["race_no"]))
            actual[key][(row.get("racer_nm") or "").strip()] = int(row.get("race_rank") or 0)

        grouped: dict[tuple[str, int], list[dict]] = defaultdict(list)
        for row in organ:
            date = (row.get("race_ymd") or "").replace(".", "")
            if not date:
                continue
            grouped[(date, int(row["race_no"]))].append(row)

        for (date, race_no), entries in grouped.items():
            finish = actual.get((date, race_no))
            if not finish:
                continue
            riders = []
            for row in entries:
                name = (row.get("racer_nm") or "").strip()
                rank = finish.get(name)
                if rank is None:
                    continue
                riders.append({"row": row, "name": name, "rank": rank if rank > 0 else 99})
            placed = {r["rank"] for r in riders}
            if len(riders) < 5 or not {1, 2, 3} <= placed:
                continue
            races.append(
                {
                    "date": date,
                    "race_no": race_no,
                    "year": year,
                    "meet": 1,
                    "meet_nm": "광명",
                    "odds": {},
                    "riders": riders,
                }
            )

    races.sort(key=lambda r: (r["date"], r["race_no"]))
    return races


# ─────────────────────────── 값 파싱 ───────────────────────────


def num(value, default: float = 0.0) -> float:
    try:
        return float(str(value).strip())
    except (TypeError, ValueError):
        return default


_BF_PATTERN = re.compile(r"(특선|우수|선발)?\s*(\d+)\s*-\s*(\d+)")
_CLASS_VALUE = {"특선": 3.0, "우수": 2.0, "선발": 1.0}


def recent_outings(row: dict) -> list[tuple[float, int]]:
    """직전 3회차 × 3일차 성적을 최근 순으로 (등급값, 착순)으로 반환."""
    out: list[tuple[float, int]] = []
    for tms in (1, 2, 3):
        for day in (3, 2, 1):
            raw = str(row.get(f"bf{tms}_day{day}_rank") or "")
            matched = _BF_PATTERN.search(raw)
            if not matched:
                continue
            finish = int(matched.group(3))
            if not 1 <= finish <= 9:
                continue
            out.append((_CLASS_VALUE.get(matched.group(1) or "", 2.0), finish))
    return out


def rec_200m(row: dict) -> float:
    """`12"00` → 12.00초. 값이 없으면 0."""
    matched = re.match(r'(\d+)"(\d+)', str(row.get("rec_200m_scr") or ""))
    return float(f"{matched.group(1)}.{matched.group(2)}") if matched else 0.0


# 앱에 반영된 기존 등급표(S 계열을 한 덩어리로 취급, A3 누락)
LEGACY_GRADE_SCORES = {"S": 10.0, "A1": 8.5, "A2": 7.0, "B1": 5.5, "B2": 4.0, "B3": 2.5}

# 실제 등급 체계는 SS·S1~S3·A1~A3·B1~B3의 10단계다.
GRADE_LEVELS = {
    "SS": 10.0, "S1": 9.0, "S2": 8.0, "S3": 7.0,
    "A1": 6.0, "A2": 5.0, "A3": 4.0,
    "B1": 3.0, "B2": 2.0, "B3": 1.0,
}


def legacy_grade_score(grade: str) -> float:
    g = (grade or "").strip().upper()
    if g.startswith("S"):
        return LEGACY_GRADE_SCORES["S"]
    return LEGACY_GRADE_SCORES.get(g, 4.0)


def grade_level(grade: str) -> float:
    return GRADE_LEVELS.get((grade or "").strip().upper(), 5.0)


def tactic_of(row: dict) -> str:
    win = num(row.get("win_tot_tcnt"))
    brk = num(row.get("brk_win_cnt"))
    mrk = num(row.get("mrk_win_cnt"))
    if brk > mrk and brk > 0:
        return "선행"
    if mrk > brk and mrk > 0:
        return "마크"
    if win > 0:
        return "추입"
    return ""


# ─────────────────────────── 기준 모델 ───────────────────────────


def score_legacy(riders: list[dict]) -> list[float]:
    """모델 적용 전 앱에서 사용하던 단순 점수식."""
    seonhaeng = sum(1 for r in riders if tactic_of(r["row"]) == "선행")
    scores = []
    for rider in riders:
        row = rider["row"]
        grade = legacy_grade_score(row.get("racer_grd_cur_cd") or "")
        avg = num(row.get("tot_tms_avg_scr"))
        avg_norm = min(max(avg / 10 if avg > 10 else avg, 0), 10)
        recent_bonus = min(max(num(row.get("pre_win_cnt")), 0), 5) * 1.8

        tactic = tactic_of(row)
        if tactic == "선행":
            tactic_score = 4.5 if seonhaeng <= 2 else 3.0
        elif tactic == "추입":
            tactic_score = 5.0 if seonhaeng >= 3 else 3.5
        elif tactic == "젖히기":
            tactic_score = 4.0
        elif tactic == "마크":
            tactic_score = 4.5 if seonhaeng >= 2 else 3.0
        else:
            tactic_score = 3.0

        lane = num(row.get("back_no"))
        lane_bonus = 1.0 if lane <= 2 else 0.7 if lane <= 4 else 0.4 if lane == 5 else 0.2

        scores.append(
            grade * 4.0 + avg_norm * 3.0 + recent_bonus * 2.2 + tactic_score * 1.5 + lane_bonus
        )
    return scores


def score_tot_avg(riders: list[dict]) -> list[float]:
    """참고용 단일 피처 - 통산 평균득점."""
    return [num(r["row"].get("tot_tms_avg_scr")) for r in riders]


def score_area_avg(riders: list[dict]) -> list[float]:
    """참고용 단일 피처 - 해당 경기장 최근 3회차 평균득점."""
    return [
        num(r["row"].get("area_tms3_avg_scr")) or num(r["row"].get("tot_tms_avg_scr"))
        for r in riders
    ]


# ─────────────────────────── 평가 ───────────────────────────


def evaluate(races: list[dict], score_race) -> dict:
    stats = defaultdict(int)

    for race in races:
        riders = race["riders"]
        scores = score_race(riders)
        order = sorted(range(len(riders)), key=lambda i: -scores[i])
        finish = [riders[i]["rank"] for i in order]

        stats["races"] += 1
        stats["win"] += finish[0] == 1
        stats["quinella_top"] += finish[0] <= 2
        stats["show"] += finish[0] <= 3
        if len(finish) >= 2:
            stats["exacta_box"] += {finish[0], finish[1]} == {1, 2}
            stats["exacta"] += finish[0] == 1 and finish[1] == 2
        if len(finish) >= 3:
            stats["trio"] += set(finish[:3]) == {1, 2, 3}

    total = max(stats["races"], 1)
    return {
        "races": stats["races"],
        "단승(1착)": stats["win"] / total * 100,
        "연승(2착내)": stats["quinella_top"] / total * 100,
        "복승(3착내)": stats["show"] / total * 100,
        "쌍복승(1·2착)": stats["exacta_box"] / total * 100,
        "쌍승(순서)": stats["exacta"] / total * 100,
        "삼복승(1~3착)": stats["trio"] / total * 100,
    }


def report(name: str, result: dict) -> str:
    parts = [f"{key} {value:5.1f}%" for key, value in result.items() if key != "races"]
    return f"{name:20s} n={result['races']:5d}  " + "  ".join(parts)


def main() -> None:
    races = load_races([2025, 2026])
    lines = [f"평가 대상 경주: {len(races)}개 (광명, 2025~2026)", ""]
    for name, fn in [
        ("이전 단순 엔진", score_legacy),
        ("통산 평균득점만", score_tot_avg),
        ("경기장 최근 득점만", score_area_avg),
    ]:
        lines.append(report(name, evaluate(races, fn)))

    output = "\n".join(lines)
    print(output)
    open(os.path.join(DATA_DIR, "baseline.txt"), "w", encoding="utf-8").write(output)


if __name__ == "__main__":
    main()
