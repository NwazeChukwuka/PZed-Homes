class ProductCatalogConfig {
  ProductCatalogConfig._();

  static const List<String> productTables = [
    'inventory_items',
    'mini_mart_items',
    'menu_items',
    'stock_items',
  ];

  static const Map<String, String> departmentToTable = {
    'bars': 'inventory_items',
    'inventory': 'inventory_items',
    'mini_mart': 'mini_mart_items',
    'minimart': 'mini_mart_items',
    'kitchen': 'menu_items',
    'restaurant': 'menu_items',
    'store': 'stock_items',
  };

  static const Map<String, String> tableToDepartmentName = {
    'inventory_items': 'Inventory',
    'mini_mart_items': 'MiniMart',
    'menu_items': 'Kitchen',
    'stock_items': 'Store',
  };

  static Map<String, List<({String key, String label})>> get priceFieldsByTable =>
      {
        'inventory_items': [
          (key: 'vip_bar_price', label: 'VIP Bar Price (₦)'),
          (key: 'outside_bar_price', label: 'Outside Bar Price (₦)'),
        ],
        'mini_mart_items': [(key: 'price', label: 'Price (₦)')],
        'menu_items': [(key: 'price', label: 'Price (₦)')],
        'stock_items': [], // store catalog has no price column
      };

  static bool hasSinglePrice(String tableName) {
    final list = priceFieldsByTable[tableName] ?? [];
    return list.length <= 1;
  }
}

