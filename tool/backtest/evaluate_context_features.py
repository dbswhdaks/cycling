"""낙차·상대전적 피처의 시간 분리 증분 효과를 평가한다."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from evaluate import evaluate, load_races
from fit_model import FEATURES as BASE_FEATURES
from fit_model import fit_conditional_logit, race_matrix
from kcycle_data import MEETS, write_json
from retrain_evaluate import APP_WEIGHTS, compact_metrics

DATA_DIR = Path(__file__).resolve().parent / "data"
PAIR_FEATURES = [
    "opponent_win_rate",
    "opponent_top3_pair_rate",
    "opponent_history_coverage",
]
INJURY_FEATURES = [
    "days_since_fall",
    "falls_30d",
    "falls_90d",
    "severe_injury_30d",
]
CONTEXT_FEATURES = PAIR_FEATURES + INJURY_FEATURES
CANDIDATES = {
    "base": [],
    "base_pairwise": PAIR_FEATURES,
    "base_injury": INJURY_FEATURES,
    "base_all_context": CONTEXT_FEATURES,
}


def context_matrix(riders: list[dict], features: list[str]) -> np.ndarray:
    base = race_matrix(riders)
    if not features:
        return base
    values = np.array(
        [
            [float(rider["row"].get(feature, 0.0) or 0.0) for feature in features]
            for rider in riders
        ],
        dtype=float,
    )
    scale = values.std(axis=0)
    scale[scale == 0] = 1.0
    normalized = (values - values.mean(axis=0)) / scale
    return np.column_stack((base, normalized))


def prepare_context(
    races: list[dict],
    features: list[str],
) -> tuple[list[np.ndarray], list[int]]:
    matrices, winners = [], []
    for race in races:
        winner = next(
            (index for index, rider in enumerate(race["riders"]) if rider["rank"] == 1),
            None,
        )
        if winner is None:
            continue
        matrices.append(context_matrix(race["riders"], features))
        winners.append(winner)
    return matrices, winners


def scorer(weights: np.ndarray, features: list[str]):
    def score_race(riders: list[dict]) -> list[float]:
        return list(context_matrix(riders, features) @ weights)

    return score_race


def by_venue(races: list[dict], score_race) -> dict:
    return {
        config["name"]: compact_metrics(
            evaluate([race for race in races if race.get("meet") == meet], score_race)
        )
        for meet, config in MEETS.items()
    }


def main() -> None:
    argparse.ArgumentParser(description=__doc__).parse_args()
    missing = [
        DATA_DIR / f"joined_context_{year}.json" for year in range(2021, 2027)
        if not (DATA_DIR / f"joined_context_{year}.json").exists()
    ]
    if missing:
        raise FileNotFoundError(
            "보강 데이터 없음: "
            + ", ".join(str(path) for path in missing)
            + ". context_features.py를 먼저 실행하세요."
        )
    train = load_races([2021, 2022, 2023, 2024], context=True)
    validation = load_races([2025], context=True)
    test = load_races([2026], context=True)
    if not train or not validation or not test:
        raise RuntimeError(
            f"보강 데이터 부족: 학습 {len(train)}, 검증 {len(validation)}, "
            f"테스트 {len(test)}경주. context_features.py를 먼저 실행하세요."
        )

    candidates = []
    for name, features in CANDIDATES.items():
        train_x, train_y = prepare_context(train, features)
        weights = fit_conditional_logit(train_x, train_y)
        score_race = scorer(weights, features)
        result = compact_metrics(evaluate(validation, score_race))
        candidates.append({"name": name, "features": features, "validation": result})

    selected = max(
        candidates,
        key=lambda candidate: (
            candidate["validation"]["win"],
            candidate["validation"]["quinella"],
            candidate["validation"]["trio"],
        ),
    )
    selected_features = selected["features"]
    development_x, development_y = prepare_context(train + validation, selected_features)
    final_weights = fit_conditional_logit(development_x, development_y)
    final_scorer = scorer(final_weights, selected_features)

    app_scorer = scorer(np.array(APP_WEIGHTS, dtype=float), [])
    app_test = compact_metrics(evaluate(test, app_scorer))
    selected_test = compact_metrics(evaluate(test, final_scorer))
    improved = (
        selected_test["win"] > app_test["win"]
        and selected_test["quinella"] >= app_test["quinella"]
        and selected_test["exacta"] >= app_test["exacta"]
        and selected_test["trio"] >= app_test["trio"]
    )
    report = {
        "split": {
            "train": {"years": [2021, 2022, 2023, 2024], "races": len(train)},
            "validation": {"years": [2025], "races": len(validation)},
            "test": {"years": [2026], "races": len(test)},
        },
        "candidates": candidates,
        "selected": selected["name"],
        "selected_features": selected_features,
        "test": {"current_app": app_test, "selected": selected_test},
        "selected_by_venue": by_venue(test, final_scorer),
        "holdout_improved_without_regression": improved,
    }
    model = {
        "features": BASE_FEATURES + selected_features,
        "weights": [float(value) for value in final_weights],
        "eligible_for_app_integration": improved,
    }
    write_json(DATA_DIR / "context_weights.json", model, indent=2)
    write_json(DATA_DIR / "reports" / "context_evaluation.json", report, indent=2)
    print(json.dumps(report, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
