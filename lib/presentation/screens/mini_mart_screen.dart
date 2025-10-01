import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class MiniMartScreen extends StatefulWidget {
  const MiniMartScreen({super.key});

  @override
  State<MiniMartScreen> createState() => _MiniMartScreenState();
}

class _MiniMartScreenState extends State<MiniMartScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
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
    _tabController = TabController(length: 3, vsync: this);
    _loadMiniMartData();
    _searchController.addListener(_filterItems);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadMiniMartData() async {
    try {
      // Load mini mart items
      final itemsResponse = await _supabase
          .from('mini_mart_items')
          .select('*')
          .order('name');
      
      // Load sales history
      final salesResponse = await _supabase
          .from('mini_mart_sales')
          .select('*')
          .order('created_at', ascending: false)
          .limit(50);

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
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error loading data: $e'), backgroundColor: Colors.red),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add items to the sale'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      final userId = _supabase.auth.currentUser!.id;
      
      // Create sale record
      final saleResponse = await _supabase.from('mini_mart_sales').insert({
        'receptionist_id': userId,
        'customer_name': _customerNameController.text.trim().isNotEmpty 
            ? _customerNameController.text.trim() 
            : 'Walk-in Customer',
        'customer_phone': _customerPhoneController.text.trim(),
        'payment_method': _paymentMethod,
        'total_amount': _saleTotal,
        'sale_date': DateTime.now().toIso8601String(),
        'items': _currentSale.map((item) => {
          'item_id': item['id'],
          'item_name': item['name'],
          'quantity': item['quantity'],
          'unit_price': item['price'],
          'total_price': (item['price'] as num).toDouble() * (item['quantity'] as int),
        }).toList(),
      }).select('id').single();

      // Update stock levels
      for (final item in _currentSale) {
        await _supabase.from('mini_mart_items').update({
          'current_stock': (item['current_stock'] as int) - (item['quantity'] as int),
        }).eq('id', item['id']);
      }

      // Clear sale
      _clearSale();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sale completed! Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)}'),
          backgroundColor: Colors.green,
        ),
      );

      await _loadMiniMartData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error processing sale: $e'), backgroundColor: Colors.red),
      );
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
    return Scaffold(
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
              tabs: const [
                Tab(text: 'Make Sale', icon: Icon(Icons.shopping_cart)),
                Tab(text: 'Sales History', icon: Icon(Icons.history)),
                Tab(text: 'Inventory', icon: Icon(Icons.inventory)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildSalesInterface(),
                _buildSalesHistory(),
                _buildInventory(),
              ],
            ),
          ),
        ],
      ),
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
                          ],
                          onChanged: (value) => setState(() => _paymentMethod = value ?? 'Cash'),
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
                          Text('Payment: ${sale['payment_method']}'),
                          Text(
                            'Date: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.parse(sale['sale_date']))}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      trailing: Text(
                        '₦${NumberFormat('#,##0.00').format(sale['total_amount'])}',
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
