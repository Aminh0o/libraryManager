import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../providers/library_provider.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ScrollController _scrollController = ScrollController();
  String? _operationFilter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<LibraryProvider>(context, listen: false).loadHistory();
    });
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      Provider.of<LibraryProvider>(context, listen: false).loadHistory(more: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final provider = Provider.of<LibraryProvider>(context);
    
    final filteredHistory = _operationFilter == null 
        ? provider.history 
        : provider.history.where((e) => e['operation'] == _operationFilter).toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.historyTitle),
        actions: [
          DropdownButton<String?>(
            value: _operationFilter,
            hint: Text(l10n.filter),
            items: [
              DropdownMenuItem(value: null, child: Text(l10n.all)),
              DropdownMenuItem(value: 'ADD', child: Text(l10n.operationAdd)),
              DropdownMenuItem(value: 'UPDATE', child: Text(l10n.operationUpdate)),
              DropdownMenuItem(value: 'DELETE', child: Text(l10n.operationDelete)),
              DropdownMenuItem(value: 'WIPE', child: Text(l10n.operationWipe)),
            ],
            onChanged: (val) {
              setState(() {
                _operationFilter = val;
              });
            },
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: filteredHistory.isEmpty && !provider.isLoading
                ? Center(child: Text(l10n.noHistoryFound))
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: filteredHistory.length + (provider.hasMoreHistory ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == filteredHistory.length) {
                        return const Center(child: Padding(
                          padding: EdgeInsets.all(8.0),
                          child: CircularProgressIndicator(),
                        ));
                      }
                      
                      final entry = filteredHistory[index];
                      final dateTime = DateTime.parse(entry['timestamp']);
                      final dateStr = DateFormat('dd/MM/yyyy HH:mm:ss').format(dateTime);
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: ListTile(
                          leading: _getOperationIcon(entry['operation']),
                          title: Text(entry['details']),
                          subtitle: Text('$dateStr • ${l10n.by}: ${entry['user']}'),
                          trailing: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: _getOperationColor(entry['operation']).withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              _getOperationLabel(entry['operation'], l10n),
                              style: TextStyle(
                                color: _getOperationColor(entry['operation']),
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  String _getOperationLabel(String op, AppLocalizations l10n) {
    switch (op) {
      case 'ADD': return l10n.operationAdd;
      case 'UPDATE': return l10n.operationUpdate;
      case 'DELETE': return l10n.operationDelete;
      case 'WIPE': return l10n.operationWipe;
      default: return op;
    }
  }

  Icon _getOperationIcon(String op) {
    switch (op) {
      case 'ADD': return const Icon(Icons.add_circle, color: Colors.green);
      case 'UPDATE': return const Icon(Icons.edit, color: Colors.blue);
      case 'DELETE': return const Icon(Icons.delete, color: Colors.red);
      case 'WIPE': return const Icon(Icons.warning, color: Colors.orange);
      default: return const Icon(Icons.history);
    }
  }

  Color _getOperationColor(String op) {
    switch (op) {
      case 'ADD': return Colors.green;
      case 'UPDATE': return Colors.blue;
      case 'DELETE': return Colors.red;
      case 'WIPE': return Colors.orange;
      default: return Colors.grey;
    }
  }
}
