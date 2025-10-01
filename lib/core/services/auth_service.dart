import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService with ChangeNotifier {
  final _supabase = Supabase.instance.client;
  AppUser? _currentUser;
  bool _isLoading = true; // Added
  bool _isLoggedIn = false; // Added
  StreamSubscription<AuthState>? _authStateSubscription;

  AppUser? get currentUser => _currentUser;
  AppRole? get userRole => _currentUser?.role;

  bool get isLoading => _isLoading; // Added
  bool get isLoggedIn => _isLoggedIn; // Added

  AuthService() {
    // Listen to auth state changes
    _authStateSubscription = _supabase.auth.onAuthStateChange.listen((data) async {
      _isLoading = true;
      notifyListeners();

      final session = data.session;
      if (session != null) {
        await _onUserLoggedIn(session.user);
        _isLoggedIn = true;
      } else {
        _currentUser = null;
        _isLoggedIn = false;
      }

      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> _onUserLoggedIn(User user) async {
    try {
      final response = await _supabase
          .from('profiles')
          .select()
          .eq('id', user.id)
          .single();

      if (response != null) {
        // Handle roles as array - get the first role for now
        final roles = (response['roles'] as List<dynamic>? ?? []);
        final primaryRole = roles.isNotEmpty 
            ? AppRole.values.byName(roles.first as String)
            : AppRole.guest;
        
        _currentUser = AppUser(
          id: response['id'],
          name: response['full_name'],
          email: response['email'] ?? '',
          role: primaryRole,
          roles: roles.map((role) => AppRole.values.byName(role as String)).toList(),
        );
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
    required AppRole role,
  }) async {
    try {
      await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': fullName,
          'roles': [role.name], // Send roles as array
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
    await _supabase.auth.signOut();
    _currentUser = null;
    _isLoggedIn = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }
}
