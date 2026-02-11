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
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:pzed_homes/presentation/widgets/scrollable_list_with_arrows.dart';
import 'package:flutter/services.dart';
import 'dart:typed_data';
import 'package:file_selector/file_selector.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

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
      throw Exception('Supabase not initialized');
    }
  }
  
  // Sales data
  List<Map<String, dynamic>> _miniMartItems = [];
  List<Map<String, dynamic>> _currentSale = [];
  List<Map<String, dynamic>> _salesHistory = [];
  double _saleTotal = 0.0;
  bool _isLoading = true;
  
  // Customer info
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _approvedByController = TextEditingController(); // For credit sales
  String _paymentMethod = 'Cash';
  
  // Search
  final _searchController = TextEditingController();
  final ScrollController _currentSaleScrollController = ScrollController();
  List<Map<String, dynamic>> _filteredItems = [];
  Timer? _filterDebounce;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadMiniMartData();
    _searchController.addListener(_onSearchChanged);
  }

  /// Debounced: avoid filtering on every keystroke; reduces main-thread workload during typing.
  void _onSearchChanged() {
    _filterDebounce?.cancel();
    _filterDebounce = Timer(const Duration(milliseconds: 150), () {
      if (mounted) _filterItems();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Tab controller will be updated in build method via Consumer
  }

  @override
  void dispose() {
    _filterDebounce?.cancel();
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _currentSaleScrollController.dispose();
    _tabController?.dispose();
    _customerNameController.dispose();
    _customerPhoneController.dispose();
    _approvedByController.dispose();
    super.dispose();
  }

  Future<void> _loadMiniMartData() async {
    try {
      // Load mini mart items from mock data
      final itemsResponse = await _dataService.getMiniMartItems();
      
      // Load sales history from mock data
      final salesResponse = await _dataService.getMiniMartSales(limit: 1000);

      if (mounted) {
        final items = List<Map<String, dynamic>>.from(itemsResponse)
            .map((item) {
          final priceKobo = (item['price'] as num?)?.toInt() ?? 0;
          return {
            ...item,
            // Normalize to naira for all UI calculations/display
            'price': PaymentService.koboToNaira(priceKobo),
          };
        }).toList();
        setState(() {
          _miniMartItems = items;
          _filteredItems = items;
          _salesHistory = List<Map<String, dynamic>>.from(salesResponse);
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

  Future<void> _processSale() async {
    if (_currentSale.isEmpty) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please add items to the sale',
        );
      }
      return;
    }

    // Verify user is logged in (clock-in no longer required for transactions)
    final authService = Provider.of<AuthService>(context, listen: false);
    if (authService.currentUser == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'You must be logged in to make transactions',
        );
      }
      return;
    }

    // Validate credit payment requirements
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
      final userId = authService.currentUser?.id ?? 'system';
      final customerName = _customerNameController.text.trim().isNotEmpty 
          ? _customerNameController.text.trim() 
          : 'Walk-in Customer';
      final customerPhone = _customerPhoneController.text.trim();
      final saleDate = DateTime.now().toIso8601String();
      
      // Create one mini_mart_sales record per item (schema supports single item per record)
      // _currentSale structure: {'id': itemId, 'name': itemName, 'price': price, 'quantity': quantity, ...}
      String? firstSaleId;
      for (final saleItem in _currentSale) {
        final itemId = saleItem['id'] as String;
        final quantity = saleItem['quantity'] as int;
        // Price from mini_mart_items is already in kobo (per schema)
        // But UI displays in naira, so saleItem['price'] is in naira
        // Convert naira to kobo for database storage
        final priceInNaira = (saleItem['price'] as num).toDouble();
        final priceInKobo = PaymentService.nairaToKobo(priceInNaira);
        final totalAmountInKobo = quantity * priceInKobo;

        // CRITICAL: Validate stock availability and update atomically to prevent race conditions
        // Use a single query with WHERE clause to ensure stock is still available
        final itemData = await _supabase
            .from('mini_mart_items')
            .select('stock_quantity, name, unit')
            .eq('id', itemId)
            .single();
        
        final currentStock = (itemData['stock_quantity'] as int?) ?? 0;
        final itemName = itemData['name'] as String? ?? 'Item';
        final unit = itemData['unit'] as String? ?? 'units';
        
        // Check stock for warning (non-blocking)
        // Sales are allowed even with zero/negative stock to accommodate delayed stock updates
        if (currentStock < quantity && mounted) {
          debugPrint('Warning: Low stock for $itemName. Available: $currentStock $unit, Requested: $quantity. Sale will proceed and may result in negative stock.');
        }

        // Calculate new stock (may be negative)
        final newStock = currentStock - quantity;

        // Update stock atomically (allows negative stock)
        // Removed .gte() constraint to allow negative stock when management delays updates
        final updateResponse = await _supabase
            .from('mini_mart_items')
            .update({'stock_quantity': newStock})
            .eq('id', itemId)
            .select('id')
            .maybeSingle();

        // If update returned null, item may have been deleted
        if (updateResponse == null) {
          throw Exception(
            'Item $itemName not found or was deleted. Please refresh and try again.'
          );
        }

        // Create sale record for this item (after stock update succeeded)
        final saleResponse = await _supabase
            .from('mini_mart_sales')
            .insert({
              'item_id': itemId,
              'quantity': quantity,
              'unit_price': priceInKobo, // In kobo
              'total_amount': totalAmountInKobo, // In kobo
              'sale_date': saleDate,
              'payment_method': _paymentMethod.toLowerCase(),
              'customer_name': customerName,
              'sold_by': userId,
            })
            .select('id')
            .maybeSingle();
        if (firstSaleId == null && saleResponse != null) {
          firstSaleId = saleResponse['id'] as String?;
        }
      }

      // Calculate total sale amount in kobo for debt/income records
      final saleTotalInKobo = (_saleTotal * 100).toInt();

      // Create or update department_sales record (paid sales only)
      if (_paymentMethod.toLowerCase() != 'credit') {
        final today = DateTime.now().toIso8601String().split('T')[0];
        try {
          final existingSales = await _supabase
              .from('department_sales')
              .select()
              .eq('department', 'mini_mart')
              .eq('date', today)
              .maybeSingle();

          final paymentBreakdown = <String, int>{_paymentMethod.toLowerCase(): saleTotalInKobo};

          if (existingSales != null) {
            // Update existing record (only if same staff_id or NULL)
            final existingStaffId = existingSales['staff_id'] as String?;
            // Only update if it's the same staff member or aggregate (NULL)
            if (existingStaffId == null || existingStaffId == userId) {
              final currentBreakdown = (existingSales['payment_method_breakdown'] as Map<String, dynamic>?) ?? <String, dynamic>{};
              final updatedBreakdown = Map<String, dynamic>.from(currentBreakdown);
              final currentMethodTotal = (updatedBreakdown[_paymentMethod.toLowerCase()] as int? ?? 0);
              updatedBreakdown[_paymentMethod.toLowerCase()] = currentMethodTotal + saleTotalInKobo;

              await _supabase
                  .from('department_sales')
                  .update({
                    'total_sales': (existingSales['total_sales'] as int) + saleTotalInKobo,
                    'transaction_count': (existingSales['transaction_count'] as int) + 1,
                    'payment_method_breakdown': updatedBreakdown,
                    'staff_id': userId, // Set staff_id if it was NULL, or keep existing
                  })
                  .eq('id', existingSales['id']);
            } else {
              // Different staff member - create separate record for this staff
              await _supabase
                  .from('department_sales')
                  .insert({
                    'department': 'mini_mart',
                    'date': today,
                    'total_sales': saleTotalInKobo,
                    'transaction_count': 1,
                    'payment_method_breakdown': paymentBreakdown,
                    'recorded_by': userId,
                    'staff_id': userId,
                  });
            }
          } else {
            await _supabase
                .from('department_sales')
                .insert({
                  'department': 'mini_mart',
                  'date': today,
                  'total_sales': saleTotalInKobo,
                  'transaction_count': 1,
                  'payment_method_breakdown': paymentBreakdown,
                  'recorded_by': userId,
                  'staff_id': userId, // Track which staff member made the sales
                });
          }
        } catch (e, stack) {
          if (kDebugMode) debugPrint('DEBUG department_sales record: $e\n$stack');
        }
      }

      // Capture receipt data before clearing
      final receiptItems = List<Map<String, dynamic>>.from(_currentSale);
      final receiptTotal = _saleTotal;

      // If credit payment, record as debt (amount in kobo)
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
        
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Sale on credit recorded! Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)} - Debt created',
          );
        }
      } else {
        if (mounted) {
          ErrorHandler.showSuccessMessage(
            context,
            'Sale completed! Total: ₦${NumberFormat('#,##0.00').format(_saleTotal)}',
          );
        }
      }

      if (mounted) {
        await _showMiniMartReceiptDialog(
          items: receiptItems,
          totalNaira: receiptTotal,
          paymentMethod: _paymentMethod,
          customerName: customerName,
        );
      }

      // Clear sale
      _clearSale();

      await _loadMiniMartData();
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
  }

  void _clearSale() {
    setState(() {
      _currentSale.clear();
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
      context: context,
      barrierDismissible: true,
      builder: (context) {
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
                if (mounted) {
                  ErrorHandler.showSuccessMessage(
                    context,
                    'Receipt copied to clipboard',
                  );
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
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        final user = authService.currentUser;
        final isReceptionist = (user?.roles.any((r) => r.name == 'receptionist') ?? false) ||
            authService.hasAssumedRole(AppRole.receptionist);

        // Update tab controller if needed
        final tabCount = isReceptionist ? 3 : 2;
        if (_tabController == null) {
          _tabController = TabController(length: tabCount, vsync: this);
        } else if (_tabController!.length != tabCount) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              setState(() {
                _tabController?.dispose();
                _tabController = TabController(length: tabCount, vsync: this);
              });
            }
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('Mini Mart', overflow: TextOverflow.ellipsis, maxLines: 1),
            backgroundColor: Colors.green[700],
            foregroundColor: Colors.white,
            leading: Navigator.of(context).canPop() ? IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.pop(),
            ) : null,
            actions: [
              ContextAwareRoleButton(suggestedRole: AppRole.receptionist),
            ],
          ),
          backgroundColor: Colors.grey[50],
          body: Column(
            children: [
              _buildHeader(context),
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
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    if (isReceptionist) _buildSalesInterface(),
                    _buildSalesHistory(),
                    _buildInventory(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mini Mart Sales',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Manage mini mart sales and inventory',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.store, color: Colors.green[700], size: 16),
                const SizedBox(width: 8),
                Text(
                  'Mini Mart',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
                  color: Colors.black.withOpacity(0.05),
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
                            final stock = item['stock_quantity'] as int? ?? 0; // Schema uses 'stock_quantity' not 'current_stock'
                            final isOutOfStock = stock <= 0;
                            
                            return Card(
                              elevation: 2,
                              child: InkWell(
                                onTap: () => _addItemToSale(item), // Always allow selection, even with zero stock
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    color: isOutOfStock ? Colors.orange[50] : Colors.white, // Warning color instead of disabled
                                    border: isOutOfStock ? Border.all(color: Colors.orange[300]!, width: 1) : null, // Visual indicator
                                    borderRadius: BorderRadius.circular(8),
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
                                          child: const Icon(Icons.inventory, size: 18),
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
                                        '₦${NumberFormat('#,##0.00').format(item['price'])}',
                                        style: TextStyle(
                                          color: Colors.green[700],
                                          fontWeight: FontWeight.bold,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(height: 1),
                                      Text(
                                        'Stock: $stock${isOutOfStock ? ' (Low)' : ''}',
                                        style: TextStyle(
                                          color: isOutOfStock ? Colors.orange[700] : Colors.grey[600], // Warning color
                                          fontSize: 9,
                                          fontWeight: isOutOfStock ? FontWeight.w600 : FontWeight.normal,
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
              color: Colors.black.withOpacity(0.05),
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
                          value: _paymentMethod,
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
                            });
                          },
                        ),
                        
                        // Show customer info fields only for credit payment
                        if (_paymentMethod == 'Credit')
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 16),
                              Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.orange[50],
                                  border: Border.all(color: Colors.orange[300]!),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Customer name and phone are required for credit sales. This will be recorded as a debt.',
                                        style: TextStyle(color: Colors.orange[900], fontSize: 12),
                                      ),
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
                                onPressed: _clearSale,
                                child: const Text('Clear'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: _processSale,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[800],
                                  foregroundColor: Colors.white,
                                ),
                                child: const Text('Process Sale'),
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
    return isMobile
        ? Column(children: [gridSection, saleSection])
        : Row(children: [gridSection, saleSection]);
  }

  Widget _buildSalesHistory() {
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
              color: Colors.black.withOpacity(0.05),
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
                child: ScrollableListViewWithArrows(
                  itemCount: _salesHistory.length,
                  itemBuilder: (context, index) {
                    final sale = _salesHistory[index];
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: Colors.green[100],
                        child: Icon(Icons.receipt, color: Colors.green[700]),
                      ),
                      title: Text(
                        sale['customer_name']?.toString() ?? 'Walk-in Customer',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Payment: ${sale['payment_method']?.toString() ?? 'N/A'}'),
                          Text(
                            'Date: ${sale['sale_date'] != null ? DateFormat('MMM dd, yyyy HH:mm').format(DateTime.parse(sale['sale_date'])) : 'N/A'}',
                            style: TextStyle(color: Colors.grey[600], fontSize: 12),
                          ),
                        ],
                      ),
                      trailing: Text(
                        '₦${NumberFormat('#,##0.00').format(PaymentService.koboToNaira(sale['total_amount'] as int? ?? 0))}',
                        style: TextStyle(
                          color: Colors.green[700],
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    );
                  },
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
              color: Colors.black.withOpacity(0.05),
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
