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
  final List<Map<String, dynamic>> _customItems = []; // Custom items not in database

  String? _selectedLocationId;
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _stockItems = [];
  List<String> _allowedLocationNames = [];
  bool _isLoading = false;
  bool _isLoadingData = true;
  String _countType = 'Opening';
  bool _isManagement = false;

  @override
  void initState() {
    super.initState();
    _checkIfManagement();
    _loadData();
  }

  void _checkIfManagement() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    if (user == null) return;

    final roles = <AppRole>{
      ...user.roles,
      if (authService.isRoleAssumed && authService.assumedRole != null)
        authService.assumedRole!,
    };

    _isManagement = roles.contains(AppRole.owner) ||
        roles.contains(AppRole.manager) ||
        roles.contains(AppRole.supervisor);
    
    // If management, redirect to approval screen
    if (_isManagement && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.of(context).pushReplacementNamed('/stock/approval');
      });
    }
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

    // Management should NOT be able to record stock counts - they only review
    // Storekeeper can record counts for Store location
    final isManagement = roles.contains(AppRole.owner) ||
        roles.contains(AppRole.manager) ||
        roles.contains(AppRole.supervisor);

    if (isManagement) {
      _allowedLocationNames = [];
      return []; // Return empty - management should not see recording screen
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
    if (roles.contains(AppRole.storekeeper) || roles.contains(AppRole.purchaser)) {
      allowed.add('Store');
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
      List<Map<String, dynamic>> merged = [];
      
      // Mini Mart uses mini_mart_items table, not stock_levels
      if (locationName.toLowerCase() == 'mini mart') {
        final miniMartItems = await _supabase
            .from('mini_mart_items')
            .select('id, name, stock_quantity, unit');
        
        merged = (miniMartItems as List).map((item) {
          return {
            'id': item['id'],
            'name': item['name'],
            'unit': item['unit'] ?? 'units',
            'current_stock': item['stock_quantity'] ?? 0,
          };
        }).toList();
      } else {
        // Other locations use stock_levels view
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
        merged = levelList.map((level) {
          final id = level['id'];
          final base = byId[id] ?? {};
          return {
            'id': level['id'],
            'name': level['name'],
            'unit': base['unit'] ?? 'units',
            'current_stock': level['current_stock'] ?? 0,
          };
        }).toList();
      }

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
      final location = _locations.firstWhere(
        (loc) => loc['id'] == _selectedLocationId,
        orElse: () => <String, dynamic>{},
      );
      final locationName = (location['name'] ?? '').toString();
      final isMiniMart = locationName.toLowerCase() == 'mini mart';
      
      final List<Map<String, dynamic>> countItems = [];

      // Collect all items with counts (even if same as system quantity)
      for (var item in _stockItems) {
        final itemId = item['id'] as String;
        final qtyString = _controllers[itemId]?.text.trim() ?? '';
        
        if (qtyString.isNotEmpty) {
          final countedQuantity = int.tryParse(qtyString) ?? 0;
          final systemQuantity = _previousCounts[itemId] ?? 0;
          
          // For Mini Mart items, we need to find or create corresponding stock_item
          String stockItemId = itemId;
          if (isMiniMart) {
            // Check if stock_item exists for this mini_mart_item
            final existingStockItem = await _supabase
                .from('stock_items')
                .select('id')
                .eq('name', item['name'] as String)
                .maybeSingle();
            
            if (existingStockItem != null) {
              stockItemId = existingStockItem['id'] as String;
            } else {
              // Create corresponding stock_item for mini_mart_item
              final newStockItem = await _supabase
                  .from('stock_items')
                  .insert({
                    'name': item['name'],
                    'description': 'Mini Mart item',
                    'category': 'Mini Mart',
                    'unit': item['unit'] ?? 'units',
                    'min_stock': 5,
                  })
                  .select('id')
                  .single();
              stockItemId = newStockItem['id'] as String;
            }
          }
          
          // Include all items that were counted (even if no change)
          countItems.add({
            'stock_item_id': stockItemId,
            'counted_quantity': countedQuantity,
            'system_quantity': systemQuantity,
          });
        }
      }

      if (countItems.isEmpty) {
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Please enter counts for at least one item',
          );
        }
        return;
      }

      // Create pending stock count record
      final countDate = DateTime.now().toIso8601String().split('T')[0];
      final countResponse = await _supabase
          .from('pending_stock_counts')
          .insert({
            'location_id': _selectedLocationId,
            'count_type': _countType,
            'count_date': countDate,
            'submitted_by': staffId,
            'status': 'pending',
          })
          .select('id')
          .single();

      final countId = countResponse['id'] as String;

      // Insert count items with reference to the pending count
      final itemsToInsert = countItems.map((item) => <String, dynamic>{
        'stock_count_id': countId,
        'stock_item_id': item['stock_item_id'],
        'counted_quantity': item['counted_quantity'],
        'system_quantity': item['system_quantity'],
      }).toList();

      await _supabase.from('stock_count_items').insert(itemsToInsert);

      // Insert custom items if any
      if (_customItems.isNotEmpty) {
        final customItemsToInsert = _customItems.map((item) => <String, dynamic>{
          'stock_count_id': countId,
          'item_name': item['name'],
          'quantity': item['quantity'],
          'unit': item['unit'] ?? 'units',
          'notes': item['notes'],
        }).toList();
        await _supabase.from('stock_count_custom_items').insert(customItemsToInsert);
      }

      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Stock count submitted for management approval!',
        );
      }

      // Clear controllers and reload data
      _controllers.forEach((key, value) => value.clear());
      setState(() {
        _customItems.clear();
      });
      await _loadData();
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

  void _showAddCustomItemDialog() {
    final nameController = TextEditingController();
    final quantityController = TextEditingController();
    final unitController = TextEditingController(text: 'units');
    final notesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Custom Item'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Item Name *',
                  border: OutlineInputBorder(),
                ),
                autofocus: true,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: quantityController,
                      decoration: const InputDecoration(
                        labelText: 'Quantity *',
                        border: OutlineInputBorder(),
                      ),
                      keyboardType: TextInputType.number,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: unitController,
                      decoration: const InputDecoration(
                        labelText: 'Unit',
                        border: OutlineInputBorder(),
                        hintText: 'units',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                  hintText: 'Additional details about this item',
                ),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              final name = nameController.text.trim();
              final quantityStr = quantityController.text.trim();
              final quantity = int.tryParse(quantityStr) ?? 0;

              if (name.isEmpty) {
                ErrorHandler.showWarningMessage(context, 'Please enter item name');
                return;
              }
              if (quantity <= 0) {
                ErrorHandler.showWarningMessage(context, 'Please enter a valid quantity');
                return;
              }

              setState(() {
                _customItems.add({
                  'name': name,
                  'quantity': quantity,
                  'unit': unitController.text.trim().isEmpty ? 'units' : unitController.text.trim(),
                  'notes': notesController.text.trim(),
                });
              });

              Navigator.pop(context);
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _controllers.forEach((key, controller) => controller.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Double safety: If management somehow reaches this screen, redirect immediately
    if (_isManagement) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/stock/approval');
        }
      });
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    
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
                  child: ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16.0),
                    children: [
                      // Existing stock items
                      ..._stockItems.map((item) {
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
                      }).toList(),

                      // Custom Items Section
                      const SizedBox(height: 16),
                      Card(
                        color: Colors.blue.shade50,
                        child: Padding(
                          padding: const EdgeInsets.all(12.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Icon(Icons.add_circle_outline, color: Colors.blue),
                                  const SizedBox(width: 8),
                                  const Text(
                                    'Custom Items (Not in Database)',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                  ),
                                  const Spacer(),
                                  IconButton(
                                    icon: const Icon(Icons.add, color: Colors.blue),
                                    onPressed: _showAddCustomItemDialog,
                                    tooltip: 'Add Custom Item',
                                  ),
                                ],
                              ),
                              if (_customItems.isEmpty)
                                Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Text(
                                    'No custom items added. Tap + to add items you see that are not in the database.',
                                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                                  ),
                                )
                              else
                                ..._customItems.asMap().entries.map((entry) {
                                  final index = entry.key;
                                  final customItem = entry.value;
                                  return Card(
                                    margin: const EdgeInsets.symmetric(vertical: 4.0),
                                    child: ListTile(
                                      title: Text(
                                        customItem['name'] as String,
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                      ),
                                      subtitle: Text(
                                        'Quantity: ${customItem['quantity']} ${customItem['unit'] ?? 'units'}',
                                      ),
                                      trailing: IconButton(
                                        icon: const Icon(Icons.delete, color: Colors.red),
                                        onPressed: () {
                                          setState(() {
                                            _customItems.removeAt(index);
                                          });
                                        },
                                      ),
                                    ),
                                  );
                                }).toList(),
                            ],
                          ),
                        ),
                      ),
                    ],
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