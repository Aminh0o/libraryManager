import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../screens/history_screen.dart';
import '../ui/app_tokens.dart';
import '../utils/display_safety.dart';
import '../widgets/app_status_chip.dart';
import '../widgets/password_dialog.dart';

/// Pass 5: per-record audit trail. Renders the last [limit] rows whose audit
/// `details` mention [subject] and a "See all" affordance that opens the
/// global [HistoryScreen] pre-filtered to the same subject (behind the same
/// admin password prompt the dashboard's History quick-action uses, so the
/// audit trail never becomes an easier path to a full dump).
///
/// The section is intentionally read-only. On load error or empty result the
/// honest-omission pattern from Pass 4's dashboard applies: hide the section
/// rather than shout a banner on an ancillary view.
class RecordHistorySection extends StatefulWidget {
  const RecordHistorySection({
    super.key,
    required this.subject,
    required this.title,
    this.limit = 8,
  });

  /// Substring to filter audit rows on (an item code or a member id).
  final String subject;

  /// Localised section title (e.g. "History" for the item profile, "Recent
  /// activity" for a member). Callers supply this so both screens can use
  /// different wording without adding a new l10n key per context.
  final String title;

  final int limit;

  @override
  State<RecordHistorySection> createState() => _RecordHistorySectionState();
}

class _RecordHistorySectionState extends State<RecordHistorySection> {
  List<Map<String, dynamic>> _rows = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final rows = await provider.itemHistory(
      widget.subject,
      limit: widget.limit,
    );
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _loaded = true;
    });
  }

  Future<void> _openAll(AppLocalizations l10n) async {
    final passed = await showPasswordPrompt(context, title: l10n.enterPassword);
    if (!passed || !mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => HistoryScreen(initialSubject: widget.subject),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pass 5 hides the section on any empty read (genuine empty or a repo
    // error that the provider already swallowed to `[]`). This matches the
    // honest-omission principle from Pass 4's dashboard Needs-Attention
    // tiles: an ancillary view should never shout a banner. The operator
    // does not need to distinguish "nothing has ever happened to this
    // record" from "we could not check right now" -- in both cases the
    // correct visible behaviour is "no timeline shown here".
    if (!_loaded || _rows.isEmpty) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.history, size: AppIcon.md, color: scheme.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Text(
                    widget.title,
                    style: txt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: scheme.onSurface,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => _openAll(l10n),
                  child: Text(l10n.seeAllHistory),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            for (var i = 0; i < _rows.length; i++)
              _HistoryRow(entry: _rows[i], isLast: i == _rows.length - 1),
          ],
        ),
      ),
    );
  }
}

/// One compact audit-line row: timestamp + operation chip + free-text details.
/// Every field is parsed through `tryParseTimestamp` / `safeText` because
/// FE2-08 requires stored history rows to be treated as untrusted (legacy
/// shapes, restored dumps, pre-9.7 forged entries).
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.entry, required this.isLast});

  final Map<String, dynamic> entry;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final ts = tryParseTimestamp(entry['timestamp']);
    final timeStr = ts == null
        ? '\u2014'
        : DateFormat.yMMMd().add_jm().format(ts);
    final op = safeText(entry['operation'], fallback: '');
    final details = safeText(entry['details'], fallback: '');
    final color = _opColor(op);
    return Padding(
      padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              timeStr,
              style: txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          AppStatusChip(label: _opLabel(op, l10n), color: color),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              details,
              style: txt.bodyMedium?.copyWith(color: scheme.onSurface),
            ),
          ),
        ],
      ),
    );
  }

  static String _opLabel(String op, AppLocalizations l10n) {
    switch (op) {
      case 'ADD':
        return l10n.operationAdd;
      case 'UPDATE':
        return l10n.operationUpdate;
      case 'DELETE':
        return l10n.operationDelete;
      case 'WIPE':
        return l10n.operationWipe;
      default:
        return op.isEmpty ? '\u2014' : op;
    }
  }

  static Color _opColor(String op) {
    switch (op) {
      case 'ADD':
        return AppStatus.success;
      case 'UPDATE':
        return AppStatus.info;
      case 'DELETE':
        return AppStatus.danger;
      case 'WIPE':
        return AppStatus.warning;
      default:
        return AppStatus.neutral;
    }
  }
}
