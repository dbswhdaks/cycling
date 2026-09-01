"""3착 이내 확률의 보정 계수를 적합한다.

1착 확률을 그대로 Plackett-Luce에 넣으면 상위권 선수의 3착 이내 확률이
과대평가된다. 효용에 배율(temperature)을 하나 두고, 실제 3착 여부에 대한
로그손실이 가장 작아지는 값을 찾는다.

학습 2025년 / 검증 2026년.

사용:
    python tool/backtest/calibrate_place.py
"""

from __future__ import annotations

import os

import numpy as np

from evaluate import DATA_DIR, load_races
from fit_model import FEATURES, prepare, race_matrix

NAMES = ["tot_avg", "area_avg", "grade", "win_rate", "recent_finish",
         "sprint", "age", "line_size", "mrk_ratio"]
WEIGHTS = np.array([0.9284, 0.3156, 0.1671, 0.1613, -0.1330,
                    0.1273, -0.1651, 0.0566, -0.2108])
COLUMNS = [FEATURES.index(name) for name in NAMES]


def top3_probabilities(probs: np.ndarray) -> np.ndarray:
    """Plackett-Luce로 각 선수의 3착 이내 확률을 계산한다."""
    count = len(probs)
    if count <= 3:
        return np.ones(count)

    result = np.zeros(count)
    for target in range(count):
        total = probs[target]
        for first in range(count):
            if first == target:
                continue
            after_first = 1 - probs[first]
            if after_first <= 0:
                continue
            total += probs[first] * probs[target] / after_first
            for second in range(count):
                if second in (first, target):
                    continue
                after_second = after_first - probs[second]
                if after_second <= 0:
                    continue
                total += (probs[first] * (probs[second] / after_first)
                          * (probs[target] / after_second))
        result[target] = min(total, 1.0)
    return result


def race_data(races: list[dict]) -> list[tuple[np.ndarray, np.ndarray]]:
    out = []
    for race in races:
        utility = race_matrix(race["riders"])[:, COLUMNS] @ WEIGHTS
        placed = np.array([1.0 if r["rank"] <= 3 else 0.0 for r in race["riders"]])
        out.append((utility, placed))
    return out


def loss(data, scale: float) -> float:
    total, count = 0.0, 0
    for utility, placed in data:
        scaled = utility * scale
        scaled -= scaled.max()
        probs = np.exp(scaled)
        probs /= probs.sum()
        top3 = np.clip(top3_probabilities(probs), 1e-6, 1 - 1e-6)
        total += -np.sum(placed * np.log(top3) + (1 - placed) * np.log(1 - top3))
        count += len(placed)
    return total / count


def summary(data, scale: float) -> tuple[float, float]:
    """1순위의 평균 예측 3착률과 실제 3착률."""
    predicted, actual = [], []
    for utility, placed in data:
        scaled = utility * scale
        scaled -= scaled.max()
        probs = np.exp(scaled)
        probs /= probs.sum()
        best = int(np.argmax(probs))
        predicted.append(top3_probabilities(probs)[best])
        actual.append(placed[best])
    return float(np.mean(predicted) * 100), float(np.mean(actual) * 100)


def main() -> None:
    train = load_races([2025])
    test = load_races([2026])
    prepare(train)
    prepare(test)
    train = [r for r in train if "matrix" in r]
    test = [r for r in test if "matrix" in r]

    train_data = race_data(train)
    test_data = race_data(test)

    candidates = np.arange(0.3, 1.61, 0.05)
    losses = [(loss(train_data, s), s) for s in candidates]
    best_loss, best_scale = min(losses)

    lines = [
        f"학습 {len(train_data)}경주 / 검증 {len(test_data)}경주",
        f"최적 배율 {best_scale:.2f} (학습 로그손실 {best_loss:.4f})",
        "",
        f"{'배율':>6} {'학습손실':>10} {'검증손실':>10} {'1순위 예측':>10} {'1순위 실제':>10}",
    ]
    for scale in [0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0, best_scale]:
        predicted, actual = summary(test_data, scale)
        lines.append(
            f"{scale:6.2f} {loss(train_data, scale):10.4f} {loss(test_data, scale):10.4f}"
            f" {predicted:9.1f}% {actual:9.1f}%"
        )

    output = "\n".join(lines)
    print(output)
    open(os.path.join(DATA_DIR, "place_calibration.txt"), "w", encoding="utf-8").write(output)


if __name__ == "__main__":
    main()
