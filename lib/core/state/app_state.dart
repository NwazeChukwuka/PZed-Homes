import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';

class AppState extends ChangeNotifier {
  bool _isInitializing = true;
  bool _isLoading = false;
  String? _loadingMessage;

  String? _error;

  bool _isDarkMode = false;
  String _language = 'en';
  double _fontScale = 1.0;

  bool _isOnline = true;
  DateTime? _lastSyncTime;

  bool get isInitializing => _isInitializing;
  bool get isLoading => _isLoading;
  String? get loadingMessage => _loadingMessage;
  String? get error => _error;
  bool get isDarkMode => _isDarkMode;
  String get language => _language;
  double get fontScale => _fontScale;
  bool get isOnline => _isOnline;
  DateTime? get lastSyncTime => _lastSyncTime;

  Future<void> initialize() async {
    if (!_isInitializing) {
      _isInitializing = true;
      notifyListeners();
    }

    try {
      await _loadUserPreferences();
      await _checkNetworkStatus();
      
      if (_isInitializing) {
        _isInitializing = false;
        notifyListeners();
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG initialize: $e\n$stack');
      _setError(ErrorHandler.getFriendlyErrorMessage(e));
      if (_isInitializing) {
        _isInitializing = false;
        notifyListeners();
      }
    }
  }

  void setLoading(bool loading, [String? message]) {
    if (_isLoading == loading && _loadingMessage == message) return;
    _isLoading = loading;
    _loadingMessage = message;
    notifyListeners();
  }

  void _setError(String error) {
    if (_error == error) return;
    _error = error;
    notifyListeners();
  }

  void clearMessages() {
    if (_error == null) return;
    _error = null;
    notifyListeners();
  }

  void toggleTheme() {
    _isDarkMode = !_isDarkMode;
    _saveUserPreferences();
    notifyListeners();
  }

  void setTheme(bool isDark) {
    if (_isDarkMode == isDark) return;
    _isDarkMode = isDark;
    _saveUserPreferences();
    notifyListeners();
  }

  void setLanguage(String language) {
    if (_language == language) return;
    _language = language;
    _saveUserPreferences();
    notifyListeners();
  }

  void setFontScale(double scale) {
    final clamped = scale.clamp(0.8, 1.5);
    if (_fontScale == clamped) return;
    _fontScale = clamped;
    _saveUserPreferences();
    notifyListeners();
  }

  void setOnlineStatus(bool isOnline) {
    if (_isOnline == isOnline) return;
    _isOnline = isOnline;
    if (isOnline) {
      _lastSyncTime = DateTime.now();
    }
    notifyListeners();
  }

  Future<void> _loadUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isDarkMode = prefs.getBool('isDarkMode') ?? false;
      _language = prefs.getString('language') ?? 'en';
      _fontScale = prefs.getDouble('fontScale') ?? 1.0;
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _loadUserPreferences: $e\n$stack');
    }
  }

  Future<void> _saveUserPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('isDarkMode', _isDarkMode);
      await prefs.setString('language', _language);
      await prefs.setDouble('fontScale', _fontScale);
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _saveUserPreferences: $e\n$stack');
    }
  }

  Future<void> _checkNetworkStatus() async {
    _isOnline = true;
  }

}

class PermissionManager {
  static bool canAccess(AppRole userRole, String feature) {
    switch (feature) {
      case 'dashboard':
        return userRole != AppRole.bartender; // Legacy bartender blocked
      
      case 'housekeeping':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.receptionist,
          AppRole.housekeeper,
          AppRole.laundry_attendant,
          AppRole.cleaner,
          AppRole.porter,
        ].contains(userRole);
      
      case 'inventory':
        return [
          AppRole.owner,
          AppRole.manager,
          AppRole.supervisor,
          AppRole.vip_bartender,
          AppRole.outside_bartender,
          AppRole.kitchen_staff,
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
          AppRole.vip_bartender, // VIP bartenders can assist with kitchen sales (closest to kitchen)
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


