import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:library_manager/services/isbn_lookup_service.dart';

void main() {
  group('IsbnLookupService', () {
    test('returns null for an invalid/short ISBN', () async {
      final svc = IsbnLookupService();
      final result = await svc.lookup('123');
      expect(result, isNull);
    });

    test('parses OpenLibrary response accurately', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'openlibrary.org') {
          final body = {
            'ISBN:9780132350884': {
              'title': 'Clean Code',
              'authors': [
                {'name': 'Robert C. Martin'},
              ],
              'publishers': [
                {'name': 'Prentice Hall'},
              ],
              'publish_date': 'August 1, 2008',
              'subjects': [
                {'name': 'Computers / Programming'},
              ],
              'cover': {
                'medium': 'https://covers.openlibrary.org/b/id/123-M.jpg',
              },
            },
          };
          return http.Response(jsonEncode(body), 200);
        }
        return http.Response('Not found', 404);
      });

      final svc = IsbnLookupService(client: mockClient);
      final book = await svc.lookup('978-0-13-235088-4');

      expect(book, isNotNull);
      expect(book!.title, 'Clean Code');
      expect(book.author, 'Robert C. Martin');
      expect(book.publisher, 'Prentice Hall');
      expect(book.year, 2008);
      expect(book.category, 'Computers / Programming');
      expect(book.coverUrl, contains('openlibrary.org'));
    });

    test('falls back to Google Books when OpenLibrary has no match', () async {
      final mockClient = MockClient((request) async {
        if (request.url.host == 'openlibrary.org') {
          return http.Response('{}', 200);
        }
        if (request.url.host == 'www.googleapis.com') {
          final body = {
            'totalItems': 1,
            'items': [
              {
                'volumeInfo': {
                  'title': 'Refactoring',
                  'authors': ['Martin Fowler', 'Kent Beck'],
                  'publisher': 'Addison-Wesley',
                  'publishedDate': '1999-07-08',
                  'categories': ['Software Engineering'],
                  'description': 'Improving the design of existing code.',
                },
              },
            ],
          };
          return http.Response(jsonEncode(body), 200);
        }
        return http.Response('Error', 500);
      });

      final svc = IsbnLookupService(client: mockClient);
      final book = await svc.lookup('9780201485677');

      expect(book, isNotNull);
      expect(book!.title, 'Refactoring');
      expect(book.author, 'Martin Fowler, Kent Beck');
      expect(book.publisher, 'Addison-Wesley');
      expect(book.year, 1999);
      expect(book.category, 'Software Engineering');
      expect(book.description, contains('Improving the design'));
    });
  });
}
