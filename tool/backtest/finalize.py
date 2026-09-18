"""앱에 이식할 최종 피처 집합과 가중치를 확정한다.

- 후보 피처 집합을 앞뒤 양방향(2025→2026, 2026→2025)으로 검증해 안정성을 본다.
- 최종 가중치는 두 해 전체로 다시 적합한다.
- 확률 보정(예측 승률 vs 실제 적중률)도 함께 확인한다.
- 마지막에 Dart 상수로 바로 옮길 수 있는 형태로 출력한다.

사용:
    python tool/backtest/finalize.py
"""

from __future__ import annotations

import os

import numpy as np

from evaluate import DATA_DIR, evaluate, load_races, report, score_legacy, score_tot_avg
from fit_model import FEATURES, fit_conditional_logit, make_scorer, prepare, race_matrix

CANDIDATES = {
    "전체": FEATURES,
    "10개": ["tot_avg", "area_avg", "grade", "win_rate", "recent_finish",
             "sprint", "age", "line_size", "line_best", "mrk_ratio"],
    "9개(line_best 제외)": ["tot_avg", "area_avg", "grade", "win_rate", "recent_finish",
                          "sprint", "age", "line_size", "mrk_ratio"],
    "8개(recent 제외)": ["tot_avg", "area_avg", "grade", "win_rate",
                       "sprint", "age", "line_size", "mrk_ratio"],
    "6개": ["tot_avg", "area_avg", "grade", "win_rate", "sprint", "mrk_ratio"],
}


def columns_of(names: list[str]) -> list[int]:
    return [FEATURES.index(name) for name in names]


def calibration(races: list[dict], weights: np.ndarray, columns: list[int]) -> str:
    """상위 예측의 평균 예측 승률과 실제 적중률을 비교한다."""
    predicted, actual = [], []
    for race in races:
        matrix = race_matrix(race["riders"])[:, columns]
        utility = matrix @ weights
        utility -= utility.max()
        probability = np.exp(utility)
        probability /= probability.sum()
        best = int(np.argmax(probability))
        predicted.append(probability[best])
        actual.append(1.0 if race["riders"][best]["rank"] == 1 else 0.0)
    return (f"1순위 평균 예측승률 {np.mean(predicted) * 100:5.1f}% / "
            f"실제 적중률 {np.mean(actual) * 100:5.1f}%")


def main() -> None:
    y2025 = load_races([2025])
    y2026 = load_races([2026])
    x2025, w2025 = prepare(y2025)
    x2026, w2026 = prepare(y2026)

    lines = ["후보별 검증 (학습 → 검증)", ""]
    lines.append(report("이전 단순 엔진 (2026)", evaluate(y2026, score_legacy)))
    lines.append(report("통산 득점만 (2026)", evaluate(y2026, score_tot_avg)))
    lines.append("")

    for name, names in CANDIDATES.items():
        columns = columns_of(names)
        forward = fit_conditional_logit(x2025, w2025, columns)
        backward = fit_conditional_logit(x2026, w2026, columns)
        lines.append(
            report(f"{name} 25→26", evaluate(y2026, make_scorer(forward, columns)))
        )
        lines.append(
            report(f"{name} 26→25", evaluate(y2025, make_scorer(backward, columns)))
        )
        drift = np.abs(forward - backward).max()
        lines.append(f"{'':22s}가중치 최대 변동 {drift:.3f}")
        lines.append("")

    # 양방향 시간 분할에서 1착·연대·쌍승 지표가 모두 가장 높았던 전체 피처를
    # 최종 모델로 선택한다.
    final_names = CANDIDATES["전체"]
    columns = columns_of(final_names)
    both_x = x2025 + x2026
    both_y = w2025 + w2026
    final = fit_conditional_logit(both_x, both_y, columns)

    lines.append("최종 가중치 (2025+2026 전체 적합)")
    for name, weight in zip(final_names, final):
        lines.append(f"  {name:14s} {weight:+.4f}")
    lines.append("")
    lines.append("확률 보정: " + calibration(y2026, final, columns))
    lines.append("")
    lines.append("Dart 상수:")
    lines.append("  static const Map<String, double> _weights = {")
    for name, weight in zip(final_names, final):
        lines.append(f"    '{name}': {weight:.4f},")
    lines.append("  };")

    output = "\n".join(lines)
    print(output)
    open(os.path.join(DATA_DIR, "final.txt"), "w", encoding="utf-8").write(output)


if __name__ == "__main__":
    main()
