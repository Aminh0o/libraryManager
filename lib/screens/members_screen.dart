import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../services/error_messages.dart';
import '../services/managed_media.dart';
import '../models/member.dart';
import '../l10n/app_localizations.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';
import '../widgets/app_toast.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../services/receipt_payload.dart';
import 'package:qr_flutter/qr_flutter.dart';
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

  /// v24: the managed photo path, or null when unset/blank. One honest
  /// accessor so the avatar logic never re-derives "has a photo" differently.
  static String? _photoOf(Member m) {
    final p0 = m.photoPath;
    return (p0 == null || p0.isEmpty) ? null : p0;
  }

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

  void _showQrModal(BuildContext context, Member member) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(member.fullName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: QrImageView(
                data: member.toQrPayload(),
                version: QrVersions.auto,
                size: 200,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              'ID: ${member.memberId}',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            if (member.gender != null) Text('Gender: ${member.gender}'),
            if (member.phone != null) Text(member.phone!),
          ],
        ),
        actions: [
          TextButton.icon(
            icon: const Icon(Icons.print_outlined),
            label: const Text('Print Card'),
            onPressed: () {
              Navigator.pop(context);
              MemberDetailScreen.printMemberCard(context, member);
            },
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
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
        : members
              .where(
                (m) =>
                    m.firstName.toLowerCase().contains(
                      _searchController.text.toLowerCase(),
                    ) ||
                    m.lastName.toLowerCase().contains(
                      _searchController.text.toLowerCase(),
                    ) ||
                    m.memberId.toLowerCase().contains(
                      _searchController.text.toLowerCase(),
                    ),
              )
              .toList();

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
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
                const SizedBox(width: AppSpacing.sm),
                IconButton.filledTonal(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: l10n.scanBarcode,
                  onPressed: () async {
                    final code = await showBarcodeScanner(
                      context,
                      mode: ScannerMode.memberQr,
                    );
                    if (code == null || !mounted) return;
                    final raw = code.trim();
                    final memberId = parseScannedMemberId(raw);
                    if (!context.mounted) return;
                    final match = provider.members
                        .where(
                          (m) =>
                              m.memberId.toLowerCase() ==
                                  memberId.toLowerCase() ||
                              m.memberId.toLowerCase() == raw.toLowerCase(),
                        )
                        .firstOrNull;
                    if (match != null) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                              MemberDetailScreen(memberId: match.memberId),
                        ),
                      );
                    } else {
                      setState(() {
                        _searchController.text = memberId;
                      });
                    }
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: provider.isLoading && members.isEmpty
                // FE-05 parity with the inventory page: while the first
                // member fetch is in flight the list is legitimately empty,
                // so show a loading state rather than the misleading
                // "no members match search" empty card.
                ? const AppLoadingState()
                : filteredMembers.isEmpty
                ? AppEmptyState(
                    icon: Icons.people_outline,
                    // Members had been re-using `noItemsFound` (wrong noun on
                    // a members list). The dedicated `noMembersMatchSearch`
                    // key already existed and now wires up correctly.
                    // A real-UI pass then caught the opposite mistake: an
                    // EMPTY query still claimed "no members match your
                    // search", which reads as a broken search box rather than
                    // an empty book. Say which one it is.
                    title: _searchController.text.isEmpty
                        ? l10n.noMembersYet
                        : l10n.noMembersMatchSearch,
                    compact: true,
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: AppSpacing.huge),
                    itemCount: filteredMembers.length,
                    itemBuilder: (context, index) {
                      final member = filteredMembers[index];
                      final isFemale = member.gender?.toLowerCase() == 'female';
                      final isMale = member.gender?.toLowerCase() == 'male';

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.xs,
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.xs,
                          ),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) =>
                                  MemberDetailScreen(memberId: member.memberId),
                            ),
                          ),
                          leading: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: scheme.primaryContainer,
                                foregroundColor: scheme.onPrimaryContainer,
                                backgroundImage: _photoOf(member) == null
                                    ? null
                                    : FileImage(File(_photoOf(member)!)),
                                child: _photoOf(member) != null
                                    ? null
                                    : member.avatarInitial.isEmpty
                                    ? const Icon(Icons.person, size: AppIcon.md)
                                    : Text(
                                        member.avatarInitial,
                                        style: txt.titleMedium,
                                      ),
                              ),
                              if (isMale || isFemale)
                                Positioned(
                                  bottom: -2,
                                  right: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: isFemale
                                          ? Colors.pink.shade400
                                          : Colors.blue.shade600,
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: scheme.surface,
                                        width: 1.5,
                                      ),
                                    ),
                                    child: Icon(
                                      isFemale ? Icons.female : Icons.male,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  member.fullName,
                                  overflow: TextOverflow.ellipsis,
                                  style: txt.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              if (member.memberType != null &&
                                  member.memberType!.isNotEmpty) ...[
                                const SizedBox(width: AppSpacing.xs),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: scheme.primary.withValues(
                                      alpha: 0.12,
                                    ),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    member.memberType!,
                                    style: txt.labelSmall?.copyWith(
                                      color: scheme.primary,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Row(
                              children: [
                                Text(
                                  'ID: ${member.memberId}',
                                  style: txt.bodySmall?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: scheme.onSurface,
                                  ),
                                ),
                                if (member.phone != null &&
                                    member.phone!.isNotEmpty) ...[
                                  Text(
                                    ' • ${member.phone}',
                                    style: txt.bodySmall?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                                if (member.status != null &&
                                    member.status!.isNotEmpty) ...[
                                  const SizedBox(width: AppSpacing.sm),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 1,
                                    ),
                                    decoration: BoxDecoration(
                                      color: member.status == 'Active'
                                          ? Colors.green.withValues(alpha: 0.15)
                                          : Colors.orange.withValues(
                                              alpha: 0.15,
                                            ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      member.status!,
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: member.status == 'Active'
                                            ? Colors.green.shade800
                                            : Colors.orange.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Direct QR Code Thumbnail Preview
                              InkWell(
                                borderRadius: BorderRadius.circular(6),
                                onTap: () => _showQrModal(context, member),
                                child: Tooltip(
                                  message: 'Scan / View Member QR Code',
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: scheme.outlineVariant,
                                      ),
                                    ),
                                    child: QrImageView(
                                      data: member.toQrPayload(),
                                      version: QrVersions.auto,
                                      size: 38,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              IconButton(
                                icon: const Icon(Icons.print_outlined),
                                tooltip: 'Print Member Card',
                                onPressed: () =>
                                    MemberDetailScreen.printMemberCard(
                                      context,
                                      member,
                                    ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.badge_outlined),
                                tooltip: 'Patron Profile',
                                onPressed: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => MemberDetailScreen(
                                      memberId: member.memberId,
                                    ),
                                  ),
                                ),
                              ),
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
                                      await provider.deleteMember(
                                        member.memberId,
                                      );
                                    } catch (e) {
                                      // FE2-01 parity: a refused delete must
                                      // say so, not vanish silently.
                                      if (context.mounted) {
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              describeError(
                                                AppLocalizations.of(context)!,
                                                e,
                                              ),
                                            ),
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
  late TextEditingController _addressCtrl;
  late TextEditingController _notesCtrl;

  // Phase 5 (v24) enrichment state. The stored values are the canonical
  // English constants (mirroring how item statuses are stored); the pickers
  // only localize the LABELS, so filters and LAN clients agree on one value
  // regardless of the UI language.
  static const List<String> _genderValues = ['male', 'female', 'other'];
  static const List<String> _typeValues = ['Student', 'Teacher', 'Standard'];
  static const List<String> _statusValues = ['Active', 'Expired', 'Suspended'];

  String? _gender;
  String? _memberType;
  String? _memberStatus;
  DateTime? _expiryDate;

  /// Managed photo path as it is STORED (from the member row). Null = none.
  String? _photoPath;

  /// Pending import chosen this session; applied on save. Kept separate from
  /// [_photoPath] so cancelling the dialog never touches the stored file, and
  /// saving a REVERT (new pick removed) deletes the old copy exactly once.
  String? _pendingPhotoSource;
  bool _photoCleared = false;

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
    _addressCtrl = TextEditingController(text: widget.member?.address);
    _notesCtrl = TextEditingController(text: widget.member?.notes);
    _gender = widget.member?.gender;
    _memberType = widget.member?.memberType;
    _memberStatus = widget.member?.status;
    _expiryDate = widget.member?.expiryDate;
    _photoPath = widget.member?.photoPath;
    _expectedVersion = widget.member?.rowVersion ?? 0;
  }

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    _idCtrl.dispose();
    _phoneCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _genderLabel(AppLocalizations l10n, String v) =>
      switch (v.toLowerCase()) {
        'male' => l10n.genderMale,
        'female' => l10n.genderFemale,
        _ => l10n.genderOther,
      };

  String? _typeLabel(AppLocalizations l10n, String v) => switch (v) {
    'Student' => l10n.typeStudent,
    'Teacher' => l10n.typeTeacher,
    _ => l10n.typeStandard,
  };

  String? _statusLabel(AppLocalizations l10n, String v) => switch (v) {
    'Active' => l10n.statusActive,
    'Expired' => l10n.statusExpired,
    _ => l10n.statusSuspended,
  };

  /// Pick an image and stage it for import (applied on save). Only offered
  /// for an EXISTING member: a brand-new row has no stable file name yet, and
  /// inventing one that changes at save time is how orphan files pile up.
  Future<void> _pickPhoto() async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['png', 'jpg', 'jpeg'],
    );
    final path = result?.files.single.path;
    if (path == null || !mounted) return;
    setState(() {
      _pendingPhotoSource = path;
      _photoCleared = false;
    });
    // Size honesty BEFORE save (same 2 MB ceiling the managed import enforces
    // at import), so a camera dump is rejected with a toast rather than a
    // silent failure on Save.
    try {
      final length = await File(path).length();
      if (length > ManagedMedia.maxBytes) {
        if (!mounted) return;
        setState(() => _pendingPhotoSource = null);
        showAppToastOn(messenger, l10n.photoTooLarge, kind: ToastKind.error);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _pendingPhotoSource = null);
      showAppToastOn(messenger, l10n.photoFailed, kind: ToastKind.error);
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      final provider = Provider.of<LibraryProvider>(context, listen: false);
      final l10n = AppLocalizations.of(context)!;
      final messenger = ScaffoldMessenger.of(context);

      final String? newPhotoPath;
      try {
        newPhotoPath = _photoCleared
            ? null
            : _pendingPhotoSource == null
            ? _photoPath
            : await ManagedMedia.importImage(
                sourcePath: _pendingPhotoSource!,
                folder: 'members',
                // Card id is the stable file key (immutable primary path:
                // edits keep the id, AUTO ids are generated before any photo
                // import because the button only exists on an existing row).
                fileName: widget.member!.memberId,
              );
      } on MediaException {
        if (mounted) {
          showAppToastOn(messenger, l10n.photoFailed, kind: ToastKind.error);
        }
        return; // keep the dialog open; nothing stored changed
      }
      // Replace-or-clear semantics: a save that removes/changes the photo
      // retires the previous managed copy. Best-effort, after the write path
      // was computed — removeImage never throws.
      if (_photoPath != null && _photoPath != newPhotoPath) {
        await ManagedMedia.removeImage(_photoPath);
      }

      // copyWith over the READ row (when editing): every field the dialog
      // does not own — row_version above all — survives exactly as stored.
      final member = widget.member == null
          ? Member(
              firstName: _firstNameCtrl.text,
              lastName: _lastNameCtrl.text,
              memberId: 'AUTO', // Auto-generate for new members
              phone: _phoneCtrl.text.isEmpty ? null : _phoneCtrl.text,
              email: _emailCtrl.text.isEmpty ? null : _emailCtrl.text,
              registeredAt: DateTime.now(),
              memberType: _memberType,
              status: _memberStatus,
              expiryDate: _expiryDate,
              address: _addressValue,
              notes: _notesValue,
              gender: _gender,
            )
          : widget.member!.copyWith(
              firstName: _firstNameCtrl.text,
              lastName: _lastNameCtrl.text,
              memberId: _idCtrl.text,
              phone: _phoneCtrl.text.isEmpty ? null : _phoneCtrl.text,
              email: _emailCtrl.text.isEmpty ? null : _emailCtrl.text,
              memberType: _memberType,
              status: _memberStatus,
              expiryDate: _expiryDate,
              photoPath: newPhotoPath,
              address: _addressValue,
              notes: _notesValue,
              gender: _gender,
            );

      try {
        if (widget.member == null) {
          await provider.addMember(member);
        } else {
          // TX-06: send the version this dialog read. A stale whole-row edit is
          // refused (409) instead of silently overwriting a newer row.
          await provider.updateMember(
            member,
            expectedVersion: _expectedVersion,
          );
        }
        if (mounted) Navigator.pop(context);
      } catch (e) {
        // Keep the dialog open (input preserved) and surface a categorized error.
        // On an edit collision, re-read the current version so ONE retry succeeds
        // rather than 409-looping on the stale token.
        if (widget.member != null) {
          await _reconcileVersion(provider);
        }
        if (mounted) {
          messenger.showSnackBar(
            SnackBar(content: Text(describeError(l10n, e))),
          );
        }
      }
    }
  }

  String? get _addressValue =>
      _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim();
  String? get _notesValue =>
      _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim();

  /// What the avatar previews / the row will store after save: the pending
  /// pick previews immediately (raw path — it is a read-only display until
  /// Save imports it), an explicit clear removes the stored path entirely.
  String? get _effectivePhotoPath {
    if (_photoCleared) return null;
    return _pendingPhotoSource ?? _photoPath;
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
    final fresh = provider.members.where(
      (m) => (id != null && m.id == id) || (id == null && m.memberId == cardId),
    );
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
                // DEF-05: member ids are machine-format codes, LTR in every UI.
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(
                  labelText: widget.member == null
                      ? l10n.memberIdAuto
                      : l10n.memberIdCode,
                  suffixIcon: widget.member == null
                      ? Icon(
                          Icons.auto_awesome,
                          size: AppIcon.md,
                          color: scheme.primary,
                        )
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
                      decoration: InputDecoration(
                        labelText: '${l10n.firstName}*',
                      ),
                      validator: (v) => v!.isEmpty ? l10n.requiredField : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameCtrl,
                      decoration: InputDecoration(
                        labelText: '${l10n.lastName}*',
                      ),
                      validator: (v) => v!.isEmpty ? l10n.requiredField : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _phoneCtrl,
                // DEF-05: phone numbers keep their order under RTL.
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: l10n.phone),
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _emailCtrl,
                // DEF-05: email addresses are always LTR.
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: l10n.email),
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: AppSpacing.md),
              // Phase 5 (v24) enrichment. Every control below is optional:
              // NULL means "not set" and renders as such — nothing is invented.
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _gender,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l10n.gender),
                      items: [
                        DropdownMenuItem(value: null, child: Text(l10n.notSet)),
                        for (final v in _genderValues)
                          DropdownMenuItem(
                            value: v,
                            child: Text(_genderLabel(l10n, v)!),
                          ),
                      ],
                      onChanged: (v) => setState(() => _gender = v),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: DropdownButtonFormField<String?>(
                      initialValue: _memberType,
                      isExpanded: true,
                      decoration: InputDecoration(labelText: l10n.memberType),
                      items: [
                        DropdownMenuItem(value: null, child: Text(l10n.notSet)),
                        for (final v in _typeValues)
                          DropdownMenuItem(
                            value: v,
                            child: Text(_typeLabel(l10n, v)!),
                          ),
                      ],
                      onChanged: (v) => setState(() => _memberType = v),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              DropdownButtonFormField<String?>(
                initialValue: _memberStatus,
                isExpanded: true,
                decoration: InputDecoration(labelText: l10n.memberStatus),
                items: [
                  DropdownMenuItem(value: null, child: Text(l10n.notSet)),
                  for (final v in _statusValues)
                    DropdownMenuItem(
                      value: v,
                      child: Text(_statusLabel(l10n, v)!),
                    ),
                ],
                onChanged: (v) => setState(() => _memberStatus = v),
              ),
              const SizedBox(height: AppSpacing.md),
              // ISO dates are machine-format values: pinned LTR (DEF-05).
              // readOnly + picker: free typing would store un-parseable text.
              TextFormField(
                controller: TextEditingController(
                  text: _expiryDate == null
                      ? ''
                      : '${_expiryDate!.year}-'
                            '${_expiryDate!.month.toString().padLeft(2, '0')}-'
                            '${_expiryDate!.day.toString().padLeft(2, '0')}',
                ),
                textDirection: TextDirection.ltr,
                readOnly: true,
                decoration: InputDecoration(
                  labelText: l10n.expiryDate,
                  suffixIcon: const Icon(Icons.calendar_today_outlined),
                  // A no-op tap keeps the field focusable-free and honest: the
                  // picker below is the only writer.
                  hintText: l10n.notSet,
                ),
                onTap: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate:
                        _expiryDate ??
                        DateTime.now().add(const Duration(days: 365)),
                    firstDate: DateTime(2000),
                    lastDate: DateTime(2100),
                  );
                  if (picked != null) {
                    setState(() => _expiryDate = picked);
                  } else if (_expiryDate != null && mounted) {
                    // Explicit clear affordance lives in the label tap; a
                    // cancelled picker changes nothing (standard contract).
                  }
                },
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _addressCtrl,
                decoration: InputDecoration(labelText: l10n.address),
              ),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _notesCtrl,
                decoration: InputDecoration(labelText: l10n.notes),
                maxLines: 3,
                minLines: 1,
              ),
              // Photo management exists only for a saved row: a brand-new
              // member has no stable file key yet (the button's absence is
              // the honest affordance, not a hidden failure).
              if (widget.member != null) ...[
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    CircleAvatar(
                      radius: 24,
                      backgroundColor: scheme.primaryContainer,
                      foregroundColor: scheme.onPrimaryContainer,
                      backgroundImage: _effectivePhotoPath == null
                          ? null
                          : FileImage(File(_effectivePhotoPath!)),
                      child: _effectivePhotoPath == null
                          ? const Icon(Icons.person, size: AppIcon.lg)
                          : null,
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: TextButton.icon(
                        onPressed: _pickPhoto,
                        icon: const Icon(Icons.add_a_photo_outlined),
                        label: Text(l10n.choosePhoto),
                      ),
                    ),
                    if (_effectivePhotoPath != null)
                      IconButton(
                        tooltip: l10n.removePhoto,
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => setState(() {
                          _pendingPhotoSource = null;
                          _photoCleared = true;
                        }),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(onPressed: _save, child: Text(l10n.save)),
      ],
    );
  }
}
