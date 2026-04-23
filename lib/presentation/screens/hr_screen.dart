import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/utils/input_sanitizer.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/presentation/widgets/layered_scroll_body.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class HrScreen extends StatefulWidget {
  const HrScreen({super.key});
  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final DataService _dataService = DataService();
  final DateFormat _dateFormat = DateFormat('MMM dd, yyyy');

  List<Map<String, dynamic>> _allStaff = [];
  List<Map<String, dynamic>> _filteredStaff = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 2,
      vsync: this,
    ); // Staff Directory, Roles & Positions
    _loadStaff();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _generateSecurePassword() {
    const prefix = 'Pzed';
    const numbers = '0123456789';
    const allLetters = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
    final random = Random.secure();
    final suffix = StringBuffer();
    
    final useThreeNumbers = random.nextBool();
    
    if (useThreeNumbers) {
      for (int i = 0; i < 3; i++) {
        suffix.write(numbers[random.nextInt(numbers.length)]);
      }
      for (int i = 0; i < 2; i++) {
        suffix.write(allLetters[random.nextInt(allLetters.length)]);
      }
    } else {
      for (int i = 0; i < 2; i++) {
        suffix.write(numbers[random.nextInt(numbers.length)]);
      }
      for (int i = 0; i < 3; i++) {
        suffix.write(allLetters[random.nextInt(allLetters.length)]);
      }
    }
    
    return '$prefix$suffix';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: LayeredScrollBody(
        topSection: Column(
          children: [
            _buildHeader(context),
            Container(
              width: double.infinity,
              color: Colors.white,
              child: TabBar(
                controller: _tabController,
                labelColor: Colors.green[800],
                unselectedLabelColor: Colors.grey[600],
                indicatorColor: Colors.green[800],
                isScrollable: false,
                tabAlignment: TabAlignment.fill,
                tabs: const [
                  Tab(text: 'Staff Directory', icon: Icon(Icons.people_alt)),
                  Tab(
                    text: 'Roles & Positions',
                    icon: Icon(Icons.admin_panel_settings),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: TabBarView(
          controller: _tabController,
          children: [
            _buildStaffDirectoryTab(context),
            _buildRolesPositionsTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Human Resources',
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Staff directory and roles & positions',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final staff = await _dataService.getStaffProfiles();
      setState(() {
        _allStaff = staff;
        _applySearchFilter();
        _isLoading = false;
      });
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _loadStaff: $e\n$stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage:
              'Failed to load staff. Please check your connection and try again.',
          onRetry: _loadStaff,
          stackTrace: stackTrace,
        );
      }
    }
  }

  void _applySearchFilter() {
    final q = _searchQuery.toLowerCase();
    _filteredStaff = _allStaff.where((u) {
      final name = (u['full_name']?.toString() ?? '').toLowerCase();
      final email = (u['email']?.toString() ?? '').toLowerCase();
      final roles = (u['roles'] as List<dynamic>? ?? [])
          .join(',')
          .toLowerCase();
      return q.isEmpty ||
          name.contains(q) ||
          email.contains(q) ||
          roles.contains(q);
    }).toList();
  }

  Widget _buildStaffDirectoryTab(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: const InputDecoration(
                    hintText: 'Search by name, email, or role',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (v) {
                    setState(() {
                      _searchQuery = v;
                      _applySearchFilter();
                    });
                  },
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _loadStaff,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              Consumer<AuthService>(
                builder: (context, authService, _) {
                  final currentRole = authService.currentUser?.role;
                  final isOwnerOrManager = currentRole == AppRole.owner || currentRole == AppRole.manager;
                  if (!isOwnerOrManager) return const SizedBox.shrink();

                  return Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: ElevatedButton.icon(
                      onPressed: _showHireNewStaffDialog,
                      icon: const Icon(Icons.person_add),
                      label: const Text('Hire New Staff'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green[700],
                        foregroundColor: Colors.white,
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _filteredStaff.length,
                  itemBuilder: (context, index) {
                    final u = _filteredStaff[index];
                    final name =
                        (u['full_name']?.toString() ??
                        (u['name']?.toString() ?? 'Unknown'));
                    final roles = (u['roles'] as List<dynamic>? ?? [])
                        .map((e) => e.toString())
                        .toList();
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green[100],
                          child: const Icon(Icons.person, color: Colors.green),
                        ),
                        title: Text(name.isEmpty ? 'Unknown' : name),
                        subtitle: Text(
                          roles.isEmpty ? 'Unassigned' : roles.join(', '),
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) {
                            switch (v) {
                              case 'promote':
                                _showPromoteDemoteDialog(u, isPromote: true);
                                break;
                              case 'demote':
                                _showPromoteDemoteDialog(u, isPromote: false);
                                break;
                              case 'transfer':
                                _showTransferRoleDialog(u);
                                break;
                              case 'assign':
                                _showAssignRoleDialog(u);
                                break;
                              case 'suspend':
                                _showSuspendDialog(u);
                                break;
                              case 'terminate':
                                _showTerminateDialog(u);
                                break;
                            }
                          },
                          itemBuilder: (context) {
                            final authService = Provider.of<AuthService>(
                              context,
                              listen: false,
                            );
                            final role = authService.currentUser?.role;
                            final canTerminate =
                                role == AppRole.owner || role == AppRole.manager;

                            return [
                              const PopupMenuItem(
                                value: 'promote',
                                child: Text('Promote'),
                              ),
                              const PopupMenuItem(
                                value: 'demote',
                                child: Text('Demote'),
                              ),
                              const PopupMenuItem(
                                value: 'transfer',
                                child: Text('Transfer'),
                              ),
                              const PopupMenuItem(
                                value: 'assign',
                                child: Text('Assign Role'),
                              ),
                              const PopupMenuItem(
                                value: 'suspend',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.pause_circle,
                                      color: Colors.orange,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text('Suspend'),
                                  ],
                                ),
                              ),
                              if (canTerminate)
                                const PopupMenuItem(
                                  value: 'terminate',
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.person_remove,
                                        color: Colors.red,
                                        size: 18,
                                      ),
                                      SizedBox(width: 8),
                                      Text('Terminate Employment'),
                                    ],
                                  ),
                                ),
                            ];
                          },
                        ),
                        onTap: () => context.push('/profile', extra: u),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildRolesPositionsTab(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ElevatedButton.icon(
                onPressed: _showCreatePositionDialog,
                icon: const Icon(Icons.add),
                label: const Text('Create Position'),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () => _showAssignRoleDialog(null),
                icon: const Icon(Icons.person_add_alt_1),
                label: const Text('Assign Role to Staff'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView(
              children: [
                ListTile(
                  leading: const Icon(Icons.admin_panel_settings),
                  title: const Text('Positions & Benefits'),
                  subtitle: const Text(
                    'Define scalable positions with benefits and permissions',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showPromoteDemoteDialog(
    Map<String, dynamic> user, {
    required bool isPromote,
  }) async {
    final available = AppRole.values
        .where((r) => r != AppRole.owner && r != AppRole.guest)
        .toList();
    AppRole? selected;
    String? selectedBar;
    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Text(isPromote ? 'Promote Staff' : 'Demote Staff'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AppRole>(
                decoration: const InputDecoration(labelText: 'Select Role'),
                items: available
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                    .toList(),
                onChanged: (v) {
                  setDialogState(() {
                    selected = v;
                    if (selected != AppRole.bartender) {
                      selectedBar = null;
                    }
                  });
                },
              ),
              if (selected == AppRole.bartender) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Select Bar'),
                  initialValue: selectedBar,
                  items: const [
                    DropdownMenuItem(value: 'vip_bar', child: Text('VIP Bar')),
                    DropdownMenuItem(value: 'outside_bar', child: Text('Outside Bar')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedBar = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selected == null) return;
                if (selected == AppRole.bartender && selectedBar == null) {
                  ErrorHandler.showWarningMessage(
                    dialogContext,
                    'Please select a bar for the bartender role',
                  );
                  return;
                }
                final roleToAssign = selected == AppRole.bartender
                    ? (selectedBar == 'outside_bar'
                        ? AppRole.outside_bartender
                        : AppRole.vip_bartender)
                    : selected!;
                await _dataService.assignRoleToStaff(
                  user['id'] as String,
                  roleToAssign.name,
                  isTemporary: false,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _loadStaff();
                if (!mounted) return;
                ErrorHandler.showSuccessMessage(
                  context,
                  'Updated role to ${roleToAssign.name} for ${user['full_name']}',
                );
              },
              child: Text(isPromote ? 'Promote' : 'Demote'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showAssignRoleDialog(Map<String, dynamic>? user) async {
    String? staffId = user?['id'] as String?;
    AppRole? selectedRole;
    String? selectedBar;
    bool isTemporary = false;
    DateTime? expiry;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setState) => AlertDialog(
          title: const Text('Assign Role to Staff'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (user == null)
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(
                      labelText: 'Select Staff (by ID)',
                    ),
                    items: _allStaff
                        .map(
                          (s) => DropdownMenuItem(
                            value: s['id'] as String,
                            child: Text(
                              s['full_name']?.toString() ?? 'Unnamed',
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => staffId = v,
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AppRole>(
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: AppRole.values
                      .where((r) => r != AppRole.owner && r != AppRole.guest)
                      .map(
                        (r) => DropdownMenuItem(value: r, child: Text(r.name)),
                      )
                      .toList(),
                  onChanged: (v) {
                    setState(() {
                      selectedRole = v;
                      if (selectedRole != AppRole.bartender) {
                        selectedBar = null;
                      }
                    });
                  },
                ),
                if (selectedRole == AppRole.bartender) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Select Bar'),
                    initialValue: selectedBar,
                    items: const [
                      DropdownMenuItem(value: 'vip_bar', child: Text('VIP Bar')),
                      DropdownMenuItem(value: 'outside_bar', child: Text('Outside Bar')),
                    ],
                    onChanged: (v) => setState(() => selectedBar = v),
                  ),
                ],
                const SizedBox(height: 12),
                SwitchListTile(
                  value: isTemporary,
                  onChanged: (v) => setState(() => isTemporary = v),
                  title: const Text('Temporary assignment'),
                ),
                if (isTemporary)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now().add(
                          const Duration(days: 7),
                        ),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => expiry = picked);
                    },
                    icon: const Icon(Icons.date_range),
                    label: Text(
                      expiry == null
                          ? 'Pick expiry date'
                          : 'Expires: ${_dateFormat.format(expiry!)}',
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (staffId != null && selectedRole != null) {
                  if (selectedRole == AppRole.bartender && selectedBar == null) {
                    ErrorHandler.showWarningMessage(
                      dialogContext,
                      'Please select a bar for the bartender role',
                    );
                    return;
                  }
                  final roleToAssign = selectedRole == AppRole.bartender
                      ? (selectedBar == 'outside_bar'
                          ? AppRole.outside_bartender
                          : AppRole.vip_bartender)
                      : selectedRole!;
                  await _dataService.assignRoleToStaff(
                    staffId!,
                    roleToAssign.name,
                    isTemporary: isTemporary,
                    expiryDate: expiry,
                  );
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  _loadStaff();
                  if (!mounted) return;
                  ErrorHandler.showSuccessMessage(
                    context,
                    'Role assigned successfully',
                  );
                }
              },
              child: const Text('Assign'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showTransferRoleDialog(Map<String, dynamic> user) async {
    AppRole? selectedRole;
    String? selectedBar;

    await showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: const Text('Transfer Staff'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<AppRole>(
                decoration: const InputDecoration(labelText: 'New Role'),
                items: AppRole.values
                    .where((r) => r != AppRole.owner && r != AppRole.guest)
                    .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
                    .toList(),
                onChanged: (v) {
                  setDialogState(() {
                    selectedRole = v;
                    if (selectedRole != AppRole.bartender) {
                      selectedBar = null;
                    }
                  });
                },
              ),
              if (selectedRole == AppRole.bartender) ...[
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  decoration: const InputDecoration(labelText: 'Select Bar'),
                  initialValue: selectedBar,
                  items: const [
                    DropdownMenuItem(value: 'vip_bar', child: Text('VIP Bar')),
                    DropdownMenuItem(value: 'outside_bar', child: Text('Outside Bar')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedBar = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedRole == null) return;
                if (selectedRole == AppRole.bartender && selectedBar == null) {
                  ErrorHandler.showWarningMessage(
                    dialogContext,
                    'Please select a bar for the bartender role',
                  );
                  return;
                }
                final roleToAssign = selectedRole == AppRole.bartender
                    ? (selectedBar == 'outside_bar'
                        ? AppRole.outside_bartender
                        : AppRole.vip_bartender)
                    : selectedRole!;
                await _dataService.assignRoleToStaff(
                  user['id'] as String,
                  roleToAssign.name,
                  isTemporary: false,
                );
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                _loadStaff();
                if (!mounted) return;
                ErrorHandler.showSuccessMessage(
                  context,
                  'Transferred ${user['full_name']} to ${roleToAssign.name}',
                );
              },
              child: const Text('Transfer'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCreatePositionDialog() async {
    final nameController = TextEditingController();
    final benefitsController = TextEditingController();
    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Create New Position'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Position Name'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: benefitsController,
                decoration: const InputDecoration(
                  labelText: 'Benefits (comma separated)',
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              final positionName = InputSanitizer.sanitizeText(nameController.text.trim());
              final benefits = InputSanitizer.sanitizeDescription(benefitsController.text.trim());
              
              if (positionName.isEmpty) {
                if (dialogContext.mounted) {
                  ErrorHandler.showWarningMessage(
                    dialogContext,
                    'Please enter a position name',
                  );
                }
                return;
              }

              try {
                final authService = Provider.of<AuthService>(context, listen: false);
                final createdBy = authService.currentUser?.id;
                
                await _dataService.createPosition({
                  'name': positionName,
                  'benefits': benefits,
                  'created_by': createdBy,
                });
                
                if (!dialogContext.mounted) return;
                Navigator.pop(dialogContext);
                if (!mounted) return;
                ErrorHandler.showSuccessMessage(context, 'Position created successfully!');
                setState(() {});
              } catch (e, stackTrace) {
                if (kDebugMode) debugPrint('DEBUG create position: $e\n$stackTrace');
                if (!mounted) return;
                ErrorHandler.handleError(
                  context,
                  e,
                  customMessage: 'Failed to create position. Please try again.',
                  stackTrace: stackTrace,
                );
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  void _showSuspendDialog(Map<String, dynamic> staff) {
    final reasonController = TextEditingController();
    DateTime? suspensionEndDate;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.pause_circle, color: Colors.orange[700]),
              const SizedBox(width: 8),
              const Text('Suspend Staff'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Staff: ${staff['full_name'] ?? staff['name'] ?? 'Unknown'}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason for Suspension',
                    border: OutlineInputBorder(),
                    hintText: 'Enter reason...',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Suspension Period:',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final picked = await showDatePicker(
                            context: dialogContext,
                            initialDate: DateTime.now().add(
                              const Duration(days: 7),
                            ),
                            firstDate: DateTime.now(),
                            lastDate: DateTime.now().add(
                              const Duration(days: 365),
                            ),
                          );
                          if (picked != null) {
                            setDialogState(() => suspensionEndDate = picked);
                          }
                        },
                        icon: const Icon(Icons.calendar_today),
                        label: Text(
                          suspensionEndDate != null
                              ? DateFormat(
                                  'MMM dd, yyyy',
                                ).format(suspensionEndDate!)
                              : 'Select End Date',
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange[700],
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'Staff will not be able to log in during suspension period.',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonController.text.isEmpty) {
                  if (dialogContext.mounted) {
                    ErrorHandler.showWarningMessage(
                      dialogContext,
                      'Please provide a reason for suspension',
                    );
                  }
                  return;
                }
                if (suspensionEndDate == null) {
                  if (dialogContext.mounted) {
                    ErrorHandler.showWarningMessage(
                      dialogContext,
                      'Please select suspension end date',
                    );
                  }
                  return;
                }

                try {
                  await _dataService.updateStaffStatus(
                    staff['id'] as String,
                    'Suspended',
                  );
                  
                  
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (!mounted) return;
                  ErrorHandler.showSuccessMessage(
                    context,
                    '${staff['full_name'] ?? staff['name'] ?? 'Staff'} has been suspended until ${DateFormat('MMM dd, yyyy').format(suspensionEndDate!)}',
                  );
                  _loadStaff();
                } catch (e, stackTrace) {
                  if (kDebugMode) debugPrint('DEBUG suspend staff: $e\n$stackTrace');
                  if (!dialogContext.mounted) return;
                  Navigator.pop(dialogContext);
                  if (!mounted) return;
                  ErrorHandler.handleError(
                    context,
                    e,
                    customMessage: 'Failed to suspend staff. Please try again.',
                    stackTrace: stackTrace,
                  );
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange[700],
                foregroundColor: Colors.white,
              ),
              child: const Text('Suspend'),
            ),
          ],
        ),
      ),
    );
  }

  void _showTerminateDialog(Map<String, dynamic> staff) {
    final reasonController = TextEditingController();
    bool confirmTermination = false;
    bool isTerminating = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (_, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.person_remove, color: Colors.red[700]),
              const SizedBox(width: 8),
              const Text('Terminate Staff'),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red[200]!),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning, color: Colors.red[700], size: 24),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'WARNING: This action is permanent and cannot be undone!',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Staff: ${staff['full_name'] ?? staff['name'] ?? 'Unknown'}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  decoration: const InputDecoration(
                    labelText: 'Reason for Termination *',
                    border: OutlineInputBorder(),
                    hintText: 'Enter detailed reason...',
                  ),
                  maxLines: 4,
                ),
                const SizedBox(height: 16),
                CheckboxListTile(
                  value: confirmTermination,
                  onChanged: (val) {
                    setDialogState(() => confirmTermination = val ?? false);
                  },
                  title: const Text(
                    'I confirm that I want to terminate this staff member',
                    style: TextStyle(fontSize: 13),
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Effects of Termination:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 8),
                      _buildTerminationEffect(
                        'Account will be deactivated immediately',
                      ),
                      _buildTerminationEffect(
                        'Staff cannot log in to the system',
                      ),
                      _buildTerminationEffect('All access permissions revoked'),
                      _buildTerminationEffect('Record kept for audit purposes'),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: isTerminating ? null : () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: !isTerminating && confirmTermination && reasonController.text.isNotEmpty
                  ? () async {
                      setDialogState(() => isTerminating = true);
                      try {
                        await _dataService.updateStaffStatus(
                          staff['id'] as String,
                          'Terminated',
                        );
                        
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        ErrorHandler.showSuccessMessage(
                          context,
                          '${staff['full_name'] ?? staff['name'] ?? 'Staff'} has been terminated',
                        );
                        _loadStaff();
                      } catch (e, stackTrace) {
                        if (kDebugMode) debugPrint('DEBUG terminate staff: $e\n$stackTrace');
                        if (dialogContext.mounted) {
                          setDialogState(() => isTerminating = false);
                        }
                        if (!dialogContext.mounted) return;
                        Navigator.pop(dialogContext);
                        if (!mounted) return;
                        ErrorHandler.handleError(
                          context,
                          e,
                          customMessage: 'Failed to terminate staff. Please try again.',
                          stackTrace: stackTrace,
                        );
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
              ),
              child: isTerminating
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Terminate Staff'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTerminationEffect(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.red[700], size: 14),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }

  void _showHireNewStaffDialog() {
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    final guestSearchController = TextEditingController();
    String? selectedRole;
    String? selectedDepartment;
    bool isLoading = false;
    var hireFromGuest = false;
    var guestProfiles = <Map<String, dynamic>>[];
    var guestsLoaded = false;
    var guestsLoading = false;
    Map<String, dynamic>? selectedGuest;
    int? outstandingKobo;
    var outstandingLoading = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (dialogCtx2, setDialogState) {
          Future<void> loadGuestList() async {
            setDialogState(() => guestsLoading = true);
            try {
              guestProfiles = await _dataService.getGuestProfilesForHiring();
              guestsLoaded = true;
            } catch (e) {
              guestProfiles = [];
              if (dialogCtx2.mounted) {
                ErrorHandler.handleError(
                  dialogCtx2,
                  e,
                  customMessage: 'Could not load guest accounts',
                );
              }
            } finally {
              setDialogState(() => guestsLoading = false);
            }
          }

          Future<void> loadOutstanding(String profileId) async {
            setDialogState(() {
              outstandingLoading = true;
              outstandingKobo = null;
            });
            try {
              outstandingKobo = await _dataService.getGuestOutstandingBalanceKobo(profileId);
            } catch (_) {
              outstandingKobo = null;
            } finally {
              setDialogState(() => outstandingLoading = false);
            }
          }

          String formatOutstanding(int kobo) {
            final naira = PaymentService.koboToNaira(kobo);
            final formatted = NumberFormat('#,##0.00', 'en_NG').format(naira);
            return '₦$formatted';
          }

          List<Map<String, dynamic>> filteredGuests() {
            final q = guestSearchController.text.trim().toLowerCase();
            if (q.isEmpty) {
              return guestProfiles.length <= 80
                  ? List<Map<String, dynamic>>.from(guestProfiles)
                  : guestProfiles.take(80).toList();
            }
            return guestProfiles
                .where((g) {
                  final n = (g['full_name'] ?? '').toString().toLowerCase();
                  final e = (g['email'] ?? '').toString().toLowerCase();
                  final p = (g['phone'] ?? '').toString().toLowerCase();
                  return n.contains(q) || e.contains(q) || p.contains(q);
                })
                .take(100)
                .toList();
          }

          void disposeHireControllers() {
            fullNameController.dispose();
            emailController.dispose();
            phoneController.dispose();
            guestSearchController.dispose();
          }

          String deptLabel(String? d) =>
              (d == null || d.isEmpty) ? 'Unassigned' : d.replaceAll('_', ' ');

          return AlertDialog(
          title: Row(
            children: [
              Icon(Icons.person_add, color: Colors.green[700]),
              const SizedBox(width: 8),
              const Text('Hire New Staff'),
            ],
          ),
          content: SingleChildScrollView(
            child: SizedBox(
              width: 500,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Existing guest?'),
                    subtitle: const Text(
                      'Convert a guest account to staff — same login, no duplicate identity.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: hireFromGuest,
                    onChanged: (v) {
                      setDialogState(() {
                        hireFromGuest = v;
                        if (v) {
                          selectedGuest = null;
                          outstandingKobo = null;
                          if (!guestsLoaded && !guestsLoading) {
                            loadGuestList();
                          }
                        }
                      });
                    },
                  ),
                  const Divider(height: 24),
                  if (!hireFromGuest)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.blue[200]!),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.info_outline,
                            color: Colors.blue[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          const Expanded(
                            child: Text(
                              'A new account would be created, and a temporary password is generated to share with the new staff.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (hireFromGuest) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.amber.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.verified_user, color: Colors.amber.shade800, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Selected guest keeps their current password and email login. Staff access applies after their next session refresh.',
                              style: TextStyle(fontSize: 12, color: Colors.brown.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (guestsLoading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else ...[
                      TextField(
                        controller: guestSearchController,
                        decoration: InputDecoration(
                          labelText: 'Search guests (name, email, phone)',
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.search),
                          suffixText: '${filteredGuests().length} match(es)',
                        ),
                        onChanged: (_) => setDialogState(() {}),
                      ),
                      const SizedBox(height: 8),
                      DropdownButtonFormField<String>(
                        key: ValueKey<String?>(selectedGuest?['id']?.toString()),
                        initialValue: selectedGuest?['id']?.toString(),
                        decoration: const InputDecoration(
                          labelText: 'Select guest *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person_search),
                        ),
                        items: filteredGuests()
                            .map(
                              (g) => DropdownMenuItem<String>(
                                value: g['id']?.toString(),
                                child: Text(
                                  '${g['full_name'] ?? 'Guest'} — ${g['email'] ?? ''}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (id) {
                          if (id == null) {
                            setDialogState(() {
                              selectedGuest = null;
                              outstandingKobo = null;
                            });
                            return;
                          }
                          final found =
                              guestProfiles.where((e) => e['id']?.toString() == id).toList();
                          final g = found.isEmpty ? null : found.first;
                          setDialogState(() => selectedGuest = g);
                          if (g != null) {
                            loadOutstanding(g['id'].toString());
                          }
                        },
                      ),
                      if (selectedGuest != null) ...[
                        const SizedBox(height: 16),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color(0xFFF5F5F5),
                          ),
                          child: Text(
                            selectedGuest!['full_name']?.toString() ?? '—',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Email',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color(0xFFF5F5F5),
                          ),
                          child: Text(selectedGuest!['email']?.toString() ?? '—'),
                        ),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Phone',
                            border: OutlineInputBorder(),
                            filled: true,
                            fillColor: Color(0xFFF5F5F5),
                          ),
                          child: Text(selectedGuest!['phone']?.toString().trim().isNotEmpty == true
                              ? selectedGuest!['phone'].toString()
                              : '—'),
                        ),
                        if (outstandingLoading)
                          const Padding(
                            padding: EdgeInsets.only(top: 12),
                            child: LinearProgressIndicator(),
                          )
                        else if (outstandingKobo != null && outstandingKobo! > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Material(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(Icons.warning_amber_rounded, color: Colors.orange.shade800),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Note: This guest has an outstanding balance of ${formatOutstanding(outstandingKobo!)}.',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.orange.shade900,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ],
                  ],
                  if (!hireFromGuest) ...[
                    const SizedBox(height: 16),
                    TextField(
                      controller: fullNameController,
                      decoration: const InputDecoration(
                        labelText: 'Full Name *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email *',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                        hintText: 'staff@pzed.home',
                      ),
                      keyboardType: TextInputType.emailAddress,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: phoneController,
                      decoration: const InputDecoration(
                        labelText: 'Phone Number',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.phone),
                      ),
                      keyboardType: TextInputType.phone,
                    ),
                  ],
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    key: ValueKey<String?>(selectedRole),
                    initialValue: selectedRole,
                    decoration: const InputDecoration(
                      labelText: 'Assign Role *',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.work),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'manager',
                        child: Text('Manager'),
                      ),
                      DropdownMenuItem(
                        value: 'supervisor',
                        child: Text('Supervisor'),
                      ),
                      DropdownMenuItem(
                        value: 'accountant',
                        child: Text('Accountant'),
                      ),
                      DropdownMenuItem(value: 'hr', child: Text('HR')),
                      DropdownMenuItem(
                        value: 'receptionist',
                        child: Text('Receptionist'),
                      ),
                      DropdownMenuItem(
                        value: 'vip_bartender',
                        child: Text('VIP Bar Bartender'),
                      ),
                      DropdownMenuItem(
                        value: 'outside_bartender',
                        child: Text('Outside Bar Bartender'),
                      ),
                      DropdownMenuItem(
                        value: 'kitchen_staff',
                        child: Text('Kitchen Staff'),
                      ),
                      DropdownMenuItem(
                        value: 'housekeeper',
                        child: Text('Housekeeper'),
                      ),
                      DropdownMenuItem(
                        value: 'porter',
                        child: Text('Porter'),
                      ),
                      DropdownMenuItem(
                        value: 'cleaner',
                        child: Text('Cleaner'),
                      ),
                      DropdownMenuItem(
                        value: 'laundry_attendant',
                        child: Text('Laundry Attendant'),
                      ),
                      DropdownMenuItem(
                        value: 'security',
                        child: Text('Security'),
                      ),
                      DropdownMenuItem(
                        value: 'purchaser',
                        child: Text('Purchaser'),
                      ),
                      DropdownMenuItem(
                        value: 'storekeeper',
                        child: Text('Storekeeper'),
                      ),
                    ],
                    onChanged: (val) {
                      setDialogState(() => selectedRole = val);
                    },
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String?>(
                    key: ValueKey<String?>(selectedDepartment),
                    initialValue: selectedDepartment,
                    decoration: const InputDecoration(
                      labelText: 'Department (optional)',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                    items: const [
                      DropdownMenuItem<String?>(value: null, child: Text('None')),
                      DropdownMenuItem<String?>(value: 'reception', child: Text('Reception')),
                      DropdownMenuItem<String?>(value: 'kitchen', child: Text('Kitchen')),
                      DropdownMenuItem<String?>(value: 'housekeeping', child: Text('Housekeeping')),
                      DropdownMenuItem<String?>(value: 'finance', child: Text('Finance')),
                      DropdownMenuItem<String?>(value: 'hr', child: Text('HR')),
                      DropdownMenuItem<String?>(value: 'security', child: Text('Security')),
                      DropdownMenuItem<String?>(value: 'maintenance', child: Text('Maintenance')),
                      DropdownMenuItem<String?>(value: 'laundry', child: Text('Laundry')),
                      DropdownMenuItem<String?>(value: 'purchasing', child: Text('Purchasing')),
                      DropdownMenuItem<String?>(value: 'storeroom', child: Text('Storeroom')),
                    ],
                    onChanged: (val) => setDialogState(() => selectedDepartment = val),
                  ),
                  if (!hireFromGuest) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Staff will receive:',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                          const SizedBox(height: 8),
                          _buildStaffBenefit('Access to assigned role features'),
                          _buildStaffBenefit('A secure temporary password to share'),
                          _buildStaffBenefit(
                            'Must change password on first login',
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: isLoading
                  ? null
                  : () {
                      disposeHireControllers();
                      Navigator.pop(dialogCtx2);
                    },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                if (selectedRole == null) {
                  if (dialogCtx2.mounted) {
                    ErrorHandler.showWarningMessage(
                      dialogCtx2,
                      'Please select a role',
                    );
                  }
                  return;
                }
                if (hireFromGuest) {
                  if (selectedGuest == null) {
                    if (dialogCtx2.mounted) {
                      ErrorHandler.showWarningMessage(
                        dialogCtx2,
                        'Please select a guest to convert',
                      );
                    }
                    return;
                  }
                } else {
                  if (fullNameController.text.trim().isEmpty) {
                    if (dialogCtx2.mounted) {
                      ErrorHandler.showWarningMessage(
                        dialogCtx2,
                        'Please enter full name',
                      );
                    }
                    return;
                  }
                  if (emailController.text.trim().isEmpty) {
                    if (dialogCtx2.mounted) {
                      ErrorHandler.showWarningMessage(
                        dialogCtx2,
                        'Please enter email',
                      );
                    }
                    return;
                  }
                }

                final staffRole = selectedRole!;
                final dept = selectedDepartment?.trim();
                final deptStr = dept != null && dept.isNotEmpty ? dept : null;

                final guestName = hireFromGuest
                    ? (selectedGuest!['full_name'] ?? 'Guest').toString()
                    : fullNameController.text.trim();

                final confirmed = await showDialog<bool>(
                  context: dialogCtx2,
                  builder: (confirmCtx) => AlertDialog(
                    title: const Text('Confirm hire'),
                    content: Text(
                      hireFromGuest
                          ? 'You are converting $guestName to ${staffRole.replaceAll('_', ' ')} in ${deptLabel(deptStr)}. They will keep their existing login credentials.'
                          : 'You are creating a new staff account for $guestName as ${staffRole.replaceAll('_', ' ')} in ${deptLabel(deptStr)}. A temporary password will be shown after success.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(confirmCtx, false),
                        child: const Text('Back'),
                      ),
                      ElevatedButton(
                        onPressed: () => Navigator.pop(confirmCtx, true),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[700],
                          foregroundColor: Colors.white,
                        ),
                        child: const Text('Confirm'),
                      ),
                    ],
                  ),
                );
                if (confirmed != true) return;

                if (!mounted) return;
                setDialogState(() => isLoading = true);
                try {
                  final authService = Provider.of<AuthService>(context, listen: false);
                  final currentUser = authService.currentUser;

                  if (currentUser?.role != AppRole.owner &&
                      currentUser?.role != AppRole.hr &&
                      currentUser?.role != AppRole.manager) {
                    throw Exception('Only owner, HR manager, or manager can create staff profiles');
                  }

                  if (hireFromGuest) {
                    final g = selectedGuest!;
                    final staffEmail = InputSanitizer.sanitizeEmail(
                      (g['email'] ?? '').toString().trim(),
                    );
                    final staffName = InputSanitizer.sanitizeText(
                      (g['full_name'] ?? '').toString().trim(),
                    );
                    final staffPhone = (g['phone'] ?? '').toString().trim().isEmpty
                        ? null
                        : InputSanitizer.sanitizePhone(g['phone'].toString().trim());
                    final profileId = g['id'] as String?;

                    if (staffEmail.isEmpty || !staffEmail.contains('@')) {
                      throw Exception('Guest profile has no valid email');
                    }
                    if (staffName.isEmpty) {
                      throw Exception('Guest profile has no name');
                    }
                    if (profileId == null || profileId.isEmpty) {
                      throw Exception('Invalid guest profile');
                    }

                    await _dataService.createStaffProfile(
                      email: staffEmail,
                      password: '-',
                      fullName: staffName,
                      role: staffRole,
                      phone: staffPhone,
                      department: deptStr,
                      userId: profileId,
                    );

                    disposeHireControllers();
                    if (dialogCtx2.mounted) Navigator.pop(dialogCtx2);

                    if (!mounted) return;
                    showDialog<void>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: Row(
                            children: [
                              Icon(Icons.check_circle, color: Colors.green[700], size: 28),
                              const SizedBox(width: 8),
                              const Expanded(child: Text('Guest converted to staff')),
                            ],
                          ),
                          content: Text(
                            '$guestName is now ${staffRole.replaceAll('_', ' ')} (${deptLabel(deptStr)}). They keep the same login; staff menus apply after they refresh or sign in again.',
                          ),
                          actions: [
                            ElevatedButton(
                              onPressed: () => Navigator.pop(ctx),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green[700],
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('OK'),
                            ),
                          ],
                        ),
                      );
                    _loadStaff();
                    return;
                  }

                  final staffName = InputSanitizer.sanitizeText(fullNameController.text.trim());
                  final staffEmail = InputSanitizer.sanitizeEmail(emailController.text.trim());
                  final staffPhone = phoneController.text.trim().isEmpty
                      ? null
                      : InputSanitizer.sanitizePhone(phoneController.text.trim());

                  if (staffName.isEmpty) {
                    throw Exception('Staff name cannot be empty');
                  }
                  if (staffEmail.isEmpty || !staffEmail.contains('@')) {
                    throw Exception('Please enter a valid email address');
                  }

                  final securePassword = _generateSecurePassword();

                  final supabase = Supabase.instance.client;
                  final currentUserSession = supabase.auth.currentSession;
                  final currentUserRefreshToken = currentUserSession?.refreshToken;

                  if (currentUserRefreshToken == null) {
                    throw Exception('Unable to save current session. Please log in again.');
                  }

                  authService.setCreatingStaffAccount(true);

                  String? userId;

                  try {
                    final signUpResponse = await supabase.auth.signUp(
                      email: staffEmail,
                      password: securePassword,
                      data: {
                        'full_name': staffName,
                      },
                    );

                    if (signUpResponse.user == null) {
                      throw Exception('Failed to create user account');
                    }

                    userId = signUpResponse.user!.id;

                    await Future.delayed(const Duration(milliseconds: 1000));

                    await supabase.auth.setSession(currentUserRefreshToken);

                    await Future.delayed(const Duration(milliseconds: 500));

                    await _dataService.createStaffProfile(
                      email: staffEmail,
                      password: securePassword,
                      fullName: staffName,
                      role: staffRole,
                      phone: staffPhone,
                      department: deptStr,
                      userId: userId,
                    );
                  } catch (profileError) {
                    try {
                      await supabase.auth.setSession(currentUserRefreshToken);
                      await Future.delayed(const Duration(milliseconds: 1000));

                      await _dataService.createStaffProfile(
                        email: staffEmail,
                        password: securePassword,
                        fullName: staffName,
                        role: staffRole,
                        phone: staffPhone,
                        department: deptStr,
                        userId: userId!,
                      );
                    } catch (retryError) {
                      try {
                        await supabase.auth.setSession(currentUserRefreshToken);
                      } catch (_) {}
                      if (kDebugMode) {
                        debugPrint('DEBUG createStaffProfile retry failed: $profileError\n$retryError');
                      }
                      rethrow;
                    }
                  } finally {
                    authService.setCreatingStaffAccount(false);

                    final finalSession = supabase.auth.currentSession;
                    if (finalSession == null || finalSession.user.id != currentUserSession?.user.id) {
                      try {
                        await supabase.auth.setSession(currentUserRefreshToken);
                      } catch (e, stack) {
                        if (kDebugMode) debugPrint('DEBUG session restore: $e\n$stack');
                        if (mounted) {
                          ErrorHandler.showWarningMessage(
                            context,
                            'Please log in again to continue. Your session was reset during staff creation.',
                          );
                        }
                      }
                    }
                  }

                  disposeHireControllers();

                  if (!dialogCtx2.mounted) return;
                  Navigator.pop(dialogCtx2);
                  if (!mounted) return;
                  showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (successCtx) => AlertDialog(
                        title: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.green[700], size: 28),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('Staff Account Created Successfully'),
                            ),
                          ],
                        ),
                        content: SingleChildScrollView(
                          child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                              Text(
                                '$staffName has been hired as ${staffRole.replaceAll('_', ' ').toUpperCase()}',
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              const SizedBox(height: 24),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.grey[100],
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.grey[300]!),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Icon(Icons.lock, size: 16, color: Colors.grey[700]),
                                        const SizedBox(width: 4),
                            const Text(
                              'Temporary Password:',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              securePassword,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                        fontSize: 18,
                                fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                  ],
                              ),
                            ),
                            const SizedBox(height: 16),
                              Container(
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.blue[50],
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline, color: Colors.blue[700], size: 20),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Please copy or screenshot this password and share it securely with the staff member.',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.blue[900],
                                        ),
                                      ),
                            ),
                          ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        actions: [
                          TextButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(ClipboardData(text: securePassword));
                              if (!successCtx.mounted) return;
                              ScaffoldMessenger.of(successCtx).showSnackBar(
                                const SnackBar(
                                  content: Text('Password copied to clipboard'),
                                  duration: Duration(seconds: 2),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy Password'),
                          ),
                          ElevatedButton(
                            onPressed: () {
                              Navigator.pop(successCtx);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green[700],
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                    _loadStaff();
                } catch (e, stackTrace) {
                  if (kDebugMode) debugPrint('DEBUG create staff account: $e\n$stackTrace');
                  setDialogState(() => isLoading = false);
                  if (mounted) {
                    String errorMsg = 'Failed to create staff account';
                    final errorString = e.toString().toLowerCase();

                    if (errorString.contains('already registered') ||
                        errorString.contains('already exists') ||
                        errorString.contains('user already registered')) {
                      errorMsg = 'Email address is already registered. Use hire from guest, or another email.';
                    } else if (errorString.contains('invalid email') ||
                        errorString.contains('email format')) {
                      errorMsg = 'Invalid email format. Please enter a valid email address.';
                    } else if (errorString.contains('network') ||
                        errorString.contains('connection') ||
                        errorString.contains('timeout')) {
                      errorMsg = 'Network connection error. Please check your internet connection and try again.';
                    } else if (errorString.contains('database') ||
                        errorString.contains('supabase')) {
                      errorMsg = 'Something went wrong. Please try again.';
                    } else if (errorString.contains('profile') ||
                        errorString.contains('createstaffprofile')) {
                      errorMsg = 'Failed to update staff profile. Please verify all information and try again.';
                    } else if (errorString.contains('only owner') || errorString.contains('Only owner')) {
                      errorMsg = 'Only owner, HR, or manager can create staff profiles';
                    } else {
                      errorMsg = ErrorHandler.getFriendlyErrorMessage(e);
                    }

                    ErrorHandler.handleError(
                      context,
                      e,
                      customMessage: errorMsg,
                      stackTrace: stackTrace,
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[700],
                foregroundColor: Colors.white,
              ),
              child: isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Text('Hire Staff'),
            ),
          ],
        );
      },
      ),
    );
  }

  Widget _buildStaffBenefit(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.green[700], size: 14),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 11))),
        ],
      ),
    );
  }
}


