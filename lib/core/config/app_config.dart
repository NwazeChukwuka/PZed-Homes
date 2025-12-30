/// Application Configuration
/// 
/// Centralized configuration for app-wide settings like URLs, feature flags, etc.
/// Update these values to match your production environment.
class AppConfig {
  AppConfig._(); // Private constructor for singleton

  /// Production app URL
  /// 
  /// IMPORTANT: This should match the Site URL in Supabase Dashboard → Authentication → URL Configuration
  /// 
  /// Current production domain: pzedluxuryhotels.com
  static const String productionUrl = 'https://www.pzedluxuryhotels.com';

  /// Password reset redirect URL
  /// 
  /// This is the URL where users will be redirected after clicking the password reset link
  /// Must match the Redirect URLs configured in Supabase Dashboard → Authentication → URL Configuration
  static String get passwordResetUrl => '$productionUrl/auth/reset-password';

  /// Auth callback URL
  /// 
  /// This is the URL where users will be redirected after authentication callbacks
  static String get authCallbackUrl => '$productionUrl/auth/callback';

  /// Check if we're in production mode
  /// 
  /// You can use this to conditionally enable/disable features
  static bool get isProduction => productionUrl.contains('pzedluxuryhotels.com');
}

