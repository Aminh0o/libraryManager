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
    this.iconTextDirection,
  });

  final String title;
  final String value;
  final IconData icon;

  /// Semantic hue for the icon chip only (from [AppStatus]); the text always
  /// uses theme colors so the tile stays legible in dark mode.
  final Color color;

  /// Forces the glyph's layout direction, defeating Material's automatic
  /// right-to-left mirroring. Needed for icons that encode DATA direction
  /// rather than reading direction: a real-UI pass caught the Arabic dashboard
  /// rendering "Borrowed (7 days)" with a down-and-left arrow while the
  /// English build showed up-and-right -- same card, same value, opposite
  /// meaning. Leave null for ordinary decorative icons.
  final TextDirection? iconTextDirection;

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
              child: Icon(
                icon,
                color: color,
                size: AppIcon.xl,
                textDirection: iconTextDirection,
              ),
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
