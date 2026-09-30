import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/fine.dart';
import '../providers/library_provider.dart';
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';
import '../widgets/app_status_chip.dart';
import '../widgets/stat_card.dart';
import '../widgets/password_dialog.dart';
import '../widgets/barcode_scanner_dialog.dart';
import 'item_form_screen.dart';
import 'history_screen.dart';

/// Phase D (frontend reconstruction): the dashboard was re-layered, not
/// re-featured. Every action below is the SAME provider call the old screen
/// made (quick scan + search hand-off FE2-10, CSV export, password-gated
/// history, reload, live device list, honest load-error banner). What changed
/// is presentation only: the brown/orange brand slab, gradient stat tiles and
/// five per-button color overrides are gone -- the page now consumes the
/// centralized tokens, reads correctly in dark mode and RTL, and groups its
/// content into titled [AppSection]s so hierarchy comes from structure, not
/// from shouting colors (§5-8/§28/§40/§43/§55/§59).
class DashboardScreen extends StatelessWidget {
  const DashboardScreen({
    super.key,
    this.onOpenInventory,
    this.onOpenLoans,
    this.onOpenReservations,
    this.onOpenFines,
  });

  /// FE2-10: the Quick Scan used to call `provider.search(code)` and then do
  /// nothing -- the operator stayed on the dashboard and never saw the result
  /// (a no-op). The dashboard is a tab inside `HomeScreen`, so it cannot change
  /// the selected tab itself; the parent injects this callback to switch to the
  /// inventory view where the search the scan just applied is actually visible.
  final VoidCallback? onOpenInventory;

  /// Core Workflow Recovery: navigation callbacks for the "Needs Attention"
  /// operational section. Each jumps to the corresponding rail tab.
  final VoidCallback? onOpenLoans;
  final VoidCallback? onOpenReservations;
  final VoidCallback? onOpenFines;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    if (provider.isLoading) {
      return const AppLoadingState();
    }

    // One horizontal rhythm for every section boundary on the page.
    const sectionGap = SizedBox(height: AppSpacing.xxxl);

    return SingleChildScrollView(
      padding: AppSpacing.allXxl,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _HeaderRow(provider: provider, l10n: l10n),
          sectionGap,

          // Core Workflow Recovery: "What needs attention?" — live operational
          // alerts the librarian sees immediately on open.
          if (provider.canWrite)
            _NeedsAttention(
              onOpenLoans: onOpenLoans,
              onOpenReservations: onOpenReservations,
              onOpenFines: onOpenFines,
            ),
          sectionGap,

          // At-a-glance operational metrics.
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: constraints.maxWidth > 800
                    ? (provider.isHost ? 3 : 2)
                    : 1,
                crossAxisSpacing: AppSpacing.lg,
                mainAxisSpacing: AppSpacing.lg,
                childAspectRatio: constraints.maxWidth > 800 ? 2.2 : 3.0,
                children: [
                  StatCard(
                    title: l10n.totalDocuments,
                    value: provider.totalQuantity.toString(),
                    icon: Icons.auto_stories_outlined,
                    color: AppStatus.info,
                  ),
                  if (provider.isHost)
                    StatCard(
                      title: l10n.inventoryValue,
                      value:
                          '${provider.totalValue.toStringAsFixed(0)} ${l10n.priceDzd.split('(').last.replaceAll(')', '')}',
                      icon: Icons.account_balance_wallet_outlined,
                      color: AppStatus.success,
                    ),
                  StatCard(
                    title: l10n.onLoan,
                    value: provider.onLoanCount.toString(),
                    icon: Icons.assignment_return_outlined,
                    color: AppStatus.borrowed,
                  ),
                ],
              );
            },
          ),
          sectionGap,

          // Collection mix by code type.
          AppSection(
            title: l10n.typeLabel,
            padding: EdgeInsets.zero,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Wrap(
                  spacing: AppSpacing.huge,
                  runSpacing: AppSpacing.xxl,
                  children: [
                    for (final def in provider.codeDefinitions)
                      _TypeCount(
                        label: def.label,
                        count: provider
                            .getCountByCodeType(def.prefix)
                            .toString(),
                      ),
                  ],
                ),
              ),
            ),
          ),
          sectionGap,

          // Host-only quick actions. Every button keeps its exact prior
          // behaviour; only the chrome changed (theme buttons, no per-widget
          // backgroundColor lottery).
          if (provider.isHost) ...[
            AppSection(
              title: l10n.quickActions,
              padding: EdgeInsets.zero,
              child: Wrap(
                spacing: AppSpacing.lg,
                runSpacing: AppSpacing.md,
                children: [
                  FilledButton.icon(
                    onPressed: () async {
                      final code = await showBarcodeScanner(context);
                      if (code != null && context.mounted) {
                        // FE2-10: apply the scan as a search AND move to the
                        // inventory view, so the operator lands on the match
                        // instead of staring at an unchanged dashboard.
                        Provider.of<LibraryProvider>(context, listen: false)
                            .search(code);
                        onOpenInventory?.call();
                      }
                    },
                    icon: const Icon(Icons.qr_code_scanner, size: AppIcon.md),
                    label: Text(l10n.quickScan),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const ItemFormScreen(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: AppIcon.md),
                    label: Text(l10n.addNewBook),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => provider.reload(),
                    icon: const Icon(Icons.refresh, size: AppIcon.md),
                    label: Text(l10n.refreshData),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      try {
                        final path = await provider.exportToCsv();
                        // null => the user cancelled the save dialog; report no
                        // success (BL-09 / 11b).
                        if (path != null && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(l10n.exportSuccess)),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(describeError(l10n, e)),
                            ),
                          );
                        }
                      }
                    },
                    icon: const Icon(Icons.download, size: AppIcon.md),
                    label: Text(l10n.exportCsv),
                  ),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final passed = await showPasswordPrompt(
                        context,
                        title: l10n.enterPassword,
                      );
                      if (passed && context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HistoryScreen(),
                          ),
                        );
                      }
                    },
                    icon: const Icon(Icons.history, size: AppIcon.md),
                    label: Text(l10n.historyAction),
                  ),
                ],
              ),
            ),
            sectionGap,
          ],

          // Live LAN clients (host only) -- counts and rows come straight from
          // the provider, so the panel is never a mock.
          if (provider.isHost)
            AppSection(
              title: l10n.connectedDevices,
              padding: EdgeInsets.zero,
              trailing: Text(
                provider.activeClients.length.toString(),
                style: txt.titleMedium?.copyWith(color: scheme.primary),
              ),
              child: provider.activeClients.isEmpty
                  ? Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Text(
                          l10n.noConnectedDevices,
                          style: txt.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    )
                  : Card(
                      child: ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        padding: EdgeInsets.zero,
                        itemCount: provider.activeClients.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final clientIp = provider.activeClients[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scheme.surfaceContainerHighest,
                              foregroundColor: scheme.onSurfaceVariant,
                              child: const Icon(
                                Icons.phone_android,
                                size: AppIcon.md,
                              ),
                            ),
                            title: Text(clientIp),
                            subtitle: Text(l10n.connectedViaLan),
                            trailing: const Icon(
                              Icons.circle,
                              color: AppStatus.success,
                              size: AppIcon.sm - 4,
                            ),
                          );
                        },
                      ),
                    ),
            ),

          // A real load failure stays visible with the classified cause
          // (FE2-12), styled through the error container so it is honest in
          // both brightness modes.
          if (provider.errorMessage != null) ...[
            const SizedBox(height: AppSpacing.xxl),
            Container(
              padding: const EdgeInsets.all(AppSpacing.lg),
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                borderRadius: AppRadius.field,
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline, color: scheme.onErrorContainer),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Text(
                      describeError(l10n, provider.loadError ?? Exception()),
                      style: txt.bodyMedium?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Page identity + the session's operating mode. The mode chip is informational
/// (host/client), tinted with the semantic palette and always text-first.
class _HeaderRow extends StatelessWidget {
  const _HeaderRow({required this.provider, required this.l10n});

  final LibraryProvider provider;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final hostColor =
        provider.isHost ? AppStatus.success : AppStatus.info;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.nationalLibrary,
              style: txt.headlineSmall?.copyWith(color: scheme.onSurface),
            ),
            Text(
              l10n.algerianSystem,
              style: txt.bodyMedium?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        AppStatusChip(
          label: provider.isHost ? l10n.hostMode : l10n.clientMode,
          color: hostColor,
        ),
      ],
    );
  }
}

/// Core Workflow Recovery: "What needs attention?" panel.
/// Fetches overdue loans, holds ready, and pending fines from the provider
/// and renders tappable alert tiles only for non-zero counts. Hidden entirely
/// when everything is clear (no false zeros, no noise).
class _NeedsAttention extends StatefulWidget {
  const _NeedsAttention({
    this.onOpenLoans,
    this.onOpenReservations,
    this.onOpenFines,
  });

  final VoidCallback? onOpenLoans;
  final VoidCallback? onOpenReservations;
  final VoidCallback? onOpenFines;

  @override
  State<_NeedsAttention> createState() => _NeedsAttentionState();
}

class _NeedsAttentionState extends State<_NeedsAttention> {
  int _overdue = 0;
  int _holdsReady = 0;
  int _pendingFines = 0;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<LibraryProvider>();
    // Overdue: already in memory.
    final overdue = provider.activeLoans.where((l) => l.isOverdue).length;
    // Holds + fines require async reads.
    int holds = 0;
    int fines = 0;
    try {
      final ready = await provider.readyForPickup();
      holds = ready.length;
    } catch (_) {}
    try {
      final pending = await provider.getFines(status: FineStatus.pending);
      fines = pending.length;
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _overdue = overdue;
      _holdsReady = holds;
      _pendingFines = fines;
      _loaded = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (!_loaded) return const SizedBox.shrink();
    final alerts = <Widget>[];
    if (_overdue > 0) {
      alerts.add(_AlertTile(
        icon: Icons.event_busy,
        label: l10n.notifOverdue(_overdue),
        color: AppStatus.danger,
        onTap: widget.onOpenLoans,
      ));
    }
    if (_holdsReady > 0) {
      alerts.add(_AlertTile(
        icon: Icons.bookmark_added,
        label: l10n.notifHoldsReady(_holdsReady),
        color: AppStatus.success,
        onTap: widget.onOpenReservations,
      ));
    }
    if (_pendingFines > 0) {
      alerts.add(_AlertTile(
        icon: Icons.receipt_long,
        label: l10n.notifFinesPending(_pendingFines),
        color: AppStatus.warning,
        onTap: widget.onOpenFines,
      ));
    }
    if (alerts.isEmpty) return const SizedBox.shrink();
    return AppSection(
      title: l10n.needsAttention,
      icon: Icons.warning_amber_rounded,
      padding: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: alerts,
      ),
    );
  }
}

class _AlertTile extends StatelessWidget {
  const _AlertTile({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: AppSpacing.sm),
      color: color.withValues(alpha: 0.08),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: color.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: Icon(icon, color: color),
        title: Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: scheme.onSurface, fontWeight: FontWeight.w500)),
        trailing: Icon(Icons.chevron_right, color: scheme.onSurfaceVariant),
        onTap: onTap,
      ),
    );
  }
}

/// One "type: count" cell inside the collection-mix panel. Label muted, value
/// prominent -- hierarchy from the type scale, not from size inflation.
class _TypeCount extends StatelessWidget {
  const _TypeCount({required this.label, required this.count});

  final String label;
  final String count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          count,
          style: txt.headlineSmall?.copyWith(
            color: scheme.onSurface,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}
