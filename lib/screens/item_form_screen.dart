import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/library_item.dart';
import '../providers/library_provider.dart';
import '../widgets/barcode_scanner_dialog.dart';

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

  @override
  void initState() {
    super.initState();
    _codeController = TextEditingController(text: widget.item?.code ?? '');
    _barcodeController = TextEditingController(text: widget.item?.barcode ?? '');
    _designationController = TextEditingController(text: widget.item?.designation ?? '');
    _quantiteController = TextEditingController(text: widget.item?.quantite.toString() ?? '1');
    _emplacementController = TextEditingController(text: widget.item?.emplacement ?? '');
    _tauxController = TextEditingController(text: widget.item?.taux.toString() ?? '0.0');
    _emplacementStockController = TextEditingController(text: widget.item?.emplacementStock ?? '');
    
    // Status initialization
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    if (widget.item != null) {
      _selectedStatus = widget.item!.status;
    } else {
      _selectedStatus = provider.statuses.isNotEmpty ? provider.statuses.first : 'Disponible';
    }
    
    _selectedCodeType = widget.item?.codeType ?? '';
    
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

  void _saveItem() {
    if (_formKey.currentState!.validate()) {
      final item = LibraryItem(
        code: _codeController.text,
        barcode: _barcodeController.text.isEmpty ? null : _barcodeController.text,
        codeType: _selectedCodeType,
        designation: _designationController.text,
        quantite: int.tryParse(_quantiteController.text) ?? 0,
        emplacement: _emplacementController.text,
        taux: double.tryParse(_tauxController.text) ?? 0.0,
        emplacementStock: _emplacementStockController.text,
        status: _selectedStatus,
      );

      final provider = Provider.of<LibraryProvider>(context, listen: false);
      if (widget.item == null) {
        provider.addItem(item);
      } else {
        provider.updateItem(item);
      }

      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);
    final isEditing = widget.item != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? l10n.editItem : l10n.addItem),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              flex: 2,
                              child: DropdownButtonFormField<String>(
                                initialValue: _selectedCodeType.isEmpty ? null : _selectedCodeType,
                                  decoration: InputDecoration(
                                    labelText: l10n.typeLabel,
                                    prefixIcon: const Icon(Icons.category),
                                    border: const OutlineInputBorder(),
                                  ),
                                items: provider.codeDefinitions.map((def) {
                                  return DropdownMenuItem(
                                    value: def.prefix,
                                    child: Text(def.label),
                                  );
                                }).toList(),
                                onChanged: isEditing ? null : (value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedCodeType = value;
                                    });
                                    _autoGenerateCode();
                                  }
                                },
                                  validator: (val) => (val == null || val.isEmpty) ? l10n.required : null,
                                ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              flex: 3,
                              child: TextFormField(
                                controller: _codeController,
                                  decoration: InputDecoration(
                                    labelText: l10n.code,
                                    hintText: l10n.autoGenerated,
                                    prefixIcon: const Icon(Icons.qr_code),
                                    border: const OutlineInputBorder(),
                                    suffixIcon: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        if (!isEditing)
                                          IconButton(
                                            icon: const Icon(Icons.refresh),
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
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _barcodeController,
                          decoration: InputDecoration(
                            labelText: l10n.barcode,
                            hintText: l10n.barcodeHint,
                            prefixIcon: const Icon(Icons.barcode_reader),
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.qr_code_scanner),
                              onPressed: () async {
                                final code = await showBarcodeScanner(context);
                                if (code != null) {
                                  _onBarcodeScanned(code);
                                }
                              },
                              tooltip: l10n.scanBarcode,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _designationController,
                          decoration: InputDecoration(
                            labelText: l10n.designation,
                            prefixIcon: const Icon(Icons.label),
                            border: const OutlineInputBorder(),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return l10n.designationRequired;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: TextFormField(
                                controller: _quantiteController,
                                decoration: InputDecoration(
                                  labelText: l10n.quantity,
                                  prefixIcon: const Icon(Icons.numbers),
                                  border: const OutlineInputBorder(),
                                ),
                                keyboardType: TextInputType.number,
                              ),
                            ),
                            if (provider.isHost) ...[
                              const SizedBox(width: 16),
                              Expanded(
                                child: TextFormField(
                                  controller: _tauxController,
                                  decoration: InputDecoration(
                                    labelText: 'Prix (DZD)',
                                    prefixIcon: const Icon(Icons.payments),
                                    border: const OutlineInputBorder(),
                                  ),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 16),
                        provider.locations.isNotEmpty
                            ? DropdownButtonFormField<String>(
                                initialValue: _emplacementController.text.isEmpty ? null : _emplacementController.text,
                                decoration: InputDecoration(
                                  labelText: l10n.location,
                                  prefixIcon: const Icon(Icons.place),
                                  border: const OutlineInputBorder(),
                                ),
                                items: provider.locations.map((loc) {
                                  return DropdownMenuItem(value: loc, child: Text(loc));
                                }).toList(),
                                onChanged: (val) => setState(() => _emplacementController.text = val ?? ''),
                              )
                            : TextFormField(
                                controller: _emplacementController,
                                decoration: InputDecoration(
                                  labelText: l10n.location,
                                  prefixIcon: const Icon(Icons.place),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                        const SizedBox(height: 16),
                        provider.attributes.any((a) => a.type == 'STOCK')
                            ? DropdownButtonFormField<String>(
                                initialValue: _emplacementStockController.text.isEmpty ? null : _emplacementStockController.text,
                                decoration: InputDecoration(
                                  labelText: l10n.stockLocation,
                                  prefixIcon: const Icon(Icons.warehouse),
                                  border: const OutlineInputBorder(),
                                ),
                                items: provider.attributes.where((a) => a.type == 'STOCK').map((a) {
                                  return DropdownMenuItem(value: a.value, child: Text(a.value));
                                }).toList(),
                                onChanged: (val) => setState(() => _emplacementStockController.text = val ?? ''),
                              )
                            : TextFormField(
                                controller: _emplacementStockController,
                                decoration: InputDecoration(
                                  labelText: l10n.stockLocation,
                                  prefixIcon: const Icon(Icons.warehouse),
                                  border: const OutlineInputBorder(),
                                ),
                              ),
                        const SizedBox(height: 16),
                        DropdownButtonFormField<String>(
                          initialValue: _selectedStatus,
                          decoration: InputDecoration(
                            labelText: l10n.status,
                            prefixIcon: const Icon(Icons.flag),
                            border: const OutlineInputBorder(),
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
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                      label: Text(l10n.cancel),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: _saveItem,
                      icon: const Icon(Icons.save),
                      label: Text(l10n.save),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
