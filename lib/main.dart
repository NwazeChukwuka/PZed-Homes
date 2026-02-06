import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/state/app_state.dart';
import 'package:pzed_homes/core/state/app_state_manager.dart';
import 'package:pzed_homes/core/connectivity/app_connectivity.dart';
import 'package:pzed_homes/core/theme/app_theme.dart';
import 'package:pzed_homes/core/navigation/app_router.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Defer orientation lock - run in background so runApp is not blocked
  if (!kIsWeb) {
    unawaited(SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]));
  }

  // Get Supabase credentials from environment variables
  // Vercel passes these via --dart-define flags in vercel_build.sh
  const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  
  // Only log in debug mode to reduce production overhead
  if (kDebugMode) {
    print('🔍 Supabase Config Check:');
    print('URL length: ${supabaseUrl.length}');
    print('Key length: ${supabaseAnonKey.length}');
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      print('⚠️ Supabase not configured! Please set SUPABASE_URL and SUPABASE_ANON_KEY as environment variables');
    }
  }
  
  // Initialize Supabase before app start
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    try {
      await Supabase.initialize(
        url: supabaseUrl,
        anonKey: supabaseAnonKey,
      );
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG Supabase init: $e\n$stack');
    }
  }

  // Initialize Paystack payment service
  PaymentService().initialize().catchError((e, stack) {
    if (kDebugMode) debugPrint('DEBUG Paystack init: $e\n$stack');
  });

  // Start app immediately - don't wait for Supabase
  runApp(const PzedHomesApp());
}

class PzedHomesApp extends StatelessWidget {
  const PzedHomesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (context) => AuthService()),
        ChangeNotifierProvider(create: (context) => AppState()),
        ChangeNotifierProvider(create: (context) => AppStateManager()),
        ChangeNotifierProvider(create: (context) => AppConnectivity()),
      ],
      child: const _AppStateManagerInitializer(
        child: _ThemedMaterialApp(),
      ),
    );
  }
}

/// Triggers AppStateManager.initialize() once when needed.
/// Does not listen to providers; child rebuilds only from _ThemedMaterialApp.
class _AppStateManagerInitializer extends StatefulWidget {
  final Widget child;

  const _AppStateManagerInitializer({required this.child});

  @override
  State<_AppStateManagerInitializer> createState() =>
      _AppStateManagerInitializerState();
}

class _AppStateManagerInitializerState extends State<_AppStateManagerInitializer> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final stateManager = context.read<AppStateManager>();
      if (!stateManager.isInitialized && !stateManager.isLoading) {
        stateManager.initialize();
      }
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Rebuilds only when theme (isDarkMode) or locale (language) changes.
class _ThemedMaterialApp extends StatelessWidget {
  const _ThemedMaterialApp();

  @override
  Widget build(BuildContext context) {
    final isDarkMode = context.select<AppState, bool>((s) => s.isDarkMode);
    final language = context.select<AppState, String>((s) => s.language);

    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'P-ZED Luxury Hotels & Suites',
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode: isDarkMode ? ThemeMode.dark : ThemeMode.light,
      locale: Locale(language),
      routerConfig: AppRouter.router,
      builder: (context, child) {
        return Stack(
          children: [
            child ?? const SizedBox.shrink(),
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: OfflineBanner(),
            ),
          ],
        );
      },
    );
  }
}
