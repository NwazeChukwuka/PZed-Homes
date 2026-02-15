import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/auth_service.dart';

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
  bool _initChecked = false;

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

  /// Initialize recovery session. Supabase may auto-establish session from URL (PKCE).
  /// Fallback: manual fragment parsing for implicit flow.
  Future<void> _initRecoverySession() async {
    if (_initChecked) return;
    final supabase = Supabase.instance.client;
    try {
      // Give Supabase a moment to auto-recover from URL (PKCE flow)
      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      if (supabase.auth.currentUser != null) {
        _initChecked = true;
        if (mounted) setState(() => _sessionReady = true);
        return;
      }

      final uri = Uri.base;
      final fragment = uri.fragment;

      // Implicit flow: parse fragment for refresh_token
      if (fragment.isNotEmpty) {
        final params = Uri.splitQueryString(fragment);
        final refreshToken = params['refresh_token'];
        if (refreshToken != null && refreshToken.isNotEmpty) {
          await supabase.auth.setSession(refreshToken);
          _initChecked = true;
          if (mounted) setState(() => _sessionReady = true);
          return;
        }
      }

      // Still no session - check again (auth listener may have established it)
      if (supabase.auth.currentUser != null) {
        _initChecked = true;
        if (mounted) setState(() => _sessionReady = true);
        return;
      }

      _initChecked = true;
      if (mounted) setState(() => _statusMessage = 'Invalid or expired reset link.');
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _initRecoverySession: $e\n$stack');
      _initChecked = true;
      if (mounted) setState(() => _statusMessage = 'Invalid or expired reset link.');
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
      final authService = context.read<AuthService>();
      final errorMsg = await authService.updateUserPassword(password);
      if (!mounted) return;
      if (errorMsg != null) {
        ErrorHandler.showWarningMessage(context, errorMsg);
        setState(() => _isLoading = false);
        return;
      }
      authService.clearRecoveryState();
      await authService.logout();
      if (!mounted) return;
      ErrorHandler.showSuccessMessage(
        context,
        'Password updated successfully. Please log in.',
      );
      context.go('/login');
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _updatePassword: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update password. Please try again.',
          stackTrace: stackTrace,
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _recheckSessionFromRecovery() {
    if (_sessionReady) return;
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null && mounted) {
      setState(() {
        _sessionReady = true;
        _statusMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, _) {
        if (authService.isRecovering && !_sessionReady && _initChecked) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _recheckSessionFromRecovery());
        }
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
      },
    );
  }
}
