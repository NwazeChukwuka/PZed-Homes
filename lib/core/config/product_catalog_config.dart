/// Configuration for the unified product catalog (Bars, MiniMart, Kitchen, Store).
/// Adding a new department (e.g. Spa) only requires adding an entry here and the
/// same CRUD flows work without new screens.
class ProductCatalogConfig {
  ProductCatalogConfig._();

  /// Supported product tables for management CRUD.
  static const List<String> productTables = [
    'inventory_items',
    'mini_mart_items',
    'menu_items',
    'stock_items',
  ];

  /// Map from logical department/screen to table name.
  /// Used by screens to know which table they are managing.
  static const Map<String, String> departmentToTable = {
    'bars': 'inventory_items',
    'inventory': 'inventory_items',
    'mini_mart': 'mini_mart_items',
    'minimart': 'mini_mart_items',
    'kitchen': 'menu_items',
    'restaurant': 'menu_items',
    'store': 'stock_items',
  };

  /// Department display name per table for activity logging (e.g. "Price Update").
  static const Map<String, String> tableToDepartmentName = {
    'inventory_items': 'Inventory',
    'mini_mart_items': 'MiniMart',
    'menu_items': 'Kitchen',
    'stock_items': 'Store',
  };

  /// Which price field(s) each table uses. Keys are column names, value is display label.
  /// Empty list = no price field (e.g. stock_items).
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

  /// Whether the table has a single price (for simple forms) or multiple (e.g. bars).
  static bool hasSinglePrice(String tableName) {
    final list = priceFieldsByTable[tableName] ?? [];
    return list.length <= 1;
  }
}
