import 'dart:convert';
import 'package:http/http.dart' as http;

/// Bibliographic metadata resolved from public cataloging APIs (OpenLibrary / Google Books).
class IsbnBookData {
  final String title;
  final String? author;
  final String? publisher;
  final int? year;
  final String? category;
  final String? description;
  final String? coverUrl;

  const IsbnBookData({
    required this.title,
    this.author,
    this.publisher,
    this.year,
    this.category,
    this.description,
    this.coverUrl,
  });
}

/// Auto-cataloging service: queries OpenLibrary and Google Books by ISBN.
class IsbnLookupService {
  final http.Client _client;

  IsbnLookupService({http.Client? client}) : _client = client ?? http.Client();

  /// Looks up book bibliographic data by [rawIsbn].
  /// Returns `null` if the lookup times out, fails, or finds no matching title.
  Future<IsbnBookData?> lookup(String rawIsbn) async {
    final cleanIsbn = rawIsbn.replaceAll(RegExp(r'[^0-9Xx]'), '').trim();
    if (cleanIsbn.length < 10) return null;

    // 1. Try OpenLibrary API first
    try {
      final olResult = await _lookupOpenLibrary(cleanIsbn);
      if (olResult != null) return olResult;
    } catch (_) {
      // Fall through to Google Books
    }

    // 2. Fallback to Google Books API
    try {
      final gbResult = await _lookupGoogleBooks(cleanIsbn);
      if (gbResult != null) return gbResult;
    } catch (_) {
      return null;
    }

    return null;
  }

  Future<IsbnBookData?> _lookupOpenLibrary(String isbn) async {
    final url = Uri.parse(
      'https://openlibrary.org/api/books?bibkeys=ISBN:$isbn&format=json&jscmd=data',
    );
    final response = await _client.get(url).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final bookKey = 'ISBN:$isbn';
    if (!data.containsKey(bookKey)) return null;

    final book = data[bookKey] as Map<String, dynamic>;
    final title = book['title']?.toString() ?? '';
    if (title.isEmpty) return null;

    String? author;
    if (book['authors'] is List && (book['authors'] as List).isNotEmpty) {
      final authors = (book['authors'] as List)
          .map((a) => a['name']?.toString() ?? '')
          .where((n) => n.isNotEmpty)
          .toList();
      if (authors.isNotEmpty) author = authors.join(', ');
    }

    String? publisher;
    if (book['publishers'] is List && (book['publishers'] as List).isNotEmpty) {
      publisher = book['publishers'][0]['name']?.toString();
    }

    int? year;
    final pubDate = book['publish_date']?.toString();
    if (pubDate != null) {
      final match = RegExp(r'\b(19|20)\d{2}\b').firstMatch(pubDate);
      if (match != null) year = int.tryParse(match.group(0)!);
    }

    String? category;
    if (book['subjects'] is List && (book['subjects'] as List).isNotEmpty) {
      category = book['subjects'][0]['name']?.toString();
    }

    String? coverUrl;
    if (book['cover'] is Map) {
      coverUrl =
          (book['cover']['large'] ??
                  book['cover']['medium'] ??
                  book['cover']['small'])
              ?.toString();
    }

    return IsbnBookData(
      title: title,
      author: author,
      publisher: publisher,
      year: year,
      category: category,
      coverUrl: coverUrl,
    );
  }

  Future<IsbnBookData?> _lookupGoogleBooks(String isbn) async {
    final url = Uri.parse(
      'https://www.googleapis.com/books/v1/volumes?q=isbn:$isbn&maxResults=1',
    );
    final response = await _client.get(url).timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return null;

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    if (data['totalItems'] == 0 || data['items'] == null) return null;

    final items = data['items'] as List;
    if (items.isEmpty) return null;

    final volumeInfo = items[0]['volumeInfo'] as Map<String, dynamic>?;
    if (volumeInfo == null) return null;

    final title = volumeInfo['title']?.toString() ?? '';
    if (title.isEmpty) return null;

    String? author;
    if (volumeInfo['authors'] is List) {
      author = (volumeInfo['authors'] as List).join(', ');
    }

    final publisher = volumeInfo['publisher']?.toString();
    final description = volumeInfo['description']?.toString();

    int? year;
    final publishedDate = volumeInfo['publishedDate']?.toString();
    if (publishedDate != null) {
      final match = RegExp(r'^\d{4}').firstMatch(publishedDate);
      if (match != null) year = int.tryParse(match.group(0)!);
    }

    String? category;
    if (volumeInfo['categories'] is List &&
        (volumeInfo['categories'] as List).isNotEmpty) {
      category = (volumeInfo['categories'] as List)[0].toString();
    }

    String? coverUrl;
    if (volumeInfo['imageLinks'] is Map) {
      coverUrl =
          (volumeInfo['imageLinks']['thumbnail'] ??
                  volumeInfo['imageLinks']['smallThumbnail'])
              ?.toString();
      if (coverUrl != null && coverUrl.startsWith('http://')) {
        coverUrl = coverUrl.replaceFirst('http://', 'https://');
      }
    }

    return IsbnBookData(
      title: title,
      author: author,
      publisher: publisher,
      year: year,
      category: category,
      description: description,
      coverUrl: coverUrl,
    );
  }
}
