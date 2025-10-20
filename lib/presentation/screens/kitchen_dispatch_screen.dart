// Location: lib/presentation/screens/kitchen_dispatch_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';

class KitchenDispatchScreen extends StatefulWidget {
  const KitchenDispatchScreen({super.key});

  @override
  State<KitchenDispatchScreen> createState() => _KitchenDispatchScreenState();
}

class _KitchenDispatchScreenState extends State<KitchenDispatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _dataService = DataService();
  final _quantityController = TextEditingController();

  List<Map<String, dynamic>> _stockItems = [];
  List<Map<String, dynamic>> _locations = [];
  String? _selectedStockItemId;
  String? _selectedDestinationLocationId;
  String? _sourceLocationId; // Kitchen location id
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAccessAndLoad();
    });
  }

  Future<void> _checkAccessAndLoad() async {
    final authService = Provider.of<MockAuthService>(context, listen: false);
    final user = authService.currentUser;
    final isKitchenStaff = (user?.roles.any((r) => r == AppRole.kitchen_staff) ?? false);
    final isAssumedKitchenStaff = authService.isRoleAssumed && authService.assumedRole == AppRole.kitchen_staff;
    final isOwnerOrManager = user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
    
    // Owner/Manager can view dispatches without assuming role
    // But need to assume role for full functionality
    final canAccess = isKitchenStaff || isAssumedKitchenStaff || isOwnerOrManager;

    if (!canAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Access restricted.'),
            backgroundColor: Colors.red,
          ));
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
      final stockResponse = await _dataService.getInventoryItems();
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
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Warning: Kitchen location not found'),
          backgroundColor: Colors.orange,
        ));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error loading data: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _dispatchItem() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStockItemId == null || _selectedDestinationLocationId == null) return;

    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<MockAuthService>(context, listen: false);
      final staffId = authService.currentUser!.id;
      final quantity = int.parse(_quantityController.text);

      if (_sourceLocationId == null) {
        throw Exception('Source location not configured');
      }

      // Optional local stock check for faster feedback
      final selected = _stockItems.firstWhere(
        (s) => s['id'] == _selectedStockItemId,
        orElse: () => <String, dynamic>{},
      );
      if (selected.isEmpty) throw Exception('Selected stock item not found');
      final currentStock = (selected['current_stock'] as num?)?.toInt() ?? 0;
      if (currentStock < quantity) {
        throw Exception('Insufficient stock. Available: $currentStock');
      }

      // Mock-only: simulate dispatch
      await Future.delayed(const Duration(milliseconds: 300));

      // Clear form and refresh
      _formKey.currentState?.reset();
      _quantityController.clear();
      setState(() {
        _selectedStockItemId = null;
        _selectedDestinationLocationId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Item dispatched successfully (mock).'),
        backgroundColor: Colors.green,
      ));

      await _loadStockAndLocations();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Error: $e'),
          backgroundColor: Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
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
    return Consumer<MockAuthService>(
      builder: (context, authService, child) {
        final user = authService.currentUser;
        final isKitchenStaff = (user?.roles.any((r) => r == AppRole.kitchen_staff) ?? false);
        final isAssumedKitchenStaff = authService.isRoleAssumed && authService.assumedRole == AppRole.kitchen_staff;
        final isOwnerOrManager = user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
        
        // Show full functionality if kitchen staff or assumed kitchen staff
        final showFullFunctionality = isKitchenStaff || isAssumedKitchenStaff;
        final destinations = _locations.where((l) => l['id'] != _sourceLocationId).toList();

        return Scaffold(
          appBar: AppBar(
            title: const Text('Kitchen Dispatch'),
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
              // Show dispatch form only if full functionality
              if (showFullFunctionality) ...[
                // Dispatch Form
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
                      labelText: 'Stock Item',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.inventory_2),
                    ),
                    items: _stockItems
                        .map((item) => DropdownMenuItem(
                              value: item['id'] as String,
                              child: Text('${item['name']} (Stock: ${item['current_stock']})'),
                            ))
                        .toList(),
                    onChanged: (val) => setState(() => _selectedStockItemId = val),
                    validator: (val) => val == null ? 'Please select an item' : null,
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
                          onChanged: (val) => setState(() => _selectedDestinationLocationId = val),
                          validator: (val) => val == null ? 'Select destination' : null,
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
              ],
              
              const Divider(thickness: 2),

              // Recent Dispatches
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Recent Dispatches',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
          Expanded(
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: Future.value(const [
                {
                  'destination_department': 'VIP Bar',
                  'quantity': 12,
                  'status': 'completed',
                  'created_at': '2024-01-15T14:30:00',
                },
                {
                  'destination_location_name': 'Outside Bar',
                  'quantity': 8,
                  'status': 'completed',
                  'created_at': '2024-01-15T13:05:00',
                },
              ]),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                final transfers = snapshot.data ?? [];

                if (transfers.isEmpty) {
                  return const Center(
                    child: Text('No recent dispatches'),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: transfers.length,
                  itemBuilder: (context, index) {
                    final transfer = transfers[index];
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.send, color: Colors.orange),
                        title: Text('To: ${transfer['destination_department']?.toString() ?? transfer['destination_location_name']?.toString() ?? 'Unknown'}'),
                        subtitle: Text('Qty: ${transfer['quantity']?.toString() ?? '0'} • Status: ${transfer['status']?.toString() ?? 'Unknown'}'),
                        trailing: Text(
                          transfer['created_at'] != null ? _formatDate(transfer['created_at'] as String) : '',
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
        );
      },
    );
  }
}
