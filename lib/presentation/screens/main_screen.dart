import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/state/app_state.dart';
import 'package:pzed_homes/core/layout/responsive_layout.dart';
import 'package:pzed_homes/core/animations/app_animations.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/screens/purchaser_dashboard_screen.dart';
import 'package:pzed_homes/presentation/screens/storekeeper_dashboard_screen.dart';
import 'package:pzed_homes/presentation/screens/mini_mart_screen.dart';

class MainScreen extends StatelessWidget {
  final Widget child;
  
  const MainScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return Consumer2<AuthService, AppState>(
      builder: (context, authService, appState, _) {
        final user = authService.currentUser;
        final userRoles = user?.roles ?? [AppRole.guest];

        // Merge: Instead of just one role, collect accessible features for ALL roles
        // PLUS add features from assumed role (additive, not restrictive)
        final accessibleFeatures = <String>{};
        for (var role in userRoles) {
          accessibleFeatures.addAll(PermissionManager.getAccessibleFeatures(role));
        }
        
        // If role is assumed, ADD those features (don't replace)
        if (authService.isRoleAssumed && authService.assumedRole != null) {
          accessibleFeatures.addAll(PermissionManager.getAccessibleFeatures(authService.assumedRole!));
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
              const Text('P-ZED Luxury Hotels & Suites'),
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
              const Text('P-ZED Luxury Hotels & Suites'),
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
              children: _getNavItemsForRoles(context, userRoles, accessibleFeatures)
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
    return Consumer<AuthService>(
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
                'P-ZED Luxury Hotels & Suites Management System',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.green[800],
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          Consumer<AuthService>(
            builder: (context, authService, child) {
              final currentUser = authService.currentUser;
              final isOwnerOrManager = currentUser?.role == AppRole.owner || currentUser?.role == AppRole.manager;
              if (!isOwnerOrManager) return const SizedBox.shrink();

              // Get suggested role based on current route
              final currentRoute = GoRouterState.of(context).uri.toString();
              final suggestedRole = AuthService.getSuggestedRoleForRoute(currentRoute);
              final buttonLabel = suggestedRole != null 
                  ? 'Assume ${AuthService.getRoleDisplayName(suggestedRole)}'
                  : 'Assume Role';

              return Row(
                children: [
                  if (authService.isRoleAssumed)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [Colors.orange.shade400, Colors.orange.shade600]),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(color: Colors.orange.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2)),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.swap_horiz, color: Colors.white, size: 16),
                          const SizedBox(width: 6),
                          Text(
                            AuthService.getRoleDisplayName(authService.assumedRole!),
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
                          ),
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => authService.returnToOriginalRole(),
                            child: const Icon(Icons.close, color: Colors.white, size: 14),
                          ),
                        ],
                      ),
                    ),
                  if (authService.isRoleAssumed) const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed: () => suggestedRole != null 
                        ? _assumeSpecificRole(context, suggestedRole)
                        : _showAssumeRoleSheet(context),
                    icon: const Icon(Icons.person_outline, size: 18),
                    label: Text(buttonLabel),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: suggestedRole != null ? Colors.orange[700] : Colors.green[800],
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      textStyle: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              );
            },
          ),
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
              // Navigate to user profile screen (settings)
              context.push('/profile');
            },
          ),
          const SizedBox(width: 24),
        ],
      ),
    );
  }

  void _assumeSpecificRole(BuildContext context, AppRole role) {
    final authService = Provider.of<AuthService>(context, listen: false);
    authService.assumeRole(role);
    if (context.mounted) {
      ErrorHandler.showInfoMessage(
        context,
        'Now assuming ${AuthService.getRoleDisplayName(role)} role',
        duration: const Duration(seconds: 2),
      );
    }
  }

  void _showAssumeRoleSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        final authService = Provider.of<AuthService>(context, listen: false);
        final roles = <Map<String, dynamic>>[
          {'label': 'Bartender', 'role': AppRole.bartender, 'icon': Icons.local_bar, 'color': Colors.purple},
          {'label': 'Receptionist', 'role': AppRole.receptionist, 'icon': Icons.support_agent, 'color': Colors.indigo},
          {'label': 'Storekeeper', 'role': AppRole.storekeeper, 'icon': Icons.inventory_2, 'color': Colors.teal},
          {'label': 'Purchaser', 'role': AppRole.purchaser, 'icon': Icons.shopping_cart, 'color': Colors.blue},
          {'label': 'Accountant', 'role': AppRole.accountant, 'icon': Icons.calculate, 'color': Colors.green},
          {'label': 'Kitchen Staff', 'role': AppRole.kitchen_staff, 'icon': Icons.restaurant, 'color': Colors.orange},
        ];

        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.5,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          builder: (context, scrollController) => Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.swap_horiz),
                    const SizedBox(width: 8),
                    const Text('Assume a Role', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const Spacer(),
                    if (authService.isRoleAssumed)
                      TextButton.icon(
                        onPressed: () {
                          authService.returnToOriginalRole();
                          Navigator.pop(context);
                        },
                        icon: const Icon(Icons.undo),
                        label: const Text('Return'),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: GridView.builder(
                    controller: scrollController,
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: 1.1,
                    ),
                    itemCount: roles.length,
                    itemBuilder: (context, i) {
                      final r = roles[i];
                      final Color base = r['color'] as Color;
                      final bool selected = authService.isRoleAssumed && authService.assumedRole == r['role'];
                      return InkWell(
                        onTap: () {
                          authService.assumeRole(r['role'] as AppRole);
                          Navigator.pop(context);
                          if (context.mounted) {
                            ErrorHandler.showInfoMessage(
                              context,
                              'Now assuming ${r['label']}',
                            );
                          }
                        },
                        borderRadius: BorderRadius.circular(14),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              colors: [base.withOpacity(0.15), base.withOpacity(0.35)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(color: selected ? base : base.withOpacity(0.3), width: selected ? 2 : 1),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 22,
                                backgroundColor: base.withOpacity(0.2),
                                child: Icon(r['icon'] as IconData, color: base),
                              ),
                              const SizedBox(height: 10),
                              Text(
                                r['label'] as String,
                                textAlign: TextAlign.center,
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
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
                children: _getNavItemsForRoles(context, userRoles, accessibleFeatures)
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
                children: _getNavItemsForRoles(context, userRoles, accessibleFeatures)
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
    return Consumer<AuthService>(
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

  List<NavigationItem> _getNavItemsForRoles(BuildContext context, List<AppRole> userRoles, List<String> accessibleFeatures) {
    final items = <NavigationItem>[];

    if (accessibleFeatures.contains('dashboard')) {
      items.add(NavigationItem(icon: Icons.dashboard, label: 'Dashboard', route: '/dashboard'));
    }
    
    // Add booking form for receptionist only (not owner/manager unless they assume receptionist role)
    final authService = Provider.of<AuthService>(context, listen: false);
    final isReceptionist = userRoles.contains(AppRole.receptionist) || 
        (authService.isRoleAssumed && authService.assumedRole == AppRole.receptionist);
    if (isReceptionist) {
      items.add(NavigationItem(icon: Icons.book_online, label: 'Create Booking', route: '/booking/create'));
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
                await Provider.of<AuthService>(context, listen: false).logout();
                
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
    return Consumer<AuthService>(
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
              children: _getNavItemsForRoles(context, userRoles, accessibleFeatures)
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
    return Consumer<AuthService>(
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
                'P-ZED Luxury Hotels & Suites Management System',
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