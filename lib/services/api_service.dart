import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart' show debugPrint;
import '../models/library_item.dart';
import '../models/member.dart';
import '../models/loan.dart';
import 'repository.dart';

class ApiService implements LibraryRepository {
  final String hostIp;
  final int port;

  ApiService({required this.hostIp, this.port = 8080});

  String get _baseUrl => 'http://$hostIp:$port';

  Future<T> _retry<T>(Future<T> Function() action) async {
    int retries = 0;
    const maxRetries = 3;
    while (true) {
      try {
        return await action();
      } catch (e) {
        retries++;
        if (retries > maxRetries || (e is! http.ClientException && e is! SocketException)) {
          rethrow;
        }
        final delay = Duration(milliseconds: 500 * retries);
        await Future.delayed(delay);
      }
    }
  }

  @override
  Future<List<LibraryItem>> getItems({int limit = 1000, int offset = 0}) async {
    return _retry(() async {
      final response = await http.get(Uri.parse('$_baseUrl/items?limit=$limit&offset=$offset'));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((map) => LibraryItem.fromMap(map)).toList();
      } else {
        throw Exception('Failed to load items');
      }
    });
  }

  @override
  Future<void> addItem(LibraryItem item) async {
    await _retry(() async {
      final response = await http.post(
        Uri.parse('$_baseUrl/items'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(item.toMap()),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to add item');
      }
    });
  }

  @override
  Future<void> updateItem(LibraryItem item) async {
    await _retry(() async {
      final response = await http.put(
        Uri.parse('$_baseUrl/items'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(item.toMap()),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to update item');
      }
    });
  }

  @override
  Future<void> deleteItem(String code) async {
    await _retry(() async {
      final response = await http.delete(Uri.parse('$_baseUrl/items/$code'));
      if (response.statusCode != 200) {
        throw Exception('Failed to delete item');
      }
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getHistory({int limit = 20, int offset = 0}) async {
    return _retry(() async {
      final response = await http.get(Uri.parse('$_baseUrl/history?limit=$limit&offset=$offset'));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load history');
      }
    });
  }

  @override
  Future<void> addHistoryEntry(Map<String, dynamic> entry) async {
    await _retry(() async {
      final response = await http.post(
        Uri.parse('$_baseUrl/history'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(entry),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to log history');
      }
    });
  }

  @override
  Future<LibraryItem?> getItemByBarcode(String barcode) async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/barcode/$barcode'));
      if (response.statusCode == 200) {
        return LibraryItem.fromMap(jsonDecode(response.body));
      }
    } catch (e) {
      debugPrint('Error fetching item by barcode: $e');
    }
    return null;
  }

  @override
  Future<Map<String, dynamic>> getStats() async {
    return _retry(() async {
      final response = await http.get(Uri.parse('$_baseUrl/stats'));
      if (response.statusCode == 200) {
        return Map<String, dynamic>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load stats');
      }
    });
  }

  Future<String> getDbVersion() async {
    try {
      final response = await http.get(Uri.parse('$_baseUrl/db-version'));
      if (response.statusCode == 200) {
        return jsonDecode(response.body)['version'];
      }
    } catch (e) {
      debugPrint('Error fetching DB version: $e');
    }
    return '0';
  }

  @override
  Future<List<Map<String, dynamic>>> getCodeDefinitions() async {
    return _retry(() async {
      final response = await http.get(Uri.parse('$_baseUrl/code-definitions'));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load code definitions');
      }
    });
  }

  @override
  Future<void> addCodeDefinition(String prefix, String label) async {
    await _retry(() async {
      final response = await http.post(
        Uri.parse('$_baseUrl/code-definitions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prefix': prefix, 'label': label}),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to add code definition');
      }
    });
  }

  @override
  Future<void> updateCodeDefinition(String oldPrefix, String newPrefix, String label) async {
    await _retry(() async {
      final response = await http.put(
        Uri.parse('$_baseUrl/code-definitions/$oldPrefix'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'prefix': newPrefix, 'label': label}),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to update code definition');
      }
    });
  }

  @override
  Future<void> deleteCodeDefinition(String prefix) async {
    await _retry(() async {
      final response = await http.delete(Uri.parse('$_baseUrl/code-definitions/$prefix'));
      if (response.statusCode != 200) {
        throw Exception('Failed to delete code definition');
      }
    });
  }

  @override
  Future<List<Map<String, dynamic>>> getAttributeDefinitions(String? type) async {
    return _retry(() async {
      final url = type != null ? '$_baseUrl/attribute-definitions?type=$type' : '$_baseUrl/attribute-definitions';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        return List<Map<String, dynamic>>.from(jsonDecode(response.body));
      } else {
        throw Exception('Failed to load attribute definitions');
      }
    });
  }

  @override
  Future<void> addAttributeDefinition(String type, String value) async {
    await _retry(() async {
      final response = await http.post(
        Uri.parse('$_baseUrl/attribute-definitions'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'type': type, 'value': value}),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to add attribute definition');
      }
    });
  }

  @override
  Future<void> deleteAttributeDefinition(int id) async {
    await _retry(() async {
      final response = await http.delete(Uri.parse('$_baseUrl/attribute-definitions/$id'));
      if (response.statusCode != 200) {
        throw Exception('Failed to delete attribute definition');
      }
    });
  }

  // Members (Client implementation)
  @override
  Future<List<Member>> getMembers() async {
    return _retry(() async {
      final response = await http.get(Uri.parse('$_baseUrl/members'));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((map) => Member.fromMap(map)).toList();
      } else {
        throw Exception('Failed to load members');
      }
    });
  }

  @override
  Future<void> addMember(Member member) async {
    await _retry(() async {
      final response = await http.post(
        Uri.parse('$_baseUrl/members'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(member.toMap()),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to add member');
      }
    });
  }

  @override
  Future<void> updateMember(Member member) async {
    await _retry(() async {
      final response = await http.put(
        Uri.parse('$_baseUrl/members'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(member.toMap()),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to update member');
      }
    });
  }

  @override
  Future<void> deleteMember(String memberId) async {
    await _retry(() async {
      final response = await http.delete(Uri.parse('$_baseUrl/members/$memberId'));
      if (response.statusCode != 200) {
        throw Exception('Failed to delete member');
      }
    });
  }

  // Loans (Client implementation)
  @override
  Future<List<Loan>> getLoans({bool activeOnly = false}) async {
    return _retry(() async {
      final url = activeOnly ? '$_baseUrl/loans?activeOnly=true' : '$_baseUrl/loans';
      final response = await http.get(Uri.parse(url));
      if (response.statusCode == 200) {
        final List<dynamic> jsonList = jsonDecode(response.body);
        return jsonList.map((map) => Loan.fromMap(map)).toList();
      } else {
        throw Exception('Failed to load loans');
      }
    });
  }

  @override
  Future<void> addLoan(Loan loan) async {
    await _retry(() async {
      final response = await http.post(
        Uri.parse('$_baseUrl/loans'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(loan.toMap()),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to add loan');
      }
    });
  }

  @override
  Future<void> updateLoan(Loan loan) async {
    await _retry(() async {
      final response = await http.put(
        Uri.parse('$_baseUrl/loans'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(loan.toMap()),
      );
      if (response.statusCode != 200) {
        throw Exception('Failed to update loan');
      }
    });
  }
}
