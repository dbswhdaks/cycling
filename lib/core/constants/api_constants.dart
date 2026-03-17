import 'package:shared_preferences/shared_preferences.dart';

/// 공공데이터포털 경륜 API - 국민체육진흥공단 (B551014)
/// https://www.data.go.kr 에서 API 활용 신청 후 인증키 발급 필요
class ApiConstants {
  static const String baseUrl = 'https://apis.data.go.kr/B551014';

  static const String _defaultServiceKey =
      '788d1f62af9d665d2f002057f9526ac8f2776910fef87b0e95d27e232fe0967f';

  static String _runtimeServiceKey = '';

  static String get serviceKey =>
      _runtimeServiceKey.isNotEmpty ? _runtimeServiceKey : _defaultServiceKey;

  static Future<void> loadServiceKey() async {
    final prefs = await SharedPreferences.getInstance();
    _runtimeServiceKey = prefs.getString('cycling_service_key') ?? '';
  }

  static Future<void> saveServiceKey(String key) async {
    _runtimeServiceKey = key.trim();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cycling_service_key', _runtimeServiceKey);
  }

  static bool get isCustomKeySet => _runtimeServiceKey.isNotEmpty;

  // ─── 경륜 API 엔드포인트 (서비스/오퍼레이션) ───

  /// 출주표 목록 조회
  static const String raceOrgan =
      '$baseUrl/SRVC_OD_API_CRA_RACE_ORGAN/TODZ_API_CRA_RACE_ORGAN_I';

  /// 경주결과 목록 조회
  static const String raceResult =
      '$baseUrl/SRVC_TODZ_CRA_RACE_RESULT/TODZ_API_CRA_RACE_RESULT';

  /// 경주결과순위 조회
  static const String raceRank =
      '$baseUrl/SRVC_CRA_RACE_RANK/TODZ_CRA_RACE_RANK';

  /// 배당률 목록 조회
  static const String payoff =
      '$baseUrl/SRVC_OD_API_CRA_PAYOFF/TODZ_API_CRA_PAYOFF_I';

  /// 연간경주일정 조회
  static const String raceSchedule =
      '$baseUrl/SRVC_WEB_CRA_MBR_INFO/todz_api_web_schedule';

  /// 회차별 경주득점 조회
  static const String tmsScr =
      '$baseUrl/SRVC_OD_API_CRA_TMS_SCR/TODZ_API_CRA_TMS_SCR_I';

  /// 선수 상대전적 조회
  static const String oppoWin =
      '$baseUrl/SRVC_OD_API_CRA_OPPO_WIN/todz_api_cra_oppo_win_i';

  /// 낙차사고 정보 조회
  static const String downAcdnt =
      '$baseUrl/SRVC_TODZ_CRA_DOWN_ACDNT/TODZ_CRA_DOWN_ACDNT';

  /// 제재선수 현황 조회
  static const String raceSanc =
      '$baseUrl/SRVC_CRA_RACE_SANC/TODZ_CRA_RACE_SANC';

  /// 경주 동영상 조회
  static const String raceVideo =
      '$baseUrl/SRVC_WEB_CRA_MBR_INFO/TODZ_API_CYCLE_RACE_VIDEO';

  /// 경기장 코드
  static const Map<int, String> venueCodes = {
    1: '광명스피돔',
    2: '창원경륜장',
    3: '부산경륜장',
  };

  /// meet 파라미터 매핑 (경기장 코드 → API meet 값)
  static const Map<int, int> meetCodes = {1: 1, 2: 2, 3: 3};

  static String venueName(int code) => venueCodes[code] ?? '알 수 없음';
}
