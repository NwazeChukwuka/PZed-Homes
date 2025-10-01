import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';

class Booking {
  final String id;
  final String guestName;
  final String roomType;
  final String roomNumber;
  final String status;
  final List<Map<String, dynamic>> extraCharges;
  final DateTime checkInDate;
  final DateTime checkOutDate;

  Booking({
    required this.id,
    required this.guestName,
    required this.roomType,
    required this.roomNumber,
    required this.status,
    required this.extraCharges,
    required this.checkInDate,
    required this.checkOutDate,
  });

  Booking copyWith({
    String? status,
    List<Map<String, dynamic>>? extraCharges,
  }) {
    return Booking(
      id: id,
      guestName: guestName,
      roomType: roomType,
      roomNumber: roomNumber,
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
      final priceResponse = await _supabase
          .from('menu_items')
          .select('price')
          .like('name', '%${_currentBooking.roomType}%')
          .limit(1)
          .single();
      
      setState(() {
        _roomBasePrice = (priceResponse['price'] as int) ~/ 100;
      });
    } catch (e) {
      print('Error fetching room price: $e');
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

      // Update booking status to checked-in
      setState(() {
        _currentBooking = _currentBooking.copyWith(status: 'Checked-in');
      });

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guest checked in successfully!'),
          backgroundColor: Colors.green,
        ),
      );

      // Return updated booking to previous screen
      Navigator.of(context).pop(_currentBooking);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error during check-in: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error adding charge: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _performCheckOut() async {
    setState(() => _isLoading = true);
    try {
      // Update room status
      await _supabase
          .from('rooms')
          .update({'status': 'Dirty'})
          .eq('room_number', _currentBooking.roomNumber);

      // Update booking status
      await _supabase
          .from('bookings')
          .update({'status': 'Checked-out'})
          .eq('id', _currentBooking.id);

      setState(() {
        _currentBooking = _currentBooking.copyWith(status: 'Checked-out');
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Guest checked out successfully. Room marked as dirty.'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error during checkout: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
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
        title: Text('Booking: Room ${_currentBooking.roomNumber}'),
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
                      _buildDetailRow(Icons.king_bed, 'Room', '${_currentBooking.roomType} - ${_currentBooking.roomNumber}'),
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

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[700]),
          const SizedBox(width: 8),
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}