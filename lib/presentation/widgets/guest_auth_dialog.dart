import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/password_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart'; // This imports the correct AppRole
import 'package:pzed_homes/presentation/screens/main_screen.dart';

class GuestAuthDialog extends StatefulWidget {
  const GuestAuthDialog({super.key});
  @override
  State<GuestAuthDialog> createState() => _GuestAuthDialogState();
}

class _GuestAuthDialogState extends State<GuestAuthDialog> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TabBar(
              controller: _tabController,
              tabs: const [Tab(text: 'Login'), Tab(text: 'Sign Up')],
            ),
            SizedBox(
              height: 350,
              child: TabBarView(
                controller: _tabController,
                children: const [
                  AuthForm(isSignUp: false),
                  AuthForm(isSignUp: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AuthForm extends StatefulWidget {
  final bool isSignUp;
  const AuthForm({super.key, required this.isSignUp});
  @override
  State<AuthForm> createState() => _AuthFormState();
}

class _AuthFormState extends State<AuthForm> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;

  Future<void> _showForgotPasswordDialog() async {
    // Use consolidated password service
    await PasswordService.showPasswordResetDialog(context);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    
    setState(() => _isLoading = true);
    final authService = Provider.of<AuthService>(context, listen: false);
    String? error;

    try {
      if (widget.isSignUp) {
        error = await authService.signUp(
          email: _emailController.text.trim(),
          password: _passwordController.text,
          fullName: _nameController.text.trim(),
          role: AppRole.guest, // FIXED: Added the required role parameter
        );
      } else {
        error = await authService.login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
      }

      if (!mounted) return;
      
      if (error == null) {
        final user = authService.currentUser;
        // Treat staff as anyone with any non-guest role
        final isStaff = user != null && user.roles.any((role) => role != AppRole.guest);

        if (isStaff) {
          // Use GoRouter navigation for staff users
          if (context.mounted) {
            try {
              // Close the dialog first
              Navigator.pop(context);
              // Then navigate to dashboard using GoRouter
              context.go('/dashboard');
              ErrorHandler.showInfoMessage(
                context,
                'Welcome! Redirecting to Staff Portal...',
              );
            } catch (e) {
              print('DEBUG: Guest auth navigation error: $e');
            }
          }
        } else {
          Navigator.pop(context);
          ErrorHandler.showSuccessMessage(
            context,
            widget.isSignUp ? 
              'Sign-up successful! Please check your email.' : 
              'Login successful!',
          );
        }
      } else {
        ErrorHandler.handleError(
          context,
          Exception(error),
          customMessage: error,
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'An error occurred during authentication',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your email';
    }
    if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
      return 'Please enter a valid email';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) {
      return 'Please enter your password';
    }
    if (value.length < 6) {
      return 'Password must be at least 6 characters';
    }
    return null;
  }

  String? _validateName(String? value) {
    if (widget.isSignUp && (value == null || value.isEmpty)) {
      return 'Please enter your full name';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (widget.isSignUp) 
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(
                  labelText: 'Full Name',
                  prefixIcon: Icon(Icons.person),
                ),
                validator: _validateName,
                textInputAction: TextInputAction.next,
              ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _emailController,
              decoration: const InputDecoration(
                labelText: 'Email',
                prefixIcon: Icon(Icons.email),
              ),
              validator: _validateEmail,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                prefixIcon: const Icon(Icons.lock),
                suffixIcon: IconButton(
                  icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
                  onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              validator: _validatePassword,
              obscureText: _obscurePassword,
              textInputAction: widget.isSignUp ? TextInputAction.done : TextInputAction.go,
              onFieldSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: _isLoading 
                ? const Center(child: CircularProgressIndicator())
                : ElevatedButton(
                    onPressed: _submit,
                    child: Text(widget.isSignUp ? 'Sign Up' : 'Login'),
                  ),
            ),
            if (!widget.isSignUp) 
              TextButton(
                onPressed: _showForgotPasswordDialog,
                child: const Text('Forgot Password?'),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }
}