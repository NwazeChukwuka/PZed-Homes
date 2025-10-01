import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class RoomDetailsScreen extends StatefulWidget {
  final Map<String, dynamic> roomType;

  const RoomDetailsScreen({
    super.key,
    required this.roomType,
  });

  @override
  State<RoomDetailsScreen> createState() => _RoomDetailsScreenState();
}

class _RoomDetailsScreenState extends State<RoomDetailsScreen> {
  final _supabase = Supabase.instance.client;
  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  List<Map<String, dynamic>> _availableRooms = [];
  bool _isLoadingAvailability = false;

  Future<void> _checkAvailability() async {
    if (_checkInDate == null || _checkOutDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select check-in and check-out dates')),
      );
      return;
    }

    setState(() => _isLoadingAvailability = true);
    try {
      final response = await _supabase.rpc('check_room_availability', params: {
        'room_type_id': widget.roomType['id'],
        'start_date': _checkInDate!.toIso8601String(),
        'end_date': _checkOutDate!.toIso8601String(),
      });

      setState(() {
        _availableRooms = List<Map<String, dynamic>>.from(response);
        _isLoadingAvailability = false;
      });
    } catch (e) {
      setState(() => _isLoadingAvailability = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error checking availability: $e'), backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _selectDate(BuildContext context, bool isCheckIn) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    
    if (picked != null) {
      setState(() {
        if (isCheckIn) {
          _checkInDate = picked;
          // Reset availability when dates change
          _availableRooms = [];
        } else {
          _checkOutDate = picked;
        }
      });
    }
  }

  void _navigateToBooking() {
    if (_checkInDate == null || _checkOutDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select dates first')),
      );
      return;
    }

    if (_availableRooms.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please check availability first')),
      );
      return;
    }

    // Navigate to booking screen with selected parameters
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Proceeding to booking...')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');
    final dateFormatter = DateFormat('EEE, MMM d, yyyy');
    final price = widget.roomType['price'] as int? ?? 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomType['type'] ?? 'Room Details'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Room Image
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(12),
                image: widget.roomType['image_url'] != null
                    ? DecorationImage(
                        image: NetworkImage(widget.roomType['image_url'] as String),
                        fit: BoxFit.cover,
                      )
                    : null,
              ),
              child: widget.roomType['image_url'] == null
                  ? Center(
                      child: Image.asset(
                        'assets/images/PZED logo.png',
                        height: 64,
                        width: 64,
                        fit: BoxFit.contain,
                        color: Colors.grey,
                      ),
                    )
                  : null,
            ),
            const SizedBox(height: 24),

            // Room Details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.roomType['type'] ?? 'Unknown Room Type',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${currencyFormatter.format(price)}/night',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (widget.roomType['description'] != null)
              Text(
                widget.roomType['description'] as String,
                style: const TextStyle(color: Colors.grey),
              ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // Date Selection
            const Text(
              'Select Dates',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.login, color: Colors.green),
                      title: const Text('Check-in'),
                      subtitle: Text(_checkInDate != null 
                          ? dateFormatter.format(_checkInDate!)
                          : 'Select date'),
                      onTap: () => _selectDate(context, true),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Card(
                    child: ListTile(
                      leading: const Icon(Icons.logout, color: Colors.red),
                      title: const Text('Check-out'),
                      subtitle: Text(_checkOutDate != null 
                          ? dateFormatter.format(_checkOutDate!)
                          : 'Select date'),
                      onTap: () => _selectDate(context, false),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _checkAvailability,
              child: _isLoadingAvailability
                  ? const CircularProgressIndicator()
                  : const Text('Check Availability'),
            ),

            const SizedBox(height: 24),

            // Availability Results
            if (_availableRooms.isNotEmpty)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Available Rooms',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _availableRooms.map((room) {
                      return Chip(
                        label: Text('Room ${room['room_number']}'),
                        backgroundColor: Colors.green[100],
                      );
                    }).toList(),
                  ),
                ],
              )
            else if (_checkInDate != null && _checkOutDate != null && !_isLoadingAvailability)
              const Text('No rooms available for selected dates'),

            const SizedBox(height: 32),
          ],
        ),
      ),
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ElevatedButton(
          onPressed: _navigateToBooking,
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.green,
            padding: const EdgeInsets.symmetric(vertical: 16),
          ),
          child: const Text('Book Now'),
        ),
      ),
    );
  }
}