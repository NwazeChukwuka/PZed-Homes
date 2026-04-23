import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

abstract final class GuestPortalTheme {
  static const Color gold = Color(0xFFFFD54F);
  static const Color goldBright = Color(0xFFFFE082);
  static const Color goldDeep = Color(0xFFC9A227);
  static const Color deepGreen = Color(0xFF0D2818);
  static const Color forestGreen = Color(0xFF1B4332);
  static const Color leafGreen = Color(0xFF2D6A4F);

  static const LinearGradient headerGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF0A2418),
      Color(0xFF0F3D2E),
      Color(0xFF1B5E3A),
      Color(0xFF2E6B45),
      Color(0x664A3728),
    ],
    stops: [0.0, 0.35, 0.62, 0.88, 1.0],
  );

  static const double headerGoldBorderWidth = 2;

  static List<BoxShadow> goldLeafShadows({double blur = 22, double dy = 8}) => [
        BoxShadow(
          color: gold.withValues(alpha: 0.18),
          blurRadius: blur,
          offset: Offset(0, dy),
          spreadRadius: 0,
        ),
        BoxShadow(
          color: goldBright.withValues(alpha: 0.08),
          blurRadius: blur * 1.4,
          offset: Offset(0, dy * 0.5),
        ),
      ];

  static SystemUiOverlayStyle get headerOverlayStyle => const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      );
}

class GuestScaffold extends StatelessWidget {
  final Widget child;

  const GuestScaffold({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    final guestChrome = base.copyWith(
      appBarTheme: base.appBarTheme.copyWith(
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: GuestPortalTheme.headerOverlayStyle,
      ),
    );

    if (child is Scaffold) {
      return Theme(data: guestChrome, child: child);
    }
    return Theme(
      data: guestChrome,
      child: Scaffold(body: child),
    );
  }
}


