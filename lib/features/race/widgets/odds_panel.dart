import 'package:flutter/material.dart';
import '../../../models/odds.dart';

class OddsPanel extends StatelessWidget {
  final Odds odds;

  const OddsPanel({super.key, required this.odds});

  @override
  Widget build(BuildContext context) {
    final sections = <Widget>[
      if (odds.win.isNotEmpty)
        _buildSection(
          context,
          title: '단승',
          subtitle: '1착 맞추기',
          entries: odds.win.map((k, v) => MapEntry('$k번', v)),
        ),
      if (odds.place.isNotEmpty)
        _buildSection(
          context,
          title: '연승',
          subtitle: '2착 안에 드는 선수 맞추기',
          entries: odds.place.map((k, v) => MapEntry('$k번', v)),
        ),
      if (odds.exacta.isNotEmpty)
        _buildSection(
          context,
          title: '쌍승',
          subtitle: '1, 2착 순서까지 맞추기',
          entries: odds.exacta,
        ),
      if (odds.quinella.isNotEmpty)
        _buildSection(
          context,
          title: '복승',
          subtitle: '1, 2착 순서 상관 없음',
          entries: odds.quinella,
        ),
      if (odds.trio.isNotEmpty)
        _buildSection(
          context,
          title: '삼복승',
          subtitle: '1, 2, 3착 순서 상관 없음',
          entries: odds.trio,
        ),
      if (odds.exactaTrio.isNotEmpty)
        _buildSection(
          context,
          title: '쌍복승',
          subtitle: '1, 2착 순서 맞추고 3착 포함',
          entries: odds.exactaTrio,
        ),
      if (odds.trifecta.isNotEmpty)
        _buildSection(
          context,
          title: '삼쌍승',
          subtitle: '1, 2, 3착 순서까지 맞추기',
          entries: odds.trifecta,
        ),
    ];

    if (sections.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (var i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          sections[i],
        ],
      ],
    );
  }

  Widget _buildSection(
    BuildContext context, {
    required String title,
    String? subtitle,
    required Map<String, double> entries,
  }) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: theme.brightness == Brightness.dark
            ? Border.all(color: const Color(0xFF30363D))
            : Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ],
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Wrap(
              alignment: WrapAlignment.start,
              spacing: 8,
              runSpacing: 8,
              children: entries.entries
                  .map((e) => _oddsChip(context, e.key, e.value.toStringAsFixed(1)))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _oddsChip(BuildContext context, String label, String value) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary.withValues(alpha: 0.12),
            theme.colorScheme.primary.withValues(alpha: 0.06),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: theme.colorScheme.primary.withValues(alpha: 0.25),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
