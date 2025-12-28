import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/utils/input_sanitizer.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateBookingScreen extends StatefulWidget {
  const CreateBookingScreen({super.key});

  @override
  State<CreateBookingScreen> createState() => _CreateBookingScreenState();
}

class _CreateBookingScreenState extends State<CreateBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _guestNameController = TextEditingController();
  final _guestEmailController = TextEditingController();
  final _guestPhoneController = TextEditingController();
  final _dataService = DataService();
  final _supabase = Supabase.instance.client;

  DateTime? _checkInDate;
  DateTime? _checkOutDate;
  String? _selectedRoomTypeId;
  String? _selectedRoomId;
  String _paymentMethod = 'Cash'; // Default payment method
  List<Map<String, dynamic>> _roomTypes = [];
  List<Map<String, dynamic>> _availableRooms = [];
  bool _isLoading = false;
  bool _isFetchingRooms = false;

  @override
  void initState() {
    super.initState();
    _loadRoomTypes();
  }

  @override
  void dispose() {
    _guestNameController.dispose();
    _guestEmailController.dispose();
    _guestPhoneController.dispose();
    super.dispose();
  }

  Future<void> _loadRoomTypes() async {
    try {
      final response = await _supabase
          .from('room_types')
          .select('id, type, price, description')
          .order('price');
      
      setState(() {
        _roomTypes = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load room types. Please check your connection and try again.',
          onRetry: _loadRoomTypes,
        );
      }
    }
  }

  Future<void> _findAvailableRooms() async {
    if (_checkInDate == null || _checkOutDate == null || _selectedRoomTypeId == null) {
      setState(() => _availableRooms = []);
      return;
    }

    setState(() => _isFetchingRooms = true);
    try {
      // Get conflicting bookings
      // Correct overlap logic: Two bookings overlap if:
      // booking.check_in_date < our.check_out_date AND booking.check_out_date > our.check_in_date
      final conflictingBookings = await _supabase
          .from('bookings')
          .select('room_id')
          .or('status.eq.Pending Check-in,status.eq.Checked-in')
          .lt('check_in_date', _checkOutDate!.toIso8601String())
          .gt('check_out_date', _checkInDate!.toIso8601String());

      final bookedRoomIds = (conflictingBookings as List)
          .where((b) => b['room_id'] != null)
          .map((b) => b['room_id'] as String)
          .toSet();

      // Get available rooms of selected type
      // _selectedRoomTypeId is a UUID from room_types.id, so we need to match against rooms.type_id
      var query = _supabase
          .from('rooms')
          .select()
          .eq('status', 'Vacant');
      
      if (_selectedRoomTypeId != null) {
        query = query.eq('type_id', _selectedRoomTypeId!); // Use type_id (UUID) not type (TEXT)
      }
      
      final rooms = await query
          .not('id', 'in', bookedRoomIds.isEmpty ? [''] : bookedRoomIds.toList());

      setState(() {
        _availableRooms = List<Map<String, dynamic>>.from(rooms);
        _selectedRoomId = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isFetchingRooms = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to check availability. Please try again.',
          onRetry: _findAvailableRooms,
        );
      }
    } finally {
      setState(() => _isFetchingRooms = false);
    }
  }

  Future<void> _selectDate(BuildContext context, bool isCheckIn) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: isCheckIn ? DateTime.now() : _checkInDate?.add(const Duration(days: 1)) ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      selectableDayPredicate: (DateTime day) {
        if (isCheckIn) return true;
        return _checkInDate == null || day.isAfter(_checkInDate!);
      },
    );

    if (picked != null) {
      setState(() {
        if (isCheckIn) {
          _checkInDate = picked;
          if (_checkOutDate != null && _checkOutDate!.isBefore(picked)) {
            _checkOutDate = null;
          }
        } else {
          _checkOutDate = picked;
        }
      });
      _findAvailableRooms();
    }
  }

  Future<void> _createBooking() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final userId = authService.currentUser?.id ?? 'system';
      
      // Get or create guest profile
      String guestProfileId;
      // Sanitize inputs to prevent XSS and other security issues
      final email = InputSanitizer.sanitizeEmail(_guestEmailController.text.trim());
      final fullName = InputSanitizer.sanitizeText(_guestNameController.text.trim());
      final phone = InputSanitizer.sanitizePhone(_guestPhoneController.text.trim());
      
      final existingProfile = await _supabase
          .from('profiles')
          .select('id')
          .eq('email', email)
          .maybeSingle();

      if (existingProfile != null) {
        guestProfileId = existingProfile['id'] as String;
      } else {
        // Profile doesn't exist - need to create auth user first
        // Generate a secure temporary password
        final tempPassword = _generateSecurePassword();
        
        // Create auth user - this will trigger the profile creation via database trigger
        final authResponse = await _supabase.auth.signUp(
          email: email,
          password: tempPassword,
          data: {
            'full_name': fullName,
            'phone': phone,
          },
        );

        if (authResponse.user == null) {
          throw Exception('Failed to create auth user for guest');
        }

        guestProfileId = authResponse.user!.id;

        // Wait a moment for the trigger to create the profile
        await Future.delayed(const Duration(milliseconds: 500));

        // Update phone if it wasn't set by trigger
        if (phone.isNotEmpty) {
          await _supabase
              .from('profiles')
              .update({'phone': phone})
              .eq('id', guestProfileId);
        }
      }

      // Get room type name for requested_room_type
      final selectedRoomType = _roomTypes.firstWhere(
        (type) => type['id'] == _selectedRoomTypeId,
        orElse: () => {'type': 'Standard'},
      );
      
      // Calculate total amount (nights * room price)
      final nights = _checkOutDate!.difference(_checkInDate!).inDays;
      final roomPrice = selectedRoomType['price'] as int? ?? 0;
      final totalAmount = nights * roomPrice;
      
      // CRITICAL: Validate payment method and amount
      // Ensure payment method is selected and valid
      if (_paymentMethod.isEmpty) {
        throw Exception('Please select a payment method');
      }
      
      int paidAmount = 0;
      if (_paymentMethod == 'Cash' || _paymentMethod == 'Card' || _paymentMethod == 'Bank Transfer') {
        // For paid bookings, require full payment
        paidAmount = totalAmount;
      } else if (_paymentMethod == 'Credit') {
        // Credit bookings can have partial or zero payment
        paidAmount = 0;
      } else {
        throw Exception('Invalid payment method selected. Please choose Cash, Card, Bank Transfer, or Credit.');
      }
      
      // Additional validation: Ensure total amount is positive
      if (totalAmount <= 0) {
        throw Exception('Invalid booking amount. Please check room selection and dates.');
      }
      
      await _dataService.createBooking({
        'guest_profile_id': guestProfileId, // Use the profile ID we just created/got
        'room_id': _selectedRoomId, // Can be null - receptionist can assign later
        'requested_room_type': selectedRoomType['type'] as String?,
        'check_in': _checkInDate!.toIso8601String(),
        'check_out': _checkOutDate!.toIso8601String(),
        'status': 'Pending Check-in',
        'total_amount': totalAmount, // Already in kobo from room_types.price
        'paid_amount': paidAmount, // Based on payment method
        'payment_method': _paymentMethod.toLowerCase(),
      });

      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Booking created successfully!');
        context.pop(true);
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to create booking. Please try again.',
          onRetry: _createBooking,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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

  @override
  Widget build(BuildContext context) {
    final dateFormatter = DateFormat('EEE, MMM d, yyyy');

    return Scaffold(
      appBar: AppBar(
        title: const Text('Create New Booking'),
        backgroundColor: Colors.teal,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Date Selection
              _buildDateSelector(
                'Check-in Date',
                _checkInDate,
                dateFormatter,
                () => _selectDate(context, true),
              ),
              const SizedBox(height: 16),
              _buildDateSelector(
                'Check-out Date',
                _checkOutDate,
                dateFormatter,
                () => _selectDate(context, false),
              ),
              const SizedBox(height: 24),

              // Room Type Selection
              DropdownButtonFormField<String>(
                value: _selectedRoomTypeId,
                decoration: const InputDecoration(
                  labelText: 'Room Type',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.hotel),
                ),
                items: _roomTypes.map((type) => DropdownMenuItem(
                  value: type['id'] as String,
                  child: Text('${type['type']} - ₦${type['price']}'),
                )).toList(),
                onChanged: (value) {
                  setState(() => _selectedRoomTypeId = value);
                  _findAvailableRooms();
                },
                validator: (val) => val == null ? 'Please select a room type' : null,
              ),
              const SizedBox(height: 16),

              // Available Rooms
              if (_isFetchingRooms)
                const Center(child: CircularProgressIndicator())
              else if (_selectedRoomTypeId != null && _availableRooms.isEmpty)
                const Text(
                  'No rooms available for selected dates',
                  style: TextStyle(color: Colors.orange),
                )
              else if (_availableRooms.isNotEmpty)
                DropdownButtonFormField<String>(
                  value: _selectedRoomId,
                  decoration: const InputDecoration(
                    labelText: 'Available Rooms',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.meeting_room),
                  ),
                  items: _availableRooms.map((room) => DropdownMenuItem(
                    value: room['id'] as String,
                    child: Text('Room ${room['room_number']}'),
                  )).toList(),
                  onChanged: (value) => setState(() => _selectedRoomId = value),
                  validator: (val) => val == null ? 'Please select a room' : null,
                ),
              
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),

              // Guest Information
              const Text(
                'Guest Information',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _guestNameController,
                decoration: const InputDecoration(
                  labelText: 'Guest Full Name',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
                validator: (val) => val?.isEmpty == true ? 'Please enter guest name' : null,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _guestEmailController,
                decoration: const InputDecoration(
                  labelText: 'Email Address',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.email),
                ),
                keyboardType: TextInputType.emailAddress,
                validator: (val) {
                  if (val?.isEmpty == true) return 'Please enter email';
                  if (!val!.contains('@')) return 'Please enter valid email';
                  return null;
                },
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _guestPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
                validator: (val) => val?.isEmpty == true ? 'Please enter phone number' : null,
              ),
              const SizedBox(height: 16),

              // Payment Method
              DropdownButtonFormField<String>(
                value: _paymentMethod,
                decoration: const InputDecoration(
                  labelText: 'Payment Method',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.payment),
                ),
                items: const [
                  DropdownMenuItem(value: 'Cash', child: Text('Cash')),
                  DropdownMenuItem(value: 'Transfer', child: Text('Bank Transfer')),
                  DropdownMenuItem(value: 'POS', child: Text('POS')),
                  DropdownMenuItem(value: 'Credit', child: Text('Credit')),
                ],
                onChanged: (value) => setState(() => _paymentMethod = value!),
              ),

              const SizedBox(height: 32),

              // Submit Button
              _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _createBooking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontSize: 18),
                        ),
                        child: const Text('Create Booking'),
                      ),
                    ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSelector(String title, DateTime? date, DateFormat formatter, VoidCallback onTap) {
    return Card(
      elevation: 2,
      child: ListTile(
        leading: Icon(
          title.contains('Check-in') ? Icons.login : Icons.logout,
          color: Colors.teal,
        ),
        title: Text(title),
        subtitle: Text(date != null ? formatter.format(date) : 'Select Date'),
        trailing: const Icon(Icons.calendar_today),
        onTap: onTap,
      ),
    );
  }
}