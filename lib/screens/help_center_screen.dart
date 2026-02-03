import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';

class HelpCenterScreen extends StatelessWidget {
  const HelpCenterScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.helpCenter),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          _buildAppDefinition(context, l10n),
          const SizedBox(height: 24),
          _buildHelpSection(
            context,
            icon: Icons.people,
            title: l10n.helpMembersTitle,
            content: l10n.helpMembersContent,
          ),
          const SizedBox(height: 16),
          _buildHelpSection(
            context,
            icon: Icons.assignment_ind,
            title: l10n.helpLoansTitle,
            content: l10n.helpLoansContent,
          ),
          const SizedBox(height: 16),
          _buildHelpSection(
            context,
            icon: Icons.sync,
            title: l10n.helpSyncTitle,
            content: l10n.helpSyncContent,
          ),
          const SizedBox(height: 16),
          _buildHelpSection(
            context,
            icon: Icons.qr_code_scanner,
            title: l10n.helpBarcodeTitle,
            content: l10n.helpBarcodeContent,
          ),
          const SizedBox(height: 32),
          Center(
            child: Text(
              'Library Manager v1.2.0',
              style: TextStyle(color: Colors.grey[600], fontStyle: FontStyle.italic),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppDefinition(BuildContext context, AppLocalizations l10n) {
    return Card(
      elevation: 0,
      color: Colors.orange.withValues(alpha: 0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.orange, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    l10n.appDefinitionTitle,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.orange),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.appDefinitionContent,
              style: TextStyle(fontSize: 16, height: 1.6, color: Colors.brown[800]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHelpSection(BuildContext context, {required IconData icon, required String title, required String content}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange.withValues(alpha: 0.1),
          child: Icon(icon, color: Colors.orange),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Text(
              content,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
