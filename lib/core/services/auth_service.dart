import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService with ChangeNotifier {
  SupabaseClient? _supabase;
  AppUser? _currentUser;
  bool _isLoading = true;
  bool _isLoggedIn = false;
  bool _isClockedIn = false;
  DateTime? _clockInTime;
  String? _currentAttendanceId;
  bool _isRoleAssumed = false;
  AppRole? _assumedRole;
  StreamSubscription<AuthState>? _authStateSubscription;
  
  // Track if user data is currently loading
  Completer<void>? _userDataCompleter;

  AppUser? get currentUser => _currentUser;
  AppRole? get userRole => _currentUser?.role;

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  bool get isClockedIn => _isClockedIn;
  DateTime? get clockInTime => _clockInTime;
  bool get isRoleAssumed => _isRoleAssumed;
  AppRole? get assumedRole => _assumedRole;

  AuthService() {
    _isLoading = false;
    _isLoggedIn = false;
    _currentUser = null;
    
    Future.microtask(() => _initializeAuth());
  }

  Future<void> _initializeAuth() async {
    try {
      _supabase = Supabase.instance.client;
    } catch (e) {
      _supabase = null;
      notifyListeners();
      return;
    }

    try {
      final initialSession = _supabase!.auth.currentSession;
      if (initialSession != null) {
        _isLoading = true;
        notifyListeners();
        await _loadUserData(initialSession.user);
      }
    } catch (e) {
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      notifyListeners();
    }
    
    if (_supabase != null) {
      _authStateSubscription = _supabase!.auth.onAuthStateChange.listen((data) async {
        // Skip if we're currently loading user data to avoid race conditions
        if (_userDataCompleter != null && !_userDataCompleter!.isCompleted) {
          return;
        }
        
        final session = data.session;
        if (session != null && session.user != null) {
          // Only reload if we don't have a current user or user ID changed
          if (_currentUser == null || _currentUser!.id != session.user.id) {
            _isLoading = true;
            notifyListeners();
            await _loadUserData(session.user);
          }
        } else {
          // User logged out
          _currentUser = null;
          _isLoggedIn = false;
          _isClockedIn = false;
          _clockInTime = null;
          _currentAttendanceId = null;
          _isLoading = false;
          notifyListeners();
        }
      });
    }
  }

  /// Centralized method to load user data with proper timeout handling
  Future<void> _loadUserData(User user) async {
    // Create or reuse completer
    if (_userDataCompleter != null && !_userDataCompleter!.isCompleted) {
      // Already loading, wait for existing load
      return _userDataCompleter!.future;
    }
    
    _userDataCompleter = Completer<void>();
    
    if (_supabase == null) {
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      _userDataCompleter!.complete();
      notifyListeners();
      return;
    }

    try {
      // Fetch profile and permissions in parallel with individual timeouts
      final profileFuture = _supabase!
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single()
          .timeout(const Duration(seconds: 8));
      
      final permissionsFuture = _supabase!
          .from('access_delegations')
          .select('permission')
          .eq('user_id', user.id)
          .timeout(const Duration(seconds: 8));

      final results = await Future.wait<dynamic>([
        profileFuture,
        permissionsFuture,
      ]);

      final profileResponse = results[0] as Map<String, dynamic>?;
      final permissionsResponse = results[1] as List<dynamic>;

      if (profileResponse != null) {
        final roles = (profileResponse['roles'] as List<dynamic>? ?? ['guest']);
        final primaryRole = roles.isNotEmpty 
            ? AppRole.values.byName(roles.first as String)
            : AppRole.guest;
            
        final permissions = permissionsResponse
            .map((p) => p['permission'] as String)
            .toList();

        _currentUser = AppUser(
          id: profileResponse['id'],
          name: profileResponse['full_name'],
          email: profileResponse['email'] ?? '',
          role: primaryRole,
          roles: roles.map((role) => AppRole.values.byName(role as String)).toList(),
          permissions: permissions,
        );
        
        _isLoggedIn = true;
        
        // Check clock-in status for non-management in background
        if (!isManagementRole()) {
          unawaited(_checkClockInStatus());
        }
      } else {
        throw Exception('Profile not found');
      }
      
      _isLoading = false;
      _userDataCompleter!.complete();
      notifyListeners();
      
    } catch (e) {
      // On any error, clear user and fail
      _currentUser = null;
      _isLoggedIn = false;
      _isLoading = false;
      _userDataCompleter!.completeError(e);
      notifyListeners();
      rethrow;
    }
  }

  Future<String?> signUp({
    required String email,
    required String password,
    required String fullName,
    required AppRole role,
  }) async {
    if (_supabase == null) {
      return 'Supabase is not configured. Please set SUPABASE_URL and SUPABASE_ANON_KEY.';
    }
    
    try {
      await _supabase!.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'roles': ['guest'],
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          throw TimeoutException('Sign up request timed out. Please check your internet connection and try again.');
        },
      );
      
      return null;
    } on TimeoutException catch (e) {
      return e.message;
    } on AuthException catch (e) {
      return e.message;
    } catch (e) {
      return 'An unexpected error occurred: ${e.toString()}';
    }
  }

  Future<String?> login({
    required String email,
    required String password,
  }) async {
    if (_supabase == null) {
      return 'Supabase is not configured. Please set SUPABASE_URL and SUPABASE_ANON_KEY.';
    }
    
    try {
      // Set loading state immediately
      _isLoading = true;
      notifyListeners();
      
      // Step 1: Authenticate (fast - usually <2 seconds)
      final response = await _supabase!.auth.signInWithPassword(
        email: email,
        password: password,
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw TimeoutException('Login request timed out. Please check your internet connection and try again.');
        },
      );
      
      if (response.user == null) {
        throw Exception('Login failed: No user returned');
      }
      
      // Step 2: Start loading user data BUT with a race condition handler
      // We'll wait up to 3 seconds for user data, then return success anyway
      final userDataFuture = _loadUserData(response.user!);
      
      try {
        // Wait maximum 3 seconds for user data
        await userDataFuture.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            // User data is taking too long, but auth succeeded
            // Return success and let data load in background
            if (kDebugMode) {
              print('⚠️ User data loading slowly, proceeding with login...');
            }
          },
        );
      } on TimeoutException {
        // Timeout is expected - data is just slow, continue with polling
        if (kDebugMode) {
          print('⚠️ User data loading slowly, proceeding with login...');
        }
      } catch (e) {
        // Real error (not timeout) - log but continue to polling
        // If it's a critical error, polling will catch it
        if (kDebugMode) {
          print('⚠️ User data load error (will retry): $e');
        }
      }
      
      // At this point, either:
      // 1. User data loaded successfully (best case)
      // 2. User data is still loading in background (acceptable)
      // 3. User data failed but we'll retry via auth state listener
      
      // Check if we got user data within the 3 second window
      if (_currentUser != null) {
        // Success - we have full user data
        return null;
      } else {
        // User data still loading or failed - wait a bit more
        // Give it 2 more attempts (total 5 seconds max)
        for (int i = 0; i < 2; i++) {
          await Future.delayed(const Duration(seconds: 1));
          if (_currentUser != null) {
            return null; // Got it!
          }
        }
        
        // After 5 seconds total, if still no user data, fail
        if (_currentUser == null) {
          await _supabase!.auth.signOut();
          _isLoading = false;
          notifyListeners();
          throw Exception('Failed to load user data. Please try again.');
        }
      }
      
      return null; // Success
      
    } on TimeoutException catch (e) {
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      notifyListeners();
      return e.message;
    } on AuthException catch (e) {
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      notifyListeners();
      return e.message;
    } catch (e) {
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      notifyListeners();
      return 'Login failed: ${e.toString()}';
    }
  }

  /// Wait for user data to be available (with timeout)
  Future<bool> waitForUserData({Duration timeout = const Duration(seconds: 5)}) async {
    if (_currentUser != null) return true;
    if (_userDataCompleter == null) return false;
    
    try {
      await _userDataCompleter!.future.timeout(timeout);
      return _currentUser != null;
    } catch (e) {
      return false;
    }
  }

  Future<void> logout() async {
    if (_supabase == null) return;
    
    if (_isClockedIn) {
      try {
        await clockOut();
      } catch (e) {
        // Continue with logout even if clock out fails
      }
    }
    
    await _supabase!.auth.signOut();
    _currentUser = null;
    _isLoggedIn = false;
    _isClockedIn = false;
    _clockInTime = null;
    _currentAttendanceId = null;
    _userDataCompleter = null;
    notifyListeners();
  }

  Future<void> _checkClockInStatus() async {
    if (_currentUser == null || _supabase == null) return;
    
    try {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      
      final response = await _supabase!
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
      _isClockedIn = false;
      _currentAttendanceId = null;
      _clockInTime = null;
    }
  }

  Future<void> clockIn() async {
    if (_currentUser == null) {
      throw Exception('User must be logged in to clock in');
    }
    if (_supabase == null) {
      throw Exception('Supabase is not configured');
    }
    
    await _checkClockInStatus();
    if (_isClockedIn) {
      throw Exception('You are already clocked in today');
    }
    
    try {
      final response = await _supabase!
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

  Future<void> clockOut() async {
    if (_currentUser == null || !_isClockedIn || _currentAttendanceId == null) {
      throw Exception('You are not clocked in');
    }
    if (_supabase == null) {
      throw Exception('Supabase is not configured');
    }
    
    try {
      await _supabase!
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

  bool isManagementRole() {
    if (_currentUser == null) return false;
    final role = _isRoleAssumed ? (_assumedRole ?? _currentUser!.role) : _currentUser!.role;
    return role == AppRole.owner ||
           role == AppRole.manager ||
           role == AppRole.supervisor ||
           role == AppRole.accountant ||
           role == AppRole.hr;
  }

  bool canMakeTransactions() {
    if (isManagementRole()) return true;
    return _isClockedIn;
  }

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

  void returnToOriginalRole() {
    clearAssumedRole();
  }

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