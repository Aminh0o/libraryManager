import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/fine.dart';
import '../models/loan.dart';
import '../models/member.dart';
import '../models/reservation.dart';
import '../providers/library_provider.dart';
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';
import '../widgets/app_status_chip.dart';
import '../widgets/record_history_section.dart';

/// Core Workflow Recovery: member detail page.
/// A pushed route opened by tapping a member card in the list. Shows the
/// member's identity, active loans (with overdue flag + renew action),
/// outstanding fines, and live reservations -- all in one operational view
/// that a librarian needs when a patron approaches the desk.
class MemberDetailScreen extends StatefulWidget {
  const MemberDetailScreen({super.key, required this.memberId});

  final String memberId;

  @override
  State<MemberDetailScreen> createState() => _MemberDetailScreenState();
}

class _MemberDetailScreenState extends State<MemberDetailScreen> {
  List<Loan>? _loans;
  List<Fine>? _fines;
  List<Reservation>? _reservations;
  double? _balance;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final provider = context.read<LibraryProvider>();
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Loans: filter the in-memory list by memberId (already loaded).
      final allLoans = provider.loans;
      _loans = allLoans
          .where((l) => l.memberId == widget.memberId)
          .toList();

      // Fines + reservations require server queries (staff-only).
      if (provider.canWrite) {
        try {
          _fines = await provider
              .getFines(memberId: widget.memberId, status: FineStatus.pending);
          _balance = await provider.outstandingBalance(widget.memberId);
        } catch (_) {
          _fines = null;
          _balance = null;
        }
        try {
          _reservations = await provider.getReservations(
            memberId: widget.memberId,
            liveOnly: true,
          );
        } catch (_) {
          _reservations = null;
        }
      }
    } catch (e) {
      _error = e.toString();
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _renew(Loan loan) async {
    final provider = context.read<LibraryProvider>();
    final l10n = AppLocalizations.of(context)!;
    try {
      await provider.renewLoan(loan);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.renewSuccess)),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(describeError(l10n, e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = context.watch<LibraryProvider>();

    // Resolve the member from the already-loaded list.
    final matches =
        provider.members.where((m) => m.memberId == widget.memberId);
    final member = matches.isEmpty ? null : matches.first;

    if (member == null) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.memberDetail)),
        body: Center(
          child: AppEmptyState(
            icon: Icons.person_search_outlined,
            title: l10n.memberNotFound,
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(l10n.memberDetail)),
      body: RefreshIndicator(
        onRefresh: _load,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(AppSpacing.xxl),
          child: Center(
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: AppSizing.maxContentWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _IdentityCard(member: member, l10n: l10n),
                  const SizedBox(height: AppSpacing.xxl),
                  if (_loading)
                    const AppLoadingState()
                  else if (_error != null)
                    AppErrorState(
                        message: _error!,
                        retryLabel: l10n.retry,
                        onRetry: _load)
                  else ...[
                    _LoansSection(
                      loans: _loans ?? [],
                      l10n: l10n,
                      canWrite: provider.canWrite,
                      onRenew: _renew,
                    ),
                    if (provider.canWrite && _fines != null) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      _FinesSection(
                        balance: _balance ?? 0,
                        fines: _fines!,
                        l10n: l10n,
                      ),
                    ],
                    if (provider.canWrite && _reservations != null) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      _ReservationsSection(
                        reservations: _reservations!,
                        l10n: l10n,
                      ),
                    ],
                    // Pass 5: per-record audit trail. Same subject filter
                    // the item profile uses, but keyed by member id (the
                    // audit `details` embed "par <fullName>" for loans but
                    // "for <memberId>" for holds, so the id is the safer
                    // stable substring to match on).
                    if (provider.canWrite) ...[
                      const SizedBox(height: AppSpacing.xxl),
                      RecordHistorySection(
                        subject: widget.memberId,
                        title: l10n.historyAction,
                      ),
                    ],
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

class _IdentityCard extends StatelessWidget {
  const _IdentityCard({required this.member, required this.l10n});
  final Member member;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Row(
          children: [
            CircleAvatar(
              radius: 32,
              backgroundColor: scheme.primaryContainer,
              foregroundColor: scheme.onPrimaryContainer,
              child: member.avatarInitial.isEmpty
                  ? const Icon(Icons.person, size: AppIcon.xl)
                  : Text(member.avatarInitial, style: txt.headlineSmall),
            ),
            const SizedBox(width: AppSpacing.xxl),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(member.fullName,
                      style: txt.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: AppSpacing.xs),
                  Text('ID: ${member.memberId}', style: txt.bodyMedium),
                  const SizedBox(height: AppSpacing.xs),
                  Wrap(
                    spacing: AppSpacing.lg,
                    runSpacing: AppSpacing.xs,
                    children: [
                      if (member.phone != null && member.phone!.isNotEmpty)
                        _MetaChip(
                            icon: Icons.phone_outlined, label: member.phone!),
                      if (member.email != null && member.email!.isNotEmpty)
                        _MetaChip(
                            icon: Icons.email_outlined, label: member.email!),
                      _MetaChip(
                        icon: Icons.calendar_today_outlined,
                        label:
                            '${l10n.registered}: ${_fmtDate(member.registeredAt)}',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime d) {
    final local = d.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-${local.day.toString().padLeft(2, '0')}';
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.icon, required this.label});
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: AppIcon.sm, color: scheme.onSurfaceVariant),
        const SizedBox(width: AppSpacing.xs),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: scheme.onSurfaceVariant)),
      ],
    );
  }
}

class _LoansSection extends StatelessWidget {
  const _LoansSection({
    required this.loans,
    required this.l10n,
    required this.canWrite,
    required this.onRenew,
  });
  final List<Loan> loans;
  final AppLocalizations l10n;
  final bool canWrite;
  final Future<void> Function(Loan) onRenew;

  @override
  Widget build(BuildContext context) {
    final active = loans.where((l) => l.isActive).toList();
    final overdue = active.where((l) => l.isOverdue).toList();
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return AppSection(
      title: l10n.memberLoans,
      icon: Icons.assignment_outlined,
      trailing: active.isEmpty
          ? null
          : AppStatusChip(
              label: '${active.length}',
              color: overdue.isNotEmpty ? AppStatus.danger : AppStatus.info,
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (overdue.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(bottom: AppSpacing.md),
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: scheme.errorContainer.withValues(alpha: 0.3),
                borderRadius: AppRadius.card,
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded,
                      color: AppStatus.danger, size: AppIcon.lg),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      l10n.memberOverdueAlert(overdue.length),
                      style: txt.bodyMedium
                          ?.copyWith(color: scheme.onErrorContainer),
                    ),
                  ),
                ],
              ),
            ),
          if (loans.isEmpty)
            AppEmptyState(
                icon: Icons.assignment_outlined,
                title: l10n.noLoansForMember,
                compact: true)
          else
            for (final loan in active)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: _LoanRow(
                    loan: loan, l10n: l10n, canWrite: canWrite, onRenew: onRenew),
              ),
        ],
      ),
    );
  }
}

class _LoanRow extends StatelessWidget {
  const _LoanRow({
    required this.loan,
    required this.l10n,
    required this.canWrite,
    required this.onRenew,
  });
  final Loan loan;
  final AppLocalizations l10n;
  final bool canWrite;
  final Future<void> Function(Loan) onRenew;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final overdue = loan.isOverdue;
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.sm,
        ),
        title: Text(loan.itemTitle, style: txt.titleSmall),
        subtitle: Text(
          '${l10n.dueDate}: ${_fmt(loan.dueDate)}',
          style: txt.bodySmall?.copyWith(
            color: overdue ? AppStatus.danger : scheme.onSurfaceVariant,
            fontWeight: overdue ? FontWeight.w600 : null,
          ),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (overdue)
              AppStatusChip(label: l10n.overdue, color: AppStatus.danger),
            if (canWrite)
              IconButton(
                icon: const Icon(Icons.refresh, size: AppIcon.lg),
                tooltip: l10n.renewLoan,
                onPressed: () => onRenew(loan),
              ),
          ],
        ),
      ),
    );
  }

  String _fmt(DateTime d) {
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

class _FinesSection extends StatelessWidget {
  const _FinesSection({
    required this.balance,
    required this.fines,
    required this.l10n,
  });
  final double balance;
  final List<Fine> fines;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return AppSection(
      title: l10n.memberFines,
      icon: Icons.receipt_long_outlined,
      trailing: AppStatusChip(
        label: '${balance.toStringAsFixed(0)} DZD',
        color: balance > 0 ? AppStatus.danger : AppStatus.success,
      ),
      child: fines.isEmpty
          ? AppEmptyState(
              icon: Icons.check_circle_outline,
              title: l10n.noPendingFines,
              compact: true,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final fine in fines)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '${fine.amount.toStringAsFixed(0)} DZD',
                          style: txt.titleSmall),
                      subtitle: fine.reason != null
                          ? Text(fine.reason!, style: txt.bodySmall)
                          : null,
                      trailing: AppStatusChip(
                        label: l10n.finePending,
                        color: AppStatus.warning,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

class _ReservationsSection extends StatelessWidget {
  const _ReservationsSection({required this.reservations, required this.l10n});
  final List<Reservation> reservations;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final txt = Theme.of(context).textTheme;
    return AppSection(
      title: l10n.memberReservations,
      icon: Icons.bookmark_outline,
      trailing: reservations.isEmpty
          ? null
          : AppStatusChip(
              label: '${reservations.length}', color: AppStatus.reserved),
      child: reservations.isEmpty
          ? AppEmptyState(
              icon: Icons.bookmark_outline,
              title: l10n.noActiveReservations,
              compact: true,
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final res in reservations)
                  Padding(
                    padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                    child: ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(res.itemCode, style: txt.titleSmall),
                      subtitle: Text(
                        res.status == ReservationStatus.available
                            ? l10n.holdReadyForPickup
                            : l10n.holdQueued,
                        style: txt.bodySmall,
                      ),
                      trailing: AppStatusChip(
                        label: res.status == ReservationStatus.available
                            ? l10n.statusAvailable
                            : l10n.statusQueued,
                        color: res.status == ReservationStatus.available
                            ? AppStatus.success
                            : AppStatus.info,
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}
