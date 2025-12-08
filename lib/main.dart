// Location: lib/main.dart

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
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // For web, skip orientation lock (not needed and blocks startup)
  if (!kIsWeb) {
    await SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
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
  
  // Initialize Supabase in background (non-blocking)
  if (supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty) {
    // Don't await - let it initialize in background
    Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
    ).catchError((e) {
      // Silent fail - app will work without Supabase
      if (kDebugMode) print('Supabase init error: $e');
    });
  }

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
      child: Consumer2<AppState, AppStateManager>(
        builder: (context, appState, stateManager, child) {
          return MaterialApp.router(
            debugShowCheckedModeBanner: false,
            title: 'P-ZED Luxury Hotels & Suites',
            theme: AppTheme.lightTheme,
            darkTheme: AppTheme.darkTheme,
            themeMode: appState.isDarkMode ? ThemeMode.dark : ThemeMode.light,
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
        },
      ),
    );
  }
}
