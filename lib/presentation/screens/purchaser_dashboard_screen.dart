import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
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
  
  // Form controllers
  final _amountController = TextEditingController();
  final _itemNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitController = TextEditingController();
  final _supplierController = TextEditingController();
  final _notesController = TextEditingController();
  
  // Budget tracking
  double _totalBudget = 0.0;
  double _remainingBudget = 0.0;
  List<Map<String, dynamic>> _purchaseHistory = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    // Initialize with default tab count
    _tabController = TabController(length: 2, vsync: this);
    _loadBudgetData();
  }
  
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateTabController();
  }
  
  void _updateTabController() {
    final authService = Provider.of<MockAuthService>(context, listen: false);
    final user = authService.currentUser;
    final isPurchaser = (user?.roles.any((r) => r.name == 'purchaser') ?? false);
    final isAssumedPurchaser = authService.isRoleAssumed && authService.assumedRole?.name == 'purchaser';
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
    _supplierController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadBudgetData() async {
    try {
      // Mock data for presentation
      final budgetResponse = [
        {'total_budget': 500000.0, 'remaining_budget': 275000.0}
      ];
      final purchasesResponse = [
        {
          'item_name': 'Heineken Crate',
          'quantity': 5,
          'unit': 'crates',
          'amount_spent': 85000.0,
          'supplier': 'Chinedu Suppliers',
          'purchase_date': DateTime.now().toIso8601String(),
        }
      ];

      if (mounted) {
        setState(() {
          _totalBudget = (budgetResponse.first['total_budget'] as num?)?.toDouble() ?? 0.0;
          _remainingBudget = (budgetResponse.first['remaining_budget'] as num?)?.toDouble() ?? 0.0;
          _purchaseHistory = List<Map<String, dynamic>>.from(purchasesResponse);
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

  Future<void> _recordPurchase() async {
    if (_amountController.text.isEmpty || 
        _itemNameController.text.isEmpty || 
        _quantityController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please fill in all required fields'), backgroundColor: Colors.red),
      );
      return;
    }

    final amount = double.tryParse(_amountController.text);
    if (amount == null || amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a valid amount'), backgroundColor: Colors.red),
      );
      return;
    }

    if (amount > _remainingBudget) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Insufficient budget remaining'), backgroundColor: Colors.red),
      );
      return;
    }

    try {
      // Mock-only: update local state
      setState(() {
        _remainingBudget -= amount;
        _purchaseHistory.insert(0, {
          'item_name': _itemNameController.text.trim(),
          'quantity': int.parse(_quantityController.text),
          'unit': _unitController.text.trim(),
          'amount_spent': amount,
          'supplier': _supplierController.text.trim(),
          'purchase_date': DateTime.now().toIso8601String(),
        });
      });

      // Clear form
      _amountController.clear();
      _itemNameController.clear();
      _quantityController.clear();
      _unitController.clear();
      _supplierController.clear();
      _notesController.clear();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Purchase recorded successfully!'), backgroundColor: Colors.green),
      );

      await _loadBudgetData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error recording purchase: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<MockAuthService>(context);
    final user = authService.currentUser;
    final isPurchaser = (user?.roles.any((r) => r.name == 'purchaser') ?? false);
    final isAssumedPurchaser = authService.isRoleAssumed && authService.assumedRole?.name == 'purchaser';
    final canRecord = isPurchaser || isAssumedPurchaser;
    
    // Owner/Manager can only access Record Purchase if they assume purchaser role
    final isOwnerOrManager = user?.roles.any((r) => r.name == 'owner' || r.name == 'manager') ?? false;
    final showRecordPurchase = canRecord && !(isOwnerOrManager && !isAssumedPurchaser);

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Consumer<MockAuthService>(
        builder: (context, authService, child) {
          final user = authService.currentUser;
          final isPurchaser = (user?.roles.any((r) => r.name == 'purchaser') ?? false);
          final isAssumedPurchaser = authService.isRoleAssumed && authService.assumedRole?.name == 'purchaser';
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
            ),
          ),
          const ContextAwareRoleButton(suggestedRole: AppRole.purchaser),
          const SizedBox(width: 12),
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
                Icon(Icons.shopping_cart, color: Colors.green[700], size: 16),
                const SizedBox(width: 8),
                Text(
                  'Budget: ₦${NumberFormat('#,##0.00').format(_remainingBudget)}',
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

  Widget _buildPurchaseForm() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(24),
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
            Row(
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
                    controller: _supplierController,
                    decoration: const InputDecoration(
                      labelText: 'Supplier',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
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
                        'Total Budget',
                        '₦${NumberFormat('#,##0.00').format(_totalBudget)}',
                        Colors.blue,
                        Icons.account_balance_wallet,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildBudgetCard(
                        'Remaining',
                        '₦${NumberFormat('#,##0.00').format(_remainingBudget)}',
                        Colors.green,
                        Icons.savings,
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
                        '₦${NumberFormat('#,##0.00').format(_totalBudget - _remainingBudget)}',
                        Colors.red,
                        Icons.shopping_cart,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildBudgetCard(
                        'Percentage Used',
                        '${((_totalBudget - _remainingBudget) / _totalBudget * 100).toStringAsFixed(1)}%',
                        Colors.orange,
                        Icons.pie_chart,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
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
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(
                    'Purchase History',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
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
