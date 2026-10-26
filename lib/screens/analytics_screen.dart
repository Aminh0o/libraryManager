import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/fine.dart';
import '../providers/library_provider.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';
import '../widgets/stat_card.dart';

/// Advanced Analytics & Comprehensive Library Statistics Screen.
/// Provides visual insights into demographics (gender, member types, status),
/// circulation health (loan velocity, overdue rate), collection distribution,
/// and financial fine tracking.
class AnalyticsScreen extends StatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  State<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends State<AnalyticsScreen> {
  List<Fine> _fines = [];

  @override
  void initState() {
    super.initState();
    _loadFines();
  }

  Future<void> _loadFines() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    if (!provider.canWrite) return;
    try {
      final list = await provider.getFines();
      if (mounted) setState(() => _fines = list);
    } catch (_) {
      // Fines load failure is non-fatal; demographic and inventory analytics still render.
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    if (provider.isLoading) {
      return Scaffold(
        appBar: AppBar(title: Text(l10n.advancedAnalytics)),
        body: const AppLoadingState(),
      );
    }

    final members = provider.members;
    final totalMembers = members.length;

    // Gender breakdown
    int maleCount = 0;
    int femaleCount = 0;
    int otherGenderCount = 0;
    for (final m in members) {
      final g = (m.gender ?? '').trim().toLowerCase();
      if (g == 'male') {
        maleCount++;
      } else if (g == 'female') {
        femaleCount++;
      } else {
        otherGenderCount++;
      }
    }

    // Member types breakdown
    final typeCounts = <String, int>{};
    for (final m in members) {
      final t = m.memberType ?? l10n.notSet;
      typeCounts[t] = (typeCounts[t] ?? 0) + 1;
    }

    // Member status breakdown
    int activeMembers = 0;
    int expiredMembers = 0;
    int suspendedMembers = 0;
    for (final m in members) {
      final s = (m.status ?? '').trim().toLowerCase();
      if (s == 'active') {
        activeMembers++;
      } else if (s == 'expired') {
        expiredMembers++;
      } else if (s == 'suspended') {
        suspendedMembers++;
      }
    }

    // Circulation calculations
    final activeLoans = provider.onLoanCount;
    final overdueLoans = provider.overdueLoanCount;
    final overdueRate = activeLoans > 0
        ? ((overdueLoans / activeLoans) * 100).toStringAsFixed(1)
        : '0.0';
    final onTimeRate = activeLoans > 0
        ? (((activeLoans - overdueLoans) / activeLoans) * 100).toStringAsFixed(
            1,
          )
        : '100.0';

    // Financial calculations
    double finesTotalPaid = 0;
    double finesTotalOutstanding = 0;
    for (final f in _fines) {
      if (f.status == FineStatus.paid) {
        finesTotalPaid += f.amount;
      } else if (f.status == FineStatus.pending) {
        finesTotalOutstanding += f.amount;
      }
    }

    // Top borrowed items from active loans
    final itemBorrowFrequency = <String, int>{};
    for (final loan in provider.loans) {
      final title = loan.itemTitle.isNotEmpty ? loan.itemTitle : loan.itemCode;
      itemBorrowFrequency[title] = (itemBorrowFrequency[title] ?? 0) + 1;
    }
    final sortedTopItems = itemBorrowFrequency.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // Zero-circulation items (items with 0 active loans)
    final activeLoanCodes = provider.loans.map((l) => l.itemCode).toSet();
    final zeroCirculationItems = provider.items
        .where((i) => !activeLoanCodes.contains(i.code))
        .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.advancedAnalytics),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refreshData,
            onPressed: () {
              provider.reload();
              _loadFines();
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: AppSpacing.allXxl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Headline Overview Stat Cards
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                return GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: isWide ? 4 : 2,
                  crossAxisSpacing: AppSpacing.md,
                  mainAxisSpacing: AppSpacing.md,
                  childAspectRatio: isWide ? 2.2 : 1.8,
                  children: [
                    StatCard(
                      title: l10n.members,
                      value: totalMembers.toString(),
                      icon: Icons.people_outline,
                      color: AppStatus.info,
                    ),
                    StatCard(
                      title: l10n.onLoan,
                      value: activeLoans.toString(),
                      icon: Icons.assignment_return_outlined,
                      color: AppStatus.borrowed,
                    ),
                    StatCard(
                      title: l10n.statOverdue,
                      value: overdueLoans.toString(),
                      icon: Icons.event_busy_outlined,
                      color: AppStatus.danger,
                    ),
                    StatCard(
                      title: l10n.totalDocuments,
                      value: provider.totalQuantity.toString(),
                      icon: Icons.auto_stories_outlined,
                      color: AppStatus.success,
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xxxl),

            // Demographics Section
            Text(
              l10n.demographics,
              style: txt.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.gender,
                      style: txt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    _DemographicBar(
                      label: l10n.genderMale,
                      count: maleCount,
                      total: totalMembers,
                      color: Colors.blue,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _DemographicBar(
                      label: l10n.genderFemale,
                      count: femaleCount,
                      total: totalMembers,
                      color: Colors.pink,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    _DemographicBar(
                      label: l10n.genderOther,
                      count: otherGenderCount,
                      total: totalMembers,
                      color: Colors.grey,
                    ),
                    const Divider(height: AppSpacing.xxl),
                    Text(
                      l10n.memberType,
                      style: txt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.lg,
                      runSpacing: AppSpacing.sm,
                      children: [
                        for (final entry in typeCounts.entries)
                          Chip(
                            avatar: const Icon(Icons.badge_outlined, size: 16),
                            label: Text('${entry.key}: ${entry.value}'),
                          ),
                      ],
                    ),
                    const Divider(height: AppSpacing.xxl),
                    Text(
                      l10n.memberStatus,
                      style: txt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Wrap(
                      spacing: AppSpacing.lg,
                      runSpacing: AppSpacing.sm,
                      children: [
                        Chip(
                          avatar: const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 16,
                          ),
                          label: Text('${l10n.statusActive}: $activeMembers'),
                        ),
                        Chip(
                          avatar: const Icon(
                            Icons.timer_off,
                            color: Colors.orange,
                            size: 16,
                          ),
                          label: Text('${l10n.statusExpired}: $expiredMembers'),
                        ),
                        Chip(
                          avatar: const Icon(
                            Icons.block,
                            color: Colors.red,
                            size: 16,
                          ),
                          label: Text(
                            '${l10n.statusSuspended}: $suspendedMembers',
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxxl),

            // Circulation Performance Section
            Text(
              l10n.circulationStats,
              style: txt.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.md),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            title: l10n.onTimeReturnRate,
                            value: '$onTimeRate %',
                            color: Colors.green,
                            icon: Icons.check_circle_outline,
                          ),
                        ),
                        Expanded(
                          child: _MetricTile(
                            title: l10n.statOverdue,
                            value: '$overdueRate %',
                            color: Colors.red,
                            icon: Icons.warning_amber_outlined,
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: AppSpacing.xl),
                    Row(
                      children: [
                        Expanded(
                          child: _MetricTile(
                            title: l10n.statBorrowed7d,
                            value: provider.weekBorrowCount.toString(),
                            color: Colors.blue,
                            icon: Icons.trending_up,
                          ),
                        ),
                        Expanded(
                          child: _MetricTile(
                            title: l10n.statReturned7d,
                            value: provider.weekReturnCount.toString(),
                            color: Colors.teal,
                            icon: Icons.trending_down,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.xxxl),

            // Top Borrowed & Dead Stock Section
            LayoutBuilder(
              builder: (context, constraints) {
                final isWide = constraints.maxWidth > 800;
                return Flex(
                  direction: isWide ? Axis.horizontal : Axis.vertical,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Top Borrowed Books
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.topBorrowedBooks,
                            style: txt.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Card(
                            child: sortedTopItems.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(
                                      AppSpacing.xl,
                                    ),
                                    child: Text(
                                      l10n.noActiveLoans,
                                      style: TextStyle(
                                        color: scheme.onSurfaceVariant,
                                      ),
                                    ),
                                  )
                                : ListView.separated(
                                    shrinkWrap: true,
                                    physics:
                                        const NeverScrollableScrollPhysics(),
                                    itemCount: sortedTopItems.take(5).length,
                                    separatorBuilder: (_, index) =>
                                        const Divider(height: 1),
                                    itemBuilder: (context, idx) {
                                      final item = sortedTopItems[idx];
                                      return ListTile(
                                        leading: CircleAvatar(
                                          child: Text('${idx + 1}'),
                                        ),
                                        title: Text(item.key),
                                        trailing: Badge(
                                          label: Text('${item.value}'),
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ],
                      ),
                    ),
                    if (isWide) const SizedBox(width: AppSpacing.xl),
                    if (!isWide) const SizedBox(height: AppSpacing.xxxl),

                    // Zero Circulation (Dead Stock)
                    Expanded(
                      flex: isWide ? 1 : 0,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.deadStockBooks,
                            style: txt.titleLarge?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(AppSpacing.xl),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${zeroCirculationItems.length} / ${provider.items.length} titles currently unborrowed',
                                    style: txt.bodyLarge?.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.sm),
                                  Text(
                                    'Catalog titles that have not been loaned out recently. Helpful for collection weeding and inventory rebalancing.',
                                    style: txt.bodyMedium?.copyWith(
                                      color: scheme.onSurfaceVariant,
                                    ),
                                  ),
                                  const SizedBox(height: AppSpacing.md),
                                  Wrap(
                                    spacing: AppSpacing.sm,
                                    children: [
                                      for (final item
                                          in zeroCirculationItems.take(6))
                                        Chip(
                                          label: Text(
                                            item.designation,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: AppSpacing.xxxl),

            // Financial Summary Section (Staff / Admin)
            if (provider.canWrite) ...[
              Text(
                l10n.financialOverview,
                style: txt.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: AppSpacing.md),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xl),
                  child: Row(
                    children: [
                      Expanded(
                        child: _MetricTile(
                          title: l10n.finesCollected,
                          value: '${finesTotalPaid.toStringAsFixed(0)} DZD',
                          color: Colors.green,
                          icon: Icons.payments_outlined,
                        ),
                      ),
                      Expanded(
                        child: _MetricTile(
                          title: l10n.finesOutstanding,
                          value:
                              '${finesTotalOutstanding.toStringAsFixed(0)} DZD',
                          color: Colors.red,
                          icon: Icons.pending_actions_outlined,
                        ),
                      ),
                      Expanded(
                        child: _MetricTile(
                          title: l10n.inventoryValue,
                          value:
                              '${provider.totalValue.toStringAsFixed(0)} DZD',
                          color: Colors.indigo,
                          icon: Icons.account_balance_wallet_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DemographicBar extends StatelessWidget {
  const _DemographicBar({
    required this.label,
    required this.count,
    required this.total,
    required this.color,
  });

  final String label;
  final int count;
  final int total;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final pct = total > 0 ? (count / total) : 0.0;
    final pctStr = (pct * 100).toStringAsFixed(1);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('$count ($pctStr %)'),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(
          value: pct,
          color: color,
          backgroundColor: color.withValues(alpha: 0.15),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.title,
    required this.value,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: color, size: 28),
        const SizedBox(height: 6),
        Text(
          value,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          title,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }
}
