import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/presentation/screens/assign_room_screen.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';

class Booking {
  final String id;
  final String guestName;
  final String roomType;
  final String? roomNumber; // Nullable - room may not be assigned yet
  final String? roomId; // Nullable - room may not be assigned yet
  final String? requestedRoomType; // Room type requested by guest
  final String status;
  final List<Map<String, dynamic>> extraCharges;
  final DateTime checkInDate;
  final DateTime checkOutDate;

  Booking({
    required this.id,
    required this.guestName,
    required this.roomType,
    this.roomNumber,
    this.roomId,
    this.requestedRoomType,
    required this.status,
    required this.extraCharges,
    required this.checkInDate,
    required this.checkOutDate,
  });

  Booking copyWith({
    String? status,
    List<Map<String, dynamic>>? extraCharges,
    String? roomNumber,
    String? roomId,
  }) {
    return Booking(
      id: id,
      guestName: guestName,
      roomType: roomType,
      roomNumber: roomNumber ?? this.roomNumber,
      roomId: roomId ?? this.roomId,
      requestedRoomType: requestedRoomType,
      status: status ?? this.status,
      extraCharges: extraCharges ?? this.extraCharges,
      checkInDate: checkInDate,
      checkOutDate: checkOutDate,
    );
  }
}

class BookingDetailsScreen extends StatefulWidget {
  final Booking booking;

  const BookingDetailsScreen({super.key, required this.booking});

  @override
  State<BookingDetailsScreen> createState() => _BookingDetailsScreenState();
}

class _BookingDetailsScreenState extends State<BookingDetailsScreen> {
  late Booking _currentBooking;
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      throw Exception('Supabase not initialized');
    }
  }
  int _roomBasePriceKobo = 0;
  bool _isLoading = false;
  final _dataService = DataService();
  List<Map<String, dynamic>> _bookingDebts = [];
  List<Map<String, dynamic>> _bookingCharges = [];

  @override
  void initState() {
    super.initState();
    _currentBooking = widget.booking;
    _fetchRoomPrice();
    _loadBookingDebts();
    _loadBookingCharges();
  }

  Future<void> _fetchRoomPrice() async {
    try {
      // Query room_types table, not menu_items - room prices are stored in room_types
      final priceResponse = await _supabase
          .from('room_types')
          .select('price')
          .eq('type', _currentBooking.roomType) // Use exact match, not LIKE
          .maybeSingle();
      
      if (priceResponse != null) {
        final priceInKobo = priceResponse['price'] as int? ?? 0;
        setState(() {
          _roomBasePriceKobo = priceInKobo;
        });
      } else {
        // Room type not found - set to 0 or show error
        setState(() {
          _roomBasePriceKobo = 0;
        });
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG fetch room price: $e\n$stack');
      setState(() {
        _roomBasePriceKobo = 0;
      });
    }
  }

  int get _extraChargesTotal {
    final jsonCharges = _currentBooking.extraCharges
        .fold(0, (sum, item) => sum + (item['price'] as int));
    final tableCharges = _bookingCharges.fold<int>(0, (sum, item) {
      final price = (item['price'] as num?)?.toInt() ?? 0;
      final qty = (item['quantity'] as num?)?.toInt() ?? 1;
      return sum + (price * qty);
    });
    return jsonCharges + tableCharges;
  }

  int get _totalBillKobo {
    return _roomBasePriceKobo + _extraChargesTotal;
  }

  Future<void> _performCheckIn() async {
    try {
      // Check if room is assigned
      if (_currentBooking.roomId == null) {
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'Room must be assigned before check-in. Please assign a room first.',
            duration: const Duration(seconds: 4),
          );
        }
        // Navigate to room assignment screen
        final assigned = await Navigator.push<bool>(
          context,
          MaterialPageRoute(
            builder: (context) => AssignRoomScreen(booking: _currentBooking),
          ),
        );
        if (assigned != true) return;
        // Reload booking data after assignment
        await _reloadBooking();
        return;
      }

      // Show confirmation dialog
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Confirm Check-in'),
          content: const Text(
            'Are you sure you want to check in this guest? This action cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      setState(() => _isLoading = true);

      // Use database function for check-in (handles status updates correctly)
      if (_supabase == null) {
        throw Exception('Supabase not initialized');
      }
      final result = await _supabase.rpc('check_in_guest', params: {
        'booking_id': _currentBooking.id,
      });

      if (result == true) {
        // Update local state
        setState(() {
          _currentBooking = _currentBooking.copyWith(status: 'Checked-in');
          _isLoading = false;
        });

        // Show success message
        if (mounted) {
          ErrorHandler.showSuccessMessage(
            context,
            'Guest checked in successfully!',
          );
        }

        // Return updated booking to previous screen
        if (mounted) {
          Navigator.of(context).pop(_currentBooking);
        }
      } else {
        throw Exception('Check-in failed. Please ensure room is assigned and booking is in correct status.');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG check in: $e\n$stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to check in guest. Please try again.',
          onRetry: _performCheckIn,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _reloadBooking() async {
    try {
      final bookingData = await _supabase
          .from('bookings')
          .select('''
            id,
            created_at,
            guest_profile_id,
            room_id,
            requested_room_type,
            check_in_date,
            check_out_date,
            status,
            total_amount,
            paid_amount,
            extra_charges,
            notes,
            created_by,
            updated_at,
            payment_method,
            guest_name,
            guest_email,
            guest_phone,
            rooms(*),
            profiles!guest_profile_id(*)
          ''')
          .eq('id', _currentBooking.id)
          .single();

      final room = bookingData['rooms'] as Map<String, dynamic>?;
      final profile = bookingData['profiles'] as Map<String, dynamic>?;
      
      setState(() {
        _currentBooking = Booking(
          id: bookingData['id'] as String,
          guestName: profile?['full_name'] as String? ?? 'Unknown',
          roomType: bookingData['requested_room_type'] as String? ?? 
                    room?['type'] as String? ?? 
                    'Unknown',
          roomNumber: room?['room_number'] as String?,
          roomId: bookingData['room_id'] as String?,
          requestedRoomType: bookingData['requested_room_type'] as String?,
          status: bookingData['status'] as String? ?? 'Pending Check-in',
          extraCharges: List<Map<String, dynamic>>.from(
            bookingData['extra_charges'] as List? ?? []
          ),
          checkInDate: DateTime.parse(bookingData['check_in_date'] as String),
          checkOutDate: DateTime.parse(bookingData['check_out_date'] as String),
        );
      });
      await _loadBookingDebts();
      await _loadBookingCharges();
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG reload booking: $e\n$stack');
    }
  }

  Future<void> _loadBookingCharges() async {
    try {
      final charges = await _dataService.getBookingCharges(_currentBooking.id);
      if (mounted) {
        setState(() => _bookingCharges = charges);
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _loadBookingCharges: $e\n$stack');
    }
  }

  Future<void> _loadBookingDebts() async {
    try {
      final debts = await _dataService.getDebts(
        bookingId: _currentBooking.id,
      );
      if (mounted) {
        setState(() => _bookingDebts = debts);
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _loadBookingDebts: $e\n$stack');
    }
  }

  Future<void> _addCharge(String itemName, int price) async {
    setState(() => _isLoading = true);
    try {
      final newCharges = List<Map<String, dynamic>>.from(_currentBooking.extraCharges);
      newCharges.add({'item': itemName, 'price': price * 100});

      await _supabase
          .from('bookings')
          .update({'extra_charges': newCharges})
          .eq('id', _currentBooking.id);

      setState(() {
        _currentBooking = _currentBooking.copyWith(
          extraCharges: newCharges,
        );
      });
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Charge added successfully!');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG add charge: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to add charge. Please try again.',
          onRetry: () => _addCharge(itemName, price),
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _performCheckOut() async {
    if (_currentBooking.roomId == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Cannot check out: No room assigned to this booking.',
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    try {
      // Use database function for check-out (handles status updates correctly)
      if (_supabase == null) {
        throw Exception('Supabase not initialized');
      }
      final result = await _supabase.rpc('check_out_guest', params: {
        'booking_id': _currentBooking.id,
      });

      if (result == true) {
        if (mounted) {
          setState(() {
            _currentBooking = _currentBooking.copyWith(status: 'Checked-out');
          });
          ErrorHandler.showSuccessMessage(
            context,
            'Guest checked out successfully. Room marked as dirty.',
          );
        }
      } else {
        throw Exception('Check-out failed. Please ensure booking is in correct status.');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG check out: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to check out guest. Please try again.',
          onRetry: _performCheckOut,
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showAddChargeDialog() {
    final formKey = GlobalKey<FormState>();
    final itemController = TextEditingController();
    final priceController = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add New Charge'),
        content: Form(
          key: formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: itemController,
                decoration: const InputDecoration(labelText: 'Item Name'),
                validator: (val) => val!.isEmpty ? 'Enter an item name' : null,
              ),
              TextFormField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Price (NGN)'),
                keyboardType: TextInputType.number,
                validator: (val) {
                  if (val!.isEmpty) return 'Enter a price';
                  if (int.tryParse(val) == null) return 'Enter a valid number';
                  return null;
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                _addCharge(itemController.text, int.parse(priceController.text));
                context.pop();
              }
            },
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }

  void _showCheckOutConfirmation() {
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');
    final outstandingDebts = _bookingDebts.where((d) {
      final status = d['status']?.toString();
      return status == 'outstanding' || status == 'partially_paid';
    }).toList();
    final outstandingTotal = outstandingDebts.fold<int>(0, (sum, d) {
      final amount = (d['amount'] as num?)?.toInt() ?? 0;
      final paid = (d['paid_amount'] as num?)?.toInt() ?? 0;
      final remaining = amount - paid;
      return sum + (remaining > 0 ? remaining : 0);
    });
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Check-out'),
        content: Text(
          'The total bill for ${_currentBooking.guestName} is ${currencyFormatter.format(PaymentService.koboToNaira(_totalBillKobo))}.'
          '${outstandingTotal > 0 ? '\n\nOutstanding debts: ${currencyFormatter.format(PaymentService.koboToNaira(outstandingTotal))}.' : ''}'
          '\n\nProceed with check-out?'
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          if (outstandingTotal > 0)
            TextButton(
              onPressed: () {
                context.pop();
                _showDebtSettlementDialog(outstandingDebts);
              },
              child: const Text('Settle Debts'),
            ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.pop();
              if (outstandingTotal > 0) {
                _showCheckoutWithoutSettlement(outstandingTotal);
              } else {
                _performCheckOut();
              }
            },
            child: const Text('Check-out Now'),
          ),
        ],
      ),
    );
  }

  void _showCheckoutWithoutSettlement(int outstandingTotal) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Proceed Without Payment?'),
        content: Text(
          'Outstanding debt is ${currencyFormatter.format(PaymentService.koboToNaira(outstandingTotal))}.\n'
          'Checkout will proceed and debts will remain unpaid.\n\nContinue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              Navigator.of(ctx).pop();
              _performCheckOut();
            },
            child: const Text('Proceed'),
          ),
        ],
      ),
    );
  }

  void _showDebtSettlementDialog(List<Map<String, dynamic>> debts) {
    User? authService;
    try {
      authService = Supabase.instance.client.auth.currentUser;
    } catch (_) {
      authService = null;
    }
    if (authService == null) {
      ErrorHandler.showWarningMessage(
        context,
        'Supabase not initialized. Please try again.',
      );
      return;
    }
    final staffId = authService?.id;
    if (staffId == null) {
      ErrorHandler.showWarningMessage(
        context,
        'You must be logged in to record payments.',
      );
      return;
    }

    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');
    final paymentMethod = ValueNotifier<String>('cash');
    final controllers = <String, TextEditingController>{};
    final remainingByDebt = <String, int>{};

    for (final debt in debts) {
      final id = debt['id'] as String;
      final amount = (debt['amount'] as num?)?.toInt() ?? 0;
      final paid = (debt['paid_amount'] as num?)?.toInt() ?? 0;
      final remaining = amount - paid;
      remainingByDebt[id] = remaining;
      controllers[id] = TextEditingController(
        text: PaymentService.koboToNaira(remaining).toStringAsFixed(2),
      );
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('Settle Outstanding Debts'),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: ValueListenableBuilder<String>(
                valueListenable: paymentMethod,
                builder: (context, method, _) {
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DropdownButtonFormField<String>(
                        value: method,
                        decoration: const InputDecoration(
                          labelText: 'Payment Method',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'cash', child: Text('Cash')),
                          DropdownMenuItem(value: 'card', child: Text('Card')),
                          DropdownMenuItem(value: 'transfer', child: Text('Transfer')),
                        ],
                        onChanged: (val) => paymentMethod.value = val ?? 'cash',
                      ),
                      const SizedBox(height: 16),
                      ...debts.map((debt) {
                        final id = debt['id'] as String;
                        final remaining = remainingByDebt[id] ?? 0;
                        final reason = debt['reason']?.toString() ?? 'Debt';
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$reason • Remaining ${currencyFormatter.format(PaymentService.koboToNaira(remaining))}',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                              const SizedBox(height: 8),
                              TextFormField(
                                controller: controllers[id],
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'Amount to collect (₦)',
                                  border: OutlineInputBorder(),
                                ),
                              ),
                            ],
                          ),
                        );
                      }),
                    ],
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                for (final debt in debts) {
                  final id = debt['id'] as String;
                  final remaining = remainingByDebt[id] ?? 0;
                  final raw = controllers[id]?.text.trim() ?? '0';
                  final amountNaira = double.tryParse(raw.replaceAll(',', '')) ?? 0;
                  final amountKobo = PaymentService.nairaToKobo(amountNaira);
                  if (amountKobo <= 0 || amountKobo != remaining) {
                    ErrorHandler.showWarningMessage(
                      context,
                      'Amount for each debt must match the remaining balance.',
                    );
                    return;
                  }
                }

                try {
                  for (final debt in debts) {
                    final id = debt['id'] as String;
                    final remaining = remainingByDebt[id] ?? 0;
                    await _dataService.recordDebtPayment(
                      debtId: id,
                      amount: remaining,
                      paymentMethod: paymentMethod.value,
                      collectedBy: staffId,
                      createdBy: staffId,
                    );
                  }
                  if (mounted) {
                    Navigator.of(ctx).pop();
                    ErrorHandler.showSuccessMessage(
                      context,
                      'Debt payments recorded. Proceeding to checkout.',
                    );
                    await _loadBookingDebts();
                    _performCheckOut();
                  }
                } catch (e, stackTrace) {
                  if (kDebugMode) debugPrint('DEBUG record payments: $e\n$stackTrace');
                  if (mounted) {
                    ErrorHandler.handleError(
                      context,
                      e,
                      customMessage: 'Failed to record payments. Please try again.',
                      stackTrace: stackTrace,
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
              child: const Text('Settle & Check-out'),
            ),
          ],
        );
      },
    ).then((_) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');

    return Scaffold(
      appBar: AppBar(
        title: Text(_currentBooking.roomNumber != null 
            ? 'Booking: Room ${_currentBooking.roomNumber}'
            : 'Booking: ${_currentBooking.guestName}'),
        backgroundColor: Colors.blueGrey,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  _buildDetailCard(
                    'Guest Information',
                    [
                      _buildDetailRow(Icons.person, 'Name', _currentBooking.guestName),
                      _buildDetailRow(Icons.phone, 'Contact', '+234 815 750 5978'),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDetailCard(
                    'Booking Details',
                    [
                      _buildDetailRow(
                        Icons.king_bed, 
                        'Room', 
                        _currentBooking.roomNumber != null 
                          ? '${_currentBooking.roomType} - ${_currentBooking.roomNumber}'
                          : '${_currentBooking.roomType} - Room Not Assigned',
                      ),
                      if (_currentBooking.roomNumber == null)
                        _buildDetailRow(
                          Icons.warning, 
                          'Room Status', 
                          'Room needs to be assigned before check-in',
                          color: Colors.orange,
                        ),
                      _buildDetailRow(Icons.info_outline, 'Status', _currentBooking.status),
                      _buildDetailRow(Icons.calendar_today, 'Check-in', DateFormat.yMMMd().format(_currentBooking.checkInDate)),
                      _buildDetailRow(Icons.calendar_today, 'Check-out', DateFormat.yMMMd().format(_currentBooking.checkOutDate)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildBillingCard(currencyFormatter),
                ],
              ),
            ),
      floatingActionButton: _currentBooking.status == 'Checked-in'
          ? FloatingActionButton.extended(
              onPressed: _showAddChargeDialog,
              label: const Text('Add Charge'),
              icon: const Icon(Icons.add),
              backgroundColor: Colors.green,
            )
          : null,
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _buildActionButton(),
      ),
    );
  }

  Widget _buildBillingCard(NumberFormat currencyFormatter) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Billing Summary', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Divider(height: 20),
            _buildDetailRow(
              Icons.hotel,
              'Room Charge',
              currencyFormatter.format(PaymentService.koboToNaira(_roomBasePriceKobo)),
            ),
            const SizedBox(height: 8),
            if (_currentBooking.extraCharges.isNotEmpty) ...[
              const Text('Extra Charges:', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._currentBooking.extraCharges.map((charge) => _buildDetailRow(
                Icons.receipt_long,
                charge['item'] as String,
                currencyFormatter.format(
                  PaymentService.koboToNaira(charge['price'] as int? ?? 0),
                ),
              )),
            ],
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Bill', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(
                  currencyFormatter.format(PaymentService.koboToNaira(_totalBillKobo)),
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget? _buildActionButton() {
    if (_currentBooking.status == 'Pending Check-in') {
      if (_currentBooking.roomId == null) {
        // Show assign room button if room not assigned
        return ElevatedButton.icon(
          icon: const Icon(Icons.room),
          label: const Text('Assign Room'),
          onPressed: () async {
            final assigned = await Navigator.push<bool>(
              context,
              MaterialPageRoute(
                builder: (context) => AssignRoomScreen(booking: _currentBooking),
              ),
            );
            if (assigned == true) {
              await _reloadBooking();
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            padding: const EdgeInsets.symmetric(vertical: 16),
            minimumSize: const Size(double.infinity, 50),
          ),
        );
      }
      // Show check-in button if room is assigned
      return ElevatedButton.icon(
        icon: const Icon(Icons.login),
        label: const Text('Confirm Guest Check-in'),
        onPressed: _performCheckIn,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.green,
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 50),
        ),
      );
    }
    if (_currentBooking.status == 'Checked-in') {
      return ElevatedButton.icon(
        icon: const Icon(Icons.logout),
        label: const Text('Proceed to Check-out'),
        onPressed: _showCheckOutConfirmation,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.red,
          padding: const EdgeInsets.symmetric(vertical: 16),
          minimumSize: const Size(double.infinity, 50),
        ),
      );
    }
    return null;
  }

  Widget _buildDetailCard(String title, List<Widget> details) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            ...details,
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color ?? Colors.grey[700]),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value, style: TextStyle(color: color))),
        ],
      ),
    );
  }
}