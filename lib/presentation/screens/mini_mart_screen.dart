import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';

class MiniMartScreen extends StatefulWidget {
  const MiniMartScreen({super.key});

  @override
  State<MiniMartScreen> createState() => _MiniMartScreenState();
}

class _MiniMartScreenState extends State<MiniMartScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final _dataService = DataService();
  final _supabase = Supabase.instance.client;
  
  // Sales data
  List<Map<String, dynamic>> _miniMartItems = [];
  List<Map<String, dynamic>> _currentSale = [];
  List<Map<String, dynamic>> _salesHistory = [];
  double _saleTotal = 0.0;
  bool _isLoading = true;
  
  // Customer info
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  String _paymentMethod = 'Cash';
  
  // Search
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> _filteredItems = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMiniMartData();
    _searchController.addListener(_filterItems);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tab controller will be updated in build method via Consumer
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMiniMartData() async {
    try {
      // Load mini mart items from mock data
      final itemsResponse = await _dataService.getMiniMartItems();
      
      // Load sales history from mock data
      final salesResponse = await _dataService.getMiniMartSales();

      if (mounted) {
        setState(() {
          _miniMartItems = List<Map<String, dynamic>>.from(itemsResponse);
          _filteredItems = _miniMartItems;
          _salesHistory = List<Map<String, dynamic>>.from(salesResponse);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load mini mart data. Please check your connection and try again.',
          onRetry: _loadMiniMartData,
        );
      }
    }
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _miniMartItems.where((item) {
        return item['name']?.toString().toLowerCase().contains(query) ?? false;
      }).toList();
    });
  }

  void _addItemToSale(Map<String, dynamic> item) {
    final existingIndex = _currentSale.indexWhere((saleItem) => saleItem['id'] == item['id']);
    
    setState(() {
      if (existingIndex != -1) {
        _currentSale[existingIndex]['quantity'] = (_currentSale[existingIndex]['quantity'] ?? 0) + 1;
      } else {
        _currentSale.add({
          ...item,
          'quantity': 1,
        });
      }
      _calculateTotal();
    });
  }

  void _removeItemFromSale(int index) {
    setState(() {
      _currentSale.removeAt(index);
      _calculateTotal();
    });
  }

  void _updateItemQuantity(int index, int quantity) {
    if (quantity <= 0) {
      _removeItemFromSale(index);
    } else {
      setState(() {
        _currentSale[index]['quantity'] = quantity;
        _calculateTotal();
      });
    }
  }

  void _calculateTotal() {
    _saleTotal = _currentSale.fold(0.0, (sum, item) {
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final quantity = (item['quantity'] as int?) ?? 0;
      return sum + (price * quantity);
    });
  }

  Future<void> _processSale() async {
    if (_currentSale.isEmpty) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please add items to the sale',
        );
      }
      return;
    }

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
    if (_paymentMethod == 'Credit') {
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
      final customerName = _customerNameController.text.trim().isNotEmpty 
          ? _customerNameController.text.trim() 
          : 'Walk-in Customer';
      final customerPhone = _customerPhoneController.text.trim();
      final saleDate = DateTime.now().toIso8601String();
      
      // Create one mini_mart_sales record per item (schema supports single item per record)
      // _currentSale structure: {'id': itemId, 'name': itemName, 'price': price, 'quantity': quantity, ...}
      for (final saleItem in _currentSale) {
        final itemId = saleItem['id'] as String;
        final quantity = saleItem['quantity'] as int;
        final priceInNaira = (saleItem['price'] as num).toDouble();
        final priceInKobo = (priceInNaira * 100).toInt(); // Convert to kobo
        final totalAmountInKobo = quantity * priceInKobo;

        // Create sale record for this item
        await _supabase
            .from('mini_mart_sales')
            .insert({
              'item_id': itemId,
              'quantity': quantity,
              'unit_price': priceInKobo, // In kobo
              'total_amount': totalAmountInKobo, // In kobo
              'sale_date': saleDate,
              'payment_method': _paymentMethod.toLowerCase(),
              'customer_name': customerName,
              'sold_by': userId,
            });

        // Update stock levels for this item
        // Get current stock from database (schema uses 'stock_quantity' not 'current_stock')
        final itemData = await _supabase
            .from('mini_mart_items')
            .select('stock_quantity')
            .eq('id', itemId)
            .single();
        
        final currentStock = (itemData['stock_quantity'] as int?) ?? 0;
        final newStock = currentStock - quantity;

        await _supabase
            .from('mini_mart_items')
            .update({'stock_quantity': newStock})
            .eq('id', itemId);
      }

      // Calculate total sale amount in kobo for debt/income records
      final saleTotalInKobo = (_saleTotal * 100).toInt();

      // Create or update department_sales record
      final today = DateTime.now().toIso8601String().split('T')[0];
      try {
        final existingSales = await _supabase
            .from('department_sales')
            .select()
            .eq('department', 'mini_mart')
            .eq('date', today)
            .maybeSingle();

        final paymentBreakdown = <String, int>{_paymentMethod.toLowerCase(): saleTotalInKobo};

        if (existingSales != null) {
          final currentBreakdown = (existingSales['payment_method_breakdown'] as Map<String, dynamic>?) ?? <String, dynamic>{};
          final updatedBreakdown = Map<String, dynamic>.from(currentBreakdown);
          final currentMethodTotal = (updatedBreakdown[_paymentMethod.toLowerCase()] as int? ?? 0);
          updatedBreakdown[_paymentMethod.toLowerCase()] = currentMethodTotal + saleTotalInKobo;

          await _supabase
              .from('department_sales')
              .update({
                'total_sales': (existingSales['total_sales'] as int) + saleTotalInKobo,
                'transaction_count': (existingSales['transaction_count'] as int) + 1,
                'payment_method_breakdown': updatedBreakdown,
              })
              .eq('id', existingSales['id']);
        } else {
          await _supabase
              .from('department_sales')
              .insert({
                'department': 'mini_mart',
                'date': today,
                'total_sales': saleTotalInKobo,
                'transaction_count': 1,
                'payment_method_breakdown': paymentBreakdown,
                'recorded_by': userId,
              });
        }
      } catch (e) {
        print('Warning: Could not create department_sales record: $e');
      }

      // If credit payment, record as debt (amount in kobo)
      if (_paymentMethod == 'Credit') {
        final debt = {
          'debtor_name': customerName,
          'debtor_phone': customerPhone,
          'debtor_type': 'customer',
          'amount': saleTotalInKobo, // Convert to kobo
          'owed_to': 'P-ZED Luxury Hotels & Suites',
          'reason': 'Mini Mart sale on credit - ${_currentSale.length} items',
          'date': DateTime.now().toIso8601String().split('T')[0],
          'due_date': DateTime.now().add(const Duration(days: 30)).toIso8601String().split('T')[0],
          'status': 'pending',
          'department': 'mini_mart',
        };
        
        await _dataService.recordDebt(debt);
        
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Sale on credit recorded! Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)} - Debt created',
          );
        }
      } else {
        if (mounted) {
          ErrorHandler.showSuccessMessage(
            context,
            'Sale completed! Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)}',
          );
        }
      }

      // Clear sale
      _clearSale();

      await _loadMiniMartData();
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to process sale. Please check your connection and try again.',
          onRetry: _processSale,
        );
      }
    }
  }

  void _clearSale() {
    setState(() {
      _currentSale.clear();
      _saleTotal = 0.0;
      _customerNameController.clear();
      _customerPhoneController.clear();
      _paymentMethod = 'Cash';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final user = authService.currentUser;
        final isReceptionist = (user?.roles.any((r) => r.name == 'receptionist') ?? false) ||
            (authService.isRoleAssumed && authService.assumedRole?.name == 'receptionist');

        // Update tab controller if needed
        final tabCount = isReceptionist ? 3 : 2;
        if (_tabController == null) {
          _tabController = TabController(length: tabCount, vsync: this);
        } else if (_tabController!.length != tabCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _tabController?.dispose();
                _tabController = TabController(length: tabCount, vsync: this);
              });
            }
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Mini Mart'),
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
            leading: Navigator.of(context).canPop() ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ) : null,
            actions: [
              ContextAwareRoleButton(suggestedRole: AppRole.receptionist),
            ],
          ),
          backgroundColor: Colors.grey[50],
          body: Column(
            children: [
              _buildHeader(context),
              Container(
                color: Colors.white,
                child: TabBar(
                  controller: _tabController,
                  labelColor: Colors.green[800],
                  unselectedLabelColor: Colors.grey[600],
                  indicatorColor: Colors.green[800],
                  tabs: [
                    if (isReceptionist) const Tab(text: 'Make Sale', icon: Icon(Icons.shopping_cart)),
                    const Tab(text: 'Sales History', icon: Icon(Icons.history)),
                    const Tab(text: 'Inventory', icon: Icon(Icons.inventory)),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    if (isReceptionist) _buildSalesInterface(),
                    _buildSalesHistory(),
                    _buildInventory(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mini Mart Sales',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage mini mart sales and inventory',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.store, color: Colors.green[700], size: 16),
                const SizedBox(width: 8),
                Text(
                  'Mini Mart',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesInterface() {
    return Row(
      children: [
        // Items Grid
        Expanded(
          flex: 2,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search items...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            childAspectRatio: 0.8,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _filteredItems.length,
                          itemBuilder: (context, index) {
                            final item = _filteredItems[index];
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
                                            color: Colors.grey[200],
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                          child: const Icon(Icons.inventory, size: 32),
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
                                        '₦${NumberFormat('#,##0.00').format(item['price'])}',
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
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
        // Sale Cart
        Expanded(
          flex: 1,
          child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.green[50],
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(12),
                      topRight: Radius.circular(12),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.shopping_cart, color: Colors.green),
                      const SizedBox(width: 8),
                      const Text(
                        'Current Sale',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '₦${NumberFormat('#,##0.00').format(_saleTotal)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _currentSale.isEmpty
                      ? const Center(
                          child: Text(
                            'No items in cart',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          itemCount: _currentSale.length,
                          itemBuilder: (context, index) {
                            final item = _currentSale[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.green[100],
                                child: Text(
                                  '${item['quantity']}',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                item['name']?.toString() ?? 'Unknown',
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                '₦${NumberFormat('#,##0.00').format(item['price'])} each',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 16),
                                    onPressed: () => _updateItemQuantity(
                                      index,
                                      (item['quantity'] as int) - 1,
                                    ),
                                  ),
                                  Text('${item['quantity']}'),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 16),
                                    onPressed: () => _updateItemQuantity(
                                      index,
                                      (item['quantity'] as int) + 1,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (_currentSale.isNotEmpty) ...[
                  const Divider(),
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        // Customer Info
                        TextField(
                          controller: _customerNameController,
                          decoration: const InputDecoration(
                            labelText: 'Customer Name (Optional)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _customerPhoneController,
                          decoration: const InputDecoration(
                            labelText: 'Phone (Optional)',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                        ),
                        const SizedBox(height: 8),
                        DropdownButtonFormField<String>(
                          value: _paymentMethod,
                          decoration: const InputDecoration(
                            labelText: 'Payment Method',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                            DropdownMenuItem(value: 'Card', child: Text('Card')),
                            DropdownMenuItem(value: 'Transfer', child: Text('Transfer')),
                            DropdownMenuItem(value: 'Credit', child: Text('Credit (Pay Later)')),
                          ],
                          onChanged: (value) => setState(() => _paymentMethod = value ?? 'Cash'),
                        ),
                        
                        // Show warning for credit payment
                        if (_paymentMethod == 'Credit')
                          Container(
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: Colors.orange[50],
                              border: Border.all(color: Colors.orange[300]!),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.warning_amber, color: Colors.orange[700], size: 16),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Customer info required. Will be recorded as debt.',
                                    style: TextStyle(color: Colors.orange[900], fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: _clearSale,
                                child: const Text('Clear'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _processSale,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[800],
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Process Sale'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSalesHistory() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(
                    'Sales History',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_salesHistory.length} Sales',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (_salesHistory.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                child: const Center(
                  child: Text('No sales recorded yet'),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _salesHistory.length,
                  itemBuilder: (context, index) {
                    final sale = _salesHistory[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green[100],
                        child: Icon(Icons.receipt, color: Colors.green[700]),
                      ),
                      title: Text(
                        sale['customer_name']?.toString() ?? 'Walk-in Customer',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Payment: ${sale['payment_method']?.toString() ?? 'N/A'}'),
                          Text(
                            'Date: ${sale['sale_date'] != null ? DateFormat('MMM dd, yyyy HH:mm').format(DateTime.parse(sale['sale_date'])) : 'N/A'}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      trailing: Text(
                        '₦${NumberFormat('#,##0.00').format(sale['total_amount'] ?? 0)}',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventory() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(
                    'Mini Mart Inventory',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_miniMartItems.length} Items',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (_miniMartItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                child: const Center(
                  child: Text('No items in mini mart'),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _miniMartItems.length,
                  itemBuilder: (context, index) {
                    final item = _miniMartItems[index];
                    final stock = item['current_stock'] as int? ?? 0;
                    final isLowStock = stock <= 5;
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isLowStock ? Colors.red[100] : Colors.green[100],
                        child: Icon(
                          Icons.inventory,
                          color: isLowStock ? Colors.red[700] : Colors.green[700],
                        ),
                      ),
                      title: Text(
                        item['name']?.toString() ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Price: ₦${NumberFormat('#,##0.00').format(item['price'])}'),
                          Text(
                            'Stock: $stock',
                            style: TextStyle(
                              color: isLowStock ? Colors.red : Colors.grey[600],
                              fontWeight: isLowStock ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      trailing: isLowStock
                          ? Chip(
                              label: const Text('Low Stock'),
                              backgroundColor: Colors.red[100],
                              labelStyle: TextStyle(color: Colors.red[700]),
                            )
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}
