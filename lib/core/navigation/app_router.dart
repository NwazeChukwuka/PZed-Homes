import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/screens/guest/guest_landing_page.dart';
import 'package:pzed_homes/presentation/screens/login_screen.dart';
import 'package:pzed_homes/presentation/screens/main_screen.dart';
import 'package:pzed_homes/presentation/screens/dashboard_screen.dart';
import 'package:pzed_homes/presentation/screens/staff_dashboard_screen.dart';
import 'package:pzed_homes/presentation/screens/housekeeping_screen.dart';
import 'package:pzed_homes/presentation/screens/inventory_screen.dart';
import 'package:pzed_homes/presentation/screens/communications_screen.dart';
import 'package:pzed_homes/presentation/screens/notifications_screen.dart';
import 'package:pzed_homes/presentation/screens/hr_screen.dart';
import 'package:pzed_homes/presentation/screens/finance_screen.dart';
import 'package:pzed_homes/presentation/screens/kitchen_dispatch_screen.dart';
import 'package:pzed_homes/presentation/screens/daily_stock_count_screen.dart';
import 'package:pzed_homes/presentation/screens/maintenance_screen.dart';
import 'package:pzed_homes/presentation/screens/pos_screen.dart';
import 'package:pzed_homes/presentation/screens/reporting_screen.dart';
import 'package:pzed_homes/presentation/screens/room_details_screen.dart';
import 'package:pzed_homes/presentation/screens/create_booking_screen.dart';
import 'package:pzed_homes/presentation/screens/booking_details_screen.dart';
import 'package:pzed_homes/presentation/screens/user_profile_screen.dart';
import 'package:pzed_homes/presentation/screens/guest/guest_home_screen.dart';
import 'package:pzed_homes/presentation/screens/guest/guest_booking_screen.dart';
import 'package:pzed_homes/presentation/screens/guest/available_rooms_screen.dart';
import 'package:pzed_homes/presentation/screens/guest/guest_booking_lookup_screen.dart';
import 'package:pzed_homes/presentation/screens/guest/about_us_screen.dart';
import 'package:pzed_homes/presentation/screens/guest/services_screen.dart';
import 'package:pzed_homes/presentation/screens/guest/contact_us_screen.dart';
import 'package:pzed_homes/presentation/screens/scanner_screen.dart';
import 'package:pzed_homes/presentation/screens/add_expense_screen.dart';
import 'package:pzed_homes/presentation/screens/purchaser_dashboard_screen.dart';
import 'package:pzed_homes/presentation/screens/storekeeper_dashboard_screen.dart';
import 'package:pzed_homes/presentation/screens/mini_mart_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/presentation/screens/reset_password_screen.dart';

class AppRouter {
  static final _rootNavigatorKey = GlobalKey<NavigatorState>();
  static final _shellNavigatorKey = GlobalKey<NavigatorState>();

  static GoRouter get router => _router;

  // Safe navigation helper methods
  static Future<T?> safePush<T>(BuildContext context, String location, {Object? extra}) async {
    try {
      return await context.push<T>(location, extra: extra);
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Navigation error occurred',
        );
      }
      return null;
    }
  }

  static void safeGo(BuildContext context, String location, {Object? extra}) {
    try {
      context.go(location, extra: extra);
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Navigation error occurred',
        );
      }
    }
  }

  static void safePop<T>(BuildContext context, [T? result]) {
    try {
      context.pop(result);
    } catch (e) {
      if (context.mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Navigation error occurred',
        );
      }
    }
  }

  static final GoRouter _router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: '/',
    debugLogDiagnostics: true,
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(
        title: const Text('Navigation Error'),
        backgroundColor: Colors.red,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.error_outline,
              size: 64,
              color: Colors.red,
            ),
            const SizedBox(height: 16),
            Text(
              'Page not found: ${state.uri}',
              style: const TextStyle(fontSize: 18),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/'),
              child: const Text('Go Home'),
            ),
          ],
        ),
      ),
    ),
    routes: [
      // Root route - decides between guest and staff
      GoRoute(
        path: '/',
        name: 'root',
        builder: (context, state) => const RootDecider(),
      ),
      
      // Guest routes
      GoRoute(
        path: '/guest',
        name: 'guest',
        builder: (context, state) => const GuestLandingPage(),
      ),
      GoRoute(
        path: '/guest/home',
        name: 'guest-home',
        builder: (context, state) => const GuestHomeScreen(),
      ),
      GoRoute(
        path: '/guest/booking',
        name: 'guest-booking',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          if (extra == null) {
            return const GuestLandingPage();
          }
          return const GuestBookingScreen();
        },
      ),
      GoRoute(
        path: '/guest/rooms',
        name: 'guest-rooms',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final checkIn = extra?['checkInDate'] as DateTime? ?? DateTime.now();
          final checkOut = extra?['checkOutDate'] as DateTime? ?? DateTime.now().add(const Duration(days: 1));
          return const AvailableRoomsScreen();
        },
      ),
      GoRoute(
        path: '/guest/booking-lookup',
        name: 'guest-booking-lookup',
        builder: (context, state) => const GuestBookingLookupScreen(),
      ),
      GoRoute(
        path: '/guest/about',
        name: 'guest-about',
        builder: (context, state) => const AboutUsScreen(),
      ),
      GoRoute(
        path: '/guest/services',
        name: 'guest-services',
        builder: (context, state) => const ServicesScreen(),
      ),
      GoRoute(
        path: '/guest/contact',
        name: 'guest-contact',
        builder: (context, state) => const ContactUsScreen(),
      ),

      // Authentication routes
      GoRoute(
        path: '/login',
        name: 'login',
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/auth/reset-password',
        name: 'reset-password',
        builder: (context, state) => const ResetPasswordScreen(),
      ),
      GoRoute(
        path: '/auth/callback',
        name: 'auth-callback',
        builder: (context, state) => const ResetPasswordScreen(),
      ),

      // Staff routes with role-based access
      ShellRoute(
        navigatorKey: _shellNavigatorKey,
        builder: (context, state, child) => MainScreen(child: child),
        routes: [
          GoRoute(
            path: '/dashboard',
            name: 'dashboard',
            builder: (context, state) {
              final authService = Provider.of<AuthService>(context, listen: false);
              final user = authService.currentUser;
              final userRole = authService.isRoleAssumed 
                  ? (authService.assumedRole ?? user?.role) 
                  : user?.role;
              
              // Management roles get the full dashboard
              final isManagement = userRole == AppRole.owner || 
                                   userRole == AppRole.manager || 
                                   userRole == AppRole.supervisor ||
                                   userRole == AppRole.accountant ||
                                   userRole == AppRole.hr;
              
              return isManagement 
                  ? const DashboardScreen() 
                  : const StaffDashboardScreen();
            },
          ),
          GoRoute(
            path: '/housekeeping',
            name: 'housekeeping',
            builder: (context, state) => const HousekeepingScreen(),
          ),
          GoRoute(
            path: '/booking/create',
            name: 'create-booking',
            builder: (context, state) => const CreateBookingScreen(),
          ),
          GoRoute(
            path: '/inventory',
            name: 'inventory',
            builder: (context, state) => const InventoryScreen(),
          ),
          GoRoute(
            path: '/communications',
            name: 'communications',
            builder: (context, state) => const CommunicationsScreen(),
          ),
          GoRoute(
            path: '/notifications',
            name: 'notifications',
            builder: (context, state) => const NotificationsScreen(),
          ),
          GoRoute(
            path: '/hr',
            name: 'hr',
            builder: (context, state) => const HrScreen(),
          ),
          GoRoute(
            path: '/finance',
            name: 'finance',
            builder: (context, state) => const FinanceScreen(),
          ),
          GoRoute(
            path: '/kitchen',
            name: 'kitchen',
            builder: (context, state) => const KitchenDispatchScreen(),
          ),
          GoRoute(
            path: '/stock',
            name: 'stock',
            builder: (context, state) => const DailyStockCountScreen(),
          ),
          GoRoute(
            path: '/maintenance',
            name: 'maintenance',
            builder: (context, state) => const MaintenanceScreen(),
          ),
          GoRoute(
            path: '/pos',
            name: 'pos',
            builder: (context, state) => const PosScreen(),
          ),
          GoRoute(
            path: '/reporting',
            name: 'reporting',
            builder: (context, state) => const ReportingScreen(),
          ),
          GoRoute(
            path: '/purchasing',
            name: 'purchasing',
            builder: (context, state) => const PurchaserDashboardScreen(),
          ),
          GoRoute(
            path: '/storekeeping',
            name: 'storekeeping',
            builder: (context, state) => const StorekeeperDashboardScreen(),
          ),
          GoRoute(
            path: '/mini_mart',
            name: 'mini_mart',
            builder: (context, state) => const MiniMartScreen(),
          ),
        ],
      ),

      // Detail routes (full screen)
      GoRoute(
        path: '/room',
        name: 'room-details',
        builder: (context, state) {
          final extra = state.extra as Map<String, dynamic>?;
          final roomType = extra?['roomType'] as Map<String, dynamic>? ?? {};
          return RoomDetailsScreen(roomType: roomType);
        },
      ),
      GoRoute(
        path: '/booking/details',
        name: 'booking-details',
        builder: (context, state) {
          final booking = state.extra as Booking?;
          if (booking == null) {
            final authService = Provider.of<AuthService>(context, listen: false);
            final user = authService.currentUser;
            final userRole = authService.isRoleAssumed 
                ? (authService.assumedRole ?? user?.role) 
                : user?.role;
            
            final isManagement = userRole == AppRole.owner || 
                                 userRole == AppRole.manager || 
                                 userRole == AppRole.supervisor ||
                                 userRole == AppRole.accountant ||
                                 userRole == AppRole.hr;
            
            return isManagement 
                ? const DashboardScreen() 
                : const StaffDashboardScreen();
          }
          return BookingDetailsScreen(booking: booking);
        },
      ),
      GoRoute(
        path: '/profile',
        name: 'profile',
        builder: (context, state) {
          final userProfile = state.extra as Map<String, dynamic>?;
          
          // If no profile data passed, load current user's profile from database
          if (userProfile == null || userProfile.isEmpty) {
            final authService = Provider.of<AuthService>(context, listen: false);
            final currentUser = authService.currentUser;
            
            if (currentUser != null) {
              // Return a FutureBuilder to load profile from database
              return FutureBuilder<Map<String, dynamic>>(
                future: _loadUserProfile(currentUser.id),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Scaffold(
                      body: Center(child: CircularProgressIndicator()),
                    );
                  }
                  
                  if (snapshot.hasError || !snapshot.hasData) {
                    // Fallback to currentUser data if database query fails
                    return UserProfileScreen(
                      userProfile: {
                        'id': currentUser.id,
                        'full_name': currentUser.name,
                        'email': currentUser.email,
                        'roles': currentUser.roles.map((r) => r.name).toList(),
                        'role': currentUser.role.name,
                        'status': 'Active',
                      },
                    );
                  }
                  
                  return UserProfileScreen(userProfile: snapshot.data!);
                },
              );
            }
          }
          
          return UserProfileScreen(userProfile: userProfile ?? const {});
        },
      ),
      GoRoute(
        path: '/scanner',
        name: 'scanner',
        builder: (context, state) => const ScannerScreen(),
      ),
      GoRoute(
        path: '/expense/add',
        name: 'add-expense',
        builder: (context, state) => const AddExpenseScreen(),
      ),
    ],
    redirect: (context, state) {
      try {
        final authService = Provider.of<AuthService>(context, listen: false);
        
        // If still loading, show loading screen
        if (authService.isLoading) {
          return null;
        }

        final isLoggedIn = authService.isLoggedIn;
        final currentUser = authService.currentUser;
        final location = state.uri.toString();

        // Guest routes - allow access
        if (location.startsWith('/guest') || location == '/') {
          return null;
        }

        // Authentication routes
        if (location == '/login') {
          return null;
        }

        // Staff routes - require authentication
        if (location.startsWith('/dashboard') || 
            location.startsWith('/housekeeping') ||
            location.startsWith('/inventory') ||
            location.startsWith('/communications') ||
            location.startsWith('/hr') ||
            location.startsWith('/finance') ||
            location.startsWith('/kitchen') ||
            location.startsWith('/stock') ||
            location.startsWith('/maintenance') ||
            location.startsWith('/pos') ||
            location.startsWith('/reporting') ||
            location.startsWith('/purchasing') ||
            location.startsWith('/storekeeping') ||
            location.startsWith('/mini_mart') ||
            location.startsWith('/room/') ||
            location.startsWith('/booking/') ||
            location.startsWith('/profile')) {
          
          if (!isLoggedIn) {
            return '/login';
          }

          // Role-based access control
          if (currentUser != null) {
            final userRole = currentUser.role;
            final hasAccess = _hasAccessToRoute(userRole, location);
            
            if (!hasAccess) {
              return '/dashboard'; // Redirect to dashboard if no access
            }
          }
        }

        return null;
      } catch (e) {
        // If there's an error accessing the provider, redirect to login
        return '/login';
      }
    },
  );

  static bool _hasAccessToRoute(AppRole userRole, String location) {
    switch (userRole) {
      case AppRole.owner:
      case AppRole.manager:
        return true; // Full access
      
      case AppRole.receptionist:
        return location.startsWith('/dashboard') ||
               location.startsWith('/communications') ||
               location.startsWith('/housekeeping') ||
               location.startsWith('/mini_mart') ||
               location.startsWith('/kitchen') ||
               location.startsWith('/inventory') ||
               location.startsWith('/stock') ||
               location.startsWith('/booking/') ||
               location.startsWith('/profile');
      
      case AppRole.housekeeper:
        return location.startsWith('/housekeeping') ||
               location.startsWith('/stock') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.kitchen_staff:
        return location.startsWith('/kitchen') ||
               location.startsWith('/stock') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.vip_bartender:
      case AppRole.outside_bartender:
      case AppRole.bartender:
        return location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.security:
        return location.startsWith('/dashboard') ||
               location.startsWith('/maintenance') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.laundry_attendant:
        return location.startsWith('/housekeeping') ||
               location.startsWith('/stock') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.cleaner:
        return location.startsWith('/housekeeping') ||
               location.startsWith('/stock') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
               
      case AppRole.it_admin:
        return true; // IT Admin has full access to all routes
      
      case AppRole.accountant:
        return location.startsWith('/finance') ||
               location.startsWith('/reporting') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.hr:
        return location.startsWith('/hr') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.supervisor:
        return location.startsWith('/dashboard') ||
               location.startsWith('/housekeeping') ||
               location.startsWith('/inventory') ||
               location.startsWith('/finance') ||
               location.startsWith('/reporting') ||
               location.startsWith('/stock') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.purchaser:
        return location.startsWith('/purchasing') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.storekeeper:
        return location.startsWith('/storekeeping') ||
               location.startsWith('/stock') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.guest:
        return false; // Guests don't have staff access
    }
  }
}

/// Helper function to load user profile from database
Future<Map<String, dynamic>> _loadUserProfile(String userId) async {
  try {
    SupabaseClient? supabase;
    try {
      supabase = Supabase.instance.client;
    } catch (_) {
      supabase = null;
    }
    if (supabase == null) return {};
    final response = await supabase
        .from('profiles')
        .select()
        .eq('id', userId)
        .single()
        .timeout(const Duration(seconds: 5));
    
    return Map<String, dynamic>.from(response);
  } catch (e) {
    // Return empty map if query fails - will be handled by fallback
    return {};
  }
}

/// Root decider widget that determines initial route
class RootDecider extends StatelessWidget {
  const RootDecider({super.key});

  @override
  Widget build(BuildContext context) {
    // Check if Supabase is initialized
    // In Supabase Flutter 2.x, accessing instance.client throws if not initialized
    bool isSupabaseInitialized = false;
    String? initError;
    SupabaseClient? supabase;
    try {
      supabase = Supabase.instance.client;
      isSupabaseInitialized = true;
    } catch (e) {
      supabase = null;
      isSupabaseInitialized = false;
      initError = e.toString();
    }
    
    // For guest users, allow the app to work without Supabase (images from assets)
    // Only require Supabase for authenticated features
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        // PRIORITY: Show guest page immediately if not logged in
        // Don't wait for auth check - render first, check auth in background
        // Even if isLoading is true, show guest page (non-blocking)
        if (!authService.isLoggedIn || authService.currentUser == null) {
          return _buildGuestPageWithWarning(isSupabaseInitialized);
        }

        // If user is logged in but still loading user data, show loading with short timeout
        // After 3 seconds, force show dashboard anyway
        if (authService.isLoading) {
          return _LoadingScreenWithTimeout(maxWaitSeconds: 3);
        }

        // For authenticated users, Supabase is required
        if (!isSupabaseInitialized) {
          return _buildConfigErrorScreen(initError);
        }

        // CRITICAL: Only navigate if user is fully loaded (has user data)
        // This prevents showing dashboard without proper initialization
        if (authService.currentUser == null) {
          return _buildGuestPageWithWarning(isSupabaseInitialized);
        }

        // If user is logged in and fully loaded, navigate to dashboard route (which includes MainScreen with sidebar)
        // This ensures the sidebar/drawer is always available
        // Use a post-frame callback with a small delay to ensure ShellRoute is ready
        WidgetsBinding.instance.addPostFrameCallback((_) {
          Future.delayed(const Duration(milliseconds: 100), () {
            if (context.mounted && authService.isLoggedIn && authService.currentUser != null) {
            try {
                // Use go() to navigate to dashboard, which is inside ShellRoute
                // This ensures MainScreen wrapper is applied
              context.go('/dashboard');
            } catch (e) {
              // If navigation fails, show a fallback
              if (kDebugMode) {
                print('Navigation error in RootDecider: $e');
              }
                // Fallback: try navigating to guest page
                if (context.mounted) {
                  context.go('/guest');
                }
            }
          }
          });
        });
        
        // Show a loading screen while navigating
        // This prevents showing the dashboard without sidebar
        return const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
  }

  Widget _buildGuestPageWithWarning(bool isSupabaseInitialized) {
    if (!isSupabaseInitialized) {
      return Stack(
        children: [
          const GuestLandingPage(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: Container(
              color: Colors.orange,
              padding: const EdgeInsets.all(8.0),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.warning, color: Colors.white, size: 16),
                  SizedBox(width: 8),
                  Text(
                    'Supabase not configured - using local assets only',
                    style: TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }
    return const GuestLandingPage();
  }

  Widget _buildConfigErrorScreen([String? error]) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Configuration Error'),
        backgroundColor: Colors.red,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 24),
              const Text(
                'Configuration Required',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Supabase environment variables are not configured.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 16),
              ),
              if (error != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Error Details:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Colors.red,
                        ),
                      ),
                      const SizedBox(height: 8),
                      SelectableText(
                        error,
                        style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'Troubleshooting Steps:',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('1. Check Vercel Environment Variables:', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('   - Go to Vercel Dashboard → Settings → Environment Variables'),
                    Text('   - Ensure variables are named exactly: SUPABASE_URL and SUPABASE_ANON_KEY'),
                    Text('   - Ensure they are enabled for Production environment'),
                    SizedBox(height: 12),
                    Text('2. Check Browser Console (F12):', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('   - Look for "🔍 Supabase Config Check" messages'),
                    Text('   - URL length should be > 0'),
                    Text('   - Key length should be > 0'),
                    SizedBox(height: 12),
                    Text('3. Redeploy after setting variables:', style: TextStyle(fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('   - Variables only apply to NEW deployments'),
                    Text('   - Trigger a new deployment after adding variables'),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue[50],
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue[200]!),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'For local development:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    SelectableText(
                      'flutter run -d edge --dart-define=SUPABASE_URL=your_url --dart-define=SUPABASE_ANON_KEY=your_key',
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Loading screen with timeout to prevent infinite loading
class _LoadingScreenWithTimeout extends StatefulWidget {
  final int maxWaitSeconds;
  const _LoadingScreenWithTimeout({this.maxWaitSeconds = 3});

  @override
  State<_LoadingScreenWithTimeout> createState() => _LoadingScreenWithTimeoutState();
}

class _LoadingScreenWithTimeoutState extends State<_LoadingScreenWithTimeout> {
  bool _showTimeout = false;
  bool _forceShow = false;

  @override
  void initState() {
    super.initState();
    // After maxWaitSeconds, force show dashboard anyway
    Future.delayed(Duration(seconds: widget.maxWaitSeconds), () {
      if (mounted) {
        setState(() {
          _showTimeout = true;
          _forceShow = true;
        });
        // Force navigation to dashboard after timeout
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              final authService = Provider.of<AuthService>(context, listen: false);
              final user = authService.currentUser;
              final userRole = authService.isRoleAssumed 
                  ? (authService.assumedRole ?? user?.role) 
                  : user?.role;
              
              final isManagement = userRole == AppRole.owner || 
                                   userRole == AppRole.manager || 
                                   userRole == AppRole.supervisor ||
                                   userRole == AppRole.accountant ||
                                   userRole == AppRole.hr;
              
              context.go(isManagement ? '/dashboard' : '/dashboard');
            } catch (e) {
              // If navigation fails, just go to guest page
              context.go('/guest');
            }
          }
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            if (_showTimeout) ...[
              const Text(
                'Loading is taking longer than expected...',
                style: TextStyle(color: Colors.orange),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  // Force show guest page
                  context.go('/guest');
                },
                child: const Text('Continue as Guest'),
              ),
            ] else
              const Text('Loading...'),
          ],
        ),
      ),
    );
  }
}
