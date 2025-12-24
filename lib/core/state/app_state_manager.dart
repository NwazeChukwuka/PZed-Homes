import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:pzed_homes/core/connectivity/app_connectivity.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/core/state/app_state.dart';

class AppStateManager extends ChangeNotifier {
  static const bool _useMock = bool.fromEnvironment('USE_MOCK', defaultValue: true);
  final SupabaseClient? _supabase = _useMock ? null : Supabase.instance.client;
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
  
  // Initialize the state manager
  Future<void> initialize() async {
    if (_isInitialized) return;
    
    _setLoading(true);
    try {
      // Initialize connectivity
      _connectivity = AppConnectivity();
      
      // Load user data
      await _loadUserData();
      
      // Load notifications
      await _loadNotifications();
      
      // Initialize cache
      await _initializeCache();
      
      _isInitialized = true;
      _setError(null);
    } catch (e) {
      _setError('Failed to initialize app: $e');
    } finally {
      _setLoading(false);
    }
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
        );
        _userRoles = _currentUser?.roles ?? [];
        _accessibleFeatures = _getAccessibleFeatures();
      }
    } catch (e) {
      _setError('Failed to load user data: $e');
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
    _currentIndex = index;
    notifyListeners();
  }
  
  void setCurrentRoute(String route) {
    _currentRoute = route;
    notifyListeners();
  }
  
  // Theme management
  void toggleDarkMode() {
    _isDarkMode = !_isDarkMode;
    notifyListeners();
  }
  
  void setLanguage(String language) {
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
      _notifications = List<Map<String, dynamic>>.from(response);
      _unreadNotifications = _notifications.where((n) => !n['is_read']).length;
      notifyListeners();
    } catch (e) {
      // Handle error silently for notifications
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
    } catch (e) {
      _setError('Failed to mark notification as read: $e');
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
    } catch (e) {
      _setError('Failed to mark all notifications as read: $e');
    }
  }
  
  // Cache management
  Future<void> _initializeCache() async {
    _cache = {};
    _lastCacheUpdate = DateTime.now();
  }
  
  void setCache(String key, dynamic value) {
    _cache[key] = value;
    _lastCacheUpdate = DateTime.now();
    notifyListeners();
  }
  
  T? getCache<T>(String key) {
    return _cache[key] as T?;
  }
  
  void clearCache() {
    _cache.clear();
    _lastCacheUpdate = null;
    notifyListeners();
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
    } catch (e) {
      _setError('Failed to refresh data: $e');
    } finally {
      _setLoading(false);
    }
  }
  
  // Error handling
  void _setError(String? error) {
    _error = error;
    notifyListeners();
  }
  
  void clearError() {
    _setError(null);
  }
  
  // Loading state
  void _setLoading(bool loading) {
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
      clearCache();
      notifyListeners();
    } catch (e) {
      _setError('Failed to logout: $e');
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
          callback: (payload) {
            _loadNotifications();
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
