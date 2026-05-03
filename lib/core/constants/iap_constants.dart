class IapConstants {
  IapConstants._();

  // Play Console 등록 상품 ID를 환경변수로 주입할 수 있습니다.
  // 예) --dart-define=IAP_MONTHLY_ID=com.example.app.premium_monthly
  //     --dart-define=IAP_YEARLY_ID=com.example.app.premium_yearly
  static const String monthlyProductId = String.fromEnvironment(
    'IAP_MONTHLY_ID',
    defaultValue: 'premium_monthly',
  );

  static const String yearlyProductId = String.fromEnvironment(
    'IAP_YEARLY_ID',
    defaultValue: 'premium_yearly',
  );

  // Play Console에 등록한 인앱 상품 ID와 동일해야 합니다.
  static const Set<String> productIds = {monthlyProductId, yearlyProductId};

  static const Set<String> subscriptionProductIds = {
    monthlyProductId,
    yearlyProductId,
  };

  // 운영에서 서버 영수증 검증을 사용한다면 --dart-define으로 함수명을 주입하세요.
  // 예: --dart-define=IAP_VERIFY_FUNCTION=verify_android_subscription
  static const String serverVerifyFunctionName = String.fromEnvironment(
    'IAP_VERIFY_FUNCTION',
    defaultValue: '',
  );
}
