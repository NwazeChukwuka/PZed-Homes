// Location: lib/presentation/screens/confirm_purchases_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  @override
  void initState() {
    super.initState();
    _pendingOrdersStream = _supabase
        .from('purchase_orders')
        .stream(primaryKey: ['id'])
        .eq('status', 'Pending')
        .order('created_at');
  }

  Future<void> _confirmOrder(String orderId) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    try {
      // Call our secure database function to confirm the order
      await _supabase.rpc('confirm_purchase_order', params: {
        'order_id': orderId,
        'storekeeper_id': authService.currentUser!.id,
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
                    onPressed: () => _confirmOrder(order['id']),
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