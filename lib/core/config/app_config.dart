class AppConfig {
  AppConfig._();

  static const String productionUrl = 'https://www.pzedluxuryhotels.com';

  static String get passwordResetUrl => '$productionUrl/auth/reset-password';

  static String get authCallbackUrl => '$productionUrl/auth/callback';

  static bool get isProduction => productionUrl.contains('pzedluxuryhotels.com');
}

