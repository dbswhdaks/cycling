import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/constants/subscription_constants.dart';

class SubscriptionScreen extends StatefulWidget {
  const SubscriptionScreen({super.key});

  @override
  State<SubscriptionScreen> createState() => _SubscriptionScreenState();
}

class _SubscriptionScreenState extends State<SubscriptionScreen> {
  bool _isProcessing = false;
  SubscriptionPlan _selectedPlan = SubscriptionPlan.monthly;

  Future<void> _handleSubscribe() async {
    if (_isProcessing) return;

    final client = Supabase.instance.client;
    final user = client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('로그인 후 구독할 수 있습니다.')));
      return;
    }

    setState(() => _isProcessing = true);
    try {
      final periodDays = SubscriptionConstants.periodDaysFor(_selectedPlan);
      final response = await client.functions.invoke(
        SubscriptionConstants.activateSubscriptionFunctionName,
        body: {
          'plan': SubscriptionConstants.dbPlanValueFor(_selectedPlan),
          'period_days': periodDays,
        },
      );
      if (response.status != 200 && response.status != 201) {
        throw Exception('activate-subscription failed: ${response.status}');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('구독이 활성화되었습니다.')));
      context.pop(true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('결제 처리 중 오류가 발생했습니다. 다시 시도해 주세요.')),
      );
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('구독하기')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      SubscriptionConstants.productName,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      SubscriptionConstants.benefitSummary,
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 14),
                    Column(
                      children: [
                        _buildPlanOption(
                          theme: theme,
                          plan: SubscriptionPlan.monthly,
                          subtitle: SubscriptionConstants.monthlyPriceLabel,
                        ),
                        const SizedBox(height: 10),
                        _buildPlanOption(
                          theme: theme,
                          plan: SubscriptionPlan.yearly,
                          subtitle: SubscriptionConstants.yearlyPriceLabel,
                          badge: SubscriptionConstants.yearlyDiscountLabel,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Spacer(),
              FilledButton(
                onPressed: _isProcessing ? null : _handleSubscribe,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
                child: _isProcessing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        '${SubscriptionConstants.planLabelFor(_selectedPlan)} ${SubscriptionConstants.subscribeButtonLabel}',
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                SubscriptionConstants.autoUnlockMessage,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlanOption({
    required ThemeData theme,
    required SubscriptionPlan plan,
    required String subtitle,
    String? badge,
  }) {
    final isSelected = _selectedPlan == plan;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _isProcessing
          ? null
          : () {
              setState(() {
                _selectedPlan = plan;
              });
            },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFFF59E0B).withValues(alpha: 0.15)
              : theme.colorScheme.surface.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isSelected
                ? const Color(0xFFF59E0B).withValues(alpha: 0.7)
                : theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Text(
          badge != null
              ? '${SubscriptionConstants.planLabelFor(plan)} $subtitle($badge)'
              : '${SubscriptionConstants.planLabelFor(plan)} $subtitle',
          style: theme.textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: isSelected ? const Color(0xFFF59E0B) : null,
          ),
        ),
      ),
    );
  }
}
