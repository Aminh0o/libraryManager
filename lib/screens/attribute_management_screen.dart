import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../models/attribute_definition.dart';
import '../l10n/app_localizations.dart';

class AttributeManagementScreen extends StatefulWidget {
  const AttributeManagementScreen({super.key});

  @override
  State<AttributeManagementScreen> createState() => _AttributeManagementScreenState();
}

class _AttributeManagementScreenState extends State<AttributeManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _valueController = TextEditingController();
  String _selectedType = 'LOCATION';

  @override
  void dispose() {
    _valueController.dispose();
    super.dispose();
  }

  void _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    
    try {
      await provider.addAttributeDefinition(_selectedType, _valueController.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.savedSuccessfully)),
        );
        _valueController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    final filteredAttributes = provider.attributes.where((a) => a.type == _selectedType).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manageAttributes),
        backgroundColor: Colors.brown[50],
      ),
      body: Row(
        children: [
          // List Section
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.manageAttributes,
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      ToggleButtons(
                        isSelected: [
                          _selectedType == 'LOCATION',
                          _selectedType == 'STATUS',
                          _selectedType == 'STOCK',
                        ],
                        onPressed: (index) {
                          setState(() {
                            if (index == 0) _selectedType = 'LOCATION';
                            if (index == 1) _selectedType = 'STATUS';
                            if (index == 2) _selectedType = 'STOCK';
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(l10n.location),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Text(l10n.status),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: const Text('Stock'),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListView.separated(
                        itemCount: filteredAttributes.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final attr = filteredAttributes[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.blue.withValues(alpha: 0.1),
                              child: Icon(
                                _selectedType == 'LOCATION' 
                                  ? Icons.location_on 
                                  : (_selectedType == 'STATUS' ? Icons.info : Icons.warehouse),
                                color: Colors.blue,
                                size: 20,
                              ),
                            ),
                            title: Text(attr.value, style: const TextStyle(fontWeight: FontWeight.bold)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete, color: Colors.red),
                              onPressed: () => _confirmDelete(attr),
                              tooltip: l10n.deleteItem,
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const VerticalDivider(width: 1),
          // Form Section
          Expanded(
            flex: 1,
            child: Container(
              color: Colors.white,
              padding: const EdgeInsets.all(24),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.addNewBook, // Replace with appropriate generic title if needed
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _valueController,
                      decoration: InputDecoration(
                        labelText: l10n.label,
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) => (value == null || value.isEmpty) ? l10n.required : null,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: _handleSave,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(l10n.addVariable), 
                      ),
                    ),
                    const Spacer(),
                    Card(
                      color: Colors.blue[50],
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.blue),
                            const SizedBox(width: 12),
                            const Expanded(
                              child: Text(
                                'Ces options apparaîtront dans les listes déroulantes lors de l\'ajout ou de la modification d\'un livre.',
                                style: TextStyle(fontSize: 12, color: Colors.blueGrey),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(AttributeDefinition attr) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.confirmDeleteDefinition),
        content: Text(l10n.deleteDefinitionWarning),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)),
          TextButton(
            onPressed: () {
              if (attr.id != null) {
                provider.deleteAttributeDefinition(attr.id!);
              }
              Navigator.pop(context);
            },
            child: Text(l10n.deleteItem, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
