enum SubscriptionPlan { monthly, yearly }

class SubscriptionConstants {
  static const String activateSubscriptionFunctionName =
      'activate-subscription';
  static const String productName = '프리미엄 구독';
  static const String benefitSummary = 'AI 추천, 종합추천은 구독 후 이용할 수 있습니다.';
  static const String autoUnlockMessage = '결제 완료 후 자동으로 기능이 열립니다.';

  static const String subscribeButtonLabel = '결제하고 구독 시작';
  static const String monthlyPlanLabel = '월간';
  static const String yearlyPlanLabel = '연간';
  static const String monthlyPriceLabel = '9,900원';
  static const String yearlyPriceLabel = '99,000원';
  static const String yearlyDiscountLabel = '17% 절약';
  static const int monthlyPeriodDays = 30;
  static const int yearlyPeriodDays = 365;

  static int periodDaysFor(SubscriptionPlan plan) {
    return plan == SubscriptionPlan.monthly
        ? monthlyPeriodDays
        : yearlyPeriodDays;
  }

  static String priceLabelFor(SubscriptionPlan plan) {
    return plan == SubscriptionPlan.monthly
        ? monthlyPriceLabel
        : yearlyPriceLabel;
  }

  static String planLabelFor(SubscriptionPlan plan) {
    return plan == SubscriptionPlan.monthly
        ? monthlyPlanLabel
        : yearlyPlanLabel;
  }

  static String dbPlanValueFor(SubscriptionPlan plan) {
    return plan == SubscriptionPlan.monthly ? 'monthly' : 'yearly';
  }
}
