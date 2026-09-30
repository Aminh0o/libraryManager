import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/library_item.dart';
import '../ui/app_tokens.dart';
import 'app_status_chip.dart';

/// Item-status control for the inventory grid.
///
/// BL-05 (Phase 11) made a title's status ALWAYS the rollup of its physical
/// copies, and Phase 12 moved the real control to a per-copy condition editor
/// on the Item Details screen. This cell is therefore a READ-ONLY derived chip
/// for everyone — host and client alike. The earlier design let the host edit a
/// title's status inline; that is now misleading (any such write is overridden
/// by, or validated against, the copy ledger), so the editor has been removed
/// rather than left to silently no-op or throw.
///
/// The chip localizes and colours the full copy-derived vocabulary
/// (Disponible / Emprunté / Réservé / En Réparation / Perdu / Archivé) and falls
/// back to a neutral grey + raw text for any legacy value it cannot translate,
/// so it never misrepresents the stored state (FE2-06).
class ItemStatusCell extends StatelessWidget {
  const ItemStatusCell({super.key, required this.status, this.isHost = false});

  /// The raw stored status string for the row.
  final String status;

  /// Retained for call-site compatibility; the cell renders read-only either
  /// way now that status is derived from copies (Phase 12).
  final bool isHost;

  /// Colour associated with a status. The string literals mirror the
  /// [CopyState] storage values (kept as literals because `switch` case labels
  /// must be compile-time constants). The grey fallback covers legacy / DB-only
  /// values (e.g. 'Payé') that are outside the copy-derived vocabulary.
  ///
  /// Phase C (frontend reconstruction): the hues come from the one centralized
  /// [AppStatus] palette, so a status reads identically in the inventory grid,
  /// item detail and every later screen (previously each chip invented its own
  /// Material swatch and the same meaning drifted between surfaces).
  static Color statusColor(String status) {
    switch (status) {
      case ItemStatus.disponible:
        return AppStatus.available;
      case ItemStatus.emprunte:
        return AppStatus.borrowed;
      case ItemStatus.reserve:
        return AppStatus.reserved;
      case ItemStatus.endommage:
        return AppStatus.damaged;
      case 'En Réparation':
        return AppStatus.repair;
      case 'Perdu':
        return AppStatus.lost;
      case 'Archivé':
        return AppStatus.archived;
      default:
        return AppStatus.neutral;
    }
  }

  /// Localizes a known status, falling through to the raw value for any
  /// status the app has no translation for.
  static String localize(String status, AppLocalizations l10n) {
    switch (status) {
      case ItemStatus.disponible:
        return l10n.statusDisponible;
      case ItemStatus.emprunte:
        return l10n.statusEmprunte;
      case ItemStatus.reserve:
        return l10n.statusReserve;
      case ItemStatus.endommage:
        return l10n.statusEndommage;
      case 'En Réparation':
        return l10n.statusEnReparation;
      case 'Perdu':
        return l10n.statusPerdu;
      case 'Archivé':
        return l10n.statusArchive;
      default:
        return status;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AppStatusChip(
      label: localize(status, l10n),
      color: statusColor(status),
    );
  }
}
