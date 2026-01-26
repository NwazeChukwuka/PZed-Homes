import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/core/error/error_handler.dart';

class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _sessionReady = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _initRecoverySession();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _initRecoverySession() async {
    final supabase = Supabase.instance.client;
    try {
      final uri = Uri.base;
      final fragment = uri.fragment;
      if (fragment.isEmpty) {
        if (supabase.auth.currentUser != null) {
          setState(() => _sessionReady = true);
        } else {
          setState(() => _statusMessage = 'Invalid or expired reset link.');
        }
        return;
      }

      final params = Uri.splitQueryString(fragment);
      final refreshToken = params['refresh_token'];
      if (refreshToken != null && refreshToken.isNotEmpty) {
        await supabase.auth.setSession(refreshToken);
        setState(() => _sessionReady = true);
      } else if (supabase.auth.currentUser != null) {
        setState(() => _sessionReady = true);
      } else {
        setState(() => _statusMessage = 'Invalid or expired reset link.');
      }
    } catch (e) {
      setState(() => _statusMessage = 'Invalid or expired reset link.');
    }
  }

  Future<void> _updatePassword() async {
    final password = _passwordController.text.trim();
    final confirm = _confirmController.text.trim();
    if (password.length < 6) {
      ErrorHandler.showWarningMessage(context, 'Password must be at least 6 characters.');
      return;
    }
    if (password != confirm) {
      ErrorHandler.showWarningMessage(context, 'Passwords do not match.');
      return;
    }

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: password),
      );
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Password updated successfully. Please log in.',
        );
        context.go('/login');
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update password. Please try again.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reset Password'),
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_statusMessage != null)
                      Text(
                        _statusMessage!,
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                    if (_statusMessage == null) ...[
                      TextField(
                        controller: _passwordController,
                        obscureText: true,
                        enabled: !_isLoading && _sessionReady,
                        decoration: const InputDecoration(
                          labelText: 'New Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _confirmController,
                        obscureText: true,
                        enabled: !_isLoading && _sessionReady,
                        decoration: const InputDecoration(
                          labelText: 'Confirm Password',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: _isLoading || !_sessionReady ? null : _updatePassword,
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Text('Update Password'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
