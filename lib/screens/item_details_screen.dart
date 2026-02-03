import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/library_item.dart';
import '../providers/library_provider.dart';
import 'item_form_screen.dart';

class ItemDetailsScreen extends StatelessWidget {
  final String itemCode;

  const ItemDetailsScreen({super.key, required this.itemCode});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);
    
    // Find item by code in the provider's list
    final item = provider.allItems.firstWhere(
      (i) => i.code == itemCode,
      orElse: () => LibraryItem(
        code: itemCode, 
        designation: 'Unknown', 
        codeType: 'LIV', 
        quantite: 0, 
        taux: 0, 
        emplacement: '---', 
        emplacementStock: '---'
      ),
    );

    final currency = l10n.priceDzd.contains('(') 
        ? l10n.priceDzd.split('(').last.replaceAll(')', '') 
        : 'DZD';

    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Text(l10n.itemProfile),
        elevation: 0,
        actions: [
          if (provider.isHost)
            IconButton(
              icon: const Icon(Icons.edit),
              tooltip: l10n.editItemDetails,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ItemFormScreen(item: item),
                  ),
                );
              },
            ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            // Hero Header
            _buildHeroHeader(context, item, l10n),
            const SizedBox(height: 24),
            
            // Info Cards
            _buildInfoCard(
              context,
              title: l10n.technicalInfo,
              icon: Icons.qr_code_2,
              color: Colors.blue,
              children: [
                _buildDetailRow(l10n.code, item.fullCode),
                _buildDetailRow(l10n.barcode, item.barcode ?? '---'),
                _buildDetailRow(l10n.typeLabel, item.codeType),
                if (!provider.isHost) _buildDetailRow(l10n.quantity, item.quantite.toString()),
              ],
            ),
            if (provider.isHost) ...[
              const SizedBox(height: 16),
              _buildInfoCard(
                context,
                title: l10n.pricingInfo,
                icon: Icons.payments_outlined,
                color: Colors.green,
                children: [
                  _buildDetailRow(l10n.quantity, item.quantite.toString()),
                  _buildDetailRow(l10n.rate, '${item.taux.toStringAsFixed(2)} $currency'),
                ],
              ),
            ],
            const SizedBox(height: 16),
            _buildInfoCard(
              context,
              title: l10n.locationInfo,
              icon: Icons.location_on_outlined,
              color: Colors.orange,
              children: [
                _buildDetailRow(l10n.location, item.emplacement),
                _buildDetailRow(l10n.stockLocation, item.emplacementStock),
              ],
            ),
            
            const SizedBox(height: 32),
            
            // Quick Actions Section
            if (provider.isHost) _buildStatusActions(context, item, provider, l10n),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroHeader(BuildContext context, LibraryItem item, AppLocalizations l10n) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          const CircleAvatar(
            radius: 40,
            backgroundColor: Colors.orange,
            child: Icon(Icons.auto_stories, size: 40, color: Colors.white),
          ),
          const SizedBox(height: 16),
          Text(
            item.designation,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _getStatusColor(item.status).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _getStatusColor(item.status)),
            ),
            child: Text(
              _getLocalizedStatus(item.status, l10n),
              style: TextStyle(
                color: _getStatusColor(item.status),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Colors.grey[200]!),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.grey),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildStatusActions(BuildContext context, LibraryItem item, LibraryProvider provider, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.quickActions,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _buildActionButton(
              l10n.markAsAvailable,
              Icons.check_circle_outline,
              Colors.green,
              () => provider.updateItemStatus(item, ItemStatus.disponible),
              enabled: item.status != ItemStatus.disponible,
            ),
            _buildActionButton(
              l10n.markAsBorrowed,
              Icons.assignment_return_outlined,
              Colors.purple,
              () => provider.updateItemStatus(item, ItemStatus.emprunte),
              enabled: item.status != ItemStatus.emprunte,
            ),
            _buildActionButton(
              l10n.markAsReserved,
              Icons.bookmark_outline,
              Colors.orange,
              () => provider.updateItemStatus(item, ItemStatus.reserve),
              enabled: item.status != ItemStatus.reserve,
            ),
            _buildActionButton(
              l10n.markAsDamaged,
              Icons.error_outline,
              Colors.red,
              () => provider.updateItemStatus(item, ItemStatus.endommage),
              enabled: item.status != ItemStatus.endommage,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(String label, IconData icon, Color color, VoidCallback onPressed, {bool enabled = true}) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        elevation: enabled ? 2 : 0,
        disabledBackgroundColor: color.withValues(alpha: 0.3),
        disabledForegroundColor: Colors.white.withValues(alpha: 0.8),
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case ItemStatus.disponible: return Colors.blue;
      case ItemStatus.emprunte: return Colors.purple;
      case ItemStatus.reserve: return Colors.orange;
      case ItemStatus.endommage: return Colors.red;
      default: return Colors.grey;
    }
  }

  String _getLocalizedStatus(String status, AppLocalizations l10n) {
    switch (status) {
      case ItemStatus.disponible: return l10n.statusDisponible;
      case ItemStatus.emprunte: return l10n.statusEmprunte;
      case ItemStatus.reserve: return l10n.statusReserve;
      case ItemStatus.endommage: return l10n.statusEndommage;
      default: return status;
    }
  }
}
