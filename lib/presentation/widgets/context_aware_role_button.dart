import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/services/auth_service.dart';
import '../../core/error/error_handler.dart';
import '../../data/models/user.dart';

/// Context-aware role assumption button that shows the appropriate role
/// based on the current screen/context
class ContextAwareRoleButton extends StatelessWidget {
  final AppRole suggestedRole;
  final String? customLabel;
  
  const ContextAwareRoleButton({
    super.key,
    required this.suggestedRole,
    this.customLabel,
  });

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    final isOwnerOrManager = user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
    
    // Only show for owner/manager
    if (!isOwnerOrManager) return const SizedBox.shrink();
    
    final isCurrentlyAssumed = authService.isRoleAssumed && authService.assumedRole == suggestedRole;
    final roleName = customLabel ?? AuthService.getRoleDisplayName(suggestedRole);
    
    return Padding(
      padding: const EdgeInsets.all(8.0),
      child: ElevatedButton.icon(
        onPressed: () {
          if (isCurrentlyAssumed) {
            authService.returnToOriginalRole();
            ErrorHandler.showInfoMessage(
              context,
              'Returned to ${user?.role.name.toUpperCase()} role',
            );
          } else {
            if (suggestedRole == AppRole.bartender) {
              _showBartenderChoice(context, authService);
              return;
            }
            authService.assumeRole(suggestedRole);
            ErrorHandler.showSuccessMessage(
              context,
              'Now assuming $roleName role',
            );
          }
        },
        icon: Icon(isCurrentlyAssumed ? Icons.person_off : Icons.person),
        label: Text(
          isCurrentlyAssumed ? 'Return to ${user?.role.name.toUpperCase()}' : 'Assume $roleName Role',
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isCurrentlyAssumed ? Colors.orange[700] : Colors.amber[700],
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
      ),
    );
  }

  void _showBartenderChoice(BuildContext context, AuthService authService) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Assume Bartender Role'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.local_bar),
              title: const Text('VIP Bar Bartender'),
              onTap: () {
                authService.assumeRole(AppRole.vip_bartender);
                Navigator.of(dialogContext).pop();
                ErrorHandler.showSuccessMessage(
                  context,
                  'Now assuming VIP Bar Bartender role',
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_bar_outlined),
              title: const Text('Outside Bar Bartender'),
              onTap: () {
                authService.assumeRole(AppRole.outside_bartender);
                Navigator.of(dialogContext).pop();
                ErrorHandler.showSuccessMessage(
                  context,
                  'Now assuming Outside Bar Bartender role',
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }
}

/// Helper function to get suggested role based on route
AppRole? getSuggestedRoleForContext(String context) {
  final contextLower = context.toLowerCase();
  
  if (contextLower.contains('inventory') || contextLower.contains('bar')) {
    return AppRole.bartender;
  }
  if (contextLower.contains('housekeeping') || contextLower.contains('room')) {
    return AppRole.housekeeper;
  }
  if (contextLower.contains('booking') || contextLower.contains('reception')) {
    return AppRole.receptionist;
  }
  if (contextLower.contains('kitchen') || contextLower.contains('dispatch')) {
    return AppRole.kitchen_staff;
  }
  if (contextLower.contains('store') && !contextLower.contains('view')) {
    return AppRole.storekeeper;
  }
  if (contextLower.contains('purchas')) {
    return AppRole.purchaser;
  }
  if (contextLower.contains('finance') || contextLower.contains('account')) {
    return AppRole.accountant;
  }
  if (contextLower.contains('hr') || contextLower.contains('staff')) {
    return AppRole.hr;
  }
  if (contextLower.contains('minimart') || contextLower.contains('mini_mart')) {
    return AppRole.receptionist; // Minimart is managed by reception
  }
  
  return null;
}
