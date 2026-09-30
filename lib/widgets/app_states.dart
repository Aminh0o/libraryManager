import 'package:flutter/material.dart';

import '../ui/app_tokens.dart';

/// PHASE C -- the standardized global states (frontend reconstruction).
///
/// §30/§31/§32 require EVERY list, table and panel to present empty, loading
/// and error conditions the same way: a calm, centered composition with an
/// icon, a plain-language message and (where the user can act) a visible next
/// step. Before this, each screen hand-rolled its own `Center(CircularProgress
/// Indicator())` / grey `Text` mixture, so the same situation looked different
/// everywhere. Screens use these instead of improvising a state again.
///
/// All strings arrive already-localized from the call site: the components
/// never invent copy, and never render a state the app has not actually
/// produced (§52) -- it is the caller's job to show these only when the
/// underlying condition is real.

/// The canonical "nothing here" composition: hero icon + title + optional
/// explanation + optional primary action.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;

  /// Supporting line; omit when the title alone is self-explanatory.
  final String? message;

  /// Optional next step (e.g. an "Add item" button). Rendered below the copy.
  final Widget? action;

  /// Tighter padding + smaller glyph for use inside dialogs and panels.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(compact ? AppSpacing.xxl : AppSpacing.huge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: compact ? AppIcon.empty : AppIcon.hero,
              color: scheme.outlineVariant,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              title,
              textAlign: TextAlign.center,
              style: txt.titleMedium?.copyWith(color: scheme.onSurface),
            ),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: txt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.xl),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// The canonical in-progress composition. Callers show it ONLY while work is
/// genuinely running -- never as decorative chrome.
class AppLoadingState extends StatelessWidget {
  const AppLoadingState({super.key, this.message});

  /// Optional "Loading members…" label under the spinner.
  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: AppIcon.xl,
            height: AppIcon.xl,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
          if (message != null) ...[
            const SizedBox(height: AppSpacing.lg),
            Text(
              message!,
              textAlign: TextAlign.center,
              style: txt.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

/// The canonical failure composition: honest message + a real retry when one
/// exists. A retry-less error still tells the operator what went wrong.
class AppErrorState extends StatelessWidget {
  const AppErrorState({
    super.key,
    required this.message,
    this.retryLabel,
    this.onRetry,
    this.details,
  });

  final String message;

  /// Localized label for the retry button; the button only renders when BOTH
  /// [retryLabel] and [onRetry] are supplied (a dead button is worse than none,
  /// §52).
  final String? retryLabel;
  final VoidCallback? onRetry;

  /// Optional technical detail (exception text) for the operator debugging a
  /// connection problem; rendered muted and selectable.
  final String? details;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: AppIcon.empty, color: scheme.error),
            const SizedBox(height: AppSpacing.lg),
            Text(
              message,
              textAlign: TextAlign.center,
              style: txt.titleMedium?.copyWith(color: scheme.onSurface),
            ),
            if (details != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SelectableText(
                details!,
                textAlign: TextAlign.center,
                style: txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            if (retryLabel != null && onRetry != null) ...[
              const SizedBox(height: AppSpacing.xl),
              FilledButton.tonalIcon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh, size: AppIcon.md),
                label: Text(retryLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
