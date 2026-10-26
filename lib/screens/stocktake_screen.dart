import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../ui/app_tokens.dart';
import '../widgets/app_toast.dart';
import '../widgets/barcode_scanner_dialog.dart';

/// Shelf Stocktaking & Physical Inventory Audit Screen.
/// Enables librarians to rapidly scan items on shelves, verifying physical
/// presence, detecting misplaced titles, and identifying missing inventory.
class StocktakeScreen extends StatefulWidget {
  const StocktakeScreen({super.key});

  @override
  State<StocktakeScreen> createState() => _StocktakeScreenState();
}

class _StocktakeScreenState extends State<StocktakeScreen> {
  final Set<String> _scannedBarcodes = <String>{};
  final List<_AuditRecord> _scannedRecords = <_AuditRecord>[];
  final TextEditingController _manualInputCtrl = TextEditingController();

  @override
  void dispose() {
    _manualInputCtrl.dispose();
    super.dispose();
  }

  void _processScannedCode(String rawCode) {
    final code = rawCode.trim();
    if (code.isEmpty) return;
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context, listen: false);

    if (_scannedBarcodes.contains(code)) {
      showAppToast(
        context,
        'Barcode already scanned: $code',
        kind: ToastKind.warning,
      );
      return;
    }

    // Match item by barcode or code
    final item = provider.items
        .where((i) => i.code == code || i.barcode == code || i.fullCode == code)
        .firstOrNull;

    setState(() {
      _scannedBarcodes.add(code);
      if (item != null) {
        _scannedRecords.insert(
          0,
          _AuditRecord(
            barcode: code,
            title: item.designation,
            location: item.emplacement,
            status: _AuditStatus.matched,
            scannedAt: DateTime.now(),
          ),
        );
        showAppToast(
          context,
          '${item.designation} (${l10n.statusAvailable})',
          kind: ToastKind.success,
        );
      } else {
        _scannedRecords.insert(
          0,
          _AuditRecord(
            barcode: code,
            title: l10n.itemNotFound,
            location: '-',
            status: _AuditStatus.unknown,
            scannedAt: DateTime.now(),
          ),
        );
        showAppToast(
          context,
          'Uncataloged barcode: $code',
          kind: ToastKind.warning,
        );
      }
    });
  }

  Future<void> _openScanner() async {
    final code = await showBarcodeScanner(context);
    if (code != null && mounted) {
      _processScannedCode(code);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    final scannedCount = _scannedBarcodes.length;
    final matchedCount = _scannedRecords
        .where((r) => r.status == _AuditStatus.matched)
        .length;
    final unknownCount = _scannedRecords
        .where((r) => r.status == _AuditStatus.unknown)
        .length;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.stocktaking),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            tooltip: l10n.scanBarcode,
            onPressed: _openScanner,
          ),
          IconButton(
            icon: const Icon(Icons.clear_all),
            tooltip: l10n.cancel,
            onPressed: _scannedRecords.isEmpty
                ? null
                : () {
                    setState(() {
                      _scannedBarcodes.clear();
                      _scannedRecords.clear();
                    });
                  },
          ),
        ],
      ),
      body: Padding(
        padding: AppSpacing.allXxl,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Headline progress cards
            Row(
              children: [
                Expanded(
                  child: Card(
                    color: scheme.primaryContainer.withValues(alpha: 0.5),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          Text(
                            '$scannedCount',
                            style: txt.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(l10n.itemsScanned),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Card(
                    color: Colors.green.withValues(alpha: 0.15),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          Text(
                            '$matchedCount',
                            style: txt.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.green,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(l10n.statusAvailable),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Card(
                    color: Colors.orange.withValues(alpha: 0.15),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: Column(
                        children: [
                          Text(
                            '$unknownCount',
                            style: txt.headlineMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Colors.orange,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(l10n.itemsMissing),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Barcode Entry Row
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _manualInputCtrl,
                    textDirection: TextDirection.ltr,
                    decoration: InputDecoration(
                      hintText: l10n.scanShelfPrompt,
                      prefixIcon: const Icon(Icons.view_week_outlined),
                      suffixIcon: IconButton(
                        icon: const Icon(Icons.qr_code_scanner),
                        onPressed: _openScanner,
                      ),
                    ),
                    onSubmitted: (val) {
                      _processScannedCode(val);
                      _manualInputCtrl.clear();
                    },
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                FilledButton.icon(
                  onPressed: () {
                    _processScannedCode(_manualInputCtrl.text);
                    _manualInputCtrl.clear();
                  },
                  icon: const Icon(Icons.check),
                  label: Text(l10n.scanBarcode),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),

            // Scanned List View
            Text(
              '${l10n.itemsScanned} (${_scannedRecords.length})',
              style: txt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: AppSpacing.sm),
            Expanded(
              child: _scannedRecords.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inventory_2_outlined,
                            size: 64,
                            color: scheme.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            l10n.scanShelfPrompt,
                            style: txt.bodyLarge?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : Card(
                      child: ListView.separated(
                        itemCount: _scannedRecords.length,
                        separatorBuilder: (_, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, idx) {
                          final record = _scannedRecords[idx];
                          final isMatched =
                              record.status == _AuditStatus.matched;
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: isMatched
                                  ? Colors.green.withValues(alpha: 0.2)
                                  : Colors.orange.withValues(alpha: 0.2),
                              foregroundColor: isMatched
                                  ? Colors.green
                                  : Colors.orange,
                              child: Icon(
                                isMatched ? Icons.check : Icons.help_outline,
                                size: AppIcon.md,
                              ),
                            ),
                            title: Text(record.title),
                            subtitle: Text(
                              '${l10n.barcode}: ${record.barcode} | ${l10n.location}: ${record.location}',
                            ),
                            trailing: Text(
                              '${record.scannedAt.hour.toString().padLeft(2, '0')}:'
                              '${record.scannedAt.minute.toString().padLeft(2, '0')}:'
                              '${record.scannedAt.second.toString().padLeft(2, '0')}',
                              style: txt.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _AuditStatus { matched, unknown }

class _AuditRecord {
  final String barcode;
  final String title;
  final String location;
  final _AuditStatus status;
  final DateTime scannedAt;

  const _AuditRecord({
    required this.barcode,
    required this.title,
    required this.location,
    required this.status,
    required this.scannedAt,
  });
}
