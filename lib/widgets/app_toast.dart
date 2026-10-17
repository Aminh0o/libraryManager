import 'package:flutter/material.dart';

import '../ui/app_tokens.dart';

/// Phase TOAST: one consistent, MEANING-BEARING feedback surface for the whole
/// app. Before this every mutation fired a bare `SnackBar(content: Text(...))`,
/// so a success and a failure looked identical and the plain bar read as a
/// developer stub rather than a shipped product. This helper keeps the platform
/// `SnackBar` (so existing tests that assert `byType(SnackBar)` and the message
/// text still pass) but adds a semantic icon + tinted surface so the operator
/// understands the OUTCOME of an action at a glance — in every language, since
/// only the icon changes, never the (already localized) message.
enum ToastKind { success, error, info, warning }

/// The shared toast host. Prefer [showAppToast] when you have a live context;
/// use [showAppToastOn] inside an async callback that captured the messenger
/// before an `await` (so the toast still fires after the operation completes).
void showAppToastOn(
  ScaffoldMessengerState messenger,
  String message, {
  ToastKind kind = ToastKind.info,
}) {
  final (IconData icon, Color tint) = switch (kind) {
    ToastKind.success => (Icons.check_circle_outline, AppStatus.success),
    ToastKind.error => (Icons.error_outline, AppStatus.danger),
    ToastKind.warning => (Icons.warning_amber_rounded, AppStatus.warning),
    ToastKind.info => (Icons.info_outline, AppStatus.info),
  };
  messenger
    ..clearSnackBars()
    ..showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(icon, color: tint, size: AppIcon.lg),
            const SizedBox(width: AppSpacing.md),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
}

/// Context variant of [showAppToastOn].
void showAppToast(
  BuildContext context,
  String message, {
  ToastKind kind = ToastKind.info,
}) {
  showAppToastOn(ScaffoldMessenger.of(context), message, kind: kind);
}
