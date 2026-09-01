"""선형(조건부 로짓) 모델이 충분한지 비선형 모델과 비교해 상한을 가늠한다.

사용:
    python tool/backtest/headroom.py
"""

from __future__ import annotations

import os

import numpy as np
from sklearn.ensemble import HistGradientBoostingClassifier

from evaluate import DATA_DIR, evaluate, load_races, report
from fit_model import FEATURES, prepare, race_matrix


def stack(races: list[dict]) -> tuple[np.ndarray, np.ndarray]:
    xs, ys = [], []
    for race in races:
        matrix = race["matrix"]
        xs.append(matrix)
        ys.append(np.array([1 if r["rank"] == 1 else 0 for r in race["riders"]]))
    return np.vstack(xs), np.concatenate(ys)


def main() -> None:
    train = load_races([2025])
    test = load_races([2026])
    prepare(train)
    prepare(test)
    train = [r for r in train if "matrix" in r]
    test = [r for r in test if "matrix" in r]

    train_x, train_y = stack(train)
    model = HistGradientBoostingClassifier(
        max_iter=300, learning_rate=0.06, max_leaf_nodes=15, l2_regularization=1.0,
        random_state=0,
    )
    model.fit(train_x, train_y)

    def score_race(riders: list[dict]) -> list[float]:
        matrix = race_matrix(riders)
        return list(model.predict_proba(matrix)[:, 1])

    lines = [
        f"학습 {len(train)}경주 / 검증 {len(test)}경주, 피처 {len(FEATURES)}개",
        report("그래디언트 부스팅", evaluate(test, score_race)),
    ]
    output = "\n".join(lines)
    print(output)
    open(os.path.join(DATA_DIR, "headroom.txt"), "w", encoding="utf-8").write(output)


if __name__ == "__main__":
    main()
