import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/presentation/screens/guest/available_rooms_screen.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class GuestHomeScreen extends StatefulWidget {
  const GuestHomeScreen({super.key});

  @override
  State<GuestHomeScreen> createState() => _GuestHomeScreenState();
}

class _GuestHomeScreenState extends State<GuestHomeScreen> {
  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  final _dateFormatter = DateFormat('EEE, MMM d, yyyy');

  Future<void> _selectDate(BuildContext context, bool isCheckIn) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isCheckIn ? DateTime.now() : _checkInDate?.add(const Duration(days: 1)) ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (DateTime day) {
        if (isCheckIn) return true;
        // For check-out, only allow dates after check-in
        return _checkInDate == null || day.isAfter(_checkInDate!);
      },
    );
    
    if (picked != null) {
      setState(() {
        if (isCheckIn) {
          _checkInDate = picked;
          // Reset check-out if it's before new check-in
          if (_checkOutDate != null && _checkOutDate!.isBefore(picked)) {
            _checkOutDate = null;
          }
        } else {
          _checkOutDate = picked;
        }
      });
    }
  }

  void _searchAvailability() {
    if (_checkInDate == null || _checkOutDate == null) {
      ErrorHandler.showWarningMessage(
        context,
        'Please select both check-in and check-out dates.',
      );
      return;
    }

    if (_checkOutDate!.isBefore(_checkInDate!) ||
        _checkOutDate!.isAtSameMomentAs(_checkInDate!)) {
      ErrorHandler.showWarningMessage(
        context,
        'Check-out date must be after the check-in date.',
      );
      return;
    }

    context.push('/guest/rooms', extra: {
      'checkInDate': _checkInDate!,
      'checkOutDate': _checkOutDate!,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Background image
        Image.network(
          'https://images.unsplash.com/photo-1566073771259-6a8506099945?ixlib=rb-4.0.3&auto=format&fit=crop&w=2070&q=80',
          fit: BoxFit.cover,
          width: double.infinity,
          height: double.infinity,
          color: Colors.black.withOpacity(0.4),
          colorBlendMode: BlendMode.darken,
          errorBuilder: (context, error, stackTrace) {
            return Container(color: Colors.grey[300]);
          },
        ),
        
        // Content
        Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 500),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Book Your Stay',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 24),
                      
                      // Check-in Date
                      _buildDateSelector(
                        context,
                        'Check-in Date',
                        _checkInDate,
                        true,
                      ),
                      const SizedBox(height: 16),
                      
                      // Check-out Date
                      _buildDateSelector(
                        context,
                        'Check-out Date',
                        _checkOutDate,
                        false,
                      ),
                      const SizedBox(height: 32),
                      
                      // Availability Button
                      ElevatedButton(
                        onPressed: _searchAvailability,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontSize: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Check Availability'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateSelector(BuildContext context, String title, DateTime? date, bool isCheckIn) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(
          isCheckIn ? Icons.login : Icons.logout,
          color: Colors.green[700],
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          date != null ? _dateFormatter.format(date) : 'Select Date',
          style: TextStyle(
            color: date != null ? Colors.black : Colors.grey,
          ),
        ),
        trailing: const Icon(Icons.calendar_today),
        onTap: () => _selectDate(context, isCheckIn),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}