import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});
  
  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _fullNameController = TextEditingController();

  bool _isSigningUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _rememberMe = false;

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isLoading) return; // Prevent double submission

    setState(() => _isLoading = true);
    
    final authService = Provider.of<AuthService>(context, listen: false);

    try {
      String? errorMessage;
      
      if (_isSigningUp) {
        errorMessage = await authService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _fullNameController.text.trim(),
          role: AppRole.guest,
        );
        
        if (mounted && errorMessage == null) {
          ErrorHandler.showSuccessMessage(
            context,
            'Account created successfully! Please check your email to verify your account before logging in.',
            duration: const Duration(seconds: 4),
          );
          
          // Switch to login mode
          setState(() {
            _isSigningUp = false;
            _passwordController.clear();
            _fullNameController.clear();
          });
        }
      } else {
        // Login attempt
        errorMessage = await authService.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          rememberMe: _rememberMe,
        );
        
        if (mounted && errorMessage == null) {
          // Wait a moment for state to update after login completes
          await Future.delayed(const Duration(milliseconds: 200));
          
          // Login successful - user data is already loaded
          final user = authService.currentUser;
          
          if (user == null) {
            await authService.logout();
            ErrorHandler.handleError(
              context,
              Exception('User data not loaded'),
              customMessage: 'Login successful but user data could not be loaded. Please try again.',
            );
            return;
          }
          
          // Check if user has staff access
          final isStaff = user.roles.any((role) => role != AppRole.guest);
          
          if (isStaff) {
            // Staff access granted
            _clearForm();
            
            // Navigate to dashboard
            if (mounted) {
              context.go('/dashboard');
              
              // Show success message after navigation
              Future.microtask(() {
                if (mounted) {
                  ErrorHandler.showSuccessMessage(
                    context,
                    'Welcome to P-ZED Luxury Hotels & Suites Staff Portal!',
                    duration: const Duration(seconds: 2),
                  );
                }
              });
            }
          } else {
            // Guest users denied access
            await authService.logout();
            if (mounted) {
              ErrorHandler.handleError(
                context,
                Exception('Access Denied'),
                customMessage: 'Access Denied. Staff credentials required.',
              );
            }
          }
        }
      }
      
      // Handle error message
      if (mounted && errorMessage != null) {
        ErrorHandler.handleError(
          context,
          Exception(errorMessage),
          customMessage: errorMessage,
        );
      }
      
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'An unexpected error occurred. Please try again.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _clearForm() {
    _emailController.clear();
    _passwordController.clear();
    _fullNameController.clear();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _fullNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Staff Portal Login'),
        backgroundColor: Colors.green[800],
        elevation: 0,
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.hotel,
                  size: 80,
                  color: Colors.green[800],
                ),
                const SizedBox(height: 16),
                const Text(
                  'P-ZED Luxury Hotels & Suites',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Staff Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 40),

                if (_isSigningUp) ...[
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    textInputAction: TextInputAction.next,
                    validator: (val) {
                      if (val == null || val.trim().isEmpty) {
                        return 'Enter your full name';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                ],

                TextFormField(
                  controller: _emailController,
                  decoration: const InputDecoration(
                    labelText: 'Email',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.email),
                  ),
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.next,
                  validator: (val) {
                    if (val == null || val.trim().isEmpty) {
                      return 'Enter an email';
                    }
                    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(val)) {
                      return 'Enter a valid email';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.lock),
                    suffixIcon: IconButton(
                      icon: Icon(
                        _obscurePassword ? Icons.visibility : Icons.visibility_off,
                      ),
                      onPressed: () {
                        setState(() => _obscurePassword = !_obscurePassword);
                      },
                    ),
                  ),
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  validator: (val) {
                    if (val == null || val.isEmpty) {
                      return 'Enter a password';
                    }
                    if (val.length < 6) {
                      return 'Password must be at least 6 characters';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                _isLoading
                    ? const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 16),
                            Text('Please wait...'),
                          ],
                        ),
                      )
                    : ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[800],
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        child: Text(_isSigningUp ? 'Sign Up' : 'Login'),
                      ),

                const SizedBox(height: 16),
                
                TextButton(
                  onPressed: _isLoading
                      ? null
                      : () {
                          setState(() {
                            _isSigningUp = !_isSigningUp;
                            // Clear form when switching modes
                            _formKey.currentState?.reset();
                          });
                        },
                  child: Text(
                    _isSigningUp
                        ? 'Already have an account? Login'
                        : "Don't have an account? Sign up",
                    style: TextStyle(
                      color: _isLoading ? Colors.grey : Colors.green[800],
                    ),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                Text(
                  'Staff access only',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}