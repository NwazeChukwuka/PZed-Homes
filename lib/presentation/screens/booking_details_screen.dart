import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/presentation/screens/assign_room_screen.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

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
  final _supabase = Supabase.instance.client;
  int _roomBasePrice = 0;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _currentBooking = widget.booking;
    _fetchRoomPrice();
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
          _roomBasePrice = priceInKobo ~/ 100; // Convert kobo to naira
        });
      } else {
        // Room type not found - set to 0 or show error
        setState(() {
          _roomBasePrice = 0;
        });
      }
    } catch (e) {
      print('Error fetching room price: $e');
      setState(() {
        _roomBasePrice = 0;
      });
    }
  }

  int get _extraChargesTotal {
    return _currentBooking.extraCharges
        .fold(0, (sum, item) => sum + (item['price'] as int));
  }

  int get _totalBill {
    return _roomBasePrice + _extraChargesTotal;
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
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to check in guest. Please try again.',
          onRetry: _performCheckIn,
        );
      }
    }
  }

  Future<void> _reloadBooking() async {
    try {
      final bookingData = await _supabase
          .from('bookings')
          .select('*, rooms(*), profiles!guest_profile_id(*)')
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
    } catch (e) {
      print('Error reloading booking: $e');
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
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to add charge. Please try again.',
          onRetry: () => _addCharge(itemName, price),
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
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to check out guest. Please try again.',
          onRetry: _performCheckOut,
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
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Confirm Check-out'),
        content: Text(
          'The total bill for ${_currentBooking.guestName} is ${currencyFormatter.format(_totalBill)}.\n\nProceed with check-out?'
        ),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.pop();
              _performCheckOut();
            },
            child: const Text('Confirm & Check-out'),
          ),
        ],
      ),
    );
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
            _buildDetailRow(Icons.hotel, 'Room Charge', currencyFormatter.format(_roomBasePrice)),
            const SizedBox(height: 8),
            if (_currentBooking.extraCharges.isNotEmpty) ...[
              const Text('Extra Charges:', style: TextStyle(fontWeight: FontWeight.bold)),
              ..._currentBooking.extraCharges.map((charge) => _buildDetailRow(
                Icons.receipt_long,
                charge['item'] as String,
                currencyFormatter.format((charge['price'] as int) ~/ 100),
              )),
            ],
            const Divider(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total Bill', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text(
                  currencyFormatter.format(_totalBill),
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