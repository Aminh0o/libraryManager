class HistoryEntry {
  final int? id;
  final String timestamp;
  final String operation; // e.g., 'ADD', 'UPDATE', 'DELETE', 'SYNC'
  final String details;
  final String user; // 'Host' or 'Client IP'

  HistoryEntry({
    this.id,
    required this.timestamp,
    required this.operation,
    required this.details,
    required this.user,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'timestamp': timestamp,
      'operation': operation,
      'details': details,
      'user': user,
    };
  }

  factory HistoryEntry.fromMap(Map<String, dynamic> map) {
    return HistoryEntry(
      id: map['id'],
      timestamp: map['timestamp'],
      operation: map['operation'],
      details: map['details'],
      user: map['user'],
    );
  }
}
