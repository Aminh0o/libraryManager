import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../services/error_messages.dart';
import '../models/member.dart';
import '../l10n/app_localizations.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';
import 'member_detail_screen.dart';

/// Phase G (frontend reconstruction): presentation-only rebuild of the
/// members tab. The orange AppBar the shell already titles (double header) is
/// gone, the search field / cards / avatars / action icons consume the tokens,
/// and deletion now reports failure honestly instead of swallowing the throw
/// (same FE2-01 await-and-surface contract every other destructive write has).
/// The client-side search filter and the TX-06 dialog logic are untouched.
class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  final TextEditingController _searchController = TextEditingController();
  
  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _showMemberDialog({Member? member}) {
    showDialog(
      context: context,
      builder: (context) => _MemberDialog(member: member),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final members = provider.members;
    
    // Simple client-side search for members
    final filteredMembers = _searchController.text.isEmpty
        ? members
        : members.where((m) => 
            m.firstName.toLowerCase().contains(_searchController.text.toLowerCase()) || 
            m.lastName.toLowerCase().contains(_searchController.text.toLowerCase()) ||
            m.memberId.toLowerCase().contains(_searchController.text.toLowerCase())
          ).toList();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                labelText: l10n.search,
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchController.text.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          setState(() {
                            _searchController.clear();
                          });
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() {}),
            ),
          ),
          Expanded(
            child: filteredMembers.isEmpty
                ? AppEmptyState(
                    icon: Icons.people_outline,
                    // Members had been re-using `noItemsFound` (wrong noun on
                    // a members list). The dedicated `noMembersMatchSearch`
                    // key already existed and now wires up correctly.
                    title: l10n.noMembersMatchSearch,
                    compact: true,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.huge),
                    itemCount: filteredMembers.length,
                    itemBuilder: (context, index) {
                      final member = filteredMembers[index];
                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.xs,
                        ),
                        child: ListTile(
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MemberDetailScreen(
                                  memberId: member.memberId),
                            ),
                          ),
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                            child: member.avatarInitial.isEmpty
                                ? const Icon(
                                    Icons.person,
                                    size: AppIcon.md,
                                  )
                                : Text(
                                    member.avatarInitial,
                                    style: txt.titleMedium,
                                  ),
                          ),
                          title: Text(
                            member.fullName,
                            style: txt.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            'ID: ${member.memberId} • ${member.phone ?? l10n.noPhone}',
                            style: txt.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.edit_outlined),
                                tooltip: l10n.editMember,
                                onPressed: () =>
                                    _showMemberDialog(member: member),
                              ),
                              IconButton(
                                icon: Icon(
                                  Icons.delete_outline,
                                  color: scheme.error,
                                ),
                                // A destructive action labelled with the wrong
                                // noun ("Delete Item" on a member row) is a
                                // data-integrity trap. Now uses `deleteMember`
                                // throughout the tooltip, dialog title, and
                                // confirm button, plus a members-specific
                                // body that warns about unsettled loans.
                                tooltip: l10n.deleteMember,
                                onPressed: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (context) => AlertDialog(
                                      title: Text(l10n.deleteMember),
                                      content: Text(l10n.confirmDeleteMember),
                                      actions: [
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, false),
                                          child: Text(l10n.cancel),
                                        ),
                                        TextButton(
                                          onPressed: () =>
                                              Navigator.pop(context, true),
                                          style: TextButton.styleFrom(
                                            foregroundColor: scheme.error,
                                          ),
                                          child: Text(l10n.deleteMember),
                                        ),
                                      ],
                                    ),
                                  );

                                  if (confirm == true) {
                                    try {
                                      await provider
                                          .deleteMember(member.memberId);
                                    } catch (e) {
                                      // FE2-01 parity: a refused delete must
                                      // say so, not vanish silently.
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(context)
                                            .showSnackBar(
                                              SnackBar(
                                                content: Text(describeError(
                                                  AppLocalizations.of(context)!,
                                                  e,
                                                )),
                                              ),
                                            );
                                      }
                                    }
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showMemberDialog(),
        icon: const Icon(Icons.add),
        label: Text(l10n.addMember),
      ),
    );
  }
}

class _MemberDialog extends StatefulWidget {
  final Member? member;

  const _MemberDialog({this.member});

  @override
  State<_MemberDialog> createState() => _MemberDialogState();
}

class _MemberDialogState extends State<_MemberDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _firstNameCtrl;
  late TextEditingController _lastNameCtrl;
  late TextEditingController _idCtrl;
  late TextEditingController _phoneCtrl;
  late TextEditingController _emailCtrl;

  // TX-06: the row_version this dialog READ. Sent as the optimistic-concurrency
  // token on an edit save so a lost race is refused (409) rather than clobbering
  // a newer row. Refreshed after a conflict so ONE retry targets the current
  // version instead of looping on the stale token.
  int _expectedVersion = 0;

  @override
  void initState() {
    super.initState();
    _firstNameCtrl = TextEditingController(text: widget.member?.firstName);
    _lastNameCtrl = TextEditingController(text: widget.member?.lastName);
    _idCtrl = TextEditingController(text: widget.member?.memberId);
    _phoneCtrl = TextEditingController(text: widget.member?.phone);
    _emailCtrl = TextEditingController(text: widget.member?.email);
    _expectedVersion = widget.member?.rowVersion ?? 0;
  }
  
  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _idCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<LibraryProvider>(context, listen: false);
      
      final member = Member(
        id: widget.member?.id,
        firstName: _firstNameCtrl.text,
        lastName: _lastNameCtrl.text,
        memberId: widget.member == null ? 'AUTO' : _idCtrl.text, // Auto-generate for new members
        phone: _phoneCtrl.text.isEmpty ? null : _phoneCtrl.text,
        email: _emailCtrl.text.isEmpty ? null : _emailCtrl.text,
        registeredAt: widget.member?.registeredAt ?? DateTime.now(),
      );

      try {
        if (widget.member == null) {
          await provider.addMember(member);
        } else {
          // TX-06: send the version this dialog read. A stale whole-row edit is
          // refused (409) instead of silently overwriting a newer row.
          await provider.updateMember(member, expectedVersion: _expectedVersion);
        }
        if (mounted) Navigator.pop(context);
      } catch (e) {
        // Keep the dialog open (input preserved) and surface a categorized error.
        // On an edit collision, re-read the current version so ONE retry succeeds
        // rather than 409-looping on the stale token.
        if (widget.member != null) {
          await _reconcileVersion(provider);
        }
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(describeError(AppLocalizations.of(context)!, e))));
      }
    }
  }

  /// TX-06: after a refused (conflicted) whole-row member edit, re-read the
  /// CURRENT stored `row_version` for this member so the next Save carries a
  /// fresh token. Reloads the member list and matches on the row's `id` (the
  /// immutable primary key), falling back to the card id. Best-effort: any
  /// failure simply leaves the previous token in place; typed input is untouched.
  Future<void> _reconcileVersion(LibraryProvider provider) async {
    try {
      await provider.reload();
    } catch (_) {
      return; // reload failed (e.g. still offline); keep the old token
    }
    if (!mounted) return;
    final id = widget.member!.id;
    final cardId = widget.member!.memberId;
    final fresh = provider.members.where((m) =>
        (id != null && m.id == id) || (id == null && m.memberId == cardId));
    if (fresh.isNotEmpty) {
      setState(() => _expectedVersion = fresh.first.rowVersion);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.member == null ? l10n.addMember : l10n.editMember),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _idCtrl,
                decoration: InputDecoration(
                  labelText: widget.member == null
                      ? l10n.memberIdAuto
                      : l10n.memberIdCode,
                  suffixIcon: widget.member == null
                      ? Icon(Icons.auto_awesome,
                          size: AppIcon.md, color: scheme.primary)
                      : null,
                ),
                readOnly: widget.member == null, // Read-only for new members
                enabled: widget.member != null, // Disabled for new members
              ),
              const SizedBox(height: AppSpacing.md),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameCtrl,
                      decoration: InputDecoration(labelText: '${l10n.firstName}*'),
                      validator: (v) =>
                          v!.isEmpty ? l10n.requiredField : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameCtrl,
                      decoration: InputDecoration(labelText: '${l10n.lastName}*'),
                      validator: (v) =>
                          v!.isEmpty ? l10n.requiredField : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phoneCtrl,
                decoration: InputDecoration(labelText: l10n.phone),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _emailCtrl,
                decoration: InputDecoration(labelText: l10n.email),
                keyboardType: TextInputType.emailAddress,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: _save, child: Text(l10n.save)),
      ],
    );
  }
}
