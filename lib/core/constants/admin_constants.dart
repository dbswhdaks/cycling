class AdminConstants {
  AdminConstants._();

  /// 관리자 로그인 비밀번호.
  /// 빌드 시점에 외부 주입이 필요하면 --dart-define=ADMIN_PASSWORD=... 로 덮어쓸 수 있다.
  static const String adminPassword = String.fromEnvironment(
    'ADMIN_PASSWORD',
    defaultValue: '71108368',
  );

  /// SharedPreferences 에 관리자 로그인 상태를 저장하는 키.
  static const String storageKey = 'admin_logged_in';
}
