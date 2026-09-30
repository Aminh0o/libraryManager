import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../services/error_messages.dart';
import '../models/library_item.dart';
import '../models/member.dart';
import '../models/loan.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_states.dart';
import '../widgets/app_status_chip.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../l10n/app_localizations.dart';

/// Phase H (frontend reconstruction): presentation-only rebuild. The orange
/// AppBar + white tab labels are gone (the shell already titles the tab, so
/// only the segmented [TabBar] remains), the hand-picked green/red/orange
/// button overrides now come from the theme, and the overdue row/chip read
/// through the semantic palette in BOTH brightness modes. Tab navigation, the
/// bulk-checkout member retention and every provider call are unchanged.
class LoanScreen extends StatefulWidget {
  const LoanScreen({super.key});

  @override
  State<LoanScreen> createState() => _LoanScreenState();
}

class _LoanScreenState extends State<LoanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Checkout State
  Member? _selectedMember;
  LibraryItem? _selectedItem;
  final TextEditingController _memberSearchCtrl = TextEditingController();
  final TextEditingController _itemSearchCtrl = TextEditingController();

  // Checkin State
  final TextEditingController _checkinSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    // The Return tab's "Confirm Return" button previously stayed enabled on
    // an empty code field and silently no-opped, so a librarian believed a
    // book had been checked in when nothing had been written. Listening to
    // the controller lets the button's `onPressed` recompute and disable
    // itself, mirroring the sibling "Validate Loan" pattern that already
    // works correctly on the New Loan tab.
    _checkinSearchCtrl.addListener(_onCheckinChanged);
  }

  void _onCheckinChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _checkinSearchCtrl.removeListener(_onCheckinChanged);
    _tabController.dispose();
    _memberSearchCtrl.dispose();
    _itemSearchCtrl.dispose();
    _checkinSearchCtrl.dispose();
    super.dispose();
  }

  void _scanItemForCheckout() async {
    final code = await showBarcodeScanner(context);
    if (code != null && mounted) {
      final provider = Provider.of<LibraryProvider>(context, listen: false);
      // Try to find by barcode or code
      final item = provider.items.firstWhere(
        (i) => i.code == code || i.barcode == code || i.fullCode == code,
        orElse: () => LibraryItem(
          code: '',
          codeType: '',
          designation: '',
          quantite: 0,
          emplacement: '',
          taux: 0,
          emplacementStock: '',
          status: '',
        ),
      );

      if (item.code.isNotEmpty) {
        setState(() {
          _selectedItem = item;
          _itemSearchCtrl.text = item.designation;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.itemNotFound)),
        );
      }
    }
  }

  void _processCheckout() async {
    if (_selectedMember == null || _selectedItem == null) return;

    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    try {
      await provider.checkOutItem(_selectedItem!, _selectedMember!);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.loanSuccess)));
        setState(() {
          _selectedItem = null;
          _itemSearchCtrl.clear();
          // Keep member selected for bulk checkout
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeError(l10n, e))));
      }
    }
  }

  void _processCheckin() async {
    final code = _checkinSearchCtrl.text;
    if (code.isEmpty) return;

    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    try {
      await provider.returnItem(
        code,
      ); // Logic needs to handle barcode lookup inside provider potentially
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.returnSuccess)));
        _checkinSearchCtrl.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeError(l10n, e))));
      }
    }
  }

  // FE2-15: renewal. `provider.renewLoan` funnels through the canonical
  // LoanTransitions.renew (which throws on a non-active loan, BL-02), and the
  // result is awaited + confirmed exactly like checkout/return -- never a
  // fire-and-forget. Errors go through the shared FE2-12 classifier.
  Future<void> _renew(Loan loan) async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    try {
      await provider.renewLoan(loan);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.renewSuccess)));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeError(l10n, e))));
      }
    }
  }

  static String _fmtDate(DateTime d) {
    final local = d.toLocal();
    final y = local.year.toString().padLeft(4, '0');
    final m = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: TabBar(
              controller: _tabController,
              tabs: [
                Tab(text: l10n.newLoan),
                Tab(text: l10n.returnLoan),
                Tab(text: l10n.activeLoans),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildCheckoutTab(context),
                _buildCheckinTab(context),
                _buildActiveLoansTab(context),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckoutTab(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizing.maxFormWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Select Member
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.selectMember, style: txt.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      if (_selectedMember != null)
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            backgroundColor: scheme.primaryContainer,
                            foregroundColor: scheme.onPrimaryContainer,
                            child: const Icon(Icons.person, size: AppIcon.md),
                          ),
                          title: Text(_selectedMember!.fullName),
                          subtitle: Text(_selectedMember!.memberId),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () =>
                                setState(() => _selectedMember = null),
                          ),
                        )
                      else
                        Autocomplete<Member>(
                          displayStringForOption: (Member option) =>
                              option.fullName,
                          optionsBuilder: (TextEditingValue textEditingValue) {
                            if (textEditingValue.text == '') {
                              return const Iterable<Member>.empty();
                            }
                            return provider.members.where((Member option) {
                              return option.fullName.toLowerCase().contains(
                                    textEditingValue.text.toLowerCase(),
                                  ) ||
                                  option.memberId.contains(
                                    textEditingValue.text,
                                  );
                            });
                          },
                          onSelected: (Member selection) {
                            setState(() => _selectedMember = selection);
                          },
                          fieldViewBuilder:
                              (
                                context,
                                fieldTextEditingController,
                                focusNode,
                                onFieldSubmitted,
                              ) {
                                return TextField(
                                  controller: fieldTextEditingController,
                                  focusNode: focusNode,
                                  decoration: InputDecoration(
                                    labelText: l10n.memberSearchHint,
                                    prefixIcon: const Icon(Icons.search),
                                  ),
                                );
                              },
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              // 2. Select Item
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.selectItem, style: txt.titleMedium),
                      const SizedBox(height: AppSpacing.sm),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _itemSearchCtrl,
                              decoration: InputDecoration(
                                labelText: l10n.itemSearchHint,
                              ),
                              readOnly:
                                  true, // Force use of scanner for now or implement autocomplete
                              onTap: _scanItemForCheckout,
                            ),
                          ),
                          IconButton(
                            tooltip: l10n.scanBarcode,
                            icon: Icon(
                              Icons.camera_alt,
                              size: AppIcon.xl,
                              color: scheme.primary,
                            ),
                            onPressed: _scanItemForCheckout,
                          ),
                        ],
                      ),
                      if (_selectedItem != null)
                        Padding(
                          padding: const EdgeInsets.only(top: AppSpacing.sm),
                          child: Text(
                            l10n.selectedItemLabel(
                              _selectedItem!.designation,
                              _selectedItem!.status,
                            ),
                            style: txt.bodyMedium?.copyWith(
                              color:
                                  _selectedItem!.status == ItemStatus.disponible
                                  ? AppStatus.success
                                  : AppStatus.danger,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const Spacer(),
              FilledButton.icon(
                onPressed:
                    (_selectedMember != null &&
                        _selectedItem != null &&
                        _selectedItem!.status == ItemStatus.disponible)
                    ? _processCheckout
                    : null,
                icon: const Icon(Icons.check),
                label: Text(l10n.validateLoan),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCheckinTab(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: AppSizing.maxFormWidth),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              Icon(
                Icons.assignment_return,
                size: AppIcon.hero,
                color: scheme.primary,
              ),
              const SizedBox(height: AppSpacing.lg),
              Text(
                l10n.scanToReturn,
                style: txt.titleMedium?.copyWith(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: AppSpacing.xxl),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _checkinSearchCtrl,
                      decoration: InputDecoration(labelText: l10n.code),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  IconButton(
                    tooltip: l10n.scanBarcode,
                    icon: Icon(
                      Icons.camera_alt,
                      size: AppIcon.xl,
                      color: scheme.primary,
                    ),
                    onPressed: () async {
                      final code = await showBarcodeScanner(context);
                      if (code != null) {
                        setState(() => _checkinSearchCtrl.text = code);
                        _processCheckin(); // Auto submit
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.lg),
              FilledButton(
                // Disabled whenever the code field is empty so a mis-tap
                // cannot masquerade as a successful return. The action
                // remains the same (`_processCheckin`) but the button now
                // visibly greys out and refuses input when there is nothing
                // to submit.
                onPressed: _checkinSearchCtrl.text.trim().isEmpty
                    ? null
                    : _processCheckin,
                child: Text(l10n.confirmReturn),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // FE2-15: the circulation desk could previously neither SEE who had what nor
  // renew anything -- `activeLoans` / `isOverdue` / `renewLoan` all existed in
  // the provider but had zero UI. This tab lists every active loan, flags the
  // overdue ones, and offers a per-row Renew action.
  Widget _buildActiveLoansTab(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final loans = provider.activeLoans;
    if (loans.isEmpty) {
      // The pinned FE2-15 key marks the whole empty composition.
      return KeyedSubtree(
        key: const Key('noActiveLoans'),
        child: AppEmptyState(
          icon: Icons.inventory_2_outlined,
          title: l10n.noActiveLoans,
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: DataTable(
        headingRowHeight: AppSizing.topBarHeight - 16,
        columns: [
          for (final label in [
            l10n.colMember,
            l10n.colItem,
            l10n.loanDateCol,
            l10n.dueDateCol,
            l10n.status,
            l10n.renew,
          ])
            DataColumn(
              label: Text(
                label,
                style: txt.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.onSurface,
                ),
              ),
            ),
        ],
        rows: [
          for (final loan in loans)
            DataRow(
              // Overdue reads through the semantic error container, so it is
              // a tint in BOTH modes (was Colors.red[50]: white-on-dark dead).
              color: WidgetStatePropertyAll<Color?>(
                loan.isOverdue
                    ? scheme.errorContainer.withValues(alpha: 0.45)
                    : null,
              ),
              cells: [
                DataCell(Text(loan.memberName)),
                DataCell(Text('${loan.itemTitle} (${loan.itemCode})')),
                DataCell(Text(_fmtDate(loan.loanDate))),
                DataCell(Text(_fmtDate(loan.dueDate))),
                DataCell(
                  loan.isOverdue
                      ? AppStatusChip(
                          label: l10n.overdue,
                          color: AppStatus.danger,
                        )
                      // Not-overdue needs no alarm chip: a quiet check says it.
                      : Icon(
                          Icons.check_circle,
                          size: AppIcon.lg,
                          color: AppStatus.success,
                        ),
                ),
                DataCell(
                  TextButton.icon(
                    key: Key('renew_${loan.id ?? loan.itemCode}'),
                    onPressed: () => _renew(loan),
                    icon: const Icon(Icons.refresh, size: AppIcon.md),
                    label: Text(l10n.renew),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}
