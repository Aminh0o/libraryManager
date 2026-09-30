import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../ui/app_tokens.dart';
import 'confirm_action_dialog.dart';

/// FE2-01/02 (P9-9.28, generalized in P9-9.29): the item-delete confirmation.
///
/// The former inline dialog called `provider.deleteItem(code)` WITHOUT awaiting
/// and popped immediately, so a failed delete closed the dialog and the row
/// silently stayed with no error. This is a thin, item-specific wrapper over
/// [ConfirmActionDialog], which owns the await-then-close + busy + error logic.
class ItemDeleteDialog extends StatelessWidget {
  const ItemDeleteDialog({
    super.key,
    required this.itemLabel,
    required this.onConfirm,
  });

  /// Identifier shown in the confirmation message (the item's full code).
  final String itemLabel;

  /// Performs the actual deletion. Must return a [Future] that completes on
  /// success and throws on failure; the dialog awaits it.
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ConfirmActionDialog(
      title: Text(l10n.deleteItem),
      // Previously this line was a hard-coded French string ("Etes-vous sûr
      // de vouloir supprimer cet élément ...") that rendered to every locale.
      // The delete confirmation is a destructive-action prompt; shipping it
      // in a language the operator does not read is a data-integrity risk.
      // Uses the parameterised `confirmDeleteItemNamed` key so the item code
      // is still visible in the body.
      content: Text(l10n.confirmDeleteItemNamed(itemLabel)),
      confirmLabel: Text(
        l10n.deleteItem,
        style: const TextStyle(color: AppStatus.danger),
      ),
      cancelLabel: Text(l10n.cancel),
      confirmKey: const Key('confirmDelete'),
      cancelKey: const Key('cancelDelete'),
      onConfirm: onConfirm,
    );
  }
}
