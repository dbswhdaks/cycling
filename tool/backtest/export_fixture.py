"""Dart 회귀 테스트용 경주 픽스처를 만든다.

앱의 출주표 파싱 → 예측 엔진 경로를 그대로 통과시켜야 하므로
공공데이터 API의 원본 필드명을 유지한 채 필요한 항목만 추린다.

사용:
    python tool/backtest/export_fixture.py
"""

from __future__ import annotations

import json
import os

from evaluate import load_races

FIXTURE = os.path.join(
    os.path.dirname(__file__), "..", "..", "test", "fixtures", "backtest_races.json"
)

# 예측 엔진이 실제로 사용하는 필드만 남긴다.
KEEP = [
    "back_no", "racer_nm", "racer_grd_cd", "racer_grd_cur_cd",
    "tot_tms_avg_scr", "area_tms3_avg_scr", "win_rate",
    "rec_200m_scr", "racer_age", "trng_plc_nm",
    "run_day_tcnt", "pre_win_cnt", "brk_win_cnt", "mrk_win_cnt", "pas_win_cnt",
] + [f"bf{tms}_day{day}_rank" for tms in (1, 2, 3) for day in (1, 2, 3)]

SAMPLE = 200


def main() -> None:
    races = load_races([2026])
    # 연중 고르게 뽑아 특정 시기에 치우치지 않게 한다.
    step = max(len(races) // SAMPLE, 1)
    sampled = races[::step][:SAMPLE]

    payload = []
    for race in sampled:
        payload.append(
            {
                "date": race["date"],
                "race_no": race["race_no"],
                "entries": [
                    {
                        key: r["row"][key]
                        for key in KEEP
                        if str(r["row"].get(key, "")).strip()
                    }
                    for r in race["riders"]
                ],
                "finish": {r["name"]: r["rank"] for r in race["riders"]},
            }
        )

    os.makedirs(os.path.dirname(FIXTURE), exist_ok=True)
    with open(FIXTURE, "w", encoding="utf-8") as f:
        json.dump(payload, f, ensure_ascii=False, separators=(",", ":"))

    size = os.path.getsize(FIXTURE) / 1024
    print(f"{len(payload)}개 경주 저장 ({size:.0f} KB)")


if __name__ == "__main__":
    main()
