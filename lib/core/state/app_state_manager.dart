import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pzed_homes/core/connectivity/app_connectivity.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/core/state/app_state.dart';

class AppStateManager extends ChangeNotifier {
  static const bool _useMock = bool.fromEnvironment('USE_MOCK', defaultValue: false);
  SupabaseClient? get _supabase {
    if (_useMock) return null;
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
  AppConnectivity? _connectivity;
  
  // App state
  bool _isInitialized = false;
  bool _isLoading = false;
  String? _error;
  
  // User state
  AppUser? _currentUser;
  List<AppRole> _userRoles = [];
  List<String> _accessibleFeatures = [];
  
  // Navigation state
  int _currentIndex = 0;
  String _currentRoute = '/dashboard';
  
  // Theme state
  bool _isDarkMode = false;
  String _selectedLanguage = 'en';
  
  // Notifications state
  int _unreadNotifications = 0;
  List<Map<String, dynamic>> _notifications = [];
  
  // Cache state
  Map<String, dynamic> _cache = {};
  DateTime? _lastCacheUpdate;
  
  // Getters
  bool get isInitialized => _isInitialized;
  bool get isLoading => _isLoading;
  String? get error => _error;
  AppUser? get currentUser => _currentUser;
  List<AppRole> get userRoles => _userRoles;
  List<String> get accessibleFeatures => _accessibleFeatures;
  int get currentIndex => _currentIndex;
  String get currentRoute => _currentRoute;
  bool get isDarkMode => _isDarkMode;
  String get selectedLanguage => _selectedLanguage;
  int get unreadNotifications => _unreadNotifications;
  List<Map<String, dynamic>> get notifications => _notifications;
  Map<String, dynamic> get cache => _cache;
  DateTime? get lastCacheUpdate => _lastCacheUpdate;
  
  // Connectivity getters
  bool get isOnline => _connectivity?.isOnline ?? true;
  ConnectivityResult get connectionStatus => _connectivity?.connectionStatus ?? ConnectivityResult.wifi;
  
  // Initialize the state manager - critical path first, defer non-critical work
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _setLoading(true);
    try {
      _connectivity = AppConnectivity();
      await _loadUserData();
      await _initializeCache();
      _isInitialized = true;
      _setError(null);
      // Defer notifications and realtime - run in background after first interactive
      _deferNonCriticalInit();
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG initialize: $e\n$stack');
      _setError(ErrorHandler.getFriendlyErrorMessage(e));
    } finally {
      _setLoading(false);
    }
  }

  void _deferNonCriticalInit() {
    Future.microtask(() async {
      try {
        await _loadNotifications();
        startRealtimeSubscriptions();
      } catch (e, stack) {
        if (kDebugMode) debugPrint('DEBUG deferred init: $e\n$stack');
      }
    });
  }
  
  // User management
  Future<void> _loadUserData() async {
    try {
      if (_useMock || _supabase == null) {
        return; // In mock mode, rely on AuthService for user state
      }
      final user = _supabase!.auth.currentUser;
      if (user != null) {
        final userRoles = List<AppRole>.from((user.userMetadata?['roles'] as List?)?.map((r) => AppRole.values.firstWhere((role) => role.name == r, orElse: () => AppRole.guest)) ?? [AppRole.guest]);
        _currentUser = AppUser(
          id: user.id,
          name: user.userMetadata?['full_name'] ?? user.email ?? 'User',
          email: user.email ?? '',
          role: userRoles.isNotEmpty ? userRoles.first : AppRole.guest,
          roles: userRoles,
          permissions: const [],
          department: user.userMetadata?['department'] as String?,
        );
        _userRoles = _currentUser?.roles ?? [];
        _accessibleFeatures = _getAccessibleFeatures();
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _loadUserData: $e\n$stack');
      _setError(ErrorHandler.getFriendlyErrorMessage(e));
    }
  }
  
  List<String> _getAccessibleFeatures() {
    final features = <String>{};
    for (var role in _userRoles) {
      features.addAll(PermissionManager.getAccessibleFeatures(role));
    }
    return features.toList();
  }
  
  // Navigation management
  void setCurrentIndex(int index) {
    if (_currentIndex == index) return;
    _currentIndex = index;
    notifyListeners();
  }
  
  void setCurrentRoute(String route) {
    if (_currentRoute == route) return;
    _currentRoute = route;
    notifyListeners();
  }
  
  // Theme management
  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }
  
  void setLanguage(String language) {
    if (_selectedLanguage == language) return;
    _selectedLanguage = language;
    notifyListeners();
  }
  
  // Notification management
  Future<void> _loadNotifications() async {
    try {
      if (_useMock || _supabase == null || !isOnline) {
        return;
      }
      final response = await _supabase!
          .from('notifications')
          .select('*')
          .eq('user_id', _currentUser?.id ?? '')
          .order('created_at', ascending: false)
          .limit(50);
      final newNotifications = List<Map<String, dynamic>>.from(response);
      final newUnread = newNotifications.where((n) => !n['is_read']).length;
      // Only notify when notification state actually changed
      if (_notifications.length == newNotifications.length &&
          _unreadNotifications == newUnread) {
        return;
      }
      _notifications = newNotifications;
      _unreadNotifications = newUnread;
      notifyListeners();
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _loadNotifications: $e\n$stack');
    }
  }
  
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      if (_useMock || _supabase == null) return;
      await _supabase!
          .from('notifications')
          .update({'is_read': true})
          .eq('id', notificationId);
      await _loadNotifications();
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG markNotificationAsRead: $e\n$stack');
      _setError(ErrorHandler.getFriendlyErrorMessage(e));
    }
  }
  
  Future<void> markAllNotificationsAsRead() async {
    try {
      if (_useMock || _supabase == null) return;
      await _supabase!
          .from('notifications')
          .update({'is_read': true})
          .eq('user_id', _currentUser?.id ?? '');
      await _loadNotifications();
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG markAllNotificationsAsRead: $e\n$stack');
      _setError(ErrorHandler.getFriendlyErrorMessage(e));
    }
  }
  
  // Cache management
  Future<void> _initializeCache() async {
    _cache = {};
    _lastCacheUpdate = DateTime.now();
  }
  
  void setCache(String key, dynamic value) {
    final prev = _cache[key];
    if (identical(prev, value) || prev == value) return;
    _cache[key] = value;
    _lastCacheUpdate = DateTime.now();
    notifyListeners();
  }
  
  T? getCache<T>(String key) {
    return _cache[key] as T?;
  }
  
  void clearCache({bool notify = true}) {
    if (_cache.isEmpty && _lastCacheUpdate == null) return;
    _cache.clear();
    _lastCacheUpdate = null;
    if (notify) notifyListeners();
  }
  
  // Data refresh
  Future<void> refreshData() async {
    if (!isOnline) {
      _setError('Cannot refresh data while offline');
      return;
    }
    
    _setLoading(true);
    try {
      await _loadUserData();
      await _loadNotifications();
      _setError(null);
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG refreshData: $e\n$stack');
      _setError(ErrorHandler.getFriendlyErrorMessage(e));
    } finally {
      _setLoading(false);
    }
  }
  
  // Error handling
  void _setError(String? error) {
    if (_error == error) return;
    _error = error;
    notifyListeners();
  }
  
  void clearError() {
    _setError(null);
  }
  
  // Loading state
  void _setLoading(bool loading) {
    if (_isLoading == loading) return;
    _isLoading = loading;
    notifyListeners();
  }
  
  // Logout
  Future<void> logout() async {
    try {
      if (!(_useMock || _supabase == null)) {
        await _supabase!.auth.signOut();
      }
      _currentUser = null;
      _userRoles = [];
      _accessibleFeatures = [];
      _notifications = [];
      _unreadNotifications = 0;
      clearCache(notify: false);
      notifyListeners();
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG logout: $e\n$stack');
      _setError(ErrorHandler.getFriendlyErrorMessage(e));
    }
  }
  
  // Utility methods
  bool hasPermission(String feature) {
    return _accessibleFeatures.contains(feature);
  }
  
  bool hasRole(AppRole role) {
    return _userRoles.contains(role);
  }
  
  bool isAdmin() {
    return _userRoles.contains(AppRole.owner) || _userRoles.contains(AppRole.manager);
  }
  
  // Real-time subscriptions
  void startRealtimeSubscriptions() {
    if (_useMock || _supabase == null || !isOnline) return;
    _supabase!
        .channel('user_notifications')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'notifications',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: _currentUser?.id,
          ),
          callback: (_) {
            _loadNotifications().catchError((e, stack) {
              if (kDebugMode) debugPrint('DEBUG realtime callback: $e\n$stack');
              _setError(ErrorHandler.getFriendlyErrorMessage(e));
              notifyListeners();
            });
          },
        )
        .subscribe();
  }
  
  void stopRealtimeSubscriptions() {
    if (_useMock || _supabase == null) return;
    _supabase!.removeAllChannels();
  }
  
  @override
  void dispose() {
    stopRealtimeSubscriptions();
    super.dispose();
  }
}

// App state provider widget
class AppStateProvider extends StatelessWidget {
  final Widget child;
  
  const AppStateProvider({
    super.key,
    required this.child,
  });
  
  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AppStateManager(),
      child: child,
    );
  }
}

// App state consumer widget
class AppStateConsumer extends StatelessWidget {
  final Widget Function(BuildContext context, AppStateManager state, Widget? child) builder;
  final Widget? child;
  
  const AppStateConsumer({
    super.key,
    required this.builder,
    this.child,
  });
  
  @override
  Widget build(BuildContext context) {
    return Consumer<AppStateManager>(
      builder: builder,
      child: child,
    );
  }
}
