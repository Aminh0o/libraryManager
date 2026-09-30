import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/fine.dart';
import '../providers/library_provider.dart';
import '../services/api_service.dart' show ApiException;
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';
import '../widgets/app_status_chip.dart';

/// Fines & payments (Phase 10.2b) -- the operator-facing ledger.
///
/// Phase H (frontend reconstruction): presentation-only rebuild. The teal
/// AppBar the shell already titles (double header) is gone -- the policy editor
/// now lives in the ledger toolbar -- and the raw red/green/orange/grey values
/// read through the theme + [AppStatus] palette with the shared state
/// components. The server-authoritative settle/waive semantics below are
/// unchanged.
///
/// Like every Phase 10 surface, this screen is deliberately THIN: it only reads
/// and mutates through [LibraryProvider], which talks to the server-authoritative
/// repository (the host's SQLite engine or a LAN client's HTTP calls). The money
/// was already decided by the server when an overdue loan was returned; here an
/// operator can only COLLECT or WAIVE an open fine, and both are guarded,
/// idempotency-safe operations -- the server refuses a double settle with a 409
/// and records WHO did it ([Fine.resolvedBy]). The overdue RATE is policy, so
/// editing it is reserved for an administrator; the rest merely reflects what
/// the server returned.
///
/// Visibility is a courtesy: a client that hides these buttons is still refused
/// by the server's route guards. The screen is mounted in the rail only for a
/// staff+ session, and re-checks `canWrite` defensively.
class FinesScreen extends StatefulWidget {
  const FinesScreen({super.key});

  @override
  State<FinesScreen> createState() => _FinesScreenState();
}

class _FinesScreenState extends State<FinesScreen> {
  List<Fine> _fines = const [];
  FineSettings _settings = FineSettings.disabled;
  FineStatus? _filter;
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
    if (!provider.canWrite) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        provider.getFineSettings(),
        provider.getFines(status: _filter),
      ]);
      if (!mounted) return;
      setState(() {
        _settings = results[0] as FineSettings;
        _fines = results[1] as List<Fine>;
      });
    } catch (e) {
      if (!mounted) return;
      _showError(l10n, e, fallback: l10n.fineViewFailed);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _money(double amount) =>
      '${amount.toStringAsFixed(2)} ${_settings.currency}';

  double get _outstanding =>
      _fines.where((f) => f.isOpen).fold<double>(0, (sum, f) => sum + f.amount);

  void _showError(AppLocalizations l10n, Object e, {String? fallback}) {
    final msg = fallback == null
        ? _fineMessage(l10n, e)
        : '$fallback\n${_fineMessage(l10n, e)}';
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

  /// Runs a settle/policy mutation with a busy guard and reload-on-success, so
  /// the list can never show a state the server refused (e.g. a lost race).
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

  Future<void> _collect(Fine fine) async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.fineCollect),
        content: Text(l10n.fineCollectConfirm(_money(fine.amount))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('collectConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.fineCollect),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _mutate(() async {
      await provider.payFine(fine.id!);
      if (mounted) _showSnack(l10n.fineSettled);
    });
  }

  Future<void> _waive(Fine fine) async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.fineWaive),
        content: Text(l10n.fineWaiveConfirm(_money(fine.amount))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('waiveConfirm'),
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: AppStatus.warning),
            child: Text(l10n.fineWaive),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await _mutate(() async {
      await provider.waiveFine(fine.id!);
      if (mounted) _showSnack(l10n.fineSettled);
    });
  }

  Future<void> _editPolicy() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _FinePolicyDialog(
        initial: _settings,
        onSubmit: (s) => provider.setFineSettings(s),
      ),
    );
    if (saved == true) {
      await _load();
      if (mounted) _showSnack(l10n.finePolicySaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    if (!provider.canWrite) {
      // The shell already shows the section title + the read-only banner; this
      // surface just says honestly that the ledger is staff-gated.
      return Scaffold(
        body: AppEmptyState(
          icon: Icons.lock_outline,
          title: l10n.onlyStaffManageFines,
          compact: true,
        ),
      );
    }

    return Scaffold(
      body: _loading
          ? const AppLoadingState()
          : RefreshIndicator(
              onRefresh: _load,
              child: Column(
                children: [
                  _toolbar(l10n, provider),
                  Expanded(
                    child: _fines.isEmpty
                        ? ListView(
                            children: [
                              AppEmptyState(
                                icon: Icons.receipt_long_outlined,
                                title: l10n.fineNoFines,
                                compact: true,
                              ),
                            ],
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.xs,
                            ),
                            itemCount: _fines.length,
                            itemBuilder: (_, i) => _tile(l10n, _fines[i]),
                          ),
                  ),
                ],
              ),
            ),
    );
  }

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
              l10n.fineOutstanding(_money(_outstanding)),
              style: txt.titleSmall?.copyWith(
                color: scheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (provider.canAdminister)
            IconButton(
              key: const Key('finePolicyButton'),
              tooltip: l10n.finePolicyTooltip,
              icon: const Icon(Icons.tune),
              onPressed: (_loading || _busy) ? null : _editPolicy,
            ),
          DropdownButton<FineStatus?>(
            key: const Key('fineFilter'),
            value: _filter,
            hint: Text(l10n.fineFilterAll),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.fineFilterAll)),
              DropdownMenuItem(
                value: FineStatus.pending,
                child: Text(l10n.fineStatusPending),
              ),
              DropdownMenuItem(
                value: FineStatus.paid,
                child: Text(l10n.fineStatusPaid),
              ),
              DropdownMenuItem(
                value: FineStatus.waived,
                child: Text(l10n.fineStatusWaived),
              ),
            ],
            onChanged: (v) {
              setState(() => _filter = v);
              _load();
            },
          ),
        ],
      ),
    );
  }

  String _memberLabel(LibraryProvider provider, Fine fine) {
    for (final m in provider.members) {
      if (m.memberId == fine.memberId) return m.fullName;
    }
    return fine.memberId;
  }

  Widget _tile(AppLocalizations l10n, Fine fine) {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    // Money states keep the shared semantic hues: an unpaid fine is the danger
    // red, a settled one the success green, a waived one the neutral grey.
    final color = switch (fine.status) {
      FineStatus.pending => AppStatus.danger,
      FineStatus.paid => AppStatus.success,
      FineStatus.waived => AppStatus.neutral,
    };
    final statusLabel = switch (fine.status) {
      FineStatus.pending => l10n.fineStatusPending,
      FineStatus.paid => l10n.fineStatusPaid,
      FineStatus.waived => l10n.fineStatusWaived,
    };
    final date = fine.createdAt == null
        ? ''
        : (DateTime.tryParse(
                fine.createdAt!,
              )?.toLocal().toString().split(' ').first ??
              '');
    return Card(
      key: Key('fine-${fine.id}'),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.12),
          child: Icon(_statusIcon(fine.status), size: AppIcon.md, color: color),
        ),
        title: Text(
          '${_memberLabel(provider, fine)}  •  ${_money(fine.amount)}',
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${fine.reason ?? ''}${date.isEmpty ? '' : '  •  $date'}'),
            if (fine.resolvedBy != null)
              Text('${l10n.fineCollectedBy}: ${fine.resolvedBy}'),
          ],
        ),
        trailing: fine.isOpen
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: Key('fine-collect-${fine.id}'),
                    tooltip: l10n.fineCollect,
                    icon: const Icon(
                      Icons.payments_outlined,
                      color: AppStatus.success,
                    ),
                    onPressed: _busy ? null : () => _collect(fine),
                  ),
                  IconButton(
                    key: Key('fine-waive-${fine.id}'),
                    tooltip: l10n.fineWaive,
                    icon: const Icon(
                      Icons.volunteer_activism_outlined,
                      color: AppStatus.warning,
                    ),
                    onPressed: _busy ? null : () => _waive(fine),
                  ),
                ],
              )
            : AppStatusChip(label: statusLabel, color: color),
      ),
    );
  }

  IconData _statusIcon(FineStatus s) => switch (s) {
    FineStatus.pending => Icons.error_outline,
    FineStatus.paid => Icons.check_circle_outline,
    FineStatus.waived => Icons.block,
  };
}

/// Surfaces the concrete, server-authored refusal for a settle (a 409 double-pay
/// / unknown fine, or a 400 malformed body) instead of a generic message. The
/// text is authored by the server / host engine and carries no secrets.
String _fineMessage(AppLocalizations l10n, Object e) {
  if (e is StateError) return e.message;
  if (e is ApiException &&
      (e.error == 'bad_request' || e.error == 'conflict') &&
      e.message.trim().isNotEmpty) {
    return e.message;
  }
  return describeError(l10n, e);
}

/// Admin-only editor for the overdue fine policy (rate + currency). A rate of 0
/// DISABLES fines -- so this dialog is also how an admin turns the feature off.
class _FinePolicyDialog extends StatefulWidget {
  const _FinePolicyDialog({required this.initial, required this.onSubmit});

  final FineSettings initial;
  final Future<void> Function(FineSettings) onSubmit;

  @override
  State<_FinePolicyDialog> createState() => _FinePolicyDialogState();
}

class _FinePolicyDialogState extends State<_FinePolicyDialog> {
  late final TextEditingController _rate = TextEditingController(
    text: widget.initial.ratePerDay.toString(),
  );
  late final TextEditingController _currency = TextEditingController(
    text: widget.initial.currency,
  );
  String? _rateError;
  bool _busy = false;

  @override
  void dispose() {
    _rate.dispose();
    _currency.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context)!;
    final rate = double.tryParse(_rate.text.trim());
    if (rate == null || !rate.isFinite || rate < 0) {
      setState(() => _rateError = l10n.fineRatePerDay);
      return;
    }
    final currency = _currency.text.trim().isEmpty
        ? widget.initial.currency
        : _currency.text.trim();
    setState(() {
      _busy = true;
      _rateError = null;
    });
    try {
      await widget.onSubmit(FineSettings(ratePerDay: rate, currency: currency));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(_fineMessage(l10n, e)),
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
      title: Text(l10n.finePolicy),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            key: const Key('fineRateField'),
            controller: _rate,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
            ],
            decoration: InputDecoration(
              labelText: l10n.fineRatePerDay,
              errorText: _rateError,
              helperText: widget.initial.enabled
                  ? null
                  : l10n.finePolicyDisabledHint,
              helperMaxLines: 3,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          TextField(
            key: const Key('fineCurrencyField'),
            controller: _currency,
            textCapitalization: TextCapitalization.characters,
            decoration: InputDecoration(labelText: l10n.fineCurrency),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          key: const Key('finePolicySave'),
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
