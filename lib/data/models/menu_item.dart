class MenuItem {
  final String id;
  final String name;
  final String department;
  final int price; // stored in kobo
  final String category;
  final String? barcode;
  final String? stockItemId;

  MenuItem({
    required this.id,
    required this.name,
    required this.department,
    required this.price,
    required this.category,
    this.barcode,
    this.stockItemId,
  });

  factory MenuItem.fromMap(Map<String, dynamic> map) {
    return MenuItem(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? 'Unknown Item',
      department: (map['department'] as String?) ?? '',
      price: (map['price'] as int?) ?? 0,
      category: (map['category'] as String?) ?? '',
      barcode: map['barcode'] as String?,
      stockItemId: map['stock_item_id'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'department': department,
      'price': price,
      'category': category,
      'barcode': barcode,
      'stock_item_id': stockItemId,
    };
  }
}