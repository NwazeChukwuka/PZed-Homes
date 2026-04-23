import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool _isAuthRecoveryNavigationUri(Uri uri) {
  final p = uri.path;
  if (p.contains('reset-password') || p.contains('auth/callback')) return true;
  if (uri.queryParameters['type'] == 'recovery') return true;
  final f = uri.fragment;
  if (f.contains('type=recovery') || f.contains('refresh_token')) return true;
  return false;
}

class AuthService with ChangeNotifier {
  SupabaseClient? _supabase;
  AppUser? _currentUser;
  bool _isLoading = true;
  bool _initializationComplete = false;
  bool _isLoggedIn = false;
  final List<AppRole> _activeAssumedRoles = [];
  StreamSubscription<AuthState>? _authStateSubscription;
  
  bool _isLoadingUserData = false;
  bool _isLoggingIn = false;
  bool _isCreatingStaffAccount = false;
  bool _isRecovering = false;
  Timer? _sessionRefreshTimer;
  Timer? _sessionWarningTimer;
  static const int _sessionWarningMinutes = 5; // Warn 5 minutes before expiry

  AppUser? get currentUser => _currentUser;
  AppRole? get userRole => _currentUser?.role;

  bool get isLoading => _isLoading;
  bool get isLoggedIn => _isLoggedIn;
  bool get isRoleAssumed => _activeAssumedRoles.isNotEmpty;
  AppRole? get assumedRole => _activeAssumedRoles.isNotEmpty ? _activeAssumedRoles.first : null;
  List<AppRole> get activeAssumedRoles => List.unmodifiable(_activeAssumedRoles);
  bool hasAssumedRole(AppRole role) => _activeAssumedRoles.contains(role);
  
  void setCreatingStaffAccount(bool value) {
    _isCreatingStaffAccount = value;
  }

  bool get isRecovering => _isRecovering;

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
        if (attempt < maxRetries - 1) {
          await Future.delayed(retryDelay);
        }
      }
    }

    _supabase = null;
    return false;
  }

  Future<void> _initializeAuth() async {
    final isInitialized = await _ensureSupabaseInitialized();
    if (!isInitialized) {
      notifyListeners();
      return;
    }

    try {
      final uri = Uri.base;
      final isRecoveryUrl = _isAuthRecoveryNavigationUri(uri);
      final initialSession = _supabase!.auth.currentSession;
      if (initialSession != null && !isRecoveryUrl) {
        await _supabase!.auth.signOut();
      }
      if (initialSession != null && isRecoveryUrl) {
        _isRecovering = true;
      }
    } catch (_) {}

    _isLoading = false;
    _isLoggedIn = false;
    _currentUser = null;
    notifyListeners();

    Future.delayed(const Duration(milliseconds: 500), () {
      _initializationComplete = true;
    });
    
    if (_supabase != null) {
      _authStateSubscription = _supabase!.auth.onAuthStateChange.listen((data) async {
        if (_isLoggingIn || _isLoadingUserData || _isCreatingStaffAccount) {
          return;
        }

        if (data.event == AuthChangeEvent.passwordRecovery) {
          _isRecovering = true;
          _isLoading = false;
          notifyListeners();
          return;
        }

        if (!_initializationComplete) {
          final session = data.session;
          if (session != null && !_isAuthRecoveryNavigationUri(Uri.base)) {
            try {
              await _supabase!.auth.signOut();
            } catch (_) {}
          }
          return;
        }

        final session = data.session;
        if (session != null) {
          final uri = Uri.base;
          final onResetPasswordPage = _isAuthRecoveryNavigationUri(uri);
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
              _isLoading = false;
              clearAssumedRoles();
              notifyListeners();
              return;
            } catch (e) {
              _currentUser = null;
              _isLoggedIn = false;
              _isLoading = false;
              notifyListeners();
              return;
            }
          }

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
          _currentUser = null;
          _isLoggedIn = false;
          _isLoading = false;
          clearAssumedRoles();
          notifyListeners();
        }
      });
    }
  }

  Future<void> _loadUserData(User user) async {
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
      throw Exception('Service is currently unavailable. Please try again later.');
    }

    try {
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

      final rolesRaw = profileResponse['roles'];
      final roles = (rolesRaw is List) 
          ? rolesRaw.map((r) => r.toString()).toList()
          : (rolesRaw != null ? [rolesRaw.toString()] : ['guest']);
      
      AppRole? safeParseRole(String roleName) {
        try {
          final trimmed = roleName.trim();
          if (trimmed.isEmpty) return null;
          for (final role in AppRole.values) {
            if (role.name == trimmed) return role;
          }
          for (final role in AppRole.values) {
            if (role.name.toLowerCase() == trimmed.toLowerCase()) return role;
          }
          return null;
        } catch (e) {
          if (kDebugMode) {
            debugPrint('ERROR in _safeParseRole for "$roleName": $e');
          }
          return null;
        }
      }

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
          if (kDebugMode) {
            print('WARNING: Error parsing role: $roleStr - $e');
          }
        }
      }

      final primaryRole = parsedRoles.isNotEmpty 
          ? parsedRoles.first
          : AppRole.guest;
          
      final permissions = permissionsResponse
          .map((p) => p['permission'] as String)
          .toList();

      if (parsedRoles.isEmpty) {
        parsedRoles.add(AppRole.guest);
      }

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
    } catch (e) {
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
    final isInitialized = await _ensureSupabaseInitialized();
    if (!isInitialized) {
      return 'Service is not configured. Please contact support.';
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
    } on TimeoutException catch (_) {
      return 'The request took too long. Please check your connection and try again.';
    } on AuthException catch (e) {
      return ErrorHandler.getFriendlyErrorMessage(e);
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
    final isInitialized = await _ensureSupabaseInitialized();
    if (!isInitialized) {
      return 'Service is not configured. Please contact support.';
    }
    
    if (_isLoggingIn) {
      return 'Login already in progress. Please wait.';
    }

    _isLoggingIn = true;
    _isLoading = true;
    notifyListeners();
    
    try {
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

      await _loadUserData(response.user!).timeout(
        const Duration(seconds: 8),
        onTimeout: () {
          throw TimeoutException('Loading user data timed out. Please try again.');
        },
      );

      if (_currentUser == null) {
        await _supabase!.auth.signOut();
        throw Exception('Failed to load user data');
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', rememberMe);

      if (rememberMe && response.session != null) {
        _startSessionMonitoring(response.session!);
      } else {
        _sessionRefreshTimer?.cancel();
        _sessionWarningTimer?.cancel();
      }

      await Future.delayed(const Duration(milliseconds: 100));

      return null;

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


  Future<String?> updateUserPassword(String newPassword) async {
    if (_supabase == null) {
      return 'Service is currently unavailable. Please try again later.';
    }
    if (newPassword.trim().length < 6) {
      return 'Password must be at least 6 characters.';
    }
    try {
      await _supabase!.auth.updateUser(UserAttributes(password: newPassword));
      return null;
    } on AuthException catch (e) {
      return ErrorHandler.getFriendlyErrorMessage(e);
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
    
    if (clearRememberMe) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('remember_me', false);
    }
    
    _currentUser = null;
    _isLoggedIn = false;
    _isLoadingUserData = false;
    _isLoggingIn = false;
    _isLoading = false;
    _isRecovering = false;
    clearAssumedRoles();
    notifyListeners();
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
    return _currentUser != null;
  }

  void assumeRole(AppRole role) {
    if (!_activeAssumedRoles.contains(role)) {
      _activeAssumedRoles.add(role);
      notifyListeners();
    }
  }

  void dropAssumedRole(AppRole role) {
    if (_activeAssumedRoles.remove(role)) {
      notifyListeners();
    }
  }

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
      case AppRole.porter:
        return 'Porter';
      default:
        return role.name.toUpperCase();
    }
  }

  void _startSessionMonitoring(Session session) {
    _sessionRefreshTimer?.cancel();
    _sessionWarningTimer?.cancel();
    
    final expiresAt = session.expiresAt;
    if (expiresAt == null) return;
    
    final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
    final now = DateTime.now();
    final timeUntilExpiry = expiryTime.difference(now);
    
    if (timeUntilExpiry.inMinutes < 5) {
      _refreshSessionIfNeeded();
    } else {
      final refreshTime = timeUntilExpiry - const Duration(minutes: 5);
      if (refreshTime.inMinutes > 0) {
        _sessionRefreshTimer = Timer(refreshTime, () {
          _refreshSessionIfNeeded();
        });
      }
    }
    
    final warningTime = timeUntilExpiry - const Duration(minutes: _sessionWarningMinutes);
    if (warningTime.inMinutes > 0) {
      _sessionWarningTimer = Timer(warningTime, () {
        _showSessionTimeoutWarning();
      });
    }
  }
  
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
    }
  }
  
  void _showSessionTimeoutWarning() {
    if (kDebugMode) {
      debugPrint('Session will expire in 5 minutes');
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _sessionRefreshTimer?.cancel();
    _sessionWarningTimer?.cancel();
    super.dispose();
  }
}