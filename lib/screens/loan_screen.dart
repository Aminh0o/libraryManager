import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../models/library_item.dart';
import '../models/member.dart';
import '../widgets/barcode_scanner_dialog.dart';
import '../l10n/app_localizations.dart';

class LoanScreen extends StatefulWidget {
  const LoanScreen({super.key});

  @override
  State<LoanScreen> createState() => _LoanScreenState();
}

class _LoanScreenState extends State<LoanScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // Checkout State
  Member? _selectedMember;
  LibraryItem? _selectedItem;
  final TextEditingController _memberSearchCtrl = TextEditingController();
  final TextEditingController _itemSearchCtrl = TextEditingController();

  // Checkin State
  final TextEditingController _checkinSearchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _memberSearchCtrl.dispose();
    _itemSearchCtrl.dispose();
    _checkinSearchCtrl.dispose();
    super.dispose();
  }

  void _scanItemForCheckout() async {
    final code = await showBarcodeScanner(context);
    if (code != null && mounted) {
      final provider = Provider.of<LibraryProvider>(context, listen: false);
      // Try to find by barcode or code
      final item = provider.items.firstWhere(
        (i) => i.code == code || i.barcode == code || i.fullCode == code,
        orElse: () => LibraryItem(code: '', codeType: '', designation: '', quantite: 0, emplacement: '', taux: 0, emplacementStock: '', status: ''),
      );
      
      if (item.code.isNotEmpty) {
        setState(() {
          _selectedItem = item;
          _itemSearchCtrl.text = item.designation;
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.itemNotFound)));
      }
    }
  }

  void _processCheckout() async {
    if (_selectedMember == null || _selectedItem == null) return;
    
    final provider = Provider.of<LibraryProvider>(context, listen: false);
    final l10n = AppLocalizations.of(context)!;
    try {
      await provider.checkOutItem(_selectedItem!, _selectedMember!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.loanSuccess)));
        setState(() {
          _selectedItem = null;
          _itemSearchCtrl.clear();
          // Keep member selected for bulk checkout
        });
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
    }
  }

  void _processCheckin() async {
     final code = _checkinSearchCtrl.text;
     if (code.isEmpty) return;

     final provider = Provider.of<LibraryProvider>(context, listen: false);
     final l10n = AppLocalizations.of(context)!;
     try {
       await provider.returnItem(code); // Logic needs to handle barcode lookup inside provider potentially
       if (mounted) {
         ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.returnSuccess)));
         _checkinSearchCtrl.clear();
       }
     } catch (e) {
       if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Erreur: $e')));
     }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.loanManagement),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.newLoan),
            Tab(text: l10n.returnLoan),
          ],
          labelColor: Colors.white,
        ),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCheckoutTab(context),
          _buildCheckinTab(context),
        ],
      ),
    );
  }

  Widget _buildCheckoutTab(BuildContext context) {
    final provider = Provider.of<LibraryProvider>(context);
    
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 1. Select Member
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(AppLocalizations.of(context)!.selectMember, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                   const SizedBox(height: 8),
                   if (_selectedMember != null)
                      ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(_selectedMember!.fullName),
                        subtitle: Text(_selectedMember!.memberId),
                        trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => setState(() => _selectedMember = null)),
                      )
                   else
                      Autocomplete<Member>(
                        displayStringForOption: (Member option) => option.fullName,
                        optionsBuilder: (TextEditingValue textEditingValue) {
                          if (textEditingValue.text == '') return const Iterable<Member>.empty();
                          return provider.members.where((Member option) {
                            return option.fullName.toLowerCase().contains(textEditingValue.text.toLowerCase()) ||
                                   option.memberId.contains(textEditingValue.text);
                          });
                        },
                        onSelected: (Member selection) {
                           setState(() => _selectedMember = selection);
                        },
                        fieldViewBuilder: (context, fieldTextEditingController, focusNode, onFieldSubmitted) {
                          return TextField(
                            controller: fieldTextEditingController,
                            focusNode: focusNode,
                            decoration: InputDecoration(
                              labelText: AppLocalizations.of(context)!.memberSearchHint,
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.search),
                            ),
                          );
                        },
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 2. Select Item
          Card(
             child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   Text(AppLocalizations.of(context)!.selectItem, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                   const SizedBox(height: 8),
                   Row(children: [
                     Expanded(
                       child: TextField(
                         controller: _itemSearchCtrl,
                         decoration: InputDecoration(
                           labelText: AppLocalizations.of(context)!.itemSearchHint,
                           border: const OutlineInputBorder(),
                         ),
                         readOnly: true, // Force use of scanner for now or implement autocomplete
                         onTap: _scanItemForCheckout,
                       ),
                     ),
                     IconButton(
                       icon: const Icon(Icons.camera_alt, size: 32, color: Colors.orange),
                       onPressed: _scanItemForCheckout,
                     ),
                   ]),
                   if (_selectedItem != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8.0),
                        child: Text('Sélectionné: ${_selectedItem!.designation} (${_selectedItem!.status})', 
                          style: TextStyle(color: _selectedItem!.status == 'Disponible' ? Colors.green : Colors.red, fontWeight: FontWeight.bold)
                        ),
                      ),
                ],
              ),
             ),
          ),
          const Spacer(),
          ElevatedButton.icon(
            onPressed: (_selectedMember != null && _selectedItem != null && _selectedItem!.status == 'Disponible') 
              ? _processCheckout 
              : null,
            icon: const Icon(Icons.check),
            label: Text(AppLocalizations.of(context)!.validateLoan),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.all(16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCheckinTab(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          const Icon(Icons.assignment_return, size: 64, color: Colors.orange),
          const SizedBox(height: 16),
          Text(l10n.scanToReturn, style: const TextStyle(fontSize: 18)),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _checkinSearchCtrl,
                  decoration: InputDecoration(
                     labelText: l10n.code,
                     border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: const Icon(Icons.camera_alt, size: 32, color: Colors.orange),
                onPressed: () async {
                   final code = await showBarcodeScanner(context);
                   if (code != null) {
                     setState(() => _checkinSearchCtrl.text = code);
                     _processCheckin(); // Auto submit
                   }
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _processCheckin,
            child: Text(l10n.confirmReturn),
          ),
        ],
      ),
    );
  }
}
