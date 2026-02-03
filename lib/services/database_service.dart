import 'dart:io';
import 'package:path/path.dart';
import 'package:flutter/foundation.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path_provider/path_provider.dart';
import '../models/library_item.dart';
import '../models/member.dart';
import '../models/loan.dart';
import 'repository.dart';

class DatabaseService implements LibraryRepository {
  static final DatabaseService _instance = DatabaseService._internal();
  static Database? _database;

  factory DatabaseService() {
    return _instance;
  }

  DatabaseService._internal();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    final String path = join(documentsDirectory.path, 'library_manager.db');

    return await openDatabase(
      path,
      version: 9,
      onCreate: _onCreate,
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute("ALTER TABLE library_items ADD COLUMN status TEXT DEFAULT 'Disponible'");
        }
        if (oldVersion < 3) {
          await db.execute("ALTER TABLE library_items ADD COLUMN code_type TEXT DEFAULT 'LIV'");
          // Update existing status values to French
          await db.execute("UPDATE library_items SET status = 'Disponible' WHERE status = 'Available'");
          await db.execute("UPDATE library_items SET status = 'Emprunté' WHERE status = 'Borrowed'");
          await db.execute("UPDATE library_items SET status = 'Payé' WHERE status = 'Paid'");
        }
        if (oldVersion < 4) {
          await db.execute('''
            CREATE TABLE code_definitions(
              prefix TEXT PRIMARY KEY,
              label TEXT
            )
          ''');
          
          // Seed defaults
          final defaults = [
            {'prefix': 'LIV', 'label': 'Livre'},
            {'prefix': 'REV', 'label': 'Revue'},
            {'prefix': 'THE', 'label': 'Thèse'},
            {'prefix': 'MEM', 'label': 'Mémoire'},
            {'prefix': 'PER', 'label': 'Périodique'},
            {'prefix': 'DOC', 'label': 'Document'},
          ];
          
          for (final def in defaults) {
            await db.insert('code_definitions', def);
          }
        }
        if (oldVersion < 5) {
          await db.execute('''
            CREATE TABLE history(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              timestamp TEXT,
              operation TEXT,
              details TEXT,
              user TEXT
            )
          ''');
        }
        if (oldVersion < 6) {
          await db.execute("ALTER TABLE library_items ADD COLUMN barcode TEXT");
        }
        if (oldVersion < 7) {
          await db.execute('''
            CREATE TABLE metadata(
              key TEXT PRIMARY KEY,
              value TEXT
            )
          ''');
          await db.insert('metadata', {'key': 'db_version', 'value': DateTime.now().millisecondsSinceEpoch.toString()});
        }
        if (oldVersion < 8) {
          await db.execute('''
            CREATE TABLE attribute_definitions(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT,
              value TEXT
            )
          ''');
          
          // Seed default statuses - These are System Enums
          final statuses = ['Disponible', 'Emprunté', 'En Réparation', 'Perdu', 'Archivé'];
          for (final status in statuses) {
            await db.insert('attribute_definitions', {'type': 'STATUS', 'value': status});
          }
        }
        if (oldVersion < 9) {
          await db.execute('''
            CREATE TABLE members(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              first_name TEXT,
              last_name TEXT,
              email TEXT,
              phone TEXT,
              member_id TEXT UNIQUE,
              registered_at TEXT
            )
          ''');
          
          await db.execute('''
            CREATE TABLE loans(
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              item_code TEXT,
              member_id TEXT,
              member_name TEXT,
              item_title TEXT,
              loan_date TEXT,
              due_date TEXT,
              return_date TEXT,
              status TEXT
            )
          ''');
        }
      },
    );
  }

  Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
          CREATE TABLE library_items(
            code TEXT PRIMARY KEY,
            barcode TEXT,
            code_type TEXT DEFAULT 'LIV',
            designation TEXT,
            quantite INTEGER,
            emplacement TEXT,
            taux REAL,
            emplacement_stock TEXT,
            status TEXT DEFAULT 'Disponible'
          )
        ''');

    await db.execute('''
          CREATE TABLE code_definitions(
            prefix TEXT PRIMARY KEY,
            label TEXT
          )
        ''');

    // Seed defaults
    final defaults = [
      {'prefix': 'LIV', 'label': 'Livre'},
      {'prefix': 'REV', 'label': 'Revue'},
      {'prefix': 'THE', 'label': 'Thèse'},
      {'prefix': 'MEM', 'label': 'Mémoire'},
      {'prefix': 'PER', 'label': 'Périodique'},
      {'prefix': 'DOC', 'label': 'Document'},
    ];

    for (final def in defaults) {
      await db.insert('code_definitions', def);
    }

    await db.execute('''
          CREATE TABLE attribute_definitions(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT,
            value TEXT
          )
        ''');

    // Seed defaults for attributes
    final statuses = ['Disponible', 'Emprunté', 'En Réparation', 'Perdu', 'Archivé'];
    for (final status in statuses) {
      await db.insert('attribute_definitions', {'type': 'STATUS', 'value': status});
    }

    await db.execute('''
          CREATE TABLE history(
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            timestamp TEXT,
            operation TEXT,
            details TEXT,
            user TEXT
          )
        ''');
    
    await db.execute('''
          CREATE TABLE metadata(
            key TEXT PRIMARY KEY,
            value TEXT
          )
        ''');
    
    await db.execute('''
      CREATE TABLE members(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        first_name TEXT,
        last_name TEXT,
        email TEXT,
        phone TEXT,
        member_id TEXT UNIQUE,
        registered_at TEXT
      )
    ''');
    
    await db.execute('''
      CREATE TABLE loans(
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        item_code TEXT,
        member_id TEXT,
        member_name TEXT,
        item_title TEXT,
        loan_date TEXT,
        due_date TEXT,
        return_date TEXT,
        status TEXT
      )
    ''');
    await db.insert('metadata', {'key': 'db_version', 'value': DateTime.now().millisecondsSinceEpoch.toString()});
  }

  /// Generates the next sequential code for a given code type
  Future<String> generateNextCode(String codeType) async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT code FROM library_items WHERE code_type = ? ORDER BY CAST(code AS INTEGER) DESC LIMIT 1",
      [codeType],
    );
    
    int nextNumber = 1;
    if (result.isNotEmpty) {
      final lastCode = result.first['code'] as String;
      final parsed = int.tryParse(lastCode);
      if (parsed != null) {
        nextNumber = parsed + 1;
      }
    }
    
    // Format with leading zeros (e.g., 0001, 0002)
    return nextNumber.toString().padLeft(4, '0');
  }

  Future<void> insertItem(LibraryItem item) async {
    await addItem(item);
  }
  
  @override
  Future<void> addItem(LibraryItem item) async {
    final db = await database;
    await db.insert('library_items', item.toMap());
    await _updateDbVersion();
  }

  Future<void> batchInsertItems(List<LibraryItem> items) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final item in items) {
        await txn.insert(
          'library_items', 
          item.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
    await _updateDbVersion();
  }

  @override
  Future<LibraryItem?> getItemByBarcode(String barcode) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'library_items',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );

    if (maps.isEmpty) return null;
    return LibraryItem.fromMap(maps.first);
  }

  Future<void> _updateDbVersion() async {
    final db = await database;
    await db.insert(
      'metadata', 
      {'key': 'db_version', 'value': DateTime.now().millisecondsSinceEpoch.toString()},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<String> getDbVersion() async {
    final db = await database;
    final results = await db.query('metadata', where: 'key = ?', whereArgs: ['db_version']);
    if (results.isNotEmpty) {
      return results.first['value'] as String;
    }
    return '0';
  }

  @override
  Future<List<LibraryItem>> getItems({int limit = 1000, int offset = 0}) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'library_items', 
      orderBy: 'code_type, code',
      limit: limit,
      offset: offset,
    );
    return List.generate(maps.length, (i) {
      return LibraryItem.fromMap(maps[i]);
    });
  }

  @override
  Future<void> updateItem(LibraryItem item) async {
    final db = await database;
    await db.update(
      'library_items',
      item.toMap(),
      where: 'code = ?',
      whereArgs: [item.code],
    );
    await _updateDbVersion();
  }

  @override
  Future<void> deleteItem(String code) async {
    final db = await database;
    await db.delete(
      'library_items',
      where: 'code = ?',
      whereArgs: [code],
    );
    await _updateDbVersion();
  }

  // History Methods
  @override
  Future<List<Map<String, dynamic>>> getHistory({int limit = 20, int offset = 0}) async {
    final db = await database;
    return await db.query(
      'history',
      orderBy: 'timestamp DESC',
      limit: limit,
      offset: offset,
    );
  }

  @override
  Future<void> addHistoryEntry(Map<String, dynamic> entry) async {
    final db = await database;
    await db.insert('history', entry);
    
    // Optional: Cleanup old history (e.g., keep last 1000)
    await db.execute("DELETE FROM history WHERE id IN (SELECT id FROM history ORDER BY timestamp DESC LIMIT -1 OFFSET 1000)");
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    final db = await database;
    
    final totalDocs = await db.rawQuery('SELECT SUM(quantite) as total FROM library_items');
    final totalValue = await db.rawQuery('SELECT SUM(quantite * taux) as total FROM library_items');
    // We use the French label since it's the one stored in DB by default
    final onLoan = await db.rawQuery('SELECT SUM(quantite) as total FROM library_items WHERE status = ?', ['Emprunté']);
    
    // Type distributions
    final typeCounts = await db.rawQuery('SELECT code_type, SUM(quantite) as count FROM library_items GROUP BY code_type');
    
    return {
      'totalQuantity': totalDocs.first['total'] ?? 0,
      'totalValue': (totalValue.first['total'] as num? ?? 0.0).toDouble(),
      'onLoan': onLoan.first['total'] ?? 0,
      'typeDist': { for (var row in typeCounts) row['code_type'] as String: row['count'] ?? 0 },
    };
  }

  // Code Definition Methods
  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async {
    final db = await database;
    return await db.query('code_definitions');
  }

  @override
  Future<void> addCodeDefinition(String prefix, String label) async {
    final db = await database;
    await db.insert('code_definitions', {'prefix': prefix, 'label': label});
    await _updateDbVersion();
  }

  @override
  Future<void> updateCodeDefinition(String oldPrefix, String newPrefix, String label) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'code_definitions',
        {'prefix': newPrefix, 'label': label},
        where: 'prefix = ?',
        whereArgs: [oldPrefix],
      );
      
      if (oldPrefix != newPrefix) {
        await txn.update(
          'library_items',
          {'code_type': newPrefix},
          where: 'code_type = ?',
          whereArgs: [oldPrefix],
        );
      }
    });
    await _updateDbVersion();
  }

  @override
  Future<void> deleteCodeDefinition(String prefix) async {
    final db = await database;
    await db.delete('code_definitions', where: 'prefix = ?', whereArgs: [prefix]);
    await _updateDbVersion();
  }

  // Attribute Definitions Implementation
  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(String? type) async {
    final db = await database;
    if (type != null) {
      return await db.query('attribute_definitions', where: 'type = ?', whereArgs: [type]);
    }
    return await db.query('attribute_definitions');
  }

  @override
  Future<void> addAttributeDefinition(String type, String value) async {
    final db = await database;
    await db.insert('attribute_definitions', {'type': type, 'value': value});
    await _updateDbVersion();
  }

  @override
  Future<void> deleteAttributeDefinition(int id) async {
    final db = await database;
    await db.delete('attribute_definitions', where: 'id = ?', whereArgs: [id]);
    await _updateDbVersion();
  }

  /// Wipes all data and resets to defaults
  Future<void> clearAllData() async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('library_items');
      await txn.delete('code_definitions');
      
      // Seed defaults
      final defaults = [
        {'prefix': 'LIV', 'label': 'Livre'},
        {'prefix': 'REV', 'label': 'Revue'},
        {'prefix': 'THE', 'label': 'Thèse'},
        {'prefix': 'MEM', 'label': 'Mémoire'},
        {'prefix': 'PER', 'label': 'Périodique'},
        {'prefix': 'DOC', 'label': 'Document'},
      ];
      
      for (final def in defaults) {
        await txn.insert('code_definitions', def);
      }
    });
  }

  /// Get count of items by code type
  Future<Map<String, int>> getCountByCodeType() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT code_type, COUNT(*) as count FROM library_items GROUP BY code_type"
    );
    
    final Map<String, int> counts = {};
    for (final row in result) {
      counts[row['code_type'] as String] = row['count'] as int;
    }
    return counts;
  }

  /// Get count of items by status
  Future<Map<String, int>> getCountByStatus() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT status, COUNT(*) as count FROM library_items GROUP BY status"
    );
    
    final Map<String, int> counts = {};
    for (final row in result) {
      counts[row['status'] as String] = row['count'] as int;
    }
    return counts;
  }

  Future<String> getDatabasePath() async {
    final Directory documentsDirectory = await getApplicationDocumentsDirectory();
    return join(documentsDirectory.path, 'library_manager.db');
  }

  Future<void> backupDatabase(String destinationPath) async {
    final dbPath = await getDatabasePath();
    final dbFile = File(dbPath);
    await dbFile.copy(destinationPath);
  }

  Future<void> restoreDatabase(String sourcePath) async {
    final dbPath = await getDatabasePath();
    if (_database != null && _database!.isOpen) {
       await _database!.close();
       _database = null; 
    }
    
    final sourceFile = File(sourcePath);
    await sourceFile.copy(dbPath);
  }

  Future<void> createAutoBackup() async {
    final docsDir = await getApplicationDocumentsDirectory();
    final backupDir = Directory(join(docsDir.path, 'library_backups'));
    if (!await backupDir.exists()) {
      await backupDir.create(recursive: true);
    }
    
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final backupPath = join(backupDir.path, 'library_backup_$timestamp.db');
    
    await backupDatabase(backupPath);

    // Cleanup: keep only last 10 backups
    try {
      final List<FileSystemEntity> backups = await backupDir.list().toList();
      backups.sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));
      
      if (backups.length > 10) {
        for (var i = 10; i < backups.length; i++) {
          await backups[i].delete();
        }
      }
    } catch (e) {
      debugPrint('Error cleaning up backups: $e');
    }
  }

  // Members
  @override
  Future<List<Member>> getMembers() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('members');
    return List.generate(maps.length, (i) => Member.fromMap(maps[i]));
  }

  Future<String> generateMemberID() async {
    final db = await database;
    final year = DateTime.now().year.toString().substring(2); // Last 2 digits of year
    
    // Get the count of members registered this year
    final yearPrefix = year;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM members WHERE member_id LIKE ?",
      ['$yearPrefix%']
    );
    
    final count = (result.first['count'] as int?) ?? 0;
    final nextNumber = (count + 1).toString().padLeft(4, '0');
    
    return '$yearPrefix$nextNumber'; // Format: YY0001, YY0002, etc.
  }

  @override
  Future<void> addMember(Member member) async {
    final db = await database;
    await db.insert('members', member.toMap());
    await _addToHistory('ADD_MEMBER', 'Added member ${member.firstName}');
  }

  @override
  Future<void> updateMember(Member member) async {
    final db = await database;
    await db.update(
      'members',
      member.toMap(),
      where: 'id = ?',
      whereArgs: [member.id],
    );
    await _addToHistory('UPDATE_MEMBER', 'Updated member ${member.firstName}');
  }

  @override
  Future<void> deleteMember(String memberId) async {
    final db = await database;
    await db.delete(
      'members',
      where: 'member_id = ?',
      whereArgs: [memberId],
    );
    await _addToHistory('DELETE_MEMBER', 'Deleted member $memberId');
  }

  // Loans
  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async {
    final db = await database;
    String? whereClause;
    List<dynamic>? whereArgs;
    
    if (activeOnly) {
      whereClause = "status = 'Active'";
    }

    final List<Map<String, dynamic>> maps = await db.query(
      'loans',
      where: whereClause,
      whereArgs: whereArgs,
      orderBy: 'loan_date DESC',
    );
    return List.generate(maps.length, (i) => Loan.fromMap(maps[i]));
  }

  @override
  Future<void> addLoan(Loan loan) async {
    final db = await database; // Ensure DB is initialized
    await db.transaction((txn) async {
      await txn.insert('loans', loan.toMap());
      // Update item status
      await txn.update(
        'library_items',
        {'status': 'Emprunté'},
        where: 'code = ?',
        whereArgs: [loan.itemCode],
      );
    });
    await _addToHistory('LOAN_OUT', 'Loaned ${loan.itemCode} to ${loan.memberName}');
  }

  @override
  Future<void> updateLoan(Loan loan) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update(
        'loans',
        loan.toMap(),
        where: 'id = ?',
        whereArgs: [loan.id],
      );
      
      // If returning, update item status
      if (loan.status == 'Returned') {
        await txn.update(
          'library_items',
          {'status': 'Disponible'},
          where: 'code = ?',
          whereArgs: [loan.itemCode],
        );
      }
    });

    if (loan.status == 'Returned') {
        await _addToHistory('LOAN_RETURN', 'Returned ${loan.itemCode}');
    }
  }

  Future<void> _addToHistory(String operation, String details) async {
    await addHistoryEntry({
      'timestamp': DateTime.now().toIso8601String(),
      'operation': operation,
      'details': details,
      'user': 'Host',
    });
  }
}

