/// Reports / management summaries domain model (Phase 10.4).
///
/// A [Report] is a SERVER-computed, read-only result set: the host runs one
/// aggregate query per report kind and hands back a fully-formed table (stable
/// column headers + already-stringified rows + a headline summary). A LAN client
/// receives the exact same structure over JSON, so host and remote operator see
/// identical numbers regardless of who is looking -- presentation and export
/// (CSV / PDF) never re-derive or re-filter the data on the client.
///
/// Reports are computed fresh on every request (nothing here is persisted), so
/// unlike `ReservationStatus` / `FineStatus` there is no "lenient parse for a
/// stored row": [ReportKind.tryParse] is the ONLY parser and is used strictly on
/// the untrusted HTTP/UI boundary (an unknown kind is a 400, never a guess).
///
/// Deliberately free of Flutter/SQL so the server, the client and tests share
/// one vocabulary.
enum ReportKind {
  /// Borrowed vs returned per day across a date window.
  circulation('circulation'),

  /// Loans still out and past their due date right now (no window).
  overdue('overdue'),

  /// Catalogue stock by title type (whole collection, no window).
  inventory('inventory'),

  /// Fines assessed / collected / waived across a date window.
  fines('fines'),

  /// Most active borrowers across a date window.
  members('members');

  const ReportKind(this.storage);

  /// Exact value used in the route path and JSON payload.
  final String storage;

  /// STRICT parse for untrusted input (route segment / UI selection): returns
  /// null rather than guessing, so a typo'd or forged report kind is refused
  /// (-> 400) instead of silently running the wrong report.
  static ReportKind? tryParse(Object? value) {
    final s = value?.toString();
    for (final k in ReportKind.values) {
      if (k.storage == s) return k;
    }
    return null;
  }

  static const ReportKind fallback = ReportKind.circulation;
}

/// One computed report. [columns] is the header row; every inner list in [rows]
/// has exactly `columns.length` already-formatted string cells (numbers and
/// dates are rendered server-side so a client cannot mis-format money). [summary]
/// is an ordered map of headline figures shown above the table. [from] / [to]
/// echo the effective window as `YYYY-MM-DD` (null for a windowless report).
class Report {
  const Report({
    required this.kind,
    required this.title,
    required this.generatedAt,
    required this.columns,
    required this.rows,
    this.summary = const {},
    this.from,
    this.to,
  });

  final ReportKind kind;

  /// Human-readable report name (localised by the server-side caller is out of
  /// scope; the UI maps [kind] to a localized title and treats this as a
  /// fallback / audit label).
  final String title;

  /// ISO-8601 generation stamp (the host clock), so an export is attributable.
  final String generatedAt;

  /// Effective window bounds as `YYYY-MM-DD` (null for an unwindowed report).
  final String? from;
  final String? to;

  final List<String> columns;
  final List<List<String>> rows;
  final Map<String, String> summary;

  int get rowCount => rows.length;

  Map<String, dynamic> toMap() => {
        'kind': kind.storage,
        'title': title,
        'generated_at': generatedAt,
        'from': from,
        'to': to,
        'columns': columns,
        'rows': rows,
        'summary': summary,
      };

  /// Client-side decode of a server-authored payload. Every cell is coerced to
  /// a display string defensively: a null cell becomes '' and a numeric cell
  /// becomes its text, so one unexpected type from a version-skewed host can
  /// never crash the whole report view (crash-safety on untrusted data).
  factory Report.fromMap(Map<String, dynamic> map) {
    List<String> cells(Object? row) =>
        (row as List? ?? const []).map((c) => c?.toString() ?? '').toList();
    return Report(
      kind: ReportKind.tryParse(map['kind']) ?? ReportKind.fallback,
      title: (map['title'] ?? '').toString(),
      generatedAt: (map['generated_at'] ?? '').toString(),
      from: map['from']?.toString(),
      to: map['to']?.toString(),
      columns: (map['columns'] as List? ?? const [])
          .map((c) => c?.toString() ?? '')
          .toList(),
      rows: (map['rows'] as List? ?? const []).map(cells).toList(),
      summary: (map['summary'] as Map? ?? const {}).map(
        (k, v) => MapEntry(k.toString(), v?.toString() ?? ''),
      ),
    );
  }
}
