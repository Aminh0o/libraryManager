import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../services/error_messages.dart';
import '../models/attribute_definition.dart';
import '../ui/app_tokens.dart';
import '../widgets/confirm_action_dialog.dart';
import '../l10n/app_localizations.dart';

class AttributeManagementScreen extends StatefulWidget {
  const AttributeManagementScreen({super.key});

  @override
  State<AttributeManagementScreen> createState() =>
      _AttributeManagementScreenState();
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
      await provider.addAttributeDefinition(
        _selectedType,
        _valueController.text,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.savedSuccessfully)));
        _valueController.clear();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(describeError(l10n, e)),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final txt = Theme.of(context).textTheme;

    final filteredAttributes = provider.attributes
        .where((a) => a.type == _selectedType)
        .toList();

    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageAttributes)),
      body: Row(
        children: [
          // List Section
          Expanded(
            flex: 2,
            child: Container(
              padding: AppSpacing.allXxl,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        l10n.manageAttributes,
                        style: txt.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
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
                        borderRadius: AppRadius.button,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: Text(l10n.location),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: Text(l10n.status),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: Text(l10n.stock),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        itemCount: filteredAttributes.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final attr = filteredAttributes[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              child: Icon(
                                _selectedType == 'LOCATION'
                                    ? Icons.location_on_outlined
                                    : (_selectedType == 'STATUS'
                                          ? Icons.info_outline
                                          : Icons.warehouse_outlined),
                                color: scheme.primary,
                                size: AppIcon.md,
                              ),
                            ),
                            title: Text(
                              attr.value,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                color: AppStatus.danger,
                                size: AppIcon.md,
                              ),
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
              color: scheme.surfaceContainerLow,
              padding: AppSpacing.allXxl,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      // The old heading said "Add new book" on an attribute
                      // form (§52: wrong label); reuse the existing generic
                      // "new value" copy instead of a mismatched title.
                      l10n.newValue,
                      style: txt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    TextFormField(
                      controller: _valueController,
                      decoration: InputDecoration(labelText: l10n.label),
                      validator: (value) => (value == null || value.isEmpty)
                          ? l10n.required
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _handleSave,
                        child: Text(l10n.addVariable),
                      ),
                    ),
                    const Spacer(),
                    // Advisory note on a themed surface (the old blue[50] card
                    // was unreadable in dark mode).
                    Container(
                      padding: AppSpacing.allMd,
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHigh,
                        borderRadius: AppRadius.card,
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: scheme.primary,
                            size: AppIcon.md,
                          ),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(
                            child: Text(
                              l10n.attributeOptionsNote,
                              style: txt.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
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

    // FE2-01/02 (P9-9.29): await the deletion and close only on success.
    showDialog(
      context: context,
      builder: (_) => ConfirmActionDialog(
        title: Text(l10n.confirmDeleteDefinition),
        content: Text(l10n.deleteDefinitionWarning),
        confirmLabel: Text(
          l10n.deleteItem,
          style: const TextStyle(color: AppStatus.danger),
        ),
        cancelLabel: Text(l10n.cancel),
        confirmKey: const Key('confirmDelete'),
        cancelKey: const Key('cancelDelete'),
        onConfirm: () async {
          if (attr.id != null) {
            await provider.deleteAttributeDefinition(attr.id!);
          }
        },
      ),
    );
  }
}
