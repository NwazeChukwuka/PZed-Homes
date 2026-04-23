import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/password_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/widgets/layered_scroll_body.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const UserProfileScreen({super.key, required this.userProfile});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
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

  Future<void> _updateProfileInfo({
    required String profileId,
    required String fullName,
    required String email,
    required String phone,
    required bool updateAuthEmail,
  }) async {
    await _supabase.from('profiles').update({
      'full_name': fullName,
      'email': email,
      'phone': phone,
      'updated_at': DateTime.now().toIso8601String(),
    }).eq('id', profileId);

    if (updateAuthEmail) {
      await _supabase.auth.updateUser(UserAttributes(email: email));
    }
  }

  Future<void> _showEditProfileDialog({
    required bool canEditEmail,
    required bool updateAuthEmail,
  }) async {
    final profileId = widget.userProfile['id'] as String?;
    if (profileId == null || profileId.isEmpty) return;

    final nameController = TextEditingController(
      text: (widget.userProfile['full_name']?.toString() ?? '').trim(),
    );
    final emailController = TextEditingController(
      text: (widget.userProfile['email']?.toString() ?? '').trim(),
    );
    final phoneController = TextEditingController(
      text: (widget.userProfile['phone']?.toString() ?? '').trim(),
    );
    bool saving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Update Personal Information'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      enabled: !saving,
                      decoration: const InputDecoration(
                        labelText: 'Full Name',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: emailController,
                      enabled: !saving && canEditEmail,
                      keyboardType: TextInputType.emailAddress,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: phoneController,
                      enabled: !saving,
                      keyboardType: TextInputType.phone,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: saving ? null : () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: saving
                      ? null
                      : () async {
                          final fullName = nameController.text.trim();
                          final email = emailController.text.trim();
                          final phone = phoneController.text.trim();

                          if (fullName.isEmpty) {
                            ErrorHandler.showWarningMessage(context, 'Full name is required');
                            return;
                          }
                          if (email.isEmpty || !email.contains('@')) {
                            ErrorHandler.showWarningMessage(context, 'Enter a valid email');
                            return;
                          }

                          setDialogState(() => saving = true);
                          try {
                            await _updateProfileInfo(
                              profileId: profileId,
                              fullName: fullName,
                              email: email,
                              phone: phone,
                              updateAuthEmail: updateAuthEmail,
                            );
                            if (!mounted || !dialogContext.mounted) return;
                            setState(() {
                              widget.userProfile['full_name'] = fullName;
                              widget.userProfile['email'] = email;
                              widget.userProfile['phone'] = phone;
                            });
                            Navigator.of(dialogContext).pop();
                            ErrorHandler.showSuccessMessage(
                              dialogContext,
                              'Profile updated',
                            );
                          } catch (e) {
                            if (mounted && dialogContext.mounted) {
                              ErrorHandler.handleError(
                                dialogContext,
                                e,
                                customMessage: 'Failed to update profile info.',
                              );
                            }
                          } finally {
                            if (dialogContext.mounted) {
                              setDialogState(() => saving = false);
                            }
                          }
                        },
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    emailController.dispose();
    phoneController.dispose();
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
                              email: currentUser!.email,
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
                              } else {
                                errorMessage = ErrorHandler.getFriendlyErrorMessage(e);
                              }
                              ErrorHandler.handleError(
                                context,
                                e,
                                customMessage: errorMessage,
                              );
                            }
                          }
                        },
                  child: isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Change Password'),
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

  AppRole? _parseRole(dynamic rawRole) {
    final role = rawRole?.toString().trim();
    if (role == null || role.isEmpty) return null;
    for (final appRole in AppRole.values) {
      if (appRole.name == role) return appRole;
    }
    return null;
  }

  String _resolveUserRoleDisplay(Map<String, dynamic> profile) {
    final primaryRole = _parseRole(profile['role']);
    if (primaryRole != null) {
      return AuthService.getRoleDisplayName(primaryRole);
    }

    final roles = (profile['roles'] as List<dynamic>? ?? [])
        .map((r) => _parseRole(r))
        .whereType<AppRole>()
        .toList();
    if (roles.isNotEmpty) {
      return AuthService.getRoleDisplayName(roles.first);
    }

    return 'Unassigned';
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final currentUser = authService.currentUser;
    final roles = <AppRole>{
      ...?currentUser?.roles,
      ...authService.activeAssumedRoles,
    };
    final bool isManagement = roles.contains(AppRole.owner) ||
        roles.contains(AppRole.manager) ||
        roles.contains(AppRole.hr) ||
        roles.contains(AppRole.supervisor) ||
        roles.contains(AppRole.accountant);
    final bool isHR = roles.contains(AppRole.hr);
    final bool isAdmin = isManagement || isHR;
    final bool isOwner = roles.contains(AppRole.owner);
    final bool canManageStaffProfileEdits = roles.contains(AppRole.owner) ||
        roles.contains(AppRole.manager) ||
        roles.contains(AppRole.hr);
    final bool viewingSelf = (currentUser?.id != null) && (widget.userProfile['id'] == currentUser!.id);

    final userStatus = widget.userProfile['status'] as String? ?? 'Active';
    final userRole = _resolveUserRoleDisplay(widget.userProfile);
    final fullName = widget.userProfile['full_name'] as String? ?? 'Unknown';
    final phone = widget.userProfile['phone'] as String?;
    final createdAt = widget.userProfile['created_at'] != null
        ? DateTime.parse(widget.userProfile['created_at'] as String)
        : null;

    return Scaffold(
      body: LayeredScrollBody(
        topSection: Container(
          color: Colors.green[700],
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
          child: Row(
            children: [
              if (Navigator.of(context).canPop())
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              Expanded(
                child: Text(
                  fullName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.refresh, color: Colors.white),
                  onPressed: () => _resetUserPassword(),
                ),
            ],
          ),
        ),
        content: SingleChildScrollView(
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
                            _buildInfoRow('Role', userRole),
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
                          Row(
                            children: [
                              const Expanded(
                                child: Text(
                                  'User Information',
                                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                                ),
                              ),
                              if (viewingSelf || (canManageStaffProfileEdits && !viewingSelf))
                                IconButton(
                                  tooltip: 'Edit information',
                                  onPressed: () => _showEditProfileDialog(
                                    canEditEmail: true,
                                    updateAuthEmail: viewingSelf,
                                  ),
                                  icon: const Icon(Icons.edit),
                                ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          _buildInfoRow('Full Name', fullName),
                          _buildInfoRow('Role', userRole),
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

                  // Management-only performance overview when viewing another staff
                  if (isManagement && !viewingSelf) ...[
                    const SizedBox(height: 24),
                    const Text(
                      'Performance Overview — Financial Focus',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildPerformanceOverviewSection(widget.userProfile),
                  ],

                  const SizedBox(height: 32),
                  ],
                ],
              ),
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

      final bookingsFuture = _supabase
          .from('bookings')
          .select('paid_amount, status, created_at')
          .eq('created_by', profileId)
          .gte('created_at', thirtyDaysAgo.toIso8601String());

      final departmentSalesFuture = _supabase
          .from('department_sales')
          .select('total_sales, transaction_count, date')
          .eq('staff_id', profileId)
          .gte('date', thirtyDaysAgo.toIso8601String().split('T')[0]);

      final debtsFuture = _supabase
          .from('debts')
          .select('amount, paid_amount, status, created_at')
          .or('sold_by.eq.$profileId,created_by.eq.$profileId')
          .gte('created_at', thirtyDaysAgo.toIso8601String());

      final payrollFuture = _supabase
          .from('payroll_records')
          .select('amount, approval_status, approved_at, month, created_at')
          .eq('staff_id', profileId)
          .order('approved_at', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false);

      final results = await Future.wait([
        bookingsFuture,
        departmentSalesFuture,
        debtsFuture,
        payrollFuture,
      ]).timeout(const Duration(seconds: 8));

      final bookings = List<Map<String, dynamic>>.from(results[0] as List);
      final departmentSales = List<Map<String, dynamic>>.from(results[1] as List);
      final debts = List<Map<String, dynamic>>.from(results[2] as List);
      final payrollRecords = List<Map<String, dynamic>>.from(results[3] as List);

      final successfulBookingStatuses = <String>{
        'checked-in',
        'checked_in',
        'checked out',
        'checked-out',
        'checked_out',
        'confirmed',
      };

      final successfulBookings = bookings.where((b) {
        final paidAmount = (b['paid_amount'] as num?)?.toInt() ?? 0;
        if (paidAmount <= 0) return false;
        final status = (b['status']?.toString() ?? '')
            .trim()
            .toLowerCase()
            .replaceAll('_', '-');
        return successfulBookingStatuses.contains(status);
      }).toList();

      final bookingCount = successfulBookings.length;
      final bookingCollected = successfulBookings.fold<int>(
        0,
        (sum, b) => sum + ((b['paid_amount'] as num?)?.toInt() ?? 0),
      );

      final departmentCount = departmentSales.fold<int>(
        0,
        (sum, row) => sum + ((row['transaction_count'] as num?)?.toInt() ?? 0),
      );
      final departmentCollected = departmentSales.fold<int>(
        0,
        (sum, row) => sum + ((row['total_sales'] as num?)?.toInt() ?? 0),
      );

      final outstandingDebts = debts.where((row) {
        final status = (row['status']?.toString() ?? '').toLowerCase();
        return status == 'outstanding' || status == 'partially_paid';
      }).toList();
      final debtCount = outstandingDebts.length;
      final debtAmount = outstandingDebts.fold<int>(
        0,
        (sum, row) {
          final total = (row['amount'] as num?)?.toInt() ?? 0;
          final paid = (row['paid_amount'] as num?)?.toInt() ?? 0;
          final remaining = total - paid;
          return sum + (remaining > 0 ? remaining : 0);
        },
      );

      final pendingPayroll = payrollRecords
          .where((row) =>
              (row['approval_status']?.toString() ?? '').toLowerCase() == 'pending')
          .toList();
      final owedMonths = pendingPayroll
          .map((row) {
            final raw = row['month']?.toString() ?? '';
            return raw.length >= 7 ? raw.substring(0, 7) : raw;
          })
          .where((month) => month.isNotEmpty)
          .toSet();
      final payrollOwedMonths = owedMonths.length;
      final payrollOwedAmount = pendingPayroll.fold<int>(
        0,
        (sum, row) => sum + ((row['amount'] as num?)?.toInt() ?? 0),
      );

      Map<String, dynamic>? lastApprovedPayroll;
      for (final record in payrollRecords) {
        final status = (record['approval_status']?.toString() ?? '').toLowerCase();
        if (status == 'approved') {
          lastApprovedPayroll = record;
          break;
        }
      }

      DateTime? parseAnyDate(dynamic raw) {
        if (raw == null) return null;
        return DateTime.tryParse(raw.toString());
      }

      DateTime? lastRevenueTransactionAt;
      void ingestDate(DateTime? date) {
        if (date == null) return;
        if (lastRevenueTransactionAt == null || date.isAfter(lastRevenueTransactionAt!)) {
          lastRevenueTransactionAt = date;
        }
      }

      for (final booking in successfulBookings) {
        ingestDate(parseAnyDate(booking['created_at']));
      }
      for (final row in departmentSales) {
        ingestDate(parseAnyDate(row['date']));
      }
      for (final row in debts) {
        ingestDate(parseAnyDate(row['created_at']));
      }

      if (mounted) {
        setState(() {
          _performanceData = {
            'booking_count': bookingCount,
            'booking_collected': bookingCollected,
            'sales_count': departmentCount,
            'sales_collected': departmentCollected,
            'debt_count': debtCount,
            'debt_amount': debtAmount,
            'payroll_owed_months': payrollOwedMonths,
            'payroll_owed_amount': payrollOwedAmount,
            'last_salary_count': lastApprovedPayroll == null ? 0 : 1,
            'last_salary_amount':
                (lastApprovedPayroll?['amount'] as num?)?.toInt() ?? 0,
            'last_salary_paid_at':
                lastApprovedPayroll?['approved_at']?.toString(),
            'last_transaction_at': lastRevenueTransactionAt?.toIso8601String(),
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
        if (context != null && context.mounted) {
          ErrorHandler.handleError(
            context,
            e,
            customMessage: 'Failed to load performance data. Please try again.',
            onRetry: () => _loadPerformanceData(profileId, context: context),
          );
        } else {
          if (kDebugMode) {
            debugPrint('Error loading performance data: $e');
          }
        }
      }
    }
  }

  // Performance overview with real data from database
  Widget _buildPerformanceOverviewSection(Map<String, dynamic> profile) {
    final staffName = (profile['full_name']?.toString() ?? 'Staff');
    final profileId = profile['id'] as String?;

    // Load performance data if not loaded
    final context = this.context;
    if (profileId != null && _performanceData == null && !_isLoadingPerformance) {
      _loadPerformanceData(profileId, context: context);
    }

    List<Map<String, String>> kpis;
    String lastSalaryTop = 'Last salary paid: N/A';
    if (_isLoadingPerformance) {
      kpis = [
        {'label': 'Bookings Revenue (30d)', 'count': 'Loading...', 'amount': 'Loading...'},
        {'label': 'Sales (30d)', 'count': 'Loading...', 'amount': 'Loading...'},
        {'label': 'Debt (Unpaid)', 'count': 'Loading...', 'amount': 'Loading...'},
        {'label': 'Salary Owed (Pending)', 'count': 'Loading...', 'amount': 'Loading...'},
        {'label': 'Last Salary Paid', 'count': 'Loading...', 'amount': 'Loading...'},
        {'label': 'Date of Last Transaction', 'count': 'Loading...', 'amount': 'N/A'},
      ];
    } else if (_performanceData != null) {
      final data = _performanceData!;
      final lastPaidAt = DateTime.tryParse(data['last_salary_paid_at']?.toString() ?? '');
      final lastPaidAtLabel = lastPaidAt == null ? 'N/A' : DateFormat.yMMMd().format(lastPaidAt);
      lastSalaryTop = 'Last salary paid: $lastPaidAtLabel';
      final lastTransaction = DateTime.tryParse(data['last_transaction_at']?.toString() ?? '');
      final lastTransactionLabel =
          lastTransaction == null ? 'N/A' : DateFormat('MMM d, yyyy • h:mm a').format(lastTransaction);
      String amountLabel(int kobo) =>
          '₦${NumberFormat('#,##0.00').format(PaymentService.koboToNaira(kobo))}';

      kpis = [
        {
          'label': 'Bookings Revenue (30d)',
          'count': '${data['booking_count'] ?? 0} txns',
          'amount': amountLabel((data['booking_collected'] as int?) ?? 0),
        },
        {
          'label': 'Sales (30d)',
          'count': '${data['sales_count'] ?? 0} txns',
          'amount': amountLabel((data['sales_collected'] as int?) ?? 0),
        },
        {
          'label': 'Debt (Unpaid)',
          'count': '${data['debt_count'] ?? 0} txns unpaid',
          'amount': amountLabel((data['debt_amount'] as int?) ?? 0),
        },
        {
          'label': 'Salary Owed (Pending)',
          'count': '${data['payroll_owed_months'] ?? 0} months',
          'amount': amountLabel((data['payroll_owed_amount'] as int?) ?? 0),
        },
        {
          'label': 'Last Salary Paid',
          'count': lastPaidAtLabel,
          'amount': amountLabel((data['last_salary_amount'] as int?) ?? 0),
        },
        {
          'label': 'Date of Last Transaction',
          'count': lastTransactionLabel,
          'amount': 'N/A',
        },
      ];
    } else {
      kpis = [
        {'label': 'Bookings Revenue (30d)', 'count': 'N/A', 'amount': 'N/A'},
        {'label': 'Sales (30d)', 'count': 'N/A', 'amount': 'N/A'},
        {'label': 'Debt (Unpaid)', 'count': 'N/A', 'amount': 'N/A'},
        {'label': 'Salary Owed (Pending)', 'count': 'N/A', 'amount': 'N/A'},
        {'label': 'Last Salary Paid', 'count': 'N/A', 'amount': 'N/A'},
        {'label': 'Date of Last Transaction', 'count': 'N/A', 'amount': 'N/A'},
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
            const SizedBox(height: 6),
            Text(
              lastSalaryTop,
              style: TextStyle(color: Colors.grey[700], fontSize: 13),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: kpis
                  .map((kpi) => _buildKpiTile(
                        kpi['label']!,
                        kpi['count']!,
                        kpi['amount']!,
                      ))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKpiTile(String title, String count, String amount) {
    return Container(
      width: 220,
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
            count,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            amount,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green),
          ),
        ],
      ),
    );
  }
}