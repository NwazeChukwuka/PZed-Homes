import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/data/models/user.dart';

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

  @override
  void initState() {
    super.initState();
    _loadUserPermissions();
  }

  // Mock implementation of permission loading
  Future<void> _loadUserPermissions() async {
    setState(() => _isLoadingPermissions = true);
    try {
      await Future.delayed(const Duration(milliseconds: 300));
      if (mounted) {
        setState(() {
          // Mock data: Randomly assign smart lock permission for demo
          _hasSmartlockPermission = widget.userProfile['id'] % 3 == 0;
          _isLoadingPermissions = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingPermissions = false);
      }
    }
  }

  // Mock implementation of permission changes
  Future<void> _onPermissionChanged(bool newValue) async {
    setState(() {
      _hasSmartlockPermission = newValue;
    });

    setState(() => _isLoading = true);
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('[Mock] Smart Lock permission ${newValue ? 'granted' : 'revoked'}'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error updating permission: $e'),
          backgroundColor: Colors.red,
        ),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('[Mock] User status updated to $newStatus'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error updating status: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _resetUserPassword() async {
    final email = widget.userProfile['email'];
    if (email == null) return;

    setState(() => _isLoading = true);
    try {
      await Future.delayed(const Duration(milliseconds: 400));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('[Mock] Password reset email would be sent'), backgroundColor: Colors.green),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error sending reset email: $e'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.red;
      case 'suspended':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<MockAuthService>(context);
    final currentUser = authService.currentUser;
    final effectiveRole = authService.isRoleAssumed
        ? (authService.assumedRole ?? currentUser?.role)
        : currentUser?.role;
    final bool isManagement = effectiveRole == AppRole.owner || effectiveRole == AppRole.manager || effectiveRole == AppRole.hr || effectiveRole == AppRole.supervisor || effectiveRole == AppRole.accountant;
    final bool isHR = effectiveRole == AppRole.hr;
    final bool isAdmin = isManagement || isHR;
    final bool isOwner = effectiveRole == AppRole.owner;
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
                        _buildRoleChip('Bartender', AppRole.bartender, authService),
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

  Widget _buildRoleChip(String roleName, AppRole role, MockAuthService authService) {
    final isCurrentlyAssumed = authService.isRoleAssumed && authService.assumedRole == role;
    
    return ChoiceChip(
      label: Text(roleName),
      selected: isCurrentlyAssumed,
      onSelected: (selected) {
        if (selected) {
          authService.assumeRole(role);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Now assuming $roleName role'),
              backgroundColor: Colors.green,
            ),
          );
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

  // Placeholder performance overview for management. Replace with real metrics when backend is ready.
  Widget _buildPerformanceOverviewSection(Map<String, dynamic> profile, {String detail = 'standard'}) {
    final staffName = (profile['full_name']?.toString() ?? 'Staff');

    final standardKpis = <Map<String, String>>[
      {'label': 'Attendance Rate', 'value': '95%'},
      {'label': 'Tasks Completed (30d)', 'value': '42'},
      {'label': 'Customer Ratings', 'value': '4.6/5'},
      {'label': 'Shift Punctuality', 'value': '92%'},
    ];

    final financialKpis = <Map<String, String>>[
      {'label': 'Sales Attributed (30d)', 'value': '₦1.8M'},
      {'label': 'Refunds/Discounts', 'value': '₦45k'},
      {'label': 'Cash Variance', 'value': '₦0'},
      {'label': 'Avg. Ticket Value', 'value': '₦14,500'},
      {'label': 'Overtime Cost (30d)', 'value': '₦120k'},
      {'label': 'Payroll Status', 'value': 'Up-to-date'},
    ];

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