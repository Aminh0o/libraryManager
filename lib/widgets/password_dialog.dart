import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../ui/app_tokens.dart';

class PasswordDialog extends StatefulWidget {
  final String title;
  const PasswordDialog({super.key, required this.title});

  @override
  State<PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<PasswordDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return AlertDialog(
      title: Text(widget.title),
      content: TextField(
        controller: _controller,
        obscureText: true,
        autofocus: true,
        decoration: InputDecoration(
          labelText: l10n.adminPassword,
          prefixIcon: const Icon(Icons.lock_outline, size: AppIcon.md),
        ),
        onSubmitted: (_) => _submit(),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _submit, child: Text(l10n.validate)),
      ],
    );
  }

  Future<void> _submit() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final errorColor = Theme.of(context).colorScheme.error;
    // FE2-11: authoritative server-side verification on the host, not the
    // local empty-password check that any operator could pass.
    final ok = await provider.verifyAdminPassword(_controller.text);
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context, true);
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.wrongPassword),
          backgroundColor: errorColor,
        ),
      );
    }
  }
}

Future<bool> showPasswordPrompt(
  BuildContext context, {
  required String title,
}) async {
  return await showDialog<bool>(
        context: context,
        builder: (context) => PasswordDialog(title: title),
      ) ??
      false;
}
