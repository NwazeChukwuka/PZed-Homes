// Consolidated password reset/change service

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import '../error/error_handler.dart';

class PasswordService {
  static final PasswordService _instance = PasswordService._internal();
  factory PasswordService() => _instance;
  PasswordService._internal();

  final _supabase = Supabase.instance.client;

  /// Send password reset email to the provided email address
  /// Returns true if successful, throws exception on error
  Future<bool> sendPasswordResetEmail(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(
        email,
        redirectTo: 'pzed-homes://reset-password', // Deep link for mobile
      );
      return true;
    } catch (e) {
      throw Exception('Failed to send password reset email: $e');
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
      throw Exception('Failed to update password: $e');
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
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Send Reset Link'),
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
                ),
              ],
            );
          },
        );
      },
    );
  }
}

