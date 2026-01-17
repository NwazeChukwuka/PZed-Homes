import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pzed_homes/data/models/user.dart';

/// Global application state management
class AppState extends ChangeNotifier {
  // Loading states
  bool _isInitializing = true;
  bool _isLoading = false;
  String? _loadingMessage;

  // Error handling
  String? _error;
  String? _warning;
  String? _success;

  // User preferences
  bool _isDarkMode = false;
  String _language = 'en';
  double _fontScale = 1.0;

  // Network state
  bool _isOnline = true;
  DateTime? _lastSyncTime;

  // Getters
  bool get isInitializing => _isInitializing;
  bool get isLoading => _isLoading;
  String? get loadingMessage => _loadingMessage;
  String? get error => _error;
  String? get warning => _warning;
  String? get success => _success;
  bool get isDarkMode => _isDarkMode;
  String get language => _language;
  double get fontScale => _fontScale;
  bool get isOnline => _isOnline;
  DateTime? get lastSyncTime => _lastSyncTime;

  // Initialize app state
  Future<void> initialize() async {
    _isInitializing = true;
    notifyListeners();

    try {
      // Load user preferences
      await _loadUserPreferences();
      
      // Check network connectivity
      await _checkNetworkStatus();
      
      _isInitializing = false;
      notifyListeners();
    } catch (e) {
      _setError('Failed to initialize app: $e');
      _isInitializing = false;
      notifyListeners();
    }
  }

  // Loading state management
  void setLoading(bool loading, [String? message]) {
    _isLoading = loading;
    _loadingMessage = message;
    notifyListeners();
  }

  // Error handling
  void _setError(String error) {
    _error = error;
    _warning = null;
    _success = null;
    notifyListeners();
  }

  void _setWarning(String warning) {
    _warning = warning;
    _error = null;
    _success = null;
    notifyListeners();
  }

  void _setSuccess(String success) {
    _success = success;
    _error = null;
    _warning = null;
    notifyListeners();
  }

  void clearMessages() {
    _error = null;
    _warning = null;
    _success = null;
    notifyListeners();
  }

  // Theme management
  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _saveUserPreferences();
    notifyListeners();
  }

  void setTheme(bool isDark) {
    _isDarkMode = isDark;
    _saveUserPreferences();
    notifyListeners();
  }

  // Language management
  void setLanguage(String language) {
    _language = language;
    _saveUserPreferences();
    notifyListeners();
  }

  // Font scale management
  void setFontScale(double scale) {
    _fontScale = scale.clamp(0.8, 1.5);
    _saveUserPreferences();
    notifyListeners();
  }

  // Network state management
  void setOnlineStatus(bool isOnline) {
    _isOnline = isOnline;
    if (isOnline) {
      _lastSyncTime = DateTime.now();
    }
    notifyListeners();
  }

  // User preferences persistence
  Future<void> _loadUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      _language = prefs.getString('language') ?? 'en';
      _fontScale = prefs.getDouble('fontScale') ?? 1.0;
      notifyListeners();
    } catch (e) {
      // If loading fails, use default values
      if (kDebugMode) {
        print('Error loading user preferences: $e');
      }
    }
  }

  Future<void> _saveUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', _isDarkMode);
      await prefs.setString('language', _language);
      await prefs.setDouble('fontScale', _fontScale);
    } catch (e) {
      // If saving fails, log error but don't throw
      if (kDebugMode) {
        print('Error saving user preferences: $e');
      }
    }
  }

  Future<void> _checkNetworkStatus() async {
    // TODO: Implement network connectivity check
    _isOnline = true;
  }

  @override
  void dispose() {
    super.dispose();
  }
}

/// Role-based permissions helper
class PermissionManager {
  static bool canAccess(AppRole userRole, String feature) {
    switch (feature) {
      case 'dashboard':
        return true; // All roles can access dashboard
      
      case 'housekeeping':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.receptionist,
          AppRole.housekeeper,
          AppRole.laundry_attendant,
          AppRole.cleaner,
        ].contains(userRole);
      
      case 'inventory':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.vip_bartender,
          AppRole.outside_bartender,
          AppRole.bartender,
          AppRole.kitchen_staff,
          AppRole.receptionist, // Receptionists can record kitchen/restaurant sales
        ].contains(userRole);
      
      case 'finance':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.accountant,
        ].contains(userRole);
      
      case 'hr':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.hr,
        ].contains(userRole);
      
      case 'kitchen':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.kitchen_staff,
          AppRole.vip_bartender,
          AppRole.outside_bartender,
          AppRole.bartender,
          AppRole.receptionist, // Receptionists can record kitchen/restaurant sales
        ].contains(userRole);
      
      case 'communications':
        return true; // All roles can access communications
      
      case 'maintenance':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.security,
        ].contains(userRole);

      case 'stock':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.storekeeper,
          AppRole.vip_bartender,
          AppRole.outside_bartender,
          AppRole.bartender,
          AppRole.kitchen_staff,
          AppRole.receptionist,
          AppRole.housekeeper,
          AppRole.laundry_attendant,
          AppRole.cleaner,
        ].contains(userRole);
      
      case 'reporting':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.accountant,
        ].contains(userRole);
      
      case 'purchasing':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.purchaser,
        ].contains(userRole);
      
      case 'storekeeping':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.storekeeper,
        ].contains(userRole);
      
      case 'mini_mart':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.receptionist,
        ].contains(userRole);
      
      default:
        return false;
    }
  }

  static List<String> getAccessibleFeatures(AppRole userRole) {
    final features = [
      'dashboard',
      'housekeeping',
      'inventory',
      'finance',
      'hr',
      'kitchen',
      'communications',
      'maintenance',
      'stock',
      'reporting',
      'purchasing',
      'storekeeping',
      'mini_mart',
    ];

    return features.where((feature) => canAccess(userRole, feature)).toList();
  }
}
