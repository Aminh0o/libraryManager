import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/app_tokens.dart';
import 'confirm_action_dialog.dart';

/// FE2-03: restoring a backup OVERWRITES the entire live database, so it must
/// never happen the moment a file is picked. This is the confirmation gate: the
/// operator sees exactly which file will replace the current data (and that a
/// safety snapshot is taken first) and must explicitly confirm. The restore is
/// awaited by the underlying [ConfirmActionDialog] and only closes on success.
class RestoreConfirmDialog extends StatelessWidget {
  const RestoreConfirmDialog({
    super.key,
    required this.filePath,
    required this.onConfirm,
  });

  /// The selected backup file, shown verbatim so the operator can catch a
  /// wrong pick before it destroys current data.
  final String filePath;

  /// Performs the actual restore. Must return a [Future] that completes on
  /// success and throws on failure.
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ConfirmActionDialog(
      title: Text(l10n.restoreDatabase),
      content: Text(
        'Cette op\u00e9ration REMPLACE toute la base de donn\u00e9es actuelle '
        'par le fichier s\u00e9lectionn\u00e9 :\n\n$filePath\n\n'
        'Une sauvegarde de s\u00e9curit\u00e9 de la base courante est effectu\u00e9e '
        'automatiquement avant l\u2019\u00e9crasement.',
      ),
      confirmLabel: Text(
        l10n.restoreDatabase,
        style: const TextStyle(color: AppStatus.danger),
      ),
      cancelLabel: Text(l10n.cancel),
      confirmKey: const Key('confirmRestore'),
      cancelKey: const Key('cancelRestore'),
      onConfirm: onConfirm,
    );
  }
}
