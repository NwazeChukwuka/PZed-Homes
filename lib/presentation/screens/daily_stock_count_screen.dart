import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';

class DailyStockCountScreen extends StatefulWidget {
  const DailyStockCountScreen({super.key});

  @override
  State<DailyStockCountScreen> createState() => _DailyStockCountScreenState();
}

class _DailyStockCountScreenState extends State<DailyStockCountScreen> {
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw Exception('Supabase not initialized');
    }
  }
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, int> _previousCounts = {};

  String? _selectedLocationId;
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _stockItems = [];
  List<String> _allowedLocationNames = [];
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
      if (_supabase == null) {
        throw Exception('Supabase not initialized');
      }
      final locations = await _supabase.from('locations').select();
      final filteredLocations = _filterLocationsByRole(
        List<Map<String, dynamic>>.from(locations),
      );

      setState(() {
        _locations = filteredLocations;
        if (_locations.length == 1) {
          _selectedLocationId = _locations.first['id'] as String?;
        }
        
        _isLoadingData = false;
      });

      if (_selectedLocationId != null) {
        await _loadItemsForLocation(_selectedLocationId!);
      }
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

  List<Map<String, dynamic>> _filterLocationsByRole(List<Map<String, dynamic>> locations) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    if (user == null) return [];

    final roles = <AppRole>{
      ...user.roles,
      if (authService.isRoleAssumed && authService.assumedRole != null)
        authService.assumedRole!,
    };

    final isManagement = roles.contains(AppRole.owner) ||
        roles.contains(AppRole.manager) ||
        roles.contains(AppRole.supervisor) ||
        roles.contains(AppRole.storekeeper);

    if (isManagement) {
      _allowedLocationNames = [];
      return locations;
    }

    final allowed = <String>{};
    if (roles.contains(AppRole.vip_bartender)) {
      allowed.add('VIP Bar');
    }
    if (roles.contains(AppRole.outside_bartender)) {
      allowed.add('Outside Bar');
    }
    if (roles.contains(AppRole.kitchen_staff)) {
      allowed.add('Kitchen');
    }
    if (roles.contains(AppRole.receptionist)) {
      allowed.add('Mini Mart');
    }
    if (roles.contains(AppRole.housekeeper) || roles.contains(AppRole.cleaner)) {
      allowed.add('Housekeeping');
    }
    if (roles.contains(AppRole.laundry_attendant)) {
      allowed.add('Laundry');
    }

    _allowedLocationNames = allowed.toList();

    return locations.where((loc) {
      final name = (loc['name'] ?? '').toString();
      return allowed.contains(name);
    }).toList();
  }

  Future<void> _loadItemsForLocation(String locationId) async {
    final location = _locations.firstWhere(
      (loc) => loc['id'] == locationId,
      orElse: () => <String, dynamic>{},
    );
    final locationName = (location['name'] ?? '').toString();
    if (locationName.isEmpty) return;

    try {
      final stockLevels = await _supabase
          .from('stock_levels')
          .select('id, name, current_stock, location_name')
          .eq('location_name', locationName);

      final levelList = List<Map<String, dynamic>>.from(stockLevels);
      final itemIds = levelList.map((e) => e['id']).toList();

      List<Map<String, dynamic>> stockItems = [];
      if (itemIds.isNotEmpty) {
        final itemsResponse = await _supabase
            .from('stock_items')
            .select('id, name, unit')
            .inFilter('id', itemIds);
        stockItems = List<Map<String, dynamic>>.from(itemsResponse);
      }

      final byId = {for (final i in stockItems) i['id']: i};
      final merged = levelList.map((level) {
        final id = level['id'];
        final base = byId[id] ?? {};
        return {
          'id': level['id'],
          'name': level['name'],
          'unit': base['unit'] ?? 'units',
          'current_stock': level['current_stock'] ?? 0,
        };
      }).toList();

      setState(() {
        _stockItems = merged;
        _controllers.clear();
        _previousCounts.clear();
        for (var item in _stockItems) {
          final itemId = item['id'] as String;
          _controllers[itemId] = TextEditingController();
          _previousCounts[itemId] = (item['current_stock'] as num?)?.toInt() ?? 0;
        }
      });
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load stock for this location.',
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
          final previous = _previousCounts[itemId] ?? 0;
          final delta = quantity - previous;
          if (delta != 0) {
            transactions.add({
              'stock_item_id': itemId,
              'location_id': _selectedLocationId,
              'staff_profile_id': staffId,
              'transaction_type': 'Adjustment',
              'quantity': delta,
              'notes': 'Daily stock count (${_countType.toLowerCase()})',
            });
          }
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
                            onChanged: (val) async {
                              setState(() => _selectedLocationId = val);
                              if (val != null) {
                                await _loadItemsForLocation(val);
                              }
                            },
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