/// Phase 19: one LAN-chat message exchanged between the host and its paired
/// staff clients. Deliberately a plain value object (no drift/ORM dependency) so
/// it survives both the host's in-process buffer and the JSON wire format that
/// clients speak. The [id] is a host-assigned, strictly increasing sequence
/// number: it is the cursor a client polls "since" so it only ever fetches new
/// messages, and it lets the UI de-duplicate without trusting wall-clock order.
class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.sender,
    required this.role,
    required this.sentAt,
    required this.text,
  });

  final int id;
  final String sender;
  final String role;
  final DateTime sentAt;
  final String text;

  Map<String, dynamic> toMap() => {
    'id': id,
    'sender': sender,
    'role': role,
    'sent_at': sentAt.toIso8601String(),
    'text': text,
  };

  factory ChatMessage.fromMap(Map<String, dynamic> m) => ChatMessage(
    id: (m['id'] as num).toInt(),
    sender: (m['sender'] ?? '').toString(),
    role: (m['role'] ?? '').toString(),
    sentAt:
        DateTime.tryParse((m['sent_at'] ?? '').toString()) ?? DateTime.now(),
    text: (m['text'] ?? '').toString(),
  );
}
