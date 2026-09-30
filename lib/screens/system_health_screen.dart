import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../config/app_info.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../services/database_service.dart';
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';

/// Phase 15: a genuine system-health dashboard. Every row here is a value the
/// running app ACTUALLY knows (its version, the DB schema it is on, whether the
/// LAN socket is listening, who is connected, and when a backup last
/// succeeded) -- nothing is decorative or optimistic. It is exposed only to a
/// host administrator behind the `systemHealth` feature flag, because it
/// discloses operational internals.
///
/// Phase I (frontend reconstruction): presentation-only pass -- this is a
/// pushed route so its AppBar stays, but the health signals now read through
/// the shared [AppStatus] hues (a green row means the same thing here as in
/// inventory) and the spacing comes from the token scale.
class SystemHealthScreen extends StatelessWidget {
  const SystemHealthScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<LibraryProvider>();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.systemHealthTitle)),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          _HealthTile(
            icon: Icons.info_outline,
            label: l10n.healthAppVersion,
            value: kAppVersion,
          ),
          _HealthTile(
            icon: Icons.storage_outlined,
            label: l10n.healthDatabaseSchema,
            value: '${DatabaseService.currentSchemaVersion}',
          ),
          _HealthTile(
            icon: Icons.devices_other_outlined,
            label: l10n.healthOperatingMode,
            value: provider.isHost ? l10n.hostMode : l10n.clientMode,
          ),
          if (provider.isHost)
            _HealthTile(
              icon: Icons.hub_outlined,
              label: l10n.healthLanServer,
              value: provider.serverRunning
                  ? l10n.healthServerRunning
                  : l10n.healthServerStopped,
              // ARC-07: rendered in the session language from the recorded
              // failure KIND, not from the provider's raw diagnostic sentence.
              error: provider.serverErrorKind == null
                  ? null
                  : provider.serverError(l10n),
              positive: provider.serverRunning,
            ),
          _HealthTile(
            icon: Icons.link,
            label: l10n.healthConnection,
            value: _connectionLabel(provider.connectionStatus, l10n),
            positive: provider.connectionStatus ==
                LanConnectionStatus.connected,
          ),
          if (provider.isHost)
            _HealthTile(
              icon: Icons.people_outline,
              label: l10n.healthConnectedClients,
              value: l10n.healthClientCount(provider.activeClients.length),
            ),
          _BackupTile(),
          const SizedBox(height: AppSpacing.xxl),
          OutlinedButton.icon(
            icon: const Icon(Icons.bug_report_outlined),
            label: Text(l10n.exportDiagnostics),
            onPressed: () => _exportDiagnostics(context),
          ),
        ],
      ),
    );
  }

  String _connectionLabel(LanConnectionStatus s, AppLocalizations l10n) =>
      switch (s) {
        LanConnectionStatus.connected => l10n.connected,
        LanConnectionStatus.reconnecting => l10n.reconnecting,
        LanConnectionStatus.disconnected => l10n.disconnected,
      };

  Future<void> _exportDiagnostics(BuildContext context) async {
    final provider = context.read<LibraryProvider>();
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final path = await provider.exportDiagnostics();
      if (path != null) {
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.diagnosticsSaved(path))));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(describeError(l10n, e))));
    }
  }
}

class _HealthTile extends StatelessWidget {
  const _HealthTile({
    required this.icon,
    required this.label,
    required this.value,
    this.positive,
    this.error,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool? positive;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    // Health verdicts use the semantic palette, never raw Colors.*; a null
    // verdict is a plain informational row.
    final color = positive == null
        ? null
        : (positive! ? AppStatus.success : AppStatus.danger);
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(icon, size: AppIcon.lg, color: color),
        title: Text(label),
        subtitle: error != null
            ? Text(
                error!,
                style: txt.bodySmall?.copyWith(color: AppStatus.danger),
              )
            : null,
        trailing: Text(
          value,
          style: txt.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }
}

/// The backup-freshness row is computed against the current time, so it lives in
/// its own small widget that can format relative age and color a stale/never
/// backup honestly (a stale backup is amber, not a green all-clear).
class _BackupTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final last = context.watch<LibraryProvider>().lastBackupAt;

    String value;
    bool fresh;
    if (last == null) {
      value = l10n.healthNever;
      fresh = false;
    } else {
      final age = DateTime.now().difference(last);
      value = _humanAge(l10n, age);
      fresh = age.inDays < 3;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ListTile(
        leading: Icon(Icons.backup_outlined,
            size: AppIcon.lg,
            color: fresh ? AppStatus.success : AppStatus.warning),
        title: Text(l10n.healthLastBackup),
        subtitle: Text(fresh ? l10n.healthBackupFresh : l10n.healthBackupStale),
        trailing: Text(
          value,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  String _humanAge(AppLocalizations l10n, Duration a) {
    if (a.inMinutes < 1) return '0m';
    if (a.inHours < 1) return '${a.inMinutes}m';
    if (a.inDays < 1) return '${a.inHours}h';
    return '${a.inDays}d';
  }
}
