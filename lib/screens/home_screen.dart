import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show LogicalKeyboardKey;
import 'package:provider/provider.dart';
import 'package:data_table_2/data_table_2.dart';
import '../l10n/app_localizations.dart';
import '../ui/app_tokens.dart';
import '../providers/library_provider.dart';
import '../providers/appearance_controller.dart';
import '../services/feature_flags.dart';
import '../services/error_messages.dart';
import '../services/windows_firewall_service.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../widgets/app_states.dart';
import '../widgets/item_status_cell.dart';
import '../widgets/item_delete_dialog.dart';
import '../models/library_item.dart';
import '../models/item_copy.dart';
import '../models/fine.dart';
import 'item_form_screen.dart';
import 'settings_screen.dart';
import 'dashboard_screen.dart';
import 'item_details_screen.dart';
import 'member_detail_screen.dart';
import 'members_screen.dart';
import 'loan_screen.dart';
import 'users_roles_screen.dart';
import 'fines_screen.dart';
import 'reservations_screen.dart';
import 'reports_screen.dart';
import 'chat_screen.dart';
import 'system_health_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  // Phase B (frontend reconstruction): the rail can be expanded or collapsed to
  // icons-only (§12). The user's toggle is authoritative, but a narrow window
  // always forces a collapse (§38) so the work area is never starved.
  bool _railPinnedExtended = true;

  @override
  void initState() {
    super.initState();
    // One-time firewall prompt for first-time host-mode users on Windows.
    // Deferred to a post-frame callback so the dialog has a valid context.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptFirewall());
  }

  Future<void> _maybePromptFirewall() async {
    if (!mounted) return;
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    if (!await provider.shouldPromptFirewall()) return;
    if (!mounted) return;

    final shouldEnable = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(l10n.firewallPromptTitle),
        content: Text(l10n.firewallPromptBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.firewallPromptDeny),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.firewallPromptAllow),
          ),
        ],
      ),
    );

    await provider.markFirewallPromptShown();

    if (shouldEnable == true && mounted) {
      final messenger = ScaffoldMessenger.of(context);
      final ok = await WindowsFirewallService.ensureLanFirewallRules();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(ok ? l10n.lanAccessEnabled : l10n.lanAccessFailed),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);
    final appearance = context.read<AppearanceController>();
    final flags = context.watch<FeatureFlags>();
    final paletteEnabled = flags.isEnabled('commandPalette');

    // Phase 10.1c: the Users & Roles surface is offered only to a device whose
    // session can administer; Settings always stays last. Phase 10.2b adds the
    // same treatment for Fines (staff+).
    //
    // The rail is now ONE data-driven list: each item carries its icon and
    // screen together with its label, so a conditional destination can never
    // drift the selectedIndex out of sync with the pages (the old parallel
    // screens/labels/destinations triple was the hazard). Settings always
    // stays last; inventory stays at index 1 (the FAB depends on it).
    final showUsers = provider.canAdminister;
    final showFines = provider.canWrite;
    // Phase 19: LAN staff chat is a staff coordination surface (the `/chat`
    // route is staff-only), so it is offered only to a writable session AND
    // while its feature flag is on -- never a tab a viewer can open to an
    // empty panel they cannot use.
    final showChat = flags.isEnabled('lanChat') && provider.canWrite;
    // Core Workflow Recovery: the dashboard "Needs Attention" tiles jump to
    // the matching rail tab. The destination list is built below, so bind it
    // through a `late final` and resolve the index lazily at tap time -- the
    // closure runs long after `items` is initialized.
    late final List<_RailItem> items;
    int indexOfScreen(Type type) =>
        items.indexWhere((e) => e.screen.runtimeType == type);
    items = <_RailItem>[
      // FE2-10: a dashboard Quick Scan applies a search and then asks the
      // parent to switch to the inventory tab, where that search is visible.
      _RailItem(
        l10n.dashboard,
        Icons.dashboard_outlined,
        Icons.dashboard,
        DashboardScreen(
          onOpenInventory: () => setState(() => _selectedIndex = 1),
          onOpenLoans: () => setState(() {
            final i = indexOfScreen(LoanScreen);
            if (i >= 0) _selectedIndex = i;
          }),
          onOpenReservations: () => setState(() {
            final i = indexOfScreen(ReservationsScreen);
            if (i >= 0) _selectedIndex = i;
          }),
          onOpenFines: () => setState(() {
            final i = indexOfScreen(FinesScreen);
            if (i >= 0) _selectedIndex = i;
          }),
        ),
      ),
      _RailItem(
        l10n.inventory,
        Icons.inventory_2_outlined,
        Icons.inventory_2,
        const _InventoryView(),
      ),
      _RailItem(
        l10n.members,
        Icons.people_outline,
        Icons.people,
        const MembersScreen(),
      ),
      _RailItem(
        l10n.loans,
        Icons.assignment_ind_outlined,
        Icons.assignment_ind,
        const LoanScreen(),
      ),
      if (showFines)
        _RailItem(
          l10n.fines,
          Icons.receipt_long_outlined,
          Icons.receipt_long,
          const FinesScreen(),
        ),
      if (showFines)
        _RailItem(
          l10n.reservations,
          Icons.bookmark_border,
          Icons.bookmark,
          const ReservationsScreen(),
        ),
      if (showFines)
        _RailItem(
          l10n.reports,
          Icons.insert_chart_outlined,
          Icons.insert_chart,
          const ReportsScreen(),
        ),
      if (showChat)
        _RailItem(
          l10n.chat,
          Icons.chat_bubble_outline,
          Icons.chat_bubble,
          const ChatScreen(),
        ),
      if (showUsers)
        _RailItem(
          l10n.usersAndRoles,
          Icons.admin_panel_settings_outlined,
          Icons.admin_panel_settings,
          const UsersRolesScreen(),
        ),
      _RailItem(
        l10n.settings,
        Icons.settings_outlined,
        Icons.settings,
        const SettingsScreen(),
      ),
    ];
    // Clamp so a runtime role change that shrinks the list can never leave the
    // saved selection out of range.
    final int index = _selectedIndex.clamp(0, items.length - 1);

    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    final scaffold = Scaffold(
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Phase B: honor the user's expand toggle, but always collapse to
          // icons-only on a narrow window so the work area is never starved.
          final compact = constraints.maxWidth < AppSizing.compactWidth;
          final extended = _railPinnedExtended && !compact;
          return Row(
            children: [
              NavigationRail(
                selectedIndex: index,
                onDestinationSelected: (int i) {
                  setState(() {
                    _selectedIndex = i;
                  });
                },
                extended: extended,
                minExtendedWidth: AppSizing.railExpanded,
                // An extended rail always shows its labels; the rail asserts
                // labelType == none whenever extended. Collapsed mode labels
                // only the selected destination.
                labelType: extended ? null : NavigationRailLabelType.selected,
                groupAlignment: extended ? -1 : 0,
                leading: Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  // `NavigationRail` computes its width as
                  // `max(railCollapsed, leadingWidth, trailingWidth,
                  // destinationWidth)`. A hard-coded 236-wide leading was
                  // forcing the "collapsed" rail to stay 236 anyway (only
                  // labels disappeared) — the toggle looked broken. Size
                  // the leading to the current state so the collapse
                  // actually shrinks the rail.
                  child: SizedBox(
                    width: extended
                        ? AppSizing.railExpanded
                        : AppSizing.railCollapsed,
                    child: extended
                        ? Row(
                            children: [
                              const SizedBox(width: AppSpacing.sm),
                              CircleAvatar(
                                backgroundColor: scheme.primaryContainer,
                                foregroundColor: scheme.onPrimaryContainer,
                                radius: 18,
                                child: Icon(
                                  Icons.library_books,
                                  size: AppIcon.md,
                                ),
                              ),
                              const SizedBox(width: AppSpacing.md),
                              Flexible(
                                child: Text(
                                  appearance.brandName,
                                  overflow: TextOverflow.ellipsis,
                                  style: txt.titleMedium,
                                ),
                              ),
                              // M3 desktop convention: the collapse toggle
                              // lives at the TOP of the rail, right beside
                              // the brand. The old position in `trailing`
                              // rendered below every destination, which is
                              // why the button felt "misplaced".
                              IconButton(
                                key: const Key('railToggle'),
                                tooltip: l10n.navCollapse,
                                icon: const Icon(
                                  Icons.keyboard_double_arrow_left,
                                ),
                                onPressed: () =>
                                    setState(() => _railPinnedExtended = false),
                              ),
                            ],
                          )
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircleAvatar(
                                backgroundColor: scheme.primaryContainer,
                                foregroundColor: scheme.onPrimaryContainer,
                                radius: 18,
                                child: Icon(
                                  Icons.library_books,
                                  size: AppIcon.md,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              IconButton(
                                key: const Key('railToggle'),
                                tooltip: l10n.navExpand,
                                icon: const Icon(
                                  Icons.keyboard_double_arrow_right,
                                ),
                                onPressed: () =>
                                    setState(() => _railPinnedExtended = true),
                              ),
                            ],
                          ),
                  ),
                ),
                destinations: [
                  for (final item in items)
                    NavigationRailDestination(
                      icon: Icon(item.icon, size: AppIcon.lg),
                      selectedIcon: Icon(item.selectedIcon, size: AppIcon.lg),
                      label: Text(item.label),
                    ),
                ],
              ),
              const VerticalDivider(
                thickness: AppBorder.width,
                width: AppBorder.width + 1,
              ),
              Expanded(
                child: Column(
                  children: [
                    Container(
                      height: AppSizing.topBarHeight,
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.xxl,
                        vertical: AppSpacing.sm,
                      ),
                      color: scheme.surface,
                      child: Row(
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                items[index].label,
                                style: txt.headlineSmall,
                              ),
                              Row(
                                children: [
                                  Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      color: _linkDotColor(
                                        provider.connectionStatus,
                                      ),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  Text(
                                    provider.isHost
                                        ? l10n.hostMode
                                        : l10n.clientMode,
                                    style: txt.bodySmall?.copyWith(
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.xs),
                                  Text(
                                    '• ${_linkLabel(provider.connectionStatus, l10n)}',
                                    style: txt.bodySmall?.copyWith(
                                      color: _linkTextColor(
                                        provider.connectionStatus,
                                      ),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const Spacer(),
                          // Phase 15: a staff-only notification bell (overdue loans,
                          // holds ready, pending fines), gated by its flag. A viewer
                          // cannot read this operational data, so it is not shown a
                          // bell that would only ever be empty.
                          if (flags.isEnabled('notificationCenter') &&
                              provider.canWrite)
                            _NotificationsButton(
                              items: items,
                              onOpen: (i) => setState(() => _selectedIndex = i),
                            ),
                          if (paletteEnabled)
                            IconButton(
                              tooltip: l10n.commandPalette,
                              icon: const Icon(Icons.search),
                              onPressed: () => _openPalette(
                                context,
                                l10n,
                                provider,
                                appearance,
                                items,
                                flags,
                              ),
                            ),
                          PopupMenuButton<Locale>(
                            onSelected: (Locale locale) =>
                                provider.setLocale(locale),
                            icon: const Icon(Icons.translate),
                            itemBuilder: (context) => const [
                              PopupMenuItem(
                                value: Locale('en'),
                                child: Text('English'),
                              ),
                              PopupMenuItem(
                                value: Locale('fr'),
                                child: Text('Français'),
                              ),
                              PopupMenuItem(
                                value: Locale('ar'),
                                child: Text('العربية'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    if (!provider.canWrite && provider.hasSession)
                      Material(
                        color: scheme.surfaceContainer,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.lg,
                            vertical: AppSpacing.sm,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.visibility,
                                size: AppIcon.sm,
                                color: AppStatus.warning,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(
                                child: Text(
                                  l10n.readOnlyMode,
                                  style: txt.bodySmall?.copyWith(
                                    color: scheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    Expanded(child: items[index].screen),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: (index == 1 && provider.canWrite)
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const ItemFormScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.add),
              label: Text(l10n.addItem),
            )
          : null,
    );

    if (!paletteEnabled) return scaffold;
    // Phase 16: a global command palette, opened by Ctrl+K (and the header
    // search button). Only bound while the flag is on, so a disabled surface
    // adds no hidden key handling either.
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _openPalette(context, l10n, provider, appearance, items, flags),
      },
      child: scaffold,
    );
  }

  /// Assemble and show the palette. Every entry drives a REAL, currently-
  /// permitted action (rail navigation, a staff-only add, the shared theme +
  /// locale switches) -- the palette never offers a command the UI would then
  /// refuse, and navigation reuses the same `items` list so it can never route
  /// to a role-hidden destination.
  void _openPalette(
    BuildContext context,
    AppLocalizations l10n,
    LibraryProvider provider,
    AppearanceController appearance,
    List<_RailItem> items,
    FeatureFlags flags,
  ) {
    final entries = <PaletteEntry>[
      for (final (i, item) in items.indexed)
        PaletteEntry(
          label: item.label,
          icon: item.icon,
          keywords: 'go open navigate ${item.label}',
          onSelect: () => setState(() => _selectedIndex = i),
        ),
      if (provider.canWrite)
        PaletteEntry(
          label: l10n.addItem,
          icon: Icons.add,
          keywords: 'new book create item',
          onSelect: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const ItemFormScreen()),
          ),
        ),
      if (provider.isHost &&
          provider.canAdminister &&
          flags.isEnabled('systemHealth'))
        PaletteEntry(
          label: l10n.systemHealthTitle,
          icon: Icons.monitor_heart_outlined,
          keywords: 'health diagnostics status server backup',
          onSelect: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const SystemHealthScreen()),
          ),
        ),
      PaletteEntry(
        label: '${l10n.themeLabel}: ${l10n.themeSystem}',
        icon: Icons.brightness_auto_outlined,
        keywords: 'theme appearance dark light system',
        onSelect: () => appearance.setThemeMode(ThemeMode.system),
      ),
      PaletteEntry(
        label: '${l10n.themeLabel}: ${l10n.themeLight}',
        icon: Icons.light_mode_outlined,
        keywords: 'theme appearance light',
        onSelect: () => appearance.setThemeMode(ThemeMode.light),
      ),
      PaletteEntry(
        label: '${l10n.themeLabel}: ${l10n.themeDark}',
        icon: Icons.dark_mode_outlined,
        keywords: 'theme appearance dark',
        onSelect: () => appearance.setThemeMode(ThemeMode.dark),
      ),
      PaletteEntry(
        label: '${l10n.language}: English',
        icon: Icons.translate,
        keywords: 'locale lang english en',
        onSelect: () => provider.setLocale(const Locale('en')),
      ),
      PaletteEntry(
        label: '${l10n.language}: Français',
        icon: Icons.translate,
        keywords: 'locale lang french fr',
        onSelect: () => provider.setLocale(const Locale('fr')),
      ),
      PaletteEntry(
        label: '${l10n.language}: العربية',
        icon: Icons.translate,
        keywords: 'locale lang arabic ar',
        onSelect: () => provider.setLocale(const Locale('ar')),
      ),
    ];

    showDialog<void>(
      context: context,
      builder: (_) => _CommandPaletteDialog(
        entries: entries,
        searchHint: l10n.paletteSearchHint,
        noMatches: l10n.paletteNoMatches,
        // Core Workflow Recovery: the palette becomes a real "find anything"
        // launcher. Data search runs read-only (`provider.itemMatches` does
        // not touch the visible inventory query), so closing the palette
        // with Escape leaves no side effects behind.
        dataSearch: (q) async {
          final out = <PaletteEntry>[];
          final items = await provider.itemMatches(q, limit: 6);
          for (final item in items) {
            out.add(
              PaletteEntry(
                label: item.designation,
                icon: Icons.auto_stories_outlined,
                keywords: '${item.code} ${item.designation}',
                section: l10n.inventory,
                onSelect: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => ItemDetailsScreen(itemCode: item.code),
                  ),
                ),
              ),
            );
          }
          final needle = q.toLowerCase();
          final members = provider.members
              .where(
                (m) =>
                    m.fullName.toLowerCase().contains(needle) ||
                    m.memberId.toLowerCase().contains(needle),
              )
              .take(6)
              .toList();
          for (final m in members) {
            out.add(
              PaletteEntry(
                label: m.fullName,
                icon: Icons.person_outline,
                keywords: m.memberId,
                section: l10n.members,
                onSelect: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MemberDetailScreen(memberId: m.memberId),
                  ),
                ),
              ),
            );
          }
          return out;
        },
      ),
    );
  }

  /// NET-07: the header link indicator is now tri-state (green / amber /
  // red) instead of a binary green/red, so a client in the reconnect grace
  // window warns in amber rather than holding a false 'Connected'.
  Color _linkDotColor(LanConnectionStatus s) => switch (s) {
    LanConnectionStatus.connected => AppStatus.success,
    LanConnectionStatus.reconnecting => AppStatus.warning,
    LanConnectionStatus.disconnected => AppStatus.danger,
  };
  Color _linkTextColor(LanConnectionStatus s) => switch (s) {
    LanConnectionStatus.connected => AppStatus.success,
    LanConnectionStatus.reconnecting => AppStatus.warning,
    LanConnectionStatus.disconnected => AppStatus.danger,
  };
  String _linkLabel(LanConnectionStatus s, AppLocalizations l10n) =>
      switch (s) {
        LanConnectionStatus.connected => l10n.connected,
        LanConnectionStatus.reconnecting => l10n.reconnecting,
        LanConnectionStatus.disconnected => l10n.disconnected,
      };

  static String getLocalizedStatus(String status, AppLocalizations l10n) {
    switch (status) {
      case ItemStatus.disponible:
        return l10n.statusDisponible;
      case ItemStatus.emprunte:
        return l10n.statusEmprunte;
      case ItemStatus.reserve:
        return l10n.statusReserve;
      case ItemStatus.endommage:
        return l10n.statusEndommage;
      default:
        return status;
    }
  }
}

/// BL-05: the status FILTER offers exactly the canonical copy-derived
/// vocabulary (`CopyState.titleStatusVocabulary`) -- the values a title's
/// rollup can actually produce. The previous union with the raw DB STATUS
/// attributes let an arbitrary/legacy string (e.g. 'Payé', a stale 'Endommagé')
/// become a selectable filter that no derived status could ever match, so
/// filtering by it silently returned nothing. Narrowing keeps filters honest.
List<String> statusFilterOptions() => CopyState.titleStatusVocabulary;

/// One navigation-rail entry: its labels, icons, and page live together so a
/// role-conditional destination (Fines, Users & Roles) can never desync the
/// rail index from the rendered screen.
class _RailItem {
  const _RailItem(this.label, this.icon, this.selectedIcon, this.screen);

  final String label;
  final IconData icon;
  final IconData selectedIcon;
  final Widget screen;
}

class _InventoryView extends StatefulWidget {
  const _InventoryView();

  @override
  State<_InventoryView> createState() => _InventoryViewState();
}

/// Maps a provider sort key to the DataTable2 column index that displays it.
/// Kept as a top-level helper so the arrow indicator lives in one place and
/// future column additions only need to update it. Returns 0 (`code`) when no
/// sort is set -- the DB default already orders by `code_type, code`, so the
/// arrow lands on a truthful column.
int _sortIndexFromKey(String? key, {required bool isHost}) {
  switch (key) {
    case 'designation':
      return 1;
    case 'quantity':
      return 2;
    case 'status':
      // The status column shifts by one on a host because the price column
      // sits between location and stock (see the columns list below).
      return isHost ? 6 : 5;
    case 'code':
    case null:
    default:
      return 0;
  }
}

class _InventoryViewState extends State<_InventoryView> {
  // FE2-10: the search box is now CONTROLLED so it mirrors the provider's
  // active query. When a scan is started from the dashboard and we switch here,
  // the field shows the scanned code instead of an empty box over filtered rows.
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    // One heading style for the whole table (was 8 copies of a bold literal).
    final headingStyle = txt.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: scheme.onSurface,
    );

    // Keep the box in sync with the provider whenever the query is changed
    // outside this field (dashboard scan, clearFilters). While the operator
    // types, onChanged pushes the value into the provider synchronously, so
    // the two already match and this is a no-op (no cursor jump).
    if (_searchController.text != provider.searchQuery) {
      _searchController.value = TextEditingValue(
        text: provider.searchQuery,
        selection: TextSelection.collapsed(offset: provider.searchQuery.length),
      );
    }

    if (provider.isLoading) {
      return const AppLoadingState();
    }

    return Padding(
      padding: AppSpacing.allLg,
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: l10n.search,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: () async {
                        final code = await showBarcodeScanner(context);
                        if (!context.mounted) return;
                        if (code != null) {
                          provider.search(code);
                        }
                      },
                      tooltip: l10n.scanBarcode,
                    ),
                  ),
                  onChanged: (value) => provider.search(value),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: AppRadius.field,
                    border: Border.all(
                      color: scheme.outlineVariant,
                      width: AppBorder.width,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: provider.codeTypeFilter,
                      hint: Text(l10n.typeLabel),
                      isExpanded: true,
                      icon: const Icon(Icons.category),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l10n.allTypes),
                        ),
                        ...provider.codeDefinitions.map(
                          (def) => DropdownMenuItem(
                            value: def.prefix,
                            child: Text(def.label),
                          ),
                        ),
                      ],
                      onChanged: (value) => provider.filterByCodeType(value),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.md,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerLow,
                    borderRadius: AppRadius.field,
                    border: Border.all(
                      color: scheme.outlineVariant,
                      width: AppBorder.width,
                    ),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: provider.statusFilter,
                      hint: Text(l10n.status),
                      isExpanded: true,
                      icon: const Icon(Icons.filter_list),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l10n.allStatuses),
                        ),
                        // BL-05: offer exactly the copy-derived canonical
                        // vocabulary (the values the rollup can produce), not
                        // the raw DB STATUS union.
                        ...statusFilterOptions().map(
                          (status) => DropdownMenuItem(
                            value: status,
                            child: Text(
                              _HomeScreenState.getLocalizedStatus(status, l10n),
                            ),
                          ),
                        ),
                      ],
                      onChanged: (value) => provider.filterByStatus(value),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.lg),
              IconButton(
                onPressed: provider.clearFilters,
                icon: const Icon(Icons.clear_all),
                tooltip: l10n.clearFilters,
              ),
              // Core Workflow Recovery: the export button moved from the
              // dashboard-only quick-actions into the working surface itself.
              // An operator filtering the inventory to a specific slice can
              // now export THAT view (the same provider.search/status/codeType
              // query) without leaving the table.
              if (provider.canWrite)
                IconButton(
                  onPressed: provider.isLoading
                      ? null
                      : () async {
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            final path = await provider.exportToCsv();
                            if (path != null) {
                              messenger.showSnackBar(
                                SnackBar(content: Text(l10n.exportSuccess)),
                              );
                            }
                          } catch (e) {
                            messenger.showSnackBar(
                              SnackBar(content: Text(describeError(l10n, e))),
                            );
                          }
                        },
                  icon: const Icon(Icons.download),
                  tooltip: l10n.exportCsv,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.lg),
          Expanded(
            child: Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Expanded(
                    child: DataTable2(
                      columnSpacing: AppSpacing.md,
                      horizontalMargin: AppSpacing.md,
                      minWidth: 1000,
                      headingRowHeight: AppSizing.topBarHeight - 16,
                      headingRowColor: WidgetStateProperty.all(
                        scheme.surfaceContainer,
                      ),
                      // Core Workflow Recovery: sort is applied by the server
                      // (see `DatabaseService.getItems`) so paginating keeps
                      // the ordering across pages. The visible arrow mirrors
                      // the provider's active sort; a null sort falls back to
                      // the code column (which is also the DB default).
                      // Each sortable [DataColumn2] carries its own onSort
                      // callback because DataTable2 does not expose a
                      // table-level onSort.
                      sortColumnIndex: _sortIndexFromKey(
                        provider.sortColumn,
                        isHost: provider.isHost,
                      ),
                      sortAscending: provider.sortAscending,
                      columns: [
                        DataColumn2(
                          label: Text(l10n.code, style: headingStyle),
                          size: ColumnSize.S,
                          onSort: (i, asc) =>
                              provider.setSort('code', ascending: asc),
                        ),
                        DataColumn2(
                          label: Text(l10n.designation, style: headingStyle),
                          size: ColumnSize.L,
                          onSort: (i, asc) =>
                              provider.setSort('designation', ascending: asc),
                        ),
                        DataColumn2(
                          label: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Text(l10n.quantity, style: headingStyle),
                          ),
                          size: ColumnSize.S,
                          numeric: true,
                          onSort: (i, asc) =>
                              provider.setSort('quantity', ascending: asc),
                        ),
                        DataColumn2(
                          label: Text(l10n.location, style: headingStyle),
                          size: ColumnSize.M,
                        ),
                        if (provider.isHost)
                          DataColumn2(
                            label: Align(
                              alignment: AlignmentDirectional.centerEnd,
                              child: Text(l10n.priceDzd, style: headingStyle),
                            ),
                            size: ColumnSize.S,
                          ),
                        DataColumn2(
                          label: Text(l10n.stockLocation, style: headingStyle),
                          size: ColumnSize.M,
                        ),
                        DataColumn2(
                          label: Text(l10n.status, style: headingStyle),
                          size: ColumnSize.S,
                          onSort: (i, asc) =>
                              provider.setSort('status', ascending: asc),
                        ),
                        if (provider.isHost)
                          DataColumn2(
                            label: Text(l10n.actions, style: headingStyle),
                            size: ColumnSize.S,
                          ),
                      ],
                      rows: provider.items.map((item) {
                        return DataRow2(
                          // Phase E: a row reads as a single interactive object
                          // -- hover/press tint from the surface scale, tap
                          // opens the item (the cells' edit/delete buttons stay
                          // as explicit secondary actions).
                          color: WidgetStateProperty.resolveWith((states) {
                            if (states.contains(WidgetState.hovered)) {
                              return scheme.surfaceContainerLow;
                            }
                            if (states.contains(WidgetState.pressed)) {
                              return scheme.surfaceContainer;
                            }
                            return Colors.transparent;
                          }),
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) =>
                                    ItemDetailsScreen(itemCode: item.code),
                              ),
                            );
                          },
                          cells: [
                            DataCell(Text(item.fullCode)),
                            DataCell(
                              ConstrainedBox(
                                constraints: const BoxConstraints(
                                  maxWidth: 420,
                                ),
                                child: Tooltip(
                                  message: item.designation,
                                  child: Text(
                                    item.designation,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ),
                            DataCell(_num(item.quantite.toString())),
                            DataCell(Text(item.emplacement)),
                            if (provider.isHost)
                              DataCell(_num(item.taux.toStringAsFixed(2))),
                            DataCell(Text(item.emplacementStock)),
                            DataCell(
                              ItemStatusCell(
                                status: item.status,
                                isHost: provider.isHost,
                              ),
                            ),
                            if (provider.isHost)
                              DataCell(
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit,
                                        color: scheme.primary,
                                      ),
                                      tooltip: l10n.editItem,
                                      onPressed: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                            builder: (context) =>
                                                ItemFormScreen(item: item),
                                          ),
                                        );
                                      },
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: scheme.error,
                                      ),
                                      tooltip: l10n.deleteItem,
                                      onPressed: () =>
                                          _confirmDelete(context, item),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        );
                      }).toList(),
                    ),
                  ),
                  if (provider.hasMoreInventory)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.sm,
                      ),
                      child: TextButton.icon(
                        onPressed: provider.isLoading
                            ? null
                            : () => provider.loadMoreItems(),
                        icon: provider.isLoading
                            ? const SizedBox(
                                width: AppIcon.sm,
                                height: AppIcon.sm,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.add),
                        label: Text(l10n.loadMore),
                      ),
                    ),
                  // Core Workflow Recovery: an honest "Showing X–Y of Z"
                  // footer so the operator can trust the visible page is a
                  // slice of a larger catalogue (previously they had to read
                  // the Load More button to infer that anything existed
                  // beyond the current page at all).
                  if (provider.inventoryTotal > 0)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        AppSpacing.sm,
                      ),
                      child: Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          l10n.paginationSummary(
                            1,
                            provider.items.length,
                            provider.inventoryTotal,
                          ),
                          style: txt.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (provider.items.isEmpty && !provider.isLoading)
            AppEmptyState(
              icon: Icons.inventory_2_outlined,
              title: l10n.noItemsFound,
              compact: true,
            ),
        ],
      ),
    );
  }

  /// One numeric table cell: right-aligned with tabular figures, so a column
  /// of amounts reads as a column (Phase E).
  Widget _num(String value) {
    final txt = Theme.of(context).textTheme;
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: Text(
        value,
        style: txt.bodyMedium?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  void _confirmDelete(BuildContext context, LibraryItem item) {
    // FE2-01/02 (P9-9.28): await the deletion and only close on success. The
    // provider rethrows on failure, so the dialog surfaces the error itself.
    showDialog(
      context: context,
      builder: (_) => ItemDeleteDialog(
        itemLabel: item.fullCode,
        onConfirm: () => Provider.of<LibraryProvider>(
          context,
          listen: false,
        ).deleteItem(item.code),
      ),
    );
  }
}

/// Phase 16: one command in the palette -- a label, icon, optional search
/// keywords, and the action it runs. Kept UI-free so the list is trivially
/// assembled from live state and unit-testable.
class PaletteEntry {
  const PaletteEntry({
    required this.label,
    required this.icon,
    required this.onSelect,
    this.keywords,
    this.section,
  });

  final String label;
  final IconData icon;
  final VoidCallback onSelect;
  final String? keywords;

  /// Core Workflow Recovery: optional group heading shown above the first
  /// entry that carries it. Used by the palette's data-search results
  /// ("Items", "Members") so an operator can tell a live record apart from
  /// a navigation command at a glance. Null (the default) means "no header".
  final String? section;

  bool matches(String query) {
    final q = query.toLowerCase();
    return label.toLowerCase().contains(q) ||
        (keywords?.toLowerCase().contains(q) ?? false);
  }
}

/// The palette overlay: a search field filters the live command list; Enter
/// runs the top result and a tap runs any row. Intentionally keeps focus in the
/// text field so typing filters immediately (the global Ctrl+K that opened it
/// is handled one level up in [HomeScreen]).
class _CommandPaletteDialog extends StatefulWidget {
  const _CommandPaletteDialog({
    required this.entries,
    required this.searchHint,
    required this.noMatches,
    this.dataSearch,
  });

  final List<PaletteEntry> entries;
  final String searchHint;
  final String noMatches;

  /// Core Workflow Recovery: async data lookup triggered after a 300ms
  /// debounce once the operator has typed at least 2 characters. Returning
  /// null (or throwing) simply means "no data results", so the palette still
  /// works for navigation commands. Data entries are appended below the
  /// filtered navigation list.
  final Future<List<PaletteEntry>> Function(String query)? dataSearch;

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final TextEditingController _controller = TextEditingController();
  List<PaletteEntry> _filtered = const [];
  List<PaletteEntry> _dataEntries = const [];
  Timer? _debounce;
  int _requestId = 0;

  @override
  void initState() {
    super.initState();
    _filtered = widget.entries;
    _controller.addListener(_recompute);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_recompute);
    _controller.dispose();
    super.dispose();
  }

  void _recompute() {
    final q = _controller.text.trim();
    setState(() {
      _filtered = q.isEmpty
          ? widget.entries
          : widget.entries.where((e) => e.matches(q)).toList();
    });
    // Core Workflow Recovery: only fire the data query once the operator has
    // committed to a search (>=2 chars). Below that every item/member table
    // would match, which is noise; and Escape never triggers a query.
    _debounce?.cancel();
    if (widget.dataSearch == null || q.length < 2) {
      if (_dataEntries.isNotEmpty) setState(() => _dataEntries = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _runData(q));
  }

  Future<void> _runData(String q) async {
    final id = ++_requestId;
    final search = widget.dataSearch;
    if (search == null) return;
    final results = await search(q);
    // A newer keystroke superseded this response -- drop it so a slow query
    // can't overwrite a fresher one.
    if (!mounted || id != _requestId) return;
    setState(() => _dataEntries = results);
  }

  void _choose(PaletteEntry e) {
    Navigator.of(context).pop();
    e.onSelect();
  }

  void _runTop() {
    final combined = _combined;
    if (combined.isNotEmpty) _choose(combined.first);
  }

  List<PaletteEntry> get _combined => [..._filtered, ..._dataEntries];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final combined = _combined;
    return AlertDialog(
      // Directional insets so the palette mirrors correctly in RTL (§40).
      contentPadding: const EdgeInsetsDirectional.only(
        start: AppSpacing.sm,
        end: AppSpacing.sm,
        top: AppSpacing.md,
      ),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: TextField(
                controller: _controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: widget.searchHint,
                  prefixIcon: const Icon(Icons.search),
                  border: InputBorder.none,
                ),
                onSubmitted: (_) => _runTop(),
              ),
            ),
            const Divider(height: 1),
            if (combined.isEmpty)
              Padding(
                padding: AppSpacing.allXxl,
                child: Text(
                  widget.noMatches,
                  textAlign: TextAlign.center,
                  style: txt.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  children: _buildRows(combined, txt, scheme),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Flatten the entry list into visual rows, inserting a small header label
  /// before the first entry of each distinct section. `selected: true` marks
  /// the very first data row (which is also the Enter-target on submit).
  List<Widget> _buildRows(
    List<PaletteEntry> combined,
    TextTheme txt,
    ColorScheme scheme,
  ) {
    final rows = <Widget>[];
    String? lastSection;
    var firstEntry = true;
    for (final entry in combined) {
      final sec = entry.section;
      if (sec != null && sec != lastSection) {
        rows.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              sec,
              style: txt.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        );
        lastSection = sec;
      }
      final isSelected = firstEntry;
      firstEntry = false;
      rows.add(
        ListTile(
          selected: isSelected,
          leading: Icon(entry.icon),
          title: Text(entry.label),
          onTap: () => _choose(entry),
        ),
      );
    }
    return rows;
  }
}

/// Phase 15: the header bell. A staff-only affordance (never shown to a
/// viewer, who can't read any of this operational data anyway), it opens the
/// notification dialog. On selecting a notification it closes and asks the
/// parent to switch to the matching rail destination.
///
/// Core Workflow Recovery: the bell now carries a live unread badge so an
/// operator sees "something needs you" without having to click into the
/// dialog. The badge recomputes whenever the provider publishes a data change
/// (debounced 500ms so a burst of mutations collapses into one query), and
/// goes away when the user acknowledges it by opening the dialog -- but a
/// subsequent real change re-arms it.
class _NotificationsButton extends StatefulWidget {
  const _NotificationsButton({required this.items, required this.onOpen});

  final List<_RailItem> items;
  final ValueChanged<int> onOpen;

  @override
  State<_NotificationsButton> createState() => _NotificationsButtonState();
}

class _NotificationsButtonState extends State<_NotificationsButton> {
  int _count = 0;
  // Signature of the last computed counts. Used to detect a REAL change so
  // the badge re-arms after the user acknowledged the previous one.
  int _lastSig = 0;
  bool _acknowledged = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    // Kick the first computation off the build frame so `context.read` is
    // legal inside the async body.
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Any provider notifyListeners rebuilds this subtree, which re-enters
    // didChangeDependencies -- a natural place to hook the data-load pulse.
    _schedule();
  }

  void _schedule() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _recompute);
  }

  Future<void> _recompute() async {
    if (!mounted) return;
    final provider = context.read<LibraryProvider>();
    var overdue = 0;
    var holds = 0;
    var fines = 0;
    try {
      overdue = provider.activeLoans.where((l) => l.isOverdue).length;
    } catch (_) {}
    try {
      holds = (await provider.readyForPickup()).length;
    } catch (_) {}
    try {
      fines = (await provider.getFines(status: FineStatus.pending)).length;
    } catch (_) {}
    if (!mounted) return;
    final sig = overdue * 1000000 + holds * 1000 + fines;
    final total = overdue + holds + fines;
    setState(() {
      _count = total;
      if (sig != _lastSig) {
        _lastSig = sig;
        _acknowledged = false;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final show = _count > 0 && !_acknowledged;
    return IconButton(
      tooltip: l10n.notifications,
      onPressed: () async {
        setState(() => _acknowledged = true);
        await showDialog<void>(
          context: context,
          builder: (_) =>
              _NotificationsDialog(items: widget.items, onOpen: widget.onOpen),
        );
      },
      icon: Badge(
        isLabelVisible: show,
        backgroundColor: scheme.error,
        textColor: scheme.onError,
        label: Text(_count > 99 ? '99+' : '$_count'),
        child: const Icon(Icons.notifications_none),
      ),
    );
  }
}

/// One computed notification: an icon, a human label, and the navigation to
/// run when tapped. Kept UI-free so the dialog just renders a list.
class _Notification {
  const _Notification({
    required this.icon,
    required this.label,
    required this.onOpen,
  });

  final IconData icon;
  final String label;
  final VoidCallback onOpen;
}

/// The notification-center dialog. Every count is read live from the same
/// provider the operational screens use -- overdue loans, holds ready for
/// pickup, pending fines. A source that fails to load is simply omitted (never
/// shown as a false zero), and the bell only ever surfaces counts > 0.
class _NotificationsDialog extends StatefulWidget {
  const _NotificationsDialog({required this.items, required this.onOpen});

  final List<_RailItem> items;
  final ValueChanged<int> onOpen;

  @override
  State<_NotificationsDialog> createState() => _NotificationsDialogState();
}

class _NotificationsDialogState extends State<_NotificationsDialog> {
  // null = still loading; a list (possibly empty) = loaded.
  List<_Notification>? _notifications;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reads inherited widgets (localizations + provider), so it must run after
    // initState -- do it once, here, where inherited lookups are legal.
    if (!_started) {
      _started = true;
      _load();
    }
  }

  Future<void> _load() async {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<LibraryProvider>();
    final results = <_Notification>[];

    try {
      final loans = await provider.fetchActiveLoans();
      final overdue = loans.where((l) => l.isOverdue).length;
      if (overdue > 0) {
        results.add(
          _Notification(
            icon: Icons.event_busy,
            label: l10n.notifOverdue(overdue),
            onOpen: () => widget.onOpen(
              widget.items.indexWhere((e) => e.screen is LoanScreen),
            ),
          ),
        );
      }
    } catch (_) {
      // Source unavailable (e.g. a transient read error): omit it rather than
      // report a misleading zero.
    }

    try {
      final ready = await provider.readyForPickup();
      if (ready.isNotEmpty) {
        results.add(
          _Notification(
            icon: Icons.bookmark_added,
            label: l10n.notifHoldsReady(ready.length),
            onOpen: () => widget.onOpen(
              widget.items.indexWhere((e) => e.screen is ReservationsScreen),
            ),
          ),
        );
      }
    } catch (_) {}

    try {
      final fines = await provider.getFines(status: FineStatus.pending);
      if (fines.isNotEmpty) {
        results.add(
          _Notification(
            icon: Icons.receipt_long,
            label: l10n.notifFinesPending(fines.length),
            onOpen: () => widget.onOpen(
              widget.items.indexWhere((e) => e.screen is FinesScreen),
            ),
          ),
        );
      }
    } catch (_) {}

    if (!mounted) return;
    setState(() => _notifications = results);
  }

  void _open(_Notification n) {
    Navigator.of(context).pop();
    n.onOpen();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return AlertDialog(
      title: Text(l10n.notifications),
      contentPadding: const EdgeInsetsDirectional.only(
        start: AppSpacing.sm,
        end: AppSpacing.sm,
        top: AppSpacing.md,
        bottom: AppSpacing.sm,
      ),
      content: SizedBox(
        width: 360,
        child: _notifications == null
            ? Padding(
                padding: AppSpacing.allXxl,
                child: Row(
                  children: [
                    const SizedBox(
                      width: AppIcon.sm,
                      height: AppIcon.sm,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Text(
                      l10n.notifLoading,
                      style: txt.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              )
            : _notifications!.isEmpty
            ? Padding(
                padding: AppSpacing.allXxl,
                child: Text(
                  l10n.notifNone,
                  textAlign: TextAlign.center,
                  style: txt.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            : ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 340),
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _notifications!.length,
                  itemBuilder: (context, i) {
                    final n = _notifications![i];
                    return ListTile(
                      leading: Icon(n.icon, color: scheme.primary),
                      title: Text(n.label),
                      onTap: () => _open(n),
                    );
                  },
                ),
              ),
      ),
    );
  }
}
