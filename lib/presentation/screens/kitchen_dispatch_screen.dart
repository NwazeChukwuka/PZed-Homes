import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:pzed_homes/presentation/widgets/scrollable_list_with_arrows.dart';
import 'package:pzed_homes/core/services/payment_service.dart';

class KitchenDispatchScreen extends StatefulWidget {
  const KitchenDispatchScreen({super.key});

  @override
  State<KitchenDispatchScreen> createState() => _KitchenDispatchScreenState();
}

class _KitchenDispatchScreenState extends State<KitchenDispatchScreen> with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _saleFormKey = GlobalKey<FormState>();
  final _dataService = DataService();
  SupabaseClient _requireSupabase() {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw Exception('Supabase not initialized');
    }
  }
  final _quantityController = TextEditingController();
  final _dispatchUnitPriceController = TextEditingController();
  final _saleQuantityController = TextEditingController();
  final _saleUnitPriceController = TextEditingController();
  final _saleCustomNameController = TextEditingController();
  final _saleCreditCustomerNameController = TextEditingController();
  final _saleCreditCustomerPhoneController = TextEditingController();
  final _searchController = TextEditingController();
  final ScrollController _currentSaleScrollController = ScrollController();
  int? _selectedSaleQuantity = 1; // Default quantity for kitchen sales
  Timer? _filterDebounce;

  List<Map<String, dynamic>> _stockItems = [];
  List<Map<String, dynamic>> _filteredItems = [];
  List<Map<String, dynamic>> _currentSale = [];
  double _saleTotal = 0.0;
  List<Map<String, dynamic>> _locations = [];
  List<Map<String, dynamic>> _departments = [];
  List<String> _missingStockLinks = [];
  Set<String> _dismissedWarnings = {};
  List<Map<String, dynamic>> _dispatchHistory = [];
  List<Map<String, dynamic>> _salesHistory = [];
  List<Map<String, dynamic>> _bookings = [];
  String? _selectedStockItemId;
  String? _selectedDestinationDepartment;
  String? _selectedDispatchBookingId;
  String? _sourceLocationId; // Kitchen location id
  bool _isLoading = false;
  bool _isCustomSale = false;
  String? _selectedSaleItemId;
  String? _selectedBookingId;
  bool _chargeToRoom = false;
  String _dispatchPaymentMethod = 'cash';
  String _dispatchPaymentStatus = 'paid';
  String _salePaymentMethod = 'cash';
  String _salesFilterPaymentMethod = 'all';
  DateTimeRange? _salesFilterRange;
  String _dispatchFilterPaymentStatus = 'all';
  DateTimeRange? _dispatchFilterRange;
  String _dispatchFilterDepartment = 'all';
  String _dispatchFilterStaffId = 'all';
  String _historyFilterType = 'all'; // 'all', 'Sale', 'Dispatch'

  // Memoized: invalidate when _salesHistory/_dispatchHistory or filter params change
  bool _filteredCachesDirty = true;
  List<Map<String, dynamic>>? _cachedFilteredSalesHistory;
  List<Map<String, dynamic>>? _cachedFilteredDispatchHistory;
  DateTimeRange? _historyFilterRange;
  String _historyFilterStaffId = 'all';
  late TabController _tabController;
  bool _hasPerformedInitialLoad = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _searchController.addListener(_onSearchChanged);
  }

  void _onSearchChanged() {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _filterItems();
    });
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _stockItems.where((item) {
        return item['name']?.toString().toLowerCase().contains(query) ?? false;
      }).toList();
    });
  }

  void _addItemToSale(Map<String, dynamic> item) {
    final priceKobo = (item['price'] as num?)?.toInt() ?? 0;
    final priceNaira = PaymentService.koboToNaira(priceKobo);
    var addedNewItem = false;
    final existingIndex = _currentSale.indexWhere((s) => s['id'] == item['id']);
    setState(() {
      if (existingIndex != -1) {
        _currentSale[existingIndex]['quantity'] =
            (_currentSale[existingIndex]['quantity'] ?? 0) + 1;
      } else {
        _currentSale.add({
          'id': item['id'],
          'name': item['name'] ?? 'Item',
          'price': priceNaira,
          'stock_item_id': item['stock_item_id'],
          'quantity': 1,
        });
        addedNewItem = true;
      }
      _saleTotal = _currentSale.fold(
        0.0,
        (sum, s) => sum + ((s['price'] as num).toDouble() * ((s['quantity'] as int?) ?? 1)),
      );
    });
    if (addedNewItem) _scrollCurrentSaleToEnd();
  }

  void _addCustomItemToSale() {
    final name = _saleCustomNameController.text.trim();
    if (name.isEmpty) return;
    final priceNaira = double.tryParse(_saleUnitPriceController.text.trim()) ?? 0;
    if (priceNaira <= 0) return;
    setState(() {
      _currentSale.add({
        'id': null,
        'name': name,
        'price': priceNaira,
        'stock_item_id': null,
        'quantity': 1,
      });
      _saleTotal = _currentSale.fold(
        0.0,
        (sum, s) => sum + ((s['price'] as num).toDouble() * ((s['quantity'] as int?) ?? 1)),
      );
      _saleCustomNameController.clear();
      _saleUnitPriceController.clear();
    });
    _scrollCurrentSaleToEnd();
  }

  void _scrollCurrentSaleToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_currentSaleScrollController.hasClients) {
        final pos = _currentSaleScrollController.position;
        _currentSaleScrollController.animateTo(
          pos.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _removeItemFromSale(int index) {
    setState(() {
      _currentSale.removeAt(index);
      _saleTotal = _currentSale.fold(
        0.0,
        (sum, s) => sum + ((s['price'] as num).toDouble() * ((s['quantity'] as int?) ?? 1)),
      );
    });
  }

  void _clearSale() {
    setState(() {
      _currentSale.clear();
      _saleTotal = 0.0;
      _selectedBookingId = null;
      _chargeToRoom = false;
      _saleCustomNameController.clear();
      _saleUnitPriceController.clear();
      _saleCreditCustomerNameController.clear();
      _saleCreditCustomerPhoneController.clear();
    });
  }

  Widget _buildKitchenSalesGrid() {
    return Expanded(
      flex: 2,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Search items...',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : LayoutBuilder(
                      builder: (context, constraints) {
                        final width = MediaQuery.sizeOf(context).width;
                        final crossAxisCount = width < 600 ? 2 : (width < 1000 ? 4 : 6);
                        final childAspectRatio = width < 600 ? 0.85 : (width < 1000 ? 0.9 : 0.95);
                        return GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            childAspectRatio: childAspectRatio,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                          ),
                          itemCount: _filteredItems.length,
                      itemBuilder: (context, index) {
                        final item = _filteredItems[index];
                        final priceKobo = (item['price'] as num?)?.toInt() ?? 0;
                        final priceNaira = PaymentService.koboToNaira(priceKobo);
                        final hasStockLink = item['stock_item_id'] != null;
                        return Card(
                          elevation: 2,
                          child: InkWell(
                            onTap: () => _addItemToSale(item),
                            child: Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: hasStockLink ? Colors.white : Colors.orange[50],
                                borderRadius: BorderRadius.circular(8),
                                border: hasStockLink ? null : Border.all(color: Colors.orange[300]!, width: 1),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SizedBox(
                                    height: 28,
                                    width: double.infinity,
                                    child: Container(
                                      decoration: BoxDecoration(
                                        color: Colors.grey[200],
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Icon(Icons.restaurant, size: 18),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    item['name']?.toString() ?? 'Unknown',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w500,
                                      fontSize: 11,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '₦${NumberFormat('#,##0.00').format(priceNaira)}',
                                    style: TextStyle(
                                      color: Colors.green[700],
                                      fontWeight: FontWeight.bold,
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    );
                      },
                    ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('Custom Order (not on menu)', style: TextStyle(fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _saleCustomNameController,
                          decoration: const InputDecoration(
                            hintText: 'Item name',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _saleUnitPriceController,
                          decoration: const InputDecoration(
                            hintText: 'Price (₦)',
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          ),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.add_circle),
                        color: Colors.orange,
                        onPressed: _addCustomItemToSale,
                        tooltip: 'Add custom item',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKitchenCurrentSaleSection() {
    return Expanded(
      flex: 1,
      child: Container(
      margin: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Current Sale', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ),
          Expanded(
            child: _currentSale.isEmpty
                ? const Center(child: Text('Tap items to add', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    controller: _currentSaleScrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: _currentSale.length,
                    itemBuilder: (context, index) {
                      final item = _currentSale[index];
                      final name = item['name'] as String? ?? 'Item';
                      final price = (item['price'] as num).toDouble();
                      final qty = item['quantity'] as int? ?? 1;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(name),
                          subtitle: Text('₦${NumberFormat('#,##0.00').format(price)} × $qty'),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '₦${NumberFormat('#,##0.00').format(price * qty)}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline, size: 20),
                                onPressed: () => _removeItemFromSale(index),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: _salePaymentMethod,
                  decoration: const InputDecoration(
                    labelText: 'Payment Method',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'cash', child: Text('Cash')),
                    DropdownMenuItem(value: 'card', child: Text('Card')),
                    DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                    DropdownMenuItem(value: 'credit', child: Text('Credit (Pay Later)')),
                  ],
                  onChanged: (val) => setState(() => _salePaymentMethod = val ?? 'cash'),
                ),
                if (_salePaymentMethod == 'credit' && !_chargeToRoom) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _saleCreditCustomerNameController,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'Customer Name *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _saleCreditCustomerPhoneController,
                    textInputAction: TextInputAction.done,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'Phone *',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Charge to Room'),
                  value: _chargeToRoom,
                  onChanged: (val) {
                    setState(() {
                      _chargeToRoom = val;
                      if (!val) _selectedBookingId = null;
                    });
                  },
                ),
                if (_chargeToRoom) ...[
                  const SizedBox(height: 4),
                  DropdownButtonFormField<String>(
                    value: _selectedBookingId,
                    decoration: const InputDecoration(
                      labelText: 'Booking',
                      border: OutlineInputBorder(),
                    ),
                    items: _bookings
                        .map((booking) {
                          final guestName = booking['guest_name'] as String? ??
                              (booking['profiles'] as Map<String, dynamic>?)?['full_name'] as String? ??
                              'Guest';
                          final roomNumber = (booking['rooms'] as Map<String, dynamic>?)
                                  ?['room_number']
                                  ?.toString() ??
                              booking['requested_room_type']?.toString() ??
                              'Room';
                          return DropdownMenuItem(
                            value: booking['id'] as String,
                            child: Text('$guestName • $roomNumber'),
                          );
                        })
                        .toList(),
                    onChanged: (val) => setState(() => _selectedBookingId = val),
                  ),
                ],
                const SizedBox(height: 16),
                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton.icon(
                        onPressed: _currentSale.isEmpty ? null : _recordKitchenSale,
                        icon: const Icon(Icons.point_of_sale),
                        label: const Text('Record Sale'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange.shade800,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                        ),
                      ),
                if (_currentSale.isNotEmpty)
                  TextButton(
                    onPressed: _clearSale,
                    child: const Text('Clear Sale'),
                  ),
              ],
            ),
          ),
        ],
      ),
    ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Run load once to avoid duplicate I/O when dependencies change (e.g. theme, locale)
    if (_hasPerformedInitialLoad) return;
    _hasPerformedInitialLoad = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAccessAndLoad();
    });
  }

  Future<void> _checkAccessAndLoad() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isKitchenStaff = (user?.roles.any((r) => r == AppRole.kitchen_staff) ?? false);
    final isAssumedKitchenStaff = authService.hasAssumedRole(AppRole.kitchen_staff);
    final isOwnerOrManager = user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
    final isReceptionist = (user?.roles.any((r) => r == AppRole.receptionist) ?? false);
    final isVipBartender = (user?.roles.any((r) => r == AppRole.vip_bartender) ?? false);
    
    // Owner/Manager/Receptionist/VIP Bartender can view dispatches without assuming role
    // But need to assume role for full functionality
    final canAccess = isKitchenStaff || isAssumedKitchenStaff || isOwnerOrManager || isReceptionist || isVipBartender;

    if (!canAccess) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Access restricted.',
          );
          Future.delayed(const Duration(milliseconds: 150), () {
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
      final menuItems = await _dataService.getMenuItems();
      final stockResponse = menuItems
          .where((item) => (item['department']?.toString().toLowerCase() ?? '') == 'restaurant')
          .toList();
      final locResponse = await _dataService.getLocations();
      final deptResponse = await _dataService.getDepartments();
      final dispatchHistory = await _dataService.getDepartmentTransfers(limit: 1000);
      final salesHistory = await _dataService.getKitchenSalesHistory(limit: 1000);
      final allBookings = await _dataService.getBookings();
      if (!mounted) return;

      if (locResponse.isEmpty) {
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'No locations found. Please add locations first.',
          );
        }
      }

      final activeDepartments = deptResponse
          .where((d) => (d['name'] as String?)?.toLowerCase() != 'restaurant')
          .toList();
      final filteredDispatchHistory = dispatchHistory.where((t) {
        final source = t['source_department']?.toString().toLowerCase();
        return source == 'restaurant' || source == 'kitchen';
      }).toList();
      final checkedInBookings = allBookings.where((b) {
        final status = _normalizeStatus(b['status']?.toString());
        return status == 'checked-in';
      }).toList();

      setState(() {
        _stockItems = List<Map<String, dynamic>>.from(stockResponse);
        _filteredItems = List<Map<String, dynamic>>.from(stockResponse);
        _locations = List<Map<String, dynamic>>.from(locResponse);
        _departments = List<Map<String, dynamic>>.from(activeDepartments);
        _dispatchHistory = List<Map<String, dynamic>>.from(filteredDispatchHistory);
        _salesHistory = List<Map<String, dynamic>>.from(salesHistory);
        _invalidateFilteredCaches();
        _bookings = List<Map<String, dynamic>>.from(checkedInBookings);
        _missingStockLinks = stockResponse
            .where((item) => item['stock_item_id'] == null)
            .map((item) => (item['name'] as String?) ?? 'Item')
            .toSet()
            .toList()
          ..sort();
      });

      // Find Kitchen location id
      final kitchen = _locations.firstWhere(
        (l) => (l['name'] as String).toLowerCase() == 'kitchen',
        orElse: () => <String, dynamic>{},
      );
      if (kitchen.isNotEmpty) {
        setState(() => _sourceLocationId = kitchen['id'] as String);
      } else {
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Warning: Kitchen location not found',
          );
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG load data: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load data. Please check your connection and try again.',
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _setDispatchPriceFromItem(String? itemId) {
    if (itemId == null) return;
    final selected = _stockItems.firstWhere(
      (s) => s['id'] == itemId,
      orElse: () => <String, dynamic>{},
    );
    if (selected.isEmpty) return;
    final priceInKobo = selected['price'] as int? ?? 0;
    final priceInNaira = PaymentService.koboToNaira(priceInKobo);
    _dispatchUnitPriceController.text = priceInNaira.toStringAsFixed(2);
  }

  void _setSalePriceFromItem(String? itemId) {
    if (itemId == null) return;
    final selected = _stockItems.firstWhere(
      (s) => s['id'] == itemId,
      orElse: () => <String, dynamic>{},
    );
    if (selected.isEmpty) return;
    final priceInKobo = selected['price'] as int? ?? 0;
    final priceInNaira = PaymentService.koboToNaira(priceInKobo);
    _saleUnitPriceController.text = priceInNaira.toStringAsFixed(2);
  }

  String _formatDepartmentName(String name) {
    if (name.isEmpty) return name;
    final words = name.split('_').map((w) {
      if (w.isEmpty) return w;
      return w[0].toUpperCase() + w.substring(1);
    }).toList();
    return words.join(' ');
  }

  String _normalizeStatus(String? raw) {
    if (raw == null) return '';
    return raw.trim().toLowerCase().replaceAll('_', '-');
  }

  Future<void> _recordDepartmentSale({
    required String department,
    required int amountInKobo,
    required String staffId,
    required String paymentMethod,
  }) async {
    final supabase = _requireSupabase();
    final today = DateTime.now().toIso8601String().split('T')[0];
    final paymentBreakdown = <String, int>{paymentMethod: amountInKobo};

    final existingSales = await supabase
        .from('department_sales')
        .select()
        .eq('department', department)
        .eq('date', today)
        .maybeSingle();

    if (existingSales != null) {
      final existingStaffId = existingSales['staff_id'] as String?;
      if (existingStaffId == null || existingStaffId == staffId) {
        final currentBreakdown =
            (existingSales['payment_method_breakdown'] as Map<String, dynamic>?) ??
                <String, dynamic>{};
        final updatedBreakdown = Map<String, dynamic>.from(currentBreakdown);
        final currentMethodTotal = (updatedBreakdown[paymentMethod] as int? ?? 0);
        updatedBreakdown[paymentMethod] = currentMethodTotal + amountInKobo;

        await supabase
            .from('department_sales')
            .update({
              'total_sales': (existingSales['total_sales'] as int) + amountInKobo,
              'transaction_count': (existingSales['transaction_count'] as int) + 1,
              'payment_method_breakdown': updatedBreakdown,
              'staff_id': staffId,
              'recorded_by': staffId,
            })
            .eq('id', existingSales['id']);
      } else {
        await supabase.from('department_sales').insert({
          'department': department,
          'date': today,
          'total_sales': amountInKobo,
          'transaction_count': 1,
          'payment_method_breakdown': paymentBreakdown,
          'recorded_by': staffId,
          'staff_id': staffId,
        });
      }
    } else {
      await supabase.from('department_sales').insert({
        'department': department,
        'date': today,
        'total_sales': amountInKobo,
        'transaction_count': 1,
        'payment_method_breakdown': paymentBreakdown,
        'recorded_by': staffId,
        'staff_id': staffId,
      });
    }
  }

  Future<void> _dispatchItem() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedStockItemId == null || _selectedDestinationDepartment == null) return;

    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final staffId = authService.currentUser!.id;
      final quantity = int.parse(_quantityController.text);
      final unitPriceNaira = double.tryParse(_dispatchUnitPriceController.text.trim()) ?? 0;

      if (_sourceLocationId == null) {
        throw Exception('Source location not configured');
      }

      // Optional local stock check for faster feedback
      final selected = _stockItems.firstWhere(
        (s) => s['id'] == _selectedStockItemId,
        orElse: () => <String, dynamic>{},
      );
      if (selected.isEmpty) throw Exception('Selected stock item not found');
      if (selected['stock_item_id'] == null) {
        throw Exception('This menu item is not linked to a stock item. Link it before dispatching.');
      }
      // Note: menu_items do not track per-location stock directly here.
      // Stock checks should be handled via stock_transactions/stock_levels if needed.

      final destinationDepartment = _selectedDestinationDepartment!;
      final isValidDepartment = _departments.any((d) => d['name'] == destinationDepartment);
      if (!isValidDepartment) {
        throw Exception('Destination department not found');
      }

      if (_dispatchPaymentStatus == 'unpaid' && _selectedDispatchBookingId == null) {
        throw Exception('Select a booking to charge to room');
      }

      final totalInKobo = PaymentService.nairaToKobo(unitPriceNaira) * quantity;
      final paymentStatus = _dispatchPaymentStatus;
      final bookingId = _selectedDispatchBookingId;
      final effectivePaymentMethod =
          paymentStatus == 'unpaid' ? 'credit' : _dispatchPaymentMethod;

      // Create department transfer
      final transferId = await _dataService.createDepartmentTransfer({
        'source_department': 'restaurant',
        'destination_department': destinationDepartment,
        'menu_item_id': _selectedStockItemId,
        'quantity': quantity,
        'dispatched_by_id': staffId,
        'status': 'Pending',
        'unit_price': PaymentService.nairaToKobo(unitPriceNaira),
        'total_amount': totalInKobo,
        'payment_method': effectivePaymentMethod,
        'payment_status': paymentStatus,
        'booking_id': bookingId,
      });

      if (totalInKobo > 0 && paymentStatus == 'paid') {
        await _recordDepartmentSale(
          department: destinationDepartment,
          amountInKobo: totalInKobo,
          staffId: staffId,
          paymentMethod: effectivePaymentMethod,
        );
      }

      if (paymentStatus == 'unpaid' && bookingId != null) {
        final booking = _bookings.firstWhere(
          (b) => b['id'] == bookingId,
          orElse: () => <String, dynamic>{},
        );
        final guestProfile = booking['profiles'] as Map<String, dynamic>?;
        final guestName = booking['guest_name'] as String? ??
            guestProfile?['full_name'] as String? ??
            'Guest';
        final guestPhone = booking['guest_phone'] as String? ??
            guestProfile?['phone'] as String? ??
            '';

        await _dataService.recordDebt({
          'debtor_name': guestName,
          'debtor_phone': guestPhone,
          'debtor_type': 'customer',
          'amount': totalInKobo,
          'owed_to': 'P-ZED Luxury Hotels & Suites',
          'department': 'reception',
          'source_department': 'restaurant',
          'source_type': 'kitchen_dispatch',
          'reference_id': transferId,
          'reason': 'Kitchen dispatch charged to room',
          'date': DateTime.now().toIso8601String().split('T')[0],
          'status': 'outstanding',
          'sold_by': staffId,
          'booking_id': bookingId,
          'sale_id': transferId,
        });

        await _dataService.addBookingCharge(
          bookingId: bookingId,
          itemName: selected['name'] as String? ?? 'Kitchen dispatch',
          priceKobo: PaymentService.nairaToKobo(unitPriceNaira),
          quantity: quantity,
          department: 'restaurant',
          addedBy: staffId,
        );
      }

      // Optional stock deduction when menu item is linked to stock item
      final stockItemId = selected['stock_item_id']?.toString();
      if (stockItemId != null && _sourceLocationId != null) {
        await _dataService.recordStockTransaction({
          'stock_item_id': stockItemId,
          'location_id': _sourceLocationId,
          'staff_profile_id': staffId,
          'transaction_type': 'Transfer_Out',
          'quantity': -quantity,
          'notes': 'Kitchen dispatch to $destinationDepartment',
        });
      }

      // Clear form and refresh
      _formKey.currentState?.reset();
      _quantityController.clear();
      _dispatchUnitPriceController.clear();
      setState(() {
        _selectedStockItemId = null;
        _selectedDestinationDepartment = null;
        _selectedDispatchBookingId = null;
        _dispatchPaymentStatus = 'paid';
        _dispatchPaymentMethod = 'cash';
      });
      
      if (mounted) {
        final selectedItemName = selected['name'] as String? ?? 'Item';
        String? guestName;
        if (bookingId != null) {
          final booking = _bookings.firstWhere(
            (b) => b['id'] == bookingId,
            orElse: () => <String, dynamic>{},
          );
          final guestProfile = booking['profiles'] as Map<String, dynamic>?;
          guestName = booking['guest_name'] as String? ??
              guestProfile?['full_name'] as String?;
        }

        await _showDispatchSlipDialog(
          itemName: selectedItemName,
          quantity: quantity,
          unitPriceNaira: unitPriceNaira,
          totalNaira: PaymentService.koboToNaira(totalInKobo),
          destinationDepartment: destinationDepartment,
          paymentMethod: effectivePaymentMethod,
          paymentStatus: paymentStatus,
          bookingId: bookingId,
          guestName: guestName,
        );
        ErrorHandler.showSuccessMessage(context, 'Item dispatched successfully!');
        await _loadStockAndLocations();
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG dispatch: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to dispatch item. Please try again.',
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _recordKitchenSale() async {
    if (_currentSale.isEmpty) return;
    if (_chargeToRoom && _selectedBookingId == null) {
      ErrorHandler.showWarningMessage(context, 'Select a booking to charge to room');
      return;
    }
    if (_salePaymentMethod == 'credit' && !_chargeToRoom) {
      final name = _saleCreditCustomerNameController.text.trim();
      final phone = _saleCreditCustomerPhoneController.text.trim();
      if (name.isEmpty || phone.isEmpty) {
        ErrorHandler.showWarningMessage(
          context,
          'Customer name and phone are required for credit sales.',
        );
        return;
      }
    }
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final staffId = authService.currentUser!.id;
      final effectivePaymentMethod = _chargeToRoom ? 'credit' : _salePaymentMethod;
      int totalSaleInKobo = 0;
      String? firstSaleId;

      for (final saleItem in _currentSale) {
        final itemName = saleItem['name'] as String? ?? 'Item';
        final quantity = saleItem['quantity'] as int? ?? 1;
        final unitPriceNaira = (saleItem['price'] as num).toDouble();
        final unitPriceKobo = PaymentService.nairaToKobo(unitPriceNaira);
        final itemTotalKobo = unitPriceKobo * quantity;

        if (saleItem['id'] != null) {
          final selected = _stockItems.firstWhere(
            (s) => s['id'] == saleItem['id'],
            orElse: () => <String, dynamic>{},
          );
          if (selected.isNotEmpty && selected['stock_item_id'] == null) {
            throw Exception('${selected['name']} is not linked to a stock item. Link it before selling.');
          }
        }

        final saleId = await _dataService.createKitchenSale({
          'menu_item_id': saleItem['id'],
          'item_name': itemName,
          'quantity': quantity,
          'unit_price': unitPriceKobo,
          'total_amount': itemTotalKobo,
          'payment_method': effectivePaymentMethod,
          'booking_id': _selectedBookingId,
          'sold_by': staffId,
        });
        if (firstSaleId == null) firstSaleId = saleId;
        totalSaleInKobo += itemTotalKobo;

        if (_chargeToRoom && _selectedBookingId != null) {
          await _dataService.addBookingCharge(
            bookingId: _selectedBookingId!,
            itemName: itemName,
            priceKobo: unitPriceKobo,
            quantity: quantity,
            department: 'restaurant',
            addedBy: staffId,
          );
        }

        final stockItemId = saleItem['stock_item_id']?.toString();
        if (stockItemId != null && _sourceLocationId != null) {
          await _dataService.recordStockTransaction({
            'stock_item_id': stockItemId,
            'location_id': _sourceLocationId,
            'staff_profile_id': staffId,
            'transaction_type': 'Sale',
            'quantity': -quantity,
            'notes': 'Kitchen sale',
          });
        }
      }

      final isWalkInCredit = _salePaymentMethod == 'credit' && !_chargeToRoom;

      if (!_chargeToRoom && !isWalkInCredit) {
        await _recordDepartmentSale(
          department: 'restaurant',
          amountInKobo: totalSaleInKobo,
          staffId: staffId,
          paymentMethod: effectivePaymentMethod,
        );
      }

      if (isWalkInCredit) {
        final customerName = _saleCreditCustomerNameController.text.trim();
        final customerPhone = _saleCreditCustomerPhoneController.text.trim();
        await _dataService.recordDebt({
          'debtor_name': customerName,
          'debtor_phone': customerPhone,
          'debtor_type': 'customer',
          'amount': totalSaleInKobo,
          'owed_to': 'P-ZED Luxury Hotels & Suites',
          'department': 'reception',
          'source_department': 'restaurant',
          'source_type': 'kitchen_sale',
          'reference_id': firstSaleId,
          'reason': 'Kitchen sale on credit (walk-in)',
          'date': DateTime.now().toIso8601String().split('T')[0],
          'status': 'outstanding',
          'sold_by': staffId,
          'sale_id': firstSaleId,
        });
      } else if (_chargeToRoom && _selectedBookingId != null) {
        final booking = _bookings.firstWhere(
          (b) => b['id'] == _selectedBookingId,
          orElse: () => <String, dynamic>{},
        );
        final guestProfile = booking['profiles'] as Map<String, dynamic>?;
        final guestName = booking['guest_name'] as String? ??
            guestProfile?['full_name'] as String? ??
            'Guest';
        final guestPhone = booking['guest_phone'] as String? ??
            guestProfile?['phone'] as String? ??
            '';

        await _dataService.recordDebt({
          'debtor_name': guestName,
          'debtor_phone': guestPhone,
          'debtor_type': 'customer',
          'amount': totalSaleInKobo,
          'owed_to': 'P-ZED Luxury Hotels & Suites',
          'department': 'reception',
          'source_department': 'restaurant',
          'source_type': 'kitchen_sale',
          'reference_id': firstSaleId,
          'reason': 'Kitchen sale charged to room',
          'date': DateTime.now().toIso8601String().split('T')[0],
          'status': 'outstanding',
          'sold_by': staffId,
          'booking_id': _selectedBookingId,
          'sale_id': firstSaleId,
        });
      }

      final firstItem = _currentSale.first;
      final firstItemName = firstItem['name'] as String? ?? 'Item';
      final firstQty = firstItem['quantity'] as int? ?? 1;
      final firstPrice = (firstItem['price'] as num).toDouble();
      final itemCount = _currentSale.length;
      final displayName = itemCount == 1
          ? firstItemName
          : '$firstItemName + ${itemCount - 1} more';
      final bookingIdForReceipt = _selectedBookingId;
      _clearSale();

      if (mounted) {
        await _showKitchenReceiptDialog(
          itemName: displayName,
          quantity: firstQty,
          unitPriceNaira: firstPrice,
          totalNaira: PaymentService.koboToNaira(totalSaleInKobo),
          paymentMethod: effectivePaymentMethod,
          bookingId: bookingIdForReceipt,
        );
        ErrorHandler.showSuccessMessage(
          context,
          isWalkInCredit
              ? 'Sale on credit recorded! Total: ₦${NumberFormat('#,##0.00').format(PaymentService.koboToNaira(totalSaleInKobo))} - Debt created'
              : 'Kitchen sale recorded successfully!',
        );
        // Reload stock and locations to refresh the food list with updated stock levels
        await _loadStockAndLocations();
        // Force UI rebuild to show updated stock
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG record sale: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to record sale. Please try again.',
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showKitchenReceiptDialog({
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String paymentMethod,
    String? bookingId,
  }) async {
    String? guestName;
    if (bookingId != null) {
      final booking = _bookings.firstWhere(
        (b) => b['id'] == bookingId,
        orElse: () => <String, dynamic>{},
      );
      final guestProfile = booking['profiles'] as Map<String, dynamic>?;
      guestName = booking['guest_name'] as String? ??
          guestProfile?['full_name'] as String?;
    }
    final receiptText = StringBuffer()
      ..writeln('P-ZED Homes Kitchen Receipt')
      ..writeln('Item: $itemName')
      ..writeln('Quantity: $quantity')
      ..writeln('Unit Price: ₦${NumberFormat('#,##0.00').format(unitPriceNaira)}')
      ..writeln('Total: ₦${NumberFormat('#,##0.00').format(totalNaira)}')
      ..writeln('Payment Method: $paymentMethod')
      ..writeln('Booking ID: ${bookingId ?? 'N/A'}')
      ..writeln('Guest: ${guestName ?? 'N/A'}')
      ..writeln('Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('Kitchen Receipt'),
          content: SingleChildScrollView(
            child: SelectableText(receiptText.toString()),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _saveKitchenReceiptPdf(
                  itemName: itemName,
                  quantity: quantity,
                  unitPriceNaira: unitPriceNaira,
                  totalNaira: totalNaira,
                  paymentMethod: paymentMethod,
                  bookingId: bookingId,
                  guestName: guestName,
                );
              },
              child: const Text('Save PDF'),
            ),
            TextButton(
              onPressed: () async {
                await _printKitchenReceipt(
                  itemName: itemName,
                  quantity: quantity,
                  unitPriceNaira: unitPriceNaira,
                  totalNaira: totalNaira,
                  paymentMethod: paymentMethod,
                  bookingId: bookingId,
                  guestName: guestName,
                );
              },
              child: const Text('Print/PDF'),
            ),
            TextButton(
              onPressed: () async {
                await _shareKitchenReceiptPdf(
                  itemName: itemName,
                  quantity: quantity,
                  unitPriceNaira: unitPriceNaira,
                  totalNaira: totalNaira,
                  paymentMethod: paymentMethod,
                  bookingId: bookingId,
                  guestName: guestName,
                );
              },
              child: const Text('Share PDF'),
            ),
            TextButton(
              onPressed: () async {
                await _emailKitchenReceiptPdf(
                  receiptText: receiptText.toString(),
                  itemName: itemName,
                  quantity: quantity,
                  unitPriceNaira: unitPriceNaira,
                  totalNaira: totalNaira,
                  paymentMethod: paymentMethod,
                  bookingId: bookingId,
                  guestName: guestName,
                );
              },
              child: const Text('Email PDF'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: receiptText.toString()));
                if (mounted) {
                  ErrorHandler.showSuccessMessage(context, 'Receipt copied to clipboard');
                }
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<Uint8List> _buildKitchenReceiptPdf({
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String paymentMethod,
    String? bookingId,
    String? guestName,
  }) async {
    final doc = pw.Document();
    final dateText = DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now());

    doc.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('P-ZED Homes Kitchen Receipt', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Text('Item: $itemName'),
              pw.Text('Quantity: $quantity'),
              pw.Text('Unit Price: ₦${NumberFormat('#,##0.00').format(unitPriceNaira)}'),
              pw.Text('Total: ₦${NumberFormat('#,##0.00').format(totalNaira)}'),
              pw.Text('Payment Method: $paymentMethod'),
              pw.Text('Booking ID: ${bookingId ?? 'N/A'}'),
              pw.Text('Guest: ${guestName ?? 'N/A'}'),
              pw.SizedBox(height: 12),
              pw.Text('Generated: $dateText', style: const pw.TextStyle(fontSize: 10)),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<void> _saveKitchenReceiptPdf({
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String paymentMethod,
    String? bookingId,
    String? guestName,
  }) async {
    try {
      final bytes = await _buildKitchenReceiptPdf(
        itemName: itemName,
        quantity: quantity,
        unitPriceNaira: unitPriceNaira,
        totalNaira: totalNaira,
        paymentMethod: paymentMethod,
        bookingId: bookingId,
        guestName: guestName,
      );
      final location = await getSaveLocation(
        suggestedName: 'kitchen_receipt_${DateTime.now().millisecondsSinceEpoch}.pdf',
        acceptedTypeGroups: [const XTypeGroup(label: 'PDF', extensions: ['pdf'])],
      );
      if (location == null) return;
      final file = XFile.fromData(
        bytes,
        mimeType: 'application/pdf',
        name: 'kitchen_receipt.pdf',
      );
      await file.saveTo(location.path);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Receipt saved to file');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG save receipt: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to save receipt. Please try again.', stackTrace: stackTrace);
      }
    }
  }

  Future<void> _printKitchenReceipt({
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String paymentMethod,
    String? bookingId,
    String? guestName,
  }) async {
    try {
      final bytes = await _buildKitchenReceiptPdf(
        itemName: itemName,
        quantity: quantity,
        unitPriceNaira: unitPriceNaira,
        totalNaira: totalNaira,
        paymentMethod: paymentMethod,
        bookingId: bookingId,
        guestName: guestName,
      );
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG print receipt: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to print receipt. Please try again.', stackTrace: stackTrace);
      }
    }
  }

  Future<void> _shareKitchenReceiptPdf({
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String paymentMethod,
    String? bookingId,
    String? guestName,
  }) async {
    try {
      final bytes = await _buildKitchenReceiptPdf(
        itemName: itemName,
        quantity: quantity,
        unitPriceNaira: unitPriceNaira,
        totalNaira: totalNaira,
        paymentMethod: paymentMethod,
        bookingId: bookingId,
        guestName: guestName,
      );
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'application/pdf', name: 'kitchen_receipt.pdf')],
        subject: 'P-ZED Homes Kitchen Receipt',
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG share receipt: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to share receipt. Please try again.', stackTrace: stackTrace);
      }
    }
  }

  Future<void> _emailKitchenReceiptPdf({
    required String receiptText,
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String paymentMethod,
    String? bookingId,
    String? guestName,
  }) async {
    final email = await _promptForEmailAddress();
    if (email == null || email.isEmpty) return;
    try {
      final bytes = await _buildKitchenReceiptPdf(
        itemName: itemName,
        quantity: quantity,
        unitPriceNaira: unitPriceNaira,
        totalNaira: totalNaira,
        paymentMethod: paymentMethod,
        bookingId: bookingId,
        guestName: guestName,
      );
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'application/pdf', name: 'kitchen_receipt.pdf')],
        subject: 'P-ZED Homes Kitchen Receipt',
        text: receiptText,
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG email receipt: $e\n$stackTrace');
      if (mounted) {
        final fallbackUri = Uri(
          scheme: 'mailto',
          path: email,
          queryParameters: {
            'subject': 'P-ZED Homes Kitchen Receipt',
            'body': receiptText,
          },
        );
        final fallbackOpened = await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        if (!fallbackOpened) {
          ErrorHandler.handleError(context, e, customMessage: 'Could not open email client. Please try again.', stackTrace: stackTrace);
        }
      }
    }
  }

  Future<void> _showDispatchSlipDialog({
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String destinationDepartment,
    required String paymentMethod,
    required String paymentStatus,
    String? bookingId,
    String? guestName,
  }) async {
    final slipText = StringBuffer()
      ..writeln('P-ZED Homes Kitchen Dispatch Slip')
      ..writeln('Item: $itemName')
      ..writeln('Quantity: $quantity')
      ..writeln('Unit Price: ₦${NumberFormat('#,##0.00').format(unitPriceNaira)}')
      ..writeln('Total: ₦${NumberFormat('#,##0.00').format(totalNaira)}')
      ..writeln('Destination: ${_formatDepartmentName(destinationDepartment)}')
      ..writeln('Payment Status: $paymentStatus')
      ..writeln('Payment Method: $paymentMethod')
      ..writeln('Booking ID: ${bookingId ?? 'N/A'}')
      ..writeln('Guest: ${guestName ?? 'N/A'}')
      ..writeln('Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}');

    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) {
        return AlertDialog(
          title: const Text('Dispatch Slip'),
          content: SingleChildScrollView(
            child: SelectableText(slipText.toString()),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _saveDispatchSlipPdf(
                  itemName: itemName,
                  quantity: quantity,
                  unitPriceNaira: unitPriceNaira,
                  totalNaira: totalNaira,
                  destinationDepartment: destinationDepartment,
                  paymentMethod: paymentMethod,
                  paymentStatus: paymentStatus,
                  bookingId: bookingId,
                  guestName: guestName,
                );
              },
              child: const Text('Save PDF'),
            ),
            TextButton(
              onPressed: () async {
                await _printDispatchSlip(
                  itemName: itemName,
                  quantity: quantity,
                  unitPriceNaira: unitPriceNaira,
                  totalNaira: totalNaira,
                  destinationDepartment: destinationDepartment,
                  paymentMethod: paymentMethod,
                  paymentStatus: paymentStatus,
                  bookingId: bookingId,
                  guestName: guestName,
                );
              },
              child: const Text('Print/PDF'),
            ),
            TextButton(
              onPressed: () async {
                await _shareDispatchSlipPdf(
                  itemName: itemName,
                  quantity: quantity,
                  unitPriceNaira: unitPriceNaira,
                  totalNaira: totalNaira,
                  destinationDepartment: destinationDepartment,
                  paymentMethod: paymentMethod,
                  paymentStatus: paymentStatus,
                  bookingId: bookingId,
                  guestName: guestName,
                );
              },
              child: const Text('Share PDF'),
            ),
            TextButton(
              onPressed: () async {
                await _emailDispatchSlipPdf(
                  slipText: slipText.toString(),
                  itemName: itemName,
                  quantity: quantity,
                  unitPriceNaira: unitPriceNaira,
                  totalNaira: totalNaira,
                  destinationDepartment: destinationDepartment,
                  paymentMethod: paymentMethod,
                  paymentStatus: paymentStatus,
                  bookingId: bookingId,
                  guestName: guestName,
                );
              },
              child: const Text('Email PDF'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: slipText.toString()));
                if (mounted) {
                  ErrorHandler.showSuccessMessage(context, 'Slip copied to clipboard');
                }
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<Uint8List> _buildDispatchSlipPdf({
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String destinationDepartment,
    required String paymentMethod,
    required String paymentStatus,
    String? bookingId,
    String? guestName,
  }) async {
    final doc = pw.Document();
    final dateText = DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now());

    doc.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('P-ZED Homes Kitchen Dispatch Slip', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Text('Item: $itemName'),
              pw.Text('Quantity: $quantity'),
              pw.Text('Unit Price: ₦${NumberFormat('#,##0.00').format(unitPriceNaira)}'),
              pw.Text('Total: ₦${NumberFormat('#,##0.00').format(totalNaira)}'),
              pw.Text('Destination: ${_formatDepartmentName(destinationDepartment)}'),
              pw.Text('Payment Status: $paymentStatus'),
              pw.Text('Payment Method: $paymentMethod'),
              pw.Text('Booking ID: ${bookingId ?? 'N/A'}'),
              pw.Text('Guest: ${guestName ?? 'N/A'}'),
              pw.SizedBox(height: 12),
              pw.Text('Generated: $dateText', style: const pw.TextStyle(fontSize: 10)),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<void> _saveDispatchSlipPdf({
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String destinationDepartment,
    required String paymentMethod,
    required String paymentStatus,
    String? bookingId,
    String? guestName,
  }) async {
    try {
      final bytes = await _buildDispatchSlipPdf(
        itemName: itemName,
        quantity: quantity,
        unitPriceNaira: unitPriceNaira,
        totalNaira: totalNaira,
        destinationDepartment: destinationDepartment,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        bookingId: bookingId,
        guestName: guestName,
      );
      final location = await getSaveLocation(
        suggestedName: 'dispatch_slip_${DateTime.now().millisecondsSinceEpoch}.pdf',
        acceptedTypeGroups: [const XTypeGroup(label: 'PDF', extensions: ['pdf'])],
      );
      if (location == null) return;
      final file = XFile.fromData(
        bytes,
        mimeType: 'application/pdf',
        name: 'dispatch_slip.pdf',
      );
      await file.saveTo(location.path);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Dispatch slip saved to file');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG save dispatch slip: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to save dispatch slip. Please try again.', stackTrace: stackTrace);
      }
    }
  }

  Future<void> _printDispatchSlip({
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String destinationDepartment,
    required String paymentMethod,
    required String paymentStatus,
    String? bookingId,
    String? guestName,
  }) async {
    try {
      final bytes = await _buildDispatchSlipPdf(
        itemName: itemName,
        quantity: quantity,
        unitPriceNaira: unitPriceNaira,
        totalNaira: totalNaira,
        destinationDepartment: destinationDepartment,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        bookingId: bookingId,
        guestName: guestName,
      );
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG print dispatch slip: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to print dispatch slip. Please try again.', stackTrace: stackTrace);
      }
    }
  }

  Future<void> _shareDispatchSlipPdf({
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String destinationDepartment,
    required String paymentMethod,
    required String paymentStatus,
    String? bookingId,
    String? guestName,
  }) async {
    try {
      final bytes = await _buildDispatchSlipPdf(
        itemName: itemName,
        quantity: quantity,
        unitPriceNaira: unitPriceNaira,
        totalNaira: totalNaira,
        destinationDepartment: destinationDepartment,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        bookingId: bookingId,
        guestName: guestName,
      );
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'application/pdf', name: 'dispatch_slip.pdf')],
        subject: 'P-ZED Homes Kitchen Dispatch Slip',
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG share dispatch slip: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to share dispatch slip. Please try again.', stackTrace: stackTrace);
      }
    }
  }

  Future<void> _emailDispatchSlipPdf({
    required String slipText,
    required String itemName,
    required int quantity,
    required double unitPriceNaira,
    required double totalNaira,
    required String destinationDepartment,
    required String paymentMethod,
    required String paymentStatus,
    String? bookingId,
    String? guestName,
  }) async {
    final email = await _promptForEmailAddress();
    if (email == null || email.isEmpty) return;
    try {
      final bytes = await _buildDispatchSlipPdf(
        itemName: itemName,
        quantity: quantity,
        unitPriceNaira: unitPriceNaira,
        totalNaira: totalNaira,
        destinationDepartment: destinationDepartment,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        bookingId: bookingId,
        guestName: guestName,
      );
      await Share.shareXFiles(
        [XFile.fromData(bytes, mimeType: 'application/pdf', name: 'dispatch_slip.pdf')],
        subject: 'P-ZED Homes Kitchen Dispatch Slip',
        text: slipText,
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG email dispatch slip: $e\n$stackTrace');
      if (mounted) {
        final fallbackUri = Uri(
          scheme: 'mailto',
          path: email,
          queryParameters: {
            'subject': 'P-ZED Homes Kitchen Dispatch Slip',
            'body': slipText,
          },
        );
        final fallbackOpened = await launchUrl(fallbackUri, mode: LaunchMode.externalApplication);
        if (!fallbackOpened) {
          ErrorHandler.handleError(context, e, customMessage: 'Could not open email client. Please try again.', stackTrace: stackTrace);
        }
      }
    }
  }

  Future<String?> _promptForEmailAddress() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Email Receipt'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Recipient Email',
              hintText: 'name@example.com',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Send'),
            ),
          ],
        );
      },
    );
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _currentSaleScrollController.dispose();
    _quantityController.dispose();
    _dispatchUnitPriceController.dispose();
    _saleQuantityController.dispose();
    _saleUnitPriceController.dispose();
    _saleCustomNameController.dispose();
    _saleCreditCustomerNameController.dispose();
    _saleCreditCustomerPhoneController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _formatDate: $e\n$stack');
      return '';
    }
  }

  void _invalidateFilteredCaches() {
    _filteredCachesDirty = true;
  }

  void _computeFilteredCaches() {
    final salesRange = _salesFilterRange;
    _cachedFilteredSalesHistory = _salesHistory.where((sale) {
      final createdAtRaw = sale['created_at']?.toString();
      final method = sale['payment_method']?.toString() ?? '';
      DateTime? createdAt;
      if (createdAtRaw != null) {
        try {
          createdAt = DateTime.parse(createdAtRaw);
        } catch (_) {}
      }
      final inRange = salesRange == null
          ? true
          : createdAt != null &&
              !createdAt.isBefore(salesRange.start) &&
              !createdAt.isAfter(
                DateTime(salesRange.end.year, salesRange.end.month, salesRange.end.day, 23, 59, 59),
              );
      final methodOk = _salesFilterPaymentMethod == 'all'
          ? true
          : method == _salesFilterPaymentMethod;
      return inRange && methodOk;
    }).toList();
    final dispatchRange = _dispatchFilterRange;
    _cachedFilteredDispatchHistory = _dispatchHistory.where((transfer) {
      final createdAtRaw = transfer['created_at']?.toString();
      final status = transfer['payment_status']?.toString() ?? '';
      final department = transfer['destination_department']?.toString() ?? '';
      final staffId = transfer['dispatched_by_id']?.toString() ?? '';
      DateTime? createdAt;
      if (createdAtRaw != null) {
        try {
          createdAt = DateTime.parse(createdAtRaw);
        } catch (_) {}
      }
      final inRange = dispatchRange == null
          ? true
          : createdAt != null &&
              !createdAt.isBefore(dispatchRange.start) &&
              !createdAt.isAfter(
                DateTime(dispatchRange.end.year, dispatchRange.end.month, dispatchRange.end.day, 23, 59, 59),
              );
      final statusOk = _dispatchFilterPaymentStatus == 'all'
          ? true
          : status == _dispatchFilterPaymentStatus;
      final departmentOk = _dispatchFilterDepartment == 'all'
          ? true
          : department == _dispatchFilterDepartment;
      final staffOk = _dispatchFilterStaffId == 'all'
          ? true
          : staffId == _dispatchFilterStaffId;
      return inRange && statusOk && departmentOk && staffOk;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredSalesHistory {
    if (_filteredCachesDirty) {
      _filteredCachesDirty = false;
      _computeFilteredCaches();
    }
    return _cachedFilteredSalesHistory!;
  }

  List<Map<String, dynamic>> get _filteredDispatchHistory {
    if (_filteredCachesDirty) {
      _filteredCachesDirty = false;
      _computeFilteredCaches();
    }
    return _cachedFilteredDispatchHistory!;
  }

  List<DropdownMenuItem<String>> _uniqueDispatchStaffItems() {
    final items = <DropdownMenuItem<String>>[];
    final seen = <String>{};
    for (final transfer in _dispatchHistory) {
      final profile = transfer['profiles'] as Map<String, dynamic>?;
      if (profile == null) continue;
      final id = profile['id']?.toString();
      if (id == null || seen.contains(id)) continue;
      seen.add(id);
      items.add(
        DropdownMenuItem(
          value: id,
          child: Text(profile['full_name'] as String? ?? 'Staff'),
        ),
      );
    }
    return items;
  }

  /// Memoized: derive showFullFunctionality from auth (avoids repeated role checks in build).
  static bool _selectorShowFullFunctionality(AuthService auth) {
    final user = auth.currentUser;
    final isKitchenStaff = (user?.roles.any((r) => r == AppRole.kitchen_staff) ?? false);
    final isAssumedKitchenStaff = auth.hasAssumedRole(AppRole.kitchen_staff);
    final isReceptionist = (user?.roles.any((r) => r == AppRole.receptionist) ?? false);
    final isVipBartender = (user?.roles.any((r) => r == AppRole.vip_bartender) ?? false);
    return isKitchenStaff || isAssumedKitchenStaff || isReceptionist || isVipBartender;
  }

  @override
  Widget build(BuildContext context) {
    return Selector<AuthService, bool>(
      selector: (_, auth) => _selectorShowFullFunctionality(auth),
      builder: (context, showFullFunctionality, _) {
        final destinations = _departments;
        return Scaffold(
          appBar: AppBar(
            title: const Text('Kitchen', overflow: TextOverflow.ellipsis, maxLines: 1),
            backgroundColor: Colors.orange.shade800,
            leading: Navigator.of(context).canPop() ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ) : null,
            actions: [
              const ContextAwareRoleButton(suggestedRole: AppRole.kitchen_staff),
              IconButton(
                icon: const Icon(Icons.refresh),
                onPressed: _loadStockAndLocations,
              ),
            ],
          ),
          body: Column(
            children: [
              if (_missingStockLinks.isNotEmpty && !_dismissedWarnings.contains('missing_stock_linkage'))
                _KitchenMissingStockWarning(
                  missingLinks: _missingStockLinks,
                  onDismiss: () {
                    setState(() => _dismissedWarnings.add('missing_stock_linkage'));
                  },
                ),
              if (showFullFunctionality)
                TabBar(
                  controller: _tabController,
                  labelColor: Colors.orange.shade800,
                  tabs: const [
                    Tab(text: 'Dispatch', icon: Icon(Icons.send)),
                    Tab(text: 'Sales', icon: Icon(Icons.point_of_sale)),
                    Tab(text: 'History', icon: Icon(Icons.history)),
                  ],
                ),
              Expanded(
                child: showFullFunctionality
                    ? TabBarView(
                        controller: _tabController,
                        children: [
                          // Dispatch tab
                          Column(
                            children: [
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
                                          labelText: 'Food Item',
                      border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.restaurant_menu),
                    ),
                    items: _stockItems
                        .map((item) => DropdownMenuItem(
                              value: item['id'] as String,
                                                  child: Text(item['name'] as String? ?? 'Item'),
                            ))
                        .toList(),
                                        onChanged: (val) {
                                          setState(() => _selectedStockItemId = val);
                                          _setDispatchPriceFromItem(val);
                                        },
                                        validator: (val) =>
                                            val == null ? 'Please select an item' : null,
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
                                              value: _selectedDestinationDepartment,
                          decoration: const InputDecoration(
                                                labelText: 'Destination Department',
                            border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.apartment),
                          ),
                          items: destinations
                              .map((destination) => DropdownMenuItem(
                                                        value: destination['name'] as String,
                                                        child: Text(
                                                          _formatDepartmentName(destination['name'] as String),
                                                        ),
                                  ))
                              .toList(),
                                              onChanged: (val) =>
                                                  setState(() => _selectedDestinationDepartment = val),
                                              validator: (val) =>
                                                  val == null ? 'Select department' : null,
                        ),
                      ),
                    ],
                  ),
                                      const SizedBox(height: 16),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextFormField(
                                              controller: _dispatchUnitPriceController,
                                              decoration: const InputDecoration(
                                                labelText: 'Unit Price (₦)',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.payments),
                                              ),
                                              keyboardType: const TextInputType.numberWithOptions(
                                                decimal: true,
                                              ),
                                              validator: (val) {
                                                if (val == null || val.isEmpty) return 'Enter price';
                                                final price = double.tryParse(val);
                                                if (price == null || price <= 0) {
                                                  return 'Enter valid price';
                                                }
                                                return null;
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: DropdownButtonFormField<String>(
                                              value: _dispatchPaymentMethod,
                                              decoration: const InputDecoration(
                                                labelText: 'Payment Method',
                                                border: OutlineInputBorder(),
                                                prefixIcon: Icon(Icons.account_balance_wallet),
                                              ),
                                              items: const [
                                                DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                                DropdownMenuItem(value: 'card', child: Text('Card')),
                                                DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                                                DropdownMenuItem(value: 'credit', child: Text('Credit (Room)')),
                                              ],
                                              onChanged: _dispatchPaymentStatus == 'unpaid'
                                                  ? null
                                                  : (val) => setState(
                                                        () => _dispatchPaymentMethod = val ?? 'cash',
                                                      ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 16),
                                      DropdownButtonFormField<String>(
                                        value: _dispatchPaymentStatus,
                                        decoration: const InputDecoration(
                                          labelText: 'Payment Status',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.payments_outlined),
                                        ),
                                        items: const [
                                          DropdownMenuItem(value: 'paid', child: Text('Paid now')),
                                          DropdownMenuItem(value: 'unpaid', child: Text('Charge to room (debt)')),
                                        ],
                                        onChanged: (val) {
                                          setState(() {
                                            _dispatchPaymentStatus = val ?? 'paid';
                                            if (_dispatchPaymentStatus == 'unpaid') {
                                              _dispatchPaymentMethod = 'credit';
                                            } else if (_dispatchPaymentMethod == 'credit') {
                                              _dispatchPaymentMethod = 'cash';
                                            }
                                          });
                                        },
                                      ),
                                      const SizedBox(height: 12),
                                      DropdownButtonFormField<String>(
                                        value: _selectedDispatchBookingId,
                                        decoration: const InputDecoration(
                                          labelText: 'Link to Booking (optional)',
                                          border: OutlineInputBorder(),
                                          prefixIcon: Icon(Icons.meeting_room),
                                        ),
                                        items: _bookings
                                            .map((booking) {
                                              final guestProfile =
                                                  booking['profiles'] as Map<String, dynamic>?;
                                              final guestName =
                                                  booking['guest_name'] as String? ??
                                                      guestProfile?['full_name'] as String? ??
                                                      'Guest';
                                              final roomNumber = (booking['rooms']
                                                              as Map<String, dynamic>?)
                                                          ?['room_number']
                                                          ?.toString() ??
                                                  booking['requested_room_type']?.toString() ??
                                                  'Room';
                                              return DropdownMenuItem(
                                                value: booking['id'] as String,
                                                child: Text('$guestName • $roomNumber'),
                                              );
                                            })
                                            .toList(),
                                        onChanged: (val) =>
                                            setState(() => _selectedDispatchBookingId = val),
                                        validator: (val) => _dispatchPaymentStatus == 'unpaid' && val == null
                                            ? 'Select a booking'
                                            : null,
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
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Recent Dispatches',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
          Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: _dispatchFilterPaymentStatus,
                                            decoration: const InputDecoration(
                                              labelText: 'Payment Status',
                                              border: OutlineInputBorder(),
                                            ),
                                            items: const [
                                              DropdownMenuItem(value: 'all', child: Text('All')),
                                              DropdownMenuItem(value: 'paid', child: Text('Paid')),
                                              DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                                            ],
                                            onChanged: (val) => setState(() {
                                              _dispatchFilterPaymentStatus = val ?? 'all';
                                              _invalidateFilteredCaches();
                                            }),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              final now = DateTime.now();
                                              final picked = await showDateRangePicker(
                                                context: context,
                                                firstDate: DateTime(now.year - 2),
                                                lastDate: DateTime(now.year + 1),
                                                initialDateRange: _dispatchFilterRange,
                                              );
                                              if (picked != null) {
                                                setState(() {
                                                _dispatchFilterRange = picked;
                                                _invalidateFilteredCaches();
                                              });
                                              }
                                            },
                                            icon: const Icon(Icons.date_range),
                                            label: Text(
                                              _dispatchFilterRange == null
                                                  ? 'Date range'
                                                  : '${DateFormat('MMM dd').format(_dispatchFilterRange!.start)} - ${DateFormat('MMM dd').format(_dispatchFilterRange!.end)}',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: _dispatchFilterDepartment,
                                            decoration: const InputDecoration(
                                              labelText: 'Destination Department',
                                              border: OutlineInputBorder(),
                                            ),
                                            items: [
                                              const DropdownMenuItem(value: 'all', child: Text('All')),
                                              ..._departments.map((dept) => DropdownMenuItem(
                                                    value: dept['name'] as String,
                                                    child: Text(_formatDepartmentName(dept['name'] as String)),
                                                  )),
                                            ],
                                            onChanged: (val) => setState(() {
                                              _dispatchFilterDepartment = val ?? 'all';
                                              _invalidateFilteredCaches();
                                            }),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: _dispatchFilterStaffId,
                                            decoration: const InputDecoration(
                                              labelText: 'Dispatched By',
                                              border: OutlineInputBorder(),
                                            ),
                                            items: [
                                              const DropdownMenuItem(value: 'all', child: Text('All')),
                                              ..._uniqueDispatchStaffItems(),
                                            ],
                                            onChanged: (val) => setState(() {
                                              _dispatchFilterStaffId = val ?? 'all';
                                              _invalidateFilteredCaches();
                                            }),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_dispatchFilterRange != null)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () => setState(() {
                                          _dispatchFilterRange = null;
                                          _invalidateFilteredCaches();
                                        }),
                                          child: const Text('Clear date filter'),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _filteredDispatchHistory.isEmpty
                                    ? ErrorHandler.buildEmptyWidget(
                    context,
                                        message: 'No recent dispatches',
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                        itemCount: _filteredDispatchHistory.length,
                                        itemBuilder: (context, index) {
                                          final transfer = _filteredDispatchHistory[index];
                                          final menuItem =
                                              transfer['menu_items'] as Map<String, dynamic>?;
                                          final itemName = menuItem?['name'] ?? 'Unknown Item';
                                          final destination = transfer['destination_department']?.toString() ?? 'Unknown';
                                          final booking = transfer['bookings'] as Map<String, dynamic>?;
                                          final bookingGuest = booking?['guest_name'] as String?;
                                          return Card(
                                            margin: const EdgeInsets.symmetric(vertical: 4),
                                            child: ListTile(
                                              leading:
                                                  const Icon(Icons.send, color: Colors.orange),
                                              title: Text(
                                                'To: ${_formatDepartmentName(destination)}',
                                              ),
                                              subtitle: Text(
                                                '$itemName • Qty: ${transfer['quantity'] ?? 0} • Status: ${transfer['status'] ?? 'Unknown'}'
                                                ' • Pay: ${transfer['payment_status'] ?? 'paid'}'
                                                '${bookingGuest != null ? ' • $bookingGuest' : ''}',
                                              ),
                                              trailing: Text(
                                                transfer['created_at'] != null
                                                    ? _formatDate(transfer['created_at'] as String)
                                                    : '',
                                                style: const TextStyle(fontSize: 12),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                          // Sales tab
                          Column(
                            children: [
                              Expanded(
                                child: MediaQuery.sizeOf(context).width < 600
                                    ? Column(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          _buildKitchenSalesGrid(),
                                          _buildKitchenCurrentSaleSection(),
                                        ],
                                      )
                                    : Row(
                                        crossAxisAlignment: CrossAxisAlignment.stretch,
                                        children: [
                                          _buildKitchenSalesGrid(),
                                          _buildKitchenCurrentSaleSection(),
                                        ],
                                      ),
                              ),
                              const Divider(thickness: 2),
                              const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Text(
                                  'Recent Kitchen Sales',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                child: Column(
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          child: DropdownButtonFormField<String>(
                                            value: _salesFilterPaymentMethod,
                                            decoration: const InputDecoration(
                                              labelText: 'Payment Method',
                                              border: OutlineInputBorder(),
                                            ),
                                            items: const [
                                              DropdownMenuItem(value: 'all', child: Text('All')),
                                              DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                              DropdownMenuItem(value: 'card', child: Text('Card')),
                                              DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                                              DropdownMenuItem(value: 'credit', child: Text('Credit')),
                                            ],
                                            onChanged: (val) => setState(() {
                                              _salesFilterPaymentMethod = val ?? 'all';
                                              _invalidateFilteredCaches();
                                            }),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: OutlinedButton.icon(
                                            onPressed: () async {
                                              final now = DateTime.now();
                                              final picked = await showDateRangePicker(
                                                context: context,
                                                firstDate: DateTime(now.year - 2),
                                                lastDate: DateTime(now.year + 1),
                                                initialDateRange: _salesFilterRange,
                                              );
                                              if (picked != null) {
                                                setState(() {
                                                _salesFilterRange = picked;
                                                _invalidateFilteredCaches();
                                              });
                                              }
                                            },
                                            icon: const Icon(Icons.date_range),
                                            label: Text(
                                              _salesFilterRange == null
                                                  ? 'Date range'
                                                  : '${DateFormat('MMM dd').format(_salesFilterRange!.start)} - ${DateFormat('MMM dd').format(_salesFilterRange!.end)}',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_salesFilterRange != null)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () => setState(() {
                                          _salesFilterRange = null;
                                          _invalidateFilteredCaches();
                                        }),
                                          child: const Text('Clear date filter'),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              Expanded(
                                child: _filteredSalesHistory.isEmpty
                                    ? ErrorHandler.buildEmptyWidget(
                    context,
                                        message: 'No recent kitchen sales',
                                      )
                                    : ListView.builder(
                                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                        itemCount: _filteredSalesHistory.length,
                                        itemBuilder: (context, index) {
                                          final sale = _filteredSalesHistory[index];
                                          final itemName = sale['item_name'] ??
                                              (sale['menu_items'] as Map<String, dynamic>?)?['name'] ??
                                              'Item';
                                          final qty = sale['quantity'] ?? 0;
                                          final total = sale['total_amount'] as int? ?? 0;
                                          final bookingId = sale['booking_id'];
                                          final booking = sale['bookings'] as Map<String, dynamic>?;
                                          final bookingGuest = booking?['guest_name'] as String?;
                                          return Card(
                                            margin: const EdgeInsets.symmetric(vertical: 4),
                                            child: ListTile(
                                              leading: const Icon(Icons.receipt_long, color: Colors.orange),
                                              title: Text('$itemName × $qty'),
                                              subtitle: Text(
                                                'Payment: ${sale['payment_method'] ?? 'cash'}'
                                                '${bookingId != null ? ' • Room Charge' : ''}'
                                                '${bookingGuest != null ? ' • $bookingGuest' : ''}',
                                              ),
                                              trailing: Text(
                                                '₦${NumberFormat('#,##0.00').format(PaymentService.koboToNaira(total))}',
                                                style: const TextStyle(fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                              ),
                            ],
                          ),
                          // History tab - shows all transactions (sales + dispatch + restock)
                          _buildHistoryTab(),
                        ],
                      )
                    : _buildReadOnlyDispatchList(),
              ),
            ],
          ),
        );
      },
    );
  }
  
  Widget _buildHistoryTab() {
    // Combine sales history and dispatch history
    final allTransactions = <Map<String, dynamic>>[];
    
    // Add sales with type and staff info
    for (var sale in _salesHistory) {
      allTransactions.add({
        ...sale,
        'transaction_type': 'Sale',
        'timestamp': sale['created_at'] ?? sale['sale_date'],
        'staff_name': (sale['profiles'] as Map<String, dynamic>?)?['full_name'] ?? 'Unknown Staff',
      });
    }
    
    // Add dispatches with type and staff info
    for (var dispatch in _dispatchHistory) {
      allTransactions.add({
        ...dispatch,
        'transaction_type': 'Dispatch',
        'timestamp': dispatch['created_at'],
        'staff_name': (dispatch['profiles'] as Map<String, dynamic>?)?['full_name'] ?? 'Unknown Staff',
      });
    }
    
    // Apply filters
    List<Map<String, dynamic>> filteredTransactions = allTransactions;
    
    // Filter by type
    if (_historyFilterType != 'all') {
      filteredTransactions = filteredTransactions.where((t) => t['transaction_type'] == _historyFilterType).toList();
    }
    
    // Filter by staff
    if (_historyFilterStaffId != 'all') {
      filteredTransactions = filteredTransactions.where((t) {
        final staffId = t['sold_by'] ?? t['dispatched_by_id'];
        return staffId?.toString() == _historyFilterStaffId;
      }).toList();
    }
    
    // Filter by date range
    if (_historyFilterRange != null) {
      filteredTransactions = filteredTransactions.where((t) {
        final timestamp = _parseTimestamp(t['timestamp']);
        if (timestamp == null) return false;
        return (timestamp.isAfter(_historyFilterRange!.start) || timestamp.isAtSameMomentAs(_historyFilterRange!.start))
            && (timestamp.isBefore(_historyFilterRange!.end) || timestamp.isAtSameMomentAs(_historyFilterRange!.end));
      }).toList();
    }
    
    // Sort by timestamp (most recent first)
    filteredTransactions.sort((a, b) {
      final aTime = _parseTimestamp(a['timestamp']);
      final bTime = _parseTimestamp(b['timestamp']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    
    // Get unique staff for filter dropdown
    final uniqueStaff = allTransactions
        .map((t) => {
              'id': t['sold_by'] ?? t['dispatched_by_id'],
              'name': t['staff_name'],
            })
        .where((s) => s['id'] != null)
        .toSet()
        .toList();
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Transaction History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '${filteredTransactions.length} transactions',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              // Filters
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _historyFilterType,
                      decoration: const InputDecoration(
                        labelText: 'Type',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'Sale', child: Text('Sales')),
                        DropdownMenuItem(value: 'Dispatch', child: Text('Dispatches')),
                      ],
                      onChanged: (val) => setState(() => _historyFilterType = val ?? 'all'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _historyFilterStaffId,
                      decoration: const InputDecoration(
                        labelText: 'Staff',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All Staff')),
                        ...uniqueStaff.map((s) => DropdownMenuItem(
                              value: s['id']?.toString(),
                              child: Text(s['name']?.toString() ?? 'Unknown'),
                            )),
                      ],
                      onChanged: (val) => setState(() => _historyFilterStaffId = val ?? 'all'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(now.year - 2),
                          lastDate: DateTime(now.year + 1),
                          initialDateRange: _historyFilterRange,
                        );
                        if (picked != null) {
                          setState(() => _historyFilterRange = picked);
                        }
                      },
                      icon: const Icon(Icons.date_range, size: 18),
                      label: Text(
                        _historyFilterRange == null
                            ? 'Date range'
                            : '${DateFormat('MMM dd').format(_historyFilterRange!.start)} - ${DateFormat('MMM dd').format(_historyFilterRange!.end)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ),
                ],
              ),
              if (_historyFilterRange != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _historyFilterRange = null),
                      child: const Text('Clear date filter'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: filteredTransactions.isEmpty
              ? ErrorHandler.buildEmptyWidget(
                  context,
                  message: 'No transactions found',
                )
              : ScrollableListViewWithArrows(
                  itemCount: filteredTransactions.length,
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemBuilder: (context, index) {
                    final transaction = filteredTransactions[index];
                    final isSale = transaction['transaction_type'] == 'Sale';
                    final timestamp = transaction['timestamp']?.toString() ?? '';
                    final time = timestamp.isNotEmpty
                        ? DateFormat('MMM dd, yyyy HH:mm').format(_parseTimestamp(timestamp)!)
                        : 'Unknown time';
                    final staffName = transaction['staff_name'] ?? 'Unknown Staff';
                    
                    if (isSale) {
                      final itemName = transaction['item_name'] ??
                          (transaction['menu_items'] as Map<String, dynamic>?)?['name'] ??
                          'Item';
                      final qty = transaction['quantity'] ?? 0;
                      final total = transaction['total_amount'] as int? ?? 0;
                      final paymentMethod = transaction['payment_method'] ?? 'cash';
                      final booking = transaction['bookings'] as Map<String, dynamic>?;
                      final bookingGuest = booking?['guest_name'] as String?;
                      final roomNumber = booking?['rooms']?['room_number'] as String?;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.point_of_sale, color: Colors.orange),
                          title: Text('$itemName × $qty'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Staff: $staffName'),
                              Text('Payment: ${paymentMethod.toUpperCase()}'),
                              if (bookingGuest != null) 
                                Text('Guest: $bookingGuest${roomNumber != null ? ' (Room $roomNumber)' : ''}'),
                              Text(time, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₦${NumberFormat('#,##0.00').format(PaymentService.koboToNaira(total))}',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ),
                      );
                    } else {
                      // Dispatch
                      final itemName = (transaction['menu_items'] as Map<String, dynamic>?)?['name'] ?? 'Item';
                      final qty = transaction['quantity'] ?? 0;
                      final destination = transaction['destination_department'] ?? 'Unknown';
                      final status = transaction['status'] ?? 'Pending';
                      final booking = transaction['bookings'] as Map<String, dynamic>?;
                      final bookingGuest = booking?['guest_name'] as String?;
                      final roomNumber = booking?['rooms']?['room_number'] as String?;
                      final totalAmount = transaction['total_amount'] as int? ?? 0;
                      
                      return Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: const Icon(Icons.send, color: Colors.blue),
                          title: Text('$itemName × $qty'),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Staff: $staffName'),
                              Text('To: ${_formatDepartmentName(destination)}'),
                              Text('Status: $status'),
                              if (bookingGuest != null)
                                Text('Guest: $bookingGuest${roomNumber != null ? ' (Room $roomNumber)' : ''}'),
                              Text(time, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                            ],
                          ),
                          trailing: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              if (totalAmount > 0)
                                Text(
                                  '₦${NumberFormat('#,##0.00').format(PaymentService.koboToNaira(totalAmount))}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                                ),
                              Icon(
                                status == 'Completed' ? Icons.check_circle : Icons.pending,
                                color: status == 'Completed' ? Colors.green : Colors.orange,
                                size: 20,
                              ),
                            ],
                          ),
                        ),
                      );
                    }
                  },
                ),
        ),
      ],
    );
  }
  
  DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    try {
      return DateTime.parse(timestamp.toString());
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _parseTimestamp: $e\n$stack');
      return null;
    }
  }

  Widget _buildReadOnlyDispatchList() {
    return Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(16.0),
          child: Text(
            'Recent Dispatches',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _dispatchFilterPaymentStatus,
                      decoration: const InputDecoration(
                        labelText: 'Payment Status',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'all', child: Text('All')),
                        DropdownMenuItem(value: 'paid', child: Text('Paid')),
                        DropdownMenuItem(value: 'unpaid', child: Text('Unpaid')),
                      ],
                      onChanged: (val) => setState(
                        () {
                          _dispatchFilterPaymentStatus = val ?? 'all';
                          _invalidateFilteredCaches();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDateRangePicker(
                          context: context,
                          firstDate: DateTime(now.year - 2),
                          lastDate: DateTime(now.year + 1),
                          initialDateRange: _dispatchFilterRange,
                        );
                        if (picked != null) {
                          setState(() {
                                                _dispatchFilterRange = picked;
                                                _invalidateFilteredCaches();
                                              });
                        }
                      },
                      icon: const Icon(Icons.date_range),
                      label: Text(
                        _dispatchFilterRange == null
                            ? 'Date range'
                            : '${DateFormat('MMM dd').format(_dispatchFilterRange!.start)} - ${DateFormat('MMM dd').format(_dispatchFilterRange!.end)}',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _dispatchFilterDepartment,
                      decoration: const InputDecoration(
                        labelText: 'Destination Department',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All')),
                        ..._departments.map((dept) => DropdownMenuItem(
                              value: dept['name'] as String,
                              child: Text(_formatDepartmentName(dept['name'] as String)),
                            )),
                      ],
                      onChanged: (val) => setState(
                        () {
                          _dispatchFilterDepartment = val ?? 'all';
                          _invalidateFilteredCaches();
                        },
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _dispatchFilterStaffId,
                      decoration: const InputDecoration(
                        labelText: 'Dispatched By',
                        border: OutlineInputBorder(),
                      ),
                      items: [
                        const DropdownMenuItem(value: 'all', child: Text('All')),
                        ..._uniqueDispatchStaffItems(),
                      ],
                      onChanged: (val) => setState(
                        () {
                          _dispatchFilterStaffId = val ?? 'all';
                          _invalidateFilteredCaches();
                        },
                      ),
                    ),
                  ),
                ],
              ),
              if (_dispatchFilterRange != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() {
                                          _dispatchFilterRange = null;
                                          _invalidateFilteredCaches();
                                        }),
                    child: const Text('Clear date filter'),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _filteredDispatchHistory.isEmpty
              ? ErrorHandler.buildEmptyWidget(
                  context,
                  message: 'No recent dispatches',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: _filteredDispatchHistory.length,
                  itemBuilder: (context, index) {
                    final transfer = _filteredDispatchHistory[index];
                    final menuItem = transfer['menu_items'] as Map<String, dynamic>?;
                    final itemName = menuItem?['name'] ?? 'Unknown Item';
                    final destination = transfer['destination_department']?.toString() ?? 'Unknown';
                    final booking = transfer['bookings'] as Map<String, dynamic>?;
                    final bookingGuest = booking?['guest_name'] as String?;
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: const Icon(Icons.send, color: Colors.orange),
                        title: Text('To: ${_formatDepartmentName(destination)}'),
                        subtitle: Text(
                          '$itemName • Qty: ${transfer['quantity'] ?? 0} • Status: ${transfer['status'] ?? 'Unknown'}'
                          ' • Pay: ${transfer['payment_status'] ?? 'paid'}'
                          '${bookingGuest != null ? ' • $bookingGuest' : ''}',
                        ),
                        trailing: Text(
                          transfer['created_at'] != null
                              ? _formatDate(transfer['created_at'] as String)
                              : '',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                );
              },
            ),
          ),
            ],
    );
  }
}

/// Extracted subwidget: reduces build cost and isolates warning UI.
class _KitchenMissingStockWarning extends StatelessWidget {
  final List<String> missingLinks;
  final VoidCallback onDismiss;

  const _KitchenMissingStockWarning({
    required this.missingLinks,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final preview = missingLinks.take(5).join(', ') + (missingLinks.length > 5 ? '...' : '');
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Card(
        color: Colors.orange[50],
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Missing stock linkage',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Some kitchen items are not linked to stock items. Sales/dispatch will be blocked for them.',
                      style: TextStyle(color: Colors.orange[800], fontSize: 12),
                    ),
                    const SizedBox(height: 6),
                    Text(preview, style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                color: Colors.orange[800],
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
