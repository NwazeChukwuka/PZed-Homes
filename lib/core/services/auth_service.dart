import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/utils/debug_logger.dart';
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
  /// Session-only list of assumed roles. Never persisted; cleared on logout/refresh.
  final List<AppRole> _activeAssumedRoles = [];
  StreamSubscription<AuthState>? _authStateSubscription;
  
  // Track if user data is currently loading to prevent concurrent loads
  bool _isLoadingUserData = false;
  // Track if we're currently performing a login to prevent auth state listener interference
  bool _isLoggingIn = false;
  // Track if we're creating a staff account (owner creating new user) - ignore auth state changes
  bool _isCreatingStaffAccount = false;
  /// True when user is in password recovery flow (from reset link). Prevents sign-out of recovery session.
  bool _isRecovering = false;
  
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
  /// True if any roles are currently assumed (for backward compatibility).
  bool get isRoleAssumed => _activeAssumedRoles.isNotEmpty;
  /// First assumed role, or null. Kept for backward compat during migration.
  AppRole? get assumedRole => _activeAssumedRoles.isNotEmpty ? _activeAssumedRoles.first : null;
  /// Read-only list of all active assumed roles.
  List<AppRole> get activeAssumedRoles => List.unmodifiable(_activeAssumedRoles);
  /// Check if a specific role is currently assumed.
  bool hasAssumedRole(AppRole role) => _activeAssumedRoles.contains(role);
  
  /// Set flag to ignore auth state changes during staff account creation
  /// This prevents the app from auto-logging in as the newly created staff member
  void setCreatingStaffAccount(bool value) {
    _isCreatingStaffAccount = value;
  }

  /// True when user landed via password reset link. UI should show update-password screen.
  bool get isRecovering => _isRecovering;

  /// Clear recovery state after password update. Call after successful password change.
  void clearRecoveryState() {
    if (_isRecovering) {
      _isRecovering = false;
      notifyListeners();
    }
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
    // EXCEPTION: Do NOT sign out when user landed on password reset URL (recovery flow)
    try {
      final uri = Uri.base;
      final isRecoveryUrl = uri.path.contains('reset-password') ||
          uri.fragment.contains('type=recovery') ||
          uri.fragment.contains('refresh_token') ||
          uri.queryParameters['type'] == 'recovery';
      final initialSession = _supabase!.auth.currentSession;
      if (initialSession != null && !isRecoveryUrl) {
        // Sign out any existing session to force explicit login
        await _supabase!.auth.signOut();
      }
      if (initialSession != null && isRecoveryUrl) {
        _isRecovering = true;
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

        // CRITICAL: Do NOT sign out when user is in password recovery flow
        if (data.event == AuthChangeEvent.passwordRecovery) {
          _isRecovering = true;
          _isLoading = false;
          notifyListeners();
          return;
        }
        
        // CRITICAL: If initialization is not complete, ignore ALL auth state changes
        // This prevents auto-login from localStorage persistence
        if (!_initializationComplete) {
          // If we see a session during initialization, sign it out immediately
          // (passwordRecovery is handled above)
          final session = data.session;
          if (session != null) {
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
        // UNLESS it's password recovery (handled above) or we're on the reset-password URL
        final session = data.session;
        if (session != null) {
          // If we don't have a current user, this session is from localStorage - sign out immediately
          // EXCEPT when in recovery flow (isRecovering keeps the session alive)
          // EXCEPT when on reset-password URL (handles PKCE where passwordRecovery may not fire)
          final uri = Uri.base;
          final onResetPasswordPage = uri.path.contains('reset-password');
          if (_currentUser == null && onResetPasswordPage) {
            _isRecovering = true;
            _isLoading = false;
            notifyListeners();
            return;
          }
          if (_currentUser == null && !_isRecovering) {
            try {
              await _supabase!.auth.signOut();
              _currentUser = null;
              _isLoggedIn = false;
              _isClockedIn = false;
              _clockInTime = null;
              _currentAttendanceId = null;
              _isLoading = false;
              clearAssumedRoles();
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
          clearAssumedRoles();
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
      // NEVER uses byName() - only safe iteration
      AppRole? safeParseRole(String roleName) {
        try {
          final trimmed = roleName.trim();
          if (trimmed.isEmpty) return null;
          
          // Debug: Print all available enum values
          if (kDebugMode && trimmed == 'outside_bartender') {
            print('DEBUG: Looking for outside_bartender');
            print('DEBUG: Available roles: ${AppRole.values.map((r) => r.name).join(', ')}');
          }
          
          // Try exact match first - iterate manually, NEVER use byName()
          for (final role in AppRole.values) {
            if (role.name == trimmed) {
              if (kDebugMode && trimmed == 'outside_bartender') {
                print('DEBUG: Found exact match: ${role.name}');
              }
              return role;
            }
          }
          
          // Try case-insensitive match
          for (final role in AppRole.values) {
            if (role.name.toLowerCase() == trimmed.toLowerCase()) {
              if (kDebugMode && trimmed == 'outside_bartender') {
                print('DEBUG: Found case-insensitive match: ${role.name}');
              }
              return role;
            }
          }
          
          if (kDebugMode && trimmed == 'outside_bartender') {
            print('DEBUG: No match found for: $trimmed');
          }
          return null;
        } catch (e) {
          // Never throw - return null on any error
          if (kDebugMode) {
            print('ERROR in _safeParseRole for "$roleName": $e');
          }
          return null;
        }
      }
      
      // Parse roles with error handling - never throw
      final parsedRoles = <AppRole>[];
      for (final roleStr in roles) {
        try {
          final roleName = roleStr.toString().trim();
          if (roleName.isEmpty) continue;
          
          final role = safeParseRole(roleName);
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
      debugLog({
        'location': 'auth_service.dart:297',
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
      });
      print('DEBUG AuthService: userId=${profileResponse['id']}, rawRoles=$roles, parsedRoles=${parsedRoles.map((r) => r.name)}');
      // #endregion
      
      // Ensure we have at least one role
      if (parsedRoles.isEmpty) {
        parsedRoles.add(AppRole.guest);
      }

      // Create user object with comprehensive error handling
      try {
        _currentUser = AppUser(
          id: profileResponse['id'],
          name: profileResponse['full_name'],
          email: profileResponse['email'] ?? '',
          role: primaryRole,
          roles: parsedRoles.isNotEmpty ? parsedRoles : [primaryRole],
          permissions: permissions,
          department: profileResponse['department'] as String?,
        );
      } catch (e) {
        // If creating AppUser fails, log and use guest role
        if (kDebugMode) {
          print('ERROR creating AppUser: $e');
          print('Stack trace: ${StackTrace.current}');
        }
        _currentUser = AppUser(
          id: profileResponse['id'],
          name: profileResponse['full_name'] ?? 'Unknown',
          email: profileResponse['email'] ?? '',
          role: AppRole.guest,
          roles: [AppRole.guest],
          permissions: [],
          department: profileResponse['department'] as String?,
        );
      }
      
      _isLoggedIn = true;
      _isLoading = false;
      _isLoadingUserData = false;
      notifyListeners();
      
      // Clock-in check removed - no longer required
      
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
    } catch (e, stackTrace) {
      if (kDebugMode) {
        debugPrint('DEBUG signUp error: $e\n$stackTrace');
      }
      return ErrorHandler.getFriendlyErrorMessage(e);
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
    } catch (e, stackTrace) {
      _isLoading = false;
      _isLoggedIn = false;
      _currentUser = null;
      _isLoggingIn = false;
      notifyListeners();
      if (kDebugMode) {
        debugPrint('DEBUG login error: $e\n$stackTrace');
      }
      return ErrorHandler.getFriendlyErrorMessage(e);
    } finally {
      _isLoggingIn = false;
    }
  }


  /// Update user password. For recovery flow, call clearRecoveryState() after success.
  /// Returns null on success, or a user-friendly error message on failure.
  Future<String?> updateUserPassword(String newPassword) async {
    if (_supabase == null) {
      return 'Supabase is not configured.';
    }
    if (newPassword.trim().length < 6) {
      return 'Password must be at least 6 characters.';
    }
    try {
      await _supabase!.auth.updateUser(UserAttributes(password: newPassword));
      return null;
    } on AuthException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('should be different') || msg.contains('same as')) {
        return 'New password must be different from your current password.';
      }
      if (msg.contains('weak') || msg.contains('at least')) {
        return 'Password is too weak. Use at least 6 characters.';
      }
      if (msg.contains('expired') || msg.contains('invalid') || msg.contains('recovery')) {
        return 'Reset link expired or invalid. Please request a new one.';
      }
      return e.message;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG updateUserPassword: $e\n$stack');
      return ErrorHandler.getFriendlyErrorMessage(e);
    }
  }

  Future<void> logout({bool clearRememberMe = true}) async {
    if (_supabase == null) return;
    
    _sessionRefreshTimer?.cancel();
    _sessionWarningTimer?.cancel();
    DataService().invalidateAllCache();
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
    _isRecovering = false;
    clearAssumedRoles();
    notifyListeners();
  }

  // Clock-in/clock-out functionality removed - no longer required
  // Transactions can be made without clocking in
  Future<void> _checkClockInStatus() async {
    // No-op - clock-in is disabled
    _isClockedIn = false;
    _currentAttendanceId = null;
    _clockInTime = null;
  }

  Future<void> clockIn() async {
    // Clock-in functionality removed - do nothing
    // Transactions work without clock-in
    return;
  }

  Future<void> clockOut() async {
    // Clock-out functionality removed - do nothing
    return;
  }

  bool isManagementRole() {
    if (_currentUser == null) return false;
    final roles = <AppRole>{
      ..._currentUser!.roles,
      ..._activeAssumedRoles,
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

  /// Add a role to the active assumed roles (stacking). Idempotent if already assumed.
  void assumeRole(AppRole role) {
    if (!_activeAssumedRoles.contains(role)) {
      _activeAssumedRoles.add(role);
      notifyListeners();
    }
  }

  /// Remove a specific assumed role.
  void dropAssumedRole(AppRole role) {
    if (_activeAssumedRoles.remove(role)) {
      notifyListeners();
    }
  }

  /// Clear all assumed roles. Called on logout/refresh.
  void clearAssumedRoles() {
    if (_activeAssumedRoles.isNotEmpty) {
      _activeAssumedRoles.clear();
      notifyListeners();
    }
  }

  @Deprecated('Use dropAssumedRole or clearAssumedRoles instead')
  void clearAssumedRole() => clearAssumedRoles();

  @Deprecated('Use dropAssumedRole for specific role, or clearAssumedRoles for all')
  void returnToOriginalRole() => clearAssumedRoles();

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