// Location: lib/presentation/screens/login_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
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
  bool _isNavigating = false; // Add navigation guard

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_isNavigating) return; // Prevent concurrent navigation

    setState(() => _isLoading = true);
    final authService = Provider.of<MockAuthService>(context, listen: false);
    
    print('DEBUG: Login attempt started for email: ${_emailController.text}');
    print('DEBUG: Is signing up: $_isSigningUp');

    try {
      String? errorMessage;
      if (_isSigningUp) {
        // Sign up always creates guest users first
        errorMessage = await authService.signUp(
          email: _emailController.text,
          password: _passwordController.text,
          fullName: _fullNameController.text,
          role: AppRole.guest,
        );
      } else {
        // Login attempt
        errorMessage = await authService.login(
          email: _emailController.text,
          password: _passwordController.text,
        );
      }

      print('DEBUG: Auth service response - errorMessage: $errorMessage');
      
      if (mounted) {
        if (errorMessage == null) {
          final user = authService.currentUser;
          final isStaff = user != null && user.roles.any((role) => role != AppRole.guest);
          
          print('DEBUG: User logged in: ${user?.name}, roles: ${user?.roles.map((r) => r.name)}');
          print('DEBUG: Is staff: $isStaff');

          if (isStaff) {
            // Staff access granted - clear form and navigate to dashboard
            _clearForm();
            
            // Set navigation guard
            setState(() => _isNavigating = true);
            
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Login successful! Welcome to P-ZED Homes Staff Portal.'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 1),
              ),
            );
            
            // Navigate to dashboard using GoRouter - this will replace the current route
            Future.delayed(const Duration(milliseconds: 800), () {
              if (mounted && _isNavigating) {
                try {
                  // Use GoRouter's go method - this replaces the current route stack
                  context.go('/dashboard');
                  print('DEBUG: Successfully navigated to dashboard');
                } catch (e) {
                  print('DEBUG: Navigation error: $e');
                  // If navigation fails, try to go to root and then dashboard
                  try {
                    context.go('/');
                    Future.delayed(const Duration(milliseconds: 100), () {
                      if (mounted) {
                        context.go('/dashboard');
                      }
                    });
                  } catch (e2) {
                    print('DEBUG: Fallback navigation error: $e2');
                  }
                } finally {
                  if (mounted) {
                    setState(() => _isNavigating = false);
                  }
                }
              }
            });
          } else {
            // Guest users are denied access
            await authService.logout();
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('Access Denied. Staff credentials required.'),
              backgroundColor: Colors.red,
            ));
          }
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(errorMessage), backgroundColor: Colors.red),
          );
        }
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('An unexpected error occurred: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _clearForm() {
    _emailController.clear();
    _passwordController.clear();
    _fullNameController.clear();
    setState(() {
      _isSigningUp = false;
      _isLoading = false;
    });
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
                const Text(
                  'P-ZED Homes Staff Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                
                // Test Users Section
                Card(
                  color: Colors.blue.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Test Users (Click to auto-fill)',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Password for all: Password123',
                          style: TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          children: MockAuthService.getAvailableUsers().map((user) {
                            return ActionChip(
                              label: Text('${user['name']} (${user['roles'].join(', ')})'),
                              onPressed: () {
                                _emailController.text = user['email'];
                                _passwordController.text = 'Password123';
                              },
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                if (_isSigningUp) ...[
                  TextFormField(
                    controller: _fullNameController,
                    decoration: const InputDecoration(
                      labelText: 'Full Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.person),
                    ),
                    validator: (val) => val!.isEmpty ? 'Enter your full name' : null,
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
                  validator: (val) {
                    if (val!.isEmpty) return 'Enter an email';
                    if (!val.contains('@')) return 'Enter a valid email';
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _passwordController,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Password',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.lock),
                  ),
                  validator: (val) {
                    if (val!.isEmpty) return 'Enter a password';
                    if (val.length < 6) return 'Password must be 6+ characters';
                    return null;
                  },
                ),
                const SizedBox(height: 32),

                _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : ElevatedButton(
                        onPressed: _submit,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[800],
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                        child: Text(_isSigningUp ? 'Sign Up' : 'Login'),
                      ),

                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => setState(() => _isSigningUp = !_isSigningUp),
                  child: Text(
                    _isSigningUp ? 'Have an account? Login' : "Don't have an account? Sign up",
                    style: TextStyle(color: Colors.green[800]),
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
