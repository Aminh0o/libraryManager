import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../ui/app_tokens.dart';

class PasswordManagementScreen extends StatefulWidget {
  const PasswordManagementScreen({super.key});

  @override
  State<PasswordManagementScreen> createState() =>
      _PasswordManagementScreenState();
}

class _PasswordManagementScreenState extends State<PasswordManagementScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  // FE2-11: whether an admin password is CURRENTLY enforced (authoritatively,
  // i.e. against the server credential on a host), which decides whether the
  // form must first prove the existing password before changing it. Resolved
  // async because on the host the answer comes from the server-side auth store,
  // NOT the local SharedPreferences copy that could be blank while a real
  // credential is in force (the old hole).
  bool _needsOldPassword = false;

  @override
  void initState() {
    super.initState();
    _loadEnforcement();
  }

  Future<void> _loadEnforcement() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final active = await provider.passwordEnforcementActive();
    if (mounted) setState(() => _needsOldPassword = active);
  }

  @override
  void dispose() {
    _oldPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.changePassword)),
      body: Center(
        child: SingleChildScrollView(
          padding: AppSpacing.allXxl,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSizing.maxFormWidth),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_needsOldPassword) ...[
                    TextFormField(
                      key: const Key('oldPassword'),
                      controller: _oldPasswordController,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.currentPassword,
                        prefixIcon: const Icon(
                          Icons.lock_outline,
                          size: AppIcon.md,
                        ),
                      ),
                      // FE2-11: only presence is checked in this (synchronous)
                      // validator; CORRECTNESS is verified authoritatively against
                      // the server credential on submit, because that check is async
                      // and so cannot live here. The weak local `checkPassword` is
                      // no longer trusted for this decision.
                      validator: (val) {
                        if (val == null || val.isEmpty) {
                          return l10n.passwordRequired;
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppSpacing.xl),
                  ],
                  TextFormField(
                    key: const Key('newPassword'),
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.newPassword,
                      prefixIcon: const Icon(
                        Icons.lock_reset_outlined,
                        size: AppIcon.md,
                      ),
                    ),
                    validator: (val) {
                      if (val == null || val.isEmpty) {
                        return l10n.passwordRequired;
                      }
                      if (val.length < 4) {
                        return l10n.minPasswordLength;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.xl),
                  TextFormField(
                    key: const Key('confirmPassword'),
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: l10n.confirmNewPassword,
                      prefixIcon: const Icon(
                        Icons.lock_outline,
                        size: AppIcon.md,
                      ),
                    ),
                    validator: (val) {
                      if (val != _newPasswordController.text) {
                        return l10n.passwordsDoNotMatch;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: AppSpacing.huge),
                  FilledButton(
                    key: const Key('savePassword'),
                    onPressed: () async {
                      if (!_formKey.currentState!.validate()) return;
                      final messenger = ScaffoldMessenger.of(context);
                      final navigator = Navigator.of(context);
                      final errorColor = Theme.of(context).colorScheme.error;
                      // FE2-11: prove the current password against the authoritative
                      // (server-side on a host) credential BEFORE overwriting it, so
                      // a host whose local prefs copy is empty can no longer change
                      // or reset the admin password without knowing it.
                      if (_needsOldPassword) {
                        final ok = await provider.verifyAdminPassword(
                          _oldPasswordController.text,
                        );
                        if (!mounted) return;
                        if (!ok) {
                          messenger.showSnackBar(
                            SnackBar(
                              content: Text(l10n.wrongPassword),
                              backgroundColor: errorColor,
                            ),
                          );
                          return;
                        }
                      }
                      await provider.changePassword(
                        _newPasswordController.text,
                      );
                      if (mounted) {
                        messenger.showSnackBar(
                          SnackBar(content: Text(l10n.passwordUpdated)),
                        );
                        navigator.pop();
                      }
                    },
                    child: Text(l10n.save),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
