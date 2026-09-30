import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../domain/hold_policy.dart';
import '../l10n/app_localizations.dart';
import '../models/library_item.dart';
import '../models/member.dart';
import '../models/reservation.dart';
import '../providers/library_provider.dart';
import '../services/api_service.dart' show ApiException;
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';
import '../widgets/app_status_chip.dart';

/// Reservations / hold queue (Phase 10.3b) -- the operator-facing hold desk.
///
/// Phase H (frontend reconstruction): presentation-only rebuild. The indigo
/// AppBar the shell already titles (double header) is gone -- the policy editor
/// now lives in the list toolbar -- and every raw grey/red/indigo value reads
/// through the theme + [AppStatus] palette, with the shared empty/loading state
/// components. The server-authoritative hold semantics below are unchanged.
///
/// Like every Phase 10 surface this screen is deliberately THIN: it only reads
/// and mutates through [LibraryProvider], which talks to the server-authoritative
/// repository (the host's SQLite engine or a LAN client's HTTP calls). The
/// SERVER owns the queue -- a hold only ever joins a line here; whether a copy
/// is actually handed to a member (promotion), when it expires, and who may
/// borrow a reserved copy are all decided host-side and merely reflected here.
/// Placing or cancelling a hold is staff-only, the pickup window / queue cap is
/// administrator policy, and a duplicate or full-queue request is refused by the
/// server (surfaced verbatim). Visibility is a courtesy: hiding a button never
/// grants a right the route guard would refuse.
class ReservationsScreen extends StatefulWidget {
  const ReservationsScreen({super.key});

  @override
  State<ReservationsScreen> createState() => _ReservationsScreenState();
}

/// The three list scopes, driven entirely by server-side queries (never a
/// client-side trim of a cached page).
enum HoldScope { all, open, ready }

class _ReservationsScreenState extends State<ReservationsScreen> {
  List<Reservation> _holds = const [];
  HoldSettings _settings = HoldSettings.defaults;
  HoldScope _scope = HoldScope.open;
  bool _loading = true;
  bool _busy = false;
  // Pass 6: focus the queue on a single title so an operator can bubble a
  // walk-in up the line. Rank is per-item, so cross-item reordering has
  // no meaning -- the reorder affordance only appears when this is set.
  String? _itemFilter;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    if (!provider.canWrite) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        provider.getHoldSettings(),
        _queryHolds(provider),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as HoldSettings;
        _holds = results[1] as List<Reservation>;
      });
    } catch (e) {
      if (!mounted) return;
      _showError(l10n, e, fallback: l10n.holdViewFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<List<Reservation>> _queryHolds(LibraryProvider provider) {
    // Pass 6: the item filter is orthogonal to the status scope. A focus
    // on one item shows every hold on that item in the current scope
    // (all/open/ready), which is exactly the queue the operator wants to
    // reorder.
    if (_itemFilter != null) {
      return provider.getReservations(itemCode: _itemFilter);
    }
    switch (_scope) {
      case HoldScope.all:
        return provider.getReservations();
      case HoldScope.open:
        return provider.getReservations(liveOnly: true);
      case HoldScope.ready:
        return provider.readyForPickup();
    }
  }

  /// Pass 6: reorder the row's queue position. Same mutation-guard as
  /// [cancel]; on success the reload reflects the server's authoritative
  /// new order (the swap can be a no-op at a boundary, which is fine -- the
  /// list simply redraws unchanged).
  Future<void> _move(Reservation hold, {required bool up}) async {
    if (hold.id == null) return;
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    await _mutate(() async {
      await provider.moveReservation(hold.id!, up: up);
      if (mounted) _showSnack(l10n.queueMoved);
    });
  }

  /// Whether the given hold is at a queue boundary within its own item line
  /// (only meaningful when the item filter is on, so the loaded _holds IS
  /// the complete line for that item). Used to dim the arrow buttons.
  bool _atBoundary(Reservation hold, {required bool up}) {
    if (hold.status != ReservationStatus.queued) return true;
    final line = _holds
        .where(
          (h) =>
              h.itemCode == hold.itemCode &&
              h.status == ReservationStatus.queued,
        )
        .toList();
    final idx = line.indexWhere((h) => h.id == hold.id);
    if (idx < 0) return true;
    return up ? idx == 0 : idx == line.length - 1;
  }

  void _showError(AppLocalizations l10n, Object e, {String? fallback}) {
    final msg = fallback == null
        ? _holdMessage(l10n, e)
        : '$fallback\n${_holdMessage(l10n, e)}';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: Theme.of(context).colorScheme.error,
      ),
    );
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Runs a place/cancel/policy mutation with a busy guard and reload-on-
  /// success, so the list can never show a state the server refused.
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

  Future<void> _place() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final placed = await showDialog<bool>(
      context: context,
      builder: (_) => _PlaceHoldDialog(
        items: provider.items,
        members: provider.members,
        onSubmit: (code, member) async {
          await provider.placeReservation(code, member);
        },
      ),
    );
    if (placed == true) {
      await _load();
      if (mounted) _showSnack(l10n.holdPlaced);
    }
  }

  Future<void> _cancel(Reservation hold) async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.holdCancel),
        content: Text(
          l10n.holdCancelConfirm(
            _memberLabel(provider.members, hold.memberId),
            _itemLabel(provider.items, hold.itemCode),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('cancelConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(l10n.holdCancel),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _mutate(() async {
      await provider.cancelReservation(hold.id!);
      if (mounted) _showSnack(l10n.holdCancelled);
    });
  }

  Future<void> _editPolicy() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _HoldPolicyDialog(
        initial: _settings,
        onSubmit: (s) => provider.setHoldSettings(s),
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) _showSnack(l10n.holdPolicySaved);
    }
  }

  String _memberLabel(List<Member> members, String id) {
    for (final m in members) {
      if (m.memberId == id) return m.fullName;
    }
    return id;
  }

  String _itemLabel(List<LibraryItem> items, String code) {
    for (final i in items) {
      if (i.code == code) return i.designation;
    }
    return code;
  }

  String _date(String? iso) {
    if (iso == null) return '';
    return DateTime.tryParse(iso)?.toLocal().toString().split(' ').first ?? '';
  }

  /// 1-based place in line for a QUEUED hold, computed from the open holds of
  /// the same title already loaded (the same pure rule the server uses).
  int? _positionFor(Reservation hold) {
    if (hold.status != ReservationStatus.queued) return null;
    final line = _holds
        .where(
          (h) =>
              h.itemCode == hold.itemCode &&
              h.status == ReservationStatus.queued,
        )
        .toList();
    return HoldPolicy.queuePosition(hold, line, DateTime.now());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    if (!provider.canWrite) {
      // The shell already shows the section title + the read-only banner; this
      // surface just says honestly that the queue is staff-gated.
      return Scaffold(
        body: AppEmptyState(
          icon: Icons.lock_outline,
          title: l10n.onlyStaffManageHolds,
          compact: true,
        ),
      );
    }

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('placeHoldFab'),
        onPressed: (_loading || _busy) ? null : _place,
        icon: const Icon(Icons.add),
        label: Text(l10n.holdPlace),
      ),
      body: _loading
          ? const AppLoadingState()
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  _toolbar(l10n, provider),
                  Expanded(
                    child: _holds.isEmpty
                        ? ListView(
                            children: [
                              AppEmptyState(
                                icon: Icons.bookmark_border,
                                title: _scopeLabel(l10n),
                                message: _scope == HoldScope.ready
                                    ? l10n.holdNothingReady
                                    : l10n.holdNoHolds,
                                compact: true,
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs,
                            ),
                            itemCount: _holds.length,
                            itemBuilder: (_, i) => _tile(l10n, _holds[i]),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  /// The current list scope, localized. Shown as the toolbar caption instead of
  /// repeating the section title the shell already renders above.
  String _scopeLabel(AppLocalizations l10n) => switch (_scope) {
    HoldScope.all => l10n.holdFilterAll,
    HoldScope.open => l10n.holdFilterOpen,
    HoldScope.ready => l10n.holdFilterReady,
  };

  Widget _toolbar(AppLocalizations l10n, LibraryProvider provider) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.lg,
        top: AppSpacing.md,
        end: AppSpacing.lg,
        bottom: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _scope == HoldScope.ready && _holds.isNotEmpty
                  ? '${_holds.length} • ${l10n.holdFilterReady}'
                  : _scopeLabel(l10n),
              style: txt.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (provider.canAdminister)
            IconButton(
              key: const Key('holdPolicyButton'),
              tooltip: l10n.holdPolicyTooltip,
              icon: const Icon(Icons.tune),
              onPressed: (_loading || _busy) ? null : _editPolicy,
            ),
          DropdownButton<HoldScope>(
            key: const Key('holdScope'),
            value: _scope,
            items: [
              DropdownMenuItem(
                value: HoldScope.all,
                child: Text(l10n.holdFilterAll),
              ),
              DropdownMenuItem(
                value: HoldScope.open,
                child: Text(l10n.holdFilterOpen),
              ),
              DropdownMenuItem(
                value: HoldScope.ready,
                child: Text(l10n.holdFilterReady),
              ),
            ],
            onChanged: (v) {
              if (v == null) return;
              setState(() => _scope = v);
              _load();
            },
          ),
          // Pass 6: item filter. Populated from the distinct item codes in
          // the currently-loaded holds so the operator picks a line they
          // can already see, not from the entire catalogue. When set, the
          // reorder arrows appear on every queued row.
          const SizedBox(width: AppSpacing.sm),
          _itemFilterDropdown(l10n),
        ],
      ),
    );
  }

  Widget _itemFilterDropdown(AppLocalizations l10n) {
    final codes = <String>{for (final h in _holds) h.itemCode}.toList()..sort();
    final hasSelection = _itemFilter != null;
    return Tooltip(
      message: l10n.queueOrderByItem,
      child: SizedBox(
        width: 140,
        child: DropdownButton<String?>(
          key: const Key('holdItemFilter'),
          isExpanded: true,
          value: hasSelection ? _itemFilter : _allSentinel,
          items: [
            DropdownMenuItem<String?>(
              value: _allSentinel,
              child: Text(
                l10n.all,
                style: TextStyle(
                  fontStyle: hasSelection ? FontStyle.normal : FontStyle.italic,
                ),
              ),
            ),
            for (final c in codes)
              DropdownMenuItem<String?>(value: c, child: Text(c)),
          ],
          onChanged: (v) {
            setState(() {
              _itemFilter = (v == _allSentinel) ? null : v;
            });
            _load();
          },
        ),
      ),
    );
  }

  /// Sentinel for "no item filter" inside the nullable dropdown. Using a
  /// distinct string instead of `null` avoids the ambiguity between "no
  /// selection" and "selection cleared by the OS".
  static const String _allSentinel = '__all__';

  Widget _tile(AppLocalizations l10n, Reservation hold) {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final scheme = Theme.of(context).colorScheme;
    // Hold states read through the same semantic palette as item statuses:
    // a live hold is the orange "reserved" hue, a ready copy is green like a
    // shelved-available one, a fulfilled line is blue like a borrowed one.
    final color = switch (hold.status) {
      ReservationStatus.queued => AppStatus.reserved,
      ReservationStatus.available => AppStatus.available,
      ReservationStatus.fulfilled => AppStatus.borrowed,
      ReservationStatus.cancelled => AppStatus.neutral,
      ReservationStatus.expired => AppStatus.danger,
    };
    final position = _positionFor(hold);
    final pickupBy = _date(hold.availableUntil);
    final subtitleParts = <String>[
      _itemLabel(provider.items, hold.itemCode),
      if (position != null) l10n.holdQueuePosition('$position'),
      if (hold.status == ReservationStatus.available && pickupBy.isNotEmpty)
        l10n.holdPickupBy(pickupBy),
    ];
    return Card(
      key: Key('hold-${hold.id}'),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(_statusIcon(hold.status), size: AppIcon.md, color: color),
        ),
        title: Text(_memberLabel(provider.members, hold.memberId)),
        subtitle: Text(subtitleParts.join('  •  ')),
        trailing: _tileTrailing(l10n, scheme, hold),
      ),
    );
  }

  /// Pass 6: the tile's trailing actions. When the operator has focused on
  /// a single item, every queued row gets up/down arrow buttons alongside
  /// the existing cancel icon; a promoted or terminal row still shows only
  /// the status chip / cancel, unchanged from before. Boundary rows keep
  /// their arrows visible but disabled so the affordance stays discoverable
  /// (an operator who wonders "why can't I move this one up?" sees an
  /// obvious greyed-out arrow instead of a mysterious missing button).
  Widget _tileTrailing(
    AppLocalizations l10n,
    ColorScheme scheme,
    Reservation hold,
  ) {
    final showReorder =
        _itemFilter != null && hold.status == ReservationStatus.queued;
    // The status chip is ALWAYS rendered — on live rows too. Previously it
    // was only in the `else` branch, so a queued hold (waiting in line) and
    // an available hold (ready at the counter) looked pixel-identical in
    // the trailing area, forcing staff to rely on the small leading icon
    // to distinguish the two. An operator scanning a busy queue needs the
    // label, not just a coloured glyph.
    final chip = AppStatusChip(
      label: _statusLabel(hold.status, l10n),
      color: _statusColor(hold.status),
    );
    final cancel = hold.isLive
        ? IconButton(
            key: Key('hold-cancel-${hold.id}'),
            tooltip: l10n.holdCancel,
            icon: Icon(Icons.cancel_presentation_outlined, color: scheme.error),
            onPressed: _busy ? null : () => _cancel(hold),
          )
        : null;
    // Terminal rows show the chip alone; live rows show [chip · cancel].
    final base = cancel == null
        ? chip
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              chip,
              const SizedBox(width: AppSpacing.xs),
              cancel,
            ],
          );
    if (!showReorder) return base;
    // Material 3 dimming for a disabled IconButton is normally driven by the
    // ambient `IconButtonTheme`. But `ListTile.trailing` re-publishes its own
    // nested `IconButtonTheme` (list_tile.dart resolves it once against the
    // tile's state set and wraps it as `WidgetStatePropertyAll`), which
    // shadows the app-level theme and pins both enabled and disabled arrows
    // to the same color. Set `Icon.color` explicitly here — an Icon's own
    // color outranks the ambient `IconTheme`/`IconButtonTheme` and is the
    // only reliable way to signal the boundary ("this row cannot move
    // further") while keeping the arrow visible.
    final upDisabled = _busy || _atBoundary(hold, up: true);
    final downDisabled = _busy || _atBoundary(hold, up: false);
    Color arrowColor(bool disabled) => disabled
        ? scheme.onSurface.withValues(alpha: 0.38)
        : scheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          key: Key('hold-up-${hold.id}'),
          tooltip: l10n.queueMoveUp,
          icon: Icon(Icons.arrow_upward, color: arrowColor(upDisabled)),
          onPressed: upDisabled ? null : () => _move(hold, up: true),
        ),
        IconButton(
          key: Key('hold-down-${hold.id}'),
          tooltip: l10n.queueMoveDown,
          icon: Icon(Icons.arrow_downward, color: arrowColor(downDisabled)),
          onPressed: downDisabled ? null : () => _move(hold, up: false),
        ),
        base,
      ],
    );
  }

  Color _statusColor(ReservationStatus s) => switch (s) {
    ReservationStatus.queued => AppStatus.reserved,
    ReservationStatus.available => AppStatus.available,
    ReservationStatus.fulfilled => AppStatus.borrowed,
    ReservationStatus.cancelled => AppStatus.neutral,
    ReservationStatus.expired => AppStatus.danger,
  };

  String _statusLabel(ReservationStatus s, AppLocalizations l10n) =>
      switch (s) {
        ReservationStatus.queued => l10n.holdStatusQueued,
        ReservationStatus.available => l10n.holdStatusAvailable,
        ReservationStatus.fulfilled => l10n.holdStatusFulfilled,
        ReservationStatus.cancelled => l10n.holdStatusCancelled,
        ReservationStatus.expired => l10n.holdStatusExpired,
      };

  IconData _statusIcon(ReservationStatus s) => switch (s) {
    ReservationStatus.queued => Icons.hourglass_empty,
    ReservationStatus.available => Icons.inventory_2_outlined,
    ReservationStatus.fulfilled => Icons.check_circle_outline,
    ReservationStatus.cancelled => Icons.block,
    ReservationStatus.expired => Icons.error_outline,
  };
}

/// Surfaces the concrete, server-authored refusal (an unknown item/member, a
/// duplicate live hold, a full queue, or a cancel of a closed hold -> 409; a
/// malformed body -> 400) instead of a generic message. The text is authored by
/// the server / host engine and carries no secrets.
String _holdMessage(AppLocalizations l10n, Object e) {
  if (e is StateError) return e.message;
  if (e is ApiException &&
      (e.error == 'bad_request' || e.error == 'conflict') &&
      e.message.trim().isNotEmpty) {
    return e.message;
  }
  return describeError(l10n, e);
}

/// Staff dialog to add a member to a title's line: choose an item and a member,
/// both read from the already-loaded catalogue/membership. The server validates
/// existence and every queue rule; a refusal is shown here verbatim.
class _PlaceHoldDialog extends StatefulWidget {
  const _PlaceHoldDialog({
    required this.items,
    required this.members,
    required this.onSubmit,
  });

  final List<LibraryItem> items;
  final List<Member> members;
  final Future<void> Function(String itemCode, String memberId) onSubmit;

  @override
  State<_PlaceHoldDialog> createState() => _PlaceHoldDialogState();
}

class _PlaceHoldDialogState extends State<_PlaceHoldDialog> {
  String? _itemCode;
  String? _memberId;
  String? _error;
  bool _busy = false;

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    if (_itemCode == null || _memberId == null) {
      setState(() => _error = l10n.holdNeedSelection);
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onSubmit(_itemCode!, _memberId!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = _holdMessage(l10n, e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final canPick = widget.items.isNotEmpty && widget.members.isNotEmpty;
    return AlertDialog(
      title: Text(l10n.holdPlace),
      content: !canPick
          ? Text(widget.items.isEmpty ? l10n.holdNoItems : l10n.holdNoMembers)
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  key: const Key('holdItemField'),
                  initialValue: _itemCode,
                  decoration: InputDecoration(labelText: l10n.holdItemLabel),
                  items: [
                    for (final i in widget.items)
                      DropdownMenuItem(
                        value: i.code,
                        child: Text(
                          '${i.designation} (${i.code})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _itemCode = v),
                ),
                const SizedBox(height: AppSpacing.md),
                DropdownButtonFormField<String>(
                  key: const Key('holdMemberField'),
                  initialValue: _memberId,
                  decoration: InputDecoration(labelText: l10n.holdMemberLabel),
                  items: [
                    for (final m in widget.members)
                      DropdownMenuItem(
                        value: m.memberId,
                        child: Text(
                          '${m.fullName} (${m.memberId})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _memberId = v),
                ),
                if (_error != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
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
          key: const Key('holdPlaceSave'),
          onPressed: (!canPick || _busy) ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.holdPlace),
        ),
      ],
    );
  }
}

/// Admin-only editor for the hold policy (pickup window + per-title queue cap).
/// Input is hardened on both sides: integer-only formatters plus a validator
/// enforcing the same bounds the server allows, and the PUT route independently
/// rejects an out-of-range value with a 400 -- the dialog is UX, the server is
/// the gate.
class _HoldPolicyDialog extends StatefulWidget {
  const _HoldPolicyDialog({required this.initial, required this.onSubmit});

  final HoldSettings initial;
  final Future<void> Function(HoldSettings) onSubmit;

  @override
  State<_HoldPolicyDialog> createState() => _HoldPolicyDialogState();
}

class _HoldPolicyDialogState extends State<_HoldPolicyDialog> {
  late final TextEditingController _pickup = TextEditingController(
    text: widget.initial.pickupDays.toString(),
  );
  late final TextEditingController _cap = TextEditingController(
    text: widget.initial.queueMaxPerItem.toString(),
  );
  bool _busy = false;

  @override
  void dispose() {
    _pickup.dispose();
    _cap.dispose();
    super.dispose();
  }

  String? _validate(String raw, int min, int max) {
    final v = int.tryParse(raw.trim());
    if (v == null || v < min || v > max) return ' ';
    return null;
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final pickupErr = _validate(_pickup.text, 1, 90);
    final capErr = _validate(_cap.text, 1, 500);
    if (pickupErr != null || capErr != null) {
      setState(() {}); // re-run validators to surface errors
      return;
    }
    setState(() => _busy = true);
    try {
      await widget.onSubmit(
        HoldSettings(
          pickupDays: int.parse(_pickup.text.trim()),
          queueMaxPerItem: int.parse(_cap.text.trim()),
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_holdMessage(l10n, e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.holdPolicy),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('holdPickupField'),
            controller: _pickup,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.holdPickupDays,
              errorText: _validate(_pickup.text, 1, 90),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('holdCapField'),
            controller: _cap,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(
              labelText: l10n.holdQueueCap,
              errorText: _validate(_cap.text, 1, 500),
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
          key: const Key('holdPolicySave'),
          onPressed: _busy ? null : _submit,
          child: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.save),
        ),
      ],
    );
  }
}
