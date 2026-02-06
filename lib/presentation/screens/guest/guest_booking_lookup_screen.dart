import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/theme/responsive_helpers.dart';
import 'package:pzed_homes/core/utils/input_sanitizer.dart';
import 'package:pzed_homes/core/services/payment_service.dart';

class GuestBookingLookupScreen extends StatefulWidget {
  const GuestBookingLookupScreen({super.key});

  @override
  State<GuestBookingLookupScreen> createState() => _GuestBookingLookupScreenState();
}

class _GuestBookingLookupScreenState extends State<GuestBookingLookupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _referenceController = TextEditingController();
  bool _isLoading = false;
  Map<String, dynamic>? _result;

  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _referenceController.dispose();
    super.dispose();
  }

  Future<void> _lookupBooking() async {
    if (!_formKey.currentState!.validate()) return;
    if (_supabase == null) {
      ErrorHandler.handleError(
        context,
        Exception('Supabase is not configured. Please try again later.'),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _result = null;
    });

    try {
      final email = InputSanitizer.sanitizeEmail(_emailController.text.trim());
      final reference = _referenceController.text.trim();
      final response = await _supabase!.rpc(
        'get_guest_booking_status',
        params: {
          'p_guest_email': email,
          'p_payment_reference': reference,
        },
      );

      final rows = List<Map<String, dynamic>>.from(response as List);
      if (rows.isEmpty) {
        if (mounted) {
          ErrorHandler.showWarningMessage(
            context,
            'No booking found for that email and reference.',
          );
        }
      } else {
        setState(() {
          _result = rows.first;
        });
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG lookup booking: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to lookup booking. Please verify your details.',
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<Uint8List> _buildBookingReceiptPdf({
    required String bookingId,
    required String guestName,
    required String roomType,
    required DateTime checkIn,
    required DateTime checkOut,
    required int nights,
    required int totalAmountKobo,
    required int paidAmountKobo,
    required String paymentMethod,
    required String paymentReference,
  }) async {
    final totalNaira = PaymentService.koboToNaira(totalAmountKobo);
    final paidNaira = PaymentService.koboToNaira(paidAmountKobo);
    final dateFormatter = DateFormat('MMM dd, yyyy');
    final doc = pw.Document();

    doc.addPage(
      pw.Page(
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text('P-ZED Homes Booking Receipt', style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 12),
              pw.Text('Booking ID: $bookingId'),
              pw.Text('Guest: $guestName'),
              pw.Text('Room Type: $roomType'),
              pw.Text('Check-in: ${dateFormatter.format(checkIn)}'),
              pw.Text('Check-out: ${dateFormatter.format(checkOut)}'),
              pw.Text('Nights: $nights'),
              pw.Text('Payment Method: $paymentMethod'),
              pw.Text('Payment Ref: $paymentReference'),
              pw.SizedBox(height: 8),
              pw.Text('Total: ₦${NumberFormat('#,##0.00').format(totalNaira)}'),
              pw.Text('Paid: ₦${NumberFormat('#,##0.00').format(paidNaira)}'),
              pw.SizedBox(height: 12),
              pw.Text('Generated: ${DateFormat('MMM dd, yyyy HH:mm').format(DateTime.now())}', style: const pw.TextStyle(fontSize: 10)),
            ],
          );
        },
      ),
    );

    return doc.save();
  }

  Future<void> _shareReceipt() async {
    if (_result == null) return;
    try {
      final checkIn = DateTime.parse(_result!['check_in_date'].toString());
      final checkOut = DateTime.parse(_result!['check_out_date'].toString());
      final nights = checkOut.difference(checkIn).inDays;
      final bytes = await _buildBookingReceiptPdf(
        bookingId: _result!['booking_id']?.toString() ?? '',
        guestName: _result!['guest_name']?.toString() ?? 'Guest',
        roomType: _result!['requested_room_type']?.toString() ?? 'Room',
        checkIn: checkIn,
        checkOut: checkOut,
        nights: nights,
        totalAmountKobo: (_result!['total_amount'] as num?)?.toInt() ?? 0,
        paidAmountKobo: (_result!['paid_amount'] as num?)?.toInt() ?? 0,
        paymentMethod: _result!['payment_method']?.toString() ?? 'online',
        paymentReference: _result!['payment_reference']?.toString() ?? '',
      );
      await Printing.sharePdf(
        bytes: bytes,
        filename: 'booking_receipt_${_result!['booking_id']}.pdf',
      );
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG share receipt: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to share receipt. Please try again.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _printReceipt() async {
    if (_result == null) return;
    try {
      final checkIn = DateTime.parse(_result!['check_in_date'].toString());
      final checkOut = DateTime.parse(_result!['check_out_date'].toString());
      final nights = checkOut.difference(checkIn).inDays;
      final bytes = await _buildBookingReceiptPdf(
        bookingId: _result!['booking_id']?.toString() ?? '',
        guestName: _result!['guest_name']?.toString() ?? 'Guest',
        roomType: _result!['requested_room_type']?.toString() ?? 'Room',
        checkIn: checkIn,
        checkOut: checkOut,
        nights: nights,
        totalAmountKobo: (_result!['total_amount'] as num?)?.toInt() ?? 0,
        paidAmountKobo: (_result!['paid_amount'] as num?)?.toInt() ?? 0,
        paymentMethod: _result!['payment_method']?.toString() ?? 'online',
        paymentReference: _result!['payment_reference']?.toString() ?? '',
      );
      await Printing.layoutPdf(onLayout: (format) async => bytes);
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG print receipt: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to print receipt. Please try again.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final formatter = DateFormat('MMM dd, yyyy');
    return Scaffold(
      appBar: AppBar(
        title: const Text('Booking Lookup'),
      ),
      body: SingleChildScrollView(
        padding: ResponsiveHelper.getResponsivePadding(
          context,
          mobile: const EdgeInsets.all(16),
          tablet: const EdgeInsets.all(24),
          desktop: const EdgeInsets.all(32),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Check your booking status',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _emailController,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Email is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _referenceController,
                        decoration: const InputDecoration(
                          labelText: 'Payment Reference',
                          border: OutlineInputBorder(),
                        ),
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Payment reference is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _isLoading ? null : _lookupBooking,
                        child: _isLoading
                            ? const SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('Check Status'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_result != null) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Booking Details',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      _buildRow('Status', _result!['status']?.toString() ?? 'Unknown'),
                      _buildRow('Room Type', _result!['requested_room_type']?.toString() ?? 'Unknown'),
                      _buildRow(
                        'Check-in',
                        _formatDate(formatter, _result!['check_in_date']),
                      ),
                      _buildRow(
                        'Check-out',
                        _formatDate(formatter, _result!['check_out_date']),
                      ),
                      _buildRow(
                        'Room Assigned',
                        (_result!['room_number'] != null && _result!['room_number'].toString().isNotEmpty)
                            ? _result!['room_number'].toString()
                            : 'Not yet assigned',
                      ),
                      _buildRow(
                        'Payment Ref',
                        _result!['payment_reference']?.toString() ?? 'N/A',
                      ),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: _result!['payment_reference'] == null
                              ? null
                              : () async {
                                  final ref = _result!['payment_reference']?.toString() ?? '';
                                  await Clipboard.setData(ClipboardData(text: ref));
                                  if (mounted) {
                                    ErrorHandler.showSuccessMessage(context, 'Payment reference copied');
                                  }
                                },
                          child: const Text('Copy reference'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _printReceipt,
                      child: const Text('Print/PDF'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _shareReceipt,
                      child: const Text('Share Receipt'),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }

  String _formatDate(DateFormat formatter, dynamic value) {
    if (value == null) return 'Unknown';
    final parsed = DateTime.tryParse(value.toString());
    if (parsed == null) return value.toString();
    return formatter.format(parsed);
  }
}
