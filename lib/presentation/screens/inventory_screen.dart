import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
// Supabase removed for mock-only mode
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:pzed_homes/data/models/user.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> with TickerProviderStateMixin {
  final DataService _dataService = DataService();
  late TabController _tabController;

  Future<List<Map<String, dynamic>>>? _inventoryFuture;
  bool _isLoading = true;
  
  // Pagination state
  int _rowsPerPage = 10;
  int _currentPage = 0;
  List<Map<String, dynamic>> _allTransactions = [];
  List<Map<String, dynamic>> _currentPageTransactions = [];
  
  // Controllers for add item dialog
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitController = TextEditingController();
  final _vipPriceController = TextEditingController();
  final _outsidePriceController = TextEditingController();
  final _categoryController = TextEditingController();

  // Bar selection for management
  String? _selectedBar;
  String? _selectedBarForSales;

  // Sales state variables
  List<Map<String, dynamic>> _currentSale = [];
  double _saleTotal = 0.0;
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _approvedByController = TextEditingController(); // For credit sales
  String _paymentMethod = 'cash';
  List<String> _missingStockItems = [];
  final Map<String, Map<String, int>> _stockByLocation = {};

  // Search controller
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    // #region agent log
    try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"inventory_screen.dart:61","message":"Inventory screen initState","data":{},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"L"})}\n', mode: FileMode.append); } catch (_) {}
    // #endregion
    _updateTabController();
    _loadInventory();
    _loadTransactions();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"inventory_screen.dart:68","message":"PostFrameCallback - role check","data":{"userId":user?.id,"roles":user?.roles.map((r)=>r.name).toList(),"isRoleAssumed":authService.isRoleAssumed,"assumedRole":authService.assumedRole?.name},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"M"})}\n', mode: FileMode.append); } catch (_) {}
      // #endregion
      final userDepartment = _bartenderDepartment(authService, user);
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"inventory_screen.dart:69","message":"Department detection result","data":{"userDepartment":userDepartment,"selectedBar":_selectedBar},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"N"})}\n', mode: FileMode.append); } catch (_) {}
      // #endregion
      if (userDepartment != null && _selectedBar == null) {
        setState(() {
          _selectedBar = userDepartment;
          _selectedBarForSales = userDepartment;
        });
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _vipPriceController.dispose();
    _outsidePriceController.dispose();
    _categoryController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _approvedByController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateTabController() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isBartender = _hasBartenderRole(authService, user);
    // #region agent log
    try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"inventory_screen.dart:96","message":"Tab controller update","data":{"isBartender":isBartender,"userId":user?.id,"roles":user?.roles.map((r)=>r.name).toList(),"isRoleAssumed":authService.isRoleAssumed,"assumedRole":authService.assumedRole?.name,"tabCount":isBartender?3:2},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"O"})}\n', mode: FileMode.append); } catch (_) {}
    // #endregion
    final tabCount = isBartender ? 3 : 2; // Current Stock, Stock Movements, Make Sale (for bartenders)
    _tabController = TabController(length: tabCount, vsync: this);
  }

  bool _isBartenderRole(AppRole role) {
    return role == AppRole.vip_bartender ||
        role == AppRole.outside_bartender;
  }

  bool _hasBartenderRole(AuthService authService, AppUser? user) {
    return (user?.roles.any(_isBartenderRole) ?? false) ||
        (authService.isRoleAssumed &&
            authService.assumedRole != null &&
            _isBartenderRole(authService.assumedRole!));
  }

  String? _bartenderDepartment(AuthService authService, AppUser? user) {
    if (authService.isRoleAssumed && authService.assumedRole != null) {
      final assumed = authService.assumedRole!;
      if (assumed == AppRole.vip_bartender) return 'vip_bar';
      if (assumed == AppRole.outside_bartender) return 'outside_bar';
    }

    if (user != null) {
      if (user.roles.contains(AppRole.vip_bartender)) return 'vip_bar';
      if (user.roles.contains(AppRole.outside_bartender)) return 'outside_bar';
    }

    return null;
  }

  Future<void> _loadInventory() async {
    // #region agent log
    try { 
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      final logData = {
        'location': 'inventory_screen.dart:132',
        'message': 'Loading inventory',
        'data': {
          'userId': user?.id,
          'userRoles': user?.roles.map((r) => r.name).toList(),
          'isRoleAssumed': authService.isRoleAssumed,
          'assumedRole': authService.assumedRole?.name
        },
        'timestamp': DateTime.now().millisecondsSinceEpoch,
        'sessionId': 'debug-session',
        'runId': 'run1',
        'hypothesisId': 'X'
      };
      File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode(logData)}\n', mode: FileMode.append); 
    } catch (_) {}
    print('DEBUG InventoryScreen: Starting _loadInventory');
    // #endregion
    setState(() {
      _isLoading = true;
    });

    try {
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"inventory_screen.dart:139","message":"Calling getInventoryItems","data":{},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"Y"})}\n', mode: FileMode.append); } catch (_) {}
      // #endregion
      final inventory = await _dataService.getInventoryItems();
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"inventory_screen.dart:141","message":"getInventoryItems success","data":{"count":inventory.length},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"Z"})}\n', mode: FileMode.append); } catch (_) {}
      // #endregion
      final stockLevels = await _dataService.getStockLevels();
      final stockItems = await _dataService.supabase
          .from('stock_items')
          .select('name')
          .limit(2000);
      _stockByLocation.clear();
      for (final row in stockLevels) {
        final location = (row['location_name'] as String?)?.toLowerCase();
        final name = (row['name'] as String?)?.toLowerCase();
        final qty = (row['current_stock'] as num?)?.toInt() ?? 0;
        if (location == null || name == null) continue;
        _stockByLocation.putIfAbsent(location, () => {})[name] = qty;
      }
      final stockNames = (stockItems as List)
          .map((e) => (e['name'] as String?)?.toLowerCase())
          .whereType<String>()
          .toSet();
      final missing = inventory
          .map((e) => (e['name'] as String?)?.toLowerCase())
          .whereType<String>()
          .where((name) => !stockNames.contains(name))
          .toSet()
          .toList()
        ..sort();
      setState(() {
        _inventoryFuture = Future.value(inventory);
        _missingStockItems = missing;
        _isLoading = false;
      });
    } catch (e) {
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"inventory_screen.dart:172","message":"_loadInventory error","data":{"error":e.toString(),"errorType":e.runtimeType.toString()},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"AA"})}\n', mode: FileMode.append); } catch (_) {}
      print('DEBUG InventoryScreen: Error loading inventory: $e');
      // #endregion
      setState(() {
        _isLoading = false;
      });
      ErrorHandler.handleError(context, e);
    }
  }

  Future<void> _loadTransactions() async {
    try {
      final transactions = await _dataService.getStockTransactions();
        setState(() {
        _allTransactions = transactions;
        _updateCurrentPageTransactions();
        });
    } catch (e) {
      ErrorHandler.handleError(context, e);
    }
  }

  void _updateCurrentPageTransactions() {
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, _allTransactions.length);
    setState(() {
      _currentPageTransactions = _allTransactions.sublist(startIndex, endIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    // Use Consumer to rebuild when role changes
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final user = authService.currentUser;
        final isBartender = _hasBartenderRole(authService, user);
        
        final showAddItemButton = user?.roles.any((role) => role.name == 'owner' || role.name == 'manager') ?? false;

        // Rebuild tab controller if bartender status changed
        final expectedTabCount = isBartender ? 3 : 2;
        if (_tabController.length != expectedTabCount) {
          _tabController.dispose();
          _tabController = TabController(length: expectedTabCount, vsync: this);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Inventory Management'),
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
            leading: Navigator.of(context).canPop() ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ) : null,
            bottom: TabBar(
              controller: _tabController,
              tabs: [
                const Tab(text: 'Current Stock', icon: Icon(Icons.inventory)),
                const Tab(text: 'Stock Movements', icon: Icon(Icons.trending_up)),
                if (isBartender)
                  const Tab(text: 'Make Sale', icon: Icon(Icons.point_of_sale)),
              ],
            ),
            actions: [
              ContextAwareRoleButton(
                suggestedRole: _selectedBar == 'outside_bar'
                    ? AppRole.outside_bartender
                    : AppRole.vip_bartender,
              ),
              if (showAddItemButton)
                IconButton(
                  icon: const Icon(Icons.add),
                  onPressed: _showAddItemDialog,
                ),
            ],
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _buildCurrentStockTab(),
              _buildStockMovementsTab(),
              if (isBartender)
                _buildMakeSaleTab(),
            ],
          ),
          floatingActionButton: showAddItemButton
              ? FloatingActionButton(
                  onPressed: _showAddItemDialog,
                  backgroundColor: Colors.green[700],
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
        );
      },
    );
  }

  Widget _buildCurrentStockTab() {
    return Column(
                  children: [
        // Bar selection for management
        _buildBarSelectionButtons(),
                    Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _inventoryFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return ErrorHandler.buildErrorWidget(
                  context,
                  snapshot.error,
                  message: 'Error loading inventory',
                  onRetry: _loadInventory,
                );
              }

              final items = snapshot.data ?? [];
              if (items.isEmpty) {
                return ErrorHandler.buildEmptyWidget(
                  context,
                  message: 'No inventory items available',
                );
              }
              final filteredItems = _filterItemsByBar(items);

              return ListView.builder(
                itemCount: filteredItems.length,
                itemBuilder: (context, index) {
                  final item = filteredItems[index];
                  return _buildInventoryItem(item);
                },
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildBarSelectionButtons() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isManagement = user?.roles.any((role) => 
        role.toString().contains('owner') || 
        role.toString().contains('manager')) ?? false;

    if (!isManagement) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
                    Expanded(
            child: ElevatedButton(
              onPressed: () => setState(() => _selectedBar = null),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedBar == null ? Colors.green[700] : Colors.grey[300],
                foregroundColor: _selectedBar == null ? Colors.white : Colors.black,
              ),
              child: const Text('All Bars'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: () => setState(() => _selectedBar = 'vip_bar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedBar == 'vip_bar' ? Colors.green[700] : Colors.grey[300],
                foregroundColor: _selectedBar == 'vip_bar' ? Colors.white : Colors.black,
              ),
              child: const Text('VIP Bar'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ElevatedButton(
              onPressed: () => setState(() => _selectedBar = 'outside_bar'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _selectedBar == 'outside_bar' ? Colors.green[700] : Colors.grey[300],
                foregroundColor: _selectedBar == 'outside_bar' ? Colors.white : Colors.black,
              ),
              child: const Text('Outside Bar'),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterItemsByBar(List<Map<String, dynamic>> items) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isManagement = user?.roles.any((role) =>
            role.toString().contains('owner') ||
            role.toString().contains('manager')) ??
        false;

    if (!isManagement) {
      final userDepartment = _bartenderDepartment(authService, user);
      if (userDepartment == null || userDepartment.isEmpty) {
        return [];
      }
      return items.where((item) {
        final department = item['department'] as String?;
        return department == userDepartment;
      }).toList();
    }

    if (_selectedBar == null) {
      return items.where((item) {
        final department = item['department'] as String?;
        return department == 'vip_bar' || department == 'outside_bar';
      }).toList();
    }
    return items.where((item) {
      final department = item['department'] as String?;
      return department == _selectedBar;
    }).toList();
  }

  Widget _buildInventoryItem(Map<String, dynamic> item) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.green[100],
          child: Icon(
            _getCategoryIcon(item['category']),
            color: Colors.green[700],
          ),
        ),
        title: Text(item['name'] ?? 'Unknown Item'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Category: ${item['category'] ?? 'Unknown'}'),
            Text('Stock: ${_getCurrentStock(item)} ${item['unit'] ?? 'units'}'),
            if (item['vip_bar_price'] != null)
              Text(
                'VIP Price: ₦${PaymentService.koboToNaira((item['vip_bar_price'] as num?)?.toInt() ?? 0).toStringAsFixed(2)}',
              ),
            if (item['outside_bar_price'] != null)
              Text(
                'Outside Price: ₦${PaymentService.koboToNaira((item['outside_bar_price'] as num?)?.toInt() ?? 0).toStringAsFixed(2)}',
              ),
          ],
        ),
        trailing: Text(
          'Department: ${item['department'] ?? 'Unknown'}',
          style: const TextStyle(fontSize: 12),
        ),
                      ),
                    );
                  }

  IconData _getCategoryIcon(String? category) {
    switch (category?.toLowerCase()) {
      case 'alcoholic drinks':
        return Icons.local_bar;
      case 'soft drinks':
        return Icons.local_drink;
      case 'snacks':
        return Icons.cookie;
      default:
        return Icons.inventory;
    }
  }

  Color _getCategoryColor(String? category) {
    switch (category?.toLowerCase()) {
      case 'alcoholic drinks':
        return Colors.blue[400]!;
      case 'soft drinks':
        return Colors.green[400]!;
      case 'snacks':
        return Colors.orange[400]!;
      default:
        return Colors.grey[400]!;
    }
  }

  Widget _buildStockMovementsTab() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Text('Rows per page:'),
              const SizedBox(width: 8),
              DropdownButton<int>(
                value: _rowsPerPage,
                items: const [
                  DropdownMenuItem(value: 5, child: Text('5')),
                  DropdownMenuItem(value: 10, child: Text('10')),
                  DropdownMenuItem(value: 20, child: Text('20')),
                ],
                onChanged: (value) {
                  setState(() {
                    _rowsPerPage = value!;
                    _currentPage = 0;
                    _updateCurrentPageTransactions();
                  });
                },
              ),
              const Spacer(),
              Text('Page ${_currentPage + 1} of ${(_allTransactions.length / _rowsPerPage).ceil()}'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _currentPageTransactions.length,
            itemBuilder: (context, index) {
              final transaction = _currentPageTransactions[index];
              return _buildTransactionItem(transaction);
            },
          ),
        ),
        if (_allTransactions.length > _rowsPerPage)
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  onPressed: _currentPage > 0 ? () {
                    setState(() {
                      _currentPage--;
                      _updateCurrentPageTransactions();
                    });
                  } : null,
                  icon: const Icon(Icons.chevron_left),
                ),
                const SizedBox(width: 16),
                IconButton(
                  onPressed: _currentPage < (_allTransactions.length / _rowsPerPage).ceil() - 1 ? () {
                    setState(() {
                      _currentPage++;
                      _updateCurrentPageTransactions();
                    });
                  } : null,
                  icon: const Icon(Icons.chevron_right),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildTransactionItem(Map<String, dynamic> transaction) {
    final isSale = transaction['type'] == 'sale';
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isSale ? Colors.red[100] : Colors.green[100],
          child: Icon(
            isSale ? Icons.sell : Icons.add_box,
            color: isSale ? Colors.red[700] : Colors.green[700],
          ),
        ),
        title: Text(transaction['customer_name'] ?? 'Unknown Customer'),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Item: ${transaction['item_id']}'),
            Text('Quantity: ${transaction['quantity']}'),
            Text('Unit Price: ₦${PaymentService.koboToNaira(transaction['unit_price'] as int? ?? 0).toStringAsFixed(2)}'),
            Text('Total: ₦${PaymentService.koboToNaira(transaction['total_amount'] as int? ?? 0).toStringAsFixed(2)}'),
            Text('Time: ${transaction['timestamp']}'),
          ],
        ),
        trailing: Text(
          isSale ? 'SALE' : 'STOCK IN',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isSale ? Colors.red[700] : Colors.green[700],
          ),
        ),
      ),
    );
  }

  Widget _buildMakeSaleTab() {
    return Row(
      children: [
        // Items grid
        Expanded(
          flex: 2,
          child: Column(
            children: [
              // Search bar
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    labelText: 'Search items...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => setState(() {}),
                ),
              ),
              // Bar selection for management
              _buildBarSelectionForSales(),
              if (_missingStockItems.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Card(
                    color: Colors.orange[50],
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Missing stock linkage',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Some items are not linked to stock items, sales will be blocked for them.',
                            style: TextStyle(color: Colors.orange[800], fontSize: 12),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _missingStockItems.take(5).join(', ') +
                                (_missingStockItems.length > 5 ? '...' : ''),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              // Items grid
              Expanded(
                child: FutureBuilder<List<Map<String, dynamic>>>(
                  future: _inventoryFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }

                    if (snapshot.hasError) {
                      return ErrorHandler.buildErrorWidget(
                        context,
                        snapshot.error,
                        message: 'Error loading inventory items',
                        onRetry: _loadInventory,
                      );
                    }

                    final items = snapshot.data ?? [];
                    if (items.isEmpty) {
                      return ErrorHandler.buildEmptyWidget(
                        context,
                        message: 'No inventory items available',
                      );
                    }

                    final filteredItems = _filterItemsForSales(items);

                    return GridView.builder(
                      padding: const EdgeInsets.all(16),
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 3,
                        crossAxisSpacing: 12,
                        mainAxisSpacing: 12,
                        childAspectRatio: 0.7,
                      ),
                      itemCount: filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = filteredItems[index];
                        return _buildSaleItemCard(item);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
        // Current sale section
        Expanded(
          flex: 1,
          child: _buildCurrentSaleSection(),
        ),
      ],
    );
  }

  Widget _buildBarSelectionForSales() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isManagement = user?.roles.any((role) => 
        role.toString().contains('owner') || 
        role.toString().contains('manager')) ?? false;
    final isBartenderAssumed = authService.isRoleAssumed &&
        authService.assumedRole != null &&
        _isBartenderRole(authService.assumedRole!);
    final hasFixedBarRole = (user?.roles.contains(AppRole.vip_bartender) ?? false) ||
        (user?.roles.contains(AppRole.outside_bartender) ?? false);

    if (!isManagement && !hasFixedBarRole) {
      return const SizedBox.shrink();
    }
    if (isManagement && !isBartenderAssumed) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          const Text('Select Bar:'),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonFormField<String>(
              value: _selectedBarForSales,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
              items: const [
                DropdownMenuItem(value: 'vip_bar', child: Text('VIP Bar')),
                DropdownMenuItem(value: 'outside_bar', child: Text('Outside Bar')),
              ],
              onChanged: (value) => setState(() {
                _selectedBarForSales = value;
                _selectedBar = value;
              }),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterItemsForSales(List<Map<String, dynamic>> items) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final userDepartment = _bartenderDepartment(authService, user);

    // Filter by search
    var filtered = items.where((item) {
      final searchTerm = _searchController.text.toLowerCase();
      if (searchTerm.isEmpty) return true;
      return (item['name'] as String? ?? '').toLowerCase().contains(searchTerm) ||
             (item['category'] as String? ?? '').toLowerCase().contains(searchTerm);
    }).toList();

    // Filter by bar/department
    if (authService.isRoleAssumed &&
        authService.assumedRole != null &&
        _isBartenderRole(authService.assumedRole!)) {
      // Management assuming bartender role (explicit bar selection)
      filtered = filtered.where((item) {
        final department = item['department'] as String?;
        return department == _selectedBarForSales;
      }).toList();
    } else if (userDepartment != null && userDepartment.isNotEmpty) {
      // Regular bartender
      filtered = filtered.where((item) {
        final department = item['department'] as String?;
        return department == userDepartment;
      }).toList();
    }

    // Filter by stock availability
    return filtered.where((item) => ((item['vip_bar_price'] as num?)?.toDouble() ?? 0.0) > 0 || 
                                    ((item['outside_bar_price'] as num?)?.toDouble() ?? 0.0) > 0).toList();
  }

  Widget _buildSaleItemCard(Map<String, dynamic> item) {
    final price = _getItemPrice(item);
    final stock = _getCurrentStock(item);
    final isOutOfStock = stock <= 0;
    
    return Card(
      elevation: 2,
      child: InkWell(
        onTap: isOutOfStock ? null : () => _addItemToSale(item),
        child: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isOutOfStock ? Colors.grey[100] : Colors.white,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: _getCategoryColor(item['category']),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    _getCategoryIcon(item['category']),
                    size: 32,
                    color: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                item['name']?.toString() ?? 'Unknown',
                style: const TextStyle(
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '₦${NumberFormat('#,##0.00').format(price)}',
                style: TextStyle(
                  color: Colors.green[700],
                  fontWeight: FontWeight.bold,
                  fontSize: 11,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Stock: $stock',
                style: TextStyle(
                  color: isOutOfStock ? Colors.red : Colors.grey[600],
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  double _getItemPrice(Map<String, dynamic> item) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final userDepartment = _bartenderDepartment(authService, user);

    if (authService.isRoleAssumed &&
        authService.assumedRole != null &&
        _isBartenderRole(authService.assumedRole!)) {
      // Management assuming bartender role
      if (_selectedBarForSales == 'vip_bar') {
        return PaymentService.koboToNaira(
          (item['vip_bar_price'] as num?)?.toInt() ?? 0,
        );
      } else if (_selectedBarForSales == 'outside_bar') {
        return PaymentService.koboToNaira(
          (item['outside_bar_price'] as num?)?.toInt() ?? 0,
        );
      }
    } else if (userDepartment == 'vip_bar') {
      return PaymentService.koboToNaira(
        (item['vip_bar_price'] as num?)?.toInt() ?? 0,
      );
    } else if (userDepartment == 'outside_bar') {
      return PaymentService.koboToNaira(
        (item['outside_bar_price'] as num?)?.toInt() ?? 0,
      );
    }

    // Default to VIP bar price
    return PaymentService.koboToNaira(
      (item['vip_bar_price'] as num?)?.toInt() ?? 0,
    );
  }

  int _getStockForLocation(String locationName, String itemName) {
    final map = _stockByLocation[locationName.toLowerCase()];
    return map?[itemName.toLowerCase()] ?? 0;
  }

  int _getCurrentStock(Map<String, dynamic> item) {
    final name = (item['name'] as String?) ?? '';
    if (name.isEmpty) return 0;
    if (_selectedBar == null) {
      final dept = item['department'] as String?;
      if (dept == 'vip_bar') return _getStockForLocation('VIP Bar', name);
      if (dept == 'outside_bar') return _getStockForLocation('Outside Bar', name);
      return _getStockForLocation('VIP Bar', name) + _getStockForLocation('Outside Bar', name);
    }
    final locationName = _selectedBar == 'vip_bar' ? 'VIP Bar' : 'Outside Bar';
    return _getStockForLocation(locationName, name);
  }

  int _getCurrentStockForBar(Map<String, dynamic> item, String barKey) {
    final name = (item['name'] as String?) ?? '';
    if (name.isEmpty) return 0;
    final locationName = barKey == 'vip_bar' ? 'VIP Bar' : 'Outside Bar';
    return _getStockForLocation(locationName, name);
  }

  Widget _buildCurrentSaleSection() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
            'Current Sale',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          
          // Total
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green[100],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Total:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '₦${NumberFormat('#,##0.00').format(_saleTotal)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
          ),
          
                          const SizedBox(height: 16),
          
          // Items in current sale
          Expanded(
            child: _currentSale.isEmpty
                ? const Center(
                    child: Text(
                      'No items selected',
                      style: TextStyle(color: Colors.grey),
                    ),
                  )
                : ListView.builder(
                    itemCount: _currentSale.length,
                    itemBuilder: (context, index) {
                      final saleItem = _currentSale[index];
                      return _buildCurrentSaleItem(saleItem);
                    },
                  ),
          ),
          
                        const SizedBox(height: 16),
          
          // Customer info and payment
          TextField(
            controller: _customerNameController,
            decoration: const InputDecoration(
              labelText: 'Customer Name',
              border: OutlineInputBorder(),
            ),
          ),
          
          const SizedBox(height: 8),
          
          TextField(
            controller: _customerPhoneController,
            decoration: const InputDecoration(
              labelText: 'Customer Phone',
              border: OutlineInputBorder(),
            ),
          ),
          
          const SizedBox(height: 8),
          
          DropdownButtonFormField<String>(
            value: _paymentMethod,
            decoration: const InputDecoration(
              labelText: 'Payment Method',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'cash', child: Text('Cash')),
              DropdownMenuItem(value: 'card', child: Text('Card')),
              DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
              DropdownMenuItem(value: 'credit', child: Text('Credit (Pay Later)')),
            ],
            onChanged: (value) => setState(() => _paymentMethod = value!),
          ),
          
          // Show warning and fields for credit payment
          if (_paymentMethod == 'credit')
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    border: Border.all(color: Colors.orange[300]!),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Customer name and phone are required for credit sales. This will be recorded as a debt.',
                          style: TextStyle(color: Colors.orange[900], fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                TextField(
                  controller: _approvedByController,
                  decoration: const InputDecoration(
                    labelText: 'Approved By (Optional)',
                    hintText: 'Enter name of supervisor/staff who approved',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          
          const SizedBox(height: 16),
          
          // Action buttons
          Row(
                              children: [
              Expanded(
                child: ElevatedButton(
                  onPressed: _currentSale.isEmpty ? null : _processSale,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Process Sale'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: _currentSale.isEmpty ? null : _clearSale,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[600],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Clear'),
                ),
              ),
            ],
          ),
        ],
            ),
          );
  }

  Widget _buildCurrentSaleItem(Map<String, dynamic> saleItem) {
    final item = saleItem['item'] as Map<String, dynamic>;
    final quantity = saleItem['quantity'] as int;
    final price = saleItem['price'] as double;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.all(8),
                child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                    item['name'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text('₦${NumberFormat('#,##0.00').format(price)} each'),
                ],
              ),
            ),
            Row(
              children: [
                IconButton(
                  onPressed: () => _updateItemQuantity(item['id'], quantity - 1),
                  icon: const Icon(Icons.remove, size: 16),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                    Text(
                  '$quantity',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  onPressed: () => _updateItemQuantity(item['id'], quantity + 1),
                  icon: const Icon(Icons.add, size: 16),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
                IconButton(
                  onPressed: () => _removeItemFromSale(item['id']),
                  icon: const Icon(Icons.delete, size: 16, color: Colors.red),
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    ),
                  ],
                ),
          ],
        ),
      ),
    );
  }

  void _addItemToSale(Map<String, dynamic> item) {
                setState(() {
      final existingIndex = _currentSale.indexWhere((saleItem) => 
          saleItem['item']['id'] == item['id']);
      
      if (existingIndex != -1) {
        _currentSale[existingIndex]['quantity']++;
      } else {
        _currentSale.add({
          'item': item,
          'quantity': 1,
          'price': _getItemPrice(item),
        });
      }
      _calculateTotal();
    });
  }

  void _removeItemFromSale(String itemId) {
                setState(() {
      _currentSale.removeWhere((saleItem) => saleItem['item']['id'] == itemId);
      _calculateTotal();
    });
  }

  void _updateItemQuantity(String itemId, int newQuantity) {
    if (newQuantity <= 0) {
      _removeItemFromSale(itemId);
      return;
    }

    setState(() {
      final index = _currentSale.indexWhere((saleItem) => 
          saleItem['item']['id'] == itemId);
      if (index != -1) {
        _currentSale[index]['quantity'] = newQuantity;
        _calculateTotal();
      }
    });
  }

  void _calculateTotal() {
    _saleTotal = _currentSale.fold(0.0, (sum, saleItem) {
      return sum + (saleItem['quantity'] as int) * (saleItem['price'] as double);
    });
  }

  void _clearSale() {
    setState(() {
      _currentSale.clear();
      _saleTotal = 0.0;
      _customerNameController.clear();
      _customerPhoneController.clear();
      _approvedByController.clear();
      _paymentMethod = 'cash';
    });
  }

  Future<void> _processSale() async {
    if (_currentSale.isEmpty) return;

    // Verify user is logged in (clock-in no longer required for transactions)
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'You must be logged in to make transactions',
        );
      }
      return;
    }

    // Validate credit payment requirements
    if (_paymentMethod == 'credit') {
      if (_customerNameController.text.trim().isEmpty || _customerPhoneController.text.trim().isEmpty) {
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Customer name and phone are required for credit sales',
          );
        }
        return;
      }
    }

    try {
      final userId = authService.currentUser?.id ?? 'system';
      final supabase = _dataService.supabase;
      final user = authService.currentUser;
      final isBartender = _hasBartenderRole(authService, user);
      final isManagement = user?.roles.any((role) =>
              role == AppRole.owner || role == AppRole.manager) ??
          false;
      final barKey = _selectedBar ?? _selectedBarForSales ?? _bartenderDepartment(authService, user);
      if (isBartender && barKey == null) {
        throw Exception('Select a bar before making sales.');
      }
      
      if (supabase == null) {
        throw Exception('Database connection not available');
      }

      // Get location ID for the selected bar
      // CRITICAL: Fail fast if location not found - don't silently continue
      String? locationId;
      final locationName = (barKey ?? 'vip_bar') == 'vip_bar' ? 'VIP Bar' : 'Outside Bar';
      final locationResponse = await supabase
          .from('locations')
          .select('id')
          .eq('name', locationName)
          .maybeSingle();
      
      if (locationResponse == null) {
        throw Exception(
          'Location "$locationName" not found in database. '
          'Please ensure locations are properly configured before processing sales.'
        );
      }
      
      locationId = locationResponse['id'] as String?;
      
      if (locationId == null) {
        throw Exception('Failed to get location ID for $locationName');
      }

      // Get active bartender shift for optional tracking (not required for transactions)
      String? activeShiftId;
      try {
        final today = DateTime.now().toIso8601String().split('T')[0];
        final shiftResponse = await supabase
            .from('bartender_shifts')
            .select('id')
            .eq('bartender_id', userId)
            .eq('status', 'active')
            .eq('bar', barKey ?? 'vip_bar')
            .eq('date', today)
            .maybeSingle();
        activeShiftId = shiftResponse?['id'] as String?;
      } catch (e) {
        // Shift lookup failed, continue without shift tracking
        if (kDebugMode) {
          debugPrint('Warning: Could not find active shift: $e');
        }
      }
      // Note: No shift is required to make transactions - shift tracking is optional

      // Process each item sale
      for (final saleItem in _currentSale) {
        final item = saleItem['item'] as Map<String, dynamic>;
        final quantity = saleItem['quantity'] as int;
        // Price from inventory_items is already in kobo (per schema)
        // But UI displays in naira, so saleItem['price'] is in naira
        // Convert naira to kobo for database storage
        final priceInNaira = saleItem['price'] as double;
        final priceInKobo = PaymentService.nairaToKobo(priceInNaira);

        // CRITICAL: Validate stock availability before processing sale
        final currentStock = _getCurrentStockForBar(item, barKey ?? 'vip_bar');
        if (currentStock < quantity) {
          throw Exception(
            'Insufficient stock for ${item['name']}. Available: $currentStock ${item['unit'] ?? 'units'}, Requested: $quantity'
          );
        }

        // Record stock transaction for location-based stock tracking
        // This ensures each bar maintains its own stock
        // Find or create corresponding stock_item for this inventory_item
        // This allows proper per-location stock tracking via stock_transactions
        String? stockItemId;
        
        try {
          // First, try to find existing stock_item by name
          final stockItemResponse = await supabase
              .from('stock_items')
              .select('id')
              .eq('name', item['name'] as String)
              .maybeSingle();
          
          if (stockItemResponse != null) {
            stockItemId = stockItemResponse['id'] as String?;
          } else {
            // CRITICAL: Don't create stock_items on-the-fly during sales
            // This causes data inconsistency and potential duplicates
            // Stock items must be pre-created before sales can be processed
            throw Exception(
              'Stock item "${item['name']}" not found in stock_items table. '
              'Please create the stock item first before processing sales. '
              'This ensures proper inventory tracking and prevents data inconsistencies.'
            );
          }
          
          // Record sale in stock_transactions for proper location-based tracking
          // This ensures VIP Bar and Outside Bar maintain separate stock levels
          // CRITICAL: Fail fast if stock_transactions insert fails - don't mask errors
          // If stock_transactions fails, we MUST NOT update inventory_items to prevent inconsistency
          try {
            await supabase
                .from('stock_transactions')
                .insert({
                  'stock_item_id': stockItemId!,
                  'location_id': locationId,
                  'staff_profile_id': userId,
                  'transaction_type': 'Sale',
                  'quantity': -quantity, // Negative for sale
                  'notes': 'Bar sale - ${item['name']} at ${_selectedBar == 'vip_bar' ? 'VIP Bar' : 'Outside Bar'}',
                  'shift_id': activeShiftId,
                });
            
            // Stock ledger is the source of truth; no direct inventory_items update
          } catch (e) {
            // CRITICAL: If stock_transactions fails, throw error immediately
            // DO NOT fall back to updating inventory_items directly - this would mask the error
            // and cause data inconsistency between stock_transactions and inventory_items
            throw Exception(
              'Failed to record stock transaction for ${item['name']}. '
              'Sale cannot be processed. Error: $e'
            );
          }
        } catch (e) {
          // Re-throw the error from stock item lookup
          rethrow;
        }
      }

      // Calculate total sale amount in kobo
      final saleTotalInKobo = (_saleTotal * 100).toInt();

      // Create or update department_sales record (paid sales only)
      final today = DateTime.now().toIso8601String().split('T')[0];
      final department = barKey ?? 'vip_bar';
      if (_paymentMethod != 'credit') {
        try {
          final existingSales = await supabase
              .from('department_sales')
              .select()
              .eq('department', department)
              .eq('date', today)
              .maybeSingle();

          final paymentBreakdown = <String, int>{_paymentMethod: saleTotalInKobo};

          if (existingSales != null) {
            // Update existing record (only if same staff_id or NULL)
            final existingStaffId = existingSales['staff_id'] as String?;
            // Only update if it's the same staff member or aggregate (NULL)
            if (existingStaffId == null || existingStaffId == userId) {
              final currentBreakdown = (existingSales['payment_method_breakdown'] as Map<String, dynamic>?) ?? <String, dynamic>{};
              final updatedBreakdown = Map<String, dynamic>.from(currentBreakdown);
              final currentMethodTotal = (updatedBreakdown[_paymentMethod] as int? ?? 0);
              updatedBreakdown[_paymentMethod] = currentMethodTotal + saleTotalInKobo;

              await supabase
                  .from('department_sales')
                  .update({
                    'total_sales': (existingSales['total_sales'] as int) + saleTotalInKobo,
                    'transaction_count': (existingSales['transaction_count'] as int) + 1,
                    'payment_method_breakdown': updatedBreakdown,
                    'staff_id': userId, // Set staff_id if it was NULL, or keep existing
                  })
                  .eq('id', existingSales['id']);
            } else {
              // Different staff member - create separate record for this staff
              await supabase
                  .from('department_sales')
                  .insert({
                    'department': department,
                    'date': today,
                    'total_sales': saleTotalInKobo,
                    'transaction_count': 1,
                    'payment_method_breakdown': paymentBreakdown,
                    'recorded_by': userId,
                    'staff_id': userId,
                  });
            }
          } else {
            // Create new record
            await supabase
                .from('department_sales')
                .insert({
                  'department': department,
                  'date': today,
                  'total_sales': saleTotalInKobo,
                  'transaction_count': 1,
                  'payment_method_breakdown': paymentBreakdown,
                  'recorded_by': userId,
                  'staff_id': userId, // Track which staff member made the sales
                });
          }

          // Update active bartender shift total_sales if shift exists (paid only)
          // This allows real-time tracking of paid sales per shift
          if (activeShiftId != null) {
            try {
              final currentShift = await supabase
                  .from('bartender_shifts')
                  .select('total_sales')
                  .eq('id', activeShiftId)
                  .single();
              
              final currentTotalSales = (currentShift['total_sales'] as int? ?? 0);
              await supabase
                  .from('bartender_shifts')
                  .update({
                    'total_sales': currentTotalSales + saleTotalInKobo,
                  })
                  .eq('id', activeShiftId);
            } catch (e) {
              // Log error but don't fail the sale
              if (kDebugMode) {
                debugPrint('Warning: Could not update shift total_sales: $e');
              }
            }
          }
        } catch (e) {
          // Log error but don't fail the sale
          if (kDebugMode) {
            debugPrint('Error creating department_sales record: $e');
          }
        }
      }

      // If credit payment, record as debt (amount in kobo)
      if (_paymentMethod == 'credit') {
        final debt = {
          'debtor_name': _customerNameController.text.trim(),
          'debtor_phone': _customerPhoneController.text.trim(),
          'debtor_type': 'customer',
          'amount': saleTotalInKobo, // Convert to kobo
          'owed_to': 'P-ZED Luxury Hotels & Suites',
          'department': department,
          'source_department': department,
          'source_type': 'bar_sale',
          'reference_id': null,
          'reason': 'Bar sale on credit - ${_currentSale.length} items (Department: $department)',
          'date': DateTime.now().toIso8601String().split('T')[0],
          'status': 'outstanding',
          'sold_by': userId, // Staff who made the sale
          'approved_by': _approvedByController.text.trim().isEmpty 
              ? null 
              : _approvedByController.text.trim(), // Optional approved by
          'sale_id': null,
        };
        
        await _dataService.recordDebt(debt);
        
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Sale on credit recorded! Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)} - Debt created',
          );
        }
      } else {
        // Show success message for regular payment
        if (mounted) {
          ErrorHandler.showSuccessMessage(
            context,
            'Sale processed successfully! Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)}',
          );
        }
      }

      // Clear sale and refresh data
      _clearSale();
      _loadInventory();
      _loadTransactions();
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to process sale. Please try again.',
        );
      }
    }
  }

  void _showAddItemDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add New Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Item Name'),
              ),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(labelText: 'Description'),
              ),
              TextField(
                controller: _quantityController,
                decoration: const InputDecoration(labelText: 'Initial Quantity'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _unitController,
                decoration: const InputDecoration(labelText: 'Unit'),
              ),
              TextField(
                controller: _vipPriceController,
                decoration: const InputDecoration(labelText: 'VIP Bar Price (₦)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _outsidePriceController,
                decoration: const InputDecoration(labelText: 'Outside Bar Price (₦)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(labelText: 'Category'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await _saveNewItem();
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _saveNewItem() async {
    try {
      if (_selectedBar == null) {
        throw Exception('Please select a bar before adding a new item.');
      }
      final vipPriceNaira = double.tryParse(_vipPriceController.text) ?? 0.0;
      final outsidePriceNaira = double.tryParse(_outsidePriceController.text) ?? 0.0;
      final initialQty = int.tryParse(_quantityController.text) ?? 0;
      final item = {
        'name': _nameController.text,
        'description': _descriptionController.text,
        'unit': _unitController.text,
        'vip_bar_price': PaymentService.nairaToKobo(vipPriceNaira),
        'outside_bar_price': PaymentService.nairaToKobo(outsidePriceNaira),
        'category': _categoryController.text,
        'department': _selectedBar, // Assign to selected bar only
      };

      await _dataService.addInventoryItem(item);

      if (initialQty > 0) {
        final stockItem = await _dataService.supabase
            .from('stock_items')
            .select('id')
            .eq('name', _nameController.text)
            .maybeSingle();
        if (stockItem == null) {
          throw Exception('Stock item not found for ${_nameController.text}. Create it first.');
        }
        final locationName = _selectedBar == 'vip_bar' ? 'VIP Bar' : 'Outside Bar';
        final location = await _dataService.supabase
            .from('locations')
            .select('id')
            .eq('name', locationName)
            .maybeSingle();
        if (location == null) {
          throw Exception('Location "$locationName" not found.');
        }
        final authService = Provider.of<AuthService>(context, listen: false);
        final staffId = authService.currentUser?.id ?? 'system';
        await _dataService.recordStockTransaction({
          'stock_item_id': stockItem['id'],
          'location_id': location['id'],
          'staff_profile_id': staffId,
          'transaction_type': 'Adjustment',
          'quantity': initialQty,
          'notes': 'Initial stock for ${_nameController.text}',
        });
      }

      // Clear form
      _nameController.clear();
      _descriptionController.clear();
      _quantityController.clear();
      _unitController.clear();
      _vipPriceController.clear();
      _outsidePriceController.clear();
      _categoryController.clear();

      // Refresh inventory
      _loadInventory();

      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Item added successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to add item. Please try again.',
        );
      }
    }
  }
}