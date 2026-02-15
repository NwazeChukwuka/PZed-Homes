import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Service for handling Paystack payment processing.
/// All amounts are in KOBO (smallest currency unit).
///
/// Keys and API calls are managed via Supabase:
/// - Public key: stored in app_config table (paystack_public_key)
/// - Secret key: PAYSTACK_SECRET_KEY in Edge Function secrets only
/// - Payment link creation: create_paystack_payment Edge Function
/// - Verification: verify_guest_booking_payment Edge Function
class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  bool _isInitialized = false;

  /// Initialize by fetching Paystack config from Supabase app_config table.
  /// Payment is configured when paystack_public_key is set in Supabase.
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('app_config')
          .select('value')
          .eq('key', 'paystack_public_key')
          .maybeSingle()
          .timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw TimeoutException('app_config query timed out'),
          );

      final value = response?['value']?.toString().trim() ?? '';
      if (value.isNotEmpty) {
        _isInitialized = true;
        if (kDebugMode) {
          // Don't log the key
          debugPrint('Paystack: initialized (config from Supabase)');
        }
      } else {
        if (kDebugMode) {
          debugPrint(
            'Paystack: not configured. Set paystack_public_key in app_config table and PAYSTACK_SECRET_KEY in Supabase Edge Function secrets.',
          );
        }
      }
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('Paystack init error: $e\n$stack');
      }
      // app_config table may not exist yet - treat as not configured
      _isInitialized = false;
    }
  }

  /// Whether payment is configured (public key present in Supabase app_config).
  bool get isInitialized => _isInitialized;

  /// Process payment: create link via Edge Function, launch Paystack, await user confirmation.
  /// Verification is done by verify_guest_booking_payment when the caller confirms the booking.
  ///
  /// [context] - BuildContext for showing payment UI
  /// [amountInKobo] - Amount in kobo (smallest currency unit)
  /// [email] - Customer email
  /// [reference] - Unique transaction reference
  /// [metadata] - Additional metadata (e.g. booking_id, guest_name)
  ///
  /// Returns true when user indicates payment is complete (caller must then verify via Edge Function).
  Future<bool> processPayment({
    required BuildContext context,
    required int amountInKobo,
    required String email,
    required String reference,
    Map<String, dynamic>? metadata,
  }) async {
    if (!isInitialized) {
      throw Exception(
        'Payment system is not configured. Set paystack_public_key in Supabase app_config and PAYSTACK_SECRET_KEY in Edge Function secrets.',
      );
    }

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.functions.invoke(
        'create_paystack_payment',
        body: {
          'amount_in_kobo': amountInKobo,
          'email': email,
          'reference': reference,
          if (metadata != null) 'metadata': metadata,
        },
      );

      if (response.status != 200) {
        final err = response.data is Map
            ? (response.data as Map)['error']?.toString()
            : response.data?.toString();
        throw Exception(err ?? 'Failed to create payment link. Check Supabase PAYSTACK_SECRET_KEY.');
      }

      final link = response.data is Map
          ? (response.data as Map)['link']?.toString()
          : null;

      if (link == null || link.isEmpty) {
        throw Exception('Payment system did not return a valid payment URL.');
      }

      final uri = Uri.parse(link);
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!launched) {
        throw Exception('Could not open payment page. Please try again.');
      }

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Complete Payment'),
          content: const Text(
            'You will be redirected to Paystack to complete your payment.\n\n'
            'After completing the payment, please return to this app and click "Payment Completed".',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Payment Completed'),
            ),
          ],
        ),
      );

      return result == true;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Payment error: $e');
      }
      rethrow;
    }
  }

  /// Generate unique payment reference
  String generateReference() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'PZED_${timestamp}_$random';
  }

  /// Convert naira to kobo
  static int nairaToKobo(double naira) {
    return (naira * 100).round();
  }

  /// Convert kobo to naira
  static double koboToNaira(int kobo) {
    return kobo / 100.0;
  }
}
