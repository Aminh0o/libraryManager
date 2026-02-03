import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:excel/excel.dart' as excel_pkg;
import '../models/library_item.dart';
import '../models/code_definition.dart';
import '../models/attribute_definition.dart';
import '../models/member.dart';
import '../models/loan.dart';
import '../services/repository.dart';
import '../services/database_service.dart';
import '../services/api_service.dart';
import '../services/http_server_service.dart';

class LibraryProvider with ChangeNotifier {
  List<LibraryItem> _items = [];
  List<LibraryItem> _filteredItems = [];
  List<Member> _members = [];
  List<Loan> _loans = [];
  List<CodeDefinition> _codeDefinitions = [];
  List<AttributeDefinition> _attributes = [];
  String _searchQuery = '';
  String? _statusFilter;
  String? _codeTypeFilter;
  bool _isLoading = false;
  String? _errorMessage;
  Locale _locale = const Locale('fr'); // Default to French for Algeria
  
  // LAN Sync Settings
  bool _isHost = true;
  String _hostIp = '192.168.1.100';
  LibraryRepository? _repository;
  HttpServerService? _server;
  Timer? _backupTimer;
  Timer? _healthTimer;
  Timer? _immediateBackupTimer;
  bool _healthCheckBusy = false;
  
  bool _isConnected = true;
  String _adminPassword = '';
  
  // Pagination State
  int _inventoryPage = 0;
  final int _pageSize = 20;
  bool _hasMoreInventory = true;
  
  List<Map<String, dynamic>> _history = [];
  int _historyPage = 0;
  bool _hasMoreHistory = true;
  String _lastDbVersion = '0';
  Map<String, dynamic> _stats = {};
  final Map<String, DateTime> _activeClients = {};

  // Getters
  List<LibraryItem> get items => (_searchQuery.isEmpty && _statusFilter == null && _codeTypeFilter == null) ? _items : _filteredItems;
  List<LibraryItem> get allItems => _items;
  Locale get locale => _locale;
  bool get isHost => _isHost;
  String get hostIp => _hostIp;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  String? get statusFilter => _statusFilter;
  String? get codeTypeFilter => _codeTypeFilter;
  bool get isConnected => _isConnected;
  bool get hasAdminPassword => _adminPassword.isNotEmpty;
  List<CodeDefinition> get codeDefinitions => _codeDefinitions;
  List<AttributeDefinition> get attributes => _attributes;
  List<Member> get members => _members;
  List<Loan> get loans => _loans;
  List<Loan> get activeLoans => _loans.where((l) => !l.isReturned).toList();
  
  List<String> get locations => _attributes.where((a) => a.type == 'LOCATION').map((a) => a.value).toList();
  List<String> get statuses => _attributes.where((a) => a.type == 'STATUS').map((a) => a.value).toList();
  
  // Pagination & History Getters
  int get inventoryPage => _inventoryPage;
  bool get hasMoreInventory => _hasMoreInventory;
  List<Map<String, dynamic>> get history => _history;
  bool get hasMoreHistory => _hasMoreHistory;
  int get pageSize => _pageSize;
  List<String> get activeClients => _activeClients.keys.where((ip) => DateTime.now().difference(_activeClients[ip]!).inMinutes < 5).toList();

  LibraryProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _isHost = prefs.getBool('isHost') ?? true;
    _hostIp = prefs.getString('hostIp') ?? '192.168.1.100';
    
    // Load saved locale
    final savedLocale = prefs.getString('locale') ?? 'fr';
    _locale = Locale(savedLocale);

    // Load admin password
    _adminPassword = prefs.getString('adminPassword') ?? '';
    
    await _initRepository();
  }

  Future<String?> getLocalIp() async {
    try {
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        includeLinkLocal: false,
        type: InternetAddressType.IPv4,
      );

      final privateAddresses = <String>[];
      final otherAddresses = <String>[];

      for (final interface in interfaces) {
        for (final addr in interface.addresses) {
          final ip = addr.address;
          if (_isPrivateIpv4(ip)) {
            privateAddresses.add(ip);
          } else {
            otherAddresses.add(ip);
          }
        }
      }

      if (privateAddresses.isNotEmpty) return privateAddresses.first;
      if (otherAddresses.isNotEmpty) return otherAddresses.first;
    } catch (e) {
      debugPrint('Error getting local IP: $e');
    }
    return null;
  }

  bool _isPrivateIpv4(String ip) {
    if (ip.startsWith('10.')) return true;
    if (ip.startsWith('192.168.')) return true;
    final parts = ip.split('.');
    if (parts.length == 4) {
      final first = int.tryParse(parts[0]);
      final second = int.tryParse(parts[1]);
      if (first == 172 && second != null && second >= 16 && second <= 31) {
        return true;
      }
    }
    return false;
  }

  Future<void> _initRepository() async {
    if (_repository is ApiService) {
      try {
        (_repository as ApiService).close();
      } catch (_) {}
    }

    if (!_isHost && _server != null) {
      try {
        await _server!.stopServer();
      } catch (_) {}
      _server = null;
    }

    if (_isHost) {
      _repository = DatabaseService();
      if (_server == null) {
        _server = HttpServerService();
        _server!.startServer(onActivity: updateClientActivity).catchError((e) => debugPrint('Server error: $e'));
      }
    } else {
      _repository = ApiService(hostIp: _hostIp);
      _server = null;
    }
    await _loadItems();
    await _loadMembers();
    await _loadLoans();
    _startHealthCheck();
    
    // Start periodic backup if host
    if (_isHost) {
      _backupTimer?.cancel();
      _backupTimer = Timer.periodic(const Duration(minutes: 30), (timer) {
        backupData().catchError((e) => debugPrint('Auto-backup error: $e'));
      });
    } else {
      _backupTimer?.cancel();
    }
  }

  Future<void> updateSettings(bool isHost, String hostIp) async {
    _isHost = isHost;
    _hostIp = hostIp;
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isHost', isHost);
    await prefs.setString('hostIp', hostIp);

    await _initRepository();
    notifyListeners();
  }

  void setLocale(Locale locale) async {
    _locale = locale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('locale', locale.languageCode);
    notifyListeners();
  }

  // Password Management
  bool checkPassword(String password) {
    if (_adminPassword.isEmpty) return true; // No password set
    
    // Check if stored password is a SHA-256 hash (64 chars hex)
    final isHash = _adminPassword.length == 64 && RegExp(r'^[a-f0-9]+$').hasMatch(_adminPassword);
    
    if (isHash) {
      final inputHash = sha256.convert(utf8.encode(password)).toString();
      return _adminPassword == inputHash;
    } else {
      // Temporary plain-text support for migration
      return _adminPassword == password;
    }
  }

  Future<void> changePassword(String newPassword) async {
    final hashed = sha256.convert(utf8.encode(newPassword)).toString();
    _adminPassword = hashed;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('adminPassword', hashed);
    notifyListeners();
  }

  // Connectivity Health Check
  void _startHealthCheck() {
    _healthTimer?.cancel();
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (timer) async {
      if (_healthCheckBusy) return;
      _healthCheckBusy = true;
      try {
      if (_isHost) {
        // Host is always "connected" to itself
        if (!_isConnected) {
          _isConnected = true;
          notifyListeners();
        }
      } else {
        try {
          final api = _repository as ApiService;
          final version = await api.getDbVersion().timeout(const Duration(seconds: 3));
          
          if (!_isConnected) {
            _isConnected = true;
            _lastDbVersion = version;
            await _reloadAll();
            notifyListeners();
          } else if (version != _lastDbVersion) {
            _lastDbVersion = version;
            await _reloadAll();
          }
        } catch (_) {
          if (_isConnected) {
            _isConnected = false;
            notifyListeners();
          }
        }
      }
      } finally {
        _healthCheckBusy = false;
      }
    });
  }

  Future<void> _reloadAll() async {
    await _loadItems();
    await _loadMembers();
    await _loadLoans();
  }

  Future<void> _loadItems({bool more = false}) async {
    if (_repository == null) return;
    if (more && !_hasMoreInventory) return;
    
    _isLoading = true;
    _errorMessage = null;
    if (!more) {
      _inventoryPage = 0;
      _items = [];
    }
    notifyListeners();
    
    try {
      final newItems = await _repository!.getItems(
        limit: _pageSize, 
        offset: _inventoryPage * _pageSize
      );
      
      if (more) {
        _items.addAll(newItems);
      } else {
        _items = newItems;
      }
      
      _hasMoreInventory = newItems.length == _pageSize;
      if (_hasMoreInventory) _inventoryPage++;

      // Load code definitions
      final defs = await _repository!.getCodeDefinitions();
      _codeDefinitions = defs.map((d) => CodeDefinition.fromMap(d)).toList();

      // Load attribute definitions
      final attrDefs = await _repository!.getAttributeDefinitions(null);
      _attributes = attrDefs.map((a) => AttributeDefinition.fromMap(a)).toList();
      
      _applyFilter();
      
      // Update Stats
      _stats = await _repository!.getStats();
    } catch (e) {
      _errorMessage = 'Erreur de chargement: $e';
      debugPrint(_errorMessage);
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoreItems() => _loadItems(more: true);

  // History Pagination
  Future<void> loadHistory({bool more = false}) async {
    if (_repository == null) return;
    if (more && !_hasMoreHistory) return;

    if (!more) {
      _historyPage = 0;
      _history = [];
    }
    
    try {
      final newHistory = await _repository!.getHistory(
        limit: _pageSize,
        offset: _historyPage * _pageSize
      );
      
      if (more) {
        _history.addAll(newHistory);
      } else {
        _history = newHistory;
      }
      
      _hasMoreHistory = newHistory.length == _pageSize;
      if (_hasMoreHistory) _historyPage++;
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading history: $e');
    }
  }

  Future<void> _logOperation(String operation, String details) async {
    if (!_isHost) return;
    final entry = {
      'timestamp': DateTime.now().toIso8601String(),
      'operation': operation,
      'details': details,
      'user': _isHost ? 'Host' : 'Client ($hostIp)',
    };
    await _repository?.addHistoryEntry(entry);
  }

  void updateClientActivity(String clientIp) {
    _activeClients[clientIp] = DateTime.now();
    notifyListeners();
  }

  // Code Definition Management
  Future<void> addCodeDefinition(String prefix, String label) async {
    if (_repository == null) return;
    await _repository!.addCodeDefinition(prefix, label);
    await _logOperation('ADD_VAR', 'Variable ajoutée: $prefix ($label)');
    await reload();
    _triggerImmediateBackup();
  }

  Future<void> updateCodeDefinition(String oldPrefix, String newPrefix, String label) async {
    if (_repository == null) return;
    await _repository!.updateCodeDefinition(oldPrefix, newPrefix, label);
    await _logOperation('UPDATE_VAR', 'Variable modifiée: $oldPrefix -> $newPrefix ($label)');
    await reload();
    _triggerImmediateBackup();
  }

  Future<void> deleteCodeDefinition(String prefix) async {
    if (_repository == null) return;
    await _repository!.deleteCodeDefinition(prefix);
    await _logOperation('DELETE_VAR', 'Variable supprimée: $prefix');
    await reload();
    _triggerImmediateBackup();
  }

  // Attribute Definition Management
  Future<void> addAttributeDefinition(String type, String value) async {
    if (_repository == null) return;
    await _repository!.addAttributeDefinition(type, value);
    await _logOperation('ADD_ATTR', 'Attribut ajouté ($type): $value');
    await reload();
    _triggerImmediateBackup();
  }

  Future<void> deleteAttributeDefinition(int id) async {
    if (_repository == null) return;
    await _repository!.deleteAttributeDefinition(id);
    await _logOperation('DELETE_ATTR', 'Attribut supprimé (ID: $id)');
    await reload();
    _triggerImmediateBackup();
  }

  void _triggerImmediateBackup() {
    if (_isHost) {
      _immediateBackupTimer?.cancel();
      _immediateBackupTimer = Timer(const Duration(seconds: 15), () {
        backupData().catchError((e) => debugPrint('Immediate backup error: $e'));
      });
    }
  }

  Future<void> reload() => _loadItems();

  void search(String query) {
    _searchQuery = query;
    _applyFilter();
    notifyListeners();
  }

  void filterByStatus(String? status) {
    _statusFilter = status;
    _applyFilter();
    notifyListeners();
  }

  void filterByCodeType(String? codeType) {
    _codeTypeFilter = codeType;
    _applyFilter();
    notifyListeners();
  }

  void clearFilters() {
    _statusFilter = null;
    _codeTypeFilter = null;
    _searchQuery = '';
    _applyFilter();
    notifyListeners();
  }

  void _applyFilter() {
    _filteredItems = _items.where((item) {
      final matchesSearch = _searchQuery.isEmpty ||
          item.designation.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.code.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          (item.barcode != null && item.barcode!.toLowerCase().contains(_searchQuery.toLowerCase())) ||
          item.fullCode.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.emplacement.toLowerCase().contains(_searchQuery.toLowerCase());
      
      final matchesStatus = _statusFilter == null || item.status == _statusFilter;
      final matchesCodeType = _codeTypeFilter == null || item.codeType == _codeTypeFilter;
      
      return matchesSearch && matchesStatus && matchesCodeType;
    }).toList();
  }

  Future<LibraryItem?> findItemByBarcode(String barcode) async {
    if (_repository == null) return null;
    return await _repository!.getItemByBarcode(barcode);
  }

  /// Generate the next code for a given code type
  Future<String> generateNextCode(String codeType) async {
    if (_repository is DatabaseService) {
      return await (_repository as DatabaseService).generateNextCode(codeType);
    }
    // For client mode, generate based on local items
    final typeItems = _items.where((i) => i.codeType == codeType).toList();
    if (typeItems.isEmpty) return '0001';
    
    int maxCode = 0;
    for (final item in typeItems) {
      final parsed = int.tryParse(item.code) ?? 0;
      if (parsed > maxCode) maxCode = parsed;
    }
    return (maxCode + 1).toString().padLeft(4, '0');
  }

  Future<void> addItem(LibraryItem item) async {
    await _repository?.addItem(item);
    await _logOperation('ADD', 'Ajout de ${item.fullCode}: ${item.designation}');
    await _loadItems();
    _triggerImmediateBackup();
  }

  Future<void> updateItem(LibraryItem item) async {
    await _repository?.updateItem(item);
    await _logOperation('UPDATE', 'Modification de ${item.fullCode}');
    await _loadItems();
    _triggerImmediateBackup();
  }

  Future<void> deleteItem(String code) async {
    await _repository?.deleteItem(code);
    await _logOperation('DELETE', 'Suppression de $code');
    await _loadItems();
    _triggerImmediateBackup();
  }

  Future<void> updateItemStatus(LibraryItem item, String newStatus) async {
    final updatedItem = LibraryItem(
      code: item.code,
      barcode: item.barcode,
      codeType: item.codeType,
      designation: item.designation,
      quantite: item.quantite,
      emplacement: item.emplacement,
      taux: item.taux,
      emplacementStock: item.emplacementStock,
      status: newStatus,
    );
    await updateItem(updatedItem);
  }

  // Statistics getters
  int get totalItems => _items.length;
  int get totalQuantity => _stats['totalQuantity'] ?? 0;
  double get totalValue => (_stats['totalValue'] ?? 0.0).toDouble();
  int get onLoanCount => _stats['onLoan'] ?? 0;
  
  int getCountByStatus(String status) => _items.where((i) => i.status == status).length;
  int getCountByCodeType(String codeType) {
    if (_stats['typeDist'] == null) return 0;
    final dist = _stats['typeDist'] as Map;
    return dist[codeType] ?? 0;
  }

  Future<void> backupData() async {
    if (_repository is DatabaseService) {
      await (_repository as DatabaseService).createAutoBackup();
    } else {
      throw Exception('Sauvegarde disponible uniquement en mode Hôte');
    }
  }

  Future<void> restoreData(String path) async {
    if (_repository is DatabaseService) {
      await (_repository as DatabaseService).restoreDatabase(path);
      await reload();
    } else {
      throw Exception('Restauration disponible uniquement en mode Hôte');
    }
  }

  Future<void> clearAllData() async {
    if (_repository is DatabaseService) {
      await (_repository as DatabaseService).clearAllData();
      await _logOperation('WIPE', 'Effacement complet de la base de données');
      await _loadItems();
      _triggerImmediateBackup();
    } else {
      throw Exception('Effacement disponible uniquement en mode Hôte');
    }
  }

  Future<void> importItemsFromExcel(String filePath) async {
    if (_repository == null || !_isHost) {
      throw Exception('Importation disponible uniquement en mode Hôte');
    }

    final bytes = File(filePath).readAsBytesSync();
    final excel = excel_pkg.Excel.decodeBytes(bytes);
    final List<LibraryItem> itemsToImport = [];

    for (var table in excel.tables.keys) {
      final sheet = excel.tables[table]!;
      if (sheet.maxRows <= 1) continue; // Skip empty sheets or headers only

      // Expecting columns: 0:Code, 1:Type, 2:Designation, 3:Quantite, 4:Emplacement, 5:Prix, 6:Stock, 7:Statut
      for (int i = 1; i < sheet.maxRows; i++) {
        final row = sheet.rows[i];
        if (row.isEmpty || row.length < 3) continue;

        String? getString(int index) {
          if (index >= row.length || row[index] == null) return null;
          final value = row[index]!.value;
          if (value == null) return null;
          return value.toString().trim();
        }

        int getInt(int index) {
          final s = getString(index);
          if (s == null) return 0;
          return int.tryParse(s.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        }

        double getDouble(int index) {
          final s = getString(index);
          if (s == null) return 0.0;
          return double.tryParse(s.replaceAll(RegExp(r'[^0-9.]'), '')) ?? 0.0;
        }

        final code = getString(0);
        final type = getString(1) ?? 'LIV';
        final designation = getString(2);

        if (code == null || designation == null) continue;

        itemsToImport.add(LibraryItem(
          code: code,
          barcode: getString(8), // Barcode at index 8
          codeType: type,
          designation: designation,
          quantite: getInt(3),
          emplacement: getString(4) ?? '',
          taux: getDouble(5),
          emplacementStock: getString(6) ?? '',
          status: getString(7) ?? ItemStatus.disponible,
        ));
      }
    }

    if (itemsToImport.isNotEmpty) {
      final dbService = _repository as DatabaseService;
      await dbService.batchInsertItems(itemsToImport);
      await _logOperation('IMPORT', '${itemsToImport.length} éléments importés depuis Excel');
      await reload();
      _triggerImmediateBackup();
    }
  }

  Future<String> exportToCsv() async {
    final buffer = StringBuffer();
    // CSV Header with French labels
    buffer.writeln('Code,Barre,Type,Designation,Quantite,Emplacement,Prix,Stock,Statut');
    
    for (final item in _items) {
      buffer.writeln('${item.code},${item.barcode ?? ""},${item.codeType},${item.designation},${item.quantite},${item.emplacement},${item.taux},${item.emplacementStock},${item.status}');
    }
    // Save to Documents
    final docsDir = await getApplicationDocumentsDirectory();
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final filePath = p.join(docsDir.path, 'bibliotheque_export_$timestamp.csv');
    final file = File(filePath);
    await file.writeAsString(buffer.toString());
    
    return filePath;
  }

  // Member Management
  Future<void> _loadMembers() async {
    if (_repository == null) return;
    try {
      _members = await _repository!.getMembers();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading members: $e');
    }
  }

  Future<void> addMember(Member member) async {
    if (_repository == null) return;
    
    // Auto-generate member ID if using DatabaseService
    String finalMemberId = member.memberId;
    if (_repository is DatabaseService && (member.memberId.isEmpty || member.memberId == 'AUTO')) {
      finalMemberId = await (_repository as DatabaseService).generateMemberID();
    }
    
    final memberWithId = Member(
      id: member.id,
      firstName: member.firstName,
      lastName: member.lastName,
      email: member.email,
      phone: member.phone,
      memberId: finalMemberId,
      registeredAt: member.registeredAt,
    );
    
    await _repository!.addMember(memberWithId);
    await _loadMembers();
    await _logOperation('ADD_MEMBER', 'Ajout membre: ${memberWithId.fullName}');
    _triggerImmediateBackup();
  }

  Future<void> updateMember(Member member) async {
    if (_repository == null) return;
    await _repository!.updateMember(member);
    await _loadMembers();
    _triggerImmediateBackup();
  }

  Future<void> deleteMember(String memberId) async {
    if (_repository == null) return;
    await _repository!.deleteMember(memberId);
    await _loadMembers();
    await _logOperation('DEL_MEMBER', 'Suppression membre: $memberId');
    _triggerImmediateBackup();
  }

  // Loan Management
  Future<void> _loadLoans() async {
    if (_repository == null) return;
    try {
      _loans = await _repository!.getLoans();
      notifyListeners();
    } catch (e) {
      debugPrint('Error loading loans: $e');
    }
  }

  Future<void> checkOutItem(LibraryItem item, Member member, {int durationDays = 15}) async {
    if (_repository == null) return;
    
    // Check if limit reached (optional logic)
    // Check if item is available
    if (item.status != 'Disponible') {
      throw Exception('Cet article n\'est pas disponible.');
    }

    final loan = Loan(
      itemCode: item.code,
      memberId: member.memberId,
      memberName: member.fullName,
      itemTitle: item.designation,
      loanDate: DateTime.now(),
      dueDate: DateTime.now().add(Duration(days: durationDays)),
    );

    await _repository!.addLoan(loan);
    await _loadLoans();
    await _loadItems(); // Refresh item status
    await _logOperation('CHECKOUT', 'Emprunt: ${item.code} par ${member.fullName}');
    _triggerImmediateBackup();
  }

  Future<void> returnItem(String itemCode) async {
    if (_repository == null) return;
    
    // Find active loan for this item
    final activeLoan = _loans.firstWhere(
      (l) => l.itemCode == itemCode && !l.isReturned,
      orElse: () => throw Exception('Aucun emprunt actif trouvé pour cet article.'),
    );

    final returnedLoan = Loan(
      id: activeLoan.id,
      itemCode: activeLoan.itemCode,
      memberId: activeLoan.memberId,
      memberName: activeLoan.memberName,
      itemTitle: activeLoan.itemTitle,
      loanDate: activeLoan.loanDate,
      dueDate: activeLoan.dueDate,
      returnDate: DateTime.now(),
      status: 'Returned',
    );

    await _repository!.updateLoan(returnedLoan);
    await _loadLoans();
    await _loadItems(); // Refresh item status
    await _logOperation('CHECKIN', 'Retour: $itemCode');
    _triggerImmediateBackup();
  }

  Future<void> renewLoan(Loan loan, {int additionalDays = 15}) async {
     if (_repository == null) return;
     
     final renewedLoan = Loan(
      id: loan.id,
      itemCode: loan.itemCode,
      memberId: loan.memberId,
      memberName: loan.memberName,
      itemTitle: loan.itemTitle,
      loanDate: loan.loanDate,
      dueDate: loan.dueDate.add(Duration(days: additionalDays)),
      returnDate: null,
      status: 'Active',
    );

    await _repository!.updateLoan(renewedLoan);
    await _loadLoans();
    await _logOperation('RENEW', 'Renouvellement: ${loan.itemCode}');
  }

  @override
  void dispose() {
    _backupTimer?.cancel();
    _healthTimer?.cancel();
    _immediateBackupTimer?.cancel();
    _healthCheckBusy = false;
    if (_repository is ApiService) {
      try {
        (_repository as ApiService).close();
      } catch (_) {}
    }
    if (_server != null) {
      _server!.stopServer().catchError((_) {});
    }
    super.dispose();
  }
}

