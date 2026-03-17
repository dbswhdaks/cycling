import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../models/race_entry.dart';
import '../providers/race_providers.dart';

class EntryCard extends ConsumerWidget {
  final RaceEntry entry;
  final int? venueCode;

  const EntryCard({super.key, required this.entry, this.venueCode});

  Color _gradeColor(String grade) {
    switch (grade) {
      case 'S':
        return const Color(0xFFE53935);
      case 'A1':
        return const Color(0xFFF57C00);
      case 'A2':
        return const Color(0xFFFDD835);
      case 'B1':
        return const Color(0xFF43A047);
      case 'B2':
        return const Color(0xFF1E88E5);
      case 'B3':
        return const Color(0xFF8E24AA);
      default:
        return const Color(0xFF757575);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final gradeColor = _gradeColor(entry.grade);

    return GestureDetector(
      onTap: () {
        ref.read(selectedRiderEntryProvider.notifier).state = entry;
        final query = venueCode != null ? '?venue=$venueCode' : '';
        context.push('/rider/${entry.riderId}$query');
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: gradeColor.withValues(alpha: 0.35),
            width: 1.5,
          ),
          boxShadow: theme.brightness == Brightness.light
              ? [
                  BoxShadow(
                    color: gradeColor.withValues(alpha: 0.06),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  gradeColor.withValues(alpha: 0.25),
                  gradeColor.withValues(alpha: 0.15),
                ],
              ),
              shape: BoxShape.circle,
            ),
            alignment: Alignment.center,
            child: Text(
              '${entry.lineNo}',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: gradeColor,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        entry.riderName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.primary,
                          decoration: TextDecoration.underline,
                          decorationColor: theme.colorScheme.primary.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 14,
                      color: theme.colorScheme.primary.withValues(alpha: 0.7),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    _buildChip(context, entry.grade, gradeColor),
                    const SizedBox(width: 6),
                    _buildChip(
                      context,
                      entry.tactic,
                      theme.colorScheme.primary.withValues(alpha: 0.8),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '평균 ${entry.avgScore.toStringAsFixed(1)}점',
                style: theme.textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '최근3 ${entry.recent3Wins}승',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ],
      ),
    ),
    );
  }


  Widget _buildChip(BuildContext context, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
