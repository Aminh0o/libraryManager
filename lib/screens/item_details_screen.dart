import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/library_item.dart';
import '../models/item_copy.dart';
import '../providers/library_provider.dart';
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';
import '../widgets/app_status_chip.dart';
import '../widgets/item_status_cell.dart';
import '../widgets/member_select_dialog.dart';
import '../widgets/record_history_section.dart';
import 'item_form_screen.dart';

/// Phase 13: non-condition actions available on a copy's overflow menu.
enum _CopyOp { barcode, remove }

/// Phase F (frontend reconstruction): presentation-only rebuild. The record
/// resolution stays exactly as FE2-14 required (a vanished record renders the
/// honest not-found state and NO phantom profile / edit affordance), the copy
/// ledger keeps every Phase 12/13 write path and permission gate, and the
/// pinned test keys survive (`itemMissingState`, the add-copy icon). What
/// changed: the orange avatar, grey[50] scaffold, hand-rolled chip clones and
/// red snackbars are replaced by the centralized tokens, [AppStatusChip] and
/// the shared state components, so this page now reads like the rest of the
/// app in light AND dark mode.
class ItemDetailsScreen extends StatelessWidget {
  final String itemCode;

  const ItemDetailsScreen({super.key, required this.itemCode});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    // FE2-14: resolve the record WITHOUT fabricating a placeholder. The item
    // may have vanished (deleted from another client, or a restore swapped the
    // DB) between the list load and opening this screen. The old `firstWhere`
    // `orElse` returned a fake 'Unknown' LibraryItem, so the operator saw a
    // plausible profile for a row that no longer exists -- and could even Edit a
    // phantom. A missing record now renders an explicit 'not found' state.
    final matches = provider.allItems.where((i) => i.code == itemCode);
    final item = matches.isEmpty ? null : matches.first;

    if (item == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.itemProfile), elevation: 0),
        body: Center(
          // The pinned FE2-14 key marks the whole not-found composition.
          child: KeyedSubtree(
            key: const Key('itemMissingState'),
            child: AppEmptyState(
              icon: Icons.search_off,
              title: l10n.itemNotFound,
              message: '${l10n.itemNotAvailable}\n($itemCode)',
            ),
          ),
        ),
      );
    }

    final currency = l10n.priceDzd.contains('(')
        ? l10n.priceDzd.split('(').last.replaceAll(')', '')
        : 'DZD';

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.itemProfile),
        elevation: 0,
        actions: [
          if (provider.isHost)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: l10n.editItemDetails,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ItemFormScreen(item: item),
                  ),
                );
              },
            ),
          const SizedBox(width: AppSpacing.sm),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          // Content is width-capped so the profile stays a readable column on
          // an ultrawide window (§38).
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: AppSizing.maxFormWidth),
            child: Padding(
              padding: AppSpacing.allXxl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HeroHeader(item: item, l10n: l10n),
                  const SizedBox(height: AppSpacing.xxl),
                  // Core Workflow Recovery: the profile is where a librarian
                  // decides what to do with a title. Placing checkout /
                  // reserve right under the hero collapses a 3-screen detour
                  // (Loans tab -> search item -> pick member) into one click
                  // while keeping every permission gate on the provider side.
                  if (provider.canWrite) _ItemActionsBar(item: item),
                  if (provider.canWrite) const SizedBox(height: AppSpacing.xxl),
                  _InfoCard(
                    title: l10n.technicalInfo,
                    icon: Icons.qr_code_2,
                    children: [
                      _DetailRow(l10n.code, item.fullCode),
                      _DetailRow(l10n.barcode, item.barcode ?? '---'),
                      _DetailRow(l10n.typeLabel, item.codeType),
                      if (!provider.isHost)
                        _DetailRow(l10n.quantity, item.quantite.toString()),
                    ],
                  ),
                  if (provider.isHost) ...[
                    const SizedBox(height: AppSpacing.lg),
                    _InfoCard(
                      title: l10n.pricingInfo,
                      icon: Icons.payments_outlined,
                      children: [
                        _DetailRow(l10n.quantity, item.quantite.toString()),
                        _DetailRow(
                          l10n.rate,
                          '${item.taux.toStringAsFixed(2)} $currency',
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.lg),
                  _InfoCard(
                    title: l10n.locationInfo,
                    icon: Icons.location_on_outlined,
                    children: [
                      _DetailRow(l10n.location, item.emplacement),
                      _DetailRow(l10n.stockLocation, item.emplacementStock),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxxl),
                  // Copies (Phase 12): host-only physical-copy ledger +
                  // condition editor. Title status is derived from these
                  // copies (BL-05), so staff change availability HERE, not on
                  // the title.
                  if (provider.isHost) _CopiesCard(itemCode: item.code),
                  // Pass 5: per-record audit trail. Staff-only (mirrors the
                  // `/history` visibility the settings screen already gates
                  // behind a password prompt). Renders the last 8 rows that
                  // mention this code; the "See all" link opens the global
                  // history pre-filtered to the same subject.
                  if (provider.canWrite) ...[
                    const SizedBox(height: AppSpacing.xxxl),
                    RecordHistorySection(
                      subject: item.code,
                      title: l10n.historyAction,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Core Workflow Recovery: staff-only action bar on the item profile.
///
/// Two capabilities the librarian performs on a specific title every day --
/// "give this to a member" (checkout) and "hold this for a member" (reserve)
/// -- used to require three screens each (Loans tab -> search item -> pick
/// member, or Reservations tab -> form). Surfacing them here keeps the
/// operator inside the record they were already reading.
////// The availability chip is host-only because the copy ledger is host-only
/// (`loadCopies` on the client returns empty -- see provider docs). On a
/// client we fall back to the derived title `status`, which is the same
/// signal checkOutItem itself enforces.
class _ItemActionsBar extends StatefulWidget {
  const _ItemActionsBar({required this.item});

  final LibraryItem item;

  @override
  State<_ItemActionsBar> createState() => _ItemActionsBarState();
}

class _ItemActionsBarState extends State<_ItemActionsBar> {
  bool _busy = false;
  int _availableCopies = 0;
  int _totalCopies = 0;
  bool _copiesLoaded = false;

  @override
  void initState() {
    super.initState();
    _loadCopies();
  }

  Future<void> _loadCopies() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final copies = await provider.loadCopies(widget.item.code);
    if (!mounted) return;
    setState(() {
      _totalCopies = copies.length;
      _availableCopies = copies
          .where((c) => c.copyState == CopyState.available)
          .length;
      _copiesLoaded = true;
    });
  }

  Future<void> _checkout() async {
    if (_busy) return;
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final member = await MemberSelectDialog.show(context);
    if (member == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await provider.checkOutItem(widget.item, member);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.loanSuccess)));
      await _loadCopies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeError(l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reserve() async {
    if (_busy) return;
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final member = await MemberSelectDialog.show(context);
    if (member == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await provider.placeReservation(widget.item.code, member.memberId);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.reserveSuccess)));
      await _loadCopies();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeError(l10n, e))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final isHost = _copiesLoaded && _totalCopies > 0;
    // Availability gate mirrors the provider's own rule: a title is only
    // checkout-eligible while its derived status is 'Disponible'.
    final titleAvailable = widget.item.status == 'Disponible';
    final checkoutEnabled =
        !(_busy) && (isHost ? _availableCopies > 0 : titleAvailable);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                AppStatusChip(
                  label: isHost
                      ? l10n.copiesAvailableLabel(
                          _availableCopies,
                          _totalCopies,
                        )
                      : ItemStatusCell.localize(widget.item.status, l10n),
                  color: checkoutEnabled
                      ? AppStatus.success
                      : AppStatus.neutral,
                ),
                const Spacer(),
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _reserve,
                      icon: _busy
                          ? const SizedBox(
                              width: AppIcon.sm,
                              height: AppIcon.sm,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(
                              Icons.bookmark_add_outlined,
                              size: AppIcon.md,
                            ),
                      label: Text(l10n.reserveAction),
                    ),
                    FilledButton.icon(
                      onPressed: checkoutEnabled ? _checkout : null,
                      icon: const Icon(
                        Icons.assignment_return_outlined,
                        size: AppIcon.md,
                      ),
                      label: Text(l10n.checkoutAction),
                    ),
                  ],
                ),
              ],
            ),
            if (!checkoutEnabled && !_busy) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                l10n.noCopiesAvailableForCheckout,
                style: txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// The item's identity block: theme-tinted glyph, designation and the derived
/// status rendered through the ONE shared chip (no hand-rolled clone here).
class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.item, required this.l10n});

  final LibraryItem item;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxxl),
        child: Column(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: const Icon(Icons.auto_stories_outlined, size: AppIcon.xl),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              item.designation,
              style: txt.headlineSmall?.copyWith(color: scheme.onSurface),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            AppStatusChip(
              label: ItemStatusCell.localize(item.status, l10n),
              color: ItemStatusCell.statusColor(item.status),
            ),
          ],
        ),
      ),
    );
  }
}

/// One titled information panel (technical / pricing / location). The header
/// reuses the shared [AppSection] framing so this page and the dashboard title
/// their groups identically.
class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: AppSection(
        title: title,
        icon: icon,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

/// A label/value line: muted label left, semibold value right, both from the
/// type scale (was hand-sized 13px greys that vanished in dark mode).
class _DetailRow extends StatelessWidget {
  const _DetailRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          Text(
            value,
            style: txt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

/// Host-only physical-copy ledger for a title (Phase 12). Lists every copy
/// with its condition chip and lets staff set an in-hand copy to
/// available / in-repair / lost / archived. A copy that is currently on loan or
/// reserved is circulation-owned, so it is shown locked with no editor: the
/// loan / hold flows must change it (otherwise the copy ledger and the derived
/// title status would desync). Each write re-derives the title status on the
/// host and is awaited before the list refreshes (FE2-01/02).
class _CopiesCard extends StatefulWidget {
  const _CopiesCard({required this.itemCode});

  final String itemCode;

  @override
  State<_CopiesCard> createState() => _CopiesCardState();
}

class _CopiesCardState extends State<_CopiesCard> {
  static const List<CopyState> _editable = [
    CopyState.available,
    CopyState.maintenance,
    CopyState.lost,
    CopyState.archived,
  ];

  List<ItemCopy> _copies = const [];
  bool _loading = true;
  bool _busy = false;
  int? _busyCopyId;

  Future<void> _load() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final copies = await provider.loadCopies(widget.itemCode);
    if (!mounted) return;
    setState(() {
      _copies = copies;
      _loading = false;
    });
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _setCondition(ItemCopy copy, CopyState target) async {
    if (_busyCopyId != null) return;
    final id = copy.id;
    if (id == null) return;
    setState(() => _busyCopyId = id);
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    try {
      await provider.setCopyCondition(widget.itemCode, id, target);
      await _load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.copyStateUpdated),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(describeError(AppLocalizations.of(context)!, e)),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyCopyId = null);
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    // The theme's snackbar styling carries the message; forcing a red bar
    // only exists in light mode and is decoration, not information.
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _addCopy() async {
    if (_busy) return;
    setState(() => _busy = true);
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    try {
      await provider.addCopy(widget.itemCode);
      await _load();
      _snack(l10n.copyAdded);
    } catch (e) {
      _snack(describeError(l10n, e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeCopy(ItemCopy copy) async {
    final id = copy.id;
    if (id == null || _busyCopyId != null) return;
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.removeCopy),
        content: Text(l10n.removeCopyConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: scheme.error),
            child: Text(l10n.operationDelete),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busyCopyId = id);
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    try {
      await provider.removeCopy(widget.itemCode, id);
      await _load();
      _snack(l10n.copyRemoved);
    } catch (e) {
      _snack(describeError(l10n, e));
    } finally {
      if (mounted) setState(() => _busyCopyId = null);
    }
  }

  Future<void> _editBarcode(ItemCopy copy) async {
    final id = copy.id;
    if (id == null) return;
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: copy.barcode ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.setCopyBarcode),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(labelText: l10n.barcode),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: Text(l10n.copyBarcodeSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted) return;
    setState(() => _busyCopyId = id);
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    try {
      await provider.setCopyBarcode(widget.itemCode, id, result);
      await _load();
      _snack(l10n.copyBarcodeSaved);
    } catch (e) {
      _snack(describeError(l10n, e));
    } finally {
      if (mounted) setState(() => _busyCopyId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Card(
      child: AppSection(
        title: l10n.itemCopies,
        icon: Icons.copy_all_outlined,
        trailing: IconButton(
          onPressed: _busy ? null : _addCopy,
          tooltip: l10n.addCopy,
          visualDensity: VisualDensity.compact,
          icon: _busy
              ? const SizedBox(
                  width: AppIcon.md,
                  height: AppIcon.md,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  Icons.add_circle_outline,
                  size: AppIcon.lg,
                  color: scheme.primary,
                ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.all(AppSpacing.lg),
                child: Center(
                  child: SizedBox(
                    width: AppIcon.md,
                    height: AppIcon.md,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else if (_copies.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
                child: Text(
                  l10n.noCopiesYet,
                  style: txt.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (var i = 0; i < _copies.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == _copies.length - 1 ? 0 : AppSpacing.sm,
                  ),
                  child: _copyRow(i, _copies[i], l10n),
                ),
          ],
        ),
      ),
    );
  }

  Widget _copyRow(int index, ItemCopy copy, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final state = copy.copyState;
    final locked = state == CopyState.onLoan || state == CopyState.reserved;
    final barcode = copy.barcode;
    return Row(
      children: [
        SizedBox(
          width: 130,
          child: Text(
            l10n.copyNumberLabel(index + 1),
            style: txt.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: scheme.onSurface,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Expanded(
          child: Text(
            (barcode == null || barcode.isEmpty)
                ? l10n.copyBarcodeMissing
                : barcode,
            style: txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppStatusChip(
          label: ItemStatusCell.localize(copy.state, l10n),
          color: ItemStatusCell.statusColor(copy.state),
        ),
        const SizedBox(width: AppSpacing.xs),
        SizedBox(
          width: 44,
          child: locked
              ? Tooltip(
                  message: l10n.copyLockedTooltip,
                  child: Icon(
                    Icons.lock_outline,
                    size: AppIcon.md,
                    color: scheme.onSurfaceVariant,
                  ),
                )
              : _copyMenu(copy, l10n),
        ),
      ],
    );
  }

  Widget _copyMenu(ItemCopy copy, AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final busy = _busyCopyId == copy.id;
    final canRemove = _copies.length > 1;
    return PopupMenuButton<Object>(
      enabled: !busy,
      tooltip: l10n.changeCopyState,
      icon: busy
          ? const SizedBox(
              width: AppIcon.md,
              height: AppIcon.md,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.more_vert, size: AppIcon.lg, color: scheme.primary),
      onSelected: (v) {
        if (v is CopyState) {
          _setCondition(copy, v);
        } else if (v == _CopyOp.barcode) {
          _editBarcode(copy);
        } else if (v == _CopyOp.remove) {
          _removeCopy(copy);
        }
      },
      itemBuilder: (_) => [
        for (final t in _editable)
          PopupMenuItem<CopyState>(
            value: t,
            enabled: t != copy.copyState,
            child: Text(ItemStatusCell.localize(t.storage, l10n)),
          ),
        const PopupMenuItem<Object>(enabled: false, child: Divider(height: 1)),
        PopupMenuItem<Object>(
          value: _CopyOp.barcode,
          child: Row(
            children: [
              Icon(Icons.qr_code, size: AppIcon.md, color: scheme.primary),
              const SizedBox(width: AppSpacing.sm),
              Text(l10n.setCopyBarcode),
            ],
          ),
        ),
        PopupMenuItem<Object>(
          value: _CopyOp.remove,
          enabled: canRemove,
          child: Row(
            children: [
              Icon(
                Icons.delete_outline,
                size: AppIcon.md,
                color: canRemove ? scheme.error : scheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                l10n.removeCopy,
                style: txt.bodyMedium?.copyWith(
                  color: canRemove ? scheme.error : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
