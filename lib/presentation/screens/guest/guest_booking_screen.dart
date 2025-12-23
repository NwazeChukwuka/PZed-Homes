// Location: lib/presentation/screens/guest/guest_booking_screen.dart

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/theme/responsive_helpers.dart';

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
  bool _isLoading = false;

  // Get Supabase client safely (returns null if not initialized)
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      return null;
    }
  }

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
    try {
      final state = GoRouterState.of(context);
      final extra = state.extra as Map<String, dynamic>?;
      if (extra != null) {
        roomType = extra['roomType'] as Map<String, dynamic>;
        checkInDate = extra['checkInDate'] as DateTime;
        checkOutDate = extra['checkOutDate'] as DateTime;
      }
    } catch (e) {
      // If GoRouterState is not available, use fallback values from initState
      // This can happen if the screen is accessed without router context
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

    // Check if Supabase is initialized
    if (_supabase == null) {
      ErrorHandler.handleError(
        context,
        Exception('Supabase is not configured. Please set your Supabase credentials in the .env file.'),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Check room type availability (count by type, not specific room)
      final isAvailable = await _checkRoomTypeAvailability();
      if (!isAvailable) {
        throw Exception('Sorry, no rooms of this type are available for the selected dates.');
      }

      // 2. Create guest profile or get existing one
      final guestProfileId = await _getOrCreateGuestProfile();

      // 3. Create booking WITHOUT room_id (receptionist will assign later)
      final bookingId = await _createPendingBooking(guestProfileId);

      // 4. Process payment (mock implementation)
      final paymentSuccess = await _processMockPayment(bookingId);
      
      if (paymentSuccess) {
        // 5. Update booking status to Pending Check-in (room will be assigned by receptionist)
        await _confirmBooking(bookingId);
        _showSuccess('Payment successful! Your booking is confirmed. A room will be assigned when you arrive.');
      } else {
        // Payment failed - delete the pending booking
        await _supabase!.from('bookings').delete().eq('id', bookingId);
        _showError('Payment failed. Please try again.');
      }

    } catch (e) {
      ErrorHandler.handleError(context, e);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<bool> _checkRoomTypeAvailability() async {
    if (_supabase == null) {
      throw Exception('Supabase is not configured');
    }

    try {
      final roomTypeName = roomType['name']?.toString() ?? roomType['type']?.toString();
      if (roomTypeName == null) throw Exception('Invalid room type');

      // Get total rooms of this type
      final totalRooms = await _supabase!
          .from('rooms')
          .select('id')
          .eq('type', roomTypeName)
          .eq('status', 'Vacant');

      if ((totalRooms as List).isEmpty) {
        return false; // No rooms of this type exist
      }

      // Count bookings for this room type during the selected dates
      // Include bookings with room_id assigned AND bookings by requested_room_type
      final conflictingBookings = await _supabase!
          .from('bookings')
          .select('room_id, requested_room_type')
          .or('status.eq.Pending Check-in,status.eq.Checked-in')
          .lte('check_in_date', checkOutDate.toIso8601String())
          .gte('check_out_date', checkInDate.toIso8601String());

      // Count rooms directly assigned
      final assignedRoomIds = (conflictingBookings as List)
          .where((b) => b['room_id'] != null)
          .map((b) => b['room_id'] as String)
          .toSet();

      // Count bookings by requested room type (without room_id)
      final bookingsByType = (conflictingBookings as List)
          .where((b) => b['room_id'] == null && b['requested_room_type'] == roomTypeName)
          .length;

      // Check if we have enough available rooms
      final availableCount = (totalRooms as List).length - assignedRoomIds.length - bookingsByType;
      
      return availableCount > 0;
    } catch (e) {
      throw Exception('Error checking room availability: $e');
    }
  }

  Future<String> _getOrCreateGuestProfile() async {
    if (_supabase == null) {
      throw Exception('Supabase is not configured');
    }

    final email = _emailController.text.trim();
    
    try {
      // Check if profile exists
      final existing = await _supabase!
          .from('profiles')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (existing != null) {
        return existing['id'] as String;
      }

      // Create new profile
      final response = await _supabase!
          .from('profiles')
          .insert({
            'full_name': _nameController.text.trim(),
            'email': email,
            'phone': _phoneController.text.trim(),
          })
          .select('id')
          .single();

      return response['id'] as String;
    } catch (e) {
      throw Exception('Error creating guest profile: $e');
    }
  }

  Future<String> _createPendingBooking(String guestProfileId) async {
    if (_supabase == null) {
      throw Exception('Supabase is not configured');
    }

    try {
      final roomTypeName = roomType['name']?.toString() ?? roomType['type']?.toString() ?? 'Standard';
      
      final response = await _supabase!
          .from('bookings')
          .insert({
            'guest_profile_id': guestProfileId,
            'room_id': null, // Room will be assigned by receptionist
            'requested_room_type': roomTypeName,
            'check_in_date': checkInDate.toIso8601String(),
            'check_out_date': checkOutDate.toIso8601String(),
            'status': 'Pending Check-in',
            'total_amount': _totalPrice * 100, // Convert naira to kobo for database
            'paid_amount': _totalPrice * 100, // Convert naira to kobo for database
          })
          .select('id')
          .single();

      return response['id'] as String;
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

  Future<void> _confirmBooking(String bookingId) async {
    if (_supabase == null) {
      throw Exception('Supabase is not configured');
    }

    try {
      final paidAmountInKobo = _totalPrice * 100;
      
      // Update booking status to Pending Check-in (room will be assigned by receptionist)
      // Don't update room status - rooms stay Vacant until check-in
      await _supabase!
          .from('bookings')
          .update({
            'status': 'Pending Check-in',
            'paid_amount': paidAmountInKobo, // Convert to kobo
          })
          .eq('id', bookingId);
      
      // Create income record for booking payment
      final roomTypeName = roomType['name']?.toString() ?? roomType['type']?.toString() ?? 'Room';
      await _supabase!
          .from('income_records')
          .insert({
            'description': 'Room booking - $roomTypeName',
            'amount': paidAmountInKobo, // Already in kobo
            'source': 'Room Booking',
            'date': DateTime.now().toIso8601String().split('T')[0],
            'department': 'reception',
            'payment_method': 'online', // Guest paid online
            'booking_id': bookingId,
          });
      
      // Note: Room status remains 'Vacant' - receptionist will assign room and update status at check-in
    } catch (e) {
      throw Exception('Error confirming booking: $e');
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ErrorHandler.handleError(
      context,
      Exception(message),
      customMessage: message,
    );
  }

  void _showSuccess(String message) {
    if (!mounted) return;
    ErrorHandler.showSuccessMessage(
      context,
      message,
      duration: const Duration(seconds: 5),
    );
    
    // Navigate back to home after success
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        try {
          context.go('/guest');
        } catch (e) {
          // If GoRouter is not available, use Navigator as fallback
          Navigator.of(context).popUntil((route) => route.isFirst);
        }
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
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: ResponsiveContainer(
                maxWidth: ResponsiveHelper.isDesktop(context) ? 800 : 600,
                padding: ResponsiveHelper.getResponsivePadding(
                  context,
                  mobile: const EdgeInsets.all(16),
                  tablet: const EdgeInsets.all(24),
                  desktop: const EdgeInsets.all(32),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
              // Booking Summary
              Card(
                elevation: 2,
                child: Padding(
                  padding: ResponsiveHelper.getResponsivePadding(
                    context,
                    mobile: const EdgeInsets.all(12),
                    tablet: const EdgeInsets.all(16),
                    desktop: const EdgeInsets.all(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Booking Summary',
                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: ResponsiveHelper.getResponsiveFontSize(
                            context,
                            mobile: 18,
                            tablet: 20,
                            desktop: 22,
                          ),
                        ),
                      ),
                      SizedBox(height: ResponsiveHelper.getResponsiveValue(
                        context,
                        mobile: 12,
                        tablet: 16,
                        desktop: 16,
                      )),
                      _buildSummaryRow(context, 'Room Type', roomType['name']?.toString() ?? 'Unknown Room'),
                      _buildSummaryRow(context, 'Check-in', dateFormat.format(checkInDate)),
                      _buildSummaryRow(context, 'Check-out', dateFormat.format(checkOutDate)),
                      _buildSummaryRow(context, 'Nights', _nightsCount.toString()),
                      Divider(height: ResponsiveHelper.getResponsiveValue(
                        context,
                        mobile: 20,
                        tablet: 24,
                        desktop: 24,
                      )),
                      _buildSummaryRow(
                        context,
                        'Total Amount',
                        currencyFormatter.format(_totalPrice),
                        isTotal: true,
                      ),
                    ],
                  ),
                ),
              ),

              SizedBox(height: ResponsiveHelper.getResponsiveValue(
                context,
                mobile: 20,
                tablet: 24,
                desktop: 24,
              )),

              // Guest Information Form
              Text(
                'Guest Information',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  fontSize: ResponsiveHelper.getResponsiveFontSize(
                    context,
                    mobile: 18,
                    tablet: 20,
                    desktop: 22,
                  ),
                ),
              ),
              SizedBox(height: ResponsiveHelper.getResponsiveValue(
                context,
                mobile: 12,
                tablet: 16,
                desktop: 16,
              )),

              Form(
                key: _formKey,
                child: Column(
                  children: [
                    TextFormField(
                      controller: _nameController,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.person),
                        contentPadding: ResponsiveHelper.getResponsivePadding(
                          context,
                          mobile: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          tablet: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          desktop: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        ),
                      ),
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getResponsiveFontSize(
                          context,
                          mobile: 14,
                          tablet: 15,
                          desktop: 16,
                        ),
                      ),
                      validator: (val) => val?.trim().isEmpty == true 
                          ? 'Please enter your name' 
                          : null,
                      textInputAction: TextInputAction.next,
                    ),
                    SizedBox(height: ResponsiveHelper.getResponsiveValue(
                      context,
                      mobile: 12,
                      tablet: 16,
                      desktop: 16,
                    )),
                    TextFormField(
                      controller: _emailController,
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.email),
                        contentPadding: ResponsiveHelper.getResponsivePadding(
                          context,
                          mobile: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          tablet: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          desktop: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        ),
                      ),
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getResponsiveFontSize(
                          context,
                          mobile: 14,
                          tablet: 15,
                          desktop: 16,
                        ),
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
                    SizedBox(height: ResponsiveHelper.getResponsiveValue(
                      context,
                      mobile: 12,
                      tablet: 16,
                      desktop: 16,
                    )),
                    TextFormField(
                      controller: _phoneController,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.phone),
                        contentPadding: ResponsiveHelper.getResponsivePadding(
                          context,
                          mobile: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
                          tablet: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
                          desktop: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                        ),
                      ),
                      style: TextStyle(
                        fontSize: ResponsiveHelper.getResponsiveFontSize(
                          context,
                          mobile: 14,
                          tablet: 15,
                          desktop: 16,
                        ),
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

              SizedBox(height: ResponsiveHelper.getResponsiveValue(
                context,
                mobile: 24,
                tablet: 32,
                desktop: 32,
              )),

                    SizedBox(height: ResponsiveHelper.getResponsiveValue(
                      context,
                      mobile: 20,
                      tablet: 24,
                      desktop: 24,
                    )),
                    
                    // Security notice
                    Text(
                      'Your payment is secured and encrypted with Paystack',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey,
                        fontSize: ResponsiveHelper.getResponsiveFontSize(
                          context,
                          mobile: 11,
                          tablet: 12,
                          desktop: 13,
                        ),
                      ),
                      textAlign: TextAlign.center,
                    ),
                    
                    SizedBox(height: ResponsiveHelper.getResponsiveValue(
                      context,
                      mobile: 6,
                      tablet: 8,
                      desktop: 8,
                    )),
                    
                    // Payment methods
                    Wrap(
                      alignment: WrapAlignment.center,
                      children: [
                        Icon(
                          Icons.credit_card,
                          size: ResponsiveHelper.getResponsiveValue(
                            context,
                            mobile: 14,
                            tablet: 16,
                            desktop: 16,
                          ),
                          color: Colors.grey,
                        ),
                        SizedBox(width: ResponsiveHelper.getResponsiveValue(
                          context,
                          mobile: 4,
                          tablet: 4,
                          desktop: 4,
                        )),
                        Flexible(
                          child: Text(
                            'Card • Bank Transfer • USSD',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey,
                              fontSize: ResponsiveHelper.getResponsiveFontSize(
                                context,
                                mobile: 11,
                                tablet: 12,
                                desktop: 13,
                              ),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ],
                    ),
                    
                    // Bottom padding to ensure content is scrollable above button
                    SizedBox(height: ResponsiveHelper.getResponsiveValue(
                      context,
                      mobile: 100,
                      tablet: 80,
                      desktop: 60,
                    )),
                  ],
                ),
              ),
            ),
          ),
          
          // Sticky Payment Button at bottom
          Container(
            padding: ResponsiveHelper.getResponsivePadding(
              context,
              mobile: const EdgeInsets.all(12),
              tablet: const EdgeInsets.all(16),
              desktop: const EdgeInsets.all(20),
            ),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _handlePayment,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                              padding: ResponsiveHelper.getResponsivePadding(
                                context,
                                mobile: const EdgeInsets.symmetric(vertical: 14),
                                tablet: const EdgeInsets.symmetric(vertical: 16),
                                desktop: const EdgeInsets.symmetric(vertical: 18),
                              ),
                              textStyle: TextStyle(
                                fontSize: ResponsiveHelper.getResponsiveFontSize(
                                  context,
                                  mobile: 16,
                                  tablet: 18,
                                  desktop: 20,
                                ),
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.lock,
                                  size: ResponsiveHelper.getResponsiveValue(
                                    context,
                                    mobile: 18,
                                    tablet: 20,
                                    desktop: 22,
                                  ),
                                ),
                                SizedBox(width: ResponsiveHelper.getResponsiveValue(
                                  context,
                                  mobile: 6,
                                  tablet: 8,
                                  desktop: 8,
                                )),
                                Flexible(
                                  child: Text('Pay ${currencyFormatter.format(_totalPrice)}'),
                                ),
                              ],
                            ),
                          ),
                        ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(BuildContext context, String label, String value, {bool isTotal = false}) {
    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: ResponsiveHelper.getResponsiveValue(
          context,
          mobile: 4.0,
          tablet: 5.0,
          desktop: 6.0,
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Flexible(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                fontSize: ResponsiveHelper.getResponsiveFontSize(
                  context,
                  mobile: isTotal ? 14 : 13,
                  tablet: isTotal ? 15 : 14,
                  desktop: isTotal ? 16 : 15,
                ),
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
                fontSize: ResponsiveHelper.getResponsiveFontSize(
                  context,
                  mobile: isTotal ? 16 : 14,
                  tablet: isTotal ? 18 : 15,
                  desktop: isTotal ? 20 : 16,
                ),
                color: isTotal ? Colors.green : null,
              ),
              textAlign: TextAlign.end,
            ),
          ),
        ],
      ),
    );
  }
}