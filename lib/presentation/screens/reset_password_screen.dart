import 'dart:async';
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

const String _kExpiredLinkMessage = 'This reset link has expired or was already used.';

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  bool _isLoading = false;
  bool _sessionReady = false;
  String? _statusMessage;
  bool _initChecked = false;
  bool _isLinkError = false;
  StreamSubscription<AuthState>? _authSubscription;

  @override
  void initState() {
    super.initState();
    _initRecoverySession();
    _authSubscription = Supabase.instance.client.auth.onAuthStateChange.listen(_onAuthStateChange);
  }

  @override
  void dispose() {
    _authSubscription?.cancel();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _onAuthStateChange(AuthState state) {
    if (state.event != AuthChangeEvent.passwordRecovery) return;
    if (state.session != null) return;
    if (!_initChecked || !mounted) return;
    setState(() {
      _isLinkError = true;
      _statusMessage = _kExpiredLinkMessage;
    });
  }

  bool _hasErrorInUrl(Uri uri) {
    final query = uri.queryParameters;
    final fragmentParams = uri.fragment.isNotEmpty ? Uri.splitQueryString(uri.fragment) : <String, String>{};
    final error = query['error'] ?? fragmentParams['error'];
    final errorCode = query['error_code'] ?? fragmentParams['error_code'];
    final description = query['error_description'] ?? fragmentParams['error_description'];
    return error != null || errorCode != null || (description?.isNotEmpty ?? false);
  }

  String? _getErrorMessageFromUrl(Uri uri) {
    if (!_hasErrorInUrl(uri)) return null;
    final query = uri.queryParameters;
    final fragmentParams = uri.fragment.isNotEmpty ? Uri.splitQueryString(uri.fragment) : <String, String>{};
    final errorCode = query['error_code'] ?? fragmentParams['error_code'];
    final description = (query['error_description'] ?? fragmentParams['error_description'] ?? '').toLowerCase();
    if (errorCode == 'otp_expired' || description.contains('expired') || description.contains('invalid')) {
      return _kExpiredLinkMessage;
    }
    return query['error_description'] ?? fragmentParams['error_description'] ?? query['error'] ?? fragmentParams['error'] ?? _kExpiredLinkMessage;
  }

  Future<void> _initRecoverySession() async {
    if (_initChecked) return;
    final supabase = Supabase.instance.client;
    try {
      final uri = Uri.base;

      final urlError = _getErrorMessageFromUrl(uri);
      if (urlError != null) {
        _initChecked = true;
        if (mounted) {
          setState(() {
            _statusMessage = urlError;
            _isLinkError = true;
          });
        }
        return;
      }

      final tokenHash = uri.queryParameters['token_hash'];
      if (tokenHash != null && tokenHash.isNotEmpty) {
        try {
          await supabase.auth.verifyOTP(type: OtpType.recovery, tokenHash: tokenHash);
          _initChecked = true;
          if (mounted) {
            setState(() => _sessionReady = true);
          }
          return;
        } catch (e, stack) {
          if (kDebugMode) debugPrint('DEBUG verifyOTP(recovery): $e\n$stack');
          _initChecked = true;
          if (mounted) {
            setState(() {
              _statusMessage = _kExpiredLinkMessage;
              _isLinkError = true;
            });
          }
          return;
        }
      }

      await Future.delayed(const Duration(milliseconds: 100));
      if (!mounted) return;

      if (supabase.auth.currentUser != null) {
        _initChecked = true;
        if (mounted) {
          setState(() => _sessionReady = true);
        }
        return;
      }

      final code = uri.queryParameters['code'];
      if (code != null && code.isNotEmpty) {
        try {
          await supabase.auth.exchangeCodeForSession(code);
          _initChecked = true;
          if (mounted) {
            setState(() => _sessionReady = true);
          }
          return;
        } catch (e, stack) {
          if (kDebugMode) debugPrint('DEBUG exchangeCodeForSession: $e\n$stack');
          final msg = e.toString().toLowerCase();
          if (msg.contains('verifier') || msg.contains('storage') || msg.contains('code')) {
            _initChecked = true;
            if (mounted) {
              setState(() {
                _statusMessage = _kExpiredLinkMessage;
                _isLinkError = true;
              });
            }
            return;
          }
          rethrow;
        }
      }

      final fragment = uri.fragment;

      if (fragment.isNotEmpty) {
        final normalizedFragment = fragment.startsWith('/') ? fragment.substring(1) : fragment;
        try {
          final params = Uri.splitQueryString(normalizedFragment);
          final refreshToken = params['refresh_token'];
          final accessToken = params['access_token'];
          if ((refreshToken != null && refreshToken.isNotEmpty) ||
              (accessToken != null && accessToken.isNotEmpty)) {
            if (refreshToken != null && refreshToken.isNotEmpty) {
              await supabase.auth.setSession(refreshToken);
            } else {
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
            _initChecked = true;
            if (mounted) {
              setState(() => _sessionReady = true);
            }
            return;
          }
        } catch (e, stack) {
          if (kDebugMode) debugPrint('DEBUG fragment parse recovery: $e\n$stack');
        }
      }

      if (supabase.auth.currentUser != null) {
        _initChecked = true;
        if (mounted) {
          setState(() => _sessionReady = true);
        }
        return;
      }

      _initChecked = true;
      if (mounted) {
        setState(() {
          _statusMessage = _kExpiredLinkMessage;
          _isLinkError = true;
        });
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _initRecoverySession: $e\n$stack');
      _initChecked = true;
      if (mounted) {
        setState(() {
          _statusMessage = _kExpiredLinkMessage;
          _isLinkError = true;
        });
      }
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
      await Supabase.instance.client.auth.signOut();
      if (!mounted) return;
      context.go('/login?passwordUpdated=1');
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
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
                        if (_isLinkError && _statusMessage != null) ...[
                          Icon(Icons.link_off, size: 48, color: Theme.of(context).colorScheme.error),
                          const SizedBox(height: 16),
                          Text(
                            _statusMessage!,
                            style: TextStyle(color: Theme.of(context).colorScheme.error, fontSize: 16),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 24),
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () => context.go('/login?showForgotPassword=1'),
                              icon: const Icon(Icons.refresh),
                              label: const Text('Request New Reset Link'),
                              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                            ),
                          ),
                        ],
                        if (!_isLinkError && _sessionReady) ...[
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
                            child: FilledButton(
                              onPressed: (_isLoading || !_sessionReady) ? null : _updatePassword,
                              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
                              child: _isLoading
                                  ? const SizedBox(
                                      height: 22,
                                      width: 22,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Text('Update Password'),
                            ),
                          ),
                        ],
                        if (!_isLinkError && !_sessionReady)
                          const Padding(
                            padding: EdgeInsets.only(top: 8),
                            child: Center(child: CircularProgressIndicator()),
                          ),
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

