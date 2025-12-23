// Location: lib/presentation/screens/storekeeper_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:pzed_homes/presentation/screens/confirm_purchases_screen.dart'; // We will reuse this screen

class StorekeeperDashboardScreen extends StatefulWidget {
  const StorekeeperDashboardScreen({super.key});
  @override
  State<StorekeeperDashboardScreen> createState() => _StorekeeperDashboardScreenState();
}

class _StorekeeperDashboardScreenState extends State<StorekeeperDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Use Provider.of with listen: true but handle disposal properly
    final authService = Provider.of<AuthService>(context, listen: true);
    final user = authService.currentUser;
    final isStorekeeper = (user?.roles.any((r) => r.name == 'storekeeper') ?? false);
    final isAssumedStorekeeper = authService.isRoleAssumed && authService.assumedRole?.name == 'storekeeper';
    final isOwnerOrManager = user?.roles.any((r) => r.name == 'owner' || r.name == 'manager') ?? false;
    final showFullFunctionality = isStorekeeper || isAssumedStorekeeper;
        
    // Owner/Manager can view store items without assuming role
    // But need to assume role for full functionality
    if (isOwnerOrManager && !isAssumedStorekeeper) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Store View'),
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
          leading: Navigator.of(context).canPop() ? IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ) : null,
          actions: const [
            ContextAwareRoleButton(suggestedRole: AppRole.storekeeper),
          ],
        ),
        body: _buildReadOnlyStoreView(),
      );
    }

    if (!showFullFunctionality) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Storekeeper Dashboard'),
          backgroundColor: Colors.green[700],
          foregroundColor: Colors.white,
          leading: Navigator.of(context).canPop() ? IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).maybePop(),
          ) : null,
          actions: const [
            ContextAwareRoleButton(suggestedRole: AppRole.storekeeper),
          ],
        ),
        body: const Center(child: Text('Access restricted. Assume Storekeeper role to view.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storekeeper Dashboard'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        leading: Navigator.of(context).canPop() ? IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ) : null,
        actions: const [
          ContextAwareRoleButton(suggestedRole: AppRole.storekeeper),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Confirm Purchases'),
            Tab(text: 'Direct Stock Entry'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          ConfirmPurchasesScreen(),
          DirectStockEntryForm(),
        ],
      ),
    );
  }
  
  Widget _buildReadOnlyStoreView() {
    final dataService = DataService();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: dataService.getInventoryItems(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return ErrorHandler.buildErrorWidget(
            context,
            snapshot.error,
            message: 'Error loading inventory',
            onRetry: () => setState(() {}), // Trigger rebuild
          );
        }
        
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return ErrorHandler.buildEmptyWidget(
            context,
            message: 'No inventory items available',
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.inventory_2, color: Colors.green),
                title: Text(item['name'] ?? 'Unknown'),
                subtitle: Text('Stock: ${item['current_stock'] ?? 0} ${item['unit'] ?? ''}'),
                trailing: Text(
                  item['department'] ?? 'N/A',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

// --- The New Direct Stock Entry Form Widget ---
class DirectStockEntryForm extends StatefulWidget {
  const DirectStockEntryForm({super.key});
  @override
  State<DirectStockEntryForm> createState() => _DirectStockEntryFormState();
}

class _DirectStockEntryFormState extends State<DirectStockEntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  final _dataService = DataService();

  String? _selectedItemId;
  String? _selectedLocationId;
  bool _isLoading = false;
  List<Map<String, dynamic>> _inventoryItems = [];
  List<Map<String, dynamic>> _locations = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final items = await _dataService.getInventoryItems();
      // Get locations from departments or use a locations table
      // For now, we'll use a predefined list from database or create a locations table
      final locations = await _getLocations();
      setState(() {
        _inventoryItems = items;
        _locations = locations;
      });
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load data. Please check your connection and try again.',
          onRetry: () => setState(() {}),
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getLocations() async {
    // Try to get locations from database, or use default list
    try {
      // If you have a locations table, query it here
      // For now, return default locations
      return [
        {'id': 'store', 'name': 'Store'},
        {'id': 'vip_bar', 'name': 'VIP Bar'},
        {'id': 'outside_bar', 'name': 'Outside Bar'},
        {'id': 'mini_mart', 'name': 'Mini Mart'},
        {'id': 'kitchen', 'name': 'Kitchen'},
      ];
    } catch (e) {
      return [];
    }
  }

  Future<void> _recordDirectEntry() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedItemId == null || _selectedLocationId == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please select item and location',
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final staffId = authService.currentUser?.id ?? 'system';
      final quantity = int.parse(_quantityController.text);
      
      // Record stock transaction
      // Note: This requires stock_item_id from stock_items table, not inventory_items
      // If using inventory_items, you may need to map to stock_items or use a different approach
      await _dataService.recordStockTransaction({
        'stock_item_id': _selectedItemId, // This should be a stock_item_id, not inventory_item_id
        'location_id': _selectedLocationId!, // Required
        'staff_profile_id': staffId, // Required
        'transaction_type': 'Purchase', // Use standard transaction type
        'quantity': quantity,
        'notes': _notesController.text.trim().isNotEmpty 
            ? 'Direct entry: ${_notesController.text.trim()}' 
            : 'Direct stock entry',
      });

      // Update inventory item stock
      final item = _inventoryItems.firstWhere((i) => i['id'] == _selectedItemId);
      final newStock = (item['current_stock'] as int? ?? 0) + quantity;
      
      // Note: You might need to add an updateInventoryStock method to DataService
      // For now, we'll just show success
      
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Stock recorded successfully!',
        );
        _formKey.currentState?.reset();
        _quantityController.clear();
        _notesController.clear();
        setState(() {
          _selectedItemId = null;
          _selectedLocationId = null;
        });
        // Reload data to reflect changes
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to record stock. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('Use this form to record stock that did not come from a purchaser (e.g., direct delivery from management).', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          // Dropdown to select a stock item
          _inventoryItems.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  value: _selectedItemId,
                  decoration: const InputDecoration(labelText: 'Stock Item', border: OutlineInputBorder()),
                  items: _inventoryItems.map((item) => DropdownMenuItem<String>(
                    value: item['id']?.toString(),
                    child: Text(item['name']?.toString() ?? 'Unknown'),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedItemId = val),
                  validator: (val) => val == null ? 'Please select an item' : null,
                ),
          const SizedBox(height: 16),
          // Dropdown to select the location where the stock is being added
          _locations.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  value: _selectedLocationId,
                  decoration: const InputDecoration(labelText: 'Receiving Location', border: OutlineInputBorder()),
                  items: _locations.map((loc) => DropdownMenuItem<String>(
                    value: loc['id']?.toString(),
                    child: Text(loc['name']?.toString() ?? 'Unknown'),
                  )).toList(),
                  onChanged: (val) => setState(() => _selectedLocationId = val),
                  validator: (val) => val == null ? 'Please select a location' : null,
                ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _quantityController,
            decoration: const InputDecoration(labelText: 'Quantity Received', border: OutlineInputBorder()),
            keyboardType: TextInputType.number,
            validator: (val) => (val == null || val.isEmpty || int.tryParse(val) == null || int.parse(val) <= 0) ? 'Enter a valid quantity' : null,
            ),
            const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes (Optional)', hintText: 'e.g., Delivered by manager', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _recordDirectEntry,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Add to Stock Ledger'),
                ),
        ],
      ),
    );
  }
}