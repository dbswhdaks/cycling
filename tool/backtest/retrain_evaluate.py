"""2021~2024 학습, 2025 검증, 2026 최종 테스트 모델 비교."""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

import numpy as np

from evaluate import evaluate, load_races, score_legacy
from fit_model import FEATURES, fit_conditional_logit, make_scorer, prepare
from kcycle_data import MEETS, write_json

DATA_DIR = Path(__file__).resolve().parent / "data"
APP_ENGINE = Path(__file__).resolve().parents[2] / "lib" / "core" / "services" / "prediction_engine.dart"
DEFAULT_CANDIDATES = (5, 8, 10, 14, len(FEATURES))
APP_WEIGHTS = [
    0.890101, 0.304633, 0.157661, 0.148355, -0.035848, -0.105133, 0.103959,
    0.016605, 0.016626, 0.119549, 0.066510, -0.147109, 0.020066, 0.146972,
    -0.098302, 0.028529, -0.183211, 0.052105, 0.053531,
]
FEATURE_ENUMS = {
    "tot_avg": "totalAvgScore",
    "area_avg": "areaAvgScore",
    "grade": "riderGrade",
    "win_rate": "winRate",
    "high3_rate": "top3Rate",
    "recent_finish": "recentFinish",
    "recent_class": "recentClass",
    "recent_place": "recentPlace",
    "outing_cnt": "outingCount",
    "sprint": "sprint",
    "gear": "gearRatio",
    "age": "age",
    "inside": "insideNumber",
    "line_size": "lineSize",
    "line_best": "lineBestScore",
    "pre_ratio": "leadWinRatio",
    "mrk_ratio": "markWinRatio",
    "brk_ratio": "breakWinRatio",
    "pas_ratio": "passWinRatio",
}


def compact_metrics(result: dict) -> dict:
    """실제 구매 조합 기준 단승·복승·쌍승·삼복승 적중률."""
    return {
        "races": result["races"],
        "win": result["단승(1착)"],
        "quinella": result["쌍복승(1·2착)"],
        "exacta": result["쌍승(순서)"],
        "trio": result["삼복승(1~3착)"],
    }


def score_key(result: dict) -> tuple[float, float, float]:
    return (result["win"], result["quinella"], result["trio"])


def load_existing_scorer():
    """현재 앱 PredictionEngine에 배포된 19개 피처 모델."""
    return make_scorer(np.array(APP_WEIGHTS, dtype=float), list(range(len(FEATURES))))


def promote_to_app(features: list[str], weights: np.ndarray) -> None:
    source = APP_ENGINE.read_text(encoding="utf-8")
    body = "\n".join(
        f"    _Feature.{FEATURE_ENUMS[name]}: {float(weight):.6f},"
        for name, weight in zip(features, weights)
    )
    pattern = re.compile(
        r"(static const Map<_Feature, double> _weights = \{\n).*?(\n  \};)",
        re.DOTALL,
    )
    updated, count = pattern.subn(rf"\g<1>{body}\g<2>", source, count=1)
    if count != 1:
        raise RuntimeError(f"앱 가중치 블록을 찾지 못함: {APP_ENGINE}")
    APP_ENGINE.write_text(updated, encoding="utf-8")


def metrics_by_venue(races: list[dict], scorer) -> dict:
    output = {}
    for meet, config in MEETS.items():
        subset = [race for race in races if race.get("meet") == meet]
        output[config["name"]] = compact_metrics(evaluate(subset, scorer))
    return output


def train_and_evaluate(promote: bool = False) -> dict:
    train = load_races([2021, 2022, 2023, 2024])
    validation = load_races([2025])
    test = load_races([2026])
    if not train or not validation or not test:
        raise RuntimeError(
            f"시간 분할 데이터 부족: 학습 {len(train)}, 검증 {len(validation)}, "
            f"테스트 {len(test)}경주"
        )

    train_x, train_y = prepare(train)
    validation_x, validation_y = prepare(validation)
    candidates = []
    all_columns = list(range(len(FEATURES)))
    full_weights = fit_conditional_logit(train_x, train_y, all_columns)
    feature_order = list(np.argsort(-np.abs(full_weights)))

    for size in DEFAULT_CANDIDATES:
        columns = sorted(feature_order[:size])
        weights = fit_conditional_logit(train_x, train_y, columns)
        scorer = make_scorer(weights, columns)
        result = compact_metrics(evaluate(validation, scorer))
        candidates.append(
            {
                "size": size,
                "features": [FEATURES[index] for index in columns],
                "weights": [float(value) for value in weights],
                "validation": result,
            }
        )
    selected = max(candidates, key=lambda candidate: score_key(candidate["validation"]))
    columns = [FEATURES.index(name) for name in selected["features"]]

    # 후보 선택이 끝난 뒤에만 검증 연도를 학습에 합치고 2026은 끝까지 홀드아웃한다.
    development_x, development_y = prepare(train + validation)
    final_weights = fit_conditional_logit(development_x, development_y, columns)
    final_scorer = make_scorer(final_weights, columns)
    legacy_test = compact_metrics(evaluate(test, score_legacy))
    final_test = compact_metrics(evaluate(test, final_scorer))
    existing_scorer = load_existing_scorer()
    existing_test = compact_metrics(evaluate(test, existing_scorer))
    benchmark = existing_test
    improved = (
        final_test["win"] > benchmark["win"]
        and final_test["quinella"] >= benchmark["quinella"]
        and final_test["exacta"] >= benchmark["exacta"]
        and final_test["trio"] >= benchmark["trio"]
    )

    report = {
        "split": {
            "train": {"years": [2021, 2022, 2023, 2024], "races": len(train_x)},
            "validation": {"years": [2025], "races": len(validation_x)},
            "test": {"years": [2026], "races": len(test)},
        },
        "selection_metric": ["win", "quinella", "trio"],
        "candidates": candidates,
        "selected_features": selected["features"],
        "models": {
            "legacy": legacy_test,
            "existing": existing_test,
            "retrained": final_test,
        },
        "retrained_by_venue": metrics_by_venue(test, final_scorer),
        "holdout_improved": improved,
        "promoted": bool(promote and improved),
    }
    weights_payload = {
        "features": selected["features"],
        "weights": [float(value) for value in final_weights],
        "trained_years": [2021, 2022, 2023, 2024, 2025],
        "holdout_year": 2026,
        "holdout_metrics": final_test,
    }
    write_json(DATA_DIR / "retrained_weights.json", weights_payload, indent=2)
    if promote and improved:
        write_json(DATA_DIR / "weights.json", weights_payload, indent=2)
        promote_to_app(selected["features"], final_weights)
    write_json(DATA_DIR / "reports" / "time_split_evaluation.json", report, indent=2)
    return report


def _format_metrics(label: str, metrics: dict | None) -> str:
    if metrics is None:
        return f"{label:12s} 기존 weights.json 없음"
    return (
        f"{label:12s} n={metrics['races']:5d} "
        f"단승 {metrics['win']:5.1f}% 복승 {metrics['quinella']:5.1f}% "
        f"쌍승 {metrics['exacta']:5.1f}% 삼복승 {metrics['trio']:5.1f}%"
    )


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--promote",
        action="store_true",
        help="2026 홀드아웃이 기존 모델보다 개선된 경우에만 weights.json 갱신",
    )
    args = parser.parse_args()
    report = train_and_evaluate(args.promote)
    print(
        f"학습/검증/테스트: {report['split']['train']['races']}/"
        f"{report['split']['validation']['races']}/{report['split']['test']['races']}경주"
    )
    for name in ("legacy", "existing", "retrained"):
        print(_format_metrics(name, report["models"][name]))
    print(f"홀드아웃 개선: {report['holdout_improved']}, 승격: {report['promoted']}")


if __name__ == "__main__":
    main()
