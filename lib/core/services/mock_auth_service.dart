import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pzed_homes/data/models/user.dart';

class MockAuthService with ChangeNotifier {
  AppUser? _currentUser;
  bool _isLoading = false;
  bool _isLoggedIn = false;

  AppUser? get currentUser => _currentUser;
  AppRole? get userRole => _currentUser?.role;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;

  // Mock users for testing
  static const Map<String, Map<String, dynamic>> _mockUsers = {
    'owner@pzed.home': {
      'id': 'owner-001',
      'full_name': 'Hotel Owner',
      'roles': ['owner'],
      'password': 'Password123',
    },
    'manager@pzed.home': {
      'id': 'manager-001',
      'full_name': 'Hotel Manager',
      'roles': ['manager'],
      'password': 'Password123',
    },
    'accountant@pzed.home': {
      'id': 'accountant-001',
      'full_name': 'Hotel Accountant',
      'roles': ['accountant'],
      'password': 'Password123',
    },
    'receptionist@pzed.home': {
      'id': 'receptionist-001',
      'full_name': 'Front Desk Receptionist',
      'roles': ['receptionist'],
      'password': 'Password123',
    },
    'bartender@pzed.home': {
      'id': 'bartender-001',
      'full_name': 'Hotel Bartender',
      'roles': ['bartender'],
      'password': 'Password123',
    },
  };

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    print('DEBUG: MockAuthService.login called with email: $email');
    _isLoading = true;
    notifyListeners();

    // Simulate network delay
    await Future.delayed(const Duration(seconds: 1));

    try {
      final userData = _mockUsers[email.toLowerCase()];
      
      if (userData == null) {
        _isLoading = false;
        notifyListeners();
        return 'User not found';
      }

      if (userData['password'] != password) {
        _isLoading = false;
        notifyListeners();
        return 'Invalid password';
      }

      // Create user object
      final roles = (userData['roles'] as List<String>)
          .map((role) => AppRole.values.byName(role))
          .toList();
      
      _currentUser = AppUser(
        id: userData['id'],
        name: userData['full_name'],
        email: userData['email'] ?? '',
        role: roles.first,
        roles: roles,
      );
      
      _isLoggedIn = true;
      _isLoading = false;
      notifyListeners();
      
      print('DEBUG: MockAuthService - Login successful for user: ${_currentUser?.name}');
      print('DEBUG: MockAuthService - User roles: ${_currentUser?.roles.map((r) => r.name)}');
      print('DEBUG: MockAuthService - Is logged in: $_isLoggedIn');
      
      return null; // Success
    } catch (e) {
      _isLoading = false;
      notifyListeners();
      return 'Login failed: $e';
    }
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String fullName,
    required AppRole role,
  }) async {
    // For mock purposes, we don't allow new signups
    return 'Sign up not available in mock mode';
  }

  Future<void> logout() async {
    _currentUser = null;
    _isLoggedIn = false;
    notifyListeners();
  }

  // Get list of available mock users for testing
  static List<Map<String, dynamic>> getAvailableUsers() {
    return _mockUsers.entries.map((entry) {
      return {
        'email': entry.key,
        'name': entry.value['full_name'],
        'roles': entry.value['roles'],
      };
    }).toList();
  }
}

