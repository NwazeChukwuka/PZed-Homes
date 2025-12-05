// Location: lib/main.dart

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

  // Set preferred orientations
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Initialize Supabase for production
  // Set these environment variables or replace with your actual credentials
  const supabaseUrl = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: 'https://idhebncfhiclruvqvmxb.supabase.co',
  );
  const supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImlkaGVibmNmaGljbHJ1dnF2bXhiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTc4ODYwMjIsImV4cCI6MjA3MzQ2MjAyMn0.khoiul_d7MLLlRJXA6duaxuyrmzPAx42qxudb7DpWQY',
  );

  await Supabase.initialize(
    url: supabaseUrl,
    anonKey: supabaseAnonKey,
  );

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
