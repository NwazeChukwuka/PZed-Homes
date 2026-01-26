import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthService with ChangeNotifier {
  SupabaseClient? _supabase;
  AppUser? _currentUser;
  bool _isLoading = true;
  bool _initializationComplete = false; // Track if initialization is done
  bool _isLoggedIn = false;
  bool _isClockedIn = false;
  DateTime? _clockInTime;
  String? _currentAttendanceId;
  bool _isRoleAssumed = false;
  AppRole? _assumedRole;
  StreamSubscription<AuthState>? _authStateSubscription;
  
  // Track if user data is currently loading to prevent concurrent loads
  bool _isLoadingUserData = false;
  // Track if we're currently performing a login to prevent auth state listener interference
  bool _isLoggingIn = false;
  // Track if we're creating a staff account (owner creating new user) - ignore auth state changes
  bool _isCreatingStaffAccount = false;
  
  // Session management
  Timer? _sessionRefreshTimer;
  Timer? _sessionWarningTimer;
  static const int _sessionWarningMinutes = 5; // Warn 5 minutes before expiry

  AppUser? get currentUser => _currentUser;
  AppRole? get userRole => _currentUser?.role;

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  bool get isClockedIn => _isClockedIn;
  DateTime? get clockInTime => _clockInTime;
  bool get isRoleAssumed => _isRoleAssumed;
  AppRole? get assumedRole => _assumedRole;
  
  /// Set flag to ignore auth state changes during staff account creation
  /// This prevents the app from auto-logging in as the newly created staff member
  void setCreatingStaffAccount(bool value) {
    _isCreatingStaffAccount = value;
  }

  AuthService() {
    _isLoading = false;
    _isLoggedIn = false;
    _currentUser = null;
    
    Future.microtask(() => _initializeAuth());
  }

  /// Ensure Supabase is initialized with retry mechanism
  Future<bool> _ensureSupabaseInitialized({int maxRetries = 5, Duration retryDelay = const Duration(milliseconds: 500)}) async {
    if (_supabase != null) {
      return true;
    }

    for (int attempt = 0; attempt < maxRetries; attempt++) {
      try {
        try {
          _supabase = Supabase.instance.client;
          return true;
        } catch (_) {
          _supabase = null;
        }
      } catch (e) {
        // Supabase not ready yet, wait and retry
        if (attempt < maxRetries - 1) {
          await Future.delayed(retryDelay);
        }
      }
    }

    _supabase = null;
    return false;
  }

  Future<void> _initializeAuth() async {
    // Try to get Supabase with retry
    final isInitialized = await _ensureSupabaseInitialized();
    if (!isInitialized) {
      notifyListeners();
      return;
    }

    // ALWAYS start at guest page - don't auto-login on app start
    // This prevents persistent login issues and ensures users explicitly log in
    // Clear any existing session to force re-login
    try {
      final initialSession = _supabase!.auth.currentSession;
      if (initialSession != null) {
        // Sign out any existing session to force explicit login
        await _supabase!.auth.signOut();
      }
    } catch (e) {
      // Ignore errors during sign out
    }
    
    // Always start logged out
    _isLoading = false;
    _isLoggedIn = false;
    _currentUser = null;
    notifyListeners();
    
    // Mark initialization as complete after a short delay
    // This allows the sign-out to complete before we start listening
    Future.delayed(const Duration(milliseconds: 500), () {
      _initializationComplete = true;
    });
    
    if (_supabase != null) {
      _authStateSubscription = _supabase!.auth.onAuthStateChange.listen((data) async {
        // CRITICAL: Skip ALL auth state changes during initialization or explicit login
        // This prevents auto-login when browser reopens
        if (_isLoggingIn || _isLoadingUserData || _isCreatingStaffAccount) {
          return;
        }
        
        // CRITICAL: If initialization is not complete, ignore ALL auth state changes
        // This prevents auto-login from localStorage persistence
        if (!_initializationComplete) {
          // If we see a session during initialization, sign it out immediately
          final session = data.session;
          if (session != null && session.user != null) {
            try {
              await _supabase!.auth.signOut();
            } catch (e) {
              // Ignore errors
            }
          }
          return;
        }
        
        // IMPORTANT: If initialization just completed and we see a session,
        // it's from localStorage persistence - sign out to force explicit login
        final session = data.session;
        if (session != null && session.user != null) {
          // If we don't have a current user, this session is from localStorage - sign out immediately
          if (_currentUser == null) {
            try {
              await _supabase!.auth.signOut();
              _currentUser = null;
              _isLoggedIn = false;
              _isClockedIn = false;
              _clockInTime = null;
              _currentAttendanceId = null;
              _isLoading = false;
              notifyListeners();
              return;
            } catch (e) {
              // If sign out fails, still don't auto-login
              _currentUser = null;
              _isLoggedIn = false;
              _isLoading = false;
              notifyListeners();
              return;
            }
          }
          
          // If we have a current user, this is a legitimate session change
          // Only reload if user ID changed
          if (_currentUser != null && _currentUser!.id != session.user.id) {
            _isLoading = true;
            notifyListeners();
            try {
              await _loadUserData(session.user);
            } catch (e) {
              _isLoading = false;
              notifyListeners();
            }
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

  /// Centralized method to load user data
  Future<void> _loadUserData(User user) async {
    // Prevent concurrent loads
    if (_isLoadingUserData) {
      return;
    }
    
    _isLoadingUserData = true;
    
    if (_supabase == null) {
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      _isLoadingUserData = false;
      notifyListeners();
      throw Exception('Supabase is not configured');
    }

    try {
      // Fetch profile and permissions in parallel with timeouts
      final profileFuture = _supabase!
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single()
          .timeout(const Duration(seconds: 5));
      
      final permissionsFuture = _supabase!
          .from('access_delegations')
          .select('permission')
          .eq('user_id', user.id)
          .timeout(const Duration(seconds: 5));

      final results = await Future.wait<dynamic>([
        profileFuture,
        permissionsFuture,
      ]);

      final profileResponse = results[0] as Map<String, dynamic>?;
      final permissionsResponse = results[1] as List<dynamic>;

      if (profileResponse == null) {
        throw Exception('Profile not found');
      }

      // Safely extract roles - handle any format
      final rolesRaw = profileResponse['roles'];
      final roles = (rolesRaw is List) 
          ? rolesRaw.map((r) => r.toString()).toList()
          : (rolesRaw != null ? [rolesRaw.toString()] : ['guest']);
      
      // Helper function to safely parse a role name without throwing
      AppRole? _safeParseRole(String roleName) {
        final trimmed = roleName.trim();
        if (trimmed.isEmpty) return null;
        
        // Try exact match first
        for (final role in AppRole.values) {
          if (role.name == trimmed) {
            return role;
          }
        }
        
        // Try case-insensitive match
        for (final role in AppRole.values) {
          if (role.name.toLowerCase() == trimmed.toLowerCase()) {
            return role;
          }
        }
        
        return null;
      }
      
      // Parse roles with error handling - never throw
      final parsedRoles = <AppRole>[];
      for (final roleStr in roles) {
        try {
          final roleName = roleStr.toString().trim();
          if (roleName.isEmpty) continue;
          
          final role = _safeParseRole(roleName);
          if (role != null) {
            parsedRoles.add(role);
          } else {
            if (kDebugMode) {
              print('WARNING: Invalid role name: $roleStr');
            }
          }
        } catch (e) {
          // Skip invalid role names - never throw
          if (kDebugMode) {
            print('WARNING: Error parsing role: $roleStr - $e');
          }
        }
      }
      
      // Determine primary role from parsed roles (first valid role, or guest)
      final primaryRole = parsedRoles.isNotEmpty 
          ? parsedRoles.first
          : AppRole.guest;
          
      final permissions = permissionsResponse
          .map((p) => p['permission'] as String)
          .toList();
      
      // #region agent log
      try { 
        final logData = {
          'location': 'auth_service.dart:280',
          'message': 'User roles loaded',
          'data': {
            'userId': profileResponse['id'],
            'rawRoles': roles.map((r) => r.toString()).toList(),
            'parsedRoles': parsedRoles.map((r) => r.name).toList(),
            'primaryRole': primaryRole.name,
            'hasVipBartender': parsedRoles.contains(AppRole.vip_bartender),
            'hasOutsideBartender': parsedRoles.contains(AppRole.outside_bartender)
          },
          'timestamp': DateTime.now().millisecondsSinceEpoch,
          'sessionId': 'debug-session',
          'runId': 'run1',
          'hypothesisId': 'U'
        };
        File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode(logData)}\n', mode: FileMode.append); 
      } catch (_) {}
      print('DEBUG AuthService: userId=${profileResponse['id']}, rawRoles=$roles, parsedRoles=${parsedRoles.map((r) => r.name)}');
      // #endregion
      
      // Ensure we have at least one role
      if (parsedRoles.isEmpty) {
        parsedRoles.add(AppRole.guest);
      }

      _currentUser = AppUser(
        id: profileResponse['id'],
        name: profileResponse['full_name'],
        email: profileResponse['email'] ?? '',
        role: primaryRole,
        roles: parsedRoles.isNotEmpty ? parsedRoles : [primaryRole],
        permissions: permissions,
        department: profileResponse['department'] as String?,
      );
      
      _isLoggedIn = true;
      _isLoading = false;
      _isLoadingUserData = false;
      notifyListeners();
      
      // Check clock-in status for non-management in background
      if (!isManagementRole()) {
        unawaited(_checkClockInStatus());
      }
      
    } catch (e) {
      // On any error, clear user and fail
      _currentUser = null;
      _isLoggedIn = false;
      _isLoading = false;
      _isLoadingUserData = false;
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
    // Ensure Supabase is initialized before attempting signup
    final isInitialized = await _ensureSupabaseInitialized();
    if (!isInitialized) {
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
      // For signup, return the original message as it might be about email already exists, etc.
      // But sanitize invalid credential messages if they appear
      final errorMessage = e.message.toLowerCase();
      final isInvalidCredentials = errorMessage.contains('invalid login credentials') ||
          errorMessage.contains('invalid password') ||
          errorMessage.contains('user not found') ||
          errorMessage.contains('invalid email') ||
          errorMessage.contains('wrong password') ||
          errorMessage.contains('incorrect password') ||
          errorMessage.contains('authentication failed');
      
      if (isInvalidCredentials) {
        return 'Incorrect username and/or password';
      }
      
      return e.message;
    } catch (e) {
      return 'An unexpected error occurred: ${e.toString()}';
    }
  }

  Future<String?> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    // Ensure Supabase is initialized before attempting login
    final isInitialized = await _ensureSupabaseInitialized();
    if (!isInitialized) {
      return 'Supabase is not configured. Please set SUPABASE_URL and SUPABASE_ANON_KEY.';
    }
    
    // Prevent concurrent login attempts
    if (_isLoggingIn) {
      return 'Login already in progress. Please wait.';
    }

    _isLoggingIn = true;
    _isLoading = true;
    notifyListeners();
    
    try {
      // Step 1: Authenticate with timeout
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
      
      // Step 2: Load user data with timeout
      await _loadUserData(response.user!).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('Loading user data timed out. Please try again.');
        },
      );
      
      // Step 3: Verify we have user data
      if (_currentUser == null) {
        await _supabase!.auth.signOut();
        throw Exception('Failed to load user data');
      }
      
      // Step 4: Save remember me preference
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', rememberMe);
      
      // Step 5: Start session monitoring if remember me is enabled
      if (rememberMe && response.session != null) {
        _startSessionMonitoring(response.session!);
      } else {
        // Clear timers if remember me is disabled
        _sessionRefreshTimer?.cancel();
        _sessionWarningTimer?.cancel();
      }
      
      // Give listeners time to update
      await Future.delayed(const Duration(milliseconds: 100));
      
      return null; // Success
      
    } on TimeoutException catch (e) {
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      _isLoggingIn = false;
      notifyListeners();
      return e.message;
    } on AuthException catch (e) {
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      _isLoggingIn = false;
      notifyListeners();
      
      // Check if this is an invalid credentials error
      final errorMessage = e.message.toLowerCase();
      final isInvalidCredentials = errorMessage.contains('invalid login credentials') ||
          errorMessage.contains('invalid password') ||
          errorMessage.contains('user not found') ||
          errorMessage.contains('email not confirmed') ||
          errorMessage.contains('invalid email') ||
          errorMessage.contains('wrong password') ||
          errorMessage.contains('incorrect password') ||
          errorMessage.contains('authentication failed');
      
      if (isInvalidCredentials) {
        return 'Incorrect username and/or password';
      }
      
      // For other auth errors, return the original message
      return e.message;
    } catch (e) {
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      _isLoggingIn = false;
      notifyListeners();
      
      // Provide more specific error messages
      final errorString = e.toString();
      if (errorString.contains('Profile not found')) {
        return 'User profile not found. Please contact support.';
      } else if (errorString.contains('timeout') || errorString.contains('Timeout')) {
        return 'Request timed out. Please check your internet connection and try again.';
      } else {
        return 'Login failed: ${errorString.contains("Invalid login credentials") ? "Invalid email or password" : errorString}';
      }
    } finally {
      _isLoggingIn = false;
    }
  }


  Future<void> logout({bool clearRememberMe = true}) async {
    if (_supabase == null) return;
    
    // Stop session monitoring timers
    _sessionRefreshTimer?.cancel();
    _sessionWarningTimer?.cancel();
    
    if (_isClockedIn) {
      try {
        await clockOut();
      } catch (e) {
        // Continue with logout even if clock out fails
      }
    }
    
    await _supabase!.auth.signOut();
    
    // Clear remember me preference if requested
    if (clearRememberMe) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', false);
    }
    
    _currentUser = null;
    _isLoggedIn = false;
    _isClockedIn = false;
    _clockInTime = null;
    _currentAttendanceId = null;
    _isLoadingUserData = false;
    _isLoggingIn = false;
    _isLoading = false;
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
    // #region agent log
    try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"auth_service.dart:516","message":"clockIn entry","data":{"userId":_currentUser?.id,"supabaseNull":_supabase==null},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"E"})}\n', mode: FileMode.append); } catch (_) {}
    // #endregion
    if (_currentUser == null) {
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"auth_service.dart:518","message":"User null check failed","data":{},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"F"})}\n', mode: FileMode.append); } catch (_) {}
      // #endregion
      throw Exception('User must be logged in to clock in');
    }
    if (_supabase == null) {
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"auth_service.dart:521","message":"Supabase null check failed","data":{},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"G"})}\n', mode: FileMode.append); } catch (_) {}
      // #endregion
      throw Exception('Supabase is not configured');
    }
    
    await _checkClockInStatus();
    if (_isClockedIn) {
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"auth_service.dart:525","message":"Already clocked in check failed","data":{"isClockedIn":_isClockedIn},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"H"})}\n', mode: FileMode.append); } catch (_) {}
      // #endregion
      throw Exception('You are already clocked in today');
    }
    
    try {
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"auth_service.dart:529","message":"Before database insert","data":{"profileId":_currentUser!.id,"date":DateTime.now().toIso8601String().split('T')[0]},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"I"})}\n', mode: FileMode.append); } catch (_) {}
      // #endregion
      final response = await _supabase!
          .from('attendance_records')
          .insert({
            'profile_id': _currentUser!.id,
            'clock_in_time': DateTime.now().toIso8601String(),
            'date': DateTime.now().toIso8601String().split('T')[0],
          })
          .select()
          .single();
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"auth_service.dart:538","message":"Database insert success","data":{"attendanceId":response['id']},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"J"})}\n', mode: FileMode.append); } catch (_) {}
      // #endregion
      _isClockedIn = true;
      _currentAttendanceId = response['id'] as String?;
      _clockInTime = DateTime.now();
      notifyListeners();
    } catch (e) {
      // #region agent log
      try { File('c:\\Users\\user\\PZed-Homes\\PZed-Homes\\.cursor\\debug.log').writeAsStringSync('${jsonEncode({"location":"auth_service.dart:544","message":"Database insert error","data":{"error":e.toString(),"errorType":e.runtimeType.toString()},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"K"})}\n', mode: FileMode.append); } catch (_) {}
      // #endregion
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
    final roles = <AppRole>{
      ..._currentUser!.roles,
      if (_isRoleAssumed && _assumedRole != null) _assumedRole!,
    };
    return roles.contains(AppRole.owner) ||
        roles.contains(AppRole.manager) ||
        roles.contains(AppRole.supervisor) ||
        roles.contains(AppRole.accountant) ||
        roles.contains(AppRole.hr);
  }

  bool canMakeTransactions() {
    // All active staff can make transactions - clock-in is no longer required
    // Clock-in/clock-out is now only for attendance tracking purposes
    return _currentUser != null;
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
    if (route.contains('/inventory')) return null;
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
      case AppRole.vip_bartender:
        return 'VIP Bar Bartender';
      case AppRole.outside_bartender:
        return 'Outside Bar Bartender';
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

  /// Start monitoring session for refresh and timeout warnings
  void _startSessionMonitoring(Session session) {
    // Stop existing timers
    _sessionRefreshTimer?.cancel();
    _sessionWarningTimer?.cancel();
    
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return;
    
    final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    final now = DateTime.now();
    final timeUntilExpiry = expiryTime.difference(now);
    
    // If session expires in less than 5 minutes, refresh immediately
    if (timeUntilExpiry.inMinutes < 5) {
      _refreshSessionIfNeeded();
    } else {
      // Schedule refresh 5 minutes before expiry
      final refreshTime = timeUntilExpiry - const Duration(minutes: 5);
      if (refreshTime.inMinutes > 0) {
        _sessionRefreshTimer = Timer(refreshTime, () {
          _refreshSessionIfNeeded();
        });
      }
    }
    
    // Schedule warning 5 minutes before expiry
    final warningTime = timeUntilExpiry - const Duration(minutes: _sessionWarningMinutes);
    if (warningTime.inMinutes > 0) {
      _sessionWarningTimer = Timer(warningTime, () {
        _showSessionTimeoutWarning();
      });
    }
  }
  
  /// Refresh session if needed (called automatically or manually)
  Future<void> _refreshSessionIfNeeded() async {
    try {
      if (_supabase == null) return;
      
      final currentSession = _supabase!.auth.currentSession;
      if (currentSession == null) return;
      
      final expiresAt = currentSession.expiresAt;
      if (expiresAt == null) return;
      
      final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
      final now = DateTime.now();
      final timeUntilExpiry = expiryTime.difference(now);
      
      // Refresh if expiring in less than 5 minutes
      if (timeUntilExpiry.inMinutes < 5) {
        final refreshedSession = await _supabase!.auth.refreshSession();
        if (refreshedSession.session != null) {
          _startSessionMonitoring(refreshedSession.session!);
          if (kDebugMode) {
            debugPrint('Session refreshed successfully');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Failed to refresh session: $e');
      }
      // If refresh fails, session might be invalid - will require re-login
    }
  }
  
  /// Show session timeout warning (5 minutes before expiry)
  void _showSessionTimeoutWarning() {
    // This will be handled by a dialog in the UI
    // For now, we'll just log it
    if (kDebugMode) {
      debugPrint('Session will expire in 5 minutes');
    }
    // TODO: Show dialog to user with option to extend session
    // This can be implemented later with a callback to show UI
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _sessionRefreshTimer?.cancel();
    _sessionWarningTimer?.cancel();
    super.dispose();
  }
}