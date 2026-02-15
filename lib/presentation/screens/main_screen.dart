import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/state/app_state.dart';
import 'package:pzed_homes/core/layout/responsive_layout.dart';
import 'package:pzed_homes/core/state/app_state_manager.dart';
import 'package:pzed_homes/core/animations/app_animations.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/performance/optimization_helpers.dart';
import 'package:pzed_homes/data/models/user.dart';

List<NavigationItem> _computeNavItems(AuthService auth) {
  final user = auth.currentUser;
  final userRoles = user?.roles ?? [AppRole.guest];
  final accessibleFeatures = <String>{};
  for (var role in userRoles) {
    accessibleFeatures.addAll(PermissionManager.getAccessibleFeatures(role));
  }
  for (final role in auth.activeAssumedRoles) {
    accessibleFeatures.addAll(PermissionManager.getAccessibleFeatures(role));
  }
  final featuresList = accessibleFeatures.toList();
  final isReceptionist = userRoles.contains(AppRole.receptionist) ||
      auth.hasAssumedRole(AppRole.receptionist);

  final items = <NavigationItem>[];
  if (featuresList.contains('dashboard')) {
    items.add(NavigationItem(icon: Icons.dashboard, label: 'Dashboard', route: '/dashboard'));
  }
  if (isReceptionist) {
    items.add(NavigationItem(icon: Icons.book_online, label: 'Create Booking', route: '/booking/create'));
  }
  if (featuresList.contains('housekeeping')) {
    items.add(NavigationItem(icon: Icons.room_service, label: 'Housekeeping', route: '/housekeeping'));
  }
  if (featuresList.contains('inventory')) {
    items.add(NavigationItem(icon: Icons.inventory, label: 'Inventory', route: '/inventory'));
  }
  if (featuresList.contains('kitchen')) {
    items.add(NavigationItem(icon: Icons.restaurant, label: 'Kitchen', route: '/kitchen'));
  }
  if (featuresList.contains('finance')) {
    items.add(NavigationItem(icon: Icons.account_balance, label: 'Finance', route: '/finance'));
  }
  if (featuresList.contains('hr')) {
    items.add(NavigationItem(icon: Icons.people, label: 'HR', route: '/hr'));
  }
  if (featuresList.contains('communications')) {
    items.add(NavigationItem(icon: Icons.announcement, label: 'Communications', route: '/communications'));
  }
  if (featuresList.contains('maintenance')) {
    items.add(NavigationItem(icon: Icons.build, label: 'Maintenance', route: '/maintenance'));
  }
  if (featuresList.contains('stock')) {
    items.add(NavigationItem(icon: Icons.inventory_2, label: 'Daily Stock Count', route: '/stock'));
  }
  if (featuresList.contains('reporting')) {
    items.add(NavigationItem(icon: Icons.analytics, label: 'Reporting', route: '/reporting'));
  }
  if (featuresList.contains('purchasing')) {
    items.add(NavigationItem(icon: Icons.shopping_cart, label: 'Purchasing', route: '/purchasing'));
  }
  if (featuresList.contains('storekeeping')) {
    items.add(NavigationItem(icon: Icons.store, label: 'Storekeeping', route: '/storekeeping'));
  }
  if (featuresList.contains('mini_mart')) {
    items.add(NavigationItem(icon: Icons.storefront, label: 'Mini Mart', route: '/mini_mart'));
  }
  return items;
}

void _showLogoutDialog(BuildContext context) {
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Logout'),
      content: const Text('Are you sure you want to logout?'),
      actions: [
        TextButton(
          onPressed: () => ctx.pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () async {
            try {
              ctx.pop();
              final authService = Provider.of<AuthService>(context, listen: false);
              await authService.logout();
              if (context.mounted) context.go('/guest');
            } catch (e, stackTrace) {
              if (kDebugMode) debugPrint('DEBUG logout: $e\n$stackTrace');
              if (context.mounted) {
                ErrorHandler.showWarningMessage(context, ErrorHandler.getFriendlyErrorMessage(e));
                context.go('/guest');
              }
            }
          },
          child: const Text('Logout'),
        ),
      ],
    ),
  );
}

String _userInitial(String name) =>
    name.isNotEmpty ? name.substring(0, 1).toUpperCase() : 'U';

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

class MainScreen extends StatelessWidget {
  final Widget child;

  const MainScreen({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ResponsiveLayout(
      mobile: _MainScreenMobile(child: child),
      tablet: _MainScreenTablet(child: child),
      desktop: _MainScreenDesktop(child: child),
      largeDesktop: _MainScreenLargeDesktop(child: child),
    );
  }
}

class _MainScreenMobile extends StatelessWidget {
  final Widget child;

  const _MainScreenMobile({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            OptimizationHelpers.buildAssetImage(
              assetPath: 'assets/images/PZED logo.png',
              width: 32,
              height: 32,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'P-ZED Luxury Hotels & Suites',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
              if (value == 'logout') _showLogoutDialog(context);
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
      body: child,
      drawer: _MobileDrawer(),
    );
  }
}

class _MainScreenTablet extends StatelessWidget {
  final Widget child;

  const _MainScreenTablet({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            OptimizationHelpers.buildAssetImage(
              assetPath: 'assets/images/PZED logo.png',
              width: 36,
              height: 36,
              fit: BoxFit.contain,
            ),
            const SizedBox(width: 16),
            const Expanded(
              child: Text(
                'P-ZED Luxury Hotels & Suites',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
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
              if (value == 'logout') _showLogoutDialog(context);
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
      drawer: _TabletDrawer(),
      body: child,
    );
  }
}

class _MainScreenDesktop extends StatelessWidget {
  final Widget child;

  const _MainScreenDesktop({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _DesktopSidebar(),
          Expanded(
            child: Column(
              children: [
                _DesktopAppBar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MainScreenLargeDesktop extends StatelessWidget {
  final Widget child;

  const _MainScreenLargeDesktop({required this.child});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Row(
        children: [
          _LargeDesktopSidebar(),
          Expanded(
            child: Column(
              children: [
                _LargeDesktopAppBar(),
                Expanded(child: child),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopSidebar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
          _SidebarHeader(),
          Expanded(
            child: Selector<AuthService, List<NavigationItem>>(
              selector: (_, auth) => _computeNavItems(auth),
              shouldRebuild: (prev, next) => !listEquals(prev, next),
              builder: (context, items, _) => ListView(
                padding: const EdgeInsets.symmetric(vertical: 8),
                children: items
                    .map((item) => _SidebarNavItem(item: item))
                    .toList(),
              ),
            ),
          ),
          _SidebarFooter(),
        ],
      ),
    );
  }
}

class _SidebarHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = context.select<AuthService, String>((a) => a.currentUser?.name ?? 'Unknown User');
    final rolesStr = context.select<AuthService, String>(
        (a) => a.currentUser?.roles.map((r) => r.name.toUpperCase()).join(', ') ?? 'GUEST');
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
              _userInitial(name),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            rolesStr,
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
  }
}

class _SidebarNavItem extends StatelessWidget {
  final NavigationItem item;

  const _SidebarNavItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final isSelected = GoRouterState.of(context).uri.toString() == item.route;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final fontSize = screenWidth < 800 ? 16.0 : 14.0;
    final iconSize = screenWidth < 800 ? 24.0 : 20.0;
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
          size: iconSize,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.green[200],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
            fontSize: fontSize,
          ),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: 16,
          vertical: screenWidth < 800 ? 12 : 8,
        ),
        onTap: () => context.go(item.route),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
    );
  }
}

class _SidebarFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
}

class _DesktopAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
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
              OptimizationHelpers.buildAssetImage(
                assetPath: 'assets/images/PZED logo.png',
                width: 40,
                height: 40,
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
          _AssumeRoleButton(),
          _NotificationBadge(),
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
}

void _showAssumeRoleSheet(BuildContext context) {
  showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return Consumer<AuthService>(
          builder: (context, authService, _) {
            final roles = <Map<String, dynamic>>[
              {'label': 'VIP Bar Bartender', 'role': AppRole.vip_bartender, 'icon': Icons.local_bar, 'color': Colors.purple},
              {'label': 'Outside Bar Bartender', 'role': AppRole.outside_bartender, 'icon': Icons.local_bar_outlined, 'color': Colors.deepPurple},
              {'label': 'Receptionist', 'role': AppRole.receptionist, 'icon': Icons.support_agent, 'color': Colors.indigo},
              {'label': 'Storekeeper', 'role': AppRole.storekeeper, 'icon': Icons.inventory_2, 'color': Colors.teal},
              {'label': 'Purchaser', 'role': AppRole.purchaser, 'icon': Icons.shopping_cart, 'color': Colors.blue},
              {'label': 'Accountant', 'role': AppRole.accountant, 'icon': Icons.calculate, 'color': Colors.green},
              {'label': 'Kitchen Staff', 'role': AppRole.kitchen_staff, 'icon': Icons.restaurant, 'color': Colors.orange},
            ];

            return DraggableScrollableSheet(
              expand: false,
              initialChildSize: 0.55,
              minChildSize: 0.4,
              maxChildSize: 0.9,
              builder: (context, scrollController) => Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.admin_panel_settings),
                        const SizedBox(width: 8),
                        const Text('Multi-Role Session', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        const Spacer(),
                        if (authService.activeAssumedRoles.isNotEmpty)
                          TextButton.icon(
                            onPressed: () {
                              authService.clearAssumedRoles();
                              if (context.mounted) {
                                ErrorHandler.showInfoMessage(context, 'Cleared all assumed roles');
                              }
                            },
                            icon: const Icon(Icons.clear_all),
                            label: const Text('Clear All'),
                          ),
                      ],
                    ),
                    if (authService.activeAssumedRoles.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: authService.activeAssumedRoles.map((role) {
                          final r = roles.firstWhere(
                            (m) => m['role'] == role,
                            orElse: () => {'label': role.name, 'color': Colors.grey},
                          );
                          final Color base = r['color'] is Color ? r['color'] as Color : Colors.grey;
                          return Chip(
                            label: Text(AuthService.getRoleDisplayName(role)),
                            deleteIcon: const Icon(Icons.close, size: 16),
                            onDeleted: () {
                              authService.dropAssumedRole(role);
                              if (context.mounted) {
                                ErrorHandler.showInfoMessage(context, 'Dropped ${AuthService.getRoleDisplayName(role)}');
                              }
                            },
                            backgroundColor: base.withOpacity(0.2),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 16),
                      const Text('Assume another role:', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      const SizedBox(height: 8),
                    ],
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
                          final AppRole role = r['role'] as AppRole;
                          final bool selected = authService.hasAssumedRole(role);
                          return InkWell(
                            onTap: () {
                              if (selected) {
                                authService.dropAssumedRole(role);
                                if (context.mounted) {
                                  ErrorHandler.showInfoMessage(context, 'Dropped ${r['label']}');
                                }
                              } else {
                                authService.assumeRole(role);
                                if (context.mounted) {
                                  ErrorHandler.showInfoMessage(context, 'Now assuming ${r['label']}');
                                }
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
                                  if (selected) const Text('Tap to drop', style: TextStyle(fontSize: 10, color: Colors.grey)),
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
      },
    );
}

class _AssumeRoleButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final showButton = context.select<AuthService, bool>((a) {
      final role = a.currentUser?.role;
      return role == AppRole.owner || role == AppRole.manager;
    });
    if (!showButton) return const SizedBox.shrink();
    return const _AssumeRoleButtonContent();
  }
}

class _AssumeRoleButtonContent extends StatelessWidget {
  const _AssumeRoleButtonContent();

  @override
  Widget build(BuildContext context) {
    final activeCount = context.select<AuthService, int>((a) => a.activeAssumedRoles.length);
    final authService = Provider.of<AuthService>(context, listen: false);
    final hasRoles = activeCount > 0;
    return Badge(
      isLabelVisible: hasRoles,
      label: Text('$activeCount'),
      child: IconButton(
        onPressed: () => _showAssumeRoleSheet(context),
        icon: const Icon(Icons.admin_panel_settings),
        tooltip: hasRoles ? 'Manage assumed roles ($activeCount active)' : 'Assume role(s)',
        style: IconButton.styleFrom(
          backgroundColor: hasRoles ? Colors.orange[700] : Colors.green[800],
          foregroundColor: Colors.white,
        ),
      ),
    );
  }
}

class _NotificationBadge extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final count = context.select<AppStateManager, int>((s) => s.unreadNotifications);
    return Stack(
      children: [
        IconButton(
          icon: const Icon(Icons.notifications_outlined),
          onPressed: () => context.push('/notifications'),
        ),
        if (count > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _MobileDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          _MobileDrawerHeader(),
          Expanded(
            child: Selector<AuthService, List<NavigationItem>>(
              selector: (_, auth) => _computeNavItems(auth),
              shouldRebuild: (prev, next) => !listEquals(prev, next),
              builder: (context, items, _) => AppAnimations.staggeredList(
                children: items.map((item) => _MobileDrawerItem(item: item)).toList(),
              ),
            ),
          ),
          _MobileDrawerFooter(),
        ],
      ),
    );
  }
}

class _MobileDrawerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = context.select<AuthService, String>((a) => a.currentUser?.name ?? 'Unknown User');
    final rolesStr = context.select<AuthService, String>(
        (a) => a.currentUser?.roles.map((r) => r.name.toUpperCase()).join(', ') ?? 'GUEST');
    return DrawerHeader(
      decoration: BoxDecoration(color: Colors.green[800]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.amber[600],
            child: Text(
              _userInitial(name),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            name,
            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            rolesStr,
            style: TextStyle(color: Colors.green[200], fontSize: 14),
          ),
        ],
      ),
    );
  }
}

class _MobileDrawerItem extends StatelessWidget {
  final NavigationItem item;

  const _MobileDrawerItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final isSelected = GoRouterState.of(context).uri.toString() == item.route;
    return ListTile(
      leading: Icon(
        item.icon,
        color: isSelected ? Colors.green[800] : Colors.grey[600],
        size: 28,
      ),
      title: Text(
        item.label,
        style: TextStyle(
          color: isSelected ? Colors.green[800] : Colors.grey[700],
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
          fontSize: 18,
        ),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      selected: isSelected,
      onTap: () {
        Navigator.of(context).pop();
        context.go(item.route);
      },
    );
  }
}

class _MobileDrawerFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.red, size: 28),
        title: const Text('Logout', style: TextStyle(fontSize: 18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        onTap: () {
          Navigator.of(context).pop();
          _showLogoutDialog(context);
        },
      ),
    );
  }
}

class _TabletDrawer extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Drawer(
      width: 320,
      child: Column(
        children: [
          _TabletDrawerHeader(),
          Expanded(
            child: Selector<AuthService, List<NavigationItem>>(
              selector: (_, auth) => _computeNavItems(auth),
              shouldRebuild: (prev, next) => !listEquals(prev, next),
              builder: (context, items, _) => AppAnimations.staggeredList(
                children: items.map((item) => _TabletDrawerItem(item: item)).toList(),
              ),
            ),
          ),
          _TabletDrawerFooter(),
        ],
      ),
    );
  }
}

class _TabletDrawerHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = context.select<AuthService, String>((a) => a.currentUser?.name ?? 'User');
    final email = context.select<AuthService, String>((a) => a.currentUser?.email ?? 'user@example.com');
    return DrawerHeader(
      decoration: BoxDecoration(color: Colors.green[800]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.amber[600],
                child: Text(
                  _userInitial(name),
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      email,
                      style: TextStyle(color: Colors.green[200], fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TabletDrawerItem extends StatelessWidget {
  final NavigationItem item;

  const _TabletDrawerItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final isSelected = GoRouterState.of(context).uri.toString() == item.route;
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
          size: 26,
        ),
        title: Text(
          item.label,
          style: TextStyle(
            color: isSelected ? Colors.white : Colors.grey[700],
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            fontSize: 18,
          ),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        onTap: () {
          Navigator.of(context).pop();
          context.go(item.route);
        },
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _TabletDrawerFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey[300]!)),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.red, size: 26),
        title: const Text('Logout', style: TextStyle(fontSize: 18)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        onTap: () {
          Navigator.of(context).pop();
          _showLogoutDialog(context);
        },
      ),
    );
  }
}

class _LargeDesktopSidebar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 320,
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
          _LargeDesktopSidebarHeader(),
          Expanded(
            child: Selector<AuthService, List<NavigationItem>>(
              selector: (_, auth) => _computeNavItems(auth),
              shouldRebuild: (prev, next) => !listEquals(prev, next),
              builder: (context, items, _) => AppAnimations.staggeredList(
                scrollable: true,
                children: items.map((item) => _LargeDesktopSidebarItem(item: item)).toList(),
              ),
            ),
          ),
          _LargeDesktopSidebarFooter(),
        ],
      ),
    );
  }
}

class _LargeDesktopSidebarHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final name = context.select<AuthService, String>((a) => a.currentUser?.name ?? 'User');
    final email = context.select<AuthService, String>((a) => a.currentUser?.email ?? 'user@example.com');
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.green[700]!, width: 1)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 32,
            backgroundColor: Colors.amber[600],
            child: Text(
              _userInitial(name),
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            name,
            style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            email,
            style: TextStyle(color: Colors.green[200], fontSize: 14),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _LargeDesktopSidebarItem extends StatelessWidget {
  final NavigationItem item;

  const _LargeDesktopSidebarItem({required this.item});

  @override
  Widget build(BuildContext context) {
    final isSelected = GoRouterState.of(context).uri.toString() == item.route;
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}

class _LargeDesktopSidebarFooter extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.green[700]!, width: 1)),
      ),
      child: ListTile(
        leading: const Icon(Icons.logout, color: Colors.red),
        title: const Text('Logout'),
        onTap: () => _showLogoutDialog(context),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}

class _LargeDesktopAppBar extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
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
              OptimizationHelpers.buildAssetImage(
                assetPath: 'assets/images/PZED logo.png',
                width: 48,
                height: 48,
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
          _NotificationBadge(),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () => context.push('/profile'),
          ),
          const SizedBox(width: 8),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') _showLogoutDialog(context);
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

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NavigationItem &&
          other.icon == icon &&
          other.label == label &&
          other.route == route;

  @override
  int get hashCode => Object.hash(icon, label, route);
}