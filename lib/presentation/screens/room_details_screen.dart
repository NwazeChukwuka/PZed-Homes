import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
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
  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  List<Map<String, dynamic>> _availableRooms = [];
  bool _isLoadingAvailability = false;

  Future<void> _checkAvailability() async {
    if (_checkInDate == null || _checkOutDate == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please select check-in and check-out dates',
        );
      }
      return;
    }

    setState(() => _isLoadingAvailability = true);
    try {
      final dataService = DataService();
      final allRooms = await dataService.getRooms();
      final type = (widget.roomType['type'] as String?)?.toLowerCase() ?? '';
      
      // Get conflicting bookings
      final supabase = Supabase.instance.client;
      final conflictingBookings = await supabase
          .from('bookings')
          .select('room_id')
          .or('status.eq.Pending Check-in,status.eq.Checked-in')
          .lte('check_in_date', _checkOutDate!.toIso8601String())
          .gte('check_out_date', _checkInDate!.toIso8601String());
      
      final bookedRoomIds = (conflictingBookings as List)
          .where((b) => b['room_id'] != null)
          .map((b) => b['room_id'] as String)
          .toSet();
      
      final available = allRooms
          .where((r) => 
              (r['type']?.toString().toLowerCase() ?? '') == type && 
              (r['status'] == 'Vacant') &&
              !bookedRoomIds.contains(r['id']?.toString()))
          .map((r) => {
                'room_number': r['room_number'] ?? r['id'],
              })
          .toList();
      
      setState(() {
        _availableRooms = List<Map<String, dynamic>>.from(available);
        _isLoadingAvailability = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingAvailability = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to check availability. Please try again.',
          onRetry: _checkAvailability,
        );
      }
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
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please select dates first',
        );
      }
      return;
    }

    if (_availableRooms.isEmpty) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please check availability first',
        );
      }
      return;
    }

    // Navigate to booking screen with selected parameters
    if (mounted) {
      ErrorHandler.showInfoMessage(
        context,
        'Proceeding to booking...',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');
    final dateFormatter = DateFormat('EEE, MMM d, yyyy');
    final priceValue = widget.roomType['price_kobo'] ??
        widget.roomType['price'] ??
        widget.roomType['price_ngn'];
    int priceKobo = 0;
    if (priceValue is int) {
      priceKobo = priceValue;
    } else if (priceValue is num) {
      priceKobo = priceValue.toInt();
    } else {
      priceKobo = int.tryParse('$priceValue') ?? 0;
    }
    if (widget.roomType['price_ngn'] != null && widget.roomType['price_kobo'] == null) {
      final ngnValue = widget.roomType['price_ngn'];
      if (ngnValue is num) {
        priceKobo = PaymentService.nairaToKobo(ngnValue.toDouble());
      }
    }
    final priceNaira = PaymentService.koboToNaira(priceKobo);
    final List<String> images = List<String>.from(widget.roomType['images'] ?? []);
    
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.roomType['name'] ?? 'Room Details'),
        backgroundColor: Colors.green,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Room Image Gallery
            if (images.isNotEmpty) ...[
              SizedBox(
                height: 250,
                child: PageView.builder(
                  allowImplicitScrolling: false,
                  itemCount: images.length,
                  itemBuilder: (context, index) {
                    return ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        images[index],
                        fit: BoxFit.cover,
                        cacheWidth: 800,
                        cacheHeight: 500,
                        gaplessPlayback: true,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            color: Colors.grey[200],
                            child: const Center(child: Icon(Icons.broken_image, size: 50)),
                          );
                        },
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),
              // Image indicator dots
              if (images.length > 1)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(
                    images.length,
                    (index) => Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: index == 0 ? Colors.green : Colors.grey[300],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 24),
            ] else
              Container(
                height: 200,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.image_not_supported, size: 50, color: Colors.grey),
                ),
              ),

            // Room Details
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    widget.roomType['name'] ?? 'Unknown Room Type',
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '${currencyFormatter.format(priceNaira)}/night',
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
                style: const TextStyle(color: Colors.grey, fontSize: 16),
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