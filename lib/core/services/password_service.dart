// Consolidated password reset/change service

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../error/error_handler.dart';
import '../config/app_config.dart';

class PasswordService {
  static final PasswordService _instance = PasswordService._internal();
  factory PasswordService() => _instance;
  PasswordService._internal();

  final _supabase = Supabase.instance.client;

  /// Send password reset email to the provided email address
  /// Returns true if successful, throws exception on error
  /// 
  /// The redirectUrl should be your production app URL where the password reset page is hosted.
  /// This must match the Site URL configured in Supabase Dashboard → Authentication → URL Configuration
  Future<bool> sendPasswordResetEmail(String email, {String? customRedirectUrl}) async {
    try {
      String redirectUrl;
      
      if (customRedirectUrl != null) {
        redirectUrl = customRedirectUrl;
      } else {
        // Environment-aware: web uses current origin, mobile uses deep link
        // Must match Redirect URLs in Supabase Dashboard
        final base = kIsWeb ? Uri.base.origin : 'com.pzed.app://reset-password';
        redirectUrl = kIsWeb ? '$base/auth/reset-password' : base;
      }
      
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: redirectUrl,
      );
      return true;
    } catch (e) {
      rethrow;
    }
  }

  /// Update user password (for authenticated users changing their password)
  /// Requires the user to be authenticated
  Future<bool> updatePassword(String newPassword) async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('User must be authenticated to change password');
      }

      await _supabase.auth.updateUser(
        UserAttributes(password: newPassword),
      );
      return true;
    } catch (e) {
      rethrow;
    }
  }

  /// Show password reset dialog
  static Future<void> showPasswordResetDialog(BuildContext context) async {
    final emailController = TextEditingController();
    final passwordService = PasswordService();
    bool isLoading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Reset Password'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Enter your email address and we\'ll send you a password reset link.',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: emailController,
                    enabled: !isLoading,
                    decoration: const InputDecoration(
                      labelText: 'Email Address',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.email),
                    ),
                    keyboardType: TextInputType.emailAddress,
                  ),
                ],
              ),
              actions: <Widget>[
                if (!isLoading)
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      emailController.dispose();
                      Navigator.of(context).pop();
                    },
                  ),
                ElevatedButton(
                  onPressed: isLoading
                      ? null
                      : () async {
                          if (emailController.text.trim().isEmpty) {
                            ErrorHandler.showWarningMessage(
                              context,
                              'Please enter your email address',
                            );
                            return;
                          }

                          if (!emailController.text.contains('@')) {
                            ErrorHandler.showWarningMessage(
                              context,
                              'Please enter a valid email address',
                            );
                            return;
                          }

                          setState(() => isLoading = true);
                          try {
                            await passwordService.sendPasswordResetEmail(
                              emailController.text.trim(),
                            );
                            emailController.dispose();
                            
                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ErrorHandler.showSuccessMessage(
                                context,
                                'Password reset link sent to your email!',
                              );
                            }
                          } catch (e) {
                            setState(() => isLoading = false);
                            if (context.mounted) {
                              ErrorHandler.handleError(
                                context,
                                e,
                                customMessage: 'Failed to send password reset email',
                              );
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Reset Link'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}

