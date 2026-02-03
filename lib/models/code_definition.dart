class CodeDefinition {
  final String prefix;
  final String label;

  CodeDefinition({
    required this.prefix,
    required this.label,
  });

  Map<String, dynamic> toMap() {
    return {
      'prefix': prefix,
      'label': label,
    };
  }

  factory CodeDefinition.fromMap(Map<String, dynamic> map) {
    return CodeDefinition(
      prefix: map['prefix'] ?? '',
      label: map['label'] ?? '',
    );
  }
}
