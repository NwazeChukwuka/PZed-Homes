import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/data/data.dart';
// Import the new screen with alias to avoid conflict
import 'package:pzed_homes/presentation/screens/booking_details_screen.dart' as details;
import 'package:pzed_homes/data/models/booking.dart' as models;

class BookingListItem extends StatelessWidget {
  final Booking booking;
  // Add a callback to notify the dashboard of an update
  final ValueChanged<details.Booking> onUpdate;

  const BookingListItem({
    super.key, 
    required this.booking,
    required this.onUpdate,
  });

  // ... (The _getStatusColor method remains the same)
  Color _getStatusColor(String status) {
    switch (status) {
      case 'Checked-in':
        return Colors.green;
      case 'Pending Check-in':
        return Colors.orange;
      case 'Checked-out':
        return Colors.blueGrey;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          // Navigate and wait for a result
          final updatedBooking = await Navigator.push<details.Booking>(
            context,
            MaterialPageRoute(
              builder: (context) => details.BookingDetailsScreen(
                booking: details.Booking(
                  id: booking.id,
                  guestName: booking.guestName,
                  roomType: booking.roomType,
                  roomNumber: booking.roomNumber, // Can be null now
                  status: booking.status,
                  extraCharges: booking.extraCharges,
                  checkInDate: booking.checkInDate,
                  checkOutDate: booking.checkOutDate,
                ),
              ),
            ),
          );

          // If we got an updated booking back, notify the dashboard
          if (updatedBooking != null) {
            onUpdate(updatedBooking);
          }
        },
        child: ListTile(
          // ... (The ListTile content remains the same)
          leading: CircleAvatar(
            backgroundColor: _getStatusColor(booking.status),
            child: const Icon(Icons.person, color: Colors.white),
          ),
          title: Text(
            booking.guestName,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
              '${booking.roomNumber != null ? "Room ${booking.roomNumber}" : "Room Not Assigned"} (${booking.roomType})\nCheck-in: ${DateFormat.yMd().format(booking.checkInDate)}'),
          trailing: Chip(
            label: Text(
              booking.status,
              style: const TextStyle(fontSize: 12),
            ),
            backgroundColor: _getStatusColor(booking.status).withOpacity(0.2),
          ),
        ),
      ),
    );
  }
}