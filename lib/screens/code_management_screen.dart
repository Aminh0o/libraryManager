import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../services/error_messages.dart';
import '../models/code_definition.dart';
import '../ui/app_tokens.dart';
import '../widgets/confirm_action_dialog.dart';
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
        await provider.updateCodeDefinition(
          _editingDefinition!.prefix,
          prefix,
          label,
        );
      }
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(l10n.savedSuccessfully)));
        _resetForm();
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
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

    return Scaffold(
      appBar: AppBar(title: Text(l10n.manageVariables)),
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
                  Text(
                    l10n.manageVariables,
                    style: txt.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Expanded(
                    child: Card(
                      clipBehavior: Clip.antiAlias,
                      child: ListView.separated(
                        itemCount: provider.codeDefinitions.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final def = provider.codeDefinitions[index];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              child: Text(
                                def.prefix[0],
                                style: TextStyle(
                                  color: scheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            title: Text(
                              def.prefix,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            subtitle: Text(def.label),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: Icon(
                                    Icons.edit_outlined,
                                    color: scheme.primary,
                                    size: AppIcon.md,
                                  ),
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
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: AppStatus.danger,
                                    size: AppIcon.md,
                                  ),
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
              color: scheme.surfaceContainerLow,
              padding: AppSpacing.allXxl,
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _editingDefinition == null
                          ? l10n.newVariable
                          : l10n.editVariable,
                      style: txt.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    TextFormField(
                      controller: _prefixController,
                      decoration: InputDecoration(
                        labelText: l10n.prefix,
                        hintText: l10n.prefixHint,
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? l10n.required
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextFormField(
                      controller: _labelController,
                      decoration: InputDecoration(
                        labelText: l10n.label,
                        hintText: l10n.labelHint,
                      ),
                      validator: (value) => (value == null || value.isEmpty)
                          ? l10n.required
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.xxl),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: _handleSave,
                        child: Text(
                          _editingDefinition == null
                              ? l10n.addVariable
                              : l10n.updateVariable,
                        ),
                      ),
                    ),
                    if (_editingDefinition != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      SizedBox(
                        width: double.infinity,
                        child: TextButton(
                          onPressed: _resetForm,
                          child: Text(l10n.cancel),
                        ),
                      ),
                    ],
                    const Spacer(),
                    // Advisory note: a subtle surface tint, not the old hard-
                    // coded cream card that was unreadable in dark mode.
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
                              l10n.notePrefixChange,
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

  void _confirmDelete(CodeDefinition def) {
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
        onConfirm: () => provider.deleteCodeDefinition(def.prefix),
      ),
    );
  }
}
