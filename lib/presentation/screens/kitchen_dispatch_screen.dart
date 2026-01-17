import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:pzed_homes/core/services/payment_service.dart';

class KitchenDispatchScreen extends StatefulWidget {
  const KitchenDispatchScreen({super.key});

  @override
  State<KitchenDispatchScreen> createState() => _KitchenDispatchScreenState();
}

class _KitchenDispatchScreenState extends State<KitchenDispatchScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _saleFormKey = GlobalKey<FormState>();
  final _dataService = DataService();
  final _quantityController = TextEditingController();
  final _dispatchUnitPriceController = TextEditingController();
  final _saleQuantityController = TextEditingController();
  final _saleUnitPriceController = TextEditingController();
  final _saleCustomNameController = TextEditingController();

  List<Map<String, dynamic>> _stockItems = [];
  List<Map<String, dynamic>> _locations = [];
  String? _selectedStockItemId;
  String? _selectedDestinationLocationId;
  String? _sourceLocationId; // Kitchen location id
  bool _isLoading = false;
  bool _isCustomSale = false;
  String? _selectedSaleItemId;
  String _dispatchPaymentMethod = 'cash';
  String _salePaymentMethod = 'cash';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAccessAndLoad();
    });
  }

  Future<void> _checkAccessAndLoad() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isKitchenStaff = (user?.roles.any((r) => r == AppRole.kitchen_staff) ?? false);
    final isAssumedKitchenStaff = authService.isRoleAssumed && authService.assumedRole == AppRole.kitchen_staff;
    final isOwnerOrManager = user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
    final isReceptionist = (user?.roles.any((r) => r == AppRole.receptionist) ?? false);
    
    // Owner/Manager/Receptionist can view dispatches without assuming role
    // But need to assume role for full functionality
    final canAccess = isKitchenStaff || isAssumedKitchenStaff || isOwnerOrManager || isReceptionist;

    if (!canAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Access restricted.',
          );
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) context.pop();
          });
        }
      });
      return;
    }

    await _loadStockAndLocations();
  }

  Future<void> _loadStockAndLocations() async {
    setState(() => _isLoading = true);
    try {
      final menuItems = await _dataService.getMenuItems();
      final stockResponse = menuItems
          .where((item) => (item['department']?.toString().toLowerCase() ?? '') == 'kitchen')
          .toList();
      final locResponse = [
        {'id': 'loc001', 'name': 'Kitchen'},
        {'id': 'loc002', 'name': 'VIP Bar'},
        {'id': 'loc003', 'name': 'Outside Bar'},
        {'id': 'loc004', 'name': 'Mini Mart'},
        {'id': 'loc005', 'name': 'Store'},
      ];

      if (!mounted) return;

      setState(() {
        _stockItems = List<Map<String, dynamic>>.from(stockResponse);
        _locations = List<Map<String, dynamic>>.from(locResponse);
      });

      // Find Kitchen location id
      final kitchen = _locations.firstWhere(
        (l) => (l['name'] as String).toLowerCase() == 'kitchen',
        orElse: () => <String, dynamic>{},
      );
      if (kitchen.isNotEmpty) {
        setState(() => _sourceLocationId = kitchen['id'] as String);
      } else {
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Warning: Kitchen location not found',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load data. Please check your connection and try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setDispatchPriceFromItem(String? itemId) {
    if (itemId == null) return;
    final selected = _stockItems.firstWhere(
      (s) => s['id'] == itemId,
      orElse: () => <String, dynamic>{},
    );
    if (selected.isEmpty) return;
    final priceInKobo = selected['price'] as int? ?? 0;
    final priceInNaira = PaymentService.koboToNaira(priceInKobo);
    _dispatchUnitPriceController.text = priceInNaira.toStringAsFixed(2);
  }

  void _setSalePriceFromItem(String? itemId) {
    if (itemId == null) return;
    final selected = _stockItems.firstWhere(
      (s) => s['id'] == itemId,
      orElse: () => <String, dynamic>{},
    );
    if (selected.isEmpty) return;
    final priceInKobo = selected['price'] as int? ?? 0;
    final priceInNaira = PaymentService.koboToNaira(priceInKobo);
    _saleUnitPriceController.text = priceInNaira.toStringAsFixed(2);
  }

  String? _departmentFromLocationName(String? locationName) {
    if (locationName == null) return null;
    switch (locationName.toLowerCase()) {
      case 'vip bar':
        return 'vip_bar';
      case 'outside bar':
        return 'outside_bar';
      case 'mini mart':
        return 'mini_mart';
      case 'kitchen':
        return 'restaurant';
      case 'reception':
        return 'reception';
      case 'store':
        return 'storekeeping';
      default:
        return null;
    }
  }

  Future<void> _recordDepartmentSale({
    required String department,
    required int amountInKobo,
    required String staffId,
    required String paymentMethod,
  }) async {
    final supabase = Supabase.instance.client;
    final today = DateTime.now().toIso8601String().split('T')[0];
    final paymentBreakdown = <String, int>{paymentMethod: amountInKobo};

    final existingSales = await supabase
        .from('department_sales')
        .select()
        .eq('department', department)
        .eq('date', today)
        .maybeSingle();

    if (existingSales != null) {
      final existingStaffId = existingSales['staff_id'] as String?;
      if (existingStaffId == null || existingStaffId == staffId) {
        final currentBreakdown =
            (existingSales['payment_method_breakdown'] as Map<String, dynamic>?) ??
                <String, dynamic>{};
        final updatedBreakdown = Map<String, dynamic>.from(currentBreakdown);
        final currentMethodTotal = (updatedBreakdown[paymentMethod] as int? ?? 0);
        updatedBreakdown[paymentMethod] = currentMethodTotal + amountInKobo;

        await supabase
            .from('department_sales')
            .update({
              'total_sales': (existingSales['total_sales'] as int) + amountInKobo,
              'transaction_count': (existingSales['transaction_count'] as int) + 1,
              'payment_method_breakdown': updatedBreakdown,
              'staff_id': staffId,
              'recorded_by': staffId,
            })
            .eq('id', existingSales['id']);
      } else {
        await supabase.from('department_sales').insert({
          'department': department,
          'date': today,
          'total_sales': amountInKobo,
          'transaction_count': 1,
          'payment_method_breakdown': paymentBreakdown,
          'recorded_by': staffId,
          'staff_id': staffId,
        });
      }
    } else {
      await supabase.from('department_sales').insert({
        'department': department,
        'date': today,
        'total_sales': amountInKobo,
        'transaction_count': 1,
        'payment_method_breakdown': paymentBreakdown,
        'recorded_by': staffId,
        'staff_id': staffId,
      });
    }
  }

  Future<void> _dispatchItem() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStockItemId == null || _selectedDestinationLocationId == null) return;

    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final staffId = authService.currentUser!.id;
      final quantity = int.parse(_quantityController.text);
      final unitPriceNaira = double.tryParse(_dispatchUnitPriceController.text.trim()) ?? 0;

      if (_sourceLocationId == null) {
        throw Exception('Source location not configured');
      }

      // Optional local stock check for faster feedback
      final selected = _stockItems.firstWhere(
        (s) => s['id'] == _selectedStockItemId,
        orElse: () => <String, dynamic>{},
      );
      if (selected.isEmpty) throw Exception('Selected stock item not found');
      // Note: menu_items do not track per-location stock directly here.
      // Stock checks should be handled via stock_transactions/stock_levels if needed.

      // Get destination location name
      final destination = _locations.firstWhere(
        (l) => l['id'] == _selectedDestinationLocationId,
        orElse: () => <String, dynamic>{},
      );
      final destinationName = destination['name'] as String? ?? 'Unknown';

      // Create department transfer
      await _dataService.createDepartmentTransfer({
        'source_department': 'Kitchen',
        'destination_department': destinationName,
        'menu_item_id': _selectedStockItemId,
        'quantity': quantity,
        'dispatched_by_id': staffId,
        'status': 'Pending',
      });

      final destinationDepartment = _departmentFromLocationName(destinationName);
      if (destinationDepartment != null) {
        final totalInKobo = PaymentService.nairaToKobo(unitPriceNaira) * quantity;
        if (totalInKobo > 0) {
          await _recordDepartmentSale(
            department: destinationDepartment,
            amountInKobo: totalInKobo,
            staffId: staffId,
            paymentMethod: _dispatchPaymentMethod,
          );
        }
      }

      // Clear form and refresh
      _formKey.currentState?.reset();
      _quantityController.clear();
      _dispatchUnitPriceController.clear();
      setState(() {
        _selectedStockItemId = null;
        _selectedDestinationLocationId = null;
      });
      
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Item dispatched successfully!',
        );
        await _loadStockAndLocations();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to dispatch item. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _recordKitchenSale() async {
    if (!_saleFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final staffId = authService.currentUser!.id;
      final quantity = int.parse(_saleQuantityController.text.trim());
      final unitPriceNaira = double.tryParse(_saleUnitPriceController.text.trim()) ?? 0;
      final totalInKobo = PaymentService.nairaToKobo(unitPriceNaira) * quantity;

      if (totalInKobo <= 0) {
        throw Exception('Sale amount must be greater than 0');
      }

      await _recordDepartmentSale(
        department: 'restaurant',
        amountInKobo: totalInKobo,
        staffId: staffId,
        paymentMethod: _salePaymentMethod,
      );

      _saleFormKey.currentState?.reset();
      _saleQuantityController.clear();
      _saleUnitPriceController.clear();
      _saleCustomNameController.clear();
      setState(() {
        _selectedSaleItemId = null;
        _isCustomSale = false;
      });

      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Kitchen sale recorded successfully!',
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to record sale. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _dispatchUnitPriceController.dispose();
    _saleQuantityController.dispose();
    _saleUnitPriceController.dispose();
    _saleCustomNameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final user = authService.currentUser;
        final isKitchenStaff = (user?.roles.any((r) => r == AppRole.kitchen_staff) ?? false);
        final isAssumedKitchenStaff = authService.isRoleAssumed && authService.assumedRole == AppRole.kitchen_staff;
        final isOwnerOrManager = user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
        final isReceptionist = (user?.roles.any((r) => r == AppRole.receptionist) ?? false);
        
        // Show full functionality if kitchen staff, assumed kitchen staff, or receptionist
        final showFullFunctionality = isKitchenStaff || isAssumedKitchenStaff || isReceptionist;
        final destinations = _locations.where((l) => l['id'] != _sourceLocationId).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Kitchen'),
            backgroundColor: Colors.orange.shade800,
            leading: Navigator.of(context).canPop() ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ) : null,
            actions: [
              const ContextAwareRoleButton(suggestedRole: AppRole.kitchen_staff),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadStockAndLocations,
              ),
            ],
          ),
          body: Column(
            children: [
              if (showFullFunctionality)
                TabBar(
                  controller: _tabController,
                  labelColor: Colors.orange.shade800,
                  tabs: const [
                    Tab(text: 'Dispatch', icon: Icon(Icons.send)),
                    Tab(text: 'Sales', icon: Icon(Icons.point_of_sale)),
                  ],
                ),
              Expanded(
                child: showFullFunctionality
                    ? TabBarView(
                        controller: _tabController,
                        children: [
                          // Dispatch tab
                          Column(
                            children: [
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      DropdownButtonFormField<String>(
                                        value: _selectedStockItemId,
                                        decoration: const InputDecoration(
                                          labelText: 'Food Item',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.restaurant_menu),
                                        ),
                                        items: _stockItems
                                            .map((item) => DropdownMenuItem(
                                                  value: item['id'] as String,
                                                  child: Text(item['name'] as String? ?? 'Item'),
                                                ))
                                            .toList(),
                                        onChanged: (val) {
                                          setState(() => _selectedStockItemId = val);
                                          _setDispatchPriceFromItem(val);
                                        },
                                        validator: (val) =>
                                            val == null ? 'Please select an item' : null,
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _quantityController,
                                              decoration: const InputDecoration(
                                                labelText: 'Quantity',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.numbers),
                                              ),
                                              keyboardType: TextInputType.number,
                                              validator: (val) {
                                                if (val == null || val.isEmpty) return 'Enter quantity';
                                                final qty = int.tryParse(val);
                                                if (qty == null || qty <= 0) return 'Enter valid quantity';
                                                return null;
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: DropdownButtonFormField<String>(
                                              value: _selectedDestinationLocationId,
                                              decoration: const InputDecoration(
                                                labelText: 'Destination',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.location_on),
                                              ),
                                              items: destinations
                                                  .map((destination) => DropdownMenuItem(
                                                        value: destination['id'] as String,
                                                        child: Text(destination['name'] as String),
                                                      ))
                                                  .toList(),
                                              onChanged: (val) =>
                                                  setState(() => _selectedDestinationLocationId = val),
                                              validator: (val) =>
                                                  val == null ? 'Select destination' : null,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _dispatchUnitPriceController,
                                              decoration: const InputDecoration(
                                                labelText: 'Unit Price (₦)',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.payments),
                                              ),
                                              keyboardType: const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                              validator: (val) {
                                                if (val == null || val.isEmpty) return 'Enter price';
                                                final price = double.tryParse(val);
                                                if (price == null || price <= 0) {
                                                  return 'Enter valid price';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: DropdownButtonFormField<String>(
                                              value: _dispatchPaymentMethod,
                                              decoration: const InputDecoration(
                                                labelText: 'Payment Method',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.account_balance_wallet),
                                              ),
                                              items: const [
                                                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                                DropdownMenuItem(value: 'card', child: Text('Card')),
                                                DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                                              ],
                                              onChanged: (val) =>
                                                  setState(() => _dispatchPaymentMethod = val ?? 'cash'),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      _isLoading
                                          ? const Center(child: CircularProgressIndicator())
                                          : ElevatedButton.icon(
                                              onPressed: _dispatchItem,
                                              icon: const Icon(Icons.send),
                                              label: const Text('Dispatch Item'),
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: Colors.orange.shade800,
                                                padding: const EdgeInsets.symmetric(vertical: 16),
                                              ),
                                            ),
                                    ],
                                  ),
                                ),
                              ),
                              const Divider(thickness: 2),
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  'Recent Dispatches',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Expanded(
                                child: FutureBuilder<List<Map<String, dynamic>>>(
                                  future: _dataService.getDepartmentTransfers(),
                                  builder: (context, snapshot) {
                                    if (snapshot.connectionState == ConnectionState.waiting) {
                                      return const Center(child: CircularProgressIndicator());
                                    }

                                    if (snapshot.hasError) {
                                      return ErrorHandler.buildErrorWidget(
                                        context,
                                        snapshot.error,
                                        message: 'Error loading recent dispatches',
                                        onRetry: () => setState(() {}),
                                      );
                                    }

                                    final transfers = snapshot.data ?? [];

                                    if (transfers.isEmpty) {
                                      return ErrorHandler.buildEmptyWidget(
                                        context,
                                        message: 'No recent dispatches',
                                      );
                                    }

                                    return ListView.builder(
                                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                      itemCount: transfers.length,
                                      itemBuilder: (context, index) {
                                        final transfer = transfers[index];
                                        final menuItem =
                                            transfer['menu_items'] as Map<String, dynamic>?;
                                        final itemName = menuItem?['name'] ?? 'Unknown Item';
                                        return Card(
                                          margin: const EdgeInsets.symmetric(vertical: 4),
                                          child: ListTile(
                                            leading:
                                                const Icon(Icons.send, color: Colors.orange),
                                            title: Text(
                                              'To: ${transfer['destination_department'] ?? 'Unknown'}',
                                            ),
                                            subtitle: Text(
                                              '$itemName • Qty: ${transfer['quantity'] ?? 0} • Status: ${transfer['status'] ?? 'Unknown'}',
                                            ),
                                            trailing: Text(
                                              transfer['created_at'] != null
                                                  ? _formatDate(transfer['created_at'] as String)
                                                  : '',
                                              style: const TextStyle(fontSize: 12),
                                            ),
                                          ),
                                        );
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                          ),
                          // Sales tab
                          Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Form(
                              key: _saleFormKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  SwitchListTile(
                                    title: const Text('Custom Order (not on menu)'),
                                    value: _isCustomSale,
                                    onChanged: (value) {
                                      setState(() {
                                        _isCustomSale = value;
                                        _selectedSaleItemId = null;
                                        _saleUnitPriceController.clear();
                                      });
                                    },
                                  ),
                                  if (!_isCustomSale) ...[
                                    DropdownButtonFormField<String>(
                                      value: _selectedSaleItemId,
                                      decoration: const InputDecoration(
                                        labelText: 'Menu Item',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.restaurant),
                                      ),
                                      items: _stockItems
                                          .map((item) => DropdownMenuItem(
                                                value: item['id'] as String,
                                                child: Text(item['name'] as String? ?? 'Item'),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        setState(() => _selectedSaleItemId = val);
                                        _setSalePriceFromItem(val);
                                      },
                                      validator: (val) {
                                        if (_isCustomSale) return null;
                                        return val == null ? 'Please select an item' : null;
                                      },
                                    ),
                                  ] else ...[
                                    TextFormField(
                                      controller: _saleCustomNameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Custom Item Name',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.edit),
                                      ),
                                      validator: (val) {
                                        if (!_isCustomSale) return null;
                                        if (val == null || val.trim().isEmpty) {
                                          return 'Enter item name';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: TextFormField(
                                          controller: _saleQuantityController,
                                          decoration: const InputDecoration(
                                            labelText: 'Quantity',
                                            border: OutlineInputBorder(),
                                            prefixIcon: Icon(Icons.numbers),
                                          ),
                                          keyboardType: TextInputType.number,
                                          validator: (val) {
                                            if (val == null || val.isEmpty) return 'Enter quantity';
                                            final qty = int.tryParse(val);
                                            if (qty == null || qty <= 0) return 'Enter valid quantity';
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _saleUnitPriceController,
                                          decoration: const InputDecoration(
                                            labelText: 'Unit Price (₦)',
                                            border: OutlineInputBorder(),
                                            prefixIcon: Icon(Icons.payments),
                                          ),
                                          keyboardType: const TextInputType.numberWithOptions(
                                            decimal: true,
                                          ),
                                          validator: (val) {
                                            if (val == null || val.isEmpty) return 'Enter price';
                                            final price = double.tryParse(val);
                                            if (price == null || price <= 0) return 'Enter valid price';
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String>(
                                    value: _salePaymentMethod,
                                    decoration: const InputDecoration(
                                      labelText: 'Payment Method',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.account_balance_wallet),
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                      DropdownMenuItem(value: 'card', child: Text('Card')),
                                      DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                                    ],
                                    onChanged: (val) =>
                                        setState(() => _salePaymentMethod = val ?? 'cash'),
                                  ),
                                  const SizedBox(height: 24),
                                  _isLoading
                                      ? const Center(child: CircularProgressIndicator())
                                      : ElevatedButton.icon(
                                          onPressed: _recordKitchenSale,
                                          icon: const Icon(Icons.point_of_sale),
                                          label: const Text('Record Sale'),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: Colors.orange.shade800,
                                            padding: const EdgeInsets.symmetric(vertical: 16),
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : _buildReadOnlyDispatchList(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildReadOnlyDispatchList() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Recent Dispatches',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Map<String, dynamic>>>(
            future: _dataService.getDepartmentTransfers(),
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }

              if (snapshot.hasError) {
                return ErrorHandler.buildErrorWidget(
                  context,
                  snapshot.error,
                  message: 'Error loading recent dispatches',
                  onRetry: () => setState(() {}),
                );
              }

              final transfers = snapshot.data ?? [];

              if (transfers.isEmpty) {
                return ErrorHandler.buildEmptyWidget(
                  context,
                  message: 'No recent dispatches',
                );
              }

              return ListView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                itemCount: transfers.length,
                itemBuilder: (context, index) {
                  final transfer = transfers[index];
                  final menuItem = transfer['menu_items'] as Map<String, dynamic>?;
                  final itemName = menuItem?['name'] ?? 'Unknown Item';
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 4),
                    child: ListTile(
                      leading: const Icon(Icons.send, color: Colors.orange),
                      title: Text('To: ${transfer['destination_department'] ?? 'Unknown'}'),
                      subtitle: Text(
                        '$itemName • Qty: ${transfer['quantity'] ?? 0} • Status: ${transfer['status'] ?? 'Unknown'}',
                      ),
                      trailing: Text(
                        transfer['created_at'] != null
                            ? _formatDate(transfer['created_at'] as String)
                            : '',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
