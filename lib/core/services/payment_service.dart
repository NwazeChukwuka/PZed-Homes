import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';

/// Service for handling Paystack payment processing
/// All amounts are handled in KOBO (smallest currency unit)
/// 
/// Note: This implementation uses Paystack's payment link API
/// For production, consider using Paystack's Flutter SDK or web-based checkout
class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  String? _publicKey;
  String? _secretKey;
  bool _isInitialized = false;

  /// Initialize Paystack with public key from environment
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    // Get Paystack keys from environment
    const publicKey = String.fromEnvironment('PAYSTACK_PUBLIC_KEY', defaultValue: '');
    const secretKey = String.fromEnvironment('PAYSTACK_SECRET_KEY', defaultValue: '');
    
    if (publicKey.isEmpty) {
      if (kDebugMode) {
        print('⚠️ PAYSTACK_PUBLIC_KEY not set. Payment will not work.');
      }
      return;
    }

    _publicKey = publicKey;
    _secretKey = secretKey;
    _isInitialized = true;
  }

  /// Check if Paystack is initialized
  bool get isInitialized => _isInitialized && _publicKey != null && _publicKey!.isNotEmpty;

  /// Process payment using Paystack Payment Link API
  /// 
  /// [context] - BuildContext for showing payment UI
  /// [amountInKobo] - Amount in kobo (smallest currency unit)
  /// [email] - Customer email
  /// [reference] - Unique transaction reference
  /// [metadata] - Additional metadata for the transaction
  /// 
  /// Returns true if payment is successful, false otherwise
  Future<bool> processPayment({
    required BuildContext context,
    required int amountInKobo,
    required String email,
    required String reference,
    Map<String, dynamic>? metadata,
  }) async {
    if (!isInitialized) {
      throw Exception('Paystack is not initialized. Please set PAYSTACK_PUBLIC_KEY environment variable.');
    }

    if (_secretKey == null || _secretKey!.isEmpty) {
      throw Exception('PAYSTACK_SECRET_KEY is required for payment processing. Please set it in environment variables.');
    }

    try {
      // Convert amount from kobo to naira for Paystack API (Paystack API expects amount in kobo)
      // Note: Paystack Payment Link API expects amount in the smallest currency unit (kobo for NGN)
      
      // Create payment link via Paystack API
      final response = await http.post(
        Uri.parse('https://api.paystack.co/paymentrequest'),
        headers: {
          'Authorization': 'Bearer $_secretKey',
          'Content-Type': 'application/json',
        },
        body: jsonEncode({
          'amount': amountInKobo, // Amount in kobo
          'email': email,
          'reference': reference,
          'currency': 'NGN',
          'metadata': {
            'booking_reference': reference,
            ...?metadata,
          },
        }),
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode == 201) {
        final responseData = jsonDecode(response.body);
        final paymentLink = responseData['data']['link'] as String?;
        
        if (paymentLink != null) {
          // Launch payment link in browser
          final uri = Uri.parse(paymentLink);
          final launched = await launchUrl(
            uri,
            mode: LaunchMode.externalApplication,
          );

          if (launched) {
            // Show dialog to user to confirm payment completion
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

            if (result == true) {
              // Verify payment status
              return await _verifyPayment(reference);
            }
          }
        }
      }

      if (kDebugMode) {
        debugPrint('DEBUG: Payment API error - status: ${response.statusCode}, body: ${response.body}');
      }
      throw Exception('Payment request failed. Please try again.');
    } catch (e) {
      if (kDebugMode) {
        print('Payment error: $e');
      }
      rethrow;
    }
  }

  /// Verify payment status with Paystack
  Future<bool> _verifyPayment(String reference) async {
    if (_secretKey == null || _secretKey!.isEmpty) {
      return false;
    }

    try {
      final response = await http.get(
        Uri.parse('https://api.paystack.co/transaction/verify/$reference'),
        headers: {
          'Authorization': 'Bearer $_secretKey',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final status = responseData['data']['status'] as String?;
        return status == 'success';
      }

      return false;
    } catch (e) {
      if (kDebugMode) {
        print('Payment verification error: $e');
      }
      return false;
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

