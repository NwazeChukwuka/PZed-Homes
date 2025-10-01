// Location: lib/presentation/screens/guest/guest_booking_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class GuestBookingScreen extends StatefulWidget {
  const GuestBookingScreen({super.key});

  @override
  State<GuestBookingScreen> createState() => _GuestBookingScreenState();
}

class _GuestBookingScreenState extends State<GuestBookingScreen> {
  late Map<String, dynamic> roomType;
  late DateTime checkInDate;
  late DateTime checkOutDate;
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    // Fallback values if no extra data
    roomType = {'name': 'Standard Room', 'price': 15000};
    checkInDate = DateTime.now();
    checkOutDate = DateTime.now().add(const Duration(days: 1));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final state = GoRouterState.of(context);
    final extra = state.extra as Map<String, dynamic>?;
    if (extra != null) {
      roomType = extra['roomType'] as Map<String, dynamic>;
      checkInDate = extra['checkInDate'] as DateTime;
      checkOutDate = extra['checkOutDate'] as DateTime;
    }
  }

  int get _totalPrice {
    final nights = checkOutDate.difference(checkInDate).inDays;
    final pricePerNight = (roomType['price'] is int)
        ? roomType['price'] as int
        : int.tryParse('${roomType['price'] ?? 0}') ?? 0;
    return pricePerNight * nights;
  }

  int get _nightsCount {
    return checkOutDate.difference(checkInDate).inDays;
  }

  Future<void> _handlePayment() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // 1. First, check room availability
      final availableRoom = await _findAvailableRoom();
      if (availableRoom == null) {
        throw Exception('Sorry, no rooms of this type are available for the selected dates.');
      }

      // 2. Create guest profile or get existing one
      final guestProfileId = await _getOrCreateGuestProfile();

      // 3. Create pending booking
      final bookingId = await _createPendingBooking(guestProfileId, availableRoom['id']);

      // 4. Process payment (mock implementation)
      final paymentSuccess = await _processMockPayment(bookingId);
      
      if (paymentSuccess) {
        // 5. Update booking status to confirmed
        await _confirmBooking(bookingId, availableRoom['id']);
        _showSuccess('Payment successful! Your booking is confirmed.');
      } else {
        // Payment failed - delete the pending booking
        await _supabase.from('bookings').delete().eq('id', bookingId);
        _showError('Payment failed. Please try again.');
      }

    } catch (e) {
      ErrorHandler.handleError(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<Map<String, dynamic>?> _findAvailableRoom() async {
    try {
      // Mock room availability - in production, this would check Supabase
      await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
      
      // For demo purposes, always return a mock available room
      return {
        'id': 'room-${roomType['id']?.toString() ?? 'unknown'}-001',
        'room_number': '${roomType['id']?.toString() ?? 'unknown'}01',
        'room_type_id': roomType['id']?.toString() ?? 'unknown',
        'status': 'Available',
      };
    } catch (e) {
      throw Exception('Error checking room availability: $e');
    }
  }

  Future<String> _getOrCreateGuestProfile() async {
    final email = _emailController.text.trim();
    
    try {
      // Mock guest profile creation - in production, this would use Supabase
      await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
      
      // For demo purposes, always return a mock guest profile ID
      return 'guest-${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      throw Exception('Error creating guest profile: $e');
    }
  }

  Future<String> _createPendingBooking(String guestProfileId, String roomId) async {
    try {
      // Mock booking creation - in production, this would use Supabase
      await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
      
      // For demo purposes, return a mock booking ID
      return 'booking-${DateTime.now().millisecondsSinceEpoch}';
    } catch (e) {
      throw Exception('Error creating booking: $e');
    }
  }

  Future<bool> _processMockPayment(String bookingId) async {
    try {
      // Show payment dialog
      final result = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Payment Confirmation'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Amount: ₦${_totalPrice.toString()}'),
              const SizedBox(height: 16),
              const Text('This is a demo payment. Click "Pay" to simulate successful payment.'),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => context.pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => context.pop(true),
              child: const Text('Pay'),
            ),
          ],
        ),
      );

      return result ?? false;
    } catch (e) {
      throw Exception('Payment processing error: $e');
    }
  }

  Future<void> _confirmBooking(String bookingId, String roomId) async {
    try {
      // Mock booking confirmation - in production, this would use Supabase
      await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
      
      // For demo purposes, just simulate the confirmation
      print('Booking confirmed: $bookingId for room: $roomId');
    } catch (e) {
      throw Exception('Error confirming booking: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 5),
      ),
    );
    
    // Navigate back to home after success
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        context.go('/guest');
      }
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currencyFormatter = NumberFormat.currency(locale: 'en_NG', symbol: '₦');
    final dateFormat = DateFormat('MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Confirm Your Booking'),
        backgroundColor: Colors.green[700],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isDesktop = constraints.maxWidth > 1200;
          final isTablet = constraints.maxWidth > 600;
          
          return SingleChildScrollView(
            child: Padding(
              padding: EdgeInsets.all(isDesktop ? 32.0 : isTablet ? 24.0 : 16.0),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isDesktop ? 800 : 600,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Booking Summary
                      Card(
                        elevation: 2,
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Booking Summary',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 16),
                              _buildSummaryRow('Room Type', roomType['name']?.toString() ?? 'Unknown Room'),
                              _buildSummaryRow('Check-in', dateFormat.format(checkInDate)),
                              _buildSummaryRow('Check-out', dateFormat.format(checkOutDate)),
                              _buildSummaryRow('Nights', _nightsCount.toString()),
                              const Divider(height: 24),
                              _buildSummaryRow(
                                'Total Amount',
                                currencyFormatter.format(_totalPrice),
                                isTotal: true,
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 24),

                      // Guest Information Form
                      Text(
                        'Guest Information',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),

                      Form(
                        key: _formKey,
                        child: Column(
                          children: [
                            TextFormField(
                              controller: _nameController,
                              decoration: const InputDecoration(
                                labelText: 'Full Name',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.person),
                              ),
                              validator: (val) => val?.trim().isEmpty == true 
                                  ? 'Please enter your name' 
                                  : null,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _emailController,
                              decoration: const InputDecoration(
                                labelText: 'Email Address',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.email),
                              ),
                              keyboardType: TextInputType.emailAddress,
                              validator: (val) {
                                if (val?.trim().isEmpty == true) {
                                  return 'Please enter your email';
                                }
                                if (!val!.contains('@')) {
                                  return 'Please enter a valid email';
                                }
                                return null;
                              },
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _phoneController,
                              decoration: const InputDecoration(
                                labelText: 'Phone Number',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.phone),
                              ),
                              keyboardType: TextInputType.phone,
                              validator: (val) => val?.trim().isEmpty == true 
                                  ? 'Please enter your phone number' 
                                  : null,
                              textInputAction: TextInputAction.done,
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Payment Button
                      _isLoading
                          ? const Center(child: CircularProgressIndicator())
                          : SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _handlePayment,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green[700],
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  textStyle: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(Icons.lock),
                                    const SizedBox(width: 8),
                                    Text('Pay ${currencyFormatter.format(_totalPrice)}'),
                                  ],
                                ),
                              ),
                            ),

                      const SizedBox(height: 16),
                      
                      // Security notice
                      Text(
                        'Your payment is secured and encrypted with Paystack',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Colors.grey,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      
                      const SizedBox(height: 8),
                      
                      // Payment methods
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          Icon(Icons.credit_card, size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              'Card • Bank Transfer • USSD',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: Colors.grey,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
              fontSize: isTotal ? 16 : null,
              color: isTotal ? Colors.green : null,
            ),
          ),
        ],
      ),
    );
  }
}