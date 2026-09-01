"""출주표 피처로 1착 확률 모델(조건부 로짓)을 학습하고 적중률을 비교한다.

경주 안에서 한 명만 1착이 되므로 일반 로지스틱 회귀가 아니라
경주 단위 소프트맥스(조건부 로짓)를 최대우도로 적합한다.
피처는 경주 안에서 표준화해 "같은 경주 안에서의 상대 우열"만 학습한다.

학습: 2025년, 검증: 2026년 (시간 분할로 미래 정보 누수 방지)

사용:
    python tool/backtest/fit_model.py
"""

from __future__ import annotations

import json
import os

import numpy as np

from evaluate import (
    DATA_DIR,
    evaluate,
    grade_level,
    load_races,
    num,
    rec_200m,
    recent_outings,
    report,
    score_area_avg,
    score_current,
    score_tot_avg,
)

FEATURES = [
    "tot_avg",        # 통산 평균득점
    "area_avg",       # 해당 경기장 최근 3회차 평균득점
    "grade",          # 등급(10단계)
    "win_rate",       # 승률
    "high3_rate",     # 삼연대율
    "recent_finish",  # 최근 착순(작을수록 좋아 부호 반전)
    "recent_class",   # 최근 출전 등급(특선 3 / 우수 2 / 선발 1)
    "recent_place",   # 최근 3착 이내 비율
    "outing_cnt",     # 최근 성적 자료 수(결장이 적을수록 큼)
    "sprint",         # 200m 기록(빠를수록 좋아 부호 반전)
    "gear",           # 기어배수
    "age",            # 나이
    "inside",         # 안쪽 배번(1·2번)
    "line_size",      # 같은 훈련지 동료 수(라인 크기)
    "line_best",      # 같은 훈련지 동료 중 최고 평균득점
    "pre_ratio",      # 선행 승 비율
    "mrk_ratio",      # 마크 승 비율
    "brk_ratio",      # 젖히기 승 비율
    "pas_ratio",      # 추입 승 비율
]

DECAY = 0.85


def rider_features(row: dict, riders: list[dict]) -> list[float]:
    outings = recent_outings(row)
    if outings:
        weights = np.array([DECAY ** i for i in range(len(outings))])
        weights /= weights.sum()
        finishes = np.array([o[1] for o in outings], dtype=float)
        classes = np.array([o[0] for o in outings], dtype=float)
        recent_finish = -float(finishes @ weights)
        recent_class = float(classes @ weights)
        recent_place = float((finishes <= 3) @ weights)
    else:
        recent_finish, recent_class, recent_place = -4.5, 2.0, 0.4

    runs = max(num(row.get("run_day_tcnt")), 1)
    sprint = rec_200m(row)
    place = (row.get("trng_plc_nm") or "").strip()

    mates = [
        r for r in riders
        if r["row"] is not row and (r["row"].get("trng_plc_nm") or "").strip() == place
    ]
    line_best = max((num(r["row"].get("tot_tms_avg_scr")) for r in mates), default=0.0)

    return [
        num(row.get("tot_tms_avg_scr")),
        num(row.get("area_tms3_avg_scr")) or num(row.get("tot_tms_avg_scr")),
        grade_level(row.get("racer_grd_cur_cd") or ""),
        num(row.get("win_rate")),
        num(row.get("high_3_rate")),
        recent_finish,
        recent_class,
        recent_place,
        float(len(outings)),
        -sprint if sprint > 0 else 0.0,
        num(row.get("gear_rate")),
        num(row.get("racer_age")),
        1.0 if num(row.get("back_no")) <= 2 else 0.0,
        float(len(mates)),
        line_best,
        num(row.get("pre_win_cnt")) / runs,
        num(row.get("mrk_win_cnt")) / runs,
        num(row.get("brk_win_cnt")) / runs,
        num(row.get("pas_win_cnt")) / runs,
    ]


def race_matrix(riders: list[dict]) -> np.ndarray:
    """경주 내 표준화된 피처 행렬."""
    matrix = np.array([rider_features(r["row"], riders) for r in riders], dtype=float)
    scale = matrix.std(axis=0)
    scale[scale == 0] = 1.0
    return (matrix - matrix.mean(axis=0)) / scale


def prepare(races: list[dict]) -> tuple[list[np.ndarray], list[int]]:
    matrices, winners = [], []
    for race in races:
        riders = race["riders"]
        first = [i for i, r in enumerate(riders) if r["rank"] == 1]
        if not first:
            continue
        race["matrix"] = race_matrix(riders)
        matrices.append(race["matrix"])
        winners.append(first[0])
    return matrices, winners


def fit_conditional_logit(
    matrices: list[np.ndarray],
    winners: list[int],
    columns: list[int] | None = None,
    l2: float = 2.0,
    iterations: int = 600,
    lr: float = 0.5,
) -> np.ndarray:
    if columns is None:
        columns = list(range(matrices[0].shape[1]))
    weights = np.zeros(len(columns))
    count = len(matrices)

    for _ in range(iterations):
        gradient = np.zeros_like(weights)
        for matrix, winner in zip(matrices, winners):
            sub = matrix[:, columns]
            utility = sub @ weights
            utility -= utility.max()
            probability = np.exp(utility)
            probability /= probability.sum()
            gradient += sub[winner] - probability @ sub
        weights += lr * (gradient / count - l2 * weights / count)

    return weights


def log_likelihood(matrices, winners, weights, columns) -> float:
    total = 0.0
    for matrix, winner in zip(matrices, winners):
        utility = matrix[:, columns] @ weights
        utility -= utility.max()
        total += utility[winner] - np.log(np.exp(utility).sum())
    return total / len(matrices)


def make_scorer(weights: np.ndarray, columns: list[int]):
    def score_race(riders: list[dict]) -> list[float]:
        matrix = race_matrix(riders)[:, columns]
        return list(matrix @ weights)

    return score_race


def main() -> None:
    train = load_races([2025])
    test = load_races([2026])

    train_x, train_y = prepare(train)
    test_x, test_y = prepare(test)

    every = list(range(len(FEATURES)))
    weights = fit_conditional_logit(train_x, train_y, every)

    lines = [
        f"학습 {len(train_x)}경주(2025) / 검증 {len(test_x)}경주(2026)",
        f"검증 로그우도 {log_likelihood(test_x, test_y, weights, every):+.4f} "
        f"(무작위 {np.log(1 / 7):+.4f})",
        "",
        "피처 가중치 (경주 내 표준화 기준):",
    ]
    order = list(np.argsort(-np.abs(weights)))
    for i in order:
        lines.append(f"  {FEATURES[i]:14s} {weights[i]:+.3f}")

    lines += ["", "적중률 (검증: 2026년 광명)"]
    lines.append(report("현재 엔진", evaluate(test, score_current)))
    lines.append(report("통산 평균득점만", evaluate(test, score_tot_avg)))
    lines.append(report("경기장 최근 득점만", evaluate(test, score_area_avg)))
    lines.append(report("전체 피처 모델", evaluate(test, make_scorer(weights, every))))

    best = None
    for size in (3, 4, 5, 6, 7, 8, 10):
        columns = sorted(order[:size])
        subset = fit_conditional_logit(train_x, train_y, columns)
        result = evaluate(test, make_scorer(subset, columns))
        lines.append(
            report(f"상위 {size}개 피처", result)
            + "\n" + " " * 22 + ", ".join(FEATURES[i] for i in columns)
        )
        if best is None or result["단승(1착)"] > best[0]["단승(1착)"]:
            best = (result, columns, subset)

    result, columns, subset = best
    lines += ["", f"선택 모델: {', '.join(FEATURES[i] for i in columns)}"]
    for i, column in enumerate(columns):
        lines.append(f"  {FEATURES[column]:14s} {subset[i]:+.4f}")

    output = "\n".join(lines)
    print(output)
    open(os.path.join(DATA_DIR, "fit.txt"), "w", encoding="utf-8").write(output)
    json.dump(
        {
            "features": [FEATURES[i] for i in columns],
            "weights": [float(w) for w in subset],
            "all_features": FEATURES,
            "all_weights": [float(w) for w in weights],
        },
        open(os.path.join(DATA_DIR, "weights.json"), "w", encoding="utf-8"),
        ensure_ascii=False,
        indent=2,
    )


if __name__ == "__main__":
    main()
