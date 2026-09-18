# KCYCLE 과거 데이터 수집·학습

경주 전에 공개된 출주표와 경주 후 KCYCLE 공식 착순·확정배당을 분리해
2021~2026년 광명·창원·부산 데이터를 재현 가능하게 수집하고 평가한다.

## 준비

- Python 3.10 이상
- `pip install -r tool/backtest/requirements.txt`
- 공공데이터포털 인증키를 `CYCLING_SERVICE_KEY` 환경변수로 설정

PowerShell:

```powershell
$env:CYCLING_SERVICE_KEY = "발급받은_인증키"
```

bash:

```bash
export CYCLING_SERVICE_KEY="발급받은_인증키"
```

`tool/backtest/data/`는 원본·체크포인트·학습 산출물을 포함하며 Git에서
제외된다.

## 전체 실행

프로젝트 루트에서 다음 순서로 실행한다.

```bash
# 1. 광명 공공 API + 창원·부산 레포츠파크 출주표와 공공 순위 수집
python tool/backtest/fetch_data.py --years 2021-2026 --meets 1,2,3

# 기존 organ_YYYY.json이 광명 전용 구형 파일이면 한 번만 새로 수집
python tool/backtest/fetch_data.py --years 2021-2026 --meets 1,2,3 --refresh

# 2. KCYCLE 공식 착순·확정배당 수집
python tool/backtest/fetch_kcycle_results.py --years 2021-2026

# 3. 출주 전/경주 후 데이터 결합
python tool/backtest/join_data.py --years 2021-2026

# 4. 무결성·누락 검사
python tool/backtest/validate_data.py --years 2021-2026 --max-missing-rate 0.02

# 5. 낙차부상 상세와 경주 직전 상대전적 피처 생성 및 증분 평가
python tool/backtest/fetch_fall_injuries.py --min-year 2021
python tool/backtest/context_features.py --years 2021-2026
python tool/backtest/evaluate_context_features.py

# 6. 기존 피처 시간 분리 재학습·비교
python tool/backtest/retrain_evaluate.py
```

모든 수집기는 임시 파일을 원자적으로 교체한다. 중단되면 같은 명령을 다시
실행한다. 출주표는 페이지/날짜 단위, KCYCLE은 경주 단위 체크포인트에서
이어진다. 공식 결과가 늦게 게시된 경주만 다시 시도하려면 다음을 사용한다.

```bash
python tool/backtest/fetch_kcycle_results.py --years 2026 --retry-missing
```

원본 HTML 보존이 필요하면 `--keep-html`을 추가한다. 서버 부하를 줄이기 위해
기본 요청 간격은 0.35초이며 `--delay`로 조정할 수 있다.

## 데이터와 결합키

- `organ_YYYY.json`: 경주 전 출주 정보. 광명은 공공 API, 창원·부산은
  레포츠파크 확정출주표를 사용하며 `_meet`은 1 광명, 2 창원, 3 부산이다.
- `kcycle_results_YYYY.json`: 공식 착순·기록·승부수·제재와 일곱 확정배당.
- `joined_YYYY.json`: `pre_race`와 `post_race`를 명시적으로 분리한 학습 입력.
- `reports/collection_YYYY.json`: 수집 상태와 요청 실패.
- `reports/join_failures_YYYY.json`: 출주/결과 매칭 실패.
- `reports/integrity_YYYY.json`: 경기장별 건수, 누락률, 중복, 착순·배당 오류.

기본 결합키는 `(날짜, 경기장, 경주번호, 배번)`이다. 결과에 선수번호가 있으면
보존하며, 선수명은 공공 API의 인코딩 문제와 동명이인 가능성 때문에 기본
키로 사용하지 않는다. 취소·동착·배당 미공개는 각각 상태값으로 유지한다.

## 테스트

```bash
python -m unittest tool/backtest/test_kcycle_data.py -v
```

실제 KCYCLE HTML 픽스처로 일반 착순과 동착을 검사하고, 일곱 승식 배당 및
배번 기반 결합을 검증한다.

## 시간 분리 평가와 모델 승격

- 학습: 2021~2024
- 피처 선택: 2025 검증
- 최종 테스트: 2026 홀드아웃

`retrain_evaluate.py`는 이전 단순 엔진, 기존 `weights.json`, 재학습 모델을
단승·복승·쌍승·삼복승 적중률로 비교하고 경기장별 결과를
`reports/time_split_evaluation.json`에 기록한다. 새 가중치는 항상
`retrained_weights.json`에 저장된다.

홀드아웃 지표가 기존 앱 모델보다 개선된 경우에만 `weights.json`과 앱의
`PredictionEngine` 가중치를 갱신하려면:

```bash
python tool/backtest/retrain_evaluate.py --promote
```

`--promote`는 단승이 기존 앱 모델보다 높고 복승·쌍승·삼복승이 하나도
낮아지지 않을 때만 파일을 변경한다. 실행 후 생성된 보고서와 앱 변경분을
함께 검토한다.

## 낙차·상대전적 실험

`fetch_fall_injuries.py`는 게시판을 매번 첫 페이지부터 스캔해 상세 ID 목록을
만든 뒤 완료한 ID를 제외하고 수집한다. 신규 게시물로 페이지가 밀려도
누락되지 않으며, 시대별로 달라진 표는 열 위치가 아닌 헤더명으로 파싱한다.

`context_features.py`는 공공 낙차사고 API의 회차·일차를 실제 날짜에 연결하고
선수별 재승/후송 기록을 낙차 이력으로 저장한다. 게시판 상세의 부상 정도와
출전불가 여부도 선수번호로 해소해 보강한다. 상대전적은 공공 API의 연간
집계를 직접 사용하지 않고 공식 착순을 날짜순으로 처리하면서 이전 경주만
누적한다. 따라서 모든 피처에 대상 경주 이후 정보가 섞이지 않는다.

생성 피처:

- `days_since_fall`, `falls_30d`, `falls_90d`, `severe_injury_30d`
- `opponent_win_rate`, `opponent_top3_pair_rate`
- `opponent_history_coverage`

`evaluate_context_features.py`는 기본 19개 피처, 상대전적 추가, 낙차 추가,
전체 추가 후보를 2025년으로 선택한 뒤 2026년 홀드아웃에서 현재 앱 모델과
비교한다. 결과는 `reports/context_evaluation.json`에 저장되며 단승이 높고
복승·쌍승·삼복승이 모두 하락하지 않은 경우에만 앱 통합 적격으로 표시한다.
