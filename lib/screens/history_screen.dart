import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../ui/app_tokens.dart';
import '../utils/display_safety.dart';
import '../widgets/app_states.dart';
import '../widgets/app_status_chip.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.initialSubject});

  /// Optional subject string that pre-filters the audit list to rows whose
  /// `details` mention it (used by the "See all history" links on Item Detail
  /// and Member Detail). Null keeps the pre-Pass-5 unfiltered behaviour.
  final String? initialSubject;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _operationFilter;
  late final TextEditingController _subjectController;
  String? _subjectFilter;
  int _subjectDebounceToken = 0;

  @override
  void initState() {
    super.initState();
    _subjectFilter = widget.initialSubject;
    _subjectController = TextEditingController(
      text: widget.initialSubject ?? '',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<LibraryProvider>(
        context,
        listen: false,
      ).loadHistory(subject: _subjectFilter);
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _subjectController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      Provider.of<LibraryProvider>(
        context,
        listen: false,
      ).loadHistory(more: true, subject: _subjectFilter);
    }
  }

  /// Debounced subject change. 300 ms keeps typing smooth without a repo call
  /// per keystroke; the token cancels any pending reload that a newer keystroke
  /// supersedes.
  void _onSubjectChanged(String value) {
    final trimmed = value.trim().isEmpty ? null : value.trim();
    setState(() => _subjectFilter = trimmed);
    final token = ++_subjectDebounceToken;
    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted || token != _subjectDebounceToken) return;
      Provider.of<LibraryProvider>(
        context,
        listen: false,
      ).loadHistory(subject: _subjectFilter);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    final filteredHistory = _operationFilter == null
        ? provider.history
        : provider.history
              .where((e) => e['operation'] == _operationFilter)
              .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          DropdownButton<String?>(
            value: _operationFilter,
            hint: Text(l10n.filter),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.all)),
              DropdownMenuItem(value: 'ADD', child: Text(l10n.operationAdd)),
              DropdownMenuItem(
                value: 'UPDATE',
                child: Text(l10n.operationUpdate),
              ),
              DropdownMenuItem(
                value: 'DELETE',
                child: Text(l10n.operationDelete),
              ),
              DropdownMenuItem(value: 'WIPE', child: Text(l10n.operationWipe)),
            ],
            onChanged: (val) {
              setState(() {
                _operationFilter = val;
              });
            },
          ),
          const SizedBox(width: AppSpacing.lg),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: TextField(
              controller: _subjectController,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.filter_alt_outlined),
                hintText: l10n.historySubjectPlaceholder,
                border: const OutlineInputBorder(),
                suffixIcon: _subjectFilter == null
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.clear),
                        tooltip: l10n.clearFilters,
                        onPressed: () {
                          _subjectController.clear();
                          _onSubjectChanged('');
                        },
                      ),
              ),
              onChanged: _onSubjectChanged,
            ),
          ),
          Expanded(
            child: filteredHistory.isEmpty && !provider.isLoading
                ? AppEmptyState(
                    icon: Icons.history,
                    title: l10n.noHistoryFound,
                    compact: true,
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount:
                        filteredHistory.length +
                        (provider.hasMoreHistory ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == filteredHistory.length) {
                        return const Padding(
                          padding: EdgeInsets.all(AppSpacing.xxl),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }

                      final entry = filteredHistory[index];
                      // FE2-08: a stored history row's shape is not fully
                      // trusted (legacy / restored / pre-P9-9.7 forged), so
                      // parse and render every field defensively -- one bad
                      // row must degrade, not blank the whole screen.
                      final dateTime = tryParseTimestamp(entry['timestamp']);
                      final dateStr = dateTime == null
                          ? '\u2014'
                          : DateFormat('dd/MM/yyyy HH:mm:ss').format(dateTime);
                      final op = safeText(entry['operation'], fallback: '');

                      return Card(
                        margin: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                          vertical: AppSpacing.xs,
                        ),
                        child: ListTile(
                          leading: _getOperationIcon(op),
                          title: Text(safeText(entry['details'])),
                          subtitle: Text(
                            '$dateStr \u2022 ${l10n.by}: ${safeText(entry['user'])}',
                          ),
                          trailing: AppStatusChip(
                            label: _getOperationLabel(op, l10n),
                            color: _getOperationColor(op),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _getOperationLabel(String op, AppLocalizations l10n) {
    switch (op) {
      case 'ADD':
        return l10n.operationAdd;
      case 'UPDATE':
        return l10n.operationUpdate;
      case 'DELETE':
        return l10n.operationDelete;
      case 'WIPE':
        return l10n.operationWipe;
      default:
        return op;
    }
  }

  // Audit verbs map onto the central status palette (add = success green,
  // update = info blue, delete = danger red, wipe = warning amber).
  Icon _getOperationIcon(String op) {
    switch (op) {
      case 'ADD':
        return const Icon(
          Icons.add_circle_outline,
          color: AppStatus.success,
          size: AppIcon.lg,
        );
      case 'UPDATE':
        return const Icon(
          Icons.edit_outlined,
          color: AppStatus.info,
          size: AppIcon.lg,
        );
      case 'DELETE':
        return const Icon(
          Icons.delete_outline,
          color: AppStatus.danger,
          size: AppIcon.lg,
        );
      case 'WIPE':
        return const Icon(
          Icons.warning_amber_rounded,
          color: AppStatus.warning,
          size: AppIcon.lg,
        );
      default:
        return const Icon(Icons.history, size: AppIcon.lg);
    }
  }

  Color _getOperationColor(String op) {
    switch (op) {
      case 'ADD':
        return AppStatus.success;
      case 'UPDATE':
        return AppStatus.info;
      case 'DELETE':
        return AppStatus.danger;
      case 'WIPE':
        return AppStatus.warning;
      default:
        return AppStatus.neutral;
    }
  }
}
