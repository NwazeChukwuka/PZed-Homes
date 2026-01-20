import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../core/services/data_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/error/error_handler.dart';
import '../../data/models/user.dart';

/// Bartender Shift Management Screen
/// Allows bartenders to record opening stock, transfers from other departments, and closing stock
class BartenderShiftScreen extends StatefulWidget {
  const BartenderShiftScreen({super.key});

  @override
  State<BartenderShiftScreen> createState() => _BartenderShiftScreenState();
}

class _BartenderShiftScreenState extends State<BartenderShiftScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DataService _dataService = DataService();
  
  // Shift state
  bool _hasActiveShift = false;
  Map<String, dynamic>? _currentShift;
  String _selectedBar = 'vip_bar'; // vip_bar or outside_bar
  
  // Opening stock
  List<Map<String, dynamic>> _openingStockItems = [];
  
  // Transfers
  List<Map<String, dynamic>> _shiftTransfers = [];
  List<Map<String, dynamic>> _pendingDirectSupplies = [];
  
  // Closing stock
  List<Map<String, dynamic>> _closingStockItems = [];
  
  // Available items for the bar
  List<Map<String, dynamic>> _availableItems = [];
  List<Map<String, dynamic>> _locations = [];
  
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadShiftData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final hasVip = user?.roles.contains(AppRole.vip_bartender) ?? false;
    final hasOutside = user?.roles.contains(AppRole.outside_bartender) ?? false;

    String? fixedBar;
    if (hasVip && !hasOutside) fixedBar = 'vip_bar';
    if (hasOutside && !hasVip) fixedBar = 'outside_bar';

    if (fixedBar != null && _selectedBar != fixedBar) {
      setState(() => _selectedBar = fixedBar!);
      _loadShiftData();
    }
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadShiftData() async {
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final staffId = authService.currentUser?.id ?? 'unknown';
      final isManagement = authService.currentUser?.roles.any(
            (role) => role == AppRole.owner || role == AppRole.manager,
          ) ??
          false;
      // Check for active shift
      final activeShift = await _dataService.getActiveShift(
        bartenderId: staffId,
        bar: _selectedBar,
      );
      final items = await _dataService.getInventoryItems();
      final locations = await _dataService.getLocations();
      final pendingSupplies = isManagement
          ? await _dataService.getDirectSupplyRequests(
              status: 'pending',
              bar: _selectedBar,
            )
          : <Map<String, dynamic>>[];
      
      setState(() {
        _hasActiveShift = activeShift != null;
        _currentShift = activeShift;
        _availableItems = items.where((item) => 
          item['category'] == 'Beverages' || item['category'] == 'Food Items'
        ).toList();
        _locations = locations;
        _pendingDirectSupplies = pendingSupplies;
        
        if (_hasActiveShift) {
          _openingStockItems = List<Map<String, dynamic>>.from(_currentShift!['opening_stock'] ?? []);
          _shiftTransfers = List<Map<String, dynamic>>.from(_currentShift!['transfers'] ?? []);
          _closingStockItems = List<Map<String, dynamic>>.from(_currentShift!['closing_stock'] ?? []);
        }
        
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load shift data. Please check your connection and try again.',
          onRetry: _loadShiftData,
        );
      }
    }
  }

  Future<void> _startShift() async {
    if (_openingStockItems.isEmpty) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please record opening stock before starting shift',
        );
      }
      return;
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final staffId = authService.currentUser?.id ?? 'unknown';
      
      await _dataService.startShift(
        bartenderId: staffId,
        bar: _selectedBar,
        openingStock: _openingStockItems,
      );
      
      await _loadShiftData();
      
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Shift started successfully');
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to start shift. Please try again.',
          onRetry: _startShift,
        );
      }
    }
  }

  Future<void> _endShift() async {
    if (_closingStockItems.isEmpty) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please record closing stock before ending shift',
        );
      }
      return;
    }

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final staffId = authService.currentUser?.id ?? 'unknown';
      await _dataService.endShift(
        shiftId: _currentShift!['id'],
        closingStock: _closingStockItems,
        transfers: _shiftTransfers,
        closedBy: staffId,
      );
      
      setState(() {
        _hasActiveShift = false;
        _currentShift = null;
        _openingStockItems.clear();
        _shiftTransfers.clear();
        _closingStockItems.clear();
      });
      
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Shift ended successfully');
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to end shift. Please try again.',
          onRetry: _endShift,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final hasVip = user?.roles.contains(AppRole.vip_bartender) ?? false;
    final hasOutside = user?.roles.contains(AppRole.outside_bartender) ?? false;
    final canSelectBar = !(hasVip ^ hasOutside);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Bartender Shift Management'),
        backgroundColor: Colors.purple[700],
        foregroundColor: Colors.white,
        leading: Navigator.of(context).canPop()
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,
        actions: [
          // Bar selector
          if (canSelectBar)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: DropdownButton<String>(
                value: _selectedBar,
                dropdownColor: Colors.purple[700],
                style: const TextStyle(color: Colors.white),
                underline: Container(),
                items: const [
                  DropdownMenuItem(value: 'vip_bar', child: Text('VIP Bar')),
                  DropdownMenuItem(value: 'outside_bar', child: Text('Outside Bar')),
                ],
                onChanged: (value) {
                  if (value != null) {
                    setState(() => _selectedBar = value);
                    _loadShiftData();
                  }
                },
              ),
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Shift Status', icon: Icon(Icons.access_time)),
            Tab(text: 'Opening Stock', icon: Icon(Icons.inventory)),
            Tab(text: 'Transfers', icon: Icon(Icons.swap_horiz)),
            Tab(text: 'Closing Stock', icon: Icon(Icons.inventory_2)),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildShiftStatusTab(),
                _buildOpeningStockTab(),
                _buildTransfersTab(),
                _buildClosingStockTab(),
              ],
            ),
    );
  }

  Widget _buildShiftStatusTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Shift Status Card
          Card(
            color: _hasActiveShift ? Colors.green[50] : Colors.grey[100],
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(
                    _hasActiveShift ? Icons.check_circle : Icons.access_time,
                    size: 64,
                    color: _hasActiveShift ? Colors.green[700] : Colors.grey[600],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _hasActiveShift ? 'Shift Active' : 'No Active Shift',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: _hasActiveShift ? Colors.green[800] : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _selectedBar == 'vip_bar' ? 'VIP Bar' : 'Outside Bar',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                  if (_hasActiveShift && _currentShift != null) ...[
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 16),
                    _buildShiftDetail('Started At', _formatDateTime(_currentShift!['start_time'])),
                    const SizedBox(height: 8),
                    _buildShiftDetail('Bartender', _currentShift!['staff_name'] ?? 'Unknown'),
                    const SizedBox(height: 8),
                    _buildShiftDetail('Opening Items', '${_openingStockItems.length}'),
                    const SizedBox(height: 8),
                    _buildShiftDetail('Transfers Received', '${_shiftTransfers.length}'),
                  ],
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 24),
          
          // Action Buttons
          if (!_hasActiveShift)
            ElevatedButton.icon(
              onPressed: _startShift,
              icon: const Icon(Icons.play_arrow),
              label: const Text('Start Shift', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            )
          else
            ElevatedButton.icon(
              onPressed: _endShift,
              icon: const Icon(Icons.stop),
              label: const Text('End Shift', style: TextStyle(fontSize: 16)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.all(16),
              ),
            ),
          
          const SizedBox(height: 16),
          
          // Quick Stats
          if (_hasActiveShift) ...[
            const Text('Shift Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard('Opening', '${_openingStockItems.length}', Icons.inventory, Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildStatCard('Transfers', '${_shiftTransfers.length}', Icons.swap_horiz, Colors.orange),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildShiftDetail(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[700])),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ],
        ),
      ),
    );
  }

  Widget _buildOpeningStockTab() {
    return Column(
      children: [
        if (!_hasActiveShift)
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.blue[50],
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.blue[700]),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Record the stock available at the start of your shift'),
                ),
              ],
            ),
          ),
        
        Expanded(
          child: _openingStockItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No opening stock recorded', style: TextStyle(color: Colors.grey[600])),
                      if (!_hasActiveShift) ...[
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _showAddOpeningStockDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Opening Stock'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _openingStockItems.length,
                  itemBuilder: (context, index) {
                    final item = _openingStockItems[index];
                    return _buildStockItemCard(item, index, isOpening: true);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildTransfersTab() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final isManagement = authService.currentUser?.roles.any(
          (role) => role == AppRole.owner || role == AppRole.manager,
        ) ??
        false;
    return Column(
      children: [
        if (_hasActiveShift)
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.orange[50],
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.orange[700]),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Record items received from other departments during your shift'),
                ),
              ],
            ),
          ),
        
        if (isManagement) _buildPendingDirectSupplies(),
        Expanded(
          child: _shiftTransfers.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.swap_horiz, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No transfers recorded', style: TextStyle(color: Colors.grey[600])),
                      if (_hasActiveShift) ...[
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _showAddTransferDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Record Transfer'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _shiftTransfers.length,
                  itemBuilder: (context, index) {
                    final transfer = _shiftTransfers[index];
                    return _buildTransferCard(transfer, index);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildClosingStockTab() {
    return Column(
      children: [
        if (_hasActiveShift)
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.purple[50],
            child: Row(
              children: [
                Icon(Icons.info, color: Colors.purple[700]),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text('Record the remaining stock at the end of your shift'),
                ),
              ],
            ),
          ),
        
        Expanded(
          child: _closingStockItems.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.inventory_2, size: 64, color: Colors.grey[400]),
                      const SizedBox(height: 16),
                      Text('No closing stock recorded', style: TextStyle(color: Colors.grey[600])),
                      if (_hasActiveShift) ...[
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: _showAddClosingStockDialog,
                          icon: const Icon(Icons.add),
                          label: const Text('Add Closing Stock'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.purple[700],
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _closingStockItems.length,
                  itemBuilder: (context, index) {
                    final item = _closingStockItems[index];
                    return _buildStockItemCard(item, index, isOpening: false);
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildStockItemCard(Map<String, dynamic> item, int index, {required bool isOpening}) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isOpening ? Colors.blue[100] : Colors.purple[100],
          child: Icon(
            Icons.inventory,
            color: isOpening ? Colors.blue[700] : Colors.purple[700],
          ),
        ),
        title: Text(item['item_name'] ?? 'Unknown Item'),
        subtitle: Text('${item['quantity']} ${item['unit'] ?? 'units'}'),
        trailing: !_hasActiveShift
            ? IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () {
                  setState(() {
                    if (isOpening) {
                      _openingStockItems.removeAt(index);
                    } else {
                      _closingStockItems.removeAt(index);
                    }
                  });
                },
              )
            : null,
      ),
    );
  }

  Widget _buildTransferCard(Map<String, dynamic> transfer, int index) {
    final status = transfer['status'] as String?;
    final statusLabel = status == null
        ? ''
        : status == 'approved'
            ? ' (Approved)'
            : status == 'denied'
                ? ' (Denied)'
                : ' (Pending)';
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Colors.orange[100],
          child: Icon(Icons.swap_horiz, color: Colors.orange[700]),
        ),
        title: Text(transfer['item_name'] ?? 'Unknown Item'),
        subtitle: Text(
          '${transfer['quantity']} ${transfer['unit'] ?? 'units'} from ${_displayTransferSource(transfer['source'] as String?)}$statusLabel',
        ),
        trailing: Text(
          _formatTime(transfer['time']),
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
        ),
      ),
    );
  }

  void _showAddOpeningStockDialog() {
    final quantityController = TextEditingController();
    String? selectedItem;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Opening Stock'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedItem,
                decoration: const InputDecoration(labelText: 'Select Item'),
                items: _availableItems.map((item) {
                  return DropdownMenuItem(
                    value: item['id'].toString(),
                    child: Text(item['name'] ?? 'Unknown'),
                  );
                }).toList(),
                onChanged: (value) => setDialogState(() => selectedItem = value),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: TextInputType.number,
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
              if (selectedItem != null && quantityController.text.isNotEmpty) {
                final item = _availableItems.firstWhere((i) => i['id'].toString() == selectedItem);
                setState(() {
                  _openingStockItems.add({
                    'item_id': item['id'],
                    'item_name': item['name'],
                    'quantity': double.parse(quantityController.text),
                    'unit': item['unit'],
                  });
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showAddTransferDialog() {
    final quantityController = TextEditingController();
    String? selectedItem;
    String source = 'general_store';

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Transfer'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedItem,
                decoration: const InputDecoration(labelText: 'Select Item'),
                items: _availableItems.map((item) {
                  return DropdownMenuItem(
                    value: item['id'].toString(),
                    child: Text(item['name'] ?? 'Unknown'),
                  );
                }).toList(),
                onChanged: (value) => setDialogState(() => selectedItem = value),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                value: source,
                decoration: const InputDecoration(labelText: 'Source'),
                items: const [
                  DropdownMenuItem(value: 'general_store', child: Text('General Store')),
                  DropdownMenuItem(value: 'vip_bar', child: Text('VIP Bar')),
                  DropdownMenuItem(value: 'outside_bar', child: Text('Outside Bar')),
                  DropdownMenuItem(value: 'kitchen', child: Text('Kitchen')),
                  DropdownMenuItem(value: 'direct_supply', child: Text('Direct Supply (Management)')),
                ],
                onChanged: (value) => setDialogState(() => source = value!),
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
            onPressed: () async {
              if (selectedItem != null && quantityController.text.isNotEmpty) {
                try {
                  final authService = Provider.of<AuthService>(context, listen: false);
                  final staffId = authService.currentUser?.id ?? 'unknown';
                  final item = _availableItems.firstWhere((i) => i['id'].toString() == selectedItem);
                  final qty = int.tryParse(quantityController.text.trim()) ?? 0;
                  if (qty <= 0) {
                    throw Exception('Enter a valid quantity');
                  }

                  final stockItem = await _dataService.supabase
                      .from('stock_items')
                      .select('id')
                      .eq('name', item['name'] as String)
                      .maybeSingle();
                  if (stockItem == null) {
                    throw Exception('Stock item not found for ${item['name']}. Create it first.');
                  }

                  final destinationLocationName = _selectedBar == 'vip_bar' ? 'VIP Bar' : 'Outside Bar';
                  final destinationLocationId = _getLocationIdByName(destinationLocationName);
                  if (destinationLocationId == null) {
                    throw Exception('Destination location not found. Please check locations setup.');
                  }

                  if (source == 'direct_supply') {
                    await _dataService.createDirectSupplyRequest(
                      stockItemId: stockItem['id'] as String,
                      bar: _selectedBar ?? 'vip_bar',
                      quantity: qty,
                      requestedBy: staffId,
                      notes: 'Direct supply request',
                    );
                  } else {
                    final sourceLocationName = _mapTransferSourceToLocation(source);
                    if (sourceLocationName == destinationLocationName) {
                      throw Exception('Source and destination cannot be the same.');
                    }

                  // If source is another bar, ensure it has enough stock to transfer (ledger-based)
                  if (source == 'vip_bar' || source == 'outside_bar') {
                    final sourceLevels = await _dataService.getStockLevels(
                      locationName: sourceLocationName,
                    );
                    final sourceItem = sourceLevels.firstWhere(
                      (row) => (row['name'] as String?) == item['name'],
                      orElse: () => <String, dynamic>{},
                    );
                    final sourceCurrentStock = (sourceItem['current_stock'] as num?)?.toInt() ?? 0;
                    if (sourceCurrentStock < qty) {
                      throw Exception(
                        'Insufficient stock in ${sourceLocationName}. Available: $sourceCurrentStock',
                      );
                    }
                  }

                    final sourceLocationId = _getLocationIdByName(sourceLocationName);
                    if (sourceLocationId == null) {
                      throw Exception('Source location not found for transfer. Please check locations setup.');
                    }

                    await _dataService.createStockTransfer(
                      stockItemId: stockItem['id'] as String,
                      sourceLocationId: sourceLocationId,
                      destinationLocationId: destinationLocationId,
                      quantity: qty,
                      issuedById: staffId,
                      receivedById: staffId,
                      notes: 'Bar transfer from $sourceLocationName',
                    );

                  }

                  // Stock ledger is the source of truth; no direct inventory_items update

                  setState(() {
                    _shiftTransfers.add({
                      'item_id': item['id'],
                      'item_name': item['name'],
                      'quantity': qty,
                      'unit': item['unit'],
                      'source': source,
                      if (source == 'direct_supply') 'status': 'pending',
                      'time': DateTime.now().toIso8601String(),
                    });
                  });
                  if (_hasActiveShift && _currentShift != null) {
                    await _dataService.updateShiftTransfers(
                      shiftId: _currentShift!['id'],
                      transfers: _shiftTransfers,
                    );
                  }
                  await _loadShiftData();
                  Navigator.pop(context);
                } catch (e) {
                  if (mounted) {
                    ErrorHandler.handleError(
                      context,
                      e,
                      customMessage: 'Failed to record transfer. Please try again.',
                    );
                  }
                }
              }
            },
            child: const Text('Record'),
          ),
        ],
      ),
    );
  }

  String _mapTransferSourceToLocation(String source) {
    switch (source) {
      case 'general_store':
        return 'Main Storeroom';
      case 'vip_bar':
        return 'VIP Bar';
      case 'outside_bar':
        return 'Outside Bar';
      case 'kitchen':
        return 'Kitchen';
      case 'direct_supply':
        return 'Management';
      default:
        return 'Main Storeroom';
    }
  }

  String _displayTransferSource(String? source) {
    switch (source) {
      case 'vip_bar':
        return 'VIP Bar';
      case 'outside_bar':
        return 'Outside Bar';
      case 'general_store':
        return 'General Store';
      case 'kitchen':
        return 'Kitchen';
      case 'direct_supply':
        return 'Direct Supply (Management)';
      default:
        return 'Unknown';
    }
  }

  Widget _buildPendingDirectSupplies() {
    if (_pendingDirectSupplies.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Pending Direct Supply Approvals',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._pendingDirectSupplies.map((req) {
                final itemName = (req['stock_items']?['name'] as String?) ?? 'Unknown Item';
                final qty = req['quantity']?.toString() ?? '0';
                final requester = (req['requested_by_profile']?['full_name'] as String?) ?? 'Unknown';
                return Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text('$itemName x$qty'),
                    subtitle: Text('Requested by $requester'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: const Icon(Icons.check_circle, color: Colors.green),
                          onPressed: () => _handleApproveDirectSupply(req['id'] as String, true),
                        ),
                        IconButton(
                          icon: const Icon(Icons.cancel, color: Colors.red),
                          onPressed: () => _handleApproveDirectSupply(req['id'] as String, false),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleApproveDirectSupply(String requestId, bool approve) async {
    try {
      await _dataService.approveDirectSupplyRequest(
        requestId: requestId,
        approve: approve,
        notes: approve ? 'Approved' : 'Denied',
      );
      await _loadShiftData();
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          approve ? 'Direct supply approved' : 'Direct supply denied',
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update direct supply request.',
        );
      }
    }
  }

  String? _getLocationIdByName(String name) {
    final match = _locations.firstWhere(
      (l) => (l['name'] as String?)?.toLowerCase() == name.toLowerCase(),
      orElse: () => <String, dynamic>{},
    );
    return match.isNotEmpty ? match['id'] as String? : null;
  }

  void _showAddClosingStockDialog() {
    final quantityController = TextEditingController();
    String? selectedItem;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Closing Stock'),
        content: StatefulBuilder(
          builder: (context, setDialogState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                value: selectedItem,
                decoration: const InputDecoration(labelText: 'Select Item'),
                items: _availableItems.map((item) {
                  return DropdownMenuItem(
                    value: item['id'].toString(),
                    child: Text(item['name'] ?? 'Unknown'),
                  );
                }).toList(),
                onChanged: (value) => setDialogState(() => selectedItem = value),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: quantityController,
                decoration: const InputDecoration(labelText: 'Quantity'),
                keyboardType: TextInputType.number,
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
              if (selectedItem != null && quantityController.text.isNotEmpty) {
                final item = _availableItems.firstWhere((i) => i['id'].toString() == selectedItem);
                setState(() {
                  _closingStockItems.add({
                    'item_id': item['id'],
                    'item_name': item['name'],
                    'quantity': double.parse(quantityController.text),
                    'unit': item['unit'],
                  });
                });
                Navigator.pop(context);
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  String _formatDateTime(dynamic dateTime) {
    if (dateTime == null) return 'N/A';
    try {
      final dt = dateTime is DateTime ? dateTime : DateTime.parse(dateTime.toString());
      return DateFormat('MMM dd, yyyy HH:mm').format(dt);
    } catch (e) {
      return dateTime.toString();
    }
  }

  String _formatTime(dynamic time) {
    if (time == null) return 'N/A';
    try {
      final dt = time is DateTime ? time : DateTime.parse(time.toString());
      return DateFormat('HH:mm').format(dt);
    } catch (e) {
      return time.toString();
    }
  }
}
