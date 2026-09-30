import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/library_item.dart';
import '../providers/library_provider.dart';
import '../services/error_messages.dart';
import '../ui/app_tokens.dart';
import '../widgets/barcode_scanner_dialog.dart';

/// Phase L (frontend reconstruction): the item form moved onto the design
/// system -- themed AppBar, token spacing, the shared filled-field theme (no
/// per-field OutlineInputBorder overrides), localized validation copy (the
/// FE2-09 number validators keep their exact behavior, the messages simply
/// come from l10n now) and a scheme-colored error snackbar. Every save
/// semantic (FE2-01/02 awaited write, TX-06 optimistic version + conflict
/// reconciliation, FE2-09 validation) is byte-for-byte the same logic.
class ItemFormScreen extends StatefulWidget {
  final LibraryItem? item;

  const ItemFormScreen({super.key, this.item});

  @override
  State<ItemFormScreen> createState() => _ItemFormScreenState();
}

class _ItemFormScreenState extends State<ItemFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _codeController;
  late TextEditingController _barcodeController;
  late TextEditingController _designationController;
  late TextEditingController _quantiteController;
  late TextEditingController _emplacementController;
  late TextEditingController _tauxController;
  late TextEditingController _emplacementStockController;
  late String _selectedStatus;
  late String _selectedCodeType;

  // FE2-01/02: guards the in-flight save so the button cannot be double-tapped
  // and the form stays open (input preserved) until the write is confirmed.
  bool _saving = false;

  // TX-06: the row_version this form READ. Sent as the optimistic-concurrency
  // token on every save so a lost race is refused (409) rather than clobbering
  // a newer row. Refreshed after a conflict so ONE retry sends the current
  // version instead of looping on the stale token.
  int _expectedVersion = 0;

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.item?.code ?? '');
    _barcodeController = TextEditingController(
      text: widget.item?.barcode ?? '',
    );
    _designationController = TextEditingController(
      text: widget.item?.designation ?? '',
    );
    _quantiteController = TextEditingController(
      text: widget.item?.quantite.toString() ?? '1',
    );
    _emplacementController = TextEditingController(
      text: widget.item?.emplacement ?? '',
    );
    _tauxController = TextEditingController(
      text: widget.item?.taux.toString() ?? '0.0',
    );
    _emplacementStockController = TextEditingController(
      text: widget.item?.emplacementStock ?? '',
    );

    // Status initialization
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    if (widget.item != null) {
      _selectedStatus = widget.item!.status;
    } else {
      _selectedStatus = provider.statuses.isNotEmpty
          ? provider.statuses.first
          : 'Disponible';
    }

    _selectedCodeType = widget.item?.codeType ?? '';
    _expectedVersion = widget.item?.rowVersion ?? 0;

    // Initial selection if adding new
    if (widget.item == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final provider = Provider.of<LibraryProvider>(context, listen: false);
        if (provider.codeDefinitions.isNotEmpty) {
          setState(() {
            _selectedCodeType = provider.codeDefinitions.first.prefix;
          });
          _autoGenerateCode();
        }
      });
    }
  }

  Future<void> _autoGenerateCode() async {
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final nextCode = await provider.generateNextCode(_selectedCodeType);
    setState(() {
      _codeController.text = nextCode;
    });
  }

  Future<void> _onBarcodeScanned(String barcode) async {
    setState(() => _barcodeController.text = barcode);

    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final existingItem = await provider.findItemByBarcode(barcode);

    if (existingItem != null && mounted) {
      // Auto-fill metadata if book found
      setState(() {
        _designationController.text = existingItem.designation;
        _tauxController.text = existingItem.taux.toString();
        _selectedCodeType = existingItem.codeType;
        _selectedStatus = existingItem.status;
        _emplacementController.text = existingItem.emplacement;
        _emplacementStockController.text = existingItem.emplacementStock;
      });
      // Still generate a NEW internal code for this specific copy
      _autoGenerateCode();
    }
  }

  @override
  void dispose() {
    _codeController.dispose();
    _barcodeController.dispose();
    _designationController.dispose();
    _quantiteController.dispose();
    _emplacementController.dispose();
    _tauxController.dispose();
    _emplacementStockController.dispose();
    super.dispose();
  }

  Future<void> _saveItem() async {
    // FE2-01/02: a save must be AWAITED and only close the form on confirmed
    // success. Previously the provider mutation was fired without awaiting and
    // the screen popped immediately, so a failed write (server conflict, network
    // error, DB rejection) was invisible and the operator's input was lost.
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    final item = LibraryItem(
      code: _codeController.text,
      barcode: _barcodeController.text.isEmpty ? null : _barcodeController.text,
      codeType: _selectedCodeType,
      designation: _designationController.text,
      quantite: int.tryParse(_quantiteController.text.trim()) ?? 0,
      emplacement: _emplacementController.text,
      taux: double.tryParse(_tauxController.text.trim()) ?? 0.0,
      emplacementStock: _emplacementStockController.text,
      status: _selectedStatus,
    );

    final provider = Provider.of<LibraryProvider>(context, listen: false);
    setState(() => _saving = true);
    try {
      if (widget.item == null) {
        await provider.addItem(item);
      } else {
        // TX-06: optimistic concurrency. Send the row_version this form READ
        // (_expectedVersion, refreshed on a conflict). If another client (or a
        // loan status change) advanced the row since, the server refuses the
        // write (409) instead of letting this save silently clobber it; the
        // catch below keeps the form open so nothing typed is lost.
        await provider.updateItem(item, expectedVersion: _expectedVersion);
      }
      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      // Keep the form open so nothing typed is lost, surface a categorized
      // (localized) failure, and re-enable Save. FE2-12: no raw exception text.
      if (!mounted) return;
      setState(() => _saving = false);
      // TX-06 conflict-recovery: an edit that collided with a newer row would
      // otherwise 409 forever on the stale token. Re-read the CURRENT stored
      // version so the operator's next Save targets it (their typed input is
      // preserved; only the concurrency token advances). This is best-effort:
      // a failed reload simply leaves the old token in place.
      if (widget.item != null) {
        await _reconcileVersion(provider);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Theme.of(context).colorScheme.error,
          content: Text(describeError(AppLocalizations.of(context)!, e)),
        ),
      );
    }
  }

  /// TX-06: after a refused (conflicted) whole-row save, re-read the CURRENT
  /// stored `row_version` for this item so the next Save carries a fresh
  /// optimistic token instead of the stale one that just lost. Reloads the
  /// catalogue (the collision means the local copy is behind) and matches on
  /// the immutable primary key. Best-effort: any failure simply leaves the
  /// previous token in place, and the operator's typed input is never touched.
  Future<void> _reconcileVersion(LibraryProvider provider) async {
    final code = widget.item!.code;
    try {
      await provider.reload();
    } catch (_) {
      return; // reload failed (e.g. still offline); keep the old token
    }
    if (!mounted) return;
    final fresh = provider.allItems.where((i) => i.code == code);
    if (fresh.isNotEmpty) {
      setState(() => _expectedVersion = fresh.first.rowVersion);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);
    final isEditing = widget.item != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? l10n.editItem : l10n.addItem)),
      body: Padding(
        padding: AppSpacing.allXxl,
        child: Form(
          key: _formKey,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(
                maxWidth: AppSizing.maxFormWidth,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(AppSpacing.xl),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: provider.codeDefinitions.isNotEmpty
                                      ? DropdownButtonFormField<String>(
                                          initialValue:
                                              _selectedCodeType.isEmpty
                                              ? null
                                              : _selectedCodeType,
                                          decoration: InputDecoration(
                                            labelText: l10n.typeLabel,
                                            prefixIcon: const Icon(
                                              Icons.category_outlined,
                                            ),
                                          ),
                                          items: provider.codeDefinitions.map((
                                            def,
                                          ) {
                                            return DropdownMenuItem(
                                              value: def.prefix,
                                              child: Text(def.label),
                                            );
                                          }).toList(),
                                          onChanged: isEditing
                                              ? null
                                              : (value) {
                                                  if (value != null) {
                                                    setState(() {
                                                      _selectedCodeType = value;
                                                    });
                                                    _autoGenerateCode();
                                                  }
                                                },
                                          validator: (val) =>
                                              (val == null || val.isEmpty)
                                              ? l10n.required
                                              : null,
                                        )
                                      : TextFormField(
                                          initialValue: _selectedCodeType,
                                          decoration: InputDecoration(
                                            labelText: l10n.typeLabel,
                                            prefixIcon: const Icon(
                                              Icons.category_outlined,
                                            ),
                                          ),
                                          enabled: !isEditing,
                                          onChanged: (value) =>
                                              _selectedCodeType = value,
                                          validator: (val) =>
                                              (val == null ||
                                                  val.trim().isEmpty)
                                              ? l10n.required
                                              : null,
                                        ),
                                ),
                                const SizedBox(width: AppSpacing.lg),
                                Expanded(
                                  flex: 3,
                                  child: TextFormField(
                                    controller: _codeController,
                                    decoration: InputDecoration(
                                      labelText: l10n.code,
                                      hintText: l10n.autoGenerated,
                                      prefixIcon: const Icon(Icons.qr_code_2),
                                      suffixIcon: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (!isEditing)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.refresh_outlined,
                                              ),
                                              onPressed: _autoGenerateCode,
                                              tooltip: l10n.refreshData,
                                            ),
                                        ],
                                      ),
                                    ),
                                    readOnly: isEditing,
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return l10n.codeRequired;
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            TextFormField(
                              controller: _barcodeController,
                              decoration: InputDecoration(
                                labelText: l10n.barcode,
                                hintText: l10n.barcodeHint,
                                prefixIcon: const Icon(
                                  Icons.view_week_outlined,
                                ),
                                suffixIcon: IconButton(
                                  icon: const Icon(Icons.qr_code_scanner),
                                  onPressed: () async {
                                    final code = await showBarcodeScanner(
                                      context,
                                    );
                                    if (code != null) {
                                      _onBarcodeScanned(code);
                                    }
                                  },
                                  tooltip: l10n.scanBarcode,
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            TextFormField(
                              controller: _designationController,
                              decoration: InputDecoration(
                                labelText: l10n.designation,
                                prefixIcon: const Icon(Icons.label_outline),
                              ),
                              validator: (value) {
                                if (value == null || value.isEmpty) {
                                  return l10n.designationRequired;
                                }
                                return null;
                              },
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: _quantiteController,
                                    decoration: InputDecoration(
                                      labelText: l10n.quantity,
                                      prefixIcon: const Icon(Icons.numbers),
                                    ),
                                    keyboardType: TextInputType.number,
                                    // FE2-09: quantity used to accept empty /
                                    // negative / non-numeric text and silently
                                    // become 0. Require a non-negative integer.
                                    validator: (value) {
                                      if (value == null ||
                                          value.trim().isEmpty) {
                                        return l10n.required;
                                      }
                                      final n = int.tryParse(value.trim());
                                      if (n == null) {
                                        return l10n.wholeNumberRequired;
                                      }
                                      if (n < 0) {
                                        return l10n.mustBeNonNegative;
                                      }
                                      return null;
                                    },
                                  ),
                                ),
                                if (provider.isHost) ...[
                                  const SizedBox(width: AppSpacing.lg),
                                  Expanded(
                                    child: TextFormField(
                                      controller: _tauxController,
                                      decoration: InputDecoration(
                                        labelText: l10n.priceDzd,
                                        prefixIcon: const Icon(
                                          Icons.payments_outlined,
                                        ),
                                      ),
                                      keyboardType:
                                          const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                      // FE2-09: price must be a non-negative
                                      // number, not silently coerced to 0.
                                      validator: (value) {
                                        if (value == null ||
                                            value.trim().isEmpty) {
                                          return l10n.required;
                                        }
                                        final n = double.tryParse(value.trim());
                                        if (n == null) {
                                          return l10n.numberRequired;
                                        }
                                        if (n < 0) {
                                          return l10n.mustBeNonNegative;
                                        }
                                        return null;
                                      },
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: AppSpacing.lg),
                            provider.locations.isNotEmpty
                                ? DropdownButtonFormField<String>(
                                    initialValue:
                                        _emplacementController.text.isEmpty
                                        ? null
                                        : _emplacementController.text,
                                    decoration: InputDecoration(
                                      labelText: l10n.location,
                                      prefixIcon: const Icon(
                                        Icons.place_outlined,
                                      ),
                                    ),
                                    items: provider.locations.map((loc) {
                                      return DropdownMenuItem(
                                        value: loc,
                                        child: Text(loc),
                                      );
                                    }).toList(),
                                    onChanged: (val) => setState(
                                      () => _emplacementController.text =
                                          val ?? '',
                                    ),
                                  )
                                : TextFormField(
                                    controller: _emplacementController,
                                    decoration: InputDecoration(
                                      labelText: l10n.location,
                                      prefixIcon: const Icon(
                                        Icons.place_outlined,
                                      ),
                                    ),
                                  ),
                            const SizedBox(height: AppSpacing.lg),
                            provider.attributes.any((a) => a.type == 'STOCK')
                                ? DropdownButtonFormField<String>(
                                    initialValue:
                                        _emplacementStockController.text.isEmpty
                                        ? null
                                        : _emplacementStockController.text,
                                    decoration: InputDecoration(
                                      labelText: l10n.stockLocation,
                                      prefixIcon: const Icon(
                                        Icons.warehouse_outlined,
                                      ),
                                    ),
                                    items: provider.attributes
                                        .where((a) => a.type == 'STOCK')
                                        .map((a) {
                                          return DropdownMenuItem(
                                            value: a.value,
                                            child: Text(a.value),
                                          );
                                        })
                                        .toList(),
                                    onChanged: (val) => setState(
                                      () => _emplacementStockController.text =
                                          val ?? '',
                                    ),
                                  )
                                : TextFormField(
                                    controller: _emplacementStockController,
                                    decoration: InputDecoration(
                                      labelText: l10n.stockLocation,
                                      prefixIcon: const Icon(
                                        Icons.warehouse_outlined,
                                      ),
                                    ),
                                  ),
                            const SizedBox(height: AppSpacing.lg),
                            provider.statuses.isNotEmpty
                                ? DropdownButtonFormField<String>(
                                    initialValue:
                                        provider.statuses.contains(
                                          _selectedStatus,
                                        )
                                        ? _selectedStatus
                                        : provider.statuses.first,
                                    decoration: InputDecoration(
                                      labelText: l10n.status,
                                      prefixIcon: const Icon(
                                        Icons.flag_outlined,
                                      ),
                                    ),
                                    items: provider.statuses.map((status) {
                                      return DropdownMenuItem(
                                        value: status,
                                        child: Text(status),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      if (value != null) {
                                        setState(() {
                                          _selectedStatus = value;
                                        });
                                      }
                                    },
                                  )
                                : TextFormField(
                                    initialValue: _selectedStatus,
                                    decoration: InputDecoration(
                                      labelText: l10n.status,
                                      prefixIcon: const Icon(
                                        Icons.flag_outlined,
                                      ),
                                    ),
                                    onChanged: (value) =>
                                        _selectedStatus = value,
                                    validator: (val) =>
                                        (val == null || val.trim().isEmpty)
                                        ? l10n.required
                                        : null,
                                  ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        OutlinedButton.icon(
                          onPressed: _saving
                              ? null
                              : () => Navigator.pop(context),
                          icon: const Icon(Icons.close, size: AppIcon.md),
                          label: Text(l10n.cancel),
                        ),
                        const SizedBox(width: AppSpacing.lg),
                        FilledButton.icon(
                          onPressed: _saving ? null : _saveItem,
                          icon: _saving
                              ? const SizedBox(
                                  width: AppIcon.sm,
                                  height: AppIcon.sm,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(
                                  Icons.save_outlined,
                                  size: AppIcon.md,
                                ),
                          label: Text(l10n.save),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
