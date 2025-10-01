// Location: lib/presentation/screens/kitchen_dispatch_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/data/models/user.dart';

class KitchenDispatchScreen extends StatefulWidget {
  const KitchenDispatchScreen({super.key});

  @override
  State<KitchenDispatchScreen> createState() => _KitchenDispatchScreenState();
}

class _KitchenDispatchScreenState extends State<KitchenDispatchScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supabase = Supabase.instance.client;
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
    final isStaff = user != null && user.roles.any((role) => role != AppRole.guest);

    if (!isStaff) {
      // Use a delayed navigation to avoid overlapping calls
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Access Denied. Staff credentials required.'),
            backgroundColor: Colors.red,
          ));
          Future.delayed(const Duration(milliseconds: 100), () {
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
      final stockResponse = await _supabase
          .from('stock_items')
          .select('id, name, current_stock')
          .order('name');

      final locResponse = await _supabase
          .from('locations')
          .select('id, name')
          .order('name');

      if (!mounted) return;

      setState(() {
        _stockItems = List<Map<String, dynamic>>.from(stockResponse as List<dynamic>);
        _locations = List<Map<String, dynamic>>.from(locResponse as List<dynamic>);
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

      // Call atomic RPC to perform the transfer on the DB side
      await _supabase.rpc('perform_stock_transfer', params: {
        'p_stock_item_id': _selectedStockItemId,
        'p_source_location_id': _sourceLocationId,
        'p_destination_location_id': _selectedDestinationLocationId,
        'p_quantity': quantity,
        'p_staff_id': staffId,
      });

      // Clear form and refresh
      _formKey.currentState?.reset();
      _quantityController.clear();
      setState(() {
        _selectedStockItemId = null;
        _selectedDestinationLocationId = null;
      });

      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Item dispatched successfully!'),
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
    final destinations = _locations.where((l) => l['id'] != _sourceLocationId).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kitchen Dispatch'),
        backgroundColor: Colors.orange.shade800,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadStockAndLocations,
          ),
        ],
      ),
      body: Column(
        children: [
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
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: _supabase
                  .from('department_transfers')
                  .stream(primaryKey: ['id'])
                  .order('created_at', ascending: false)
                  .limit(20),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }

                if (snapshot.hasError) {
                  return Center(child: Text('Error: ${snapshot.error}'));
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
  }
}
