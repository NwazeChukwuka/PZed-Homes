import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  bool _isInitialized = false;
  static const String _transferAccountsKey = 'transfer_bank_accounts';
  static const String _transferDisplayCountKey = 'transfer_display_count';
  static const String _transferSupportPhoneKey = 'transfer_support_phone';

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
          debugPrint('Paystack: initialized');
        }
      } else {
        if (kDebugMode) {
          debugPrint('Paystack: not configured. Check app_config and Edge Function secrets.');
        }
      }
    } catch (e, stack) {
      if (kDebugMode) {
        debugPrint('Paystack init error: $e\n$stack');
      }
      _isInitialized = false;
    }
  }

  bool get isInitialized => _isInitialized;

  Future<bool> processPayment({
    required BuildContext context,
    required int amountInKobo,
    required String email,
    required String reference,
    Map<String, dynamic>? metadata,
  }) async {
    if (!isInitialized) {
      throw Exception('Payment system is not configured. Please contact support.');
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
        if (kDebugMode) {
          final err = response.data is Map
              ? (response.data as Map)['error']?.toString()
              : response.data?.toString();
          debugPrint('Paystack create link error: $err');
        }
        throw Exception('Failed to create payment link. Please try again.');
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

      if (!context.mounted) return false;

      final result = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          title: const Text('Complete Payment'),
          content: const Text(
            'You will be redirected to a payment page to complete your payment.\n\n'
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

  String generateReference() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = (timestamp % 10000).toString().padLeft(4, '0');
    return 'PZED_${timestamp}_$random';
  }

  static int nairaToKobo(double naira) {
    return (naira * 100).round();
  }

  static double koboToNaira(int kobo) {
    return kobo / 100.0;
  }

  Future<Map<String, dynamic>> getTransferConfig() async {
    List<Map<String, dynamic>> rows = [];
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('app_config')
          .select('key, value')
          .inFilter('key', [
            _transferAccountsKey,
            _transferDisplayCountKey,
            _transferSupportPhoneKey,
            'paystack_public_key',
          ]);
      rows = List<Map<String, dynamic>>.from(response as List);
    } catch (_) {
      rows = [];
    }

    String valueFor(String key) {
      final row = rows.cast<Map<String, dynamic>?>().firstWhere(
            (r) => (r?['key']?.toString() ?? '') == key,
            orElse: () => null,
          );
      return row?['value']?.toString() ?? '';
    }

    final rawAccounts = valueFor(_transferAccountsKey);
    final List<Map<String, dynamic>> accounts = [];
    if (rawAccounts.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawAccounts);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              accounts.add({
                'bank_name': item['bank_name']?.toString() ?? '',
                'account_name': item['account_name']?.toString() ?? '',
                'account_number': item['account_number']?.toString() ?? '',
                'priority': int.tryParse(item['priority']?.toString() ?? '') ?? 0,
                'active': item['active'] == true,
              });
            }
          }
        }
      } catch (_) {}
    }
    accounts.sort((a, b) => (a['priority'] as int).compareTo(b['priority'] as int));

    final displayCount = int.tryParse(valueFor(_transferDisplayCountKey)) ?? 1;
    final supportPhone = valueFor(_transferSupportPhoneKey).isEmpty
        ? '+2348157505978'
        : valueFor(_transferSupportPhoneKey);
    final paystackConfigured = valueFor('paystack_public_key').trim().isNotEmpty;

    return {
      'accounts': accounts,
      'display_count': displayCount.clamp(1, 10),
      'support_phone': supportPhone,
      'paystack_configured': paystackConfigured,
    };
  }

  Future<void> saveTransferConfig({
    required List<Map<String, dynamic>> accounts,
    required int displayCount,
    String? supportPhone,
  }) async {
    final normalized = accounts
        .take(10)
        .map((a) => {
              'bank_name': a['bank_name']?.toString().trim() ?? '',
              'account_name': a['account_name']?.toString().trim() ?? '',
              'account_number': a['account_number']?.toString().trim() ?? '',
              'priority': int.tryParse(a['priority']?.toString() ?? '') ?? 0,
              'active': a['active'] == true,
            })
        .toList();

    await _saveConfigValue(_transferAccountsKey, jsonEncode(normalized));
    await _saveConfigValue(
      _transferDisplayCountKey,
      displayCount.clamp(1, 10).toString(),
    );
    if (supportPhone != null && supportPhone.trim().isNotEmpty) {
      await _saveConfigValue(_transferSupportPhoneKey, supportPhone.trim());
    }
  }

  Future<void> _saveConfigValue(String key, String value) async {
    final supabase = Supabase.instance.client;
    final updated = await supabase
        .from('app_config')
        .update({
          'value': value,
          'updated_at': DateTime.now().toIso8601String(),
        })
        .eq('key', key)
        .select('key')
        .limit(1);

    if ((updated as List).isEmpty) {
      try {
        await supabase.from('app_config').insert({'key': key, 'value': value});
      } catch (_) {
        await supabase
            .from('app_config')
            .update({
              'value': value,
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('key', key);
      }
    }
  }
}


