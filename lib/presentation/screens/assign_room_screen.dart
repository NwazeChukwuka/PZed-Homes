// Screen for receptionists to assign rooms to bookings

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/presentation/screens/booking_details_screen.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class AssignRoomScreen extends StatefulWidget {
  final Booking booking;

  const AssignRoomScreen({super.key, required this.booking});

  @override
  State<AssignRoomScreen> createState() => _AssignRoomScreenState();
}

class _AssignRoomScreenState extends State<AssignRoomScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _availableRooms = [];
  String? _selectedRoomId;
  bool _isLoading = true;
  bool _isAssigning = false;

  @override
  void initState() {
    super.initState();
    _loadAvailableRooms();
  }

  Future<void> _loadAvailableRooms() async {
    setState(() => _isLoading = true);
    try {
      final requestedType = widget.booking.requestedRoomType ?? widget.booking.roomType;
      
      // Get available rooms of the requested type
      final rooms = await _supabase
          .from('rooms')
          .select()
          .eq('type', requestedType)
          .eq('status', 'Vacant')
          .order('room_number');

      // Filter out rooms that are booked during the check-in/check-out dates
      // Correct overlap logic: A booking conflicts if:
      // booking.check_in_date < our.check_out_date AND booking.check_out_date > our.check_in_date
      final conflictingBookings = await _supabase
          .from('bookings')
          .select('room_id')
          .or('status.eq.Pending Check-in,status.eq.Checked-in')
          .lt('check_in_date', widget.booking.checkOutDate.toIso8601String())
          .gt('check_out_date', widget.booking.checkInDate.toIso8601String());

      final bookedRoomIds = (conflictingBookings as List)
          .where((b) => b['room_id'] != null)
          .map((b) => b['room_id'] as String)
          .toSet();

      final available = (rooms as List)
          .where((r) => !bookedRoomIds.contains(r['id'] as String))
          .toList();

      setState(() {
        _availableRooms = List<Map<String, dynamic>>.from(available);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ErrorHandler.handleError(context, e);
      }
    }
  }

  Future<void> _assignRoom() async {
    if (_selectedRoomId == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Please select a room',
        );
      }
      return;
    }

    setState(() => _isAssigning = true);
    try {
      // Verify payment status before assigning room
      final booking = await _supabase
          .from('bookings')
          .select('total_amount, paid_amount, status, requested_room_type')
          .eq('id', widget.booking.id)
          .single();

      final totalAmount = booking['total_amount'] as int? ?? 0;
      final paidAmount = booking['paid_amount'] as int? ?? 0;

      // Warn if booking is not fully paid, but allow assignment (receptionist can collect payment later)
      if (paidAmount < totalAmount) {
        final shouldProceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Payment Incomplete'),
            content: Text(
              'This booking has not been fully paid.\n'
              'Total: ₦${(totalAmount / 100).toStringAsFixed(0)}\n'
              'Paid: ₦${(paidAmount / 100).toStringAsFixed(0)}\n'
              'Outstanding: ₦${((totalAmount - paidAmount) / 100).toStringAsFixed(0)}\n\n'
              'Do you want to assign the room anyway?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Assign Anyway'),
              ),
            ],
          ),
        );

        if (shouldProceed != true) {
          if (mounted) {
            setState(() => _isAssigning = false);
          }
          return;
        }
      }

      // Verify room type matches booking request (additional UI validation)
      final selectedRoom = _availableRooms.firstWhere(
        (r) => r['id'] == _selectedRoomId,
        orElse: () => <String, dynamic>{},
      );
      final roomType = selectedRoom['type'] as String?;
      final requestedType = booking['requested_room_type'] as String?;

      if (requestedType != null && roomType != requestedType) {
        final shouldProceed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Room Type Mismatch'),
            content: Text(
              'This booking requested: $requestedType\n'
              'Selected room is: $roomType\n\n'
              'The database function will validate this, but do you want to continue?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );

        if (shouldProceed != true) {
          if (mounted) {
            setState(() => _isAssigning = false);
          }
          return;
        }
      }

      // Use database function to assign room (includes validation)
      await _supabase.rpc('assign_room_to_booking', params: {
        'booking_id': widget.booking.id,
        'room_id': _selectedRoomId,
      });

      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Room assigned successfully!',
        );
        Navigator.of(context).pop(true); // Return true to indicate success
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(context, e);
      }
    } finally {
      if (mounted) {
        setState(() => _isAssigning = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Assign Room'),
        backgroundColor: Colors.blueGrey,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Booking Info Card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Guest: ${widget.booking.guestName}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Requested Room Type: ${widget.booking.requestedRoomType ?? widget.booking.roomType}',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        Text(
                          'Check-in: ${widget.booking.checkInDate.toString().split(' ')[0]}',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                        Text(
                          'Check-out: ${widget.booking.checkOutDate.toString().split(' ')[0]}',
                          style: TextStyle(color: Colors.grey[700]),
                        ),
                      ],
                    ),
                  ),
                ),

                // Available Rooms List
                Expanded(
                  child: _availableRooms.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.hotel, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text(
                                'No available rooms of this type',
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Please check other room types or dates',
                                style: TextStyle(
                                  color: Colors.grey[500],
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: _availableRooms.length,
                          itemBuilder: (context, index) {
                            final room = _availableRooms[index];
                            final isSelected = _selectedRoomId == room['id'];
                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              elevation: isSelected ? 4 : 1,
                              color: isSelected ? Colors.blue[50] : null,
                              child: ListTile(
                                leading: Icon(
                                  Icons.room,
                                  color: isSelected ? Colors.blue : Colors.grey,
                                  size: 32,
                                ),
                                title: Text(
                                  'Room ${room['room_number']}',
                                  style: TextStyle(
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                                subtitle: Text(
                                  'Type: ${room['type']}\nStatus: ${room['status']}',
                                ),
                                trailing: isSelected
                                    ? const Icon(Icons.check_circle, color: Colors.blue)
                                    : null,
                                onTap: () {
                                  setState(() {
                                    _selectedRoomId = room['id'] as String;
                                  });
                                },
                              ),
                            );
                          },
                        ),
                ),

                // Assign Button
                if (_availableRooms.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        icon: _isAssigning
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                ),
                              )
                            : const Icon(Icons.check),
                        label: Text(_isAssigning ? 'Assigning...' : 'Assign Room'),
                        onPressed: _isAssigning ? null : _assignRoom,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
    );
  }
}

