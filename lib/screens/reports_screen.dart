import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../domain/report_query.dart';
import '../l10n/app_localizations.dart';
import '../models/report.dart';
import '../providers/library_provider.dart';
import '../services/api_service.dart' show ApiException;
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';
import '../utils/app_date.dart';
import '../widgets/app_states.dart';

/// Reports / management summaries (Phase 10.4b) -- the read-only analytics
/// surface over the 10.4a engine.
///
/// Phase I (frontend reconstruction): presentation-only rebuild. The indigo
/// AppBar the shell already titles (double header) is gone, raw grey/indigo
/// values read through the theme, and the pre-run / no-data conditions use the
/// shared state components. The verbatim server-authored rendering below is
/// unchanged.
///
/// Like every Phase 10 surface this screen is deliberately THIN. It never
/// computes a figure, filters a row, or formats a number itself: it asks
/// [LibraryProvider] for a [Report] (host SQLite engine or LAN-client HTTP) and
/// renders the server-authored columns / rows / summary verbatim, so the
/// on-screen table and an exported CSV/PDF can never disagree -- both come from
/// the SAME [Report]. Reports expose patron and financial data, so the whole
/// surface is staff-gated (the client-side twin of the server's `staff` route
/// guard); a read-only (viewer) session is offered no surface at all.
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  ReportKind _kind = ReportKind.circulation;
  final TextEditingController _from = TextEditingController();
  final TextEditingController _to = TextEditingController();
  Report? _report;
  bool _busy = false;

  @override
  void dispose() {
    _from.dispose();
    _to.dispose();
    super.dispose();
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: error ? Theme.of(context).colorScheme.error : null,
      ),
    );
  }

  /// Runs the report on the host. A windowed kind validates its dates with the
  /// SAME strict parser the server route uses (a malformed day is caught before
  /// any request), but the server stays the authority -- a refusal / bad window
  /// comes back as an error and is surfaced verbatim, never pretended applied.
  Future<void> _run() async {
    if (_busy) return;
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final from = _from.text.trim();
    final to = _to.text.trim();
    if (ReportQuery.usesWindow(_kind)) {
      try {
        ReportQuery.parseDay(from.isEmpty ? null : from);
        ReportQuery.parseDay(to.isEmpty ? null : to);
      } on FormatException {
        _showSnack(l10n.reportInvalidDates, error: true);
        return;
      }
    }
    setState(() => _busy = true);
    try {
      final report = await provider.generateReport(
        _kind,
        from: from.isEmpty ? null : from,
        to: to.isEmpty ? null : to,
      );
      if (!mounted) return;
      setState(() => _report = report);
    } catch (e) {
      if (mounted) {
        _showSnack(_reportMessage(l10n, e, l10n.reportFailed), error: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Exports the CURRENT server-authored report. Nothing is re-derived: the
  /// bytes are rendered from the same [Report] the table is showing.
  Future<void> _export({required bool pdf}) async {
    if (_busy || _report == null) return;
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final report = _report!;
    setState(() => _busy = true);
    try {
      // ARC-07 (P22): the export document's chrome labels are localized here
      // (a BuildContext is available); the report DATA still comes from the
      // same server-authored [Report], so host/client tables and the exported
      // file cannot disagree.
      final labels = {
        'from': l10n.reportFrom,
        'to': l10n.reportTo,
        'generated': l10n.reportGeneratedLabel,
        'period': l10n.reportPeriodLabel,
        'noRecords': l10n.reportNoData,
      };
      final path = pdf
          ? await provider.exportReportPdf(report, labels: labels)
          : await provider.exportReportCsv(report, labels: labels);
      // A null path means the user cancelled the save dialog: nothing was
      // written, so report no success (and no error).
      if (path != null && mounted) _showSnack(l10n.reportSaved(path));
    } catch (e) {
      if (mounted) {
        _showSnack(
          _reportMessage(l10n, e, l10n.reportExportFailed),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _kindLabel(AppLocalizations l10n, ReportKind k) => switch (k) {
    ReportKind.circulation => l10n.reportKindCirculation,
    ReportKind.overdue => l10n.reportKindOverdue,
    ReportKind.inventory => l10n.reportKindInventory,
    ReportKind.fines => l10n.reportKindFines,
    ReportKind.members => l10n.reportKindMembers,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    if (!provider.canWrite) {
      // The shell already shows the section title + the read-only banner; this
      // surface just says honestly that reports are staff-gated.
      return Scaffold(
        body: AppEmptyState(
          icon: Icons.lock_outline,
          title: l10n.onlyStaffRunReports,
          compact: true,
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          _controls(l10n),
          const Divider(height: 1),
          Expanded(child: _body(l10n)),
        ],
      ),
    );
  }

  Widget _controls(AppLocalizations l10n) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final windowed = ReportQuery.usesWindow(_kind);
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ReportKind>(
                  key: const Key('reportKindField'),
                  initialValue: _kind,
                  decoration: InputDecoration(labelText: l10n.reportSelectKind),
                  items: [
                    for (final k in ReportKind.values)
                      DropdownMenuItem(
                        value: k,
                        child: Text(_kindLabel(l10n, k)),
                      ),
                  ],
                  onChanged: _busy
                      ? null
                      : (v) {
                          if (v == null) return;
                          setState(() {
                            _kind = v;
                            // A windowless kind has no use for the dates.
                            if (!ReportQuery.usesWindow(v)) {
                              _from.clear();
                              _to.clear();
                            }
                          });
                        },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              FilledButton.icon(
                key: const Key('reportRunButton'),
                onPressed: _busy ? null : _run,
                icon: _busy
                    ? const SizedBox(
                        width: AppIcon.sm,
                        height: AppIcon.sm,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.play_arrow),
                label: Text(l10n.reportRun),
              ),
            ],
          ),
          if (windowed) ...[
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _dateField(
                    l10n,
                    _from,
                    'reportFromField',
                    l10n.reportFrom,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: _dateField(l10n, _to, 'reportToField', l10n.reportTo),
                ),
              ],
            ),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Padding(
                padding: const EdgeInsetsDirectional.only(top: AppSpacing.sm),
                child: Text(
                  l10n.reportWindowNote,
                  style: txt.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dateField(
    AppLocalizations l10n,
    TextEditingController controller,
    String key,
    String label,
  ) {
    return TextField(
      key: Key(key),
      controller: controller,
      enabled: !_busy,
      decoration: InputDecoration(
        labelText: label,
        hintText: l10n.reportDateHint,
      ),
    );
  }

  Widget _body(AppLocalizations l10n) {
    final report = _report;
    if (report == null) {
      return AppEmptyState(
        icon: Icons.insert_chart_outlined,
        title: l10n.reportRun,
        compact: true,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _summaryBar(l10n, report),
        Expanded(child: _table(l10n, report)),
      ],
    );
  }

  Widget _summaryBar(AppLocalizations l10n, Report report) {
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;
    final period = report.from != null || report.to != null
        ? '${report.from ?? '—'} → ${report.to ?? '—'}'
        : null;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        start: AppSpacing.lg,
        top: AppSpacing.sm,
        end: AppSpacing.lg,
        bottom: AppSpacing.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _kindLabel(l10n, report.kind),
                  style: txt.titleSmall?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                // The engine stores `generated_at` as an ISO-8601 string.
                // Rendering it verbatim leaked the `T` separator and
                // microsecond tail into the operator's report header
                // ("Generated 2026-09-29T23:30:35.331300"). Route it through
                // AppDate so it reads "Generated 2026-09-29 23:30", and fall
                // back to the raw string if the value is not parseable
                // (defensive against hand-edited or legacy rows).
                l10n.reportGeneratedAt(
                  AppDate.tryParse(report.generatedAt) != null
                      ? AppDate.dateTime(report.generatedAt)
                      : report.generatedAt,
                ),
                style: txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                key: const Key('reportExportCsv'),
                onPressed: _busy ? null : () => _export(pdf: false),
                icon: const Icon(Icons.table_chart, size: AppIcon.sm),
                label: Text(l10n.reportExportCsv),
              ),
              const SizedBox(width: AppSpacing.sm),
              OutlinedButton.icon(
                key: const Key('reportExportPdf'),
                onPressed: _busy ? null : () => _export(pdf: true),
                icon: const Icon(Icons.picture_as_pdf, size: AppIcon.sm),
                label: Text(l10n.reportExportPdf),
              ),
            ],
          ),
          if (period != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: AppSpacing.xs),
              child: Text(
                period,
                style: txt.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          if (report.summary.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final e in report.summary.entries)
                  Chip(
                    label: Text('${e.key}: ${e.value}'),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _table(AppLocalizations l10n, Report report) {
    if (report.rows.isEmpty) {
      return AppEmptyState(
        icon: Icons.query_stats_outlined,
        title: l10n.reportNoData,
        compact: true,
      );
    }
    final txt = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.lg,
          vertical: AppSpacing.xs,
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DataTable(
            headingRowColor: WidgetStateProperty.all(scheme.surfaceContainer),
            columns: [
              for (final c in report.columns)
                DataColumn(
                  label: Text(
                    c,
                    style: txt.titleSmall?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
            rows: [
              for (final row in report.rows)
                DataRow(cells: [for (final cell in row) DataCell(Text(cell))]),
            ],
          ),
        ),
      ),
    );
  }
}

/// Surfaces the concrete server/host refusal (a bad or reversed window -> 400,
/// a forbidden role -> 403) verbatim where it carries no secret, otherwise a
/// categorized message. [fallback] prefixes the reason for readability.
String _reportMessage(AppLocalizations l10n, Object e, String fallback) {
  if (e is StateError) return '$fallback\n${e.message}';
  if (e is ApiException &&
      (e.error == 'bad_request' || e.error == 'conflict') &&
      e.message.trim().isNotEmpty) {
    return '$fallback\n${e.message}';
  }
  return describeError(l10n, e);
}
