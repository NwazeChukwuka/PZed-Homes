import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/core/utils/input_sanitizer.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CreateBookingScreen extends StatefulWidget {
  const CreateBookingScreen({super.key});

  @override
  State<CreateBookingScreen> createState() => _CreateBookingScreenState();
}

class _CreateBookingScreenState extends State<CreateBookingScreen> {
  final _formKey = GlobalKey<FormState>();
  final _guestNameController = TextEditingController();
  final _guestPhoneController = TextEditingController();
  final _amountPaidController = TextEditingController();
  final _discountReasonController = TextEditingController();
  final _approvedByController = TextEditingController(); // For credit bookings
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
  bool _discountApplied = false;

  @override
  void initState() {
    super.initState();
    _loadRoomTypes();
  }

  @override
  void dispose() {
    _guestNameController.dispose();
    _guestPhoneController.dispose();
    _amountPaidController.dispose();
    _discountReasonController.dispose();
    _approvedByController.dispose();
    super.dispose();
  }
  
  // Calculate base total amount (nights * room price)
  int get _baseTotalAmount {
    if (_checkInDate == null || _checkOutDate == null || _selectedRoomTypeId == null) {
      return 0;
    }
    final nights = _checkOutDate!.difference(_checkInDate!).inDays;
    final selectedRoomType = _roomTypes.firstWhere(
      (type) => type['id'] == _selectedRoomTypeId,
      orElse: () => {'price': 0},
    );
    final roomPrice = selectedRoomType['price'] as int? ?? 0;
    return nights * roomPrice;
  }
  
  // Get number of nights
  int get _nightsCount {
    if (_checkInDate == null || _checkOutDate == null) {
      return 0;
    }
    return _checkOutDate!.difference(_checkInDate!).inDays;
  }
  
  // Get amount paid by customer (from input or base total) - returns in kobo
  int get _amountPaid {
    if (!_discountApplied) {
      return _baseTotalAmount;
    }
    final amountText = _amountPaidController.text.trim();
    if (amountText.isEmpty) {
      return _baseTotalAmount;
    }
    // Input is in naira, convert to kobo
    final amountInNaira = double.tryParse(amountText.replaceAll(',', '')) ?? 0.0;
    return PaymentService.nairaToKobo(amountInNaira);
  }
  
  // Calculate discount amount (can be negative for overpayment)
  int get _discountAmount {
    if (!_discountApplied) {
      return 0;
    }
    return _baseTotalAmount - _amountPaid;
  }
  
  // Calculate discount percentage
  double get _discountPercentage {
    if (!_discountApplied || _baseTotalAmount == 0) {
      return 0.0;
    }
    return (_discountAmount / _baseTotalAmount) * 100;
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
      
      // Guest details are optional and stored only on the booking record
      final fullName = InputSanitizer.sanitizeText(_guestNameController.text.trim());
      final phoneRaw = _guestPhoneController.text.trim();
      final phone = phoneRaw.isEmpty ? null : InputSanitizer.sanitizePhone(phoneRaw);
      final displayGuestName = fullName.isEmpty ? 'Guest' : fullName;
      final guestNameForRecord = fullName.isEmpty ? null : fullName;

      // Get room type name for requested_room_type
      final selectedRoomType = _roomTypes.firstWhere(
        (type) => type['id'] == _selectedRoomTypeId,
        orElse: () => {'type': 'Standard'},
      );
      
      // Calculate total amount (nights * room price)
      final totalAmount = _baseTotalAmount;
      
      // CRITICAL: Validate payment method and amount
      // Ensure payment method is selected and valid
      if (_paymentMethod.isEmpty) {
        throw Exception('Please select a payment method');
      }
      
      // Get amount paid (from discount input or base total)
      int paidAmount = _amountPaid;
      
      // Validate discount input if discount is applied
      if (_discountApplied) {
        final amountText = _amountPaidController.text.trim();
        if (amountText.isEmpty) {
          throw Exception('Please enter the amount paid by customer when discount is applied');
        }
        // Input is in naira, convert to kobo
        final amountInNaira = double.tryParse(amountText.replaceAll(',', '')) ?? 0.0;
        if (amountInNaira < 0) {
          throw Exception('Amount paid cannot be negative');
        }
        paidAmount = PaymentService.nairaToKobo(amountInNaira);
      } else {
        // No discount - set paid amount based on payment method
        if (_paymentMethod == 'Cash' || _paymentMethod == 'Transfer' || _paymentMethod == 'POS') {
          paidAmount = totalAmount;
        } else if (_paymentMethod == 'Credit') {
          paidAmount = 0;
        }
      }
      
      // Additional validation: Ensure total amount is positive
      if (totalAmount <= 0) {
        throw Exception('Invalid booking amount. Please check room selection and dates.');
      }
      
      final bookingId = await _dataService.createBooking({
        'room_id': _selectedRoomId, // Can be null - receptionist can assign later
        'requested_room_type': selectedRoomType['type'] as String?,
        'check_in': _checkInDate!.toIso8601String(),
        'check_out': _checkOutDate!.toIso8601String(),
        'status': 'Pending Check-in',
        'total_amount': totalAmount, // Already in kobo from room_types.price
        'paid_amount': paidAmount, // Amount actually paid by customer
        'payment_method': _paymentMethod.toLowerCase(),
        'discount_applied': _discountApplied,
        'discount_amount': _discountAmount,
        'discount_percentage': _discountPercentage,
        'discount_reason': _discountApplied ? (_discountReasonController.text.trim().isEmpty ? null : _discountReasonController.text.trim()) : null,
        'discount_applied_by': _discountApplied ? userId : null,
        'guest_name': guestNameForRecord,
        'guest_phone': phone,
      });

      // If credit payment, create debt linked to booking
      if (_paymentMethod.toLowerCase() == 'credit') {
        final debt = {
          'debtor_name': displayGuestName,
          'debtor_phone': phone ?? '',
          'debtor_type': 'customer',
          'amount': totalAmount, // Total booking amount in kobo
          'owed_to': 'P-ZED Luxury Hotels & Suites',
          'reason': 'Room booking on credit - ${_nightsCount} night(s)',
          'date': DateTime.now().toIso8601String().split('T')[0],
          'status': 'outstanding',
          'sold_by': userId, // Staff who made the booking
          'approved_by': _approvedByController.text.trim().isEmpty 
              ? null 
              : _approvedByController.text.trim(), // Optional approved by
          'booking_id': bookingId, // Link to booking
        };
        
        await _dataService.recordDebt(debt);
      }

      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Booking created successfully!');
        _resetBookingForm();
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

  void _resetBookingForm() {
    _formKey.currentState?.reset();
    _guestNameController.clear();
    _guestPhoneController.clear();
    _amountPaidController.clear();
    _discountReasonController.clear();
    _approvedByController.clear();
    setState(() {
      _checkInDate = null;
      _checkOutDate = null;
      _selectedRoomTypeId = null;
      _selectedRoomId = null;
      _availableRooms = [];
      _paymentMethod = 'Cash';
      _discountApplied = false;
      _isFetchingRooms = false;
    });
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
                  child: Text(
                    '${type['type']} - ₦${PaymentService.koboToNaira(type['price'] as int? ?? 0).toStringAsFixed(2)}',
                  ),
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
                'Guest Information (Optional)',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),

              TextFormField(
                controller: _guestNameController,
                decoration: const InputDecoration(
                  labelText: 'Guest Full Name (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.person),
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _guestPhoneController,
                decoration: const InputDecoration(
                  labelText: 'Phone Number (Optional)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.phone),
                ),
                keyboardType: TextInputType.phone,
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
              
              // Show approved by field for credit payment
              if (_paymentMethod == 'Credit')
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange[50],
                          border: Border.all(color: Colors.orange[300]!),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.warning_amber, color: Colors.orange[700], size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'This booking will be recorded as a debt until payment is received.',
                                style: TextStyle(color: Colors.orange[900], fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                      ),
                      TextFormField(
                        controller: _approvedByController,
                        decoration: const InputDecoration(
                          labelText: 'Approved By (Optional)',
                          hintText: 'Enter name of supervisor/staff who approved',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                      ),
                    ],
                  ),
                ),
              
              const SizedBox(height: 24),
              const Divider(),
              const SizedBox(height: 16),
              
              // Price Summary
              _buildPriceSummary(),
              
              const SizedBox(height: 16),
              
              // Discount Toggle
              Card(
                color: Colors.grey[50],
                child: SwitchListTile(
                  title: const Text(
                    'Apply Discount / Record Amount Paid',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('Enter exact amount paid by customer'),
                  value: _discountApplied,
                  onChanged: (value) {
                    setState(() {
                      _discountApplied = value;
                      if (!value) {
                        _amountPaidController.clear();
                        _discountReasonController.clear();
                      }
                    });
                  },
                  secondary: Icon(
                    _discountApplied ? Icons.discount : Icons.discount_outlined,
                    color: _discountApplied ? Colors.orange : Colors.grey,
                  ),
                ),
              ),
              
              // Discount Input Fields (shown when discount is applied)
              if (_discountApplied) ...[
                const SizedBox(height: 16),
                TextFormField(
                  controller: _amountPaidController,
                  decoration: InputDecoration(
                    labelText: 'Amount Paid by Customer (₦)',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.attach_money),
                    helperText: 'Enter the exact amount the customer paid',
                    suffixText: _baseTotalAmount > 0 
                        ? 'Base: ₦${PaymentService.koboToNaira(_baseTotalAmount).toStringAsFixed(2)}'
                        : null,
                  ),
                  keyboardType: TextInputType.number,
                  onChanged: (value) {
                    setState(() {}); // Trigger rebuild to update discount display
                  },
                  validator: (val) {
                    if (_discountApplied && (val == null || val.trim().isEmpty)) {
                      return 'Please enter amount paid';
                    }
                    if (val != null && val.trim().isNotEmpty) {
                      final amount = int.tryParse(val.replaceAll(',', '')) ?? 0;
                      if (amount < 0) {
                        return 'Amount cannot be negative';
                      }
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                // Discount Calculation Display
                if (_amountPaidController.text.trim().isNotEmpty && _baseTotalAmount > 0)
                  _buildDiscountDisplay(),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _discountReasonController,
                  decoration: const InputDecoration(
                    labelText: 'Discount Reason (Optional)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.note),
                    helperText: 'e.g., Long stay, Loyalty customer, Management approval',
                  ),
                  maxLines: 2,
                ),
              ],

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
  
  Widget _buildPriceSummary() {
    if (_baseTotalAmount == 0) {
      return const SizedBox.shrink();
    }
    
    return Card(
      color: Colors.blue[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Price Summary',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Base Price:'),
                Text(
                  '₦${PaymentService.koboToNaira(_baseTotalAmount).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            if (_checkInDate != null && _checkOutDate != null) ...[
              const SizedBox(height: 4),
              Text(
                '${_checkOutDate!.difference(_checkInDate!).inDays} night(s)',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ],
        ),
      ),
    );
  }
  
  Widget _buildDiscountDisplay() {
    final discountAmount = _discountAmount;
    final discountPercentage = _discountPercentage;
    final amountPaid = _amountPaid;
    final isOverpayment = discountAmount < 0;
    
    return Card(
      color: isOverpayment ? Colors.green[50] : Colors.orange[50],
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  isOverpayment ? 'Overpayment (Credit)' : 'Discount Given',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    color: isOverpayment ? Colors.green[700] : Colors.orange[700],
                  ),
                ),
                Text(
                  isOverpayment 
                      ? '+₦${PaymentService.koboToNaira((-discountAmount).toInt()).toStringAsFixed(2)}'
                      : '-₦${PaymentService.koboToNaira(discountAmount.toInt()).toStringAsFixed(2)}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isOverpayment ? Colors.green[700] : Colors.orange[700],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Discount Percentage:'),
                Text(
                  '${discountPercentage.abs().toStringAsFixed(2)}%',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Amount Paid:'),
                Text(
                  '₦${PaymentService.koboToNaira(amountPaid).toStringAsFixed(2)}',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}