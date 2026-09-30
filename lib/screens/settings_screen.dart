import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io' show Platform;
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../providers/appearance_controller.dart';
import '../services/feature_flags.dart';
import '../models/user_account.dart';
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';
import 'users_roles_screen.dart' show roleLabel, roleDescription;
import 'code_management_screen.dart';
import 'attribute_management_screen.dart';
import 'history_screen.dart';
import 'password_management_screen.dart';
import 'help_center_screen.dart';
import 'system_health_screen.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/restore_confirm_dialog.dart';
import '../services/update_service.dart';
import '../services/onboarding_service.dart';
import '../services/windows_firewall_service.dart';
import 'package:qr_flutter/qr_flutter.dart';

/// Phase J (frontend reconstruction): the settings center redesigned per the
/// brief's §48 -- categories instead of one giant page, a search field that
/// filters across every visible setting, permission awareness (a category the
/// signed-in role cannot act in is not offered at all), an honest
/// unsaved-changes indicator with a revert next to Save, and descriptions on
/// the tiles. Every action, gate and confirmation below is the SAME one the
/// old page had (FE2-11 password verification, FE2-03 restore gate, Phase
/// 10.1c pairing roles, ARC-06/07 honesty); only the arrangement changed.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

/// One searchable block inside a category: its localized search terms (title
/// + subtitle copy) and the widget that actually performs the action.
class _SettingEntry {
  const _SettingEntry({required this.keywords, required this.builder});

  final List<String> keywords;
  final WidgetBuilder builder;

  bool matches(String query) =>
      keywords.any((k) => k.toLowerCase().contains(query));
}

/// A settings category shown in the left navigator. Only categories with at
/// least one visible entry are ever offered (permission awareness, §48).
class _SettingCategory {
  const _SettingCategory({
    required this.id,
    required this.title,
    required this.icon,
    required this.entries,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<_SettingEntry> entries;
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _ipController;
  late bool _isHost;
  bool _canEditSettings = false;
  bool _savingSettings = false;

  // §48: category selection + cross-category search.
  final TextEditingController _searchCtrl = TextEditingController();
  int _catIndex = 0;

  @override
  void initState() {
    super.initState();
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    _ipController = TextEditingController(text: provider.hostIp);
    // The unsaved-changes indicator must live-update while the draft is typed.
    _ipController.addListener(_onDraftChanged);
    _isHost = provider.isHost;
  }

  void _onDraftChanged() => setState(() {});

  @override
  void dispose() {
    _ipController.removeListener(_onDraftChanged);
    _ipController.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  /// True while the drafted mode/IP differ from the committed settings.
  bool _dirty(LibraryProvider provider) =>
      _isHost != provider.isHost ||
      _ipController.text.trim() != provider.hostIp;

  Future<void> _saveSettings() async {
    if (_savingSettings) return;
    setState(() => _savingSettings = true);

    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;

    try {
      await provider.updateSettings(
        _isHost,
        _ipController.text,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.savedSuccessfully)),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(describeError(l10n, e)),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _savingSettings = false);
      }
    }
  }

  // ---------------------------------------------------------------- categorize

  List<_SettingCategory> _categories(
    AppLocalizations l10n,
    LibraryProvider provider,
    FeatureFlags flags,
  ) {
    final cats = <_SettingCategory>[
      _SettingCategory(
        id: 'general',
        title: l10n.settingsCatGeneral,
        icon: Icons.settings_outlined,
        entries: [
          _SettingEntry(
            keywords: [
              l10n.connectionMode,
              l10n.unlockSettings,
              l10n.hostModeOption,
              l10n.clientModeOption,
              l10n.hostIpLabel,
              l10n.hostIpHelper,
            ],
            builder: (_) => _connectionBlock(l10n, provider),
          ),
          if (!provider.isHost)
            _SettingEntry(
              keywords: [l10n.scanServerCode, l10n.scanServerDescription],
              builder: (_) => _scanServerCard(l10n, provider),
            ),
          if (!provider.isHost)
            _SettingEntry(
              keywords: [
                l10n.enterPairingCode,
                l10n.enterPairingCodeDescription,
              ],
              builder: (_) => _pairingEntryCard(l10n, provider),
            ),
          if (!provider.isHost)
            _SettingEntry(
              keywords: [
                l10n.account,
                l10n.signedInAs(
                  provider.sessionUsername ?? '',
                  roleLabel(l10n, provider.sessionRole),
                ),
                l10n.readOnlyAccount,
                l10n.signIn,
                l10n.signOut,
              ],
              builder: (_) => _accountCard(l10n, provider),
            ),
          if (provider.isHost)
            _SettingEntry(
              keywords: [l10n.pairingCode, l10n.pairingCodeDescription],
              builder: (_) => _hostPairingCard(l10n, provider),
            ),
          if (provider.isHost)
            _SettingEntry(
              keywords: [l10n.connectedDevices],
              builder: (_) => _connectedDevicesCard(l10n, provider),
            ),
        ],
      ),
      if (flags.isEnabled('appearanceSettings'))
        _SettingCategory(
          id: 'appearance',
          title: l10n.appearance,
          icon: Icons.palette_outlined,
          entries: [
            _SettingEntry(
              keywords: [
                l10n.appearanceHint,
                l10n.themeLabel,
                l10n.themeSystem,
                l10n.themeLight,
                l10n.themeDark,
                l10n.accentColor,
                l10n.brandName,
                l10n.brandNameHint,
              ],
              builder: (_) => const _AppearanceSection(),
            ),
          ],
        ),
      if (provider.isHost)
        _SettingCategory(
          id: 'library',
          title: l10n.settingsCatLibrary,
          icon: Icons.category_outlined,
          entries: [
            _SettingEntry(
              keywords: [
                l10n.variablesTitle,
                l10n.manageVariables,
                l10n.manageVariablesDescription,
                l10n.manageAttributes,
              ],
              builder: (_) => _variablesBlock(l10n),
            ),
          ],
        ),
      if (provider.isHost)
        _SettingCategory(
          id: 'data',
          title: l10n.settingsCatData,
          icon: Icons.storage_outlined,
          entries: [
            _SettingEntry(
              keywords: [
                l10n.dataProtection,
                l10n.enableLanAccess,
                l10n.enableLanAccessDescription,
                l10n.backupDatabase,
                l10n.backupDescription,
                l10n.restoreDatabase,
                l10n.restoreDescription,
                l10n.importExcel,
              ],
              builder: (_) => _dataProtectionBlock(l10n, provider),
            ),
            _SettingEntry(
              keywords: [l10n.historyTitle, l10n.showActionsLog],
              builder: (_) => _historyCard(l10n),
            ),
          ],
        ),
      if (provider.isHost)
        _SettingCategory(
          id: 'security',
          title: l10n.settingsCatSecurity,
          icon: Icons.shield_outlined,
          entries: [
            _SettingEntry(
              keywords: [
                l10n.adminPassword,
                l10n.changePassword,
                l10n.setPassword,
              ],
              builder: (_) => _adminPasswordCard(l10n, provider),
            ),
            _SettingEntry(
              keywords: [
                l10n.dangerZone,
                l10n.eraseAllData,
                l10n.eraseWarning,
                l10n.setupRoadmap,
                l10n.resetOnboardingDesc,
              ],
              builder: (_) => _dangerZoneBlock(l10n),
            ),
          ],
        ),
      _SettingCategory(
        id: 'advanced',
        title: l10n.settingsCatAdvanced,
        icon: Icons.construction_outlined,
        entries: [
          if (flags.isEnabled('systemHealth') &&
              provider.isHost &&
              provider.canAdminister)
            _SettingEntry(
              keywords: [l10n.systemHealthTitle],
              builder: (_) => _systemHealthCard(l10n),
            ),
          if (provider.canAdminister)
            _SettingEntry(
              keywords: [l10n.featuresTitle, l10n.featureFlagsHint],
              builder: (_) => const _FeaturesSection(),
            ),
          _SettingEntry(
            keywords: [l10n.helpCenter, l10n.documentation],
            builder: (_) => _helpCard(l10n),
          ),
          _SettingEntry(
            keywords: [l10n.checkForUpdates],
            builder: (_) => _updatesCard(l10n),
          ),
          if (provider.canAdminister)
            _SettingEntry(
              keywords: [l10n.exportDiagnostics],
              builder: (_) => _diagnosticsCard(l10n, provider),
            ),
        ],
      ),
    ];
    // Permission awareness: never offer a category with nothing in it.
    return cats.where((c) => c.entries.isNotEmpty).toList();
  }

  // ------------------------------------------------------------------- shell

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);
    final flags = context.watch<FeatureFlags>();
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    final cats = _categories(l10n, provider, flags);
    // A runtime role/flag change can shrink the list; clamp the selection.
    final sel = _catIndex.clamp(0, cats.length - 1);
    final query = _searchCtrl.text.trim().toLowerCase();

    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Left navigator: search + category list (§48).
          SizedBox(
            width: 240,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  child: TextField(
                    key: const Key('settingsSearch'),
                    controller: _searchCtrl,
                    style: txt.bodyMedium,
                    decoration: InputDecoration(
                      hintText: l10n.settingsSearchHint,
                      prefixIcon: const Icon(Icons.search, size: AppIcon.md),
                      suffixIcon: query.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: AppIcon.md),
                              tooltip: l10n.cancel,
                              onPressed: () =>
                                  setState(_searchCtrl.clear),
                            )
                          : null,
                      isDense: true,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.sm,
                    ),
                    children: [
                      for (var i = 0; i < cats.length; i++)
                        ListTile(
                          key: Key('settingsCat_${cats[i].id}'),
                          selected: query.isEmpty && i == sel,
                          selectedTileColor: scheme.secondaryContainer
                              .withValues(alpha: 0.5),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.tile,
                          ),
                          leading: Icon(cats[i].icon, size: AppIcon.md),
                          title: Text(cats[i].title, style: txt.bodyLarge),
                          onTap: () => setState(() {
                            _catIndex = i;
                            _searchCtrl.clear();
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          // Right pane: the selected category (or the search results).
          Expanded(
            child: query.isNotEmpty
                ? _searchPane(l10n, cats, query)
                : _categoryPane(l10n, provider, cats[sel]),
          ),
        ],
      ),
    );
  }

  Widget _paneScroll({required List<Widget> children}) {
    // One vertical rhythm between blocks, token-pinned here once.
    final spaced = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) spaced.add(const SizedBox(height: AppSpacing.xl));
      spaced.add(children[i]);
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizing.maxFormWidth),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: spaced,
          ),
        ),
      ),
    );
  }

  Widget _categoryPane(
    AppLocalizations l10n,
    LibraryProvider provider,
    _SettingCategory cat,
  ) {
    final children = <Widget>[
      for (final e in cat.entries) e.builder(context),
      // Save belongs to the connection draft, so it lives in General only.
      if (cat.id == 'general') _saveBlock(l10n, provider),
    ];
    return _paneScroll(children: children);
  }

  Widget _searchPane(
    AppLocalizations l10n,
    List<_SettingCategory> cats,
    String query,
  ) {
    final blocks = <Widget>[];
    for (final c in cats) {
      final hits = c.entries.where((e) => e.matches(query)).toList();
      if (hits.isEmpty) continue;
      blocks.add(_SectionHeader(title: c.title, icon: c.icon));
      blocks.addAll(hits.map((e) => e.builder(context)));
      if (c.id == 'general' &&
          hits.any((e) => e.keywords.contains(l10n.connectionMode))) {
        blocks.add(_saveBlock(l10n, context.watch<LibraryProvider>()));
      }
    }
    if (blocks.isEmpty) {
      return AppEmptyState(
        icon: Icons.search_off,
        title: l10n.noItemsFound,
        message: l10n.settingsSearchHint,
        compact: true,
      );
    }
    return _paneScroll(children: blocks);
  }

  // ------------------------------------------------------------------ blocks

  Widget _sectionTitle(BuildContext context, String title, {Color? color}) {
    final txt = Theme.of(context).textTheme;
    return Text(
      title,
      style: txt.titleMedium?.copyWith(
        color: color ?? Theme.of(context).colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    );
  }

  Widget _connectionBlock(AppLocalizations l10n, LibraryProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, l10n.connectionMode),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: CheckboxListTile(
            title: Text(l10n.unlockSettings),
            controlAffinity: ListTileControlAffinity.leading,
            value: _canEditSettings,
            onChanged: (val) async {
              if (val == true) {
                final passed = await _showPasswordPrompt(
                    context, title: l10n.enterPassword);
                if (passed) {
                  setState(() => _canEditSettings = true);
                }
              } else {
                setState(() => _canEditSettings = false);
              }
            },
          ),
        ),
        Card(
          child: Column(
            children: [
              RadioListTile<bool>(
                title: Text(l10n.hostModeOption),
                value: true,
                // ignore: deprecated_member_use
                groupValue: _isHost,
                // ignore: deprecated_member_use
                onChanged: _canEditSettings
                    ? (value) => setState(() => _isHost = value!)
                    : null,
              ),
              RadioListTile<bool>(
                title: Text(l10n.clientModeOption),
                value: false,
                // ignore: deprecated_member_use
                groupValue: _isHost,
                // ignore: deprecated_member_use
                onChanged: _canEditSettings
                    ? (value) => setState(() => _isHost = value!)
                    : null,
              ),
            ],
          ),
        ),
        TextField(
          controller: _ipController,
          decoration: InputDecoration(
            labelText: l10n.hostIpLabel,
            helperText: l10n.hostIpHelper,
          ),
          enabled: _canEditSettings && !_isHost, // Only needed for client
        ),
      ],
    );
  }

  Widget _saveBlock(AppLocalizations l10n, LibraryProvider provider) {
    final txt = Theme.of(context).textTheme;
    final dirty = _dirty(provider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (dirty) ...[
          Row(
            children: [
              Icon(Icons.circle, size: AppIcon.sm, color: AppStatus.warning),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  l10n.settingsUnsaved,
                  style: txt.bodyMedium?.copyWith(
                    color: AppStatus.warning,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              TextButton(
                onPressed: _savingSettings
                    ? null
                    : () => setState(() {
                          // Revert the draft to the committed settings.
                          _isHost = provider.isHost;
                          _ipController.text = provider.hostIp;
                        }),
                child: Text(l10n.settingsRevert),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
        FilledButton.icon(
          onPressed: _savingSettings ? null : _saveSettings,
          icon: _savingSettings
              ? const SizedBox(
                  width: AppIcon.sm,
                  height: AppIcon.sm,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined, size: AppIcon.md),
          label: Text(l10n.save),
        ),
      ],
    );
  }

  Widget _scanServerCard(AppLocalizations l10n, LibraryProvider provider) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.qr_code_scanner, size: AppIcon.lg),
        title: Text(l10n.scanServerCode),
        subtitle: Text(l10n.scanServerDescription),
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final savedText = l10n.savedSuccessfully;
          final p = Provider.of<LibraryProvider>(context, listen: false);
          final code = await showBarcodeScanner(context);
          if (!mounted) return;
          if (code != null && code.startsWith('LIB_SYNC:')) {
            final ip = code.split(':').last;
            setState(() {
              _ipController.text = ip;
            });
            await p.updateSettings(false, ip);
            if (!mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(savedText)),
            );
          }
        },
      ),
    );
  }

  Widget _pairingEntryCard(AppLocalizations l10n, LibraryProvider provider) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.password, size: AppIcon.lg),
        title: Text(l10n.enterPairingCode),
        subtitle: Text(l10n.enterPairingCodeDescription),
        onTap: () async {
          final p = Provider.of<LibraryProvider>(context, listen: false);
          final messenger = ScaffoldMessenger.of(context);

          final entered = await showDialog<String>(
            context: context,
            builder: (dialogContext) {
              final controller = TextEditingController();
              return AlertDialog(
                title: Text(l10n.enterPairingCode),
                content: TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: l10n.pairingCode,
                    hintText: '123456',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    child: Text(l10n.cancel),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, controller.text),
                    child: Text(l10n.validate),
                  ),
                ],
              );
            },
          );

          if (!context.mounted) return;
          final pairingCode = (entered ?? '').trim();
          if (pairingCode.isEmpty) return;

          messenger.showSnackBar(
            SnackBar(content: Text(l10n.pairingSearching)),
          );

          final ip = await p.discoverHostIpByPairingCode(pairingCode);
          if (!context.mounted) return;
          if (ip != null) {
            setState(() {
              _ipController.text = ip;
            });
            await p.updateSettings(false, ip);
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.pairingIpSet)),
            );
          } else {
            messenger.showSnackBar(
              SnackBar(content: Text(l10n.pairingHostNotFound)),
            );
          }
        },
      ),
    );
  }

  Widget _accountCard(AppLocalizations l10n, LibraryProvider provider) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(
          provider.hasSession
              ? Icons.account_circle
              : Icons.account_circle_outlined,
          size: AppIcon.lg,
          color: provider.hasSession ? scheme.primary : scheme.onSurfaceVariant,
        ),
        title: Text(l10n.account),
        subtitle: Text(
          provider.hasSession
              ? l10n.signedInAs(
                  provider.sessionUsername ?? '',
                  roleLabel(l10n, provider.sessionRole),
                )
              : l10n.readOnlyAccount,
        ),
        trailing: provider.hasSession
            ? TextButton(
                onPressed: () => provider.signOut(),
                child: Text(l10n.signOut),
              )
            : TextButton(
                onPressed: () => _showSignInDialog(context, provider, l10n),
                child: Text(l10n.signIn),
              ),
        onTap: provider.hasSession
            ? null
            : () => _showSignInDialog(context, provider, l10n),
      ),
    );
  }

  Widget _hostPairingCard(AppLocalizations l10n, LibraryProvider provider) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.qr_code, size: AppIcon.lg),
        title: Text(l10n.pairingCode),
        subtitle: Text(l10n.pairingCodeDescription),
        onTap: () async {
          final p = Provider.of<LibraryProvider>(context, listen: false);
          final pairingTitle = l10n.pairingCode;
          final cancelText = l10n.cancel;

          final messenger = ScaffoldMessenger.of(context);

          // Phase 10.1c: pick the role the paired device will be granted
          // BEFORE minting the single-use code, so pairing can no longer hand
          // out the old unattributed-admin token.
          final role = await showDialog<UserRole>(
            context: context,
            builder: (_) => const _PairingRoleDialog(),
          );
          if (role == null || !context.mounted) return;

          String code;
          try {
            code = await p.startPairingCode(role: role);
          } catch (e) {
            if (!context.mounted) return;
            messenger.showSnackBar(
                SnackBar(content: Text(describeError(l10n, e))));
            return;
          }
          final ip = await p.getLocalIp();
          if (!mounted) return;
          if (ip == null) return;

          final expiresAt = p.pairingCodeExpiresAt;
          final minutesLeft = expiresAt?.difference(DateTime.now()).inMinutes;

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
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    code,
                    style: Theme.of(dialogContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text('IP: $ip',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  if (minutesLeft != null) ...[
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      l10n.pairingValidMinutes(minutesLeft <= 0 ? 0 : minutesLeft),
                      style: Theme.of(dialogContext)
                          .textTheme
                          .bodySmall
                          ?.copyWith(
                            color: Theme.of(dialogContext)
                                .colorScheme
                                .onSurfaceVariant,
                          ),
                    ),
                  ],
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
    );
  }

  Widget _connectedDevicesCard(
      AppLocalizations l10n, LibraryProvider provider) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.devices, size: AppIcon.lg),
        title: Text(l10n.connectedDevices),
        subtitle: Text('${provider.activeClients.length}'),
      ),
    );
  }

  Widget _systemHealthCard(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        leading: Icon(
          Icons.monitor_heart_outlined,
          size: AppIcon.lg,
          color: scheme.primary,
        ),
        title: Text(l10n.systemHealthTitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const SystemHealthScreen()),
          );
        },
      ),
    );
  }

  Widget _helpCard(AppLocalizations l10n) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.help_outline, size: AppIcon.lg),
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
    );
  }

  Widget _updatesCard(AppLocalizations l10n) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.system_update, size: AppIcon.lg),
        title: Text(l10n.checkForUpdates),
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final result = await UpdateService.checkForUpdate();
          if (!mounted) return;
          switch (result.status) {
            case UpdateStatus.notConfigured:
              // ARC-06: never claim "you are up to date" when no feed
              // was ever contacted -- say so honestly.
              messenger.showSnackBar(
                  SnackBar(content: Text(l10n.updateNotConfigured)));
              break;
            case UpdateStatus.failed:
              messenger.showSnackBar(
                  SnackBar(content: Text(l10n.updateCheckFailed)));
              break;
            case UpdateStatus.upToDate:
              messenger.showSnackBar(
                  SnackBar(content: Text(l10n.noUpdateAvailable)));
              break;
            case UpdateStatus.available:
              showDialog(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: Text(l10n.updateAvailable),
                  content: Text(
                      l10n.updateFoundVersion(result.version ?? '')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(dialogContext),
                        child: Text(l10n.cancel)),
                    if (result.hasUpdate)
                      TextButton(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          UpdateService.launchUpdate(result.url!);
                        },
                        child: Text(l10n.updateNow),
                      ),
                  ],
                ),
              );
              break;
          }
        },
      ),
    );
  }

  Widget _diagnosticsCard(AppLocalizations l10n, LibraryProvider provider) {
    // ARC-06: admin-only diagnostics export (the bundle can reveal internal
    // paths + operation traces, so it is gated identically to the other
    // administer affordances; it never carries credentials).
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bug_report_outlined, size: AppIcon.lg),
        title: Text(l10n.exportDiagnostics),
        onTap: () async {
          final scaffold = ScaffoldMessenger.of(context);
          try {
            final path = await provider.exportDiagnostics();
            if (path != null && context.mounted) {
              scaffold.showSnackBar(
                  SnackBar(content: Text(l10n.diagnosticsSaved(path))));
            }
          } catch (e) {
            if (context.mounted) {
              scaffold.showSnackBar(
                  SnackBar(content: Text(l10n.diagnosticsFailed)));
            }
          }
        },
      ),
    );
  }

  Widget _dataProtectionBlock(
      AppLocalizations l10n, LibraryProvider provider) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, l10n.dataProtection),
        const SizedBox(height: AppSpacing.sm),
        if (!kIsWeb && Platform.isWindows)
          Card(
            child: ListTile(
              leading: const Icon(Icons.security, size: AppIcon.lg),
              title: Text(l10n.enableLanAccess),
              subtitle: Text(l10n.enableLanAccessDescription),
              onTap: () async {
                final messenger = ScaffoldMessenger.of(context);
                final ok =
                    await WindowsFirewallService.ensureLanFirewallRules();
                if (!context.mounted) return;
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                        ok ? l10n.lanAccessEnabled : l10n.lanAccessFailed),
                  ),
                );
              },
            ),
          ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.backup_outlined, size: AppIcon.lg),
            title: Text(l10n.backupDatabase),
            subtitle: Text(l10n.backupDescription),
            onTap: () async {
              final p =
                  Provider.of<LibraryProvider>(context, listen: false);
              final scaffold = ScaffoldMessenger.of(context);
              try {
                await p.backupData();
                scaffold.showSnackBar(
                    SnackBar(content: Text(l10n.backupSuccess)));
              } catch (e) {
                scaffold.showSnackBar(
                    SnackBar(content: Text('${l10n.backupFailed} $e')));
              }
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: Icon(Icons.restore_outlined,
                size: AppIcon.lg, color: scheme.error),
            title: Text(l10n.restoreDatabase),
            subtitle: Text(l10n.restoreDescription),
            onTap: () async {
              final p =
                  Provider.of<LibraryProvider>(context, listen: false);
              final scaffold = ScaffoldMessenger.of(context);
              final l10n = AppLocalizations.of(context)!;
              try {
                FilePickerResult? result =
                    await FilePicker.platform.pickFiles(
                  dialogTitle: l10n.selectBackupDatabase,
                  type: FileType.any,
                );

                if (result != null && result.files.single.path != null) {
                  final path = result.files.single.path!;
                  // FE2-03: a restore overwrites the ENTIRE live database,
                  // so it must never fire the instant a file is picked.
                  // Show a confirmation gate naming the file; the restore
                  // is awaited by the gate and only closes on success (a
                  // pre-restore safety snapshot is taken inside
                  // DatabaseService.restoreDatabase).
                  if (!mounted) return;
                  showDialog(
                    context: context,
                    builder: (_) => RestoreConfirmDialog(
                      filePath: path,
                      onConfirm: () async {
                        await p.restoreData(path);
                        scaffold.showSnackBar(
                            SnackBar(content: Text(l10n.restoreSuccess)));
                      },
                    ),
                  );
                }
              } catch (e) {
                scaffold.showSnackBar(
                    SnackBar(content: Text('${l10n.restoreFailed} $e')));
              }
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.table_view, size: AppIcon.lg),
            title: Text(l10n.importExcel),
            onTap: () async {
              final p =
                  Provider.of<LibraryProvider>(context, listen: false);
              final scaffold = ScaffoldMessenger.of(context);
              try {
                FilePickerResult? result = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['xlsx'],
                );

                if (result != null && result.files.single.path != null) {
                  final path = result.files.single.path!;
                  await p.importItemsFromExcel(path);
                  scaffold.showSnackBar(
                      SnackBar(content: Text(l10n.importSuccess)));
                }
              } catch (e) {
                scaffold.showSnackBar(
                    SnackBar(content: Text('${l10n.importError}$e')));
              }
            },
          ),
        ),
        // Core Workflow Recovery: export sits with backup/restore/import so
        // an operator looking for it in Settings finds it in the same group
        // they were already trained on. Uses the SAME provider.exportToCsv()
        // the dashboard + inventory toolbar trigger, so behaviour cannot
        // drift between surfaces.
        Card(
          child: ListTile(
            leading: const Icon(Icons.download_outlined, size: AppIcon.lg),
            title: Text(l10n.exportCsv),
            subtitle: Text(l10n.exportSuccess),
            onTap: () async {
              final p =
                  Provider.of<LibraryProvider>(context, listen: false);
              final scaffold = ScaffoldMessenger.of(context);
              try {
                final path = await p.exportToCsv();
                if (path != null) {
                  scaffold.showSnackBar(
                      SnackBar(content: Text(l10n.exportSuccess)));
                }
              } catch (e) {
                scaffold.showSnackBar(
                    SnackBar(content: Text('$e')));
              }
            },
          ),
        ),
      ],
    );
  }

  Widget _historyCard(AppLocalizations l10n) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.history, size: AppIcon.lg),
        title: Text(l10n.historyTitle),
        subtitle: Text(l10n.showActionsLog),
        trailing: const Icon(Icons.chevron_right),
        onTap: () async {
          final navigator = Navigator.of(context);
          final passed = await _showPasswordPrompt(
              context, title: l10n.enterPassword);
          if (passed && mounted) {
            navigator.push(
              MaterialPageRoute(builder: (context) => const HistoryScreen()),
            );
          }
        },
      ),
    );
  }

  Widget _variablesBlock(AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, l10n.variablesTitle),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: ListTile(
            leading: const Icon(Icons.category_outlined, size: AppIcon.lg),
            title: Text(l10n.manageVariables),
            subtitle: Text(l10n.manageVariablesDescription),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) => const CodeManagementScreen()),
              );
            },
          ),
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.tune, size: AppIcon.lg),
            title: Text(l10n.manageAttributes),
            subtitle: Text(l10n.manageVariablesDescription),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (context) =>
                        const AttributeManagementScreen()),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _adminPasswordCard(
      AppLocalizations l10n, LibraryProvider provider) {
    return Card(
      child: ListTile(
        leading: const Icon(Icons.lock_outline, size: AppIcon.lg),
        title: Text(l10n.adminPassword),
        subtitle: Text(
            provider.hasAdminPassword ? l10n.changePassword : l10n.setPassword),
        trailing: const Icon(Icons.chevron_right),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) => const PasswordManagementScreen()),
          );
        },
      ),
    );
  }

  Widget _dangerZoneBlock(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle(context, l10n.dangerZone, color: scheme.error),
        const SizedBox(height: AppSpacing.sm),
        Card(
          color: scheme.errorContainer.withValues(alpha: 0.35),
          child: ListTile(
            leading: Icon(Icons.delete_forever,
                size: AppIcon.lg, color: scheme.error),
            title: Text(l10n.eraseAllData),
            subtitle: Text(
              l10n.eraseWarning,
              style: txt.bodySmall?.copyWith(color: scheme.error),
            ),
            onTap: () => _handleEraseData(context),
          ),
        ),
        Card(
          color: scheme.errorContainer.withValues(alpha: 0.35),
          child: ListTile(
            leading:
                Icon(Icons.restart_alt, size: AppIcon.lg, color: scheme.error),
            title: Text(l10n.setupRoadmap),
            subtitle: Text(
              l10n.resetOnboardingDesc,
              style: txt.bodySmall?.copyWith(color: scheme.error),
            ),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              final resetText = l10n.resetRestartApp;
              final passed = await _showPasswordPrompt(
                  context, title: l10n.enterPassword);
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
    );
  }

  // ------------------------------------------------------------------ actions

  Future<void> _handleEraseData(BuildContext context) async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;

    final passed =
        await _showPasswordPrompt(context, title: l10n.enterPassword);
    if (!context.mounted || !passed) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.eraseAllData),
        content: Text(l10n.eraseWarning),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel)),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text(l10n.eraseAllData),
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

  Future<bool> _showPasswordPrompt(
      BuildContext context, {required String title}) async {
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
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel)),
          TextButton(
            onPressed: () async {
              final provider =
                  Provider.of<LibraryProvider>(context, listen: false);
              final messenger = ScaffoldMessenger.of(context);
              // FE2-11: verify against the server-side credential, not the
              // local empty-password check that anyone could pass.
              final ok = await provider.verifyAdminPassword(controller.text);
              if (!context.mounted) return;
              if (ok) {
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

  /// Client-mode sign-in as a NAMED account (Phase 10.1c). Success promotes
  /// this device to the account's real role (write affordances appear); any
  /// refusal — including a host lockout, which is deliberately
  /// indistinguishable from a wrong password so accounts cannot be enumerated
  /// — shows one generic message.
  Future<void> _showSignInDialog(
      BuildContext context, LibraryProvider provider, AppLocalizations l10n) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => _SignInDialog(provider: provider),
    );
    if (!context.mounted) return;
    if (ok == true) {
      messenger.showSnackBar(SnackBar(
        content: Text(l10n.signedInAs(
            provider.sessionUsername ?? '', roleLabel(l10n, provider.sessionRole))),
      ));
    } else {
      messenger.showSnackBar(
        SnackBar(
          content: Text(l10n.signInFailed),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

/// Category caption used inside the SEARCH results pane (the category title
/// with its icon), so a match always says where it lives.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: AppIcon.md, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.sm),
        Text(
          title,
          style: txt.titleMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Role chooser shown BEFORE a pairing code is minted (Phase 10.1c). The
/// selected role is baked into the named `device-<code>` account the host
/// creates on redemption, so a paired counter PC can be a viewer/staff instead
/// of the historical all-powerful anonymous admin.
class _PairingRoleDialog extends StatefulWidget {
  const _PairingRoleDialog();

  @override
  State<_PairingRoleDialog> createState() => _PairingRoleDialogState();
}

class _PairingRoleDialogState extends State<_PairingRoleDialog> {
  UserRole _role = UserRole.staff;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(l10n.pairAsRole),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final r in UserRole.values.reversed)
            ListTile(
              leading: Icon(
                _role == r
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: _role == r ? scheme.primary : null,
              ),
              title: Text(roleLabel(l10n, r)),
              subtitle: Text(
                roleDescription(l10n, r),
                style:
                    txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              onTap: () => setState(() => _role = r),
            ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _role),
          child: Text(l10n.validate),
        ),
      ],
    );
  }
}

class _SignInDialog extends StatefulWidget {
  const _SignInDialog({required this.provider});

  final LibraryProvider provider;

  @override
  State<_SignInDialog> createState() => _SignInDialogState();
}

class _SignInDialogState extends State<_SignInDialog> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _busy = false;
  bool _obscure = true;

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final u = _username.text.trim();
    final p = _password.text;
    if (u.isEmpty || p.isEmpty) return;
    setState(() => _busy = true);
    final session = await widget.provider.loginUser(username: u, password: p);
    if (!mounted) return;
    Navigator.pop(context, session != null);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.signIn),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _username,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.username),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _password,
            obscureText: _obscure,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              labelText: l10n.password,
              suffixIcon: IconButton(
                icon: Icon(
                    _obscure ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _obscure = !_obscure),
              ),
            ),
          ),
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
                  width: AppIcon.sm,
                  height: AppIcon.sm,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.signIn),
        ),
      ],
    );
  }
}

/// Phase 14/17: the per-device appearance console. Theme mode + accent seed are
/// offered to every signed-in user (they only change what that person sees),
/// while the brand name -- the white-label product title -- is an administrator
/// affordance because it changes the identity the whole deployment presents.
/// The section no longer repeats its own "Appearance" title: in the Phase J
/// layout the category navigator already names it.
class _AppearanceSection extends StatefulWidget {
  const _AppearanceSection();

  @override
  State<_AppearanceSection> createState() => _AppearanceSectionState();
}

class _AppearanceSectionState extends State<_AppearanceSection> {
  TextEditingController? _brand;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Seed the field once from the persisted brand so later controller-driven
    // rebuilds never clobber what the operator is typing.
    _brand ??= TextEditingController(
      text: Provider.of<AppearanceController>(context, listen: false).brandName,
    );
  }

  @override
  void dispose() {
    _brand?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final appearance = context.watch<AppearanceController>();
    final canAdmin = context.watch<LibraryProvider>().canAdminister;

    String themeLabel(ThemeMode m) => switch (m) {
          ThemeMode.system => l10n.themeSystem,
          ThemeMode.light => l10n.themeLight,
          ThemeMode.dark => l10n.themeDark,
        };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.appearanceHint,
          style: txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(l10n.themeLabel),
        const SizedBox(height: AppSpacing.sm),
        SegmentedButton<ThemeMode>(
          showSelectedIcon: false,
          selected: {appearance.themeMode},
          segments: [
            for (final m in const [
              ThemeMode.system,
              ThemeMode.light,
              ThemeMode.dark,
            ])
              ButtonSegment(
                value: m,
                label: Text(themeLabel(m)),
                icon: Icon(switch (m) {
                  ThemeMode.system => Icons.brightness_auto_outlined,
                  ThemeMode.light => Icons.light_mode_outlined,
                  ThemeMode.dark => Icons.dark_mode_outlined,
                }),
              ),
          ],
          onSelectionChanged: (s) => appearance.setThemeMode(s.first),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(l10n.accentColor),
        const SizedBox(height: AppSpacing.sm),
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.md,
          children: [
            for (final preset in AppearanceController.presetSeeds)
              _SeedSwatch(
                color: Color(preset.value),
                name: preset.name,
                selected: appearance.seedValue == preset.value,
                onTap: () => appearance.setSeedColor(preset.value),
              ),
          ],
        ),
        if (canAdmin) ...[
          const SizedBox(height: AppSpacing.lg),
          TextField(
            controller: _brand,
            textInputAction: TextInputAction.done,
            onSubmitted: (v) async {
              final messenger = ScaffoldMessenger.of(context);
              final msg = l10n.brandNameUpdated;
              await appearance.setBrandName(v);
              // Reflect the (possibly defaulted) stored value back into the box.
              if (!mounted) return;
              _brand!.text = appearance.brandName;
              messenger.showSnackBar(SnackBar(content: Text(msg)));
            },
            decoration: InputDecoration(
              labelText: l10n.brandName,
              helperText: l10n.brandNameHint,
            ),
          ),
        ],
      ],
    );
  }
}

/// A circular accent-color option in the appearance picker.
class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.color,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: name,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Colors.transparent,
              width: 2,
            ),
          ),
          child: selected
              ? const Icon(Icons.check, color: Colors.white, size: AppIcon.md)
              : null,
        ),
      ),
    );
  }
}

/// Phase 14: the admin-only feature-flag console. One switch per catalog flag;
/// toggling persists immediately and drives the same [FeatureFlags] the rest
/// of the UI consults.
class _FeaturesSection extends StatelessWidget {
  const _FeaturesSection();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final flags = context.watch<FeatureFlags>();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.featuresTitle,
          style: txt.titleMedium?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w600,
          ),
        ),
        Text(
          l10n.featureFlagsHint,
          style: txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.sm),
        Card(
          child: Column(
            children: [
              for (final flag in FeatureFlags.catalog)
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  title: Text(flag.label),
                  value: flags.isEnabled(flag.id),
                  onChanged: (v) => flags.setEnabled(flag.id, v),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
