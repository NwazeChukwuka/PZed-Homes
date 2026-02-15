import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class ConfirmPurchasesScreen extends StatefulWidget {
  const ConfirmPurchasesScreen({super.key});
  @override
  State<ConfirmPurchasesScreen> createState() => _ConfirmPurchasesScreenState();
}

class _ConfirmPurchasesScreenState extends State<ConfirmPurchasesScreen> {
  final _supabase = Supabase.instance.client;
  late final Stream<List<Map<String, dynamic>>> _pendingOrdersStream;
  List<Map<String, dynamic>> _locations = [];
  String? _defaultStoreLocationId;
  bool _isLoadingLocations = true;

  @override
  void initState() {
    super.initState();
    _pendingOrdersStream = _supabase
        .from('purchase_orders')
        .stream(primaryKey: ['id'])
        .eq('status', 'Pending')
        .order('created_at');
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    try {
      final locations = await _supabase
          .from('locations')
          .select('id, name')
          .order('name');
      final list = List<Map<String, dynamic>>.from(locations);
      final defaultLocation = list.firstWhere(
        (loc) {
          final name = (loc['name'] ?? '').toString().toLowerCase();
          return name.contains('main store') || name.contains('main storeroom');
        },
        orElse: () => <String, dynamic>{},
      );
      setState(() {
        _locations = list;
        _defaultStoreLocationId = defaultLocation.isNotEmpty ? defaultLocation['id'] as String? : null;
        _isLoadingLocations = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingLocations = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load locations.',
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _fetchOrderItems(String orderId) async {
    final response = await _supabase
        .from('purchase_order_items')
        .select('quantity, unit_cost, stock_items(name, unit)')
        .eq('purchase_order_id', orderId);
    return List<Map<String, dynamic>>.from(response);
  }

  Future<void> _confirmOrder(String orderId, {String? locationId}) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      // Call our secure database function to confirm the order
      await _supabase.rpc('confirm_purchase_order', params: {
        'order_id': orderId,
        'storekeeper_id': authService.currentUser!.id,
        if (locationId != null) 'location_id': locationId,
      });
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Purchase Confirmed & Stock Updated!',
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to confirm purchase order. Please try again.',
          onRetry: () => _confirmOrder(orderId),
        );
      }
    }
  }

  Future<void> _showConfirmDialog(Map<String, dynamic> order) async {
    if (_isLoadingLocations) {
      ErrorHandler.showWarningMessage(context, 'Loading locations. Please wait.');
      return;
    }
    String? selectedLocationId = _defaultStoreLocationId;
    final orderId = order['id'] as String;
    final totalCost = (order['total_cost'] as num?)?.toInt() ?? 0;
    final items = await _fetchOrderItems(orderId);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final contentWidth = screenWidth < 420 ? screenWidth - 48 : 420.0;
        return AlertDialog(
          title: const Text('Confirm Purchase Order'),
          content: SizedBox(
            width: contentWidth,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Supplier: ${order['supplier_name'] ?? 'Unknown'}'),
                const SizedBox(height: 8),
                Text('Total: ₦${NumberFormat('#,##0.00').format(totalCost / 100)}'),
                const SizedBox(height: 12),
                if (_locations.isEmpty)
                  const Text('No locations found. Please create a Main Store location.')
                else
                  DropdownButtonFormField<String>(
                    initialValue: selectedLocationId,
                    decoration: const InputDecoration(
                      labelText: 'Receiving Location',
                      border: OutlineInputBorder(),
                    ),
                    items: _locations.map((loc) {
                      return DropdownMenuItem<String>(
                        value: loc['id']?.toString(),
                        child: Text(loc['name']?.toString() ?? 'Unknown'),
                      );
                    }).toList(),
                    onChanged: (val) => selectedLocationId = val,
                  ),
                const SizedBox(height: 12),
                const Text('Items:', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                if (items.isEmpty)
                  const Text('No line items found.')
                else
                  ...items.map((item) {
                    final stock = item['stock_items'] as Map<String, dynamic>?;
                    final name = stock?['name'] ?? 'Unknown Item';
                    final unit = stock?['unit'] ?? '';
                    final qty = item['quantity'] ?? 0;
                    final unitCost = (item['unit_cost'] as num?)?.toInt() ?? 0;
                    return Text(
                      '- $name: $qty $unit @ ₦${NumberFormat('#,##0.00').format(unitCost / 100)}',
                    );
                  }),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                if (_locations.isNotEmpty && selectedLocationId == null) {
                  ErrorHandler.showWarningMessage(context, 'Select a receiving location.');
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _confirmOrder(orderId, locationId: selectedLocationId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirm Incoming Stock')),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _pendingOrdersStream,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          
          if (snapshot.hasError) {
            return ErrorHandler.buildErrorWidget(
              context,
              snapshot.error,
              message: 'Error loading pending orders',
            );
          }
          
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return ErrorHandler.buildEmptyWidget(
              context,
              message: 'No pending purchases to confirm',
            );
          }
          
          final orders = snapshot.data!;

          return ListView.builder(
            itemCount: orders.length,
            itemBuilder: (context, index) {
              final order = orders[index];
              return Card(
                margin: const EdgeInsets.all(8),
                child: ListTile(
                  title: Text('PO from ${order['supplier_name'] ?? 'Unknown Supplier'}'),
                  subtitle: Text('ID: ${order['id'].substring(0, 8)}...'),
                  trailing: ElevatedButton(
                    onPressed: () => _showConfirmDialog(order),
                    child: const Text('Confirm'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}