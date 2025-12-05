import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class StockMovementsScreen extends StatefulWidget {
  const StockMovementsScreen({super.key});

  @override
  State<StockMovementsScreen> createState() => _StockMovementsScreenState();
}

class _StockMovementsScreenState extends State<StockMovementsScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = true;
  List<Map<String, dynamic>> _recentMovements = [];
  
  // Controllers for new stock entry dialog
  final _itemNameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _unitController = TextEditingController();
  final _locationController = TextEditingController();
  final _notesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadRecentMovements();
  }

  @override
  void dispose() {
    _itemNameController.dispose();
    _quantityController.dispose();
    _unitController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadRecentMovements() async {
    try {
      final response = await _supabase
          .from('stock_transactions')
          .select('*, stock_items(name, unit), locations(name), profiles(full_name)')
          .order('created_at', ascending: false)
          .limit(50);

      if (mounted) {
        setState(() {
          _recentMovements = List<Map<String, dynamic>>.from(response);
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load stock movements. Please check your connection and try again.',
          onRetry: _loadRecentMovements,
        );
      }
    }
  }

  Future<void> _showNewStockEntryDialog() async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('New Stock Entry'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _itemNameController,
                  decoration: const InputDecoration(
                    labelText: 'Item Name *',
                    border: OutlineInputBorder(),
                  ),
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
                          labelText: 'Unit *',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _locationController,
                  decoration: const InputDecoration(
                    labelText: 'Location/Department *',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
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
              child: const Text('Add Entry'),
              onPressed: () async {
                if (_itemNameController.text.trim().isEmpty ||
                    _quantityController.text.trim().isEmpty ||
                    _unitController.text.trim().isEmpty ||
                    _locationController.text.trim().isEmpty) {
                  if (mounted) {
                    ErrorHandler.showWarningMessage(
                      context,
                      'Please fill in all required fields',
                    );
                  }
                  return;
                }

                try {
                  final quantity = int.tryParse(_quantityController.text.trim());
                  if (quantity == null || quantity < 0) {
                    if (mounted) {
                      ErrorHandler.showWarningMessage(
                        context,
                        'Please enter a valid quantity',
                      );
                    }
                    return;
                  }

                  // Insert new stock transaction
                  await _supabase.from('stock_transactions').insert({
                    'item_name': _itemNameController.text.trim(),
                    'quantity': quantity,
                    'unit': _unitController.text.trim(),
                    'location': _locationController.text.trim(),
                    'transaction_type': 'purchase',
                    'notes': _notesController.text.trim(),
                    'created_at': DateTime.now().toIso8601String(),
                  });

                  _clearControllers();
                  
                  if (mounted) {
                    Navigator.of(context).pop();
                    ErrorHandler.showSuccessMessage(
                      context,
                      'Stock entry added successfully!',
                    );
                    // Refresh movements
                    await _loadRecentMovements();
                  }
                } catch (e) {
                  if (mounted) {
                    ErrorHandler.handleError(
                      context,
                      e,
                      customMessage: 'Failed to add stock entry. Please try again.',
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
    _itemNameController.clear();
    _quantityController.clear();
    _unitController.clear();
    _locationController.clear();
    _notesController.clear();
  }

  Color _getTransactionColor(String type) {
    switch (type.toLowerCase()) {
      case 'purchase':
        return Colors.green;
      case 'usage':
        return Colors.red;
      case 'transfer':
        return Colors.blue;
      case 'adjustment':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  IconData _getTransactionIcon(String type) {
    switch (type.toLowerCase()) {
      case 'purchase':
        return Icons.shopping_cart;
      case 'usage':
        return Icons.inventory;
      case 'transfer':
        return Icons.swap_horiz;
      case 'adjustment':
        return Icons.tune;
      default:
        return Icons.question_mark;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Stock Movements'),
        backgroundColor: Colors.blueGrey.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadRecentMovements,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadRecentMovements,
              child: _recentMovements.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2, size: 64, color: Colors.grey.shade400),
                          const SizedBox(height: 16),
                          const Text(
                            'No stock movements found',
                            style: TextStyle(fontSize: 18, color: Colors.grey),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(8.0),
                      itemCount: _recentMovements.length,
                      itemBuilder: (context, index) {
                        final movement = _recentMovements[index];
                        final itemName = movement['stock_items']?['name'] ?? 'Unknown';
                        final unit = movement['stock_items']?['unit'] ?? 'units';
                        final location = movement['locations']?['name'] ?? 'Unknown';
                        final staffName = movement['profiles']?['full_name'] ?? 'Unknown';
                        final quantity = movement['quantity'] as int? ?? 0;
                        final type = movement['transaction_type'] as String? ?? 'Unknown';
                        final createdAt = movement['created_at'] != null
                            ? DateTime.parse(movement['created_at'] as String)
                            : null;

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          child: ListTile(
                            leading: Icon(
                              _getTransactionIcon(type),
                              color: _getTransactionColor(type),
                            ),
                            title: Text(itemName),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('$quantity $unit • $location'),
                                if (movement['notes'] != null)
                                  Text('Notes: ${movement['notes']}'),
                                if (createdAt != null)
                                  Text(
                                    DateFormat('MMM d, yyyy - h:mm a').format(createdAt),
                                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                                  ),
                                Text('By: $staffName', style: const TextStyle(fontSize: 12)),
                              ],
                            ),
                            trailing: Chip(
                              label: Text(
                                type,
                                style: TextStyle(
                                  color: _getTransactionColor(type),
                                  fontSize: 12,
                                ),
                              ),
                              backgroundColor: _getTransactionColor(type).withOpacity(0.1),
                            ),
                          ),
                        );
                      },
                    ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showNewStockEntryDialog,
        icon: const Icon(Icons.add),
        label: const Text('New Entry'),
        backgroundColor: Colors.blueGrey.shade700,
      ),
    );
  }
}