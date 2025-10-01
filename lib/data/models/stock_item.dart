// Location: lib/data/models/stock_item.dart
class StockItem {
  final String id;
  final String name;
  final String unit;
  int currentQuantity;
  final int reorderLevel;

  StockItem({
    required this.id,
    required this.name,
    required this.unit,
    required this.currentQuantity,
    required this.reorderLevel,
  });

  factory StockItem.fromMap(Map<String, dynamic> map) {
    return StockItem(
      id: map['id'] as String,
      name: map['name'] as String,
      unit: map['unit'] as String,
      currentQuantity: map['current_quantity'] as int,
      reorderLevel: map['reorder_level'] as int,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'unit': unit,
      'current_quantity': currentQuantity,
      'reorder_level': reorderLevel,
    };
  }
}
