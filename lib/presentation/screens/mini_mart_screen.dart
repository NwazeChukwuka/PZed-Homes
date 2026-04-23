import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/core/utils/staff_auth_helper.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/core/config/product_catalog_config.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:pzed_homes/presentation/widgets/product_card.dart';
import 'package:pzed_homes/presentation/widgets/product_form_dialog.dart';
import 'package:pzed_homes/presentation/widgets/layered_scroll_body.dart';
import 'package:pzed_homes/presentation/widgets/sale_list_item.dart';
import 'package:pzed_homes/presentation/widgets/scrollable_list_with_arrows.dart';
import 'package:flutter/services.dart';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';
import 'package:uuid/uuid.dart';

class MiniMartScreen extends StatefulWidget {
  const MiniMartScreen({super.key});

  @override
  State<MiniMartScreen> createState() => _MiniMartScreenState();
}

class _MiniMartScreenState extends State<MiniMartScreen> with SingleTickerProviderStateMixin {
  TabController? _tabController;
  final _dataService = DataService();
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw Exception('Service is currently unavailable. Please try again.');
    }
  }
  
  List<Map<String, dynamic>> _miniMartItems = [];
  final List<Map<String, dynamic>> _currentSale = [];
  List<Map<String, dynamic>> _salesHistory = [];
  double _saleTotal = 0.0;
  bool _isLoading = true;
  bool _isProcessingSale = false;
  String? _saleLedgerSessionId;
  StateSetter? _miniMartSaleModalSetState;
  bool _dismissCreditSalesWarning = false;
  
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _approvedByController = TextEditingController(); // For credit sales
  String _paymentMethod = 'Cash';
  
  final _searchController = TextEditingController();
  final ScrollController _currentSaleScrollController = ScrollController();
  final ScrollController _salesHistoryScrollController = ScrollController();
  List<Map<String, dynamic>> _filteredItems = [];
  Timer? _filterDebounce;

  final _addItemNameController = TextEditingController();
  final _addItemPriceController = TextEditingController();
  final _addItemStockController = TextEditingController(text: '0');
  final _addItemSavingNotifier = ValueNotifier<bool>(false);
  bool _addItemAvailable = true;
  String _addItemCategory = 'Snacks';
  static const _miniMartCategories = ['Snacks', 'Drinks', 'Toiletries', 'Other'];

  static const int _salesHistoryPageSize = 50;
  int _salesHistoryOffset = 0;
  bool _salesHistoryHasMore = true;
  bool _salesHistoryLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMiniMartData();
    _searchController.addListener(_onSearchChanged);
    _salesHistoryScrollController.addListener(_onSalesHistoryScroll);
  }

  void _onSalesHistoryScroll() {
    if (_salesHistoryLoadingMore || !_salesHistoryHasMore) return;
    if (!_salesHistoryScrollController.hasClients) return;
    final pos = _salesHistoryScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMoreSalesHistory();
    }
  }

  void _onSearchChanged() {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _filterItems();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _salesHistoryScrollController.removeListener(_onSalesHistoryScroll);
    _salesHistoryScrollController.dispose();
    _searchController.dispose();
    _currentSaleScrollController.dispose();
    _tabController?.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _approvedByController.dispose();
    _addItemSavingNotifier.dispose();
    _addItemNameController.dispose();
    _addItemPriceController.dispose();
    _addItemStockController.dispose();
    super.dispose();
  }

  void _showAddMiniMartItemDialog() {
    _addItemNameController.clear();
    _addItemPriceController.clear();
    _addItemStockController.text = '0';
    setState(() {
      _addItemAvailable = true;
      _addItemCategory = 'Snacks';
    });
    showDialog(
      context: context,
      builder: (dialogContext) => ValueListenableBuilder<bool>(
        valueListenable: _addItemSavingNotifier,
        builder: (context, saving, _) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
          title: const Text('Add Mini Mart Item'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _addItemNameController,
                  decoration: const InputDecoration(labelText: 'Item Name *'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addItemPriceController,
                  decoration: const InputDecoration(labelText: 'Price (₦)'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _addItemCategory,
                  decoration: const InputDecoration(labelText: 'Category'),
                  items: _miniMartCategories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
                  onChanged: (v) => setDialogState(() => _addItemCategory = v ?? 'Snacks'),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _addItemStockController,
                  decoration: const InputDecoration(labelText: 'Initial Stock'),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  title: const Text('Available'),
                  value: _addItemAvailable,
                  onChanged: (v) => setDialogState(() => _addItemAvailable = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      _addItemSavingNotifier.value = true;
                      try {
                        await _saveNewMiniMartItem(dialogContext);
                      } finally {
                        _addItemSavingNotifier.value = false;
                      }
                    },
              child: Text(saving ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    ),
    );
  }

  Future<void> _saveNewMiniMartItem(BuildContext dialogContext) async {
    final name = _addItemNameController.text.trim();
    if (name.isEmpty) {
      ErrorHandler.showWarningMessage(context, 'Item name is required.');
      return;
    }
    final priceNaira = double.tryParse(_addItemPriceController.text.trim());
    if (priceNaira == null || priceNaira < 0) {
      ErrorHandler.showWarningMessage(context, 'Enter a valid price (₦).');
      return;
    }
    final authService = Provider.of<AuthService>(context, listen: false);
    final staffId = StaffAuthHelper.requireStaffProfileId(
      context,
      authService: authService,
      supabase: _supabase,
    );
    if (staffId == null) return;
    final stock = int.tryParse(_addItemStockController.text.trim()) ?? 0;
    try {
      await _dataService.addMiniMartItem(
        name: name,
        priceKobo: PaymentService.nairaToKobo(priceNaira),
        category: _addItemCategory,
        stockQuantity: stock,
        isAvailable: _addItemAvailable,
      );
      await _dataService.logActivity(staffId, 'Added item', 'MiniMart', 'Added $name');
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Item added successfully.');
        _loadMiniMartData();
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: ErrorHandler.getAdminErrorMessage(
            e,
            itemName: name,
            department: 'Mini Mart',
          ),
        );
      }
    } catch (e, stackTrace) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to add item. Please try again.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _loadMiniMartData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      final isManagement =
          user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
      final staffId = user?.id;
      final results = await Future.wait([
        _dataService.getMiniMartItems(),
        _dataService.getMiniMartSales(
          limit: _salesHistoryPageSize,
          offset: 0,
          staffId: isManagement ? null : staffId,
        ),
      ]);
      final itemsResponse = results[0];
      final salesResponse = results[1];

      if (mounted) {
        final items = List<Map<String, dynamic>>.from(itemsResponse)
            .map((item) {
          final priceKobo = (item['price'] as num?)?.toInt() ?? 0;
          return {
            ...item,
            'price': PaymentService.koboToNaira(priceKobo),
          };
        }).toList();
        setState(() {
          _miniMartItems = items;
          _filteredItems = items;
          _salesHistory = List<Map<String, dynamic>>.from(salesResponse);
          _salesHistoryOffset = _salesHistoryPageSize;
          _salesHistoryHasMore = salesResponse.length >= _salesHistoryPageSize;
          _isLoading = false;
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _loadMiniMartData: $e\n$stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load mini mart data. Please check your connection and try again.',
          onRetry: _loadMiniMartData,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _loadMoreSalesHistory() async {
    if (_salesHistoryLoadingMore || !_salesHistoryHasMore) return;
    _salesHistoryLoadingMore = true;
    if (mounted) setState(() {});
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = authService.currentUser;
      final isManagement =
          user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
      final staffId = user?.id;
      final more = await _dataService.getMiniMartSales(
        limit: _salesHistoryPageSize,
        offset: _salesHistoryOffset,
        staffId: isManagement ? null : staffId,
      );
      if (!mounted) return;
      setState(() {
        _salesHistory.addAll(more);
        _salesHistoryOffset += _salesHistoryPageSize;
        _salesHistoryHasMore = more.length >= _salesHistoryPageSize;
      });
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _loadMoreSalesHistory: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.showWarningMessage(context, ErrorHandler.getFriendlyErrorMessage(e));
      }
    } finally {
      if (mounted) setState(() => _salesHistoryLoadingMore = false);
    }
  }

  void _filterItems() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredItems = _miniMartItems.where((item) {
        return item['name']?.toString().toLowerCase().contains(query) ?? false;
      }).toList();
    });
  }

  void _addItemToSale(Map<String, dynamic> item) {
    var addedNewItem = false;
    final existingIndex = _currentSale.indexWhere((saleItem) => saleItem['id'] == item['id']);
    
    setState(() {
      if (existingIndex != -1) {
        _currentSale[existingIndex]['quantity'] = (_currentSale[existingIndex]['quantity'] ?? 0) + 1;
      } else {
        _saleLedgerSessionId ??= const Uuid().v4();
        _currentSale.add({
          ...item,
          'quantity': 1,
        });
        addedNewItem = true;
      }
      _calculateTotal();
    });
    if (addedNewItem) _scrollCurrentSaleToEnd();
  }

  void _removeItemFromSale(int index) {
    setState(() {
      _currentSale.removeAt(index);
      if (_currentSale.isEmpty) _saleLedgerSessionId = null;
      _calculateTotal();
    });
  }

  void _updateItemQuantity(int index, int quantity) {
    if (quantity <= 0) {
      _removeItemFromSale(index);
    } else {
      setState(() {
        _currentSale[index]['quantity'] = quantity;
        _calculateTotal();
      });
    }
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

  void _calculateTotal() {
    _saleTotal = _currentSale.fold(0.0, (sum, item) {
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      final quantity = (item['quantity'] as int?) ?? 0;
      return sum + (price * quantity);
    });
  }

  void _notifyMiniMartSaleProcessingChanged() {
    if (mounted) setState(() {});
    _miniMartSaleModalSetState?.call(() {});
  }

  Future<void> _processSale() async {
    if (_isProcessingSale) return;

    if (_currentSale.isEmpty) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please add items to the sale',
        );
      }
      return;
    }

    _isProcessingSale = true;
    _notifyMiniMartSaleProcessingChanged();

    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = StaffAuthHelper.requireStaffProfileId(
        context,
        authService: authService,
        supabase: _supabase,
      );
      if (userId == null) return;

      if (_paymentMethod == 'Credit') {
        if (_customerNameController.text.trim().isEmpty || _customerPhoneController.text.trim().isEmpty) {
          if (mounted) {
            ErrorHandler.showWarningMessage(
              context,
              'Customer name and phone are required for credit sales',
            );
          }
          return;
        }
      }

      try {
      final customerName = _customerNameController.text.trim().isNotEmpty 
          ? _customerNameController.text.trim() 
          : 'Walk-in Customer';
      final customerPhone = _customerPhoneController.text.trim();
      final saleDateOnly = DateTime.now().toIso8601String().split('T')[0];
      
      final unifiedItems = <Map<String, dynamic>>[];
      for (final saleItem in _currentSale) {
        final itemId = saleItem['id'] as String;
        final quantity = saleItem['quantity'] as int;
        final priceInNaira = (saleItem['price'] as num).toDouble();
        final priceInKobo = PaymentService.nairaToKobo(priceInNaira);
        final totalAmountInKobo = quantity * priceInKobo;

        final itemData = await _supabase
            .from('mini_mart_items')
            .select('stock_quantity, name, unit')
            .eq('id', itemId)
            .single();
        
        final currentStock = (itemData['stock_quantity'] as int?) ?? 0;
        final itemName = itemData['name'] as String? ?? 'Item';
        final unit = itemData['unit'] as String? ?? 'units';
        
        if (currentStock < quantity && mounted) {
          debugPrint('Warning: Low stock for $itemName. Available: $currentStock $unit, Requested: $quantity. Sale will proceed and may result in negative stock.');
        }

        unifiedItems.add({
          'item_id': itemId,
          'quantity': quantity,
          'unit_price_kobo': priceInKobo,
          'line_total_kobo': totalAmountInKobo,
          'notes': 'Mini mart sale',
        });
      }

      final saleTotalInKobo = (_saleTotal * 100).toInt();

      final unifiedRes = await _dataService.processUnifiedSale(
        transactionId: _saleLedgerSessionId ?? const Uuid().v4(),
        items: unifiedItems,
        paymentData: {
          'flow': 'mini_mart',
          'department': 'mini_mart',
          'payment_method': _paymentMethod.toLowerCase(),
          'staff_id': userId,
          'sale_date': saleDateOnly,
          'customer_name': customerName,
        },
      );
      if (unifiedRes['applied'] != true) {
        if (unifiedRes['duplicate'] == true) {
          if (mounted) {
            ErrorHandler.showInfoMessage(
              context,
              'This sale was already recorded (duplicate request ignored).',
            );
          }
          _clearSale();
          return;
        }
        throw Exception('Failed to persist sale atomically.');
      }
      _saleLedgerSessionId = null;
      final firstSaleId = unifiedRes['first_sale_id']?.toString();

      final receiptItems = List<Map<String, dynamic>>.from(_currentSale);
      final receiptTotal = _saleTotal;

      if (_paymentMethod == 'Credit') {
        final debt = {
          'debtor_name': customerName,
          'debtor_phone': customerPhone,
          'debtor_type': 'customer',
          'amount': saleTotalInKobo, // Convert to kobo
          'owed_to': 'P-ZED Luxury Hotels & Suites',
          'department': 'mini_mart',
          'source_department': 'mini_mart',
          'source_type': 'mini_mart_sale',
          'reference_id': firstSaleId,
          'reason': 'Mini Mart sale on credit - ${_currentSale.length} items (Department: mini_mart)',
          'date': DateTime.now().toIso8601String().split('T')[0],
          'status': 'outstanding',
          'sold_by': userId, // Staff who made the sale
          'approved_by': _approvedByController.text.trim().isEmpty 
              ? null 
              : _approvedByController.text.trim(), // Optional approved by
          'sale_id': firstSaleId,
        };
        
        await _dataService.recordDebt(debt);
      }

      if (mounted) {
        ErrorHandler.showLedgerConfirmedSnackBar(
          context,
          'Mini Mart sale saved to ledger. Safe to close.',
        );
        if (_paymentMethod == 'Credit') {
          ErrorHandler.showWarningMessage(
            context,
            'Sale on credit recorded! Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)} - Debt created',
          );
        } else {
          ErrorHandler.showSuccessMessage(
            context,
            'Sale completed! Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)}',
          );
        }
      }

      _clearSale();

      if (mounted) {
        try {
          await _showMiniMartReceiptDialog(
            items: receiptItems,
            totalNaira: receiptTotal,
            paymentMethod: _paymentMethod,
            customerName: customerName,
          );
        } catch (e) {
          if (kDebugMode) debugPrint('DEBUG _showMiniMartReceiptDialog: $e');
        }
        try {
          await _loadMiniMartData();
        } catch (e) {
          if (kDebugMode) debugPrint('DEBUG _loadMiniMartData: $e');
          if (mounted) {
            ErrorHandler.showSuccessMessage(
              context,
              'Sale completed. (Failed to refresh list, please refresh manually.)',
            );
          }
        }
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: ErrorHandler.getAdminErrorMessage(e),
          onRetry: _processSale,
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _processSale: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to process sale. Please check your connection and try again.',
          onRetry: _processSale,
          stackTrace: stackTrace,
        );
      }
    }
    } finally {
      _isProcessingSale = false;
      _notifyMiniMartSaleProcessingChanged();
    }
  }

  void _clearSale() {
    setState(() {
      _currentSale.clear();
      _saleLedgerSessionId = null;
      _saleTotal = 0.0;
      _customerNameController.clear();
      _customerPhoneController.clear();
      _approvedByController.clear();
      _paymentMethod = 'Cash';
    });
  }

  Future<void> _showMiniMartReceiptDialog({
    required List<Map<String, dynamic>> items,
    required double totalNaira,
    required String paymentMethod,
    required String customerName,
  }) async {
    final screenContext = context;
    final receiptText = StringBuffer()
      ..writeln('P-ZED Homes Mini Mart Receipt')
      ..writeln('Customer: $customerName')
      ..writeln('Payment Method: $paymentMethod')
      ..writeln('Items:');

    for (final item in items) {
      final name = item['name']?.toString() ?? 'Item';
      final qty = item['quantity'] ?? 0;
      final price = item['price'] as num? ?? 0;
      receiptText.writeln('- $name x$qty @ ₦${NumberFormat('#,##0.00').format(price)}');
    }

    receiptText
      ..writeln('Total: ₦${NumberFormat('#,##0.00').format(totalNaira)}')
      ..writeln('Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}');

    await showDialog<void>(
      context: screenContext,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Mini Mart Receipt'),
          content: SingleChildScrollView(
            child: SelectableText(receiptText.toString()),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _saveMiniMartReceiptPdf(
                  items: items,
                  totalNaira: totalNaira,
                  paymentMethod: paymentMethod,
                  customerName: customerName,
                );
              },
              child: const Text('Save PDF'),
            ),
            TextButton(
              onPressed: () async {
                await _printMiniMartReceipt(
                  items: items,
                  totalNaira: totalNaira,
                  paymentMethod: paymentMethod,
                  customerName: customerName,
                );
              },
              child: const Text('Print/PDF'),
            ),
            TextButton(
              onPressed: () async {
                await _shareMiniMartReceiptPdf(
                  items: items,
                  totalNaira: totalNaira,
                  paymentMethod: paymentMethod,
                  customerName: customerName,
                );
              },
              child: const Text('Share PDF'),
            ),
            TextButton(
              onPressed: () async {
                await _emailMiniMartReceiptPdf(
                  receiptText: receiptText.toString(),
                  items: items,
                  totalNaira: totalNaira,
                  paymentMethod: paymentMethod,
                  customerName: customerName,
                );
              },
              child: const Text('Email PDF'),
            ),
            TextButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: receiptText.toString()));
                if (!screenContext.mounted) return;
                ErrorHandler.showSuccessMessage(
                  screenContext,
                  'Receipt copied to clipboard',
                );
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _shareMiniMartReceiptPdf({
    required List<Map<String, dynamic>> items,
    required double totalNaira,
    required String paymentMethod,
    required String customerName,
  }) async {
    try {
      final bytes = await _buildMiniMartReceiptPdf(
        items: items,
        totalNaira: totalNaira,
        paymentMethod: paymentMethod,
        customerName: customerName,
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'mini_mart_receipt_${DateTime.now().millisecondsSinceEpoch}.pdf',
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG share receipt: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to share receipt. Please try again.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<Uint8List> _buildMiniMartReceiptPdf({
    required List<Map<String, dynamic>> items,
    required double totalNaira,
    required String paymentMethod,
    required String customerName,
  }) async {
    final doc = pw.Document();
    final dateText = DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now());

    doc.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('P-ZED Homes Mini Mart Receipt', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Text('Customer: $customerName'),
              pw.Text('Payment Method: $paymentMethod'),
              pw.SizedBox(height: 8),
              pw.Text('Items:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              ...items.map((item) {
                final name = item['name']?.toString() ?? 'Item';
                final qty = item['quantity'] ?? 0;
                final price = item['price'] as num? ?? 0;
                return pw.Text('- $name x$qty @ ₦${NumberFormat('#,##0.00').format(price)}');
              }),
              pw.SizedBox(height: 10),
              pw.Text('Total: ₦${NumberFormat('#,##0.00').format(totalNaira)}'),
              pw.SizedBox(height: 12),
              pw.Text('Generated: $dateText', style: const pw.TextStyle(fontSize: 10)),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<void> _saveMiniMartReceiptPdf({
    required List<Map<String, dynamic>> items,
    required double totalNaira,
    required String paymentMethod,
    required String customerName,
  }) async {
    try {
      final bytes = await _buildMiniMartReceiptPdf(
        items: items,
        totalNaira: totalNaira,
        paymentMethod: paymentMethod,
        customerName: customerName,
      );

      final location = await getSaveLocation(
        suggestedName: 'mini_mart_receipt_${DateTime.now().millisecondsSinceEpoch}.pdf',
        acceptedTypeGroups: [const XTypeGroup(label: 'PDF', extensions: ['pdf'])],
      );
      if (location == null) return;

      final file = XFile.fromData(
        bytes,
        mimeType: 'application/pdf',
        name: 'mini_mart_receipt.pdf',
      );
      await file.saveTo(location.path);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Receipt saved to file');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG save receipt: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to save receipt. Please try again.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _printMiniMartReceipt({
    required List<Map<String, dynamic>> items,
    required double totalNaira,
    required String paymentMethod,
    required String customerName,
  }) async {
    try {
      final docBytes = await _buildMiniMartReceiptPdf(
        items: items,
        totalNaira: totalNaira,
        paymentMethod: paymentMethod,
        customerName: customerName,
      );
      await Printing.layoutPdf(
        onLayout: (format) async => docBytes,
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG print receipt: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to generate receipt. Please try again.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _emailMiniMartReceiptPdf({
    required String receiptText,
    required List<Map<String, dynamic>> items,
    required double totalNaira,
    required String paymentMethod,
    required String customerName,
  }) async {
    final email = await _promptForEmailAddress();
    if (email == null || email.isEmpty) return;

    try {
      final bytes = await _buildMiniMartReceiptPdf(
        items: items,
        totalNaira: totalNaira,
        paymentMethod: paymentMethod,
        customerName: customerName,
      );
      await Share.shareXFiles(
        [
          XFile.fromData(
            bytes,
            mimeType: 'application/pdf',
            name: 'mini_mart_receipt_${DateTime.now().millisecondsSinceEpoch}.pdf',
          ),
        ],
        subject: 'P-ZED Homes Mini Mart Receipt',
        text: receiptText,
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG email receipt: $e\n$stackTrace');
      if (mounted) {
        final fallbackUri = Uri(
          scheme: 'mailto',
          path: email,
          queryParameters: {
            'subject': 'P-ZED Homes Mini Mart Receipt',
            'body': receiptText,
          },
        );
        final fallbackOpened = await launchUrl(
          fallbackUri,
          mode: LaunchMode.externalApplication,
        );
        if (!mounted) return;
        if (!fallbackOpened) {
          ErrorHandler.handleError(
            context,
            e,
            customMessage: 'Could not open email client. Please try again.',
            stackTrace: stackTrace,
          );
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
  Widget build(BuildContext context) {
    return Selector<AuthService, ({bool isReceptionist, bool showAddItem})>(
      selector: (_, auth) {
        final u = auth.currentUser;
        final isReceptionist = (u?.roles.any((r) => r.name == 'receptionist') ?? false) ||
            auth.hasAssumedRole(AppRole.receptionist);
        final showAddItem = u?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
        return (isReceptionist: isReceptionist, showAddItem: showAddItem);
      },
      builder: (context, data, child) {
        final isReceptionist = data.isReceptionist;
        final showAddItem = data.showAddItem;
        final tabCount = isReceptionist ? 3 : 2;

        if (_tabController != null && _tabController!.length != tabCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _tabController?.dispose();
                _tabController = TabController(length: tabCount, vsync: this);
              });
            }
          });
        }

        final tabCountMismatch = _tabController!.length != tabCount;
        if (tabCountMismatch) {
          final showLocalRoleButton = MediaQuery.sizeOf(context).width >= 700;
          return Scaffold(
            body: LayeredScrollBody(
              topSection: Container(
                color: Colors.green[700],
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(
                  children: [
                    if (Navigator.of(context).canPop())
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: Colors.white),
                        onPressed: () => context.pop(),
                      ),
                    const Expanded(
                      child: Text(
                        'Mini Mart',
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    if (showLocalRoleButton)
                      const ContextAwareRoleButton(suggestedRole: AppRole.receptionist),
                  ],
                ),
              ),
              content: const Center(child: CircularProgressIndicator()),
            ),
          );
        }

        return Scaffold(
          floatingActionButton: showAddItem
              ? FloatingActionButton(
                  onPressed: _showAddMiniMartItemDialog,
                  backgroundColor: Colors.green[700],
                  child: const Icon(Icons.add, color: Colors.white),
                )
              : null,
          backgroundColor: Colors.grey[50],
          body: LayeredScrollBody(
            topSection: Column(
              children: [
                Container(
                  color: Colors.green[700],
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 620;
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (Navigator.of(context).canPop())
                                IconButton(
                                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                                  onPressed: () => context.pop(),
                                ),
                              const Expanded(
                                child: Text(
                                  'Mini Mart',
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 20,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              if (!isMobile)
                                const ContextAwareRoleButton(suggestedRole: AppRole.receptionist),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                Container(
                  color: Colors.white,
                  child: TabBar(
                    controller: _tabController,
                    labelColor: Colors.green[800],
                    unselectedLabelColor: Colors.grey[600],
                    indicatorColor: Colors.green[800],
                    tabs: [
                      if (isReceptionist) const Tab(text: 'Make Sale', icon: Icon(Icons.shopping_cart)),
                      const Tab(text: 'Sales History', icon: Icon(Icons.history)),
                      const Tab(text: 'Inventory', icon: Icon(Icons.inventory)),
                    ],
                  ),
                ),
              ],
            ),
            content: TabBarView(
              controller: _tabController,
              children: [
                if (isReceptionist) _buildSalesInterface(),
                _buildSalesHistory(),
                _buildInventory(),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSalesInterface() {
    final isMobile = MediaQuery.sizeOf(context).width < 600;
    final gridSection = Expanded(
      flex: 2,
      child: Container(
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                Container(
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
                            final crossAxisCount = width < 800 ? 2 : (width < 1200 ? 3 : 4);
                            return GridView.builder(
                              padding: const EdgeInsets.all(16),
                              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: crossAxisCount,
                                childAspectRatio: 1.0,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                              ),
                              itemCount: _filteredItems.length,
                              itemBuilder: (context, index) {
                                final item = _filteredItems[index];
                                final stock = item['stock_quantity'] as int? ?? 0;
                                final isOutOfStock = stock <= 0;
                                final tableName = ProductCatalogConfig.departmentToTable['mini_mart'] ?? 'mini_mart_items';
                                final showActions = Provider.of<AuthService>(context, listen: false)
                                    .currentUser
                                    ?.roles
                                    .any((r) => r == AppRole.owner || r == AppRole.manager) ??
                                    false;
                                return Stack(
                                  children: [
                                    ProductCard(
                                      name: item['name']?.toString() ?? 'Unknown',
                                      price: '₦${NumberFormat('#,##0.00').format(item['price'])}',
                                      icon: Icons.inventory,
                                      backgroundColor: isOutOfStock ? Colors.orange[50] : Colors.white,
                                      border: isOutOfStock ? Border.all(color: Colors.orange[300]!, width: 1) : null,
                                      onTap: () => _addItemToSale(item),
                                    ),
                                    if (showActions)
                                      Positioned(
                                        top: 16,
                                        right: 16,
                                        child: PopupMenuButton<String>(
                                          padding: EdgeInsets.zero,
                                          child: Container(
                                            width: 28,
                                            height: 28,
                                            decoration: const BoxDecoration(
                                              color: Colors.black38,
                                              shape: BoxShape.circle,
                                            ),
                                            child: const Icon(Icons.more_vert, color: Colors.white, size: 18),
                                          ),
                                          itemBuilder: (context) => const [
                                            PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18), SizedBox(width: 8), Text('Edit')])),
                                            PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete, size: 18, color: Colors.red), SizedBox(width: 8), Text('Delete', style: TextStyle(color: Colors.red))])),
                                          ],
                                          onSelected: (value) async {
                                            if (value == 'edit') {
                                              final productForDialog = {
                                                'id': item['id'],
                                                'name': item['name'],
                                                'category': item['category'],
                                                'price': PaymentService.nairaToKobo((item['price'] as num).toDouble()),
                                              };
                                              await showDialog(
                                                context: context,
                                                builder: (ctx) => ProductFormDialog(
                                                  tableName: tableName,
                                                  product: productForDialog,
                                                  onSave: (updates, [priceChangeDetails]) async {
                                                    try {
                                                      final authService = Provider.of<AuthService>(context, listen: false);
                                                      final staffId = StaffAuthHelper.requireStaffProfileId(
                                                        context,
                                                        authService: authService,
                                                        supabase: _supabase,
                                                      );
                                                      if (staffId == null) return;
                                                      await _dataService.updateProduct(
                                                        tableName,
                                                        item['id'].toString(),
                                                        updates,
                                                      );
                                                      if (priceChangeDetails != null &&
                                                          priceChangeDetails.isNotEmpty &&
                                                          mounted) {
                                                        final department = ProductCatalogConfig
                                                            .tableToDepartmentName[tableName] ?? 'MiniMart';
                                                        await _dataService.logActivity(
                                                          staffId,
                                                          'Price Update',
                                                          department,
                                                          priceChangeDetails,
                                                        );
                                                      }
                                                      if (!context.mounted) return;
                                                      ErrorHandler.showSuccessMessage(context, 'Product updated.');
                                                        _loadMiniMartData();
                                                    } on PostgrestException catch (e) {
                                                      if (!context.mounted) return;
                                                      final message = e.code == '42501'
                                                          ? 'Permission Denied: Only Managers or Owners can change prices.'
                                                          : null;
                                                      ErrorHandler.handleError(context, e, customMessage: message, stackTrace: StackTrace.current);
                                                    } catch (e, stackTrace) {
                                                      if (!context.mounted) return;
                                                      ErrorHandler.handleError(context, e, stackTrace: stackTrace);
                                                    }
                                                  },
                                                ),
                                              );
                                            } else if (value == 'delete') {
                                              await showDeleteProductConfirmation(
                                                context,
                                                productName: item['name']?.toString() ?? 'this item',
                                                onConfirm: () async {
                                                  final authService = Provider.of<AuthService>(context, listen: false);
                                                  final staffId = StaffAuthHelper.requireStaffProfileId(
                                                    context,
                                                    authService: authService,
                                                    supabase: _supabase,
                                                  );
                                                  if (staffId == null) {
                                                    throw Exception('Session expired. Cannot delete without audit.');
                                                  }
                                                  final itemName = item['name']?.toString() ?? 'this item';
                                                  await _dataService.deleteProduct(
                                                    tableName,
                                                    item['id'].toString(),
                                                  );
                                                  final department = ProductCatalogConfig
                                                      .tableToDepartmentName[tableName] ?? 'MiniMart';
                                                  await _dataService.logActivity(
                                                    staffId,
                                                    'Product Deletion',
                                                    department,
                                                    'Deleted $itemName from the catalog.',
                                                  );
                                                  if (!context.mounted) return;
                                                  ErrorHandler.showSuccessMessage(context, 'Product deleted.');
                                                    _loadMiniMartData();
                                                },
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                  ],
                                );
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
    final saleSection = Expanded(
      flex: 1,
      child: Container(
        margin: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(12),
                  topRight: Radius.circular(12),
                ),
              ),
              child: Row(
                children: [
                  const Icon(Icons.shopping_cart, color: Colors.green),
                      const SizedBox(width: 8),
                      const Text(
                        'Current Sale',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '₦${NumberFormat('#,##0.00').format(_saleTotal)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _currentSale.isEmpty
                      ? const Center(
                          child: Text(
                            'No items in cart',
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      : ListView.builder(
                          controller: _currentSaleScrollController,
                          itemCount: _currentSale.length,
                          itemBuilder: (context, index) {
                            final item = _currentSale[index];
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.green[100],
                                child: Text(
                                  '${item['quantity']}',
                                  style: TextStyle(
                                    color: Colors.green[700],
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                item['name']?.toString() ?? 'Unknown',
                                style: const TextStyle(fontSize: 14),
                              ),
                              subtitle: Text(
                                '₦${NumberFormat('#,##0.00').format(item['price'])} each',
                                style: const TextStyle(fontSize: 12),
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: const Icon(Icons.remove, size: 16),
                                    onPressed: () => _updateItemQuantity(
                                      index,
                                      (item['quantity'] as int) - 1,
                                    ),
                                  ),
                                  Text('${item['quantity']}'),
                                  IconButton(
                                    icon: const Icon(Icons.add, size: 16),
                                    onPressed: () => _updateItemQuantity(
                                      index,
                                      (item['quantity'] as int) + 1,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
                if (_currentSale.isNotEmpty) ...[
                  const Divider(),
                  Container(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        DropdownButtonFormField<String>(
                          initialValue: _paymentMethod,
                          decoration: const InputDecoration(
                            labelText: 'Payment Method',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: const [
                            DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                            DropdownMenuItem(value: 'Card', child: Text('Card')),
                            DropdownMenuItem(value: 'Transfer', child: Text('Transfer')),
                            DropdownMenuItem(value: 'Credit', child: Text('Credit (Pay Later)')),
                          ],
                          onChanged: (value) {
                            setState(() {
                              _paymentMethod = value!;
                              if (_paymentMethod != 'Credit') {
                                _dismissCreditSalesWarning = false;
                              }
                            });
                          },
                        ),
                        
                        if (_paymentMethod == 'Credit')
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              if (!_dismissCreditSalesWarning)
                                Container(
                                  margin: const EdgeInsets.only(bottom: 12),
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: Colors.orange[50],
                                    border: Border.all(color: Colors.orange[300]!),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Customer name and phone are required for credit sales. This will be recorded as a debt.',
                                          style: TextStyle(color: Colors.orange[900], fontSize: 12),
                                        ),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.close, size: 18),
                                        color: Colors.orange[800],
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(),
                                        tooltip: 'Dismiss',
                                        onPressed: () {
                                          setState(() => _dismissCreditSalesWarning = true);
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                              TextField(
                                controller: _customerNameController,
                                decoration: const InputDecoration(
                                  labelText: 'Customer Name *',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _customerPhoneController,
                                decoration: const InputDecoration(
                                  labelText: 'Phone *',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _approvedByController,
                                decoration: const InputDecoration(
                                  labelText: 'Approved By (Optional)',
                                  hintText: 'Enter name of supervisor/staff who approved',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ],
                          ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: (_currentSale.isEmpty || _isProcessingSale) ? null : _clearSale,
                                child: const Text('Clear'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: (_currentSale.isEmpty || _isProcessingSale) ? null : _processSale,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[800],
                                  foregroundColor: Colors.white,
                                ),
                                child: _isProcessingSale
                                    ? const SizedBox(
                                        height: 22,
                                        width: 22,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                      )
                                    : const Text('Process Sale'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
    );
    if (isMobile) {
      return Column(
        children: [
          Expanded(child: gridSection),
          if (_currentSale.isNotEmpty) _buildMiniMartMobileSaleBar(),
        ],
      );
    }
    return Row(children: [gridSection, saleSection]);
  }

  Widget _buildMiniMartMobileSaleBar() {
    return Material(
      elevation: 8,
      child: InkWell(
        onTap: _showMiniMartCartModal,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          color: Colors.white,
          child: SafeArea(
            top: false,
            child: Row(
              children: [
                const Icon(Icons.shopping_cart, color: Colors.green),
                const SizedBox(width: 12),
                Text(
                  'Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    color: Colors.green,
                  ),
                ),
                const Spacer(),
                const Icon(Icons.keyboard_arrow_up, color: Colors.grey),
                const SizedBox(width: 4),
                const Text('View Cart', style: TextStyle(fontWeight: FontWeight.w500)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showMiniMartCartModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          _miniMartSaleModalSetState = setModalState;
          return SafeArea(
            child: Container(
              height: MediaQuery.of(context).size.height * 0.7,
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
              ),
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        const Text('Current Sale', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        const Spacer(),
                        Text(
                          '₦${NumberFormat('#,##0.00').format(_saleTotal)}',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: _isProcessingSale ? null : () => Navigator.pop(context),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _currentSale.isEmpty
                        ? const Center(child: Text('No items in cart', style: TextStyle(color: Colors.grey)))
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            itemCount: _currentSale.length,
                            itemBuilder: (context, index) {
                              final item = _currentSale[index];
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: Colors.green[100],
                                  child: Text(
                                    '${item['quantity']}',
                                    style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Text(item['name']?.toString() ?? 'Unknown'),
                                subtitle: Text('₦${NumberFormat('#,##0.00').format(item['price'])} each'),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.remove, size: 16),
                                      onPressed: () {
                                        _updateItemQuantity(index, (item['quantity'] as int) - 1);
                                        setModalState(() {});
                                      },
                                    ),
                                    Text('${item['quantity']}'),
                                    IconButton(
                                      icon: const Icon(Icons.add, size: 16),
                                      onPressed: () {
                                        _updateItemQuantity(index, (item['quantity'] as int) + 1);
                                        setModalState(() {});
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 8,
                          offset: const Offset(0, -2),
                        ),
                      ],
                    ),
                    child: _buildMiniMartMobileSaleSheetActions(
                      onClose: () => Navigator.pop(context),
                      onUpdate: () => setModalState(() {}),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).whenComplete(() => _miniMartSaleModalSetState = null);
  }

  Widget _buildMiniMartMobileSaleSheetActions({
    VoidCallback? onClose,
    VoidCallback? onUpdate,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _paymentMethod,
          decoration: const InputDecoration(
            labelText: 'Payment Method',
            border: OutlineInputBorder(),
            isDense: true,
          ),
          items: const [
            DropdownMenuItem(value: 'Cash', child: Text('Cash')),
            DropdownMenuItem(value: 'Card', child: Text('Card')),
            DropdownMenuItem(value: 'Transfer', child: Text('Transfer')),
            DropdownMenuItem(value: 'Credit', child: Text('Credit (Pay Later)')),
          ],
          onChanged: (value) => setState(() => _paymentMethod = value!),
        ),
        if (_paymentMethod == 'Credit')
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 12),
              TextField(
                controller: _customerNameController,
                decoration: const InputDecoration(
                  labelText: 'Customer Name *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _customerPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone *',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _approvedByController,
                decoration: const InputDecoration(
                  labelText: 'Approved By (Optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: (_currentSale.isEmpty || _isProcessingSale)
                    ? null
                    : () {
                        _clearSale();
                        onUpdate?.call();
                        onClose?.call();
                      },
                child: const Text('Clear'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                onPressed: (_currentSale.isEmpty || _isProcessingSale)
                    ? null
                    : () async {
                        await _processSale();
                        if (context.mounted && _currentSale.isEmpty) onClose?.call();
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green[800],
                  foregroundColor: Colors.white,
                ),
                child: _isProcessingSale
                    ? const SizedBox(
                        height: 22,
                        width: 22,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Process Sale'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSalesHistory() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final authService = Provider.of<AuthService>(context, listen: false);
    final isManagement = authService.currentUser?.roles
            .any((r) => r == AppRole.owner || r == AppRole.manager) ??
        false;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(
                    'Sales History',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_salesHistory.length} Sales',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (_salesHistory.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                child: const Center(
                  child: Text('No sales recorded yet'),
                ),
              )
            else
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _loadMiniMartData,
                  child: ScrollableListViewWithArrows(
                    controller: _salesHistoryScrollController,
                    itemCount: _salesHistory.length + (_salesHistoryLoadingMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index >= _salesHistory.length) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      final sale = _salesHistory[index];
                      final itemName = (sale['mini_mart_items'] as Map<String, dynamic>?)?['name']?.toString() ?? 'Item';
                      final qty = sale['quantity'] as int? ?? 1;
                      final staffName = (sale['sold_by_profile'] as Map<String, dynamic>?)?['full_name']?.toString() ?? 'Unknown Staff';
                      final paymentMethod = sale['payment_method']?.toString() ?? 'N/A';
                      final saleDate = sale['sale_date']?.toString();
                      final timestamp = saleDate != null && saleDate.isNotEmpty
                          ? DateFormat('MMM dd, yyyy HH:mm').format(DateTime.parse(saleDate))
                          : 'N/A';
                      final totalKobo = sale['total_amount'] as int? ?? 0;
                      return SaleListItem(
                        productName: itemName,
                        quantity: qty,
                        staffName: staffName,
                        showStaffName: isManagement,
                        paymentMethod: paymentMethod,
                        timestamp: timestamp,
                        totalAmountKobo: totalKobo,
                        icon: Icons.receipt,
                        iconColor: Colors.green[700]!,
                      );
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventory() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  Text(
                    'Mini Mart Inventory',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey[800],
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '${_miniMartItems.length} Items',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
            if (_miniMartItems.isEmpty)
              Container(
                padding: const EdgeInsets.all(40),
                child: const Center(
                  child: Text('No items in mini mart'),
                ),
              )
            else
              Expanded(
                child: ScrollableListViewWithArrows(
                  itemCount: _miniMartItems.length,
                  itemBuilder: (context, index) {
                    final item = _miniMartItems[index];
                    final stock = item['stock_quantity'] as int? ?? 0; // Schema uses 'stock_quantity' not 'current_stock'
                    final isLowStock = stock <= 5;
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isLowStock ? Colors.red[100] : Colors.green[100],
                        child: Icon(
                          Icons.inventory,
                          color: isLowStock ? Colors.red[700] : Colors.green[700],
                        ),
                      ),
                      title: Text(
                        item['name']?.toString() ?? 'Unknown',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Price: ₦${NumberFormat('#,##0.00').format(item['price'])}'),
                          Text(
                            'Stock: $stock',
                            style: TextStyle(
                              color: isLowStock ? Colors.red : Colors.grey[600],
                              fontWeight: isLowStock ? FontWeight.bold : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                      trailing: isLowStock
                          ? Chip(
                              label: const Text('Low Stock'),
                              backgroundColor: Colors.red[100],
                              labelStyle: TextStyle(color: Colors.red[700]),
                            )
                          : null,
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}


