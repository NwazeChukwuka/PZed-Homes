import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class DailyStockCountScreen extends StatefulWidget {
  const DailyStockCountScreen({super.key});

  @override
  State<DailyStockCountScreen> createState() => _DailyStockCountScreenState();
}

class _DailyStockCountScreenState extends State<DailyStockCountScreen> {
  final _supabase = Supabase.instance.client;
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, int> _previousCounts = {};

  String? _selectedLocationId;
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _stockItems = [];
  bool _isLoading = false;
  bool _isLoadingData = true;
  String _countType = 'Opening';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final [locations, stockItems] = await Future.wait([
        _supabase.from('locations').select(),
        _supabase.from('stock_items').select('id, name, unit'),
      ]);

      setState(() {
        _locations = List<Map<String, dynamic>>.from(locations);
        _stockItems = List<Map<String, dynamic>>.from(stockItems);
        
        // Initialize controllers and previous counts
        // Note: stock_items don't have current_stock - it's calculated from transactions
        // We'll initialize previous counts as 0, or calculate from transactions if needed
        for (var item in _stockItems) {
          final itemId = item['id'] as String;
          _controllers[itemId] = TextEditingController();
          _previousCounts[itemId] = 0; // Will be calculated from stock_transactions if needed
        }
        
        _isLoadingData = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingData = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load stock data. Please check your connection and try again.',
          onRetry: _loadData,
        );
      }
    }
  }

  Future<void> _submitCount() async {
    if (_selectedLocationId == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please select a location',
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final staffId = authService.currentUser!.id;
      final List<Map<String, dynamic>> transactions = [];

      for (var item in _stockItems) {
        final itemId = item['id'] as String;
        final qtyString = _controllers[itemId]?.text.trim() ?? '';
        
        if (qtyString.isNotEmpty) {
          final quantity = int.tryParse(qtyString) ?? 0;
          transactions.add({
            'stock_item_id': itemId,
            'location_id': _selectedLocationId,
            'staff_profile_id': staffId,
            'transaction_type': _countType,
            'quantity': quantity,
            'previous_quantity': _previousCounts[itemId],
            'notes': 'Daily stock count',
          });
        }
      }

      if (transactions.isNotEmpty) {
        await _supabase.from('stock_transactions').insert(transactions);
        
        // Note: Stock levels for stock_items are calculated from stock_transactions
        // using the calculate_stock_level() function, so no manual update is needed.
        // The transactions themselves represent the stock changes.

        if (mounted) {
          ErrorHandler.showSuccessMessage(
            context,
            'Stock count submitted successfully!',
          );
        }

        // Clear controllers and reload data
        _controllers.forEach((key, value) => value.clear());
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to submit stock count. Please try again.',
          onRetry: _submitCount,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _controllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Daily Stock Count'),
        backgroundColor: Colors.brown.shade700,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoadingData
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Header Section
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: _selectedLocationId,
                            decoration: const InputDecoration(
                              labelText: 'Select Location',
                              border: OutlineInputBorder(),
                              prefixIcon: Icon(Icons.location_on),
                            ),
                            items: _locations.map((loc) => DropdownMenuItem(
                              value: loc['id'] as String,
                              child: Text(loc['name'] as String),
                            )).toList(),
                            onChanged: (val) => setState(() => _selectedLocationId = val),
                          ),
                          const SizedBox(height: 16),
                          SegmentedButton<String>(
                            segments: const [
                              ButtonSegment(value: 'Opening', label: Text('Opening Stock')),
                              ButtonSegment(value: 'Closing', label: Text('Closing Stock')),
                            ],
                            selected: {_countType},
                            onSelectionChanged: (selection) => setState(() => _countType = selection.first),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                // Stock Items List
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    itemCount: _stockItems.length,
                    itemBuilder: (context, index) {
                      final item = _stockItems[index];
                      final itemId = item['id'] as String;
                      final unit = item['unit'] as String? ?? 'units';
                      final currentStock = _previousCounts[itemId] ?? 0;

                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4.0),
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item['name'] as String,
                                      style: const TextStyle(fontWeight: FontWeight.bold),
                                    ),
                                    Text(
                                      'Current: $currentStock $unit',
                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                    ),
                                  ],
                                ),
                              ),
                              SizedBox(
                                width: 120,
                                child: TextFormField(
                                  controller: _controllers[itemId],
                                  textAlign: TextAlign.center,
                                  decoration: InputDecoration(
                                    hintText: 'Count',
                                    border: const OutlineInputBorder(),
                                    contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                                    suffixText: unit,
                                  ),
                                  keyboardType: TextInputType.number,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),

                // Submit Button
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: _isLoading
                      ? const CircularProgressIndicator()
                      : ElevatedButton(
                          onPressed: _submitCount,
                          style: ElevatedButton.styleFrom(
                            minimumSize: const Size(double.infinity, 50),
                            backgroundColor: Colors.brown.shade700,
                          ),
                          child: const Text('Submit Stock Count'),
                        ),
                ),
              ],
            ),
    );
  }
}