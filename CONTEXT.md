# 경륜 예측 앱 (Cycling Prediction)

## 프로젝트 구조

```
lib/
├── main.dart                  # 앱 진입점 (ProviderScope + MaterialApp.router)
├── router/
│   └── app_router.dart        # GoRouter 라우팅 설정
├── core/
│   ├── constants/
│   │   └── api_constants.dart  # API 키, 엔드포인트, 경기장 코드
│   ├── theme/
│   │   └── app_theme.dart      # 다크/라이트 테마
│   ├── network/
│   │   └── dio_client.dart     # Dio HTTP 클라이언트
│   ├── services/
│   │   ├── cycling_api_service.dart  # 경륜 API 서비스
│   │   └── ml_api_service.dart       # Python ML 백엔드 API 서비스
│   └── widgets/
│       └── shimmer_loading.dart      # 로딩 Shimmer 위젯
├── models/
│   ├── race.dart              # 경주 계획 모델
│   ├── race_entry.dart        # 출주표 (선수, 기수, 등급 등)
│   ├── race_result.dart      # 경주 결과 (순위, 기록)
│   ├── odds.dart             # 배당률 (단승, 복승, 쌍승, 삼복승, 삼쌍승)
│   └── prediction.dart      # AI 예측 결과 모델
├── features/
│   ├── home/
│   │   ├── screens/home_screen.dart   # 홈: 경기장별 탭, 경주 목록
│   │   └── widgets/race_card.dart     # 경주 카드 위젯
│   ├── race/
│   │   ├── screens/
│   │   │   ├── race_detail_screen.dart  # 출주표 + 배당률 + AI 예측
│   │   │   └── race_result_screen.dart  # 경주 결과 순위
│   │   ├── widgets/
│   │   │   ├── entry_card.dart          # 출전 선수 카드
│   │   │   ├── odds_panel.dart          # 배당률 패널
│   │   │   └── prediction_summary.dart  # AI 예측 요약
│   │   └── providers/
│   │       └── race_providers.dart      # Riverpod 프로바이더
│   ├── rider/
│   │   └── screens/rider_detail_screen.dart  # 선수 전적, 차트
│   └── prediction/
│       └── screens/prediction_screen.dart    # AI 예측 상세 리포트

backend/
├── main.py              # FastAPI 서버 (예측, 데이터수집, 학습 API)
├── config.py            # 환경변수 설정
├── requirements.txt     # Python 의존성
├── services/
│   ├── cycling_client.py # 경륜 API 클라이언트
│   ├── data_collector.py  # 과거 데이터 수집/CSV 저장
│   └── predictor.py      # ML 예측 서비스
├── features/
│   └── engineering.py   # 특성 엔지니어링 (전법, 등급, 평균득점 등)
├── models/              # 학습된 모델 저장 (.joblib)
└── data/                # 수집된 데이터 캐시 (.csv)
```

## 기술 스택

- **Flutter**: Riverpod, GoRouter, Dio, fl_chart, Google Fonts
- **Backend**: Python FastAPI, XGBoost, scikit-learn, pandas
- **API**: 경륜경정총괄본부, 국민체육진흥공단
- **데이터 저장**: Notion (Work 프로젝트 ID: `.env` 참조)

## Notion 설정

- 데이터 저장소: Notion Work 프로젝트 ID 사용
- `.env`에 `NOTION_ACCESS_TOKEN`, `NOTION_WORK_PROJECT_ID` 설정
- `.env.example`을 복사해 `.env` 생성 후 실제 값 입력

## 화면 라우팅

- `/` → 홈 (오늘의 경주)
- `/race/:venue/:date/:raceNo` → 경주 상세 (출주표)
- `/result/:venue/:date/:raceNo` → 경주 결과
- `/rider/:riderId?venue=` → 선수 상세
- `/prediction/:venue/:date/:raceNo` → AI 예측 리포트

---

## 경륜 분석 도메인 지식

### 1️⃣ 선수 정보

| 항목 | 설명 |
|------|------|
| **선수 이름 / 기수** | 출전 선수 기본 정보 |
| **나이, 출신 학교** | 선수 배경 |
| **훈련지** | 창원, 김해, 대전 등 |
| **등급** | S, A1, A2, B1, B2, B3 |
| **최근 성적** | 최근 경주 결과 |
| **전법** | 선행 / 젖히기 / 추입 / 마크 |

> 👉 **경륜 분석에서 전법과 등급이 가장 중요합니다.**

### 2️⃣ 경주 정보

| 항목 | 설명 |
|------|------|
| **경주 번호** | 경주 식별 |
| **출전 선수** | 7명 |
| **배정 등급** | 선수별 배정 등급 |
| **거리** | 보통 2025m |
| **경기장** | 경주 개최 장소 |

**한국 주요 경기장**

- 광명스피돔
- 창원경륜장
- 부산경륜장

### 3️⃣ 배당 정보

베팅 종류에 따라 배당이 달라집니다.

| 베팅 종류 | 설명 |
|----------|------|
| **단승** | 1등 맞추기 |
| **복승** | 1, 2등 순서 상관 없음 |
| **쌍승** | 1, 2등 순서 맞추기 |
| **삼복승** | 1, 2, 3등 순서 상관 없음 |
| **삼쌍승** | 1, 2, 3등 순서 맞추기 |

> 배당은 실시간 판매 금액에 따라 변동됩니다.

### 4️⃣ 기록 데이터

분석에 가장 중요한 데이터입니다.

| 항목 | 설명 |
|------|------|
| **평균 득점** | 선수별 평균 득점 |
| **최근 3회 / 10회 성적** | 최근 경주 성적 |
| **라인 형성** | 스타트 라인 형성 |
| **스타트 기록** | 스타트 관련 기록 |
| **결승 진출률** | 결승 진출 비율 |

### 5️⃣ 실시간 정보

경륜에서는 경주 직전 정보가 매우 중요합니다.

| 항목 | 설명 |
|------|------|
| **선수 몸 상태** | 건강/컨디션 |
| **라인 형성 변화** | 실시간 라인 변화 |
| **예상 작전** | 전법/전략 |
| **인기 순위** | 베팅 인기 순위 |

### 6️⃣ 경륜 데이터 보는 곳

**대표적인 공식 사이트**

- **경륜경정총괄본부**
- **국민체육진흥공단**

여기에서 **출주표**, **결과**, **영상**, **통계**를 모두 확인할 수 있습니다.

---

## 💡 앱 개발용 경륜 데이터 (중요)

앱을 만들 때 많이 사용하는 데이터:

| 데이터 | 용도 |
|--------|------|
| **출주표** | 경주별 출전 선수, 기수, 등급 |
| **선수 기록** | 선수별 전적, 평균 득점, 전법 |
| **배당** | 단승/복승/쌍승 등 실시간 배당률 |
| **경주 결과** | 순위, 기록, 완주 시간 |
| **과거 기록** | ML 학습용 히스토리 데이터 |

**데이터 수집 방식**

1. **공식 사이트 크롤링** — 경륜경정총괄본부, 국민체육진흥공단 웹페이지 파싱
2. **API 연결** — 공공/제공 API가 있다면 직접 연동
3. **DB 구축** — 수집 데이터를 DB에 저장 후 앱/백엔드에서 조회

---

## ML 특성 (경륜 특화)

전법, 등급, 평균 득점, 최근 3회/10회 성적, 라인 형성, 스타트 기록, 결승 진출률, 등급 인코딩, 경기장 인코딩 등

## 백엔드 사용법

```bash
cd backend
pip install -r requirements.txt
# 1) 데이터 수집
curl -X POST "http://localhost:8000/collect?venue=1&days=90"
# 2) 모델 학습
curl -X POST "http://localhost:8000/train"
# 3) 예측
curl "http://localhost:8000/predict/1/20260302/1"
# 서버 시작
uvicorn main:app --reload --port 8000
```
