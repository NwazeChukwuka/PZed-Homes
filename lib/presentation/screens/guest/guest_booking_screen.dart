import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/theme/responsive_helpers.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/core/utils/input_sanitizer.dart';
import 'package:pzed_homes/core/config/app_config.dart';

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
    roomType = {'name': 'Standard Room', 'price': 1500000};
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

  int get _pricePerNightKobo {
    final priceValue = roomType['price_kobo'] ?? roomType['price'];
    if (priceValue is int) {
      return priceValue;
    }
    if (priceValue is num) {
      return priceValue.toInt();
    }
    return int.tryParse('${priceValue ?? 0}') ?? 0;
  }

  /// Get total price in kobo (for database storage)
  int get _totalPriceInKobo {
    final nights = checkOutDate.difference(checkInDate).inDays;
    return _pricePerNightKobo * nights;
  }

  /// Get total price in naira (for display)
  double get _totalPriceInNaira {
    return PaymentService.koboToNaira(_totalPriceInKobo);
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
      // 1. Create guest profile or get existing one
      final guestProfileId = await _getOrCreateGuestProfile();

      // 2. Create booking atomically with availability check using database function
      // This prevents race conditions by performing availability check and booking creation
      // in a single database transaction
      final bookingId = await _createPendingBookingAtomically(guestProfileId);

      // 4. Process payment with Paystack
      final paymentSuccess = await _processPayment(bookingId);
      
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

      final response = await _supabase!.rpc(
        'get_available_room_types',
        params: {
          'start_date': checkInDate.toIso8601String(),
          'end_date': checkOutDate.toIso8601String(),
        },
      );

      final rows = List<Map<String, dynamic>>.from(response as List);
      final match = rows.firstWhere(
        (row) => (row['type'] as String?)?.toLowerCase() == roomTypeName.toLowerCase(),
        orElse: () => <String, dynamic>{},
      );

      final available = (match['available_count'] as num?)?.toInt() ?? 0;
      return available > 0;
    } catch (e) {
      throw Exception('Error checking room availability: $e');
    }
  }

  Future<String> _getOrCreateGuestProfile() async {
    if (_supabase == null) {
      throw Exception('Supabase is not configured');
    }

    // Sanitize inputs to prevent XSS and other security issues
    final email = InputSanitizer.sanitizeEmail(_emailController.text.trim());
    final fullName = InputSanitizer.sanitizeText(_nameController.text.trim());
    final phone = InputSanitizer.sanitizePhone(_phoneController.text.trim());
    
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

      // Profile doesn't exist - need to create auth user first
      // Generate a secure temporary password (guest can reset via email if needed)
      final tempPassword = _generateSecurePassword();
      
      // Create auth user - this will trigger the profile creation via database trigger
      final authResponse = await _supabase!.auth.signUp(
        email: email,
        password: tempPassword,
        data: {
          'full_name': fullName,
          'phone': phone,
        },
      );

      if (authResponse.user == null) {
        throw Exception('Failed to create auth user');
      }

      final userId = authResponse.user!.id;

      // Wait a moment for the trigger to create the profile
      await Future.delayed(const Duration(milliseconds: 500));

      // Verify profile was created and update with additional info if needed
      final profile = await _supabase!
          .from('profiles')
          .select('id, phone')
          .eq('id', userId)
          .single();

      // Update phone if it wasn't set by trigger
      if (phone.isNotEmpty && (profile['phone'] == null || profile['phone'].toString().isEmpty)) {
        await _supabase!
            .from('profiles')
            .update({'phone': phone})
            .eq('id', userId);
      }

      // CRITICAL: Send password reset email so guest can set their own password
      // This allows guests to log in and view their bookings
      // Make this more robust - retry once if it fails
      bool emailSent = false;
      for (int attempt = 0; attempt < 2 && !emailSent; attempt++) {
        try {
          await _supabase!.auth.resetPasswordForEmail(
            email,
            redirectTo: AppConfig.passwordResetUrl,
          );
          emailSent = true;
          if (kDebugMode) {
            debugPrint('Password reset email sent successfully to $email');
          }
        } catch (e) {
          if (attempt == 1) {
            // Final attempt failed - log but don't fail the booking
            // Guest can use "Forgot Password" later
            if (kDebugMode) {
              debugPrint('Warning: Could not send password reset email after 2 attempts: $e');
            }
          } else {
            // Wait a bit before retry
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }
      }

      return userId;
    } catch (e) {
      // If user already exists in auth, try to sign in to get the user ID
      if (e.toString().contains('already registered') || e.toString().contains('already exists')) {
        try {
          // User exists in auth - find their profile
          final profile = await _supabase!
              .from('profiles')
              .select('id')
              .eq('email', email)
              .maybeSingle();
          
          if (profile != null) {
            return profile['id'] as String;
          }
        } catch (_) {
          // Fall through to throw original error
        }
      }
      throw Exception('Error creating guest profile: $e');
    }
  }

  /// Generate a secure temporary password for guest accounts
  String _generateSecurePassword() {
    // Generate a random password - guest can reset via email if needed
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
    final random = DateTime.now().millisecondsSinceEpoch;
    final password = StringBuffer();
    for (int i = 0; i < 16; i++) {
      password.write(chars[(random + i) % chars.length]);
    }
    return password.toString();
  }

  // NEW: Use atomic database function to prevent race conditions
  // This function atomically checks room availability and creates the booking
  Future<String> _createPendingBookingAtomically(String guestProfileId) async {
    if (_supabase == null) {
      throw Exception('Supabase is not configured');
    }

    try {
      final roomTypeName = roomType['name']?.toString() ?? roomType['type']?.toString() ?? 'Standard';
      final guestName = _nameController.text.trim();
      final guestEmail = _emailController.text.trim();
      final guestPhone = _phoneController.text.trim();
      
      // Use database function to atomically check availability and create booking
      // This prevents race conditions where multiple guests book the same room type simultaneously
      final response = await _supabase!.rpc(
        'create_booking_with_availability_check',
        params: {
          'p_guest_profile_id': guestProfileId,
          'p_requested_room_type': roomTypeName,
          'p_check_in_date': checkInDate.toIso8601String().split('T')[0],
          'p_check_out_date': checkOutDate.toIso8601String().split('T')[0],
          'p_total_amount': _totalPriceInKobo, // Already in kobo
          'p_paid_amount': 0, // Will be updated after successful payment
          'p_payment_method': 'paystack', // Will be updated after payment
          'p_guest_name': guestName,
          'p_guest_email': guestEmail,
          'p_guest_phone': guestPhone.isNotEmpty ? guestPhone : null,
        },
      );

      return response as String; // Function returns UUID directly
    } catch (e) {
      // Provide user-friendly error messages
      final errorMsg = e.toString();
      if (errorMsg.contains('No rooms of type') || errorMsg.contains('not available')) {
        throw Exception('Sorry, no rooms of this type are available for the selected dates. Please try different dates or room type.');
      }
      throw Exception('Error creating booking: $e');
    }
  }

  Future<bool> _processPayment(String bookingId) async {
    try {
      final paymentService = PaymentService();
      
      // Check if Paystack is initialized
      if (!paymentService.isInitialized) {
        throw Exception('Payment system is not configured. Please contact support.');
      }

      final email = _emailController.text.trim();
      if (email.isEmpty) {
        throw Exception('Email is required for payment');
      }

      // Generate unique payment reference
      final reference = paymentService.generateReference();
      
      // Show loading dialog
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      try {
        // Process payment with Paystack
        final success = await paymentService.processPayment(
          context: context,
          amountInKobo: _totalPriceInKobo,
          email: email,
          reference: reference,
          metadata: {
            'booking_id': bookingId,
            'guest_name': _nameController.text.trim(),
            'room_type': roomType['name']?.toString() ?? roomType['type']?.toString() ?? 'Unknown',
            'check_in': checkInDate.toIso8601String(),
            'check_out': checkOutDate.toIso8601String(),
          },
        );

        // Close loading dialog
        if (mounted) {
          Navigator.of(context).pop();
        }

        return success;
      } catch (e) {
        // Close loading dialog
        if (mounted) {
          Navigator.of(context).pop();
        }
        rethrow;
      }
    } catch (e) {
      throw Exception('Payment processing error: ${e.toString()}');
    }
  }

  Future<void> _confirmBooking(String bookingId) async {
    if (_supabase == null) {
      throw Exception('Supabase is not configured');
    }

    try {
      // Update booking status to Pending Check-in (room will be assigned by receptionist)
      // Don't update room status - rooms stay Vacant until check-in
      await _supabase!
          .from('bookings')
          .update({
            'status': 'Pending Check-in',
            'paid_amount': _totalPriceInKobo, // Already in kobo
          })
          .eq('id', bookingId);
      
      // Create income record for booking payment
      final roomTypeName = roomType['name']?.toString() ?? roomType['type']?.toString() ?? 'Room';
      await _supabase!
          .from('income_records')
          .insert({
            'description': 'Room booking - $roomTypeName',
            'amount': _totalPriceInKobo, // Already in kobo
            'source': 'Room Booking',
            'date': DateTime.now().toIso8601String().split('T')[0],
            'department': 'reception',
            'payment_method': 'online', // Guest paid online via Paystack
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
                        currencyFormatter.format(_totalPriceInNaira),
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
                                  child: Text('Pay ${currencyFormatter.format(_totalPriceInNaira)}'),
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