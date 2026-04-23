import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/presentation/screens/login_screen.dart';
import 'package:pzed_homes/presentation/screens/main_screen.dart';

class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      child: const SizedBox.shrink(),
      builder: (context, authService, child) {
        if (authService.currentUser != null) {
          return MainScreen(child: child ?? const SizedBox.shrink());
        }
        return const LoginScreen();
      },
    );
  }
}






