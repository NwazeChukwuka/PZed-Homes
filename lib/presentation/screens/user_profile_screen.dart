import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/password_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const UserProfileScreen({super.key, required this.userProfile});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  bool _isLoading = false;
  bool _hasSmartlockPermission = false;
  bool _isLoadingPermissions = true;
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _performanceData;
  bool _isLoadingPerformance = false;

  String? _currentProfileId;

  @override
  void initState() {
    super.initState();
    _currentProfileId = widget.userProfile['id'] as String?;
    _loadUserPermissions();
  }

  @override
  void didUpdateWidget(UserProfileScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Clear performance data when switching to a different profile
    final newProfileId = widget.userProfile['id'] as String?;
    if (newProfileId != null && newProfileId != _currentProfileId) {
      setState(() {
        _performanceData = null;
        _isLoadingPerformance = false;
        _currentProfileId = newProfileId;
      });
      // Reload performance data for new profile (will be loaded when build method is called with context)
    }
  }

  // Load real permissions from database
  Future<void> _loadUserPermissions() async {
    setState(() => _isLoadingPermissions = true);
    try {
      final userId = widget.userProfile['id'] as String;
      final response = await _supabase
          .from('access_delegations')
          .select('permission')
          .eq('user_id', userId)
          .timeout(const Duration(seconds: 5));
      
      final permissions = (response as List).map((p) => p['permission'] as String).toList();
      
      if (mounted) {
        setState(() {
          _hasSmartlockPermission = permissions.contains('view_smartlock_logs');
          _isLoadingPermissions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _hasSmartlockPermission = false;
          _isLoadingPermissions = false;
        });
      }
    }
  }

  // Update permission in database
  Future<void> _onPermissionChanged(bool newValue) async {
    try {
      final userId = widget.userProfile['id'] as String;
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      
      if (currentUserId == null) {
        throw Exception('User not authenticated');
      }
      
      if (newValue) {
        // Grant permission
        await _supabase
            .from('access_delegations')
            .upsert({
              'user_id': userId,
              'permission': 'view_smartlock_logs',
              'granted_by_id': currentUserId,
            });
      } else {
        // Revoke permission
        await _supabase
            .from('access_delegations')
            .delete()
            .eq('user_id', userId)
            .eq('permission', 'view_smartlock_logs');
      }
      
      if (mounted) {
        setState(() {
          _hasSmartlockPermission = newValue;
        });
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update permission. Please try again.',
        );
      }
    }

    setState(() => _isLoading = true);
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Smart Lock permission ${newValue ? 'granted' : 'revoked'}',
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update permission. Please try again.',
        );
      }
      // Revert on error
      setState(() {
        _hasSmartlockPermission = !newValue;
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateUserStatus(String newStatus) async {
    setState(() => _isLoading = true);
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'User status updated to $newStatus',
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update status. Please try again.',
        );
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetUserPassword() async {
    final email = widget.userProfile['email'];
    if (email == null) {
      if (mounted) {
        ErrorHandler.showWarningMessage(
          context,
          'Email address not found',
        );
      }
      return;
    }

    // Use consolidated password service
    await PasswordService.showPasswordResetDialog(context);
  }

  Future<void> _showChangePasswordDialog() async {
    final oldPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();
    final confirmPasswordController = TextEditingController();
    bool isLoading = false;
    bool obscureOldPassword = true;
    bool obscureNewPassword = true;
    bool obscureConfirmPassword = true;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Change Password'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: oldPasswordController,
                      enabled: !isLoading,
                      obscureText: obscureOldPassword,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock),
                        suffixIcon: IconButton(
                          icon: Icon(obscureOldPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setDialogState(() => obscureOldPassword = !obscureOldPassword),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: newPasswordController,
                      enabled: !isLoading,
                      obscureText: obscureNewPassword,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscureNewPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setDialogState(() => obscureNewPassword = !obscureNewPassword),
                        ),
                        helperText: 'Must be at least 6 characters',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: confirmPasswordController,
                      enabled: !isLoading,
                      obscureText: obscureConfirmPassword,
                      decoration: InputDecoration(
                        labelText: 'Confirm New Password',
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.lock_outline),
                        suffixIcon: IconButton(
                          icon: Icon(obscureConfirmPassword ? Icons.visibility : Icons.visibility_off),
                          onPressed: () => setDialogState(() => obscureConfirmPassword = !obscureConfirmPassword),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: <Widget>[
                if (!isLoading)
                  TextButton(
                    child: const Text('Cancel'),
                    onPressed: () {
                      oldPasswordController.dispose();
                      newPasswordController.dispose();
                      confirmPasswordController.dispose();
                      Navigator.of(context).pop();
                    },
                  ),
                ElevatedButton(
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change Password'),
                  onPressed: isLoading
                      ? null
                      : () async {
                          // Validation
                          if (oldPasswordController.text.isEmpty) {
                            ErrorHandler.showWarningMessage(
                              context,
                              'Please enter your current password',
                            );
                            return;
                          }

                          if (newPasswordController.text.length < 6) {
                            ErrorHandler.showWarningMessage(
                              context,
                              'New password must be at least 6 characters',
                            );
                            return;
                          }

                          if (newPasswordController.text != confirmPasswordController.text) {
                            ErrorHandler.showWarningMessage(
                              context,
                              'New passwords do not match',
                            );
                            return;
                          }

                          setDialogState(() => isLoading = true);

                          try {
                            final passwordService = PasswordService();
                            
                            // Verify old password by attempting to re-authenticate
                            final authService = Provider.of<AuthService>(context, listen: false);
                            final currentUser = authService.currentUser;
                            if (currentUser?.email == null) {
                              throw Exception('User email not found');
                            }

                            // Re-authenticate with old password
                            await Supabase.instance.client.auth.signInWithPassword(
                              email: currentUser!.email!,
                              password: oldPasswordController.text,
                            );

                            // Update to new password
                            await passwordService.updatePassword(newPasswordController.text);

                            oldPasswordController.dispose();
                            newPasswordController.dispose();
                            confirmPasswordController.dispose();

                            if (context.mounted) {
                              Navigator.of(context).pop();
                              ErrorHandler.showSuccessMessage(
                                context,
                                'Password changed successfully!',
                              );
                            }
                          } catch (e) {
                            setDialogState(() => isLoading = false);
                            if (context.mounted) {
                              String errorMessage = 'Failed to change password';
                              if (e.toString().contains('Invalid login credentials')) {
                                errorMessage = 'Current password is incorrect';
                              } else if (e.toString().contains('Password')) {
                                errorMessage = e.toString();
                              }
                              ErrorHandler.handleError(
                                context,
                                e,
                                customMessage: errorMessage,
                              );
                            }
                          }
                        },
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.grey;
      case 'suspended':
        return Colors.orange;
      case 'resigned':
        return Colors.blue;
      case 'terminated':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.currentUser;
    final effectiveRole = authService.isRoleAssumed
        ? (authService.assumedRole ?? currentUser?.role)
        : currentUser?.role;
    final roles = <AppRole>{
      ...?currentUser?.roles,
      if (authService.isRoleAssumed && authService.assumedRole != null)
        authService.assumedRole!,
    };
    final bool isManagement = roles.contains(AppRole.owner) ||
        roles.contains(AppRole.manager) ||
        roles.contains(AppRole.hr) ||
        roles.contains(AppRole.supervisor) ||
        roles.contains(AppRole.accountant);
    final bool isHR = roles.contains(AppRole.hr);
    final bool isAdmin = isManagement || isHR;
    final bool isOwner = roles.contains(AppRole.owner);
    final bool viewingSelf = (currentUser?.id != null) && (widget.userProfile['id'] == currentUser!.id);

    final userStatus = widget.userProfile['status'] as String? ?? 'Active';
    final userRole = widget.userProfile['role'] as String? ?? 'Unknown';
    final fullName = widget.userProfile['full_name'] as String? ?? 'Unknown';
    final phone = widget.userProfile['phone'] as String?;
    final createdAt = widget.userProfile['created_at'] != null
        ? DateTime.parse(widget.userProfile['created_at'] as String)
        : null;

    return Scaffold(
      appBar: AppBar(
        title: Text(fullName),
        actions: [
          if (isAdmin) IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () => _resetUserPassword(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Owner/Manager have full access to all profiles
                  // Non-management staff should not reach this screen for other users (hidden in UI)

                  // Limited view for non-management when viewing other staff
                  if (!viewingSelf && !isAdmin) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Limited Profile',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 12),
                            _buildInfoRow('Full Name', fullName),
                            _buildInfoRow('Role', userRole.toUpperCase()),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (viewingSelf || isAdmin) ...[
                  // User Avatar
                  Center(
                    child: CircleAvatar(
                      radius: 50,
                      backgroundColor: Colors.blueGrey.shade100,
                      child: Icon(
                        Icons.person,
                        size: 40,
                        color: Colors.blueGrey.shade600,
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // User Information
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'User Information',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 16),
                          _buildInfoRow('Full Name', fullName),
                          _buildInfoRow('Role', userRole.toUpperCase()),
                          _buildInfoRow('Status', userStatus, 
                              valueColor: _getStatusColor(userStatus)),
                          if (phone != null) _buildInfoRow('Phone', phone),
                          if (createdAt != null) 
                            _buildInfoRow('Member Since', DateFormat.yMMMd().format(createdAt)),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Change Password Section (for users viewing their own profile)
                  if (viewingSelf) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Change Password',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Update your account password',
                              style: TextStyle(color: Colors.grey),
                            ),
                            const SizedBox(height: 16),
                            ElevatedButton.icon(
                              onPressed: _showChangePasswordDialog,
                              icon: const Icon(Icons.lock_outline),
                              label: const Text('Change Password'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.blue[700],
                                foregroundColor: Colors.white,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                  ],

                  // Permission Delegation Section (Owner only)
                  if (isOwner && !viewingSelf) ...[
                    _buildPermissionsCard(isOwner: true),
                    const SizedBox(height: 24),
                  ],

                  // View-only permissions for users viewing their own profile
                  if (viewingSelf && !isOwner) ...[
                    _buildViewOnlyPermissions(),
                    const SizedBox(height: 24),
                  ],

                  // Role Assumption Section (for Owner and Manager)
                  if (isManagement) ...[
                    const Text(
                      'Assume Role',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Temporarily assume a role to access specific functionalities:',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildRoleChip('VIP Bar Bartender', AppRole.vip_bartender, authService),
                        _buildRoleChip('Outside Bar Bartender', AppRole.outside_bartender, authService),
                        _buildRoleChip('Receptionist', AppRole.receptionist, authService),
                        _buildRoleChip('Storekeeper', AppRole.storekeeper, authService),
                        _buildRoleChip('Purchaser', AppRole.purchaser, authService),
                        _buildRoleChip('Accountant', AppRole.accountant, authService),
                        _buildRoleChip('Kitchen Staff', AppRole.kitchen_staff, authService),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (authService.isRoleAssumed) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange.shade300),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline, color: Colors.orange.shade700),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Currently assuming: ${authService.assumedRole?.toString().split('.').last ?? 'Unknown'}',
                                style: TextStyle(
                                  color: Colors.orange.shade700,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            TextButton(
                              onPressed: () => authService.returnToOriginalRole(),
                              child: const Text('Return to Original Role'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],

                  // Admin Actions
                  if (isAdmin) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Admin Actions',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _buildStatusChip('Active', userStatus),
                        _buildStatusChip('Inactive', userStatus),
                        _buildStatusChip('Suspended', userStatus),
                        _buildStatusChip('Resigned', userStatus),
                        _buildStatusChip('Terminated', userStatus),
                      ],
                    ),
                  ],

                  // Management-only performance overview when viewing another staff
                  if (isManagement && !viewingSelf) ...[
                    const SizedBox(height: 24),
                    Text(
                      (effectiveRole == AppRole.owner || effectiveRole == AppRole.accountant)
                          ? 'Performance Overview — Financial Focus'
                          : 'Performance Overview',
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    if (effectiveRole == AppRole.owner || effectiveRole == AppRole.accountant)
                      _buildPerformanceOverviewSection(widget.userProfile, detail: 'financial')
                    else
                      _buildPerformanceOverviewSection(widget.userProfile, detail: 'standard'),
                  ],

                  const SizedBox(height: 32),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildInfoRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value,
              style: TextStyle(color: valueColor),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusChip(String status, String currentStatus) {
    return ChoiceChip(
      label: Text(status),
      selected: currentStatus.toLowerCase() == status.toLowerCase(),
      onSelected: (selected) {
        if (selected) {
          _updateUserStatus(status);
        }
      },
      selectedColor: _getStatusColor(status),
      labelStyle: TextStyle(
        color: currentStatus.toLowerCase() == status.toLowerCase() 
            ? Colors.white 
            : null,
      ),
    );
  }

  Widget _buildRoleChip(String roleName, AppRole role, AuthService authService) {
    final isCurrentlyAssumed = authService.isRoleAssumed && authService.assumedRole == role;
    
    return ChoiceChip(
      label: Text(roleName),
      selected: isCurrentlyAssumed,
      onSelected: (selected) {
        if (selected) {
          authService.assumeRole(role);
          if (mounted) {
            ErrorHandler.showSuccessMessage(
              context,
              'Now assuming $roleName role',
            );
          }
        }
      },
      selectedColor: Colors.green,
      labelStyle: TextStyle(
        color: isCurrentlyAssumed ? Colors.white : null,
      ),
    );
  }

  // Permission Delegation Card (for Owners managing other users)
  Widget _buildPermissionsCard({required bool isOwner}) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Manage Delegated Permissions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Grant special access permissions to this user',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const Divider(height: 24),
            if (_isLoadingPermissions)
              const Center(child: CircularProgressIndicator())
            else
              SwitchListTile(
                title: const Text('Smart Lock Log Access'),
                subtitle: const Text('Grants access to view all smart lock activity logs and history.'),
                value: _hasSmartlockPermission,
                onChanged: _onPermissionChanged,
                secondary: Icon(
                  Icons.lock_clock, 
                  color: _hasSmartlockPermission ? Colors.teal : Colors.grey
                ),
              ),
          ],
        ),
      ),
    );
  }

  // View-only permissions for regular users
  Widget _buildViewOnlyPermissions() {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'My Delegated Permissions',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'Special access permissions granted by management',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const Divider(height: 24),
            if (_isLoadingPermissions)
              const Center(child: CircularProgressIndicator())
            else if (!_hasSmartlockPermission)
              const ListTile(
                leading: Icon(Icons.info_outline, color: Colors.grey),
                title: Text('No special permissions granted'),
                subtitle: Text('Contact management for additional access needs.'),
              )
            else
              const ListTile(
                leading: Icon(Icons.lock_clock, color: Colors.teal),
                title: Text('Smart Lock Log Access'),
                subtitle: Text('You have been granted access to view smart lock activity logs.'),
              ),
          ],
        ),
      ),
    );
  }

  // Load performance data from database
  Future<void> _loadPerformanceData(String profileId, {BuildContext? context}) async {
    if (_isLoadingPerformance) return;
    
    setState(() => _isLoadingPerformance = true);
    
    try {
      final now = DateTime.now();
      final thirtyDaysAgo = now.subtract(const Duration(days: 30));
      
      // Load attendance records
      final attendanceResponse = await _supabase
          .from('attendance_records')
          .select('*')
          .eq('profile_id', profileId)
          .gte('date', thirtyDaysAgo.toIso8601String().split('T')[0])
          .timeout(const Duration(seconds: 5));
      
      final attendanceRecords = attendanceResponse as List;
      
      // Load department sales (for sales attributed to this staff member)
      final salesResponse = await _supabase
          .from('department_sales')
          .select('total_sales, transaction_count')
          .eq('staff_id', profileId) // Filter by staff_id to get individual performance
          .gte('date', thirtyDaysAgo.toIso8601String().split('T')[0])
          .timeout(const Duration(seconds: 5));
      
      final salesRecords = salesResponse as List;
      
      // Load payroll records
      final payrollResponse = await _supabase
          .from('payroll_records')
          .select('*')
          .eq('staff_id', profileId)
          .gte('month', thirtyDaysAgo.toIso8601String().split('T')[0])
          .timeout(const Duration(seconds: 5));
      
      final payrollRecords = payrollResponse as List;
      
      // Calculate metrics
      final totalDays = 30;
      final attendanceDays = attendanceRecords.length;
      final attendanceRate = totalDays > 0 ? (attendanceDays / totalDays * 100).toStringAsFixed(0) : '0';
      
      // Calculate total sales (sum of all department sales)
      final totalSales = salesRecords.fold<int>(0, (sum, record) {
        return sum + ((record['total_sales'] as num?)?.toInt() ?? 0);
      });
      
      // Calculate average ticket value (simplified - total sales / transaction count)
      final totalTransactions = salesRecords.fold<int>(0, (sum, record) {
        return sum + ((record['transaction_count'] as num?)?.toInt() ?? 0);
      });
      final avgTicketValue = totalTransactions > 0 ? (totalSales / totalTransactions / 100) : 0.0;
      
      // Calculate overtime cost (from payroll - simplified)
      final overtimeCost = payrollRecords.fold<int>(0, (sum, record) {
        return sum + ((record['amount'] as num?)?.toInt() ?? 0);
      });
      
      // Check payroll status
      final pendingPayroll = payrollRecords.where((r) => r['status'] == 'pending').length;
      final payrollStatus = pendingPayroll > 0 ? 'Pending ($pendingPayroll)' : 'Up-to-date';
      
      if (mounted) {
        setState(() {
          _performanceData = {
            'attendance_rate': attendanceRate,
            'attendance_days': attendanceDays,
            'total_sales': totalSales,
            'avg_ticket_value': avgTicketValue,
            'overtime_cost': overtimeCost,
            'payroll_status': payrollStatus,
          };
          _isLoadingPerformance = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _performanceData = null;
          _isLoadingPerformance = false;
        });
        // Show error to user with retry option if context is available
        if (context != null && mounted) {
          ErrorHandler.handleError(
            context,
            e,
            customMessage: 'Failed to load performance data. Please try again.',
            onRetry: () => _loadPerformanceData(profileId, context: context),
          );
        } else {
          // Log error if context not available
          if (kDebugMode) {
            debugPrint('Error loading performance data: $e');
          }
        }
      }
    }
  }

  // Performance overview with real data from database
  Widget _buildPerformanceOverviewSection(Map<String, dynamic> profile, {String detail = 'standard'}) {
    final staffName = (profile['full_name']?.toString() ?? 'Staff');
    final profileId = profile['id'] as String?;
    
    // Load performance data if not loaded
    // Get context from the widget tree
    final context = this.context;
    if (profileId != null && _performanceData == null && !_isLoadingPerformance) {
      _loadPerformanceData(profileId, context: context);
    }
    
    // Build KPIs from real data or show loading
    List<Map<String, String>> standardKpis;
    List<Map<String, String>> financialKpis;
    
    if (_isLoadingPerformance) {
      standardKpis = [
        {'label': 'Attendance Rate', 'value': 'Loading...'},
        {'label': 'Tasks Completed (30d)', 'value': 'Loading...'},
        {'label': 'Customer Ratings', 'value': 'N/A'},
        {'label': 'Shift Punctuality', 'value': 'Loading...'},
      ];
      financialKpis = [
        {'label': 'Sales Attributed (30d)', 'value': 'Loading...'},
        {'label': 'Refunds/Discounts', 'value': 'N/A'},
        {'label': 'Cash Variance', 'value': 'N/A'},
        {'label': 'Avg. Ticket Value', 'value': 'Loading...'},
        {'label': 'Overtime Cost (30d)', 'value': 'Loading...'},
        {'label': 'Payroll Status', 'value': 'Loading...'},
      ];
    } else if (_performanceData != null) {
      final data = _performanceData!;
      final salesAmount = PaymentService.koboToNaira(data['total_sales'] as int? ?? 0);
      final avgTicket = PaymentService.koboToNaira((data['avg_ticket_value'] as num? ?? 0).toInt());
      final overtime = PaymentService.koboToNaira(data['overtime_cost'] as int? ?? 0);
      
      standardKpis = [
        {'label': 'Attendance Rate', 'value': '${data['attendance_rate']}%'},
        {'label': 'Days Present (30d)', 'value': '${data['attendance_days']}'},
        {'label': 'Customer Ratings', 'value': 'N/A'}, // Not tracked in database yet
        {'label': 'Shift Punctuality', 'value': 'N/A'}, // Not tracked in database yet
      ];
      
      financialKpis = [
        {'label': 'Sales Attributed (30d)', 'value': '₦${NumberFormat('#,##0.00').format(salesAmount)}'},
        {'label': 'Refunds/Discounts', 'value': 'N/A'}, // Not tracked separately yet
        {'label': 'Cash Variance', 'value': 'N/A'}, // Not tracked yet
        {'label': 'Avg. Ticket Value', 'value': '₦${NumberFormat('#,##0.00').format(avgTicket)}'},
        {'label': 'Payroll Cost (30d)', 'value': '₦${NumberFormat('#,##0.00').format(overtime)}'},
        {'label': 'Payroll Status', 'value': data['payroll_status'] as String? ?? 'N/A'},
      ];
    } else {
      // Fallback if data failed to load
      standardKpis = [
        {'label': 'Attendance Rate', 'value': 'N/A'},
        {'label': 'Days Present (30d)', 'value': 'N/A'},
        {'label': 'Customer Ratings', 'value': 'N/A'},
        {'label': 'Shift Punctuality', 'value': 'N/A'},
      ];
      financialKpis = [
        {'label': 'Sales Attributed (30d)', 'value': 'N/A'},
        {'label': 'Refunds/Discounts', 'value': 'N/A'},
        {'label': 'Cash Variance', 'value': 'N/A'},
        {'label': 'Avg. Ticket Value', 'value': 'N/A'},
        {'label': 'Payroll Cost (30d)', 'value': 'N/A'},
        {'label': 'Payroll Status', 'value': 'N/A'},
      ];
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$staffName — Key Performance Indicators',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: (detail == 'financial' ? financialKpis : standardKpis)
                  .map((kpi) => _buildKpiTile(kpi['label']!, kpi['value']!))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiTile(String title, String value) {
    return Container(
      width: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(color: Colors.black87)),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}