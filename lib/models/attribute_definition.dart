class AttributeDefinition {
  final int? id;
  final String type; // 'LOCATION', 'STATUS', 'STOCK'
  final String value;

  AttributeDefinition({
    this.id,
    required this.type,
    required this.value,
  });

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'type': type,
      'value': value,
    };
  }

  factory AttributeDefinition.fromMap(Map<String, dynamic> map) {
    return AttributeDefinition(
      id: map['id'],
      type: map['type'],
      value: map['value'],
    );
  }
}
