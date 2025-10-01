// Location: lib/presentation/screens/main_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/core/state/app_state.dart';
import 'package:pzed_homes/core/layout/responsive_layout.dart';
import 'package:pzed_homes/core/animations/app_animations.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/screens/purchaser_dashboard_screen.dart';
import 'package:pzed_homes/presentation/screens/storekeeper_dashboard_screen.dart';
import 'package:pzed_homes/presentation/screens/mini_mart_screen.dart';

class MainScreen extends StatelessWidget {
  final Widget child;
  
  const MainScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer2<MockAuthService, AppState>(
      builder: (context, authService, appState, _) {
        final user = authService.currentUser;
        final userRoles = user?.roles ?? [AppRole.guest];

        // Merge: Instead of just one role, collect accessible features for ALL roles
        final accessibleFeatures = <String>{};
        for (var role in userRoles) {
          accessibleFeatures.addAll(PermissionManager.getAccessibleFeatures(role));
        }

        return ResponsiveLayout(
          mobile: _buildMobileLayout(context, userRoles, accessibleFeatures.toList()),
          tablet: _buildTabletLayout(context, userRoles, accessibleFeatures.toList()),
          desktop: _buildDesktopLayout(context, userRoles, accessibleFeatures.toList()),
          largeDesktop: _buildLargeDesktopLayout(context, userRoles, accessibleFeatures.toList()),
        );
      },
    );
  }

  Widget _buildMobileLayout(BuildContext context, List<AppRole> userRoles, List<String> accessibleFeatures) {
    return Scaffold(
      appBar: AppBar(
        title: AppAnimations.slideInFromBottom(
          child: Row(
            children: [
              AppAnimations.bounce(
                child: Image.asset(
                  'assets/images/PZED logo.png',
                  height: 32,
                  width: 32,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 12),
              const Text('P-ZED Homes'),
            ],
          ),
        ),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => context.push('/profile'),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _showLogoutDialog(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: AppAnimations.fadeTransition(
        child: child,
        animation: AlwaysStoppedAnimation(1.0),
      ),
      drawer: _buildMobileDrawer(context, userRoles, accessibleFeatures),
    );
  }

  Widget _buildTabletLayout(BuildContext context, List<AppRole> userRoles, List<String> accessibleFeatures) {
    return Scaffold(
      appBar: AppBar(
        title: AppAnimations.slideInFromBottom(
          child: Row(
            children: [
              AppAnimations.bounce(
                child: Image.asset(
                  'assets/images/PZED logo.png',
                  height: 36,
                  width: 36,
                  fit: BoxFit.contain,
                ),
              ),
              const SizedBox(width: 16),
              const Text('P-ZED Homes'),
            ],
          ),
        ),
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => context.push('/profile'),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _showLogoutDialog(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      drawer: _buildTabletDrawer(context, userRoles, accessibleFeatures),
      body: AppAnimations.fadeTransition(
        child: child,
        animation: AlwaysStoppedAnimation(1.0),
      ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, List<AppRole> userRoles, List<String> accessibleFeatures) {
    return Scaffold(
      body: AppAnimations.fadeTransition(
        child: Row(
          children: [
            AppAnimations.slideTransition(
              child: _buildDesktopSidebar(context, userRoles, accessibleFeatures),
              animation: AlwaysStoppedAnimation(1.0),
              direction: SlideDirection.left,
            ),
            Expanded(
              child: Column(
                children: [
                  AppAnimations.slideInFromBottom(
                    child: _buildDesktopAppBar(context),
                  ),
                  Expanded(
                    child: AppAnimations.fadeTransition(
                      child: child,
                      animation: AlwaysStoppedAnimation(1.0),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        animation: AlwaysStoppedAnimation(1.0),
      ),
    );
  }

  Widget _buildLargeDesktopLayout(BuildContext context, List<AppRole> userRoles, List<String> accessibleFeatures) {
    return Scaffold(
      body: AppAnimations.fadeTransition(
        child: Row(
          children: [
            AppAnimations.slideTransition(
              child: _buildLargeDesktopSidebar(context, userRoles, accessibleFeatures),
              animation: AlwaysStoppedAnimation(1.0),
              direction: SlideDirection.left,
            ),
            Expanded(
              child: Column(
                children: [
                  AppAnimations.slideInFromBottom(
                    child: _buildLargeDesktopAppBar(context),
                  ),
                  Expanded(
                    child: AppAnimations.fadeTransition(
                      child: child,
                      animation: AlwaysStoppedAnimation(1.0),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        animation: AlwaysStoppedAnimation(1.0),
      ),
    );
  }

  Widget _buildDesktopSidebar(BuildContext context, List<AppRole> userRoles, List<String> accessibleFeatures) {
    return Container(
      width: 280,
      decoration: BoxDecoration(
        color: Colors.green[800],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildSidebarHeader(context),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: _getNavItemsForRoles(userRoles, accessibleFeatures)
                  .map((item) => _buildSidebarNavItem(context, item))
                  .toList(),
            ),
          ),
          _buildSidebarFooter(context),
        ],
      ),
    );
  }

  Widget _buildSidebarHeader(BuildContext context) {
    return Consumer<MockAuthService>(
      builder: (context, authService, _) {
        final user = authService.currentUser;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.green[900],
            border: Border(
              bottom: BorderSide(color: Colors.green[700]!, width: 1),
            ),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.amber[600],
                child: Text(
                  user?.name.substring(0, 1).toUpperCase() ?? 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user?.name ?? 'Unknown User',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                (user?.roles.map((r) => r.name.toUpperCase()).join(', ')) ?? 'GUEST',
                style: TextStyle(
                  color: Colors.green[200],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSidebarNavItem(BuildContext context, NavigationItem item) {
    final isSelected = _isCurrentRoute(context, item.route);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? Colors.amber[600] : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: isSelected ? Colors.white : Colors.green[200],
          size: 20,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.green[200],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 14,
          ),
        ),
        onTap: () => _navigateToRoute(context, item.route),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildSidebarFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.green[700]!, width: 1),
        ),
      ),
      child: ListTile(
        leading: Icon(Icons.logout, color: Colors.red[300]),
        title: Text(
          'Logout',
          style: TextStyle(color: Colors.red[300]),
        ),
        onTap: () => _showLogoutDialog(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildDesktopAppBar(BuildContext context) {
    return Container(
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 24),
          Row(
            children: [
              Image.asset(
                'assets/images/PZED logo.png',
                height: 40,
                width: 40,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 16),
              Text(
                'P-ZED Homes Management System',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.green[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              // Handle notifications
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () {
              // Handle settings
            },
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  Widget _buildMobileDrawer(BuildContext context, List<AppRole> userRoles, List<String> accessibleFeatures) {
    return Drawer(
      child: AppAnimations.fadeTransition(
        child: Column(
          children: [
            AppAnimations.slideInFromBottom(
              child: _buildMobileDrawerHeader(context),
            ),
            Expanded(
              child: AppAnimations.staggeredList(
                children: _getNavItemsForRoles(userRoles, accessibleFeatures)
                    .map((item) => _buildMobileDrawerItem(context, item))
                    .toList(),
              ),
            ),
            AppAnimations.slideInFromBottom(
              child: _buildMobileDrawerFooter(context),
            ),
          ],
        ),
        animation: AlwaysStoppedAnimation(1.0),
      ),
    );
  }

  Widget _buildTabletDrawer(BuildContext context, List<AppRole> userRoles, List<String> accessibleFeatures) {
    return Drawer(
      width: 320, // Wider for tablet
      child: AppAnimations.fadeTransition(
        child: Column(
          children: [
            AppAnimations.slideInFromBottom(
              child: _buildTabletDrawerHeader(context),
            ),
            Expanded(
              child: AppAnimations.staggeredList(
                children: _getNavItemsForRoles(userRoles, accessibleFeatures)
                    .map((item) => _buildTabletDrawerItem(context, item))
                    .toList(),
              ),
            ),
            AppAnimations.slideInFromBottom(
              child: _buildTabletDrawerFooter(context),
            ),
          ],
        ),
        animation: AlwaysStoppedAnimation(1.0),
      ),
    );
  }

  Widget _buildMobileDrawerHeader(BuildContext context) {
    return Consumer<MockAuthService>(
      builder: (context, authService, _) {
        final user = authService.currentUser;
        return DrawerHeader(
          decoration: BoxDecoration(
            color: Colors.green[800],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.amber[600],
                child: Text(
                  user?.name.substring(0, 1).toUpperCase() ?? 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                user?.name ?? 'Unknown User',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                (user?.roles.map((r) => r.name.toUpperCase()).join(', ')) ?? 'GUEST',
                style: TextStyle(
                  color: Colors.green[200],
                  fontSize: 14,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMobileDrawerItem(BuildContext context, NavigationItem item) {
    final isSelected = _isCurrentRoute(context, item.route);
    
    return ListTile(
      leading: Icon(
        item.icon,
        color: isSelected ? Colors.green[800] : Colors.grey[600],
      ),
      title: Text(
        item.label,
        style: TextStyle(
          color: isSelected ? Colors.green[800] : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      onTap: () {
        Navigator.of(context).pop(); // Close drawer
        _navigateToRoute(context, item.route);
      },
    );
  }

  Widget _buildMobileDrawerFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.red),
        title: const Text('Logout'),
        onTap: () {
          Navigator.of(context).pop(); // Close drawer
          _showLogoutDialog(context);
        },
      ),
    );
  }

  List<NavigationItem> _getNavItemsForRoles(List<AppRole> userRoles, List<String> accessibleFeatures) {
    final items = <NavigationItem>[];

    if (accessibleFeatures.contains('dashboard')) {
      items.add(NavigationItem(icon: Icons.dashboard, label: 'Dashboard', route: '/dashboard'));
    }
    if (accessibleFeatures.contains('housekeeping')) {
      items.add(NavigationItem(icon: Icons.room_service, label: 'Housekeeping', route: '/housekeeping'));
    }
    if (accessibleFeatures.contains('inventory')) {
      items.add(NavigationItem(icon: Icons.inventory, label: 'Inventory', route: '/inventory'));
    }
    if (accessibleFeatures.contains('kitchen')) {
      items.add(NavigationItem(icon: Icons.restaurant, label: 'Kitchen', route: '/kitchen'));
    }
    if (accessibleFeatures.contains('finance')) {
      items.add(NavigationItem(icon: Icons.account_balance, label: 'Finance', route: '/finance'));
    }
    if (accessibleFeatures.contains('hr')) {
      items.add(NavigationItem(icon: Icons.people, label: 'HR', route: '/hr'));
    }
    if (accessibleFeatures.contains('communications')) {
      items.add(NavigationItem(icon: Icons.announcement, label: 'Communications', route: '/communications'));
    }
    if (accessibleFeatures.contains('maintenance')) {
      items.add(NavigationItem(icon: Icons.build, label: 'Maintenance', route: '/maintenance'));
    }
    if (accessibleFeatures.contains('reporting')) {
      items.add(NavigationItem(icon: Icons.analytics, label: 'Reporting', route: '/reporting'));
    }
    if (accessibleFeatures.contains('purchasing')) {
      items.add(NavigationItem(icon: Icons.shopping_cart, label: 'Purchasing', route: '/purchasing'));
    }
    if (accessibleFeatures.contains('storekeeping')) {
      items.add(NavigationItem(icon: Icons.store, label: 'Storekeeping', route: '/storekeeping'));
    }
    if (accessibleFeatures.contains('mini_mart')) {
      items.add(NavigationItem(icon: Icons.storefront, label: 'Mini Mart', route: '/mini_mart'));
    }

    return items;
  }

  bool _isCurrentRoute(BuildContext context, String route) {
    final currentLocation = GoRouterState.of(context).uri.toString();
    return currentLocation == route;
  }

  void _navigateToRoute(BuildContext context, String route) {
    context.go(route);
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => context.pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              try {
                // Close dialog first
                context.pop();
                
                // Logout and navigate safely
                await Provider.of<MockAuthService>(context, listen: false).logout();
                
                // Navigate to home after a brief delay
                Future.delayed(const Duration(milliseconds: 100), () {
                  if (context.mounted) {
                    context.go('/');
                  }
                });
              } catch (e) {
                print('DEBUG: Logout navigation error: $e');
              }
            },
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  // Tablet drawer methods
  Widget _buildTabletDrawerHeader(BuildContext context) {
    return Consumer<MockAuthService>(
      builder: (context, authService, _) {
        final user = authService.currentUser;
        return DrawerHeader(
          decoration: BoxDecoration(
            color: Colors.green[800],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.amber[600],
                    child: Text(
                      user?.name.substring(0, 1).toUpperCase() ?? 'U',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.name ?? 'User',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          user?.email ?? 'user@example.com',
                          style: TextStyle(
                            color: Colors.green[200],
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildTabletDrawerItem(BuildContext context, NavigationItem item) {
    final isSelected = _isCurrentRoute(context, item.route);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: isSelected ? Colors.amber[600] : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: isSelected ? Colors.white : Colors.grey[600],
          size: 24,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 16,
          ),
        ),
        onTap: () {
          Navigator.of(context).pop(); // Close drawer
          context.go(item.route);
        },
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildTabletDrawerFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.grey[300]!),
        ),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.red),
        title: const Text('Logout'),
        onTap: () {
          Navigator.of(context).pop(); // Close drawer
          _showLogoutDialog(context);
        },
      ),
    );
  }

  // Large desktop sidebar methods
  Widget _buildLargeDesktopSidebar(BuildContext context, List<AppRole> userRoles, List<String> accessibleFeatures) {
    return Container(
      width: 320, // Wider for large desktop
      decoration: BoxDecoration(
        color: Colors.green[800],
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(2, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          _buildLargeDesktopSidebarHeader(context),
          Expanded(
            child: AppAnimations.staggeredList(
              children: _getNavItemsForRoles(userRoles, accessibleFeatures)
                  .map((item) => _buildLargeDesktopSidebarItem(context, item))
                  .toList(),
            ),
          ),
          _buildLargeDesktopSidebarFooter(context),
        ],
      ),
    );
  }

  Widget _buildLargeDesktopSidebarHeader(BuildContext context) {
    return Consumer<MockAuthService>(
      builder: (context, authService, _) {
        final user = authService.currentUser;
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Colors.green[700]!, width: 1),
            ),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 32,
                backgroundColor: Colors.amber[600],
                child: Text(
                  user?.name.substring(0, 1).toUpperCase() ?? 'U',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                user?.name ?? 'User',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                user?.email ?? 'user@example.com',
                style: TextStyle(
                  color: Colors.green[200],
                  fontSize: 14,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLargeDesktopSidebarItem(BuildContext context, NavigationItem item) {
    final isSelected = _isCurrentRoute(context, item.route);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: isSelected ? Colors.amber[600] : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        leading: Icon(
          item.icon,
          color: isSelected ? Colors.white : Colors.green[200],
          size: 24,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.green[200],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: 16,
          ),
        ),
        onTap: () => context.go(item.route),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
    );
  }

  Widget _buildLargeDesktopSidebarFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: Colors.green[700]!, width: 1),
        ),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.red),
        title: const Text('Logout'),
        onTap: () => _showLogoutDialog(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }

  Widget _buildLargeDesktopAppBar(BuildContext context) {
    return Container(
      height: 80, // Taller for large desktop
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const SizedBox(width: 32),
          Row(
            children: [
              Image.asset(
                'assets/images/PZED logo.png',
                height: 48,
                width: 48,
                fit: BoxFit.contain,
              ),
              const SizedBox(width: 20),
              Text(
                'P-ZED Homes Management System',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.green[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () {
              // Handle notifications
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => context.push('/profile'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _showLogoutDialog(context);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout),
                    SizedBox(width: 8),
                    Text('Logout'),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 32),
        ],
      ),
    );
  }
}

class NavigationItem {
  final IconData icon;
  final String label;
  final String route;

  NavigationItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}