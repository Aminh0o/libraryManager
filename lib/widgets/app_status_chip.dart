import 'package:flutter/material.dart';

import '../ui/app_tokens.dart';

/// PHASE C -- the shared status chip (frontend reconstruction).
///
/// §26/§27: a status must READ THE SAME everywhere (inventory grid, item
/// detail, loans, reservations), and must never rely on colour alone -- the
/// label is always present, so the chip stays legible for colour-blind
/// operators and in dark mode. The tinted-background construction lived twice
/// (ItemStatusCell here, ad-hoc Containers in screens); it now lives once.
class AppStatusChip extends StatelessWidget {
  const AppStatusChip({super.key, required this.label, required this.color});

  /// Already-localized status text; the chip never colours-meaning-without-text.
  final String label;

  /// The semantic hue (from [AppStatus] / ItemStatusCell.statusColor).
  final Color color;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadius.chip,
        border: Border.all(color: color, width: AppBorder.width),
      ),
      child: Text(
        label,
        style: txt.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// PHASE C -- a titled content section (§46).
///
/// Dashboard panels, settings groups and detail sub-sections all need the same
/// "title, optional trailing action, content" framing. Screens previously
/// re-spaced hand-built `Row(Text(bold))` headers with drifting sizes; this
/// pins the header role to the theme's titleMedium and the rhythm to tokens.
class AppSection extends StatelessWidget {
  const AppSection({
    super.key,
    required this.title,
    required this.child,
    this.icon,
    this.trailing,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
  });

  final String title;
  final Widget child;

  /// Optional leading glyph for scannable panel identity.
  final IconData? icon;

  /// Optional action pinned to the header's trailing edge (automatically
  /// mirrors in RTL because it lives inside [Row.end] semantics of the Flex).
  final Widget? trailing;

  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: AppIcon.md, color: scheme.onSurfaceVariant),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: Text(
                  title,
                  style: txt.titleMedium?.copyWith(color: scheme.onSurface),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          child,
        ],
      ),
    );
  }
}
