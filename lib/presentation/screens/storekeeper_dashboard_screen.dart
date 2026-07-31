import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/utils/staff_auth_helper.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:pzed_homes/presentation/widgets/layered_scroll_body.dart';
import 'package:pzed_homes/presentation/screens/confirm_purchases_screen.dart'; // We will reuse this screen
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';

class StorekeeperDashboardScreen extends StatefulWidget {
  const StorekeeperDashboardScreen({super.key});
  @override
  State<StorekeeperDashboardScreen> createState() => _StorekeeperDashboardScreenState();
}

class _StorekeeperDashboardScreenState extends State<StorekeeperDashboardScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    final authService = Provider.of<AuthService>(context, listen: false);
    final userRole = authService.currentUser?.role;
    final canManageWastage = [
      AppRole.owner,
      AppRole.manager,
      AppRole.supervisor,
      AppRole.accountant,
      AppRole.storekeeper,
    ].contains(userRole);
    
    _tabController = TabController(length: canManageWastage ? 4 : 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final selected = context.select<AuthService, ({bool showFull, bool ownerManager, bool isAssumed})>((auth) {
      final u = auth.currentUser;
      final isStorekeeper = u?.roles.any((r) => r.name == 'storekeeper') ?? false;
      final isAssumed = auth.hasAssumedRole(AppRole.storekeeper);
      final isOwnerOrManager = u?.roles.any((r) => r.name == 'owner' || r.name == 'manager') ?? false;
      return (showFull: isStorekeeper || isAssumed, ownerManager: isOwnerOrManager, isAssumed: isAssumed);
    });
    final showFull = selected.showFull;
    final ownerManager = selected.ownerManager;
    final isAssumedStorekeeper = selected.isAssumed;
        
    if (ownerManager && !isAssumedStorekeeper) {
      return Scaffold(
        body: LayeredScrollBody(
          topSection: _buildStorekeeperHeader(
            context: context,
            title: 'Store View',
            subtitle: '',
            showTabs: false,
          ),
          content: _buildReadOnlyStoreView(),
        ),
      );
    }

    if (!showFull) {
      return Scaffold(
        body: LayeredScrollBody(
          topSection: _buildStorekeeperHeader(
            context: context,
            title: 'Storekeeper Dashboard',
            subtitle: 'Assume Storekeeper role for full access',
            showTabs: false,
          ),
          content: const Center(child: Text('Access restricted. Assume Storekeeper role to view.')),
        ),
      );
    }

    return Scaffold(
      body: LayeredScrollBody(
        topSection: _buildStorekeeperHeader(
          context: context,
          title: 'Storekeeper Dashboard',
          subtitle: 'Warehouse operations and stock movement',
          showTabs: true,
        ),
        content: TabBarView(
          controller: _tabController,
          children: [
            const ConfirmPurchasesScreen(),
            const DirectStockEntryForm(),
            const StockTransferForm(),
            if (_canManageWastage(context))
              const WastageManagementTab(),
          ],
        ),
      ),
    );
  }

  Widget _buildStorekeeperHeader({
    required BuildContext context,
    required String title,
    required String subtitle,
    required bool showTabs,
  }) {
    final showLocalRoleButton = MediaQuery.sizeOf(context).width >= 700;
    return Column(
      children: [
        Container(
          color: Colors.green[700],
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          child: Row(
            children: [
              if (Navigator.of(context).canPop())
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Text(
                        subtitle,
                        style: const TextStyle(color: Colors.white70, fontSize: 12),
                      ),
                  ],
                ),
              ),
              if (showLocalRoleButton)
                const ContextAwareRoleButton(suggestedRole: AppRole.storekeeper),
            ],
          ),
        ),
        if (showTabs)
          TabBar(
            controller: _tabController,
            tabs: [
              const Tab(text: 'Confirm Purchases'),
              const Tab(text: 'Direct Stock Entry'),
              const Tab(text: 'Issue to Department'),
              if (_canManageWastage(context))
                const Tab(text: 'Wastage Management'),
            ],
          ),
      ],
    );
  }

  bool _canManageWastage(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
    final userRole = authService.currentUser?.role;
    return [
      AppRole.owner,
      AppRole.manager,
      AppRole.supervisor,
      AppRole.accountant,
      AppRole.storekeeper,
    ].contains(userRole);
  }

  Widget _buildReadOnlyStoreView() {
    final dataService = DataService();
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: dataService.getStockLevels(locationName: 'Main Store'),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return ErrorHandler.buildErrorWidget(
            context,
            snapshot.error,
            message: 'Error loading inventory',
            onRetry: () => setState(() {}), // Trigger rebuild
          );
        }
        
        final items = snapshot.data ?? [];
        if (items.isEmpty) {
          return ErrorHandler.buildEmptyWidget(
            context,
            message: 'No stock items available in Main Store',
          );
        }
        
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: const Icon(Icons.inventory_2, color: Colors.green),
                title: Text(item['name'] ?? 'Unknown'),
                subtitle: Text(
                  'Stock: ${item['current_stock'] ?? 0} (${item['location_name'] ?? 'Unknown Location'})',
                ),
                trailing: Text(
                  item['min_stock'] != null ? 'Min: ${item['min_stock']}' : 'Min: N/A',
                  style: TextStyle(color: Colors.grey[600]),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class DirectStockEntryForm extends StatefulWidget {
  const DirectStockEntryForm({super.key});
  @override
  State<DirectStockEntryForm> createState() => _DirectStockEntryFormState();
}

class _DirectStockEntryFormState extends State<DirectStockEntryForm> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  final _dataService = DataService();

  String? _selectedStockItemId;
  String? _selectedLocationId;
  bool _isProcessingDirectEntry = false;
  String? _pendingDirectEntryRequestId;
  List<Map<String, dynamic>> _stockItems = [];
  List<Map<String, dynamic>> _locations = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final items = await _dataService.getStockItems();
      final locations = await _getLocations();
      setState(() {
        _stockItems = items;
        _locations = locations;
      });
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _loadData (Record): $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load data. Please check your connection and try again.',
          onRetry: () => setState(() {}),
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<List<Map<String, dynamic>>> _getLocations() async {
    try {
      final locations = await _dataService.getLocations();
      if (locations.isEmpty) {
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'No locations found. Please add locations first.',
          );
        }
        return [];
      }
      return locations;
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _getLocations: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load locations. Please try again.',
          stackTrace: stackTrace,
        );
      }
      return [];
    }
  }

  Future<void> _recordDirectEntry() async {
    if (_isProcessingDirectEntry) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStockItemId == null || _selectedLocationId == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please select item and location',
        );
      }
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final staffId = StaffAuthHelper.requireStaffProfileId(
      context,
      authService: authService,
      supabase: _dataService.supabase,
    );
    if (staffId == null) return;

    setState(() => _isProcessingDirectEntry = true);
    try {
      final quantity = int.parse(_quantityController.text);
      final stockItemId = _selectedStockItemId!;
      final notes = _notesController.text.trim().isNotEmpty
          ? 'Direct entry: ${_notesController.text.trim()}'
          : 'Direct stock entry';

      _pendingDirectEntryRequestId ??= const Uuid().v4();
      final applied = await _dataService.recordDirectStockEntry(
        clientRequestId: _pendingDirectEntryRequestId!,
        stockItemId: stockItemId,
        locationId: _selectedLocationId!,
        staffProfileId: staffId,
        quantity: quantity,
        notes: notes,
      );

      if (!applied) {
        if (mounted) {
          ErrorHandler.showInfoMessage(
            context,
            'This delivery was already saved to the ledger (duplicate ignored).',
          );
          ErrorHandler.showLedgerConfirmedSnackBar(
            context,
            'Ledger already had this entry — no duplicate.',
          );
        }
        _pendingDirectEntryRequestId = null;
        return;
      }

      _pendingDirectEntryRequestId = null;

      if (mounted) {
        ErrorHandler.showLedgerConfirmedSnackBar(
          context,
          'Stock ledger saved. Safe to leave this screen.',
        );
        ErrorHandler.showSuccessMessage(
          context,
          'Stock recorded successfully!',
        );
        _formKey.currentState?.reset();
        _quantityController.clear();
        _notesController.clear();
        setState(() {
          _selectedStockItemId = null;
          _selectedLocationId = null;
        });
        await _loadData();
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _recordDirectEntry: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to record stock. Please try again.',
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingDirectEntry = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text('Use this form to record stock that did not come from a purchaser (e.g., direct delivery from management).', style: TextStyle(color: Colors.grey)),
          const SizedBox(height: 16),
          _stockItems.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  key: ValueKey<String?>(_selectedStockItemId),
                  initialValue: _selectedStockItemId,
                  decoration: const InputDecoration(labelText: 'Stock Item', border: OutlineInputBorder()),
                  items: _stockItems.map((item) => DropdownMenuItem<String>(
                    value: item['id']?.toString(),
                    child: Text(item['name']?.toString() ?? 'Unknown'),
                  )).toList(),
                  onChanged: (val) => setState(() {
                    _selectedStockItemId = val;
                    _pendingDirectEntryRequestId = null;
                  }),
                  validator: (val) => val == null ? 'Please select an item' : null,
                ),
          const SizedBox(height: 16),
          _locations.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  key: ValueKey<String?>(_selectedLocationId),
                  initialValue: _selectedLocationId,
                  decoration: const InputDecoration(labelText: 'Receiving Location', border: OutlineInputBorder()),
                  items: _locations.map((loc) => DropdownMenuItem<String>(
                    value: loc['id']?.toString(),
                    child: Text(loc['name']?.toString() ?? 'Unknown'),
                  )).toList(),
                  onChanged: (val) => setState(() {
                    _selectedLocationId = val;
                    _pendingDirectEntryRequestId = null;
                  }),
                  validator: (val) => val == null ? 'Please select a location' : null,
                ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _quantityController,
            decoration: const InputDecoration(labelText: 'Quantity Received', border: OutlineInputBorder()),
            keyboardType: TextInputType.number,
            validator: (val) => (val == null || val.isEmpty || int.tryParse(val) == null || int.parse(val) <= 0) ? 'Enter a valid quantity' : null,
            ),
            const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes (Optional)', hintText: 'e.g., Delivered by manager', border: OutlineInputBorder()),
            ),
            const SizedBox(height: 24),
          _isProcessingDirectEntry
              ? const Center(child: CircularProgressIndicator())
              : ElevatedButton(
                  onPressed: _isProcessingDirectEntry ? null : _recordDirectEntry,
                  style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                  child: const Text('Add to Stock Ledger'),
                ),
        ],
      ),
    );
  }
}

class StockTransferForm extends StatefulWidget {
  const StockTransferForm({super.key});
  @override
  State<StockTransferForm> createState() => _StockTransferFormState();
}

class _StockTransferFormState extends State<StockTransferForm> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _notesController = TextEditingController();
  final _dataService = DataService();

  String? _selectedStockItemId;
  String? _sourceLocationId;
  String? _destinationLocationId;
  String? _selectedRecipientId;
  bool _isProcessingTransfer = false;
  String? _pendingStockTransferRequestId;

  List<Map<String, dynamic>> _stockItems = [];
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _staffProfiles = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final items = await _dataService.getStockItems();
      final locations = await _dataService.getLocations();
      final staff = await _dataService.getStaffProfiles();

      setState(() {
        _stockItems = items;
        _locations = locations;
        _staffProfiles = staff;
        _sourceLocationId = _defaultMainStoreLocationId();
      });
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _loadData (Transfer): $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load transfer data. Please try again.',
          onRetry: _loadData,
          stackTrace: stackTrace,
        );
      }
    }
  }

  String? _defaultMainStoreLocationId() {
    if (_locations.isEmpty) return null;
    final match = _locations.firstWhere(
      (loc) {
        final name = (loc['name'] ?? '').toString().toLowerCase();
        return name.contains('main') || name.contains('store');
      },
      orElse: () => <String, dynamic>{},
    );
    if (match.isEmpty) return _locations.isNotEmpty ? _locations.first['id']?.toString() : null;
    return match['id']?.toString();
  }

  List<Map<String, dynamic>> _eligibleRecipients() {
    if (_destinationLocationId == null) return [];
    final destination = _locations.firstWhere(
      (loc) => loc['id']?.toString() == _destinationLocationId,
      orElse: () => <String, dynamic>{},
    );
    final locationName = (destination['name'] ?? '').toString();
    final roleFilters = _rolesForLocation(locationName);

    if (roleFilters.isEmpty) return _staffProfiles;

    return _staffProfiles.where((profile) {
      final roles = (profile['roles'] as List?)?.map((r) => r.toString()).toList() ?? [];
      return roles.any((r) => roleFilters.contains(r));
    }).toList();
  }

  List<String> _rolesForLocation(String locationName) {
    final name = locationName.toLowerCase();
    if (name.contains('vip')) return ['vip_bartender'];
    if (name.contains('outside') || name.contains('bar')) {
      return ['outside_bartender'];
    }
    if (name.contains('kitchen')) return ['kitchen_staff'];
    if (name.contains('laundry')) return ['laundry_attendant'];
    if (name.contains('housekeeping')) return ['housekeeper', 'cleaner'];
    if (name.contains('reception') || name.contains('front')) return ['receptionist'];
    if (name.contains('mini')) return ['receptionist'];
    return [];
  }

  Future<void> _submitTransfer() async {
    if (_isProcessingTransfer) return;
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStockItemId == null ||
        _sourceLocationId == null ||
        _destinationLocationId == null ||
        _selectedRecipientId == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please select item, source, destination, and recipient',
        );
      }
      return;
    }

    final authService = Provider.of<AuthService>(context, listen: false);
    final issuedById = StaffAuthHelper.requireStaffProfileId(
      context,
      authService: authService,
      supabase: _dataService.supabase,
    );
    if (issuedById == null) return;

    setState(() => _isProcessingTransfer = true);
    try {
      final quantity = int.parse(_quantityController.text.trim());

      _pendingStockTransferRequestId ??= const Uuid().v4();
      final transferRowId = await _dataService.createStockTransfer(
        stockItemId: _selectedStockItemId!,
        sourceLocationId: _sourceLocationId!,
        destinationLocationId: _destinationLocationId!,
        quantity: quantity,
        issuedById: issuedById,
        receivedById: _selectedRecipientId!,
        notes: _notesController.text.trim().isEmpty ? null : _notesController.text.trim(),
        clientRequestId: _pendingStockTransferRequestId,
      );

      if (transferRowId == null) {
        if (mounted) {
          ErrorHandler.showInfoMessage(
            context,
            'This transfer was already recorded (duplicate request ignored).',
          );
          ErrorHandler.showLedgerConfirmedSnackBar(
            context,
            'Transfer already on ledger — no duplicate.',
          );
        }
        _pendingStockTransferRequestId = null;
        return;
      }

      _pendingStockTransferRequestId = null;

      if (mounted) {
        ErrorHandler.showLedgerConfirmedSnackBar(
          context,
          'Transfer saved to ledger. Safe to continue.',
        );
        ErrorHandler.showSuccessMessage(context, 'Stock transferred successfully!');
        _formKey.currentState?.reset();
        _quantityController.clear();
        _notesController.clear();
        setState(() {
          _selectedStockItemId = null;
          _destinationLocationId = null;
          _selectedRecipientId = null;
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _submitTransfer: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to transfer stock. Please try again.',
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) setState(() => _isProcessingTransfer = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final recipients = _eligibleRecipients();

    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16.0),
        children: [
          const Text(
            'Use this form to issue stock from the main store to a department and record who received it.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 16),
          _stockItems.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  key: ValueKey<String?>(_selectedStockItemId),
                  initialValue: _selectedStockItemId,
                  decoration: const InputDecoration(labelText: 'Stock Item', border: OutlineInputBorder()),
                  items: _stockItems.map((item) => DropdownMenuItem<String>(
                    value: item['id']?.toString(),
                    child: Text(item['name']?.toString() ?? 'Unknown'),
                  )).toList(),
                  onChanged: (val) => setState(() {
                    _selectedStockItemId = val;
                    _pendingStockTransferRequestId = null;
                  }),
                  validator: (val) => val == null ? 'Please select an item' : null,
                ),
          const SizedBox(height: 16),
          _locations.isEmpty
              ? const Center(child: CircularProgressIndicator())
              : DropdownButtonFormField<String>(
                  key: ValueKey<String?>(_sourceLocationId),
                  initialValue: _sourceLocationId,
                  decoration: const InputDecoration(labelText: 'Source Location', border: OutlineInputBorder()),
                  items: _locations.map((loc) => DropdownMenuItem<String>(
                    value: loc['id']?.toString(),
                    child: Text(loc['name']?.toString() ?? 'Unknown'),
                  )).toList(),
                  onChanged: (val) => setState(() {
                    _sourceLocationId = val;
                    _pendingStockTransferRequestId = null;
                  }),
                  validator: (val) => val == null ? 'Please select a source location' : null,
                ),
          const SizedBox(height: 16),
          _locations.isEmpty
              ? const SizedBox.shrink()
              : DropdownButtonFormField<String>(
                  key: ValueKey<String>('${_sourceLocationId}_$_destinationLocationId'),
                  initialValue: _destinationLocationId,
                  decoration: const InputDecoration(labelText: 'Destination Location', border: OutlineInputBorder()),
                  items: _locations
                      .where((loc) => loc['id']?.toString() != _sourceLocationId)
                      .map((loc) => DropdownMenuItem<String>(
                            value: loc['id']?.toString(),
                            child: Text(loc['name']?.toString() ?? 'Unknown'),
                          ))
                      .toList(),
                  onChanged: (val) => setState(() {
                    _destinationLocationId = val;
                    _selectedRecipientId = null;
                    _pendingStockTransferRequestId = null;
                  }),
                  validator: (val) => val == null ? 'Please select a destination location' : null,
                ),
          const SizedBox(height: 16),
          recipients.isEmpty
              ? const Text('No eligible staff found for selected location.')
              : DropdownButtonFormField<String>(
                  key: ValueKey<String?>(_selectedRecipientId),
                  initialValue: _selectedRecipientId,
                  decoration: const InputDecoration(labelText: 'Recipient Staff', border: OutlineInputBorder()),
                  items: recipients.map((staff) => DropdownMenuItem<String>(
                    value: staff['id']?.toString(),
                    child: Text(staff['full_name']?.toString() ?? 'Unknown'),
                  )).toList(),
                  onChanged: (val) => setState(() {
                    _selectedRecipientId = val;
                    _pendingStockTransferRequestId = null;
                  }),
                  validator: (val) => val == null ? 'Please select a recipient' : null,
                ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _quantityController,
            decoration: const InputDecoration(labelText: 'Quantity', border: OutlineInputBorder()),
            keyboardType: TextInputType.number,
            validator: (val) {
              if (val == null || val.trim().isEmpty) return 'Please enter quantity';
              final qty = int.tryParse(val.trim()) ?? 0;
              if (qty <= 0) return 'Quantity must be greater than 0';
              return null;
            },
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _notesController,
            decoration: const InputDecoration(labelText: 'Notes (Optional)', border: OutlineInputBorder()),
            maxLines: 2,
          ),
          const SizedBox(height: 24),
          _isProcessingTransfer
              ? const Center(child: CircularProgressIndicator())
              : SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _isProcessingTransfer ? null : _submitTransfer,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Record Transfer'),
                  ),
                ),
        ],
      ),
    );
  }
}

class WastageManagementTab extends StatefulWidget {
  const WastageManagementTab({super.key});

  @override
  State<WastageManagementTab> createState() => _WastageManagementTabState();
}

class _WastageManagementTabState extends State<WastageManagementTab> {
  final DataService _dataService = DataService();
  List<Map<String, dynamic>> _wastageRequests = [];
  Map<String, dynamic> _analytics = {};
  bool _isLoading = true;
  String _selectedStatusFilter = 'pending';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final requests = await _dataService.getWastageRequests(status: _selectedStatusFilter);
      final analytics = await _dataService.getWastageAnalytics();
      setState(() {
        _wastageRequests = requests;
        _analytics = analytics;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to load wastage data');
      }
    }
  }

  Future<void> _approveRequest(String requestId) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final approvedBy = authService.currentUser?.id;
    if (approvedBy == null) return;

    try {
      await _dataService.approveWastageRequest(requestId, approvedBy);
      if (!mounted) return;
      ErrorHandler.showSuccessMessage(context, 'Wastage request approved');
      _loadData();
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to approve request');
      }
    }
  }

  Future<void> _rejectRequest(String requestId) async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final approvedBy = authService.currentUser?.id;
    if (approvedBy == null) return;

    try {
      await _dataService.rejectWastageRequest(requestId, approvedBy);
      if (!mounted) return;
      ErrorHandler.showSuccessMessage(context, 'Wastage request rejected');
      _loadData();
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to reject request');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Report Wastage Button
        Padding(
          padding: const EdgeInsets.all(16),
          child: SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _showReportWastageDialog,
              icon: const Icon(Icons.report_problem),
              label: const Text('Report Wastage'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Summary Cards
                Row(
                  children: [
                    Expanded(
                      child: _buildSummaryCard(
                        'Pending Approvals',
                        '${_analytics['pending_count'] ?? 0}',
                        Icons.pending_actions,
                        Colors.orange,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildSummaryCard(
                        'Total This Month',
                        _calculateTotalQuantity(),
                        Icons.delete_outline,
                        Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Status Filter
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(value: 'pending', label: Text('Pending')),
                    ButtonSegment(value: 'approved', label: Text('Approved')),
                    ButtonSegment(value: 'rejected', label: Text('Rejected')),
                  ],
                  selected: {_selectedStatusFilter},
                  onSelectionChanged: (Set<String> newSelection) {
                    setState(() => _selectedStatusFilter = newSelection.first);
                    _loadData();
                  },
                ),
                const SizedBox(height: 16),

                // Wastage Requests List
                _wastageRequests.isEmpty
                    ? const Center(
                        child: Padding(
                          padding: EdgeInsets.all(32),
                          child: Text('No wastage requests found'),
                        ),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _wastageRequests.length,
                        itemBuilder: (context, index) {
                          final request = _wastageRequests[index];
                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: ListTile(
                              title: Text(
                                request['stock_items']?['name']?.toString() ?? 'Unknown Item',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Quantity: ${request['quantity']}'),
                                  Text('Reason: ${request['reason_type']?.toString() ?? 'N/A'}'),
                                  Text(
                                    'Location: ${request['locations']?['name']?.toString() ?? 'N/A'}',
                                  ),
                                  Text(
                                    'Requested by: ${request['requested_by_profile']?['full_name']?.toString() ?? 'Unknown'}',
                                  ),
                                  if (request['notes'] != null && request['notes'].toString().isNotEmpty)
                                    Text('Notes: ${request['notes']}'),
                                ],
                              ),
                              trailing: request['status'] == 'pending'
                                  ? Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.check, color: Colors.green),
                                          onPressed: () => _approveRequest(request['id'].toString()),
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.close, color: Colors.red),
                                          onPressed: () => _rejectRequest(request['id'].toString()),
                                        ),
                                      ],
                                    )
                                  : Icon(
                                      request['status'] == 'approved' ? Icons.check_circle : Icons.cancel,
                                      color: request['status'] == 'approved' ? Colors.green : Colors.red,
                                    ),
                            ),
                          );
                        },
                      ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 24),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _calculateTotalQuantity() {
    int total = 0;
    for (var item in _analytics['by_department'] ?? []) {
      total += (item['quantity'] as num?)?.toInt() ?? 0;
    }
    return total.toString();
  }

  Future<void> _showReportWastageDialog() async {
    final itemController = TextEditingController();
    final quantityController = TextEditingController();
    final notesController = TextEditingController();
    String? selectedItemId;
    String? selectedLocationId;
    String? selectedReason;
    bool isLoading = false;
    List<Map<String, dynamic>> stockItems = [];
    List<Map<String, dynamic>> locations = [];

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogCtx, setDialogState) {
          Future<void> loadData() async {
            setDialogState(() => isLoading = true);
            try {
              stockItems = await _dataService.getStockItems();
              locations = await _dataService.getLocations();
            } catch (e) {
              if (mounted) {
                ErrorHandler.handleError(dialogContext, e, customMessage: 'Failed to load data');
              }
            } finally {
              setDialogState(() => isLoading = false);
            }
          }

          loadData();

          return AlertDialog(
            title: const Text('Report Wastage'),
            content: SizedBox(
              width: 500,
              child: isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Item *',
                              border: OutlineInputBorder(),
                            ),
                            items: stockItems.map((item) => DropdownMenuItem<String>(
                              value: item['id']?.toString(),
                              child: Text(item['name']?.toString() ?? 'Unknown'),
                            )).toList(),
                            onChanged: (val) => setDialogState(() => selectedItemId = val),
                            validator: (val) => val == null ? 'Please select an item' : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Location *',
                              border: OutlineInputBorder(),
                            ),
                            items: locations.map((loc) => DropdownMenuItem<String>(
                              value: loc['id']?.toString(),
                              child: Text(loc['name']?.toString() ?? 'Unknown'),
                            )).toList(),
                            onChanged: (val) => setDialogState(() => selectedLocationId = val),
                            validator: (val) => val == null ? 'Please select a location' : null,
                          ),
                          const SizedBox(height: 16),
                          DropdownButtonFormField<String>(
                            decoration: const InputDecoration(
                              labelText: 'Reason *',
                              border: OutlineInputBorder(),
                            ),
                            items: const [
                              DropdownMenuItem(value: 'spoilt', child: Text('Spoilt')),
                              DropdownMenuItem(value: 'trashed', child: Text('Trashed')),
                              DropdownMenuItem(value: 'destroyed', child: Text('Destroyed')),
                              DropdownMenuItem(value: 'expired', child: Text('Expired')),
                            ],
                            onChanged: (val) => setDialogState(() => selectedReason = val),
                            validator: (val) => val == null ? 'Please select a reason' : null,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: quantityController,
                            decoration: const InputDecoration(
                              labelText: 'Quantity *',
                              border: OutlineInputBorder(),
                            ),
                            keyboardType: TextInputType.number,
                            validator: (val) {
                              if (val == null || val.trim().isEmpty) return 'Please enter quantity';
                              final qty = int.tryParse(val.trim()) ?? 0;
                              if (qty <= 0) return 'Quantity must be greater than 0';
                              return null;
                            },
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: notesController,
                            decoration: const InputDecoration(
                              labelText: 'Notes (Optional)',
                              border: OutlineInputBorder(),
                            ),
                            maxLines: 3,
                          ),
                        ],
                      ),
                    ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (selectedItemId == null || selectedLocationId == null || selectedReason == null) {
                    return;
                  }
                  final quantity = int.tryParse(quantityController.text.trim()) ?? 0;
                  if (quantity <= 0) return;

                  setDialogState(() => isLoading = true);
                  try {
                    final authService = Provider.of<AuthService>(context, listen: false);
                    final requestedBy = authService.currentUser?.id;
                    if (requestedBy == null) return;

                    await _dataService.createWastageRequest(
                      stockItemId: selectedItemId!,
                      locationId: selectedLocationId!,
                      quantity: quantity,
                      reasonType: selectedReason!,
                      notes: notesController.text.trim().isEmpty ? null : notesController.text.trim(),
                      requestedBy: requestedBy,
                    );

                    if (!mounted) return;
                    Navigator.pop(dialogContext);
                    ErrorHandler.showSuccessMessage(context, 'Wastage request submitted');
                    _loadData();
                  } catch (e) {
                    setDialogState(() => isLoading = false);
                    if (mounted) {
                      ErrorHandler.handleError(context, e, customMessage: 'Failed to submit request');
                    }
                  }
                },
                child: const Text('Submit'),
              ),
            ],
          );
        },
      ),
    );
  }
}