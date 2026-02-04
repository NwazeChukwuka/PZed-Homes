import 'dart:typed_data';
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
  int? _selectedSaleQuantity = 1; // Default quantity for kitchen sales

  List<Map<String, dynamic>> _stockItems = [];
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
  DateTimeRange? _historyFilterRange;
  String _historyFilterStaffId = 'all';
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAccessAndLoad();
    });
  }

  Future<void> _checkAccessAndLoad() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final isKitchenStaff = (user?.roles.any((r) => r == AppRole.kitchen_staff) ?? false);
    final isAssumedKitchenStaff = authService.isRoleAssumed && authService.assumedRole == AppRole.kitchen_staff;
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
      final dispatchHistory = await _dataService.getDepartmentTransfers();
      final salesHistory = await _dataService.getKitchenSalesHistory();
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
        _locations = List<Map<String, dynamic>>.from(locResponse);
        _departments = List<Map<String, dynamic>>.from(activeDepartments);
        _dispatchHistory = List<Map<String, dynamic>>.from(filteredDispatchHistory);
        _salesHistory = List<Map<String, dynamic>>.from(salesHistory);
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
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load data. Please check your connection and try again.',
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
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to dispatch item. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _recordKitchenSale() async {
    if (!_saleFormKey.currentState!.validate()) return;
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final staffId = authService.currentUser!.id;
      final quantity = _selectedSaleQuantity ?? 1;
      final unitPriceNaira = double.tryParse(_saleUnitPriceController.text.trim()) ?? 0;
      final totalInKobo = PaymentService.nairaToKobo(unitPriceNaira) * quantity;

      if (totalInKobo <= 0) {
        throw Exception('Sale amount must be greater than 0');
      }

      if (_chargeToRoom && _selectedBookingId == null) {
        throw Exception('Select a booking to charge to room');
      }

      final selectedItem = _stockItems.firstWhere(
        (s) => s['id'] == _selectedSaleItemId,
        orElse: () => <String, dynamic>{},
      );
      if (!_isCustomSale && selectedItem['stock_item_id'] == null) {
        throw Exception('This menu item is not linked to a stock item. Link it before selling.');
      }
      final itemName = _isCustomSale
          ? (_saleCustomNameController.text.trim().isEmpty
              ? 'Custom Item'
              : _saleCustomNameController.text.trim())
          : (selectedItem['name'] as String? ?? 'Menu Item');

      final effectivePaymentMethod = _chargeToRoom ? 'credit' : _salePaymentMethod;

      final saleId = await _dataService.createKitchenSale({
        'menu_item_id': _isCustomSale ? null : _selectedSaleItemId,
        'item_name': itemName,
        'quantity': quantity,
        'unit_price': PaymentService.nairaToKobo(unitPriceNaira),
        'total_amount': totalInKobo,
        'payment_method': effectivePaymentMethod,
        'booking_id': _selectedBookingId,
        'sold_by': staffId,
      });

      if (!_chargeToRoom) {
        await _recordDepartmentSale(
          department: 'restaurant',
          amountInKobo: totalInKobo,
          staffId: staffId,
          paymentMethod: effectivePaymentMethod,
        );
      }

      if (_chargeToRoom && _selectedBookingId != null) {
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
          'amount': totalInKobo,
          'owed_to': 'P-ZED Luxury Hotels & Suites',
          'department': 'reception',
          'source_department': 'restaurant',
          'source_type': 'kitchen_sale',
          'reference_id': saleId,
          'reason': 'Kitchen sale charged to room',
          'date': DateTime.now().toIso8601String().split('T')[0],
          'status': 'outstanding',
          'sold_by': staffId,
          'booking_id': _selectedBookingId,
          'sale_id': saleId,
        });

        await _dataService.addBookingCharge(
          bookingId: _selectedBookingId!,
          itemName: itemName,
          priceKobo: PaymentService.nairaToKobo(unitPriceNaira),
          quantity: quantity,
          department: 'restaurant',
          addedBy: staffId,
        );
      }

      // Optional stock deduction when menu item is linked to stock item
      final stockItemId = selectedItem['stock_item_id']?.toString();
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

      _saleFormKey.currentState?.reset();
      _saleQuantityController.clear();
      _saleUnitPriceController.clear();
      _saleCustomNameController.clear();
      setState(() {
        _selectedSaleItemId = null;
        _selectedSaleQuantity = 1; // Reset to default quantity
        _isCustomSale = false;
        _selectedBookingId = null;
        _chargeToRoom = false;
      });

      if (mounted) {
        await _showKitchenReceiptDialog(
          itemName: itemName,
          quantity: quantity,
          unitPriceNaira: unitPriceNaira,
          totalNaira: PaymentService.koboToNaira(totalInKobo),
          paymentMethod: effectivePaymentMethod,
          bookingId: _selectedBookingId,
        );
        ErrorHandler.showSuccessMessage(context, 'Kitchen sale recorded successfully!');
        // Reload stock and locations to refresh the food list with updated stock levels
        await _loadStockAndLocations();
        // Force UI rebuild to show updated stock
        if (mounted) {
          setState(() {});
        }
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to record sale. Please try again.',
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
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to save receipt. Please try again.');
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
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to print receipt. Please try again.');
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
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to share receipt. Please try again.');
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
    } catch (e) {
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
          ErrorHandler.handleError(context, e, customMessage: 'Could not open email client. Please try again.');
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
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to save dispatch slip. Please try again.');
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
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to print dispatch slip. Please try again.');
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
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e, customMessage: 'Failed to share dispatch slip. Please try again.');
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
    } catch (e) {
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
          ErrorHandler.handleError(context, e, customMessage: 'Could not open email client. Please try again.');
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
    _quantityController.dispose();
    _dispatchUnitPriceController.dispose();
    _saleQuantityController.dispose();
    _saleUnitPriceController.dispose();
    _saleCustomNameController.dispose();
    _tabController.dispose();
    super.dispose();
  }

  String _formatDate(String dateString) {
    try {
      final date = DateTime.parse(dateString);
      return '${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return '';
    }
  }

  List<Map<String, dynamic>> get _filteredSalesHistory {
    final range = _salesFilterRange;
    return _salesHistory.where((sale) {
      final createdAtRaw = sale['created_at']?.toString();
      final method = sale['payment_method']?.toString() ?? '';
      DateTime? createdAt;
      if (createdAtRaw != null) {
        try {
          createdAt = DateTime.parse(createdAtRaw);
        } catch (_) {}
      }

      final inRange = range == null
          ? true
          : createdAt != null &&
              !createdAt.isBefore(range.start) &&
              !createdAt.isAfter(
                DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59),
              );
      final methodOk = _salesFilterPaymentMethod == 'all'
          ? true
          : method == _salesFilterPaymentMethod;
      return inRange && methodOk;
    }).toList();
  }

  List<Map<String, dynamic>> get _filteredDispatchHistory {
    final range = _dispatchFilterRange;
    return _dispatchHistory.where((transfer) {
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

      final inRange = range == null
          ? true
          : createdAt != null &&
              !createdAt.isBefore(range.start) &&
              !createdAt.isAfter(
                DateTime(range.end.year, range.end.month, range.end.day, 23, 59, 59),
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

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final user = authService.currentUser;
        final isKitchenStaff = (user?.roles.any((r) => r == AppRole.kitchen_staff) ?? false);
        final isAssumedKitchenStaff = authService.isRoleAssumed && authService.assumedRole == AppRole.kitchen_staff;
        final isOwnerOrManager = user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
        final isReceptionist = (user?.roles.any((r) => r == AppRole.receptionist) ?? false);
        final isVipBartender = (user?.roles.any((r) => r == AppRole.vip_bartender) ?? false);
        
        // Show full functionality if kitchen staff, assumed kitchen staff, receptionist, or VIP bartender
        final showFullFunctionality = isKitchenStaff || isAssumedKitchenStaff || isReceptionist || isVipBartender;
        final destinations = _departments;

        return Scaffold(
          appBar: AppBar(
            title: const Text('Kitchen'),
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
                Padding(
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
                                Text(
                                  _missingStockLinks.take(5).join(', ') +
                                      (_missingStockLinks.length > 5 ? '...' : ''),
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            color: Colors.orange[800],
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () {
                              setState(() {
                                _dismissedWarnings.add('missing_stock_linkage');
                              });
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
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
                                            onChanged: (val) => setState(
                                              () => _dispatchFilterPaymentStatus = val ?? 'all',
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
                                                setState(() => _dispatchFilterRange = picked);
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
                                              () => _dispatchFilterDepartment = val ?? 'all',
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
                                              () => _dispatchFilterStaffId = val ?? 'all',
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (_dispatchFilterRange != null)
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed: () => setState(() => _dispatchFilterRange = null),
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
                              Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Form(
                                  key: _saleFormKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                  SwitchListTile(
                                    title: const Text('Custom Order (not on menu)'),
                                    value: _isCustomSale,
                                    onChanged: (value) {
                                      setState(() {
                                        _isCustomSale = value;
                                        _selectedSaleItemId = null;
                                        _saleUnitPriceController.clear();
                                      });
                                    },
                                  ),
                                  if (!_isCustomSale) ...[
                                    DropdownButtonFormField<String>(
                                      value: _selectedSaleItemId,
                                      decoration: const InputDecoration(
                                        labelText: 'Menu Item',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.restaurant),
                                      ),
                                      items: _stockItems
                                          .map((item) => DropdownMenuItem(
                                                value: item['id'] as String,
                                                child: Text(item['name'] as String? ?? 'Item'),
                                              ))
                                          .toList(),
                                      onChanged: (val) {
                                        setState(() => _selectedSaleItemId = val);
                                        _setSalePriceFromItem(val);
                                      },
                                      validator: (val) {
                                        if (_isCustomSale) return null;
                                        return val == null ? 'Please select an item' : null;
                                      },
                                    ),
                                  ] else ...[
                                    TextFormField(
                                      controller: _saleCustomNameController,
                                      decoration: const InputDecoration(
                                        labelText: 'Custom Item Name',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.edit),
                                      ),
                                      validator: (val) {
                                        if (!_isCustomSale) return null;
                                        if (val == null || val.trim().isEmpty) {
                                          return 'Enter item name';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: DropdownButtonFormField<int>(
                                          value: _selectedSaleQuantity,
                                          decoration: const InputDecoration(
                                            labelText: 'Quantity',
                                            border: OutlineInputBorder(),
                                            prefixIcon: Icon(Icons.numbers),
                                          ),
                                          items: List.generate(20, (index) => index + 1)
                                              .map((qty) => DropdownMenuItem(
                                                    value: qty,
                                                    child: Text('$qty'),
                                                  ))
                                              .toList(),
                                          onChanged: (val) {
                                            setState(() {
                                              _selectedSaleQuantity = val;
                                            });
                                          },
                                          validator: (val) {
                                            if (val == null || val <= 0) return 'Select quantity';
                                            return null;
                                          },
                                        ),
                                      ),
                                      const SizedBox(width: 16),
                                      Expanded(
                                        child: TextFormField(
                                          controller: _saleUnitPriceController,
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
                                            if (price == null || price <= 0) return 'Enter valid price';
                                            return null;
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  DropdownButtonFormField<String>(
                                    value: _salePaymentMethod,
                                    decoration: const InputDecoration(
                                      labelText: 'Payment Method',
                                      border: OutlineInputBorder(),
                                      prefixIcon: Icon(Icons.account_balance_wallet),
                                    ),
                                    items: const [
                                      DropdownMenuItem(value: 'cash', child: Text('Cash')),
                                      DropdownMenuItem(value: 'card', child: Text('Card')),
                                      DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                                    ],
                                    onChanged: (val) =>
                                        setState(() => _salePaymentMethod = val ?? 'cash'),
                                  ),
                                  const SizedBox(height: 12),
                                  SwitchListTile(
                                    title: const Text('Charge to Guest Room'),
                                    subtitle: const Text('Creates a debt for reception to collect at checkout'),
                                    value: _chargeToRoom,
                                    onChanged: (val) {
                                      setState(() {
                                        _chargeToRoom = val;
                                        if (!val) _selectedBookingId = null;
                                      });
                                    },
                                  ),
                                  if (_chargeToRoom) ...[
                                    const SizedBox(height: 8),
                                    DropdownButtonFormField<String>(
                                      value: _selectedBookingId,
                                      decoration: const InputDecoration(
                                        labelText: 'Select Checked‑in Booking',
                                        border: OutlineInputBorder(),
                                        prefixIcon: Icon(Icons.meeting_room),
                                      ),
                                      items: _bookings
                                          .map((booking) {
                                            final guestProfile = booking['profiles'] as Map<String, dynamic>?;
                                            final guestName = booking['guest_name'] as String? ??
                                                guestProfile?['full_name'] as String? ??
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
                                      validator: (val) {
                                        if (_chargeToRoom && val == null) {
                                          return 'Select a booking';
                                        }
                                        return null;
                                      },
                                    ),
                                  ],
                                  const SizedBox(height: 24),
                                  _isLoading
                                      ? const Center(child: CircularProgressIndicator())
                                      : ElevatedButton.icon(
                                          onPressed: _recordKitchenSale,
                                          icon: const Icon(Icons.point_of_sale),
                                          label: const Text('Record Sale'),
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
                                            onChanged: (val) => setState(
                                              () => _salesFilterPaymentMethod = val ?? 'all',
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
                                                initialDateRange: _salesFilterRange,
                                              );
                                              if (picked != null) {
                                                setState(() => _salesFilterRange = picked);
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
                                          onPressed: () => setState(() => _salesFilterRange = null),
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
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: filteredTransactions.length,
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
    } catch (e) {
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
                        () => _dispatchFilterPaymentStatus = val ?? 'all',
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
                          setState(() => _dispatchFilterRange = picked);
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
                        () => _dispatchFilterDepartment = val ?? 'all',
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
                        () => _dispatchFilterStaffId = val ?? 'all',
                      ),
                    ),
                  ),
                ],
              ),
              if (_dispatchFilterRange != null)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _dispatchFilterRange = null),
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
