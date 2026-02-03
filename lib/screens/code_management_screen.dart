import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../models/code_definition.dart';
import '../l10n/app_localizations.dart';

class CodeManagementScreen extends StatefulWidget {
  const CodeManagementScreen({super.key});

  @override
  State<CodeManagementScreen> createState() => _CodeManagementScreenState();
}

class _CodeManagementScreenState extends State<CodeManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _prefixController = TextEditingController();
  final _labelController = TextEditingController();
  CodeDefinition? _editingDefinition;

  @override
  void dispose() {
    _prefixController.dispose();
    _labelController.dispose();
    super.dispose();
  }

  void _resetForm() {
    _prefixController.clear();
    _labelController.clear();
    _editingDefinition = null;
    setState(() {});
  }

  void _handleSave() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);
    
    final prefix = _prefixController.text.toUpperCase();
    final label = _labelController.text;

    try {
      if (_editingDefinition == null) {
        await provider.addCodeDefinition(prefix, label);
      } else {
        await provider.updateCodeDefinition(_editingDefinition!.prefix, prefix, label);
      }
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.savedSuccessfully)),
        );
        _resetForm();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.manageVariables),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
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
                  Text(
                    l10n.manageVariables,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Card(
                      elevation: 2,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListView.separated(
                        itemCount: provider.codeDefinitions.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final def = provider.codeDefinitions[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.withValues(alpha: 0.1),
                              child: Text(def.prefix[0], style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                            ),
                            title: Text(def.prefix, style: const TextStyle(fontWeight: FontWeight.bold)),
                            subtitle: Text(def.label),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  onPressed: () {
                                    setState(() {
                                      _editingDefinition = def;
                                      _prefixController.text = def.prefix;
                                      _labelController.text = def.label;
                                    });
                                  },
                                  tooltip: l10n.editItem,
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  onPressed: () => _confirmDelete(def),
                                  tooltip: l10n.deleteItem,
                                ),
                              ],
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
                      _editingDefinition == null ? l10n.newVariable : l10n.editVariable,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _prefixController,
                      decoration: InputDecoration(
                        labelText: l10n.prefix,
                        border: const OutlineInputBorder(),
                        hintText: l10n.prefixHint,
                      ),
                      validator: (value) => (value == null || value.isEmpty) ? l10n.required : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _labelController,
                      decoration: InputDecoration(
                        labelText: l10n.label,
                        border: const OutlineInputBorder(),
                        hintText: l10n.labelHint,
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
                          backgroundColor: Colors.orange, 
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        child: Text(_editingDefinition == null ? l10n.addVariable : l10n.updateVariable),
                      ),
                    ),
                    if (_editingDefinition != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _resetForm,
                          child: Text(l10n.cancel),
                        ),
                      ),
                    ],
                    const Spacer(),
                    Card(
                      color: const Color(0xFFFFF3E0),
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: Row(
                          children: [
                            const Icon(Icons.info_outline, color: Colors.orange),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                l10n.notePrefixChange,
                                style: const TextStyle(fontSize: 12, color: Colors.brown),
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

  void _confirmDelete(CodeDefinition def) {
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
              provider.deleteCodeDefinition(def.prefix);
              Navigator.pop(context);
            },
            child: Text(l10n.deleteItem, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
