import 'package:flutter/material.dart';

import '../ui/app_tokens.dart';

/// A single operational metric (dashboard "at a glance" row).
///
/// Phase D (frontend reconstruction): the old tile painted a diagonal
/// gradient, a 20px radius and `Colors.black87` text -- decoration that broke
/// dark mode and made every metric shout the same volume. The replacement is a
/// quiet bordered surface (shaped by the global Card theme) with ONE
/// restrained signal: a tonal icon chip in the metric's semantic colour. The
/// number carries the hierarchy via the type scale, not via saturation.
class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  final String title;
  final String value;
  final IconData icon;

  /// Semantic hue for the icon chip only (from [AppStatus]); the text always
  /// uses theme colors so the tile stays legible in dark mode.
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.14),
                borderRadius: AppRadius.tile,
              ),
              child: Icon(icon, color: color, size: AppIcon.xl),
            ),
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: txt.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: txt.headlineSmall?.copyWith(
                        color: scheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
