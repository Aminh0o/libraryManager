import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import 'code_management_screen.dart';
import 'attribute_management_screen.dart';
import 'history_screen.dart';
import 'password_management_screen.dart';
import 'help_center_screen.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../services/update_service.dart';
import '../services/onboarding_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _ipController;
  late bool _isHost;
  bool _canEditSettings = false;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    _ipController = TextEditingController(text: provider.hostIp);
    _isHost = provider.isHost;
  }

  @override
  void dispose() {
    _ipController.dispose();
    super.dispose();
  }

  void _saveSettings() {
    Provider.of<LibraryProvider>(context, listen: false).updateSettings(
      _isHost,
      _ipController.text,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.settings),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Mode',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            CheckboxListTile(
              title: const Text('Débloquer les modifications (requiert mot de passe)'),
              value: _canEditSettings,
              onChanged: (val) async {
                if (val == true) {
                  final passed = await _showPasswordPrompt(context, title: l10n.enterPassword);
                  if (passed) {
                    setState(() => _canEditSettings = true);
                  }
                } else {
                  setState(() => _canEditSettings = false);
                }
              },
            ),
            RadioListTile<bool>(
              title: const Text('Host (Main PC - Server)'),
              value: true,
              // ignore: deprecated_member_use
              groupValue: _isHost,
              // ignore: deprecated_member_use
              onChanged: _canEditSettings ? (value) {
                setState(() {
                  _isHost = value!;
                });
              } : null,
            ),
            RadioListTile<bool>(
              title: const Text('Client (Stock PC)'),
              value: false,
              // ignore: deprecated_member_use
              groupValue: _isHost,
              // ignore: deprecated_member_use
              onChanged: _canEditSettings ? (value) {
                setState(() {
                  _isHost = value!;
                });
              } : null,
            ),
            const Divider(),
            const SizedBox(height: 16),
            TextField(
              controller: _ipController,
              decoration: const InputDecoration(
                labelText: 'Host IP Address',
                helperText:
                    'Enter the IP address of the Main PC (e.g., 192.168.1.50)',
                border: OutlineInputBorder(),
              ),
              enabled: _canEditSettings && !_isHost, // Only needed for client
            ),
            const SizedBox(height: 10),
            if (!_isHost) 
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.qr_code_scanner, color: Colors.blue),
                  title: Text(l10n.scanServerCode),
                  subtitle: Text(l10n.scanServerDescription),
                  onTap: () async {
                     final messenger = ScaffoldMessenger.of(context);
                     final savedText = l10n.savedSuccessfully;
                     final code = await showBarcodeScanner(context);
                     if (!mounted) return;
                     if (code != null && code.startsWith('LIB_SYNC:')) {
                       final ip = code.split(':').last;
                       setState(() {
                         _ipController.text = ip;
                       });
                       messenger.showSnackBar(
                         SnackBar(content: Text(savedText)),
                       );
                     }
                  },
                ),
              ),
            if (_isHost)
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.qr_code, color: Colors.blue),
                  title: Text(l10n.pairingCode),
                  subtitle: Text(l10n.pairingCodeDescription),
                  onTap: () async {
                     final provider = Provider.of<LibraryProvider>(context, listen: false);
                     final pairingTitle = l10n.pairingCode;
                     final cancelText = l10n.cancel;
                     final ip = await provider.getLocalIp();
                     if (!context.mounted) return;
                     if (ip == null) return;

                     await showDialog<void>(
                       context: context,
                       builder: (dialogContext) => AlertDialog(
                         title: Text(pairingTitle),
                         content: Column(
                           mainAxisSize: MainAxisSize.min,
                           children: [
                             SizedBox(
                               width: 200,
                               height: 200,
                               child: QrImageView(
                                 data: 'LIB_SYNC:$ip',
                                 version: QrVersions.auto,
                                 size: 200.0,
                               ),
                             ),
                             const SizedBox(height: 16),
                             Text('IP: $ip', style: const TextStyle(fontWeight: FontWeight.bold)),
                           ],
                         ),
                         actions: [
                           TextButton(
                             onPressed: () => Navigator.pop(dialogContext),
                             child: Text(cancelText),
                           ),
                         ],
                       ),
                     );
                  },
                ),
              ),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              l10n.helpCenter,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.help_outline, color: Colors.blue),
                title: Text(l10n.helpCenter),
                subtitle: Text(l10n.documentation),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const HelpCenterScreen()),
                  );
                },
              ),
            ),
            Card(
              elevation: 2,
              child: ListTile(
                leading: const Icon(Icons.system_update, color: Colors.green),
                title: Text(l10n.checkForUpdates),
                onTap: () async {
                  final update = await UpdateService.checkForUpdate();
                  if (!context.mounted) return;
                  if (update != null) {
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: Text(l10n.updateAvailable),
                        content: Text('${l10n.updateAvailable}: ${update['version']}'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
                          TextButton(
                            onPressed: () => UpdateService.launchUpdate(update['url']),
                            child: Text(l10n.updateNow),
                          ),
                        ],
                      ),
                    );
                  } else {
                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.noUpdateAvailable)));
                  }
                },
              ),
            ),
            const SizedBox(height: 30),
            if (_isHost) ...[
              Text(
                l10n.dataProtection,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.orange),
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.backup, color: Colors.blue),
                  title: Text(l10n.backupDatabase),
                  subtitle: Text(l10n.backupDescription),
                  onTap: () async {
                    final provider = Provider.of<LibraryProvider>(context, listen: false);
                    final scaffold = ScaffoldMessenger.of(context);
                    try {
                      await provider.backupData();
                      scaffold.showSnackBar(SnackBar(
                          content: Text(l10n.backupSuccess)));
                    } catch (e) {
                      scaffold.showSnackBar(SnackBar(content: Text('Backup failed: $e')));
                    }
                  },
                ),
              ),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.restore, color: Colors.red),
                  title: Text(l10n.restoreDatabase),
                  subtitle: Text(l10n.restoreDescription),
                  onTap: () async {
                    final provider = Provider.of<LibraryProvider>(context, listen: false);
                    final scaffold = ScaffoldMessenger.of(context);
                    try {
                      FilePickerResult? result = await FilePicker.platform.pickFiles(
                        dialogTitle: 'Select Backup Database',
                        type: FileType.any,
                      );

                      if (result != null && result.files.single.path != null) {
                        final path = result.files.single.path!;
                        await provider.restoreData(path);
                        scaffold.showSnackBar(SnackBar(
                            content: Text(
                                l10n.restoreSuccess)));
                      }
                    } catch (e) {
                      scaffold.showSnackBar(SnackBar(content: Text('Restore failed: $e')));
                    }
                  },
                ),
              ),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.table_view, color: Colors.green),
                  title: Text(l10n.importExcel),
                  onTap: () async {
                    final provider = Provider.of<LibraryProvider>(context, listen: false);
                    final scaffold = ScaffoldMessenger.of(context);
                    try {
                      FilePickerResult? result = await FilePicker.platform.pickFiles(
                        type: FileType.custom,
                        allowedExtensions: ['xlsx'],
                      );

                      if (result != null && result.files.single.path != null) {
                        final path = result.files.single.path!;
                        await provider.importItemsFromExcel(path);
                        scaffold.showSnackBar(SnackBar(content: Text(l10n.importSuccess)));
                      }
                    } catch (e) {
                      scaffold.showSnackBar(SnackBar(content: Text('${l10n.importError}$e')));
                    }
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (_isHost) ...[
              Text(
                l10n.variablesTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.orange),
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.category_outlined, color: Colors.orange),
                  title: Text(l10n.manageVariables),
                  subtitle: Text(l10n.manageVariablesDescription),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const CodeManagementScreen()),
                    );
                  },
                ),
              ),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.tune, color: Colors.orange),
                  title: Text(l10n.manageAttributes),
                  subtitle: Text(l10n.manageVariablesDescription),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const AttributeManagementScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (_isHost) ...[
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.history, color: Colors.blueGrey),
                  title: Text(l10n.historyTitle),
                  subtitle: Text(l10n.showActionsLog),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    final navigator = Navigator.of(context);
                    final passed = await _showPasswordPrompt(context, title: l10n.enterPassword);
                    if (passed && mounted) {
                      navigator.push(
                        MaterialPageRoute(builder: (context) => const HistoryScreen()),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (_isHost) ...[
              Text(
                l10n.security,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.orange),
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 2,
                child: ListTile(
                  leading: const Icon(Icons.lock_outline, color: Colors.orange),
                  title: Text(l10n.adminPassword),
                  subtitle: Text(provider.hasAdminPassword ? l10n.changePassword : l10n.setPassword),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const PasswordManagementScreen()),
                    );
                  },
                ),
              ),
              const SizedBox(height: 24),
            ],
            if (_isHost) ...[
              Text(
                l10n.dangerZone,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.red),
              ),
              const SizedBox(height: 10),
              Card(
                elevation: 2,
                color: Colors.red[50],
                child: ListTile(
                  leading: const Icon(Icons.delete_forever, color: Colors.red),
                  title: Text(l10n.eraseAllData),
                  subtitle: Text(l10n.eraseWarning, style: TextStyle(fontSize: 12, color: Colors.red[900])),
                  onTap: () => _handleEraseData(context),
                ),
              ),
              Card(
                elevation: 2,
                color: Colors.red[50],
                child: ListTile(
                  leading: const Icon(Icons.restart_alt, color: Colors.red),
                  title: Text(l10n.setupRoadmap),
                  subtitle: Text(l10n.resetOnboardingDesc, style: const TextStyle(fontSize: 12, color: Colors.red)),
                  onTap: () async {
                    final messenger = ScaffoldMessenger.of(context);
                    final resetText = l10n.resetRestartApp;
                    final passed = await _showPasswordPrompt(context, title: l10n.enterPassword);
                    if (!context.mounted || !passed) return;
                    await OnboardingService.resetSetup();
                    if (!context.mounted) return;
                    messenger.showSnackBar(
                      SnackBar(content: Text(resetText)),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _saveSettings,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: Text(l10n.save),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleEraseData(BuildContext context) async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    final passed = await _showPasswordPrompt(context, title: l10n.enterPassword);
    if (!context.mounted || !passed) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.eraseAllData),
        content: Text(l10n.eraseWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.eraseAllData, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (!context.mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      final successString = l10n.dataWiped;
      await provider.clearAllData();
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(successString)),
      );
    }
  }

  Future<bool> _showPasswordPrompt(BuildContext context, {required String title}) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          obscureText: true,
          decoration: InputDecoration(labelText: l10n.adminPassword),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () {
              final provider = Provider.of<LibraryProvider>(context, listen: false);
              final messenger = ScaffoldMessenger.of(context);
              if (provider.checkPassword(controller.text)) {
                Navigator.pop(context, true);
              } else {
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.wrongPassword)),
                );
              }
            },
            child: Text(l10n.validate),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}
