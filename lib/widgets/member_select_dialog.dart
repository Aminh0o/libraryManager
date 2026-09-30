import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/member.dart';
import '../providers/library_provider.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';

/// Core Workflow Recovery: reusable "pick a member" dialog.
///
/// Used by the item-detail action bar (checkout / reserve from the item
/// profile), so the operator never has to leave the record to complete the
/// workflow. Returns the selected [Member] or `null` on cancel / dismiss.
///
/// Design constraints:
/// - Search is client-side against `provider.members` (name or member ID) —
///   the member table is small enough for the in-memory list to be the
///   authoritative source; no extra network round-trip per keystroke.
/// - Empty query shows the full list (alphabetical). Non-empty query filters
///   case-insensitively against both fullName and memberId.
/// - No results renders the shared [AppEmptyState] so the message matches the
///   rest of the app in light/dark/RTL.
class MemberSelectDialog extends StatefulWidget {
  const MemberSelectDialog({super.key, this.title});

  /// Optional override of the dialog heading. Defaults to
  /// `AppLocalizations.selectMember` (existing key) so callers do not need to
  /// pass anything for the common case.
  final String? title;

  /// Convenience helper mirroring the app's other `showXxxDialog` patterns.
  static Future<Member?> show(BuildContext context, {String? title}) {
    return showDialog<Member>(
      context: context,
      builder: (ctx) => MemberSelectDialog(title: title),
    );
  }

  @override
  State<MemberSelectDialog> createState() => _MemberSelectDialogState();
}

class _MemberSelectDialogState extends State<MemberSelectDialog> {
  final TextEditingController _ctrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  List<Member> _filter(List<Member> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      final sorted = [...all]
        ..sort((a, b) => a.fullName.toLowerCase().compareTo(
            b.fullName.toLowerCase()));
      return sorted;
    }
    return all.where((m) {
      return m.fullName.toLowerCase().contains(q) ||
          m.memberId.toLowerCase().contains(q);
    }).toList()
      ..sort((a, b) =>
          a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final matches = _filter(provider.members);
    return AlertDialog(
      title: Text(widget.title ?? l10n.selectMember),
      content: SizedBox(
        width: 480,
        height: 460,
        child: Column(
          children: [
            TextField(
              controller: _ctrl,
              autofocus: true,
              decoration: InputDecoration(
                hintText: l10n.memberSearchHint,
                prefixIcon: const Icon(Icons.search, size: AppIcon.md),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: AppSpacing.md),
            Expanded(
              child: matches.isEmpty
                  ? AppEmptyState(
                      icon: Icons.person_off_outlined,
                      title: l10n.noMembersMatchSearch,
                      compact: true,
                    )
                  : ListView.separated(
                      itemCount: matches.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) {
                        final m = matches[i];
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                            child: Text(
                              m.fullName.isNotEmpty
                                  ? m.fullName[0].toUpperCase()
                                  : '?',
                            ),
                          ),
                          title: Text(m.fullName),
                          subtitle: Text(m.memberId),
                          onTap: () => Navigator.of(context).pop(m),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
      ],
    );
  }
}
