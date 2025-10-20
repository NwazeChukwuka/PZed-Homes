// Location: lib/presentation/screens/storekeeper_dashboard_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
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
    return Consumer<MockAuthService>(
      builder: (context, authService, child) {
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
      },
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
          return Center(child: Text('Error: ${snapshot.error}'));
        }
        
        final items = snapshot.data ?? [];
        
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
  // Moved to mock-only; hook into DataService if needed later
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();

  String? _selectedItemId;
  String? _selectedLocationId;
  bool _isLoading = false;

  Future<void> _recordDirectEntry() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Stock recorded (mock).'), backgroundColor: Colors.green));
      _formKey.currentState?.reset();
      _quantityController.clear();
      _notesController.clear();
      setState(() {
        _selectedItemId = null;
        _selectedLocationId = null;
      });

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red));
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
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Future.value(const [
              {'id': 'stk01', 'name': 'Heineken'},
              {'id': 'stk02', 'name': 'Coca-Cola'},
              {'id': 'stk03', 'name': 'Bottled Water'},
            ]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Stock Item', border: OutlineInputBorder()),
                items: snapshot.data!.map((item) => DropdownMenuItem<String>(value: item['id']?.toString(), child: Text(item['name']?.toString() ?? ''))).toList(),
                onChanged: (val) => setState(() => _selectedItemId = val),
                validator: (val) => val == null ? 'Please select an item' : null,
              );
            },
          ),
          const SizedBox(height: 16),
          // Dropdown to select the location where the stock is being added
          FutureBuilder<List<Map<String, dynamic>>>(
            future: Future.value(const [
              {'id': 'loc005', 'name': 'Store'},
              {'id': 'loc002', 'name': 'VIP Bar'},
              {'id': 'loc003', 'name': 'Outside Bar'},
              {'id': 'loc004', 'name': 'Mini Mart'},
            ]),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
              return DropdownButtonFormField<String>(
                decoration: const InputDecoration(labelText: 'Receiving Location', border: OutlineInputBorder()),
                items: snapshot.data!.map((loc) => DropdownMenuItem<String>(value: loc['id']?.toString(), child: Text(loc['name']?.toString() ?? ''))).toList(),
                onChanged: (val) => setState(() => _selectedLocationId = val),
                validator: (val) => val == null ? 'Please select a location' : null,
              );
            },
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