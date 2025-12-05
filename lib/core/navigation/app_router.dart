// Location: lib/core/navigation/app_router.dart

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
import 'package:pzed_homes/presentation/screens/guest/about_us_screen.dart';
import 'package:pzed_homes/presentation/screens/guest/services_screen.dart';
import 'package:pzed_homes/presentation/screens/guest/contact_us_screen.dart';
import 'package:pzed_homes/presentation/screens/scanner_screen.dart';
import 'package:pzed_homes/presentation/screens/add_expense_screen.dart';
import 'package:pzed_homes/presentation/screens/purchaser_dashboard_screen.dart';
import 'package:pzed_homes/presentation/screens/storekeeper_dashboard_screen.dart';
import 'package:pzed_homes/presentation/screens/mini_mart_screen.dart';

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
        path: '/booking/create',
        name: 'create-booking',
        builder: (context, state) => const CreateBookingScreen(),
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
               location.startsWith('/booking/') ||
               location.startsWith('/profile');
      
      case AppRole.housekeeper:
        return location.startsWith('/housekeeping') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.kitchen_staff:
        return location.startsWith('/kitchen') ||
               location.startsWith('/stock') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.bartender:
        return location.startsWith('/kitchen') ||
               location.startsWith('/inventory') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.security:
        return location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.laundry_attendant:
        return location.startsWith('/housekeeping') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.cleaner:
        return location.startsWith('/housekeeping') ||
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
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.purchaser:
        return location.startsWith('/purchasing') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.storekeeper:
        return location.startsWith('/storekeeping') ||
               location.startsWith('/communications') ||
               location.startsWith('/profile');
      
      case AppRole.guest:
        return false; // Guests don't have staff access
    }
  }
}

/// Root decider widget that determines initial route
class RootDecider extends StatelessWidget {
  const RootDecider({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<AuthService>(
      builder: (context, authService, child) {
        // If still loading user info
        if (authService.isLoading) {
          return const Scaffold(
            body: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Loading...'),
                ],
              ),
            ),
          );
        }

        // If user is not logged in, show guest landing page
        if (!authService.isLoggedIn) {
          return const GuestLandingPage();
        }

        // If user is logged in, show appropriate dashboard
        // This prevents navigation conflicts with login screen
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
      },
    );
  }
}
