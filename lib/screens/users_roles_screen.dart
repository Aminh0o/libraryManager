import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/user_account.dart';
import '../providers/library_provider.dart';
import '../services/api_service.dart' show ApiException;
import '../services/auth_service.dart' show AuthService;
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';
import '../utils/app_date.dart';
import '../widgets/app_states.dart';

/// Users & Roles administration (Phase 10.1c).
///
/// This screen is the OPERATOR-FACING half of the authorization model that the
/// server already enforces on every mutating route (Phase 10.1a/10.1b). It is
/// deliberately thin: every action simply calls the provider, which runs the
/// authoritative [AuthService] on the host and the ADMIN-guarded HTTP surface
/// on a client. Refusals (last-admin, reserved name, duplicate, weak password)
/// are decided by that shared core and surfaced here verbatim — the UI never
/// re-implements (and so can never drift from or bypass) the real rules.
///
/// Visibility/enablement here is a courtesy; a client that hides these buttons
/// is still refused a 403 by the server, and one that forges its way in is
/// refused identically.
class UsersRolesScreen extends StatefulWidget {
  const UsersRolesScreen({super.key});

  @override
  State<UsersRolesScreen> createState() => _UsersRolesScreenState();
}

class _UsersRolesScreenState extends State<UsersRolesScreen> {
  List<UserRecord> _users = const [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    if (!provider.canAdminister) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final users = await provider.listUsers();
      if (!mounted) return;
      setState(() => _users = users);
    } catch (e) {
      if (!mounted) return;
      _showError(l10n, e, fallback: l10n.readAccountFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(AppLocalizations l10n, Object e, {String? fallback}) {
    final msg = fallback == null
        ? _userAdminMessage(l10n, e)
        : '$fallback\n${_userAdminMessage(l10n, e)}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  /// Runs an administrative mutation with a busy guard and reload-on-success,
  /// so the list can never show a state the server has refused.
  Future<void> _mutate(Future<void> Function() action) async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context)!;
    setState(() => _busy = true);
    try {
      await action();
      await _load();
    } catch (e) {
      if (mounted) _showError(l10n, e);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _showCreateDialog() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final created = await showDialog<bool>(
      context: context,
      builder: (_) => _CreateAccountDialog(
        onSubmit: (username, password, role) => provider.createUser(
          username: username,
          password: password,
          role: role,
        ),
      ),
    );
    if (created == true) await _load();
  }

  Future<void> _changeRole(UserRecord user) async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangeRoleDialog(
        initial: user.role,
        onSubmit: (role) => provider.changeUserRole(user.username, role),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _changePassword(UserRecord user) async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final changed = await showDialog<bool>(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        onSubmit: (password) => provider.setUserPassword(
          username: user.username,
          password: password,
        ),
      ),
    );
    if (changed == true) await _load();
  }

  Future<void> _confirmRemove(UserRecord user) async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.removeAccount),
        content: Text(l10n.removeAccountConfirm(user.username)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              l10n.removeAccount,
              style: const TextStyle(color: AppStatus.danger),
            ),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _mutate(() => provider.removeUser(user.username));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    if (!provider.canAdminister) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.usersAndRoles)),
        body: AppEmptyState(
          icon: Icons.lock_outline,
          title: l10n.onlyAdminManagesUsers,
          compact: true,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.usersAndRoles),
        actions: [
          IconButton(
            key: const Key('createAccountButton'),
            tooltip: l10n.createAccount,
            icon: const Icon(Icons.person_add_alt_outlined),
            onPressed: (_loading || _busy) ? null : _showCreateDialog,
          ),
        ],
      ),
      body: _loading
          ? const AppLoadingState()
          : RefreshIndicator(
              onRefresh: _load,
              child: _users.isEmpty
                  ? ListView(
                      children: [
                        AppEmptyState(
                          icon: Icons.people_outline,
                          // Previously this said "No accounts yet" while the
                          // operator was actively signed in as the built-in
                          // administrator — the list came back empty because
                          // `AuthService.users()` only synthesises the admin
                          // row once a password has been stored, and clients
                          // see nothing at all before the first sync. Copy
                          // now reflects the true state: the operator's own
                          // access exists, they just have no NAMED accounts
                          // yet. This is a factual, non-lying empty state.
                          title: l10n.noNamedAccounts,
                          message: l10n.noNamedAccountsHint,
                          compact: true,
                        ),
                      ],
                    )
                  : ListView.separated(
                      itemCount: _users.length,
                      separatorBuilder: (_, _) => const Divider(height: 1),
                      itemBuilder: (context, i) => _row(_users[i], l10n),
                    ),
            ),
    );
  }

  Widget _row(UserRecord user, AppLocalizations l10n) {
    final isBuiltInAdmin = user.username == AuthService.adminUsername;
    return ListTile(
      key: ValueKey('user-${user.username}'),
      enabled: !_busy,
      leading: CircleAvatar(
        backgroundColor: _roleColor(user.role).withValues(alpha: 0.12),
        child: Icon(
          _roleIcon(user.role),
          color: _roleColor(user.role),
          size: AppIcon.lg,
        ),
      ),
      title: Text(user.username),
      subtitle: Text(
        // A raw `DateTime.toString()` (or a stored ISO-8601 string) leaked
        // microseconds and the `T` separator into this subtitle, so operators
        // read "Staff • 2026-09-29T23:30:35.331300". `AppDate.dateTime`
        // normalises it to "Staff • 2026-09-29 23:30", or falls back to just
        // the role label when `createdAt` is absent (the built-in admin has
        // no creation timestamp recorded).
        user.createdAt == null
            ? roleLabel(l10n, user.role)
            : '${roleLabel(l10n, user.role)} • ${AppDate.dateTime(user.createdAt)}',
      ),
      trailing: isBuiltInAdmin
          ? Tooltip(
              message: l10n.roleAdmin,
              child: Icon(
                Icons.shield_outlined,
                color: _roleColor(UserRole.admin),
                size: AppIcon.lg,
              ),
            )
          : PopupMenuButton<String>(
              onSelected: (value) {
                switch (value) {
                  case 'role':
                    _changeRole(user);
                    break;
                  case 'password':
                    _changePassword(user);
                    break;
                  case 'remove':
                    _confirmRemove(user);
                    break;
                }
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: 'role',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.manage_accounts_outlined),
                    title: Text(l10n.changeRole),
                  ),
                ),
                PopupMenuItem(
                  value: 'password',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(Icons.password_outlined),
                    title: Text(l10n.changePassword),
                  ),
                ),
                PopupMenuItem(
                  value: 'remove',
                  child: ListTile(
                    dense: true,
                    leading: const Icon(
                      Icons.delete_outline,
                      color: AppStatus.danger,
                      size: AppIcon.lg,
                    ),
                    title: Text(
                      l10n.removeAccount,
                      style: const TextStyle(color: AppStatus.danger),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  // Role hues reuse the central status palette (a role, like a status, is a
  // meaning-bearing badge rendered as tint + icon + text, never color alone).
  static Color _roleColor(UserRole role) => switch (role) {
    UserRole.admin => AppStatus.reserved,
    UserRole.staff => AppStatus.borrowed,
    UserRole.viewer => AppStatus.archived,
  };

  static IconData _roleIcon(UserRole role) => switch (role) {
    UserRole.admin => Icons.admin_panel_settings_outlined,
    UserRole.staff => Icons.person_outline,
    UserRole.viewer => Icons.visibility_outlined,
  };
}

String roleLabel(AppLocalizations l10n, UserRole role) => switch (role) {
  UserRole.admin => l10n.roleAdmin,
  UserRole.staff => l10n.roleStaff,
  UserRole.viewer => l10n.roleViewer,
};

String roleDescription(AppLocalizations l10n, UserRole role) => switch (role) {
  UserRole.admin => l10n.roleAdminDescription,
  UserRole.staff => l10n.roleStaffDescription,
  UserRole.viewer => l10n.roleViewerDescription,
};

/// Surfaces the concrete, server-authored reason for a user-admin refusal
/// (the format/conflict messages carry no secrets — see the HTTP error
/// middleware), falling back to the generic localized classifier.
String _userAdminMessage(AppLocalizations l10n, Object e) {
  if (e is UserAdminException) return e.message;
  if (e is ApiException &&
      (e.error == 'bad_request' || e.error == 'conflict') &&
      e.message.trim().isNotEmpty) {
    return e.message;
  }
  return describeError(l10n, e);
}

class _CreateAccountDialog extends StatefulWidget {
  const _CreateAccountDialog({required this.onSubmit});

  final Future<void> Function(String username, String password, UserRole role)
  onSubmit;

  @override
  State<_CreateAccountDialog> createState() => _CreateAccountDialogState();
}

class _CreateAccountDialogState extends State<_CreateAccountDialog> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController();
  final _password = TextEditingController();
  UserRole _role = UserRole.staff;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_username.text.trim(), _password.text, _role);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _userAdminMessage(AppLocalizations.of(context)!, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSizing.maxDialogWidth),
      child: AlertDialog(
        title: Text(l10n.createAccount),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  key: const Key('createUsername'),
                  controller: _username,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: l10n.username,
                    helperText: l10n.usernameRules,
                    helperMaxLines: 3,
                  ),
                  validator: (v) {
                    final name = UserRecord.normalizeUsername(v ?? '');
                    if (!UserRecord.isValidUsername(name)) {
                      return l10n.usernameRules;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  key: const Key('createPassword'),
                  controller: _password,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.password,
                    helperText: l10n.passwordMinLength(
                      UserRecord.minPasswordLength,
                    ),
                  ),
                  validator: (v) =>
                      (v == null || v.length < UserRecord.minPasswordLength)
                      ? l10n.passwordMinLength(UserRecord.minPasswordLength)
                      : null,
                ),
                const SizedBox(height: AppSpacing.md),
                _RoleField(
                  value: _role,
                  onChanged: (r) => setState(() => _role = r),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    _error!,
                    style: TextStyle(color: scheme.error),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            key: const Key('createSubmit'),
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.createAccount),
          ),
        ],
      ),
    );
  }
}

class _ChangeRoleDialog extends StatefulWidget {
  const _ChangeRoleDialog({required this.initial, required this.onSubmit});

  final UserRole initial;
  final Future<void> Function(UserRole role) onSubmit;

  @override
  State<_ChangeRoleDialog> createState() => _ChangeRoleDialogState();
}

class _ChangeRoleDialogState extends State<_ChangeRoleDialog> {
  late UserRole _role = widget.initial;
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_role);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _userAdminMessage(AppLocalizations.of(context)!, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSizing.maxDialogWidth),
      child: AlertDialog(
        title: Text(l10n.changeRole),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _RoleField(
              value: _role,
              onChanged: (r) => setState(() => _role = r),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                style: TextStyle(color: scheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.changeRole),
          ),
        ],
      ),
    );
  }
}

class _ChangePasswordDialog extends StatefulWidget {
  const _ChangePasswordDialog({required this.onSubmit});

  final Future<void> Function(String password) onSubmit;

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_password.text);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _userAdminMessage(AppLocalizations.of(context)!, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: AppSizing.maxDialogWidth),
      child: AlertDialog(
        title: Text(l10n.changePassword),
        content: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _password,
                obscureText: true,
                autofocus: true,
                decoration: InputDecoration(
                  labelText: l10n.newPassword,
                  helperText: l10n.passwordMinLength(
                    UserRecord.minPasswordLength,
                  ),
                ),
                validator: (v) =>
                    (v == null || v.length < UserRecord.minPasswordLength)
                    ? l10n.passwordMinLength(UserRecord.minPasswordLength)
                    : null,
              ),
              if (_error != null) ...[
                const SizedBox(height: AppSpacing.md),
                Text(
                  _error!,
                  style: TextStyle(color: scheme.error),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(l10n.changePassword),
          ),
        ],
      ),
    );
  }
}

/// A role selector shared by the create and change dialogs. Rendered as a
/// Material 3 [SegmentedButton] rather than a [DropdownButtonFormField] so
/// the choice never opens an overlay that can occlude the dialog's own
/// Cancel / Create buttons — a real usability failure in the previous build
/// where the operator could not see what they were confirming. With three
/// fixed roles a segmented control also communicates the whole option set
/// at a glance; the currently selected role's description sits directly
/// underneath so the operator reads what they are granting without opening
/// anything.
class _RoleField extends StatelessWidget {
  const _RoleField({required this.value, required this.onChanged});

  final UserRole value;
  final ValueChanged<UserRole> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(l10n.role, style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.xs),
        SegmentedButton<UserRole>(
          segments: [
            for (final r in UserRole.values)
              ButtonSegment<UserRole>(
                value: r,
                label: Text(roleLabel(l10n, r)),
                icon: Icon(_segmentIcon(r)),
              ),
          ],
          selected: {value},
          onSelectionChanged: (s) => onChanged(s.first),
          showSelectedIcon: false,
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          roleDescription(l10n, value),
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  static IconData _segmentIcon(UserRole role) => switch (role) {
    UserRole.admin => Icons.admin_panel_settings_outlined,
    UserRole.staff => Icons.person_outline,
    UserRole.viewer => Icons.visibility_outlined,
  };
}
