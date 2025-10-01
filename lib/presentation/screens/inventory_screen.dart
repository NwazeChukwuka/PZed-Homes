import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class InventoryScreen extends StatefulWidget {
  const InventoryScreen({super.key});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  final _supabase = Supabase.instance.client;

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
  final _categoryController = TextEditingController();

  // Stream for transactions
  final _transactionStream = Supabase.instance.client
      .from('stock_transactions')
      .stream(primaryKey: ['id'])
      .order('created_at', ascending: false);

  @override
  void initState() {
    super.initState();
    _inventoryFuture = _loadInventory();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<List<Map<String, dynamic>>> _loadInventory() async {
    try {
      final response = await _supabase
          .from('inventory_items')
          .select('*, categories(name)')
          .order('name');

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      ErrorHandler.handleError(context, e);
      return [];
    }
  }

  Future<void> _loadTransactions() async {
    try {
      final response = await _supabase
          .from('stock_transactions')
          .select('*')
          .order('created_at', ascending: false);
      
      if (mounted) {
        setState(() {
          _allTransactions = List<Map<String, dynamic>>.from(response);
          _updatePagination();
        });
      }
    } catch (e) {
      ErrorHandler.handleError(context, e);
    }
  }

  void _updatePagination() {
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, _allTransactions.length);
    setState(() {
      _currentPageTransactions = _allTransactions.sublist(startIndex, endIndex);
    });
  }

  Future<void> _showAddItemDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Add New Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Name *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _quantityController,
                        decoration: const InputDecoration(
                          labelText: 'Initial Quantity *',
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _unitController,
                        decoration: const InputDecoration(
                          labelText: 'Unit (e.g., kg, liters) *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _categoryController,
                  decoration: const InputDecoration(
                    labelText: 'Category *',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                _clearControllers();
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Add Item'),
              onPressed: () async {
                if (_nameController.text.trim().isEmpty ||
                    _quantityController.text.trim().isEmpty ||
                    _unitController.text.trim().isEmpty ||
                    _categoryController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please fill in all required fields'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                try {
                  final quantity = int.tryParse(_quantityController.text.trim());
                  if (quantity == null || quantity < 0) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Please enter a valid quantity'),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }

                  // Insert new inventory item
                  await _supabase.from('inventory_items').insert({
                    'name': _nameController.text.trim(),
                    'description': _descriptionController.text.trim(),
                    'current_stock': quantity,
                    'unit': _unitController.text.trim(),
                    'category_id': await _getOrCreateCategory(_categoryController.text.trim()),
                  });

                  _clearControllers();
                  
                  if (mounted) {
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Item added successfully!'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    // Refresh inventory
                    _inventoryFuture = _loadInventory();
                    setState(() {});
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Error adding item: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _clearControllers() {
    _nameController.clear();
    _descriptionController.clear();
    _quantityController.clear();
    _unitController.clear();
    _categoryController.clear();
  }

  Future<String> _getOrCreateCategory(String categoryName) async {
    try {
      // Try to find existing category
      final existing = await _supabase
          .from('categories')
          .select('id')
          .eq('name', categoryName)
          .maybeSingle();
      
      if (existing != null) {
        return existing['id'];
      }
      
      // Create new category
      final newCategory = await _supabase
          .from('categories')
          .insert({'name': categoryName})
          .select('id')
          .single();
      
      return newCategory['id'];
    } catch (e) {
      // Fallback to a default category ID if category operations fail
      return '1';
    }
  }

  Color _getTransactionTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'in':
      case 'restock':
      case 'purchase':
        return Colors.green;
      case 'out':
      case 'usage':
      case 'sale':
        return Colors.red;
      case 'transfer':
        return Colors.blue;
      case 'adjustment':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        backgroundColor: Colors.grey[50],
        body: Column(
          children: [
            _buildHeader(context),
            Container(
              color: Colors.white,
              child: const TabBar(
                labelColor: Colors.green,
                unselectedLabelColor: Colors.grey,
                indicatorColor: Colors.green,
                tabs: [
                  Tab(text: 'Items', icon: Icon(Icons.inventory_2)),
                  Tab(text: 'Transactions', icon: Icon(Icons.list_alt)),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  // Inventory Items Tab
                  _buildInventoryItemsTab(),
                  // Transactions Tab
                  _buildTransactionsTab(),
                ],
              ),
            ),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          label: const Text('Add Item'),
          icon: const Icon(Icons.add),
          onPressed: _showAddItemDialog,
          backgroundColor: Colors.green[800],
        ),
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
                  'Inventory Management',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage inventory items and track stock transactions',
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
                Icon(Icons.inventory_2, color: Colors.green[700], size: 16),
                const SizedBox(width: 8),
                Text(
                  'Stock Management',
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

  Widget _buildInventoryItemsTab() {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadInventory,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _inventoryFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 48, color: Colors.red),
                          const SizedBox(height: 16),
                          Text('Error: ${snapshot.error}', textAlign: TextAlign.center),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: _loadInventory,
                            child: const Text('Try Again'),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                final items = snapshot.data ?? [];
                if (items.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.inventory_2, size: 64, color: Colors.grey.shade400),
                        const SizedBox(height: 16),
                        const Text(
                          'No inventory items found',
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(24),
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
                    child: ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      itemCount: items.length,
                      itemBuilder: (context, index) {
                        final item = items[index];
                        final currentStock = item['current_stock'] as int? ?? 0;
                        final minStock = item['min_stock'] as int? ?? 0;
                        final unit = item['unit'] as String? ?? 'units';

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          elevation: 2,
                          child: ListTile(
                            leading: Icon(
                              Icons.inventory_2,
                              color: _getStockLevelColor(currentStock, minStock),
                            ),
                            title: Text(
                              item['name'] as String? ?? 'Unknown Item',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('Category: ${item['categories']?['name'] ?? 'Uncategorized'}'),
                                Text('Stock: $currentStock $unit'),
                                if (minStock > 0) Text('Min required: $minStock $unit'),
                              ],
                            ),
                            trailing: Chip(
                              label: Text(
                                '$currentStock',
                                style: TextStyle(
                                  color: _getStockLevelColor(currentStock, minStock),
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              backgroundColor: _getStockLevelColor(currentStock, minStock).withOpacity(0.1),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                );
              },
            ),
          );
  }

  Widget _buildTransactionsTab() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: _transactionStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final transactions = snapshot.data!;
        _allTransactions = transactions;
        _updatePagination();
        
        if (transactions.isEmpty) {
          return const Center(child: Text('No transactions found'));
        }

        return Padding(
          padding: const EdgeInsets.all(24),
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
            child: PaginatedDataTable(
              header: Container(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Text(
                      'Stock Transactions',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_allTransactions.length} Total Transactions',
                      style: TextStyle(
                        color: Colors.grey[600],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              columns: const [
                DataColumn(label: Text('Item Name')),
                DataColumn(label: Text('Location')),
                DataColumn(label: Text('Quantity')),
                DataColumn(label: Text('Type')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Notes')),
              ],
              source: _TransactionDataSource(
                transactions: _currentPageTransactions,
                getTransactionTypeColor: _getTransactionTypeColor,
              ),
              rowsPerPage: _rowsPerPage,
              onPageChanged: (pageIndex) {
                setState(() {
                  _currentPage = pageIndex;
                });
                _updatePagination();
              },
              onRowsPerPageChanged: (newRowsPerPage) {
                setState(() {
                  _rowsPerPage = newRowsPerPage ?? 10;
                  _currentPage = 0;
                });
                _updatePagination();
              },
              availableRowsPerPage: const [5, 10, 20, 50],
              showFirstLastButtons: true,
            ),
          ),
        );
      },
    );
  }

  Color _getStockLevelColor(int current, int min) {
    if (current <= 0) return Colors.red;
    if (current <= min) return Colors.orange;
    return Colors.green;
  }
}

class _TransactionDataSource extends DataTableSource {
  final List<Map<String, dynamic>> transactions;
  final Color Function(String) getTransactionTypeColor;

  _TransactionDataSource({
    required this.transactions,
    required this.getTransactionTypeColor,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= transactions.length) return null;
    
    final transaction = transactions[index];
    final itemName = transaction['item_name']?.toString() ?? 'Unknown';
    final location = transaction['location']?.toString() ?? 'N/A';
    final quantity = transaction['quantity']?.toString() ?? '0';
    final type = transaction['transaction_type']?.toString() ?? 'Unknown';
    final date = transaction['created_at'] != null 
        ? DateFormat('MMM dd, yyyy HH:mm').format(DateTime.parse(transaction['created_at']))
        : 'N/A';
    final notes = transaction['notes']?.toString() ?? '';

    return DataRow(
      cells: [
        DataCell(
          Text(
            itemName,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        DataCell(Text(location)),
        DataCell(
          Text(
            quantity,
            style: TextStyle(
              color: getTransactionTypeColor(type),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        DataCell(
          Chip(
            label: Text(
              type,
              style: TextStyle(
                color: getTransactionTypeColor(type),
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
            backgroundColor: getTransactionTypeColor(type).withOpacity(0.1),
            side: BorderSide(color: getTransactionTypeColor(type).withOpacity(0.3)),
          ),
        ),
        DataCell(Text(date)),
        DataCell(
          Text(
            notes,
            style: TextStyle(
              color: Colors.grey[600],
              fontSize: 12,
            ),
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => transactions.length;

  @override
  int get selectedRowCount => 0;
}