import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';

class PasswordManagementScreen extends StatefulWidget {
  const PasswordManagementScreen({super.key});

  @override
  State<PasswordManagementScreen> createState() => _PasswordManagementScreenState();
}

class _PasswordManagementScreenState extends State<PasswordManagementScreen> {
  final _oldPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

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
      appBar: AppBar(
        title: Text(l10n.changePassword),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (provider.hasAdminPassword) ...[
                TextFormField(
                  controller: _oldPasswordController,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.currentPassword,
                    border: const OutlineInputBorder(),
                    filled: true,
                    fillColor: Colors.grey[50],
                  ),
                  validator: (val) {
                    if (val == null || val.isEmpty) return l10n.passwordRequired;
                    if (!provider.checkPassword(val)) return l10n.wrongPassword;
                    return null;
                  },
                ),
                const SizedBox(height: 20),
              ],
              TextFormField(
                controller: _newPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.newPassword,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                validator: (val) {
                  if (val == null || val.isEmpty) return l10n.passwordRequired;
                  if (val.length < 4) return l10n.minPasswordLength;
                  return null;
                },
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: _confirmPasswordController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.confirmNewPassword,
                  border: const OutlineInputBorder(),
                  filled: true,
                  fillColor: Colors.grey[50],
                ),
                validator: (val) {
                  if (val != _newPasswordController.text) return l10n.passwordsDoNotMatch;
                  return null;
                },
              ),
              const SizedBox(height: 40),
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    final messenger = ScaffoldMessenger.of(context);
                    final navigator = Navigator.of(context);
                    await provider.changePassword(_newPasswordController.text);
                    if (mounted) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(l10n.passwordUpdated)),
                      );
                      navigator.pop();
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                child: Text(l10n.save),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
