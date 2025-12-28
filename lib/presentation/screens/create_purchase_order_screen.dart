import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/data_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/payment_service.dart';
import '../../core/error/error_handler.dart';
import 'package:go_router/go_router.dart';

class CreatePurchaseOrderScreen extends StatefulWidget {
  const CreatePurchaseOrderScreen({super.key});

  @override
  State<CreatePurchaseOrderScreen> createState() => _CreatePurchaseOrderScreenState();
}

class _CreatePurchaseOrderScreenState extends State<CreatePurchaseOrderScreen> {
  final _formKey = GlobalKey<FormState>();
  final _supplierController = TextEditingController();
  final _dataService = DataService();
  
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _stockItems = [];
  bool _isLoading = false;
  bool _isLoadingItems = true;

  @override
  void initState() {
    super.initState();
    _loadStockItems();
  }

  Future<void> _loadStockItems() async {
    try {
      setState(() => _isLoadingItems = true);
      final items = await _dataService.getStockItems();
      setState(() {
        _stockItems = items;
        _isLoadingItems = false;
      });
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e);
        setState(() => _isLoadingItems = false);
      }
    }
  }

  void _addItem() {
    setState(() {
      _items.add({
        'stock_item_id': null,
        'quantity': 1,
        'unit_cost': 0, // In kobo
      });
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  void _updateItem(int index, String field, dynamic value) {
    setState(() {
      _items[index][field] = value;
      // Recalculate total if quantity or unit_cost changed
      if (field == 'quantity' || field == 'unit_cost') {
        final quantity = _items[index]['quantity'] as int? ?? 0;
        final unitCost = _items[index]['unit_cost'] as int? ?? 0;
        _items[index]['total_cost'] = quantity * unitCost;
      }
    });
  }

  int get _totalCost {
    return _items.fold<int>(0, (sum, item) {
      final quantity = item['quantity'] as int? ?? 0;
      final unitCost = item['unit_cost'] as int? ?? 0;
      return sum + (quantity * unitCost);
    });
  }

  Future<void> _submitPurchaseOrder() async {
    if (!_formKey.currentState!.validate()) return;

    if (_items.isEmpty) {
      ErrorHandler.showWarningMessage(context, 'Please add at least one item to the purchase order');
      return;
    }

    // Validate all items have stock_item_id, quantity > 0, and unit_cost > 0
    for (int i = 0; i < _items.length; i++) {
      final item = _items[i];
      if (item['stock_item_id'] == null) {
        ErrorHandler.showWarningMessage(context, 'Please select a stock item for item ${i + 1}');
        return;
      }
      if ((item['quantity'] as int? ?? 0) <= 0) {
        ErrorHandler.showWarningMessage(context, 'Quantity must be greater than 0 for item ${i + 1}');
        return;
      }
      if ((item['unit_cost'] as int? ?? 0) <= 0) {
        ErrorHandler.showWarningMessage(context, 'Unit cost must be greater than 0 for item ${i + 1}');
        return;
      }
    }

    setState(() => _isLoading = true);

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final purchaserId = authService.currentUser?.id;

      if (purchaserId == null) {
        throw Exception('User must be logged in to create purchase orders');
      }

      await _dataService.createPurchaseOrder({
        'purchaser_id': purchaserId,
        'supplier_name': _supplierController.text.trim(),
        'total_cost': _totalCost, // Already in kobo
        'items': _items.map((item) => {
          'stock_item_id': item['stock_item_id'],
          'quantity': item['quantity'],
          'unit_cost': item['unit_cost'], // Already in kobo
        }).toList(),
      });

      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Purchase order created successfully!');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to create purchase order. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  void dispose() {
    _supplierController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Purchase Order'),
        backgroundColor: Colors.blue[700],
      ),
      body: _isLoadingItems
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Supplier Name
                          TextFormField(
                            controller: _supplierController,
                            decoration: const InputDecoration(
                              labelText: 'Supplier Name *',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.business),
                            ),
                            validator: (value) {
                              if (value?.trim().isEmpty ?? true) {
                                return 'Please enter supplier name';
                              }
                              return null;
                            },
                          ),
                          const SizedBox(height: 24),

                          // Items Section
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                'Items',
                                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              ),
                              ElevatedButton.icon(
                                onPressed: _addItem,
                                icon: const Icon(Icons.add),
                                label: const Text('Add Item'),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // Items List
                          if (_items.isEmpty)
                            const Center(
                              child: Padding(
                                padding: EdgeInsets.all(32.0),
                                child: Text(
                                  'No items added. Click "Add Item" to start.',
                                  style: TextStyle(color: Colors.grey),
                                ),
                              ),
                            )
                          else
                            ...List.generate(_items.length, (index) {
                              return _buildItemCard(index);
                            }),

                          const SizedBox(height: 16),

                          // Total Cost
                          Card(
                            color: Colors.blue[50],
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Text(
                                    'Total Cost:',
                                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                  ),
                                  Text(
                                    '₦${(_totalCost / 100).toStringAsFixed(2)}',
                                    style: TextStyle(
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.blue[700],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Submit Button
                  Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: SafeArea(
                      child: SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading ? null : _submitPurchaseOrder,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue[700],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text(
                                  'Submit Purchase Order',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildItemCard(int index) {
    final item = _items[index];
    final selectedStockItemId = item['stock_item_id'] as String?;
    final selectedStockItem = _stockItems.firstWhere(
      (si) => si['id'] == selectedStockItemId,
      orElse: () => <String, dynamic>{},
    );

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Item ${index + 1}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _removeItem(index),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Stock Item Dropdown
            DropdownButtonFormField<String>(
              value: selectedStockItemId,
              decoration: const InputDecoration(
                labelText: 'Stock Item *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.inventory_2),
              ),
              items: _stockItems.map((stockItem) {
                return DropdownMenuItem<String>(
                  value: stockItem['id'] as String?,
                  child: Text(stockItem['name'] as String? ?? 'Unknown'),
                );
              }).toList(),
              onChanged: (value) => _updateItem(index, 'stock_item_id', value),
              validator: (value) {
                if (value == null) {
                  return 'Please select a stock item';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Quantity
            TextFormField(
              initialValue: (item['quantity'] as int? ?? 1).toString(),
              decoration: const InputDecoration(
                labelText: 'Quantity *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.numbers),
              ),
              keyboardType: TextInputType.number,
              onChanged: (value) {
                final qty = int.tryParse(value) ?? 0;
                _updateItem(index, 'quantity', qty);
              },
              validator: (value) {
                final qty = int.tryParse(value ?? '0') ?? 0;
                if (qty <= 0) {
                  return 'Quantity must be greater than 0';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),

            // Unit Cost (in Naira, will convert to kobo)
            TextFormField(
              initialValue: ((item['unit_cost'] as int? ?? 0) / 100).toStringAsFixed(2),
              decoration: const InputDecoration(
                labelText: 'Unit Cost (₦) *',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.attach_money),
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              onChanged: (value) {
                final costInNaira = double.tryParse(value) ?? 0.0;
                final costInKobo = PaymentService.nairaToKobo(costInNaira);
                _updateItem(index, 'unit_cost', costInKobo);
              },
              validator: (value) {
                final costInNaira = double.tryParse(value ?? '0') ?? 0.0;
                if (costInNaira <= 0) {
                  return 'Unit cost must be greater than 0';
                }
                return null;
              },
            ),

            // Item Total
            if (selectedStockItemId != null)
              Padding(
                padding: const EdgeInsets.only(top: 8.0),
                child: Text(
                  'Item Total: ₦${((item['total_cost'] as int? ?? 0) / 100).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue[700],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
