import 'package:flutter/material.dart';
// Supabase removed for mock-only mode
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
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
  String _paymentMethod = 'cash';

  // Search controller
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _updateTabController();
    _loadInventory();
    _loadTransactions();
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
    _searchController.dispose();
    super.dispose();
  }

  void _updateTabController() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isBartender = user?.roles.any((role) => 
        role.toString().contains('bartender') || 
        (authService.isRoleAssumed && authService.assumedRole.toString().contains('bartender'))) ?? false;
    
    final tabCount = isBartender ? 3 : 2; // Current Stock, Stock Movements, Make Sale (for bartenders)
    _tabController = TabController(length: tabCount, vsync: this);
  }

  Future<void> _loadInventory() async {
        setState(() {
      _isLoading = true;
    });

    try {
      final inventory = await _dataService.getInventoryItems();
      setState(() {
        _inventoryFuture = Future.value(inventory);
        _isLoading = false;
      });
    } catch (e) {
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
        final isBartender = (user?.roles.any((role) => role.name == 'bartender') ?? false) ||
            (authService.isRoleAssumed && authService.assumedRole?.name == 'bartender');
        
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
              const ContextAwareRoleButton(suggestedRole: AppRole.bartender),
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
    if (_selectedBar == null) return items;
    return items.where((item) {
      final department = item['department'] as String?;
      return department == _selectedBar || department == 'both';
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
            Text('Stock: ${item['current_stock'] ?? 0} ${item['unit'] ?? 'units'}'),
            if (item['vip_bar_price'] != null)
              Text('VIP Price: ₦${item['vip_bar_price']}'),
            if (item['outside_bar_price'] != null)
              Text('Outside Price: ₦${item['outside_bar_price']}'),
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
            Text('Unit Price: ₦${transaction['unit_price']}'),
            Text('Total: ₦${transaction['total_amount']}'),
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
        authService.assumedRole.toString().contains('bartender');

    if (!isManagement || !isBartenderAssumed) return const SizedBox.shrink();

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
              onChanged: (value) => setState(() => _selectedBarForSales = value),
            ),
          ),
        ],
      ),
    );
  }

  List<Map<String, dynamic>> _filterItemsForSales(List<Map<String, dynamic>> items) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final userDepartment = (user?.roles.any((role) => role.toString().contains('bartender')) ?? false) 
        ? ((user?.roles.isNotEmpty == true && user!.roles.first.toString().contains('vip')) ? 'vip_bar' : 'outside_bar')
        : '';

    // Filter by search
    var filtered = items.where((item) {
      final searchTerm = _searchController.text.toLowerCase();
      if (searchTerm.isEmpty) return true;
      return (item['name'] as String? ?? '').toLowerCase().contains(searchTerm) ||
             (item['category'] as String? ?? '').toLowerCase().contains(searchTerm);
    }).toList();

    // Filter by bar/department
    if (authService.isRoleAssumed && authService.assumedRole.toString().contains('bartender')) {
      // Management assuming bartender role
      filtered = filtered.where((item) {
        final department = item['department'] as String?;
        return department == _selectedBarForSales || department == 'both';
      }).toList();
    } else if (userDepartment.isNotEmpty) {
      // Regular bartender
      filtered = filtered.where((item) {
        final department = item['department'] as String?;
        return department == userDepartment || department == 'both';
      }).toList();
    }

    // Filter by stock availability
    return filtered.where((item) => ((item['vip_bar_price'] as num?)?.toDouble() ?? 0.0) > 0 || 
                                    ((item['outside_bar_price'] as num?)?.toDouble() ?? 0.0) > 0).toList();
  }

  Widget _buildSaleItemCard(Map<String, dynamic> item) {
    final price = _getItemPrice(item);
    final stock = item['current_stock'] as int? ?? 0;
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
                '₦${NumberFormat('#,##0').format(price)}',
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
    final userDepartment = (user?.roles.any((role) => role.toString().contains('bartender')) ?? false) 
        ? ((user?.roles.isNotEmpty == true && user!.roles.first.toString().contains('vip')) ? 'vip_bar' : 'outside_bar')
        : '';

    if (authService.isRoleAssumed && authService.assumedRole.toString().contains('bartender')) {
      // Management assuming bartender role
      if (_selectedBarForSales == 'vip_bar') {
        return (item['vip_bar_price'] as num?)?.toDouble() ?? 0.0;
      } else if (_selectedBarForSales == 'outside_bar') {
        return (item['outside_bar_price'] as num?)?.toDouble() ?? 0.0;
      }
    } else if (userDepartment == 'vip_bar') {
      return (item['vip_bar_price'] as num?)?.toDouble() ?? 0.0;
    } else if (userDepartment == 'outside_bar') {
      return (item['outside_bar_price'] as num?)?.toDouble() ?? 0.0;
    }

    // Default to VIP bar price
    return (item['vip_bar_price'] as num?)?.toDouble() ?? 0.0;
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
                  '₦${_saleTotal.toStringAsFixed(0)}',
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
          
          // Show warning for credit payment
          if (_paymentMethod == 'credit')
            Container(
              margin: const EdgeInsets.only(top: 8),
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
                  Text('₦${price.toStringAsFixed(0)} each'),
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
      _paymentMethod = 'cash';
    });
  }

  Future<void> _processSale() async {
    if (_currentSale.isEmpty) return;

    // Check if staff is clocked in
    final authService = Provider.of<AuthService>(context, listen: false);
    if (!authService.canMakeTransactions()) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'You must clock in before making transactions',
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
      
      if (supabase == null) {
        throw Exception('Database connection not available');
      }

      // Get location ID for the selected bar
      String? locationId;
      try {
        final locationName = _selectedBar == 'vip_bar' ? 'VIP Bar' : 'Outside Bar';
        final locationResponse = await supabase
            .from('locations')
            .select('id')
            .eq('name', locationName)
            .maybeSingle();
        locationId = locationResponse?['id'] as String?;
      } catch (e) {
        // Location lookup failed, continue without it for inventory update
      }

      // Get active bartender shift for shift tracking
      String? activeShiftId;
      try {
        final today = DateTime.now().toIso8601String().split('T')[0];
        final shiftResponse = await supabase
            .from('bartender_shifts')
            .select('id')
            .eq('bartender_id', userId)
            .eq('status', 'active')
            .eq('date', today)
            .maybeSingle();
        activeShiftId = shiftResponse?['id'] as String?;
      } catch (e) {
        // Shift lookup failed, continue without shift tracking
        print('Warning: Could not find active shift: $e');
      }

      // Process each item sale
      for (final saleItem in _currentSale) {
        final item = saleItem['item'] as Map<String, dynamic>;
        final quantity = saleItem['quantity'] as int;
        final priceInNaira = saleItem['price'] as double;
        final priceInKobo = (priceInNaira * 100).toInt(); // Convert to kobo

        // Record stock transaction for location-based stock tracking
        // This ensures each bar maintains its own stock
        if (locationId != null) {
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
              // Create new stock_item if it doesn't exist
              final newStockItem = await supabase
                  .from('stock_items')
                  .insert({
                    'name': item['name'],
                    'description': item['description'],
                    'unit': item['unit'] ?? 'units',
                  })
                  .select('id')
                  .single();
              stockItemId = newStockItem['id'] as String;
              
              // Optionally, update inventory_item to link to stock_item (if schema allows)
              // This would require adding stock_item_id column to inventory_items
            }
            
            // Record sale in stock_transactions for proper location-based tracking
            // This ensures VIP Bar and Outside Bar maintain separate stock levels
            await supabase
                .from('stock_transactions')
                .insert({
                  'stock_item_id': stockItemId!,
                  'location_id': locationId,
                  'staff_profile_id': userId,
                  'transaction_type': 'Sale',
                  'quantity': -quantity, // Negative for sale
                  'notes': 'Bar sale - ${item['name']} at ${_selectedBar == 'vip_bar' ? 'VIP Bar' : 'Outside Bar'}',
                });
          } catch (e) {
            // If stock_transactions recording fails, fall back to updating inventory_items
            // This is not ideal but ensures the sale is recorded
            print('Warning: Could not record in stock_transactions: $e');
            final currentStock = item['current_stock'] as int? ?? 0;
            await supabase
                .from('inventory_items')
                .update({
                  'current_stock': currentStock - quantity,
                })
                .eq('id', item['id']);
          }
        } else {
          // Fallback: update global stock if location lookup failed
          final currentStock = item['current_stock'] as int? ?? 0;
          await supabase
              .from('inventory_items')
              .update({
                'current_stock': currentStock - quantity,
              })
              .eq('id', item['id']);
        }
      }

      // Calculate total sale amount in kobo
      final saleTotalInKobo = (_saleTotal * 100).toInt();

      // Create or update department_sales record
      final today = DateTime.now().toIso8601String().split('T')[0];
      final department = _selectedBar ?? 'vip_bar';
      
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

        // Update active bartender shift total_sales if shift exists
        // This allows real-time tracking of sales per shift
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
            print('Warning: Could not update shift total_sales: $e');
          }
        }
      } catch (e) {
        // Log error but don't fail the sale
        print('Error creating department_sales record: $e');
      }

      // If credit payment, record as debt (amount in kobo)
      if (_paymentMethod == 'credit') {
        final debt = {
          'debtor_name': _customerNameController.text.trim(),
          'debtor_phone': _customerPhoneController.text.trim(),
          'debtor_type': 'customer',
          'amount': saleTotalInKobo, // Convert to kobo
          'owed_to': 'P-ZED Luxury Hotels & Suites',
          'reason': 'Bar sale on credit - ${_currentSale.length} items',
          'date': DateTime.now().toIso8601String(),
          'due_date': DateTime.now().add(const Duration(days: 30)).toIso8601String(),
          'status': 'pending',
          'department': department,
        };
        
        await _dataService.recordDebt(debt);
        
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Sale on credit recorded! Total: ₦${_saleTotal.toStringAsFixed(0)} - Debt created',
          );
        }
      } else {
        // Show success message for regular payment
        if (mounted) {
          ErrorHandler.showSuccessMessage(
            context,
            'Sale processed successfully! Total: ₦${_saleTotal.toStringAsFixed(0)}',
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
                decoration: const InputDecoration(labelText: 'VIP Bar Price'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: _outsidePriceController,
                decoration: const InputDecoration(labelText: 'Outside Bar Price'),
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
      final item = {
        'name': _nameController.text,
        'description': _descriptionController.text,
        'current_stock': int.parse(_quantityController.text),
        'unit': _unitController.text,
        'vip_bar_price': double.parse(_vipPriceController.text),
        'outside_bar_price': double.parse(_outsidePriceController.text),
        'category': _categoryController.text,
        'department': 'both', // Default to both bars
      };

      await _dataService.addInventoryItem(item);

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