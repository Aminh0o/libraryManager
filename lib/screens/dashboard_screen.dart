import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../widgets/stat_card.dart';
import '../widgets/password_dialog.dart';
import '../widgets/barcode_scanner_dialog.dart';
import 'item_form_screen.dart';
import 'history_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.orange));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.nationalLibrary,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Colors.brown[900],
                        ),
                  ),
                  Text(
                    l10n.algerianSystem,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.brown[400],
                        ),
                  ),
                ],
              ),
              Chip(
                avatar: Icon(
                  provider.isHost ? Icons.dns : Icons.computer,
                  size: 18,
                  color: provider.isHost ? Colors.green : Colors.blue,
                ),
                label: Text(provider.isHost ? l10n.hostMode : l10n.clientMode),
                backgroundColor: (provider.isHost ? Colors.green : Colors.blue).withValues(alpha: 0.1),
              ),
            ],
          ),
          const SizedBox(height: 32),
          
          // Primary Stats
          LayoutBuilder(
            builder: (context, constraints) {
              return GridView.count(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisCount: constraints.maxWidth > 800 ? (provider.isHost ? 3 : 2) : 1,
                crossAxisSpacing: 20,
                mainAxisSpacing: 20,
                childAspectRatio: constraints.maxWidth > 800 ? 2.2 : 3.0,
                children: [
                   StatCard(
                     title: l10n.totalDocuments,
                     value: provider.totalQuantity.toString(),
                     icon: Icons.auto_stories,
                     color: Colors.blue,
                   ),
                   if (provider.isHost)
                     StatCard(
                       title: l10n.inventoryValue,
                       value: '${provider.totalValue.toStringAsFixed(0)} ${l10n.priceDzd.split('(').last.replaceAll(')', '')}',
                       icon: Icons.account_balance_wallet,
                       color: Colors.green,
                     ),
                   StatCard(
                     title: l10n.onLoan,
                     value: provider.onLoanCount.toString(),
                     icon: Icons.assignment_return,
                     color: Colors.purple,
                   ),
                 ],
              );
            },
          ),
          
          const SizedBox(height: 32),
          
          // Category Summary
          Text(
            l10n.typeLabel,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20.0),
              child: Wrap(
                spacing: 32,
                runSpacing: 20,
                children: provider.codeDefinitions.map((def) {
                  final count = provider.getCountByCodeType(def.prefix);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        def.label,
                        style: TextStyle(color: Colors.grey[600], fontSize: 13),
                      ),
                      Text(
                        count.toString(),
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),
          
          const SizedBox(height: 32),
          
          // Quick Actions
          if (provider.isHost) ...[
            Text(
              l10n.quickActions,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              children: [
                ElevatedButton.icon(
                  onPressed: () async {
                    final code = await showBarcodeScanner(context);
                    if (code != null && context.mounted) {
                      // Process scan from dashboard (e.g. search)
                      Provider.of<LibraryProvider>(context, listen: false).search(code);
                      // Navigator.push might be needed if we want to jump to inventory
                    }
                  },
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(l10n.quickScan),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.brown[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const ItemFormScreen()),
                    );
                  },
                  icon: const Icon(Icons.add),
                  label: Text(l10n.addNewBook),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () => provider.reload(),
                  icon: const Icon(Icons.refresh),
                  label: Text(l10n.refreshData),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      await provider.exportToCsv();
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.exportSuccess)),
                        );
                      }
                    } catch (e) {
                       if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
                        );
                      }
                    }
                  },
                  icon: const Icon(Icons.download),
                  label: Text(l10n.exportCsv),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () async {
                    final passed = await showPasswordPrompt(context, title: l10n.enterPassword);
                    if (passed && context.mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => const HistoryScreen()),
                      );
                    }
                  },
                  icon: const Icon(Icons.history),
                  label: Text(l10n.historyAction),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blueGrey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  ),
                ),
              ],
            ),
          ],
          
          if (provider.isHost) ...[
            const SizedBox(height: 32),
            Row(
              children: [
                const Icon(Icons.devices, color: Colors.blue),
                const SizedBox(width: 8),
                Text(
                  l10n.connectedDevices,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(color: Colors.blue, borderRadius: BorderRadius.circular(12)),
                  child: Text(
                    provider.activeClients.length.toString(),
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (provider.activeClients.isNotEmpty)
              Card(
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: provider.activeClients.length,
                  separatorBuilder: (context, index) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final clientIp = provider.activeClients[index];
                    return ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.phone_android, size: 20)),
                      title: Text(clientIp),
                      subtitle: Text(l10n.connectedViaLan),
                      trailing: const Icon(Icons.circle, color: Colors.green, size: 12),
                    );
                  },
                ),
              ),
          ],
          
          if (provider.errorMessage != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red[100]!),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      provider.errorMessage!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
