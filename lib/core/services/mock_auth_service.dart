import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pzed_homes/data/models/user.dart';

class MockAuthService with ChangeNotifier {
  AppUser? _currentUser;
  bool _isLoading = false;
  bool _isLoggedIn = false;
  bool _isRoleAssumed = false;
  AppRole? _assumedRole;
  bool _isClockedIn = false;
  DateTime? _clockInTime;
  
  // Global attendance tracking for all staff
  static final List<Map<String, dynamic>> _attendanceRecords = [];

  AppUser? get currentUser => _currentUser;
  AppRole? get userRole => _currentUser?.role;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  bool get isRoleAssumed => _isRoleAssumed;
  AppRole? get assumedRole => _assumedRole;
  bool get isClockedIn => _isClockedIn;
  DateTime? get clockInTime => _clockInTime;
  
  // Get all attendance records
  static List<Map<String, dynamic>> getAttendanceRecords() => List.from(_attendanceRecords);

  // Mock users for testing with Igbo names
  static const Map<String, Map<String, dynamic>> _mockUsers = {
    'owner@pzed.home': {
      'id': 'owner-001',
      'full_name': 'P-ZED Owner',
      'roles': ['owner'],
      'password': 'Password123',
    },
    'manager@pzed.home': {
      'id': 'manager-001',
      'full_name': 'Adaeze Nwankwo',
      'roles': ['manager'],
      'password': 'Password123',
    },
    'supervisor@pzed.home': {
      'id': 'supervisor-001',
      'full_name': 'Chidi Nwankwo',
      'roles': ['supervisor'],
      'password': 'Password123',
    },
    'accountant@pzed.home': {
      'id': 'accountant-001',
      'full_name': 'Ngozi Igwe',
      'roles': ['accountant'],
      'password': 'Password123',
    },
    'receptionist@pzed.home': {
      'id': 'receptionist-001',
      'full_name': 'Emeka Onyeka',
      'roles': ['receptionist'],
      'password': 'Password123',
    },
    'bartender@pzed.home': {
      'id': 'bartender-001',
      'full_name': 'Amara Chukwu',
      'roles': ['bartender'],
      'password': 'Password123',
    },
    'hr@pzed.home': {
      'id': 'hr-001',
      'full_name': 'Ifeoma Nwosu',
      'roles': ['hr'],
      'password': 'Password123',
    },
    'storekeeper@pzed.home': {
      'id': 'storekeeper-001',
      'full_name': 'Chioma Eze',
      'roles': ['storekeeper'],
      'password': 'Password123',
    },
    'purchaser@pzed.home': {
      'id': 'purchaser-001',
      'full_name': 'Ikenna Okafor',
      'roles': ['purchaser'],
      'password': 'Password123',
    },
    'kitchen@pzed.home': {
      'id': 'kitchen-001',
      'full_name': 'Obinna Nwosu',
      'roles': ['kitchen_staff'],
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
        permissions: const [],
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
    _isClockedIn = false;
    _clockInTime = null;
    notifyListeners();
  }

  // Clock in/out methods
  void clockIn() {
    _isClockedIn = true;
    _clockInTime = DateTime.now();
    
    // Record attendance
    _attendanceRecords.add({
      'id': 'att-${DateTime.now().millisecondsSinceEpoch}',
      'staff_id': _currentUser?.id ?? 'unknown',
      'staff_name': _currentUser?.name ?? 'Unknown',
      'staff_role': _currentUser?.role.name ?? 'unknown',
      'clock_in_time': _clockInTime!.toIso8601String(),
      'clock_out_time': null,
      'status': 'clocked_in',
      'date': DateTime.now().toIso8601String(),
    });
    
    notifyListeners();
  }

  void clockOut() {
    _isClockedIn = false;
    
    // Update the latest attendance record for this user
    final latestRecord = _attendanceRecords.lastWhere(
      (record) => record['staff_id'] == _currentUser?.id && record['clock_out_time'] == null,
      orElse: () => {},
    );
    
    if (latestRecord.isNotEmpty) {
      latestRecord['clock_out_time'] = DateTime.now().toIso8601String();
      latestRecord['status'] = 'clocked_out';
    }
    
    _clockInTime = null;
    notifyListeners();
  }

  // Check if user is management (doesn't need to clock in)
  bool isManagementRole() {
    final role = _isRoleAssumed ? _assumedRole : _currentUser?.role;
    return role == AppRole.owner ||
           role == AppRole.manager ||
           role == AppRole.supervisor ||
           role == AppRole.accountant ||
           role == AppRole.hr;
  }

  // Check if user can make transactions
  bool canMakeTransactions() {
    // Management can always make transactions
    if (isManagementRole()) return true;
    
    // Junior staff must be clocked in
    return _isClockedIn;
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

  // Role assumption methods
  void assumeRole(AppRole role) {
    _isRoleAssumed = true;
    _assumedRole = role;
    notifyListeners();
  }

  void returnToOriginalRole() {
    _isRoleAssumed = false;
    _assumedRole = null;
    notifyListeners();
  }
  
  // Get suggested role based on current route/section
  static AppRole? getSuggestedRoleForRoute(String route) {
    if (route.contains('/inventory')) return AppRole.bartender;
    if (route.contains('/housekeeping') || route.contains('/mini_mart')) return AppRole.receptionist;
    if (route.contains('/kitchen')) return AppRole.kitchen_staff;
    if (route.contains('/storekeeping')) return AppRole.storekeeper;
    if (route.contains('/purchasing')) return AppRole.purchaser;
    if (route.contains('/finance')) return AppRole.accountant;
    if (route.contains('/hr')) return AppRole.hr;
    return null;
  }
  
  // Get role display name
  static String getRoleDisplayName(AppRole role) {
    switch (role) {
      case AppRole.bartender:
        return 'Bartender';
      case AppRole.receptionist:
        return 'Receptionist';
      case AppRole.kitchen_staff:
        return 'Kitchen Staff';
      case AppRole.storekeeper:
        return 'Storekeeper';
      case AppRole.purchaser:
        return 'Purchaser';
      case AppRole.accountant:
        return 'Accountant';
      case AppRole.hr:
        return 'HR';
      default:
        return role.name.toUpperCase();
    }
  }
}

