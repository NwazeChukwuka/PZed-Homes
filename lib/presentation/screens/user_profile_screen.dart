import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/data/models/user.dart';

class UserProfileScreen extends StatefulWidget {
  final Map<String, dynamic> userProfile;

  const UserProfileScreen({super.key, required this.userProfile});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> {
  final _supabase = Supabase.instance.client;
  bool _isLoading = false;

  Future<void> _updateUserStatus(String newStatus) async {
    setState(() => _isLoading = true);
    try {
      await _supabase
          .from('profiles')
          .update({'status': newStatus})
          .eq('id', widget.userProfile['id']);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('User status updated to $newStatus'), backgroundColor: Colors.green),
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
      await _supabase.auth.resetPasswordForEmail(email);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Password reset email sent'), backgroundColor: Colors.green),
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
    final isAdmin = currentUser?.role == AppRole.manager || currentUser?.role == AppRole.owner || currentUser?.role == AppRole.hr;
    
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

                  // Admin Actions
                  if (isAdmin) ...[
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

                  const SizedBox(height: 32),
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
}