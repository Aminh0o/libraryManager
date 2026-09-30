import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';

/// FE2-01/02 (P9-9.29): the generic "await-then-close" confirmation dialog.
///
/// A number of screens need the exact same behaviour: show a confirm/cancel
/// prompt, run an async operation on confirm, and ONLY dismiss the dialog when
/// the operation succeeds -- keeping it open (with a visible error) when it
/// throws. Previously each such dialog fired the operation without awaiting and
/// popped immediately, so a rejected write vanished silently. This widget owns
/// that logic once so every caller inherits the correctness guarantee.
class ConfirmActionDialog extends StatefulWidget {
  const ConfirmActionDialog({
    super.key,
    required this.title,
    required this.content,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.onConfirm,
    this.confirmKey = const Key('confirmAction'),
    this.cancelKey = const Key('cancelAction'),
  });

  final Widget title;
  final Widget content;
  final Widget confirmLabel;
  final Widget cancelLabel;

  /// Performs the actual operation. Must return a [Future] that completes on
  /// success and throws on failure; the dialog awaits it.
  final Future<void> Function() onConfirm;

  /// Keys are configurable so callers (and their tests) can target a stable
  /// handle without depending on localized button text.
  final Key confirmKey;
  final Key cancelKey;

  @override
  State<ConfirmActionDialog> createState() => _ConfirmActionDialogState();
}

class _ConfirmActionDialogState extends State<ConfirmActionDialog> {
  bool _busy = false;

  Future<void> _confirm() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onConfirm();
      if (!mounted) return;
      Navigator.pop(context); // success: close the dialog
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(describeError(AppLocalizations.of(context)!, e)),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: widget.title,
      content: widget.content,
      actions: [
        TextButton(
          key: widget.cancelKey,
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: widget.cancelLabel,
        ),
        TextButton(
          key: widget.confirmKey,
          onPressed: _busy ? null : _confirm,
          child: _busy
              ? SizedBox(
                  width: AppIcon.md,
                  height: AppIcon.md,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.onSurface,
                  ),
                )
              : widget.confirmLabel,
        ),
      ],
    );
  }
}
