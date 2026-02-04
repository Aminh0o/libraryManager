import 'dart:convert';
import 'dart:io';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import 'package:flutter/foundation.dart' show debugPrint, kReleaseMode;
import '../models/library_item.dart';
import '../models/member.dart';
import '../models/loan.dart';
import 'database_service.dart';

class HttpServerService {
  late Handler _handler;
  final DatabaseService _db = DatabaseService();
  HttpServer? _server;

  bool get isRunning => _server != null;

  Future<void> stopServer() async {
    final server = _server;
    if (server == null) return;
    _server = null;
    try {
      await server.close(force: true);
    } catch (e) {
      debugPrint('Error stopping server: $e');
    }
  }

  Future<void> startServer({Function(String ip)? onActivity}) async {
    if (_server != null) return;
    final router = Router();

    // GET /items
    router.get('/items', (Request request) async {
      final queryParams = request.url.queryParameters;
      final limit = int.tryParse(queryParams['limit'] ?? '1000') ?? 1000;
      final offset = int.tryParse(queryParams['offset'] ?? '0') ?? 0;
      
      final items = await _db.getItems(limit: limit, offset: offset);
      final jsonList = items.map((item) => item.toMap()).toList();
      return Response.ok(jsonEncode(jsonList), headers: {'content-type': 'application/json'});
    });

    // POST /items
    router.post('/items', (Request request) async {
      final payload = await request.readAsString();
      final map = jsonDecode(payload);
      final item = LibraryItem.fromMap(map);
      await _db.addItem(item);
      
      // Log operation
      await _db.addHistoryEntry({
        'timestamp': DateTime.now().toIso8601String(),
        'operation': 'ADD',
        'details': 'Item ajouté: ${item.fullCode}',
        'user': request.context['shelf.io.connection_info']?.toString() ?? 'Client',
      });
      
      return Response.ok('Item added');
    });

     // PUT /items
    router.put('/items', (Request request) async {
      final payload = await request.readAsString();
      final map = jsonDecode(payload);
      final item = LibraryItem.fromMap(map);
      await _db.updateItem(item);
      
      // Log operation
      await _db.addHistoryEntry({
        'timestamp': DateTime.now().toIso8601String(),
        'operation': 'UPDATE',
        'details': 'Item modifié: ${item.fullCode}',
        'user': request.context['shelf.io.connection_info']?.toString() ?? 'Client',
      });
      
      return Response.ok('Item updated');
    });

    // DELETE /items/<code.>
    router.delete('/items/<code>', (Request request, String code) async {
      await _db.deleteItem(code);
      
      // Log operation
      await _db.addHistoryEntry({
        'timestamp': DateTime.now().toIso8601String(),
        'operation': 'DELETE',
        'details': 'Item supprimé: $code',
        'user': request.context['shelf.io.connection_info']?.toString() ?? 'Client',
      });
      
      return Response.ok('Item deleted');
    });

    // GET /history
    router.get('/history', (Request request) async {
      final queryParams = request.url.queryParameters;
      final limit = int.tryParse(queryParams['limit'] ?? '20') ?? 20;
      final offset = int.tryParse(queryParams['offset'] ?? '0') ?? 0;
      
      final stats = await _db.getHistory(limit: limit, offset: offset);
      return Response.ok(jsonEncode(stats), headers: {'content-type': 'application/json'});
    });

    // POST /history
    router.post('/history', (Request request) async {
      final payload = await request.readAsString();
      final map = jsonDecode(payload);
      await _db.addHistoryEntry(map);
      return Response.ok('History logged');
    });

    // GET /stats
    router.get('/stats', (Request request) async {
      final stats = await _db.getStats();
      return Response.ok(jsonEncode(stats), headers: {'content-type': 'application/json'});
    });

    router.get('/barcode/<barcode>', (Request request, String barcode) async {
      final item = await _db.getItemByBarcode(barcode);
      if (item == null) {
        return Response.notFound(jsonEncode({'error': 'Item not found'}));
      }
      return Response.ok(jsonEncode(item.toMap()), headers: {'content-type': 'application/json'});
    });

    // GET /db-version
    router.get('/db-version', (Request request) async {
      final version = await _db.getDbVersion();
      return Response.ok(jsonEncode({'version': version}), headers: {'content-type': 'application/json'});
    });

    // Code Definitions CRUD
    router.get('/code-definitions', (Request request) async {
      final defs = await _db.getCodeDefinitions();
      return Response.ok(jsonEncode(defs), headers: {'content-type': 'application/json'});
    });

    router.post('/code-definitions', (Request request) async {
      final payload = await request.readAsString();
      final map = jsonDecode(payload);
      await _db.addCodeDefinition(map['prefix'], map['label']);
      return Response.ok('Definition added');
    });

    router.put('/code-definitions/<prefix>', (Request request, String prefix) async {
      final payload = await request.readAsString();
      final map = jsonDecode(payload);
      await _db.updateCodeDefinition(prefix, map['prefix'], map['label']);
      return Response.ok('Definition updated');
    });

    router.delete('/code-definitions/<prefix>', (Request request, String prefix) async {
      await _db.deleteCodeDefinition(prefix);
      return Response.ok('Definition deleted');
    });

    // Attribute Definitions Enum/Lists
    router.get('/attribute-definitions', (Request request) async {
      final type = request.url.queryParameters['type'];
      final defs = await _db.getAttributeDefinitions(type);
      return Response.ok(jsonEncode(defs), headers: {'content-type': 'application/json'});
    });

    router.post('/attribute-definitions', (Request request) async {
      final payload = await request.readAsString();
      final map = jsonDecode(payload);
      await _db.addAttributeDefinition(map['type'], map['value']);
      return Response.ok('Attribute added');
    });

    router.delete('/attribute-definitions/<id>', (Request request, String id) async {
      final intId = int.tryParse(id);
      if (intId != null) {
        await _db.deleteAttributeDefinition(intId);
      }
      return Response.ok('Attribute deleted');
    });

    // Members CRUD
    router.get('/members', (Request request) async {
      final members = await _db.getMembers();
      final jsonList = members.map((m) => m.toMap()).toList();
      return Response.ok(jsonEncode(jsonList), headers: {'content-type': 'application/json'});
    });

    router.post('/members', (Request request) async {
      final payload = await request.readAsString();
      final map = jsonDecode(payload);
      final member = Member.fromMap(map);
      Member finalMember = member;
      final memberId = member.memberId.trim();
      if (memberId.isEmpty || memberId == 'AUTO') {
        final generated = await _db.generateMemberID();
        finalMember = Member(
          id: member.id,
          firstName: member.firstName,
          lastName: member.lastName,
          email: member.email,
          phone: member.phone,
          memberId: generated,
          registeredAt: member.registeredAt,
        );
      }
      await _db.addMember(finalMember);
      
      await _db.addHistoryEntry({
        'timestamp': DateTime.now().toIso8601String(),
        'operation': 'ADD_MEMBER',
        'details': 'Member added: ${finalMember.fullName}',
        'user': request.context['shelf.io.connection_info']?.toString() ?? 'Client',
      });
      
      return Response.ok(
        jsonEncode(finalMember.toMap()),
        headers: {'content-type': 'application/json'},
      );
    });

    router.put('/members', (Request request) async {
      final payload = await request.readAsString();
      final map = jsonDecode(payload);
      final member = Member.fromMap(map);
      await _db.updateMember(member);
      
      await _db.addHistoryEntry({
        'timestamp': DateTime.now().toIso8601String(),
        'operation': 'UPDATE_MEMBER',
        'details': 'Member updated: ${member.fullName}',
        'user': request.context['shelf.io.connection_info']?.toString() ?? 'Client',
      });
      
      return Response.ok('Member updated');
    });

    router.delete('/members/<memberId>', (Request request, String memberId) async {
      await _db.deleteMember(memberId);
      
      await _db.addHistoryEntry({
        'timestamp': DateTime.now().toIso8601String(),
        'operation': 'DELETE_MEMBER',
        'details': 'Member deleted: $memberId',
        'user': request.context['shelf.io.connection_info']?.toString() ?? 'Client',
      });
      
      return Response.ok('Member deleted');
    });

    // Loans CRUD
    router.get('/loans', (Request request) async {
      final queryParams = request.url.queryParameters;
      final activeOnly = queryParams['activeOnly'] == 'true';
      final loans = await _db.getLoans(activeOnly: activeOnly);
      final jsonList = loans.map((l) => l.toMap()).toList();
      return Response.ok(jsonEncode(jsonList), headers: {'content-type': 'application/json'});
    });

    router.post('/loans', (Request request) async {
      final payload = await request.readAsString();
      final map = jsonDecode(payload);
      final loan = Loan.fromMap(map);
      await _db.addLoan(loan);
      
      await _db.addHistoryEntry({
        'timestamp': DateTime.now().toIso8601String(),
        'operation': 'LOAN_OUT',
        'details': 'Loan created: ${loan.itemCode} to ${loan.memberName}',
        'user': request.context['shelf.io.connection_info']?.toString() ?? 'Client',
      });
      
      return Response.ok('Loan added');
    });

    router.put('/loans', (Request request) async {
      final payload = await request.readAsString();
      final map = jsonDecode(payload);
      final loan = Loan.fromMap(map);
      await _db.updateLoan(loan);
      
      await _db.addHistoryEntry({
        'timestamp': DateTime.now().toIso8601String(),
        'operation': loan.status == 'Returned' ? 'LOAN_RETURN' : 'LOAN_UPDATE',
        'details': 'Loan updated: ${loan.itemCode}',
        'user': request.context['shelf.io.connection_info']?.toString() ?? 'Client',
      });
      
      return Response.ok('Loan updated');
    });

    _handler = Pipeline()
        .addMiddleware(kReleaseMode ? (Handler inner) => inner : logRequests())
        .addMiddleware((innerHandler) {
          return (request) async {
            final connectionInfo = request.context['shelf.io.connection_info'] as dynamic;
            String? ip;
            if (connectionInfo != null) {
              // Try to get remoteAddress from shelf.io.connection_info
              try { ip = connectionInfo.remoteAddress.address; } catch (_) {}
            }
            if (ip != null && onActivity != null) {
              onActivity(ip);
            }
            return await innerHandler(request);
          };
        })
        .addHandler(router.call);

    // Listen on all interfaces (0.0.0.0) to allow LAN access
    _server = await shelf_io.serve(_handler, '0.0.0.0', 8080);
    debugPrint('Server listening on port ${_server!.port}');
  }
}
