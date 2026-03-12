import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized helper to get staff_profile_id for admin/transaction flows.
/// Prevents using invalid placeholders like 'system' and shows a standard
/// session-expired dialog when no session is available.
class StaffAuthHelper {
  /// Returns the current staff profile id (same as auth uid when using Supabase profiles).
  /// Tries [authService.currentUser?.id] first, then [supabase.auth.currentUser?.id].
  /// Returns null if neither is available (e.g. session expired).
  static String? getStaffProfileId(
    AuthService? authService,
    SupabaseClient? supabase,
  ) {
    final fromAuthService = authService?.currentUser?.id;
    if (fromAuthService != null && fromAuthService.isNotEmpty) {
      return fromAuthService;
    }
    final fromSupabase = supabase?.auth.currentUser?.id;
    if (fromSupabase != null && fromSupabase.isNotEmpty) {
      return fromSupabase;
    }
    return null;
  }

  /// Ensures a valid staff profile id before running a transaction.
  /// If no session is found, shows the standard "Session Expired: Please Re-login"
  /// dialog and returns null. Callers must not proceed with the transaction when null.
  static String? requireStaffProfileId(
    BuildContext context, {
    required AuthService authService,
    SupabaseClient? supabase,
  }) {
    final supabaseClient = supabase ?? Supabase.instance.client;
    final staffId = getStaffProfileId(authService, supabaseClient);
    if (staffId != null) return staffId;
    _showSessionExpiredDialog(context);
    return null;
  }

  static void _showSessionExpiredDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.login, color: Colors.orange, size: 48),
        title: const Text('Session Expired: Please Re-login'),
        content: const Text(
          'Your session may have expired or you are not signed in. Please re-login to continue.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              context.go('/login');
            },
            child: const Text('Go to Login'),
          ),
        ],
      ),
    );
  }
}
