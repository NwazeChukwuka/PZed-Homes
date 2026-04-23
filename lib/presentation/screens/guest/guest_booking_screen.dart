import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/theme/responsive_helpers.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/core/utils/input_sanitizer.dart';
import 'package:pzed_homes/data/models/user.dart';

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
  bool _termsAccepted = false;
  String? _paymentReference;
  static const String _termsVersion = 'v1';
  bool _loggedInGuestPrefillScheduled = false;
  bool _isLoadingTransferConfig = false;
  bool _usePaystack = false;
  bool _paystackConfigured = false;
  int _transferDisplayCount = 1;
  String _supportPhone = '+2348157505978';
  List<Map<String, dynamic>> _transferAccounts = [];
  /// Name and email from profile; read-only for logged-in guests.
  bool _lockedNameAndEmail = false;
  /// Phone read-only when loaded from profile and non-empty.
  bool _phoneLocked = false;

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
    roomType = {
      'name': 'Standard Room',
      'price': 1500000,
      'price_kobo': 1500000,
    };
    checkInDate = DateTime.now();
    checkOutDate = DateTime.now().add(const Duration(days: 1));
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadTransferConfig());
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
    if (!_loggedInGuestPrefillScheduled) {
      _loggedInGuestPrefillScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyLoggedInGuestPrefill());
    }
  }

  bool _isLoggedInGuestAccount(AuthService auth) {
    final u = auth.currentUser;
    if (u == null) return false;
    return u.roles.contains(AppRole.guest);
  }

  Future<void> _applyLoggedInGuestPrefill() async {
    if (!mounted) return;
    final auth = Provider.of<AuthService>(context, listen: false);
    if (!_isLoggedInGuestAccount(auth)) return;

    final u = auth.currentUser!;
    final hasName = u.name.trim().isNotEmpty;
    final hasEmail = u.email.trim().isNotEmpty;
    if (hasName) {
      _nameController.text = u.name.trim();
    }
    if (hasEmail) {
      _emailController.text = u.email.trim();
    }
    if (hasName || hasEmail) {
      setState(() => _lockedNameAndEmail = true);
    }

    await _loadPhoneFromProfile();
  }

  Future<void> _loadPhoneFromProfile() async {
    final auth = Provider.of<AuthService>(context, listen: false);
    final id = auth.currentUser?.id;
    if (id == null || _supabase == null || !mounted) return;
    try {
      final row = await _supabase!.from('profiles').select('phone').eq('id', id).maybeSingle();
      final p = row?['phone']?.toString().trim() ?? '';
      if (!mounted) return;
      setState(() {
        if (p.isNotEmpty) {
          _phoneController.text = p;
          _phoneLocked = true;
        } else {
          _phoneLocked = false;
        }
      });
    } catch (_) {
      if (mounted) setState(() => _phoneLocked = false);
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

  Future<void> _loadTransferConfig() async {
    setState(() => _isLoadingTransferConfig = true);
    try {
      final config = await PaymentService().getTransferConfig();
      if (!mounted) return;
      final accounts = List<Map<String, dynamic>>.from(config['accounts'] as List? ?? const []);
      final active = accounts.where((a) => a['active'] == true).toList()
        ..sort((a, b) {
          final ap = int.tryParse(a['priority']?.toString() ?? '') ?? 0;
          final bp = int.tryParse(b['priority']?.toString() ?? '') ?? 0;
          return ap.compareTo(bp);
        });
      setState(() {
        _transferAccounts = active;
        _transferDisplayCount = (config['display_count'] as int? ?? 1).clamp(1, 10);
        _supportPhone =
            config['support_phone']?.toString().trim().isNotEmpty == true
                ? config['support_phone'].toString().trim()
                : '+2348157505978';
        _paystackConfigured = config['paystack_configured'] == true;
        _isLoadingTransferConfig = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _transferAccounts = [];
        _paystackConfigured = false;
        _isLoadingTransferConfig = false;
      });
    }
  }

  Future<bool> _validateCheckoutInputs() async {
    if (!_formKey.currentState!.validate()) return false;
    if (!_termsAccepted) {
      ErrorHandler.showWarningMessage(
        context,
        'Please accept the terms and cancellation policy to continue.',
      );
      return false;
    }

    // Check if Supabase is initialized
    if (_supabase == null) {
      ErrorHandler.handleError(
        context,
        Exception('Service is currently unavailable. Please try again later.'),
      );
      return false;
    }
    return true;
  }

  Future<void> _handlePayment() async {
    final canProceed = await _validateCheckoutInputs();
    if (!mounted) return;
    if (!canProceed) return;
    if (!_usePaystack && _transferAccounts.isEmpty) {
      ErrorHandler.showWarningMessage(
        context,
        'No transfer accounts are available yet. Please request account information first.',
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. Use guest account only if already logged in
      final guestProfileId = _supabase!.auth.currentUser?.id;

      if (_usePaystack) {
        final paymentService = PaymentService();
        if (!paymentService.isInitialized) {
          throw Exception('Paystack is not configured. Use bank transfer or contact support.');
        }
        _paymentReference ??= paymentService.generateReference();

        final bookingId = await _createPendingBookingAtomically(
          guestProfileId,
          paymentMethod: 'paystack',
          paymentProvider: 'paystack',
          paidAmount: 0,
        );

        final paymentSuccess = await _processPayment(bookingId);
        if (paymentSuccess) {
          await _confirmBooking(bookingId);
          final refText = _paymentReference == null ? '' : ' Reference: $_paymentReference';
          _showSuccess(
            'Payment successful! Your booking is confirmed. A room will be assigned when you arrive.$refText',
          );
        } else {
          await _supabase!.from('bookings').delete().eq('id', bookingId);
          _showError('Payment failed. Please try again.');
        }
      } else {
        _paymentReference = PaymentService().generateReference();
        await _createPendingBookingAtomically(
          guestProfileId,
          paymentMethod: 'bank_transfer_pending',
          paymentProvider: 'manual_transfer',
          paidAmount: 0,
        );
        _showSuccess(
          'Transfer declaration received. Please keep your transfer receipt and present it at reception for room assignment.',
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _handlePayment: $e\n$stackTrace');
      if (mounted) ErrorHandler.handleError(context, e, stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // Guest accounts are created only via explicit signup on the landing page.

  // NEW: Use atomic database function to prevent race conditions
  // This function atomically checks room availability and creates the booking
  Future<String> _createPendingBookingAtomically(
    String? guestProfileId, {
    required String paymentMethod,
    required String paymentProvider,
    required int paidAmount,
  }) async {
    if (_supabase == null) {
      throw Exception('Service is currently unavailable. Please try again later.');
    }

    try {
      final roomTypeName = roomType['name']?.toString() ?? roomType['type']?.toString() ?? 'Standard';
      final guestName = InputSanitizer.sanitizeText(_nameController.text.trim());
      final guestEmail = InputSanitizer.sanitizeEmail(_emailController.text.trim());
      final guestPhone = InputSanitizer.sanitizePhone(_phoneController.text.trim());
      
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
          'p_paid_amount': paidAmount,
          'p_payment_method': paymentMethod,
          'p_payment_reference': _paymentReference,
          'p_payment_provider': paymentProvider,
          'p_guest_name': guestName,
          'p_guest_email': guestEmail,
          'p_guest_phone': guestPhone.isNotEmpty ? guestPhone : null,
          'p_terms_accepted': _termsAccepted,
          'p_terms_version': _termsVersion,
        },
      );

      return response as String; // Function returns UUID directly
    } catch (e) {
      // Provide user-friendly error messages
      final errorMsg = e.toString();
      if (errorMsg.contains('No rooms of type') || errorMsg.contains('not available')) {
        throw Exception('Sorry, no rooms of this type are available for the selected dates. Please try different dates or room type.');
      }
      rethrow;
    }
  }

  Future<void> _handleCouldNotTransfer() async {
    final canProceed = await _validateCheckoutInputs();
    if (!mounted) return;
    if (!canProceed) return;

    String reason = 'Bank app/network issue';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('Could Not Make Transfer'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select the reason so we can improve payment support:'),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    labelText: 'Reason',
                  ),
                  items: const [
                    DropdownMenuItem(value: 'Bank app/network issue', child: Text('Bank app/network issue')),
                    DropdownMenuItem(value: 'Transfer limit exceeded', child: Text('Transfer limit exceeded')),
                    DropdownMenuItem(value: 'Insufficient balance', child: Text('Insufficient balance')),
                    DropdownMenuItem(value: 'Did not trust transfer option', child: Text('Did not trust transfer option')),
                    DropdownMenuItem(value: 'Other', child: Text('Other')),
                  ],
                  onChanged: (value) => setDialogState(() => reason = value ?? reason),
                ),
              ],
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Close')),
              ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Submit')),
            ],
          );
        },
      ),
    );
    if (confirmed != true) return;

    setState(() => _isLoading = true);
    try {
      final guestProfileId = _supabase!.auth.currentUser?.id;
      _paymentReference = PaymentService().generateReference();
      final bookingId = await _createPendingBookingAtomically(
        guestProfileId,
        paymentMethod: 'bank_transfer_unpaid',
        paymentProvider: 'manual_transfer',
        paidAmount: 0,
      );
      try {
        await _supabase!.rpc(
          'update_booking_lifecycle_status',
          params: {
            'p_booking_id': bookingId,
            'p_new_status': 'Cancelled',
            'p_reason': 'Transfer not made: $reason',
          },
        );
        await _supabase!.from('bookings').update({
          'notes': 'Transfer not made reason: $reason',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', bookingId);
      } catch (_) {
        await _supabase!.from('bookings').update({
          'status': 'Cancelled',
          'notes': 'Transfer not made reason: $reason',
          'updated_at': DateTime.now().toIso8601String(),
        }).eq('id', bookingId);
      }
      _showSuccess('Thanks for your feedback. You can retry booking when ready.');
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _handleCouldNotTransfer: $e\n$stackTrace');
      if (mounted) ErrorHandler.handleError(context, e, stackTrace: stackTrace);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copyAccountNumber(String accountNumber) async {
    await Clipboard.setData(ClipboardData(text: accountNumber));
    if (!mounted) return;
    ErrorHandler.showSuccessMessage(context, 'Account number copied.');
  }

  Future<void> _requestAccountInformation() async {
    final normalized = _supportPhone.trim();
    final uri = Uri.parse('tel:$normalized');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
      return;
    }
    if (!mounted) return;
    ErrorHandler.showWarningMessage(
      context,
      'No account details configured. Please contact hotel support: $normalized',
    );
  }

  Future<bool> _processPayment(String bookingId) async {
    try {
      final paymentService = PaymentService();
      
      // Check if Paystack is initialized
      if (!paymentService.isInitialized) {
        throw Exception('Payment system is not configured. Please contact support.');
      }

      final email = InputSanitizer.sanitizeEmail(_emailController.text.trim());
      if (email.isEmpty) {
        throw Exception('Email is required for payment');
      }

      final reference = _paymentReference ?? paymentService.generateReference();
      _paymentReference = reference;
      
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
      rethrow;
    }
  }

  Future<void> _confirmBooking(String bookingId) async {
    if (_supabase == null) {
      throw Exception('Service is currently unavailable. Please try again later.');
    }

    try {
      final response = await _supabase!.functions.invoke(
        'verify_guest_booking_payment',
        body: {
          'booking_id': bookingId,
          'payment_reference': _paymentReference,
          'guest_email': InputSanitizer.sanitizeEmail(_emailController.text.trim()),
        },
      );
      if (response.status != 200) {
        throw Exception('Payment verification failed');
      }
      
      // Note: Room status remains 'Vacant' - receptionist will assign room and update status at check-in
    } catch (e) {
      rethrow;
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
          final auth = Provider.of<AuthService>(context, listen: false);
          context.go(auth.currentUser != null ? '/guest/home' : '/guest');
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
              if (_lockedNameAndEmail) ...[
                Text(
                  'Booking as ${_nameController.text.isNotEmpty ? _nameController.text : 'Guest'}',
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
                const SizedBox(height: 6),
                Text(
                  'Your profile details below are locked for this reservation. Add or update phone if needed.',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.grey[700],
                        height: 1.35,
                      ),
                ),
              ] else
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
                      readOnly: _lockedNameAndEmail,
                      enableInteractiveSelection: true,
                      decoration: InputDecoration(
                        labelText: 'Full Name',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.person),
                        filled: _lockedNameAndEmail,
                        fillColor: _lockedNameAndEmail ? Colors.grey.shade100 : null,
                        helperText: _lockedNameAndEmail ? 'From your account' : null,
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
                      readOnly: _lockedNameAndEmail,
                      enableInteractiveSelection: true,
                      decoration: InputDecoration(
                        labelText: 'Email Address',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.email),
                        filled: _lockedNameAndEmail,
                        fillColor: _lockedNameAndEmail ? Colors.grey.shade100 : null,
                        helperText: _lockedNameAndEmail ? 'From your account' : null,
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
                      readOnly: _phoneLocked,
                      enableInteractiveSelection: true,
                      decoration: InputDecoration(
                        labelText: 'Phone Number',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.phone),
                        filled: _phoneLocked,
                        fillColor: _phoneLocked ? Colors.grey.shade100 : null,
                        helperText: _phoneLocked ? 'From your account' : 'Required for payment confirmation',
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

              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Bank Transfer (Primary Option)',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Make transfer to one of the accounts below, then tap "I have made the transfer". '
                        'Please keep your transfer receipt and present it at reception so your room can be assigned.',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Colors.grey[700],
                            ),
                      ),
                      const SizedBox(height: 10),
                      if (_isLoadingTransferConfig)
                        const Center(child: CircularProgressIndicator())
                      else if (_transferAccounts.isEmpty)
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'No transfer account details are currently available.',
                              style: TextStyle(color: Colors.orange),
                            ),
                            const SizedBox(height: 10),
                            OutlinedButton.icon(
                              onPressed: _requestAccountInformation,
                              icon: const Icon(Icons.call),
                              label: const Text('Request account information'),
                            ),
                          ],
                        )
                      else
                        ..._transferAccounts
                            .take(_transferDisplayCount.clamp(1, 10))
                            .map(
                              (account) => Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(account['bank_name']?.toString() ?? 'Bank'),
                                  subtitle: Text(
                                    '${account['account_name']?.toString() ?? ''}\n'
                                    '${account['account_number']?.toString() ?? ''}',
                                  ),
                                  isThreeLine: true,
                                  trailing: IconButton(
                                    tooltip: 'Copy account number',
                                    icon: const Icon(Icons.copy),
                                    onPressed: () => _copyAccountNumber(
                                      account['account_number']?.toString() ?? '',
                                    ),
                                  ),
                                ),
                              ),
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
                    
                    // Security notice
                    Text(
                      'Your payment is secured and encrypted',
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
                    Text(
                      _paystackConfigured
                          ? 'Bank Transfer • Optional Paystack'
                          : 'Bank Transfer',
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
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 10,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Checkbox(
                        value: _termsAccepted,
                        onChanged: (value) {
                          setState(() => _termsAccepted = value ?? false);
                        },
                      ),
                      Expanded(
                        child: GestureDetector(
                          onTap: () => setState(() => _termsAccepted = !_termsAccepted),
                          child: Text(
                            'I agree to the booking terms & cancellation policy',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_paystackConfigured)
                    SwitchListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Use Paystack instead'),
                      subtitle: const Text('Turn on to pay instantly with card/USSD'),
                      value: _usePaystack,
                      onChanged: _isLoading
                          ? null
                          : (value) => setState(() => _usePaystack = value),
                    ),
                  _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : _usePaystack
                          ? SizedBox(
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
                                child: Text('Pay ${currencyFormatter.format(_totalPriceInNaira)}'),
                              ),
                            )
                          : Column(
                              children: [
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _handlePayment,
                                    icon: const Icon(Icons.verified_user),
                                    label: const Text('I have made the transfer'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green[700],
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: OutlinedButton(
                                    onPressed: _handleCouldNotTransfer,
                                    child: const Text("I couldn't make the transfer"),
                                  ),
                                ),
                              ],
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