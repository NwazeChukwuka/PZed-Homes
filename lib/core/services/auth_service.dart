import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService with ChangeNotifier {
  final _supabase = Supabase.instance.client;
  AppUser? _currentUser;
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _isClockedIn = false;
  DateTime? _clockInTime;
  String? _currentAttendanceId;
  bool _isRoleAssumed = false;
  AppRole? _assumedRole;
  StreamSubscription<AuthState>? _authStateSubscription;

  AppUser? get currentUser => _currentUser;
  AppRole? get userRole => _currentUser?.role;

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  bool get isClockedIn => _isClockedIn;
  DateTime? get clockInTime => _clockInTime;
  bool get isRoleAssumed => _isRoleAssumed;
  AppRole? get assumedRole => _assumedRole;

  AuthService() {
    // Check initial session synchronously first (fast check)
    final initialSession = _supabase.auth.currentSession;
    if (initialSession != null) {
      // User has a session - load their data asynchronously
      _isLoading = true;
      _initializeAuthState(initialSession.user);
    } else {
      // No session - user is not logged in, clear loading immediately
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      notifyListeners();
    }
    
    // Listen to auth state changes (for future logins/logouts)
    _authStateSubscription = _supabase.auth.onAuthStateChange.listen((data) async {
      // Skip if we're still in initial loading
      if (_isLoading && data.session == null && !_isLoggedIn) {
        return;
      }
      
      // Only set loading if we're actually changing state
      final wasLoggedIn = _isLoggedIn;
      final hasSession = data.session != null;
      
      if (wasLoggedIn != hasSession) {
        _isLoading = true;
        notifyListeners();
      }

      final session = data.session;
      if (session != null) {
        await _onUserLoggedIn(session.user);
        _isLoggedIn = true;
      } else {
        _currentUser = null;
        _isLoggedIn = false;
        _isClockedIn = false;
        _clockInTime = null;
        _currentAttendanceId = null;
      }

      if (wasLoggedIn != hasSession) {
        _isLoading = false;
        notifyListeners();
      }
    });
  }

  Future<void> _initializeAuthState(User user) async {
    try {
      // Load user data with timeout to prevent hanging
      await _onUserLoggedIn(user).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          // If timeout, still mark as logged in
          _isLoggedIn = true;
        },
      );
      _isLoggedIn = true;
    } catch (e) {
      // On error, assume not logged in
      _isLoggedIn = false;
      _currentUser = null;
    } finally {
      // Always clear loading state
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _onUserLoggedIn(User user) async {
    try {
      // Optimize: Fetch profile and permissions in parallel
      // This reduces total wait time from 2 sequential queries to 1 parallel query
      final profileFuture = _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();
      
      final permissionsFuture = _supabase
          .from('access_delegations')
          .select('permission')
          .eq('user_id', user.id);

      // Wait for both queries in parallel
      final results = await Future.wait([
        profileFuture as Future<dynamic>,
        permissionsFuture as Future<dynamic>,
      ]);
      final profileResponse = results[0] as Map<String, dynamic>?;
      final permissionsResponse = results[1] as List<dynamic>;

      if (profileResponse != null) {
        // Handle roles as array - get the first role for now
        final roles = (profileResponse['roles'] as List<dynamic>? ?? []);
        final primaryRole = roles.isNotEmpty 
            ? AppRole.values.byName(roles.first as String)
            : AppRole.guest;
            
        final permissions = permissionsResponse.map((p) => p['permission'] as String).toList();

        // Create the AppUser with roles AND permissions
        _currentUser = AppUser(
          id: profileResponse['id'],
          name: profileResponse['full_name'],
          email: profileResponse['email'] ?? '',
          role: primaryRole,
          roles: roles.map((role) => AppRole.values.byName(role as String)).toList(),
          permissions: permissions,
        );
        
        // Check clock-in status in background (non-blocking for login flow)
        // Only check if user is not management (management doesn't need to clock in)
        // Don't await - let it run in background
        if (!isManagementRole()) {
          _checkClockInStatus(); // Fire and forget - don't await
        }
      }
    } catch (_) {
      _currentUser = null;
      _isLoggedIn = false;
    }
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String fullName,
    required AppRole role, // Ignored - always creates guest
  }) async {
    try {
      // Force guest role - staff profiles can only be created by management via HR screen
      await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'roles': ['guest'], // Always guest - database trigger also enforces this
        },
      );
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    try {
      await _supabase.auth.signInWithPassword(email: email, password: password);
      return null;
    } on AuthException catch (e) {
      return e.message;
    }
  }

  Future<void> logout() async {
    // Clock out if still clocked in
    if (_isClockedIn) {
      await clockOut();
    }
    await _supabase.auth.signOut();
    _currentUser = null;
    _isLoggedIn = false;
    _isClockedIn = false;
    _clockInTime = null;
    _currentAttendanceId = null;
    notifyListeners();
  }

  // Check if user is currently clocked in (from database)
  Future<void> _checkClockInStatus() async {
    if (_currentUser == null) return;
    
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      
      // Optimize: Only select needed fields to reduce data transfer
      final response = await _supabase
          .from('attendance_records')
          .select('id, clock_in_time')
          .eq('profile_id', _currentUser!.id)
          .gte('clock_in_time', startOfDay.toIso8601String())
          .isFilter('clock_out_time', null)
          .order('clock_in_time', ascending: false)
          .limit(1)
          .maybeSingle();
      
      if (response != null) {
        _isClockedIn = true;
        _currentAttendanceId = response['id'] as String?;
        _clockInTime = DateTime.tryParse(response['clock_in_time'] as String? ?? '');
      } else {
        _isClockedIn = false;
        _currentAttendanceId = null;
        _clockInTime = null;
      }
      notifyListeners();
    } catch (e) {
      // If error, assume not clocked in
      _isClockedIn = false;
      _currentAttendanceId = null;
      _clockInTime = null;
    }
  }

  // Clock in - saves to Supabase
  Future<void> clockIn() async {
    if (_currentUser == null) {
      throw Exception('User must be logged in to clock in');
    }
    
    // Check if already clocked in today
    await _checkClockInStatus();
    if (_isClockedIn) {
      throw Exception('You are already clocked in today');
    }
    
    try {
      final response = await _supabase
          .from('attendance_records')
          .insert({
            'profile_id': _currentUser!.id,
            'clock_in_time': DateTime.now().toIso8601String(),
            'date': DateTime.now().toIso8601String().split('T')[0],
          })
          .select()
          .single();
      
      _isClockedIn = true;
      _currentAttendanceId = response['id'] as String?;
      _clockInTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to clock in: $e');
    }
  }

  // Clock out - updates Supabase record
  Future<void> clockOut() async {
    if (_currentUser == null || !_isClockedIn || _currentAttendanceId == null) {
      throw Exception('You are not clocked in');
    }
    
    try {
      await _supabase
          .from('attendance_records')
          .update({
            'clock_out_time': DateTime.now().toIso8601String(),
          })
          .eq('id', _currentAttendanceId!);
      
      _isClockedIn = false;
      _clockInTime = null;
      _currentAttendanceId = null;
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to clock out: $e');
    }
  }

  // Check if user is management (doesn't need to clock in)
  bool isManagementRole() {
    if (_currentUser == null) return false;
    // Consider assumed role if one is set
    final role = _isRoleAssumed ? (_assumedRole ?? _currentUser!.role) : _currentUser!.role;
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

  // Role assumption (for compatibility with MockAuthService)
  // In production, this can be used for temporary role delegation
  void assumeRole(AppRole role) {
    _isRoleAssumed = true;
    _assumedRole = role;
    notifyListeners();
  }

  void clearAssumedRole() {
    _isRoleAssumed = false;
    _assumedRole = null;
    notifyListeners();
  }

  // Alias for compatibility with MockAuthService
  void returnToOriginalRole() {
    clearAssumedRole();
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

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }
}