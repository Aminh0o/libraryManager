import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:data_table_2/data_table_2.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../models/library_item.dart';
import 'item_form_screen.dart';
import 'settings_screen.dart';
import 'dashboard_screen.dart';
import 'item_details_screen.dart';
import 'members_screen.dart';
import 'loan_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    final List<Widget> screens = [
      const DashboardScreen(),
      const _InventoryView(),
      const MembersScreen(),
      const LoanScreen(),
      const SettingsScreen(),
    ];

    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: _selectedIndex,
            onDestinationSelected: (int index) {
              setState(() {
                _selectedIndex = index;
              });
            },
            labelType: NavigationRailLabelType.all,
            backgroundColor: Colors.brown[50],
            selectedIconTheme: const IconThemeData(color: Colors.orange, size: 30),
            unselectedIconTheme: IconThemeData(color: Colors.brown[300]),
            selectedLabelTextStyle: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
            destinations: [
              NavigationRailDestination(
                icon: const Icon(Icons.dashboard_outlined),
                selectedIcon: const Icon(Icons.dashboard),
                label: Text(l10n.dashboard),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.inventory_2_outlined),
                selectedIcon: const Icon(Icons.inventory_2),
                label: Text(l10n.inventory),
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.people_outline),
                selectedIcon: const Icon(Icons.people),
                label: const Text('Membres'), // TODO: Localize
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.assignment_ind_outlined),
                selectedIcon: const Icon(Icons.assignment_ind),
                label: const Text('Prêts'), // TODO: Localize
              ),
              NavigationRailDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: Text(l10n.settings),
              ),
            ],
            leading: Padding(
              padding: const EdgeInsets.symmetric(vertical: 20),
              child: CircleAvatar(
                backgroundColor: Colors.orange,
                radius: 20,
                child: const Icon(Icons.library_books, color: Colors.white),
              ),
            ),
          ),
          const VerticalDivider(thickness: 1, width: 1),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  color: Colors.white,
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getTitle(_selectedIndex, l10n),
                            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                ),
                          ),
                          Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: provider.isConnected ? Colors.green : Colors.red,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                provider.isHost ? l10n.hostMode : l10n.clientMode,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey[600],
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '• ${provider.isConnected ? l10n.connected : l10n.disconnected}',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: provider.isConnected ? Colors.green[700] : Colors.red[700],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const Spacer(),
                      PopupMenuButton<Locale>(
                        onSelected: (Locale locale) => provider.setLocale(locale),
                        icon: const Icon(Icons.translate),
                        itemBuilder: (context) => [
                          const PopupMenuItem(value: Locale('en'), child: Text('English')),
                          const PopupMenuItem(value: Locale('fr'), child: Text('Français')),
                          const PopupMenuItem(value: Locale('ar'), child: Text('العربية')),
                        ],
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: screens[_selectedIndex]),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: (_selectedIndex == 1 && provider.isHost)
          ? FloatingActionButton.extended(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const ItemFormScreen()),
                );
              },
              icon: const Icon(Icons.add),
              label: Text(l10n.addItem),
              backgroundColor: Colors.orange,
            )
          : null,
    );
  }
  String _getTitle(int index, AppLocalizations l10n) {
    switch (index) {
      case 0: return l10n.dashboard;
      case 1: return l10n.inventory;
      case 2: return 'Gestion des Membres'; // TODO: Localize
      case 3: return 'Gestion des Prêts';   // TODO: Localize
      case 4: return l10n.settings;
      default: return '';
    }
  }

  static String getLocalizedStatus(String status, AppLocalizations l10n) {
    switch (status) {
      case ItemStatus.disponible: return l10n.statusDisponible;
      case ItemStatus.emprunte: return l10n.statusEmprunte;
      case ItemStatus.reserve: return l10n.statusReserve;
      case ItemStatus.endommage: return l10n.statusEndommage;
      default: return status;
    }
  }
}

class _InventoryView extends StatelessWidget {
  const _InventoryView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);

    if (provider.isLoading) {
      return const Center(child: CircularProgressIndicator(color: Colors.orange));
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                flex: 4,
                child: TextField(
                  decoration: InputDecoration(
                    hintText: l10n.search,
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.camera_alt),
                      onPressed: () async {
                        final code = await showBarcodeScanner(context);
                        if (!context.mounted) return;
                        if (code != null) {
                          provider.search(code);
                        }
                      },
                      tooltip: l10n.scanBarcode,
                    ),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    filled: true,
                    fillColor: Colors.white,
                  ),
                  onChanged: (value) => provider.search(value),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: provider.codeTypeFilter,
                      hint: Text(l10n.typeLabel),
                      isExpanded: true,
                      icon: const Icon(Icons.category, color: Colors.orange),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l10n.allTypes),
                        ),
                        ...provider.codeDefinitions.map((def) => DropdownMenuItem(
                          value: def.prefix,
                          child: Text(def.label),
                        )),
                      ],
                      onChanged: (value) => provider.filterByCodeType(value),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: provider.statusFilter,
                      hint: Text(l10n.status),
                      isExpanded: true,
                      icon: const Icon(Icons.filter_list, color: Colors.orange),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(l10n.allStatuses),
                        ),
                        ...ItemStatus.all.map((status) => DropdownMenuItem(
                          value: status,
                          child: Text(_HomeScreenState.getLocalizedStatus(status, l10n)),
                        )),
                      ],
                      onChanged: (value) => provider.filterByStatus(value),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              IconButton(
                onPressed: provider.clearFilters,
                icon: const Icon(Icons.clear_all),
                tooltip: l10n.clearFilters,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: Card(
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              child: Column(
                children: [
                  Expanded(
                    child: DataTable2(
                      columnSpacing: 12,
                      horizontalMargin: 12,
                      minWidth: 1000,
                      headingRowColor: WidgetStateProperty.all(Colors.orange.withValues(alpha: 0.1)),
                      columns: [
                        DataColumn2(label: Text(l10n.code, style: const TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S),
                        DataColumn2(label: Text(l10n.designation, style: const TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.L),
                        DataColumn2(label: Text(l10n.quantity, style: const TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S),
                        DataColumn2(label: Text(l10n.location, style: const TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.M),
                        if (provider.isHost) DataColumn2(label: Text(l10n.priceDzd, style: const TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S),
                        DataColumn2(label: Text(l10n.stockLocation, style: const TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.M),
                        DataColumn2(label: Text(l10n.status, style: const TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S),
                        if (provider.isHost) DataColumn2(label: Text(l10n.actions, style: const TextStyle(fontWeight: FontWeight.bold)), size: ColumnSize.S),
                      ],
                      rows: provider.items.map((item) {
                        return DataRow2(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ItemDetailsScreen(itemCode: item.code),
                              ),
                            );
                          },
                          cells: [
                          DataCell(Text(item.fullCode)),
                          DataCell(Text(item.designation)),
                          DataCell(Text(item.quantite.toString())),
                          DataCell(Text(item.emplacement)),
                          if (provider.isHost) DataCell(Text(item.taux.toStringAsFixed(2))),
                          DataCell(Text(item.emplacementStock)),
                          DataCell(
                            provider.isHost
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: _getStatusColor(item.status).withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: _getStatusColor(item.status)),
                                    ),
                                    child: Text(
                                      _HomeScreenState.getLocalizedStatus(item.status, l10n),
                                      style: TextStyle(color: _getStatusColor(item.status), fontWeight: FontWeight.bold, fontSize: 12),
                                    ),
                                  )
                                : DropdownButton<String>(
                                    value: ItemStatus.all.contains(item.status) ? item.status : ItemStatus.disponible,
                                    underline: Container(),
                                    isDense: true,
                                    icon: const Icon(Icons.arrow_drop_down, color: Colors.orange),
                                    style: const TextStyle(color: Colors.black87, fontWeight: FontWeight.w500, fontSize: 13),
                                    items: ItemStatus.all.map((s) {
                                      return DropdownMenuItem(value: s, child: Text(s));
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) provider.updateItemStatus(item, val);
                                    },
                                  ),
                          ),
                          if (provider.isHost)
                            DataCell(Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit, color: Colors.blue),
                                  tooltip: l10n.editItem,
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => ItemFormScreen(item: item),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete, color: Colors.red),
                                  tooltip: l10n.deleteItem,
                                  onPressed: () => _confirmDelete(context, item),
                                ),
                              ],
                            )),
                        ]);
                      }).toList(),
                    ),
                  ),
                  if (provider.hasMoreInventory)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: TextButton.icon(
                        onPressed: provider.isLoading ? null : () => provider.loadMoreItems(),
                        icon: provider.isLoading 
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.add),
                        label: Text(l10n.loadMore),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (provider.items.isEmpty && !provider.isLoading)
            Padding(
              padding: const EdgeInsets.all(32.0),
              child: Column(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    l10n.noItemsFound,
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
        ],
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

  void _confirmDelete(BuildContext context, LibraryItem item) {
    final l10n = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteItem),
        content: Text('Êtes-vous sûr de vouloir supprimer cet élément (${item.fullCode})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Provider.of<LibraryProvider>(context, listen: false).deleteItem(item.code);
              Navigator.pop(context);
            },
            child: Text(l10n.deleteItem, style: const TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
