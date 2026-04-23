import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
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

bool _supabaseReady = false;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    usePathUrlStrategy();
  }

  if (!kIsWeb) {
    unawaited(SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]));
  }

  const supabaseUrl = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
  const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
  if (kDebugMode) {
    print('Config check:');
    print('URL length: ${supabaseUrl.length}');
    print('Key length: ${supabaseAnonKey.length}');
    if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
      print('⚠️ Backend not configured. Please set required environment variables.');
    }
  }
  unawaited(_initializeSupabaseInBackground(supabaseUrl, supabaseAnonKey));

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
      unawaited(_initializePaymentServiceWhenReady());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

Future<void> _initializeSupabaseInBackground(String supabaseUrl, String supabaseAnonKey) async {
  if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) return;
  try {
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.implicit,
      ),
    ).timeout(
      const Duration(seconds: 10),
      onTimeout: () => throw TimeoutException('Supabase initialization timed out'),
    );
    _supabaseReady = true;
  } on TimeoutException catch (e, stack) {
    if (kDebugMode) debugPrint('DEBUG Supabase init timeout: $e\n$stack');
  } catch (e, stack) {
    if (kDebugMode) debugPrint('DEBUG Supabase init: $e\n$stack');
  }
}

Future<void> _initializePaymentServiceWhenReady() async {
  for (var i = 0; i < 20; i++) {
    if (_supabaseReady) {
      try {
        await PaymentService().initialize();
      } catch (e, stack) {
        if (kDebugMode) debugPrint('DEBUG PaymentService init: $e\n$stack');
      }
      return;
    }
    await Future.delayed(const Duration(milliseconds: 300));
  }
}

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
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: RepaintBoundary(child: const OfflineBanner()),
            ),
          ],
        );
      },
    );
  }
}
