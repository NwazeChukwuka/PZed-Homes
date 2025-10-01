// Location: lib/core/error/error_handler.dart

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Centralized error handling for the application
class ErrorHandler {
  static void handleError(
    BuildContext context,
    dynamic error, {
    String? customMessage,
    VoidCallback? onRetry,
  }) {
    String message;
    String title = 'Error';
    IconData icon = Icons.error_outline;
    Color color = Colors.red;

    if (error is AuthException) {
      message = _handleAuthError(error);
      title = 'Authentication Error';
      icon = Icons.lock_outline;
    } else if (error is PostgrestException) {
      message = _handleDatabaseError(error);
      title = 'Database Error';
      icon = Icons.storage_outlined;
    } else if (error is NetworkException) {
      message = _handleNetworkError(error);
      title = 'Network Error';
      icon = Icons.wifi_off;
      color = Colors.orange;
    } else if (error is Exception) {
      message = _handleGenericError(error);
    } else {
      message = customMessage ?? 'An unexpected error occurred';
    }

    _showErrorDialog(
      context,
      title: title,
      message: message,
      icon: icon,
      color: color,
      onRetry: onRetry,
    );
  }

  static String _handleAuthError(AuthException error) {
    switch (error.message) {
      case 'Invalid login credentials':
        return 'Invalid email or password. Please check your credentials and try again.';
      case 'Email not confirmed':
        return 'Please check your email and click the confirmation link before signing in.';
      case 'User already registered':
        return 'An account with this email already exists. Please try signing in instead.';
      case 'Password should be at least 6 characters':
        return 'Password must be at least 6 characters long.';
      case 'Signup is disabled':
        return 'New account registration is currently disabled. Please contact support.';
      default:
        return 'Authentication failed: ${error.message}';
    }
  }

  static String _handleDatabaseError(PostgrestException error) {
    switch (error.code) {
      case '23505': // Unique constraint violation
        return 'This record already exists. Please check your input and try again.';
      case '23503': // Foreign key constraint violation
        return 'Cannot delete this record as it is referenced by other data.';
      case '23502': // Not null constraint violation
        return 'Required fields are missing. Please fill in all required information.';
      case '42501': // Insufficient privilege
        return 'You do not have permission to perform this action.';
      default:
        return 'Database error: ${error.message}';
    }
  }

  static String _handleNetworkError(NetworkException error) {
    return 'Network connection failed. Please check your internet connection and try again.';
  }

  static String _handleGenericError(Exception error) {
    return 'An unexpected error occurred: ${error.toString()}';
  }

  static void _showErrorDialog(
    BuildContext context, {
    required String title,
    required String message,
    required IconData icon,
    required Color color,
    VoidCallback? onRetry,
  }) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        icon: Icon(icon, color: color, size: 48),
        title: Text(title),
        content: Text(message),
        actions: [
          if (onRetry != null)
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onRetry();
              },
              child: const Text('Retry'),
            ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  static void showSuccessMessage(
    BuildContext context,
    String message, {
    String title = 'Success',
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.green,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static void showWarningMessage(
    BuildContext context,
    String message, {
    String title = 'Warning',
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.warning, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  static void showInfoMessage(
    BuildContext context,
    String message, {
    String title = 'Info',
    Duration duration = const Duration(seconds: 3),
  }) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.info, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.blue,
        duration: duration,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

/// Custom exception classes
class NetworkException implements Exception {
  final String message;
  NetworkException(this.message);
  
  @override
  String toString() => 'NetworkException: $message';
}

class ValidationException implements Exception {
  final String message;
  final String? field;
  
  ValidationException(this.message, [this.field]);
  
  @override
  String toString() => 'ValidationException: $message';
}

class BusinessLogicException implements Exception {
  final String message;
  final String? code;
  
  BusinessLogicException(this.message, [this.code]);
  
  @override
  String toString() => 'BusinessLogicException: $message';
}

/// Error boundary widget for catching and handling errors
class ErrorBoundary extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext context, Object error, StackTrace? stackTrace)? errorBuilder;

  const ErrorBoundary({
    super.key,
    required this.child,
    this.errorBuilder,
  });

  @override
  State<ErrorBoundary> createState() => _ErrorBoundaryState();
}

class _ErrorBoundaryState extends State<ErrorBoundary> {
  Object? _error;
  StackTrace? _stackTrace;

  @override
  void initState() {
    super.initState();
    // Store the original error handler
    final originalErrorHandler = FlutterError.onError;
    
    FlutterError.onError = (FlutterErrorDetails details) {
      // Call original error handler first
      originalErrorHandler?.call(details);
      
      // Then handle our custom error boundary
      if (mounted) {
        setState(() {
          _error = details.exception;
          _stackTrace = details.stack;
        });
      }
    };
  }

  @override
  void dispose() {
    // Restore original error handler on dispose
    FlutterError.onError = FlutterError.onError;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error!, _stackTrace);
      }
      
      return MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            title: const Text('Error'),
            backgroundColor: Colors.red,
          ),
          body: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 64,
                  color: Colors.red,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Something went wrong',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Please try again or contact support if the problem persists.',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () {
                    if (mounted) {
                      setState(() {
                        _error = null;
                        _stackTrace = null;
                      });
                    }
                  },
                  child: const Text('Try Again'),
                ),
                if (kDebugMode) ...[
                  const SizedBox(height: 16),
                  const Text('Debug Info:', style: TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 8),
                  Text(
                    _error.toString(),
                    style: const TextStyle(fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return widget.child;
  }
}
