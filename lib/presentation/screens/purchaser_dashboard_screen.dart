import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

class PurchaserDashboardScreen extends StatefulWidget {
  const PurchaserDashboardScreen({super.key});

  @override
  State<PurchaserDashboardScreen> createState() => _PurchaserDashboardScreenState();
}

class _PurchaserDashboardScreenState extends State<PurchaserDashboardScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final _dataService = DataService();
  
  // Form controllers
  final _amountController = TextEditingController();
  final _itemNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitController = TextEditingController();
  final _categoryController = TextEditingController();
  final _supplierController = TextEditingController();
  final _notesController = TextEditingController();
  
  // Budget tracking (stored in kobo)
  int _monthlyBudgetKobo = 0;
  int _spentKobo = 0;
  int _varianceKobo = 0;
  bool _budgetExceeded = false;
  bool _budgetSet = false;
  List<Map<String, dynamic>> _purchaseHistory = [];
  List<Map<String, dynamic>> _pendingOrders = [];
  bool _isLoading = true;
  List<Map<String, dynamic>> _suppliers = [];
  String? _selectedSupplierId;

  @override
  void initState() {
    super.initState();
    // Initialize with default tab count
    _tabController = TabController(length: 2, vsync: this);
    _loadBudgetData();
    _loadSuppliers();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTabController();
  }
  
  void _updateTabController() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isPurchaser = (user?.roles.any((r) => r.name == 'purchaser') ?? false);
    final isAssumedPurchaser = authService.hasAssumedRole(AppRole.purchaser);
    final isOwnerOrManager = user?.roles.any((r) => r.name == 'owner' || r.name == 'manager') ?? false;
    final showRecordPurchase = (isPurchaser || isAssumedPurchaser) && !(isOwnerOrManager && !isAssumedPurchaser);
    
    final tabCount = showRecordPurchase ? 3 : 2;
    if (!mounted || _tabController == null || _tabController!.length == tabCount) return;
    
    _tabController?.dispose();
    _tabController = TabController(length: tabCount, vsync: this);
  }

  @override
  void dispose() {
    _tabController?.dispose();
    _amountController.dispose();
    _itemNameController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _categoryController.dispose();
    _supplierController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadBudgetData() async {
    try {
      final now = DateTime.now();
      final monthStart = DateTime(now.year, now.month, 1);
      final nextMonthStart = DateTime(now.year, now.month + 1, 1);
      final monthEnd = nextMonthStart.subtract(const Duration(milliseconds: 1));

      // Load purchase orders for current month
      final orders = await _dataService.getPurchaseOrders(
        startDate: monthStart,
        endDate: monthEnd,
      );

      int totalSpent = 0;
      for (var order in orders) {
        if (order['status'] == 'Confirmed' || order['status'] == 'Pending') {
          totalSpent += (order['total_cost'] as num?)?.toInt() ?? 0;
        }
      }

      // Load monthly budget (set by management/accountant)
      final budget = await _dataService.getMonthlyPurchaseBudget(monthStart);
      _budgetSet = budget != null;
      _monthlyBudgetKobo = (budget?['amount'] as num?)?.toInt() ?? 0;
      _spentKobo = totalSpent;
      _varianceKobo = _monthlyBudgetKobo - _spentKobo;
      _budgetExceeded = _varianceKobo < 0;
      
      // Convert purchase orders to history format
      _purchaseHistory = orders.where((o) => o['status'] == 'Confirmed').map((order) {
        final items = order['purchase_order_items'] as List?;
        final firstItem = items?.isNotEmpty == true ? items![0] : null;
        final stockItem = firstItem?['stock_items'] as Map<String, dynamic>?;
        return {
          'item_name': stockItem?['name'] ?? 'Multiple Items',
          'quantity': items?.fold<int>(0, (sum, item) => sum + (item['quantity'] as int? ?? 0)) ?? 0,
          'unit': 'units',
          'amount_spent': ((order['total_cost'] as num?)?.toDouble() ?? 0.0) / 100,
          'supplier': order['supplier_name'] ?? 'Unknown',
          'purchase_date': order['created_at'] ?? DateTime.now().toIso8601String(),
        };
      }).toList();
      
      _pendingOrders = orders.where((o) => o['status'] == 'Pending').toList();

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load data. Please check your connection and try again.',
          onRetry: _loadBudgetData,
        );
      }
    }
  }

  Future<void> _loadSuppliers() async {
    try {
      final suppliers = await _dataService.getSuppliers();
      if (mounted) {
        setState(() {
          _suppliers = suppliers;
        });
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load suppliers. You can still type a supplier manually.',
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _resolveSupplier() async {
    final typedName = _supplierController.text.trim();
    if (typedName.isNotEmpty) {
      final existing = _suppliers.firstWhere(
        (s) => s['name']?.toString().toLowerCase() == typedName.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );
      if (existing.isNotEmpty) {
        return existing;
      }
      final created = await _dataService.addSupplier(name: typedName);
      if (mounted) {
        setState(() {
          _suppliers = [created, ..._suppliers];
        });
      }
      return created;
    }

    if (_selectedSupplierId != null) {
      final selected = _suppliers.firstWhere(
        (s) => s['id']?.toString() == _selectedSupplierId,
        orElse: () => <String, dynamic>{},
      );
      if (selected.isNotEmpty) {
        return selected;
      }
    }

    return null;
  }

  Future<void> _recordPurchase() async {
    if (_amountController.text.isEmpty || 
        _itemNameController.text.isEmpty || 
        _quantityController.text.isEmpty) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please fill in all required fields',
        );
      }
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please enter a valid amount',
        );
      }
      return;
    }

    final quantity = int.tryParse(_quantityController.text);
    if (quantity == null || quantity <= 0) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Quantity must be greater than 0',
        );
      }
      return;
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final purchaserId = authService.currentUser?.id;
      if (purchaserId == null) {
        throw Exception('User not authenticated');
      }

      // Get or create stock item
      final stockItems = await _dataService.getStockItems();
      final existingItem = stockItems.firstWhere(
        (item) => item['name']?.toString().toLowerCase() == _itemNameController.text.trim().toLowerCase(),
        orElse: () => <String, dynamic>{},
      );

      String? stockItemId;
      if (existingItem.isNotEmpty) {
        stockItemId = existingItem['id']?.toString();
      } else {
        final supplier = await _resolveSupplier();
        // Create new stock item if it doesn't exist
        stockItemId = await _dataService.addStockItem(
          name: _itemNameController.text.trim(),
          description: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
          unit: _unitController.text.trim(),
          category: _categoryController.text.trim(),
          preferredSupplierId: supplier?['id']?.toString(),
          preferredSupplierName: supplier?['name']?.toString(),
        );
      }

      if (stockItemId == null) {
        throw Exception('Failed to get or create stock item');
      }

      // Create purchase order
      final totalCost = (amount * 100).toInt(); // Convert to kobo
      final supplier = await _resolveSupplier();
      await _dataService.createPurchaseOrder({
        'purchaser_id': purchaserId,
        'supplier_name': supplier?['name']?.toString() ?? _supplierController.text.trim(),
        'total_cost': totalCost,
        'items': [
          {
            'stock_item_id': stockItemId,
            'quantity': quantity,
            'unit_cost': ((amount / quantity) * 100).toInt(),
          }
        ],
      });

      // Clear form
      _amountController.clear();
      _itemNameController.clear();
      _quantityController.clear();
      _unitController.clear();
      _categoryController.clear();
      _supplierController.clear();
      _notesController.clear();
      _selectedSupplierId = null;

      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Purchase order created successfully!',
        );
        await _loadBudgetData();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to record purchase. Please try again.',
          onRetry: _recordPurchase,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    final isPurchaser = (user?.roles.any((r) => r.name == 'purchaser') ?? false);
    final isAssumedPurchaser = authService.hasAssumedRole(AppRole.purchaser);
    final canRecord = isPurchaser || isAssumedPurchaser;
    
    // Owner/Manager can only access Record Purchase if they assume purchaser role
    final isOwnerOrManager = user?.roles.any((r) => r.name == 'owner' || r.name == 'manager') ?? false;
    final showRecordPurchase = canRecord && !(isOwnerOrManager && !isAssumedPurchaser);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Consumer<AuthService>(
        builder: (context, authService, child) {
          final user = authService.currentUser;
          final isPurchaser = (user?.roles.any((r) => r.name == 'purchaser') ?? false);
          final isAssumedPurchaser = authService.hasAssumedRole(AppRole.purchaser);
          final isOwnerOrManager = user?.roles.any((r) => r.name == 'owner' || r.name == 'manager') ?? false;
          final showRecordPurchase = (isPurchaser || isAssumedPurchaser) && !(isOwnerOrManager && !isAssumedPurchaser);
          
          // Update tab controller if needed
          final tabCount = showRecordPurchase ? 3 : 2;
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
          
          return Column(
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
                    if (showRecordPurchase) const Tab(text: 'Record Purchase', icon: Icon(Icons.add_shopping_cart)),
                    const Tab(text: 'Budget Overview', icon: Icon(Icons.account_balance_wallet)),
                    const Tab(text: 'Purchase History', icon: Icon(Icons.history)),
                  ],
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    if (showRecordPurchase) _buildPurchaseForm(),
                    _buildBudgetOverview(),
                    _buildPurchaseHistory(),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final padding = isMobile ? 16.0 : 24.0;
    final titleSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Purchaser Dashboard',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green[800],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Record purchases and manage company budget',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.grey[600],
          ),
        ),
      ],
    );
    final budgetChip = Container(
      padding: EdgeInsets.symmetric(horizontal: isMobile ? 12 : 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.green[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.green[200]!),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.shopping_cart, color: Colors.green[700], size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              _budgetSet
                  ? 'Budget: ₦${NumberFormat('#,##0.00').format(_monthlyBudgetKobo / 100)}'
                  : 'Budget: Not set',
              style: TextStyle(
                color: _budgetExceeded ? Colors.red[700] : Colors.green[700],
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );

    return Container(
      padding: EdgeInsets.all(padding),
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
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleSection,
                const SizedBox(height: 12),
                const ContextAwareRoleButton(suggestedRole: AppRole.purchaser),
                const SizedBox(height: 12),
                budgetChip,
              ],
            )
          : Row(
              children: [
                Expanded(child: titleSection),
                const ContextAwareRoleButton(suggestedRole: AppRole.purchaser),
                const SizedBox(width: 12),
                budgetChip,
              ],
            ),
    );
  }

  Widget _buildPurchaseForm() {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final formPadding = isMobile ? 16.0 : 24.0;
    return SingleChildScrollView(
      padding: EdgeInsets.all(formPadding),
      child: Container(
        padding: EdgeInsets.all(formPadding),
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
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Record New Purchase',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 20),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  return Column(
                    children: [
                      TextField(
                        controller: _itemNameController,
                        decoration: const InputDecoration(
                          labelText: 'Item Name *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _categoryController,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _itemNameController,
                        decoration: const InputDecoration(
                          labelText: 'Item Name *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _categoryController,
                        decoration: const InputDecoration(
                          labelText: 'Category',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 600) {
                  return Column(
                    children: [
                      DropdownButtonFormField<String>(
                        value: _selectedSupplierId,
                        decoration: const InputDecoration(
                          labelText: 'Preferred Supplier',
                          border: OutlineInputBorder(),
                        ),
                        items: _suppliers.map((supplier) {
                          return DropdownMenuItem(
                            value: supplier['id']?.toString(),
                            child: Text(supplier['name']?.toString() ?? 'Unknown'),
                          );
                        }).toList(),
                        onChanged: (v) => setState(() => _selectedSupplierId = v),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _supplierController,
                        decoration: const InputDecoration(
                          labelText: 'Or enter supplier name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        value: _selectedSupplierId,
                        decoration: const InputDecoration(
                          labelText: 'Preferred Supplier',
                          border: OutlineInputBorder(),
                        ),
                        items: _suppliers.map((supplier) {
                          final id = supplier['id']?.toString();
                          final name = supplier['name']?.toString() ?? 'Unknown';
                          return DropdownMenuItem(value: id, child: Text(name));
                        }).toList(),
                        onChanged: (value) => setState(() => _selectedSupplierId = value),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: TextField(
                        controller: _supplierController,
                        decoration: const InputDecoration(
                          labelText: 'Supplier (type to add)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _quantityController,
                    decoration: const InputDecoration(
                      labelText: 'Quantity *',
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
                      labelText: 'Unit (kg, liters, etc.)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount Spent (₦) *',
                border: OutlineInputBorder(),
                prefixText: '₦',
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes (Optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _recordPurchase,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Record Purchase'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBudgetOverview() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final padding = isMobile ? 16.0 : 24.0;

    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final canManageBudget = user?.roles.any((r) =>
            r.name == 'owner' ||
            r.name == 'manager' ||
            r.name == 'accountant') ??
        false;
    final percentUsed = _monthlyBudgetKobo == 0
        ? 0.0
        : (_spentKobo / _monthlyBudgetKobo) * 100;

    return Padding(
      padding: EdgeInsets.all(padding),
      child: Column(
        children: [
          Container(
            padding: EdgeInsets.all(padding),
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
                Text(
                  'Budget Overview',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _buildBudgetCard(
                        'Monthly Budget',
                        _budgetSet
                            ? '₦${NumberFormat('#,##0.00').format(_monthlyBudgetKobo / 100)}'
                            : 'Not set',
                        Colors.blue,
                        Icons.account_balance_wallet,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildBudgetCard(
                        _budgetExceeded ? 'Deficit' : 'Surplus',
                        '₦${NumberFormat('#,##0.00').format(_varianceKobo.abs() / 100)}',
                        _budgetExceeded ? Colors.red : Colors.green,
                        _budgetExceeded ? Icons.warning : Icons.savings,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _buildBudgetCard(
                        'Spent',
                        '₦${NumberFormat('#,##0.00').format(_spentKobo / 100)}',
                        Colors.red,
                        Icons.shopping_cart,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildBudgetCard(
                        'Percentage Used',
                        '${percentUsed.toStringAsFixed(1)}%',
                        Colors.orange,
                        Icons.pie_chart,
                      ),
                    ),
                  ],
                ),
                if (canManageBudget) ...[
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _showSetBudgetDialog,
                      icon: const Icon(Icons.edit),
                      label: const Text('Set Monthly Budget'),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showSetBudgetDialog() async {
    final controller = TextEditingController(
      text: _budgetSet ? (_monthlyBudgetKobo / 100).toStringAsFixed(2) : '',
    );
    final authService = Provider.of<AuthService>(context, listen: false);
    final userId = authService.currentUser?.id;
    if (userId == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Set Monthly Budget'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Amount (₦)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    final amount = double.tryParse(controller.text.trim());
    if (amount == null || amount <= 0) {
      if (mounted) {
        ErrorHandler.showWarningMessage(context, 'Enter a valid budget amount');
      }
      return;
    }

    final now = DateTime.now();
    final monthStart = DateTime(now.year, now.month, 1);
    await _dataService.upsertMonthlyPurchaseBudget(
      monthStart: monthStart,
      amountKobo: (amount * 100).round(),
      updatedBy: userId,
    );
    await _loadBudgetData();
  }

  Widget _buildBudgetCard(String title, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPurchaseHistory() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final padding = isMobile ? 16.0 : 24.0;

    return Padding(
      padding: EdgeInsets.all(padding),
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
              padding: EdgeInsets.all(isMobile ? 16.0 : 20.0),
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      'Purchase History',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey[800],
                      ),
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_purchaseHistory.length} Records',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (_purchaseHistory.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                child: const Center(
                  child: Text('No purchase records found'),
                ),
              )
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _purchaseHistory.length,
                  itemBuilder: (context, index) {
                    final purchase = _purchaseHistory[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green[100],
                        child: Icon(Icons.shopping_cart, color: Colors.green[700]),
                      ),
                      title: Text(
                        purchase['item_name']?.toString() ?? 'Unknown Item',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Quantity: ${purchase['quantity']} ${purchase['unit']}'),
                          if (purchase['supplier'] != null)
                            Text('Supplier: ${purchase['supplier']}'),
                          Text(
                            'Date: ${DateFormat('MMM dd, yyyy').format(DateTime.parse(purchase['purchase_date']))}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      trailing: Text(
                        '₦${NumberFormat('#,##0.00').format(purchase['amount_spent'])}',
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
}
