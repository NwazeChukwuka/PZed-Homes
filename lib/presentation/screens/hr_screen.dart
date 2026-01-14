import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/utils/input_sanitizer.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/config/app_config.dart';
import 'package:pzed_homes/data/models/user.dart';
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

  // State
  List<Map<String, dynamic>> _allStaff = [];
  List<Map<String, dynamic>> _filteredStaff = [];
  DateTime _selectedDate = DateTime.now();
  bool _isLoading = true;
  String _searchQuery = '';
  List<Map<String, dynamic>> _attendanceRecords = [];
  Map<String, dynamic>? _performanceMetrics;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
    ); // Staff, Duty, Attendance, Performance, Roles/Positions
    _loadStaff();
    _loadAttendanceRecords();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  /// Generate a secure random password with "Pzed" prefix
  String _generateSecurePassword() {
    const prefix = 'Pzed';
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
    final random = Random.secure();
    final suffix = StringBuffer();
    
    // Generate 8 random characters
    for (int i = 0; i < 8; i++) {
      suffix.write(chars[random.nextInt(chars.length)]);
    }
    
    return '$prefix$suffix';
  }

  /// Get the password reset URL for the app
  /// Uses centralized configuration from AppConfig
  String _getPasswordResetUrl() {
    return AppConfig.passwordResetUrl;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: Column(
        children: [
          _buildHeader(context),
          Container(
            color: Colors.white,
            child: TabBar(
              controller: _tabController,
              labelColor: Colors.green[800],
              unselectedLabelColor: Colors.grey[600],
              indicatorColor: Colors.green[800],
              isScrollable: true,
              tabs: const [
                Tab(text: 'Staff Directory', icon: Icon(Icons.people_alt)),
                Tab(text: 'Duty Roster', icon: Icon(Icons.event_available)),
                Tab(text: 'Attendance', icon: Icon(Icons.access_time)),
                Tab(text: 'Performance', icon: Icon(Icons.assessment)),
                Tab(
                  text: 'Roles & Positions',
                  icon: Icon(Icons.admin_panel_settings),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStaffDirectoryTab(context),
                _buildDutyRosterTab(context),
                _buildAttendanceTab(context),
                _buildPerformanceTab(context),
                _buildRolesPositionsTab(context),
              ],
            ),
          ),
        ],
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
            color: Colors.black.withOpacity(0.05),
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
                  'Staff directory, duty roster, performance, roles and positions',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.green[50],
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green[200]!),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.people, color: Colors.green[700], size: 16),
                const SizedBox(width: 8),
                Text(
                  'User Management',
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Load attendance records
  Future<void> _loadAttendanceRecords() async {
    try {
      final records = await _dataService.getAttendanceRecords();
      if (mounted) {
        setState(() {
          _attendanceRecords = records;
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }

  // ---------- Staff Directory ----------
  Future<void> _loadStaff() async {
    setState(() => _isLoading = true);
    try {
      final staff = await _dataService.getStaffProfiles();
      // Exclude owner
      final filtered = staff.where((s) {
        final roles = (s['roles'] as List<dynamic>? ?? [])
            .map((e) => e.toString())
            .toList();
        return !roles.contains('owner');
      }).toList();
      setState(() {
        _allStaff = filtered;
        _applySearchFilter();
        _isLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage:
              'Failed to load staff. Please check your connection and try again.',
          onRetry: _loadStaff,
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
              // Owner and manager can hire new staff
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
                            final isOwner =
                                authService.currentUser?.role == AppRole.owner;

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
                              // Only owner can terminate
                              if (isOwner)
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

  // ---------- Duty Roster ----------
  Widget _buildDutyRosterTab(BuildContext context) {
    // Load attendance records for selected date
    final selectedDateStr = _selectedDate.toIso8601String().split('T')[0];
    final onDuty = _attendanceRecords.where((record) {
      final recordDate = record['date'] as String?;
      if (recordDate == null) return false;
      final recordDateStr = recordDate.split('T')[0];
      return recordDateStr == selectedDateStr && record['clock_out_time'] == null;
    }).toList();
    
    // Get staff IDs who are on duty
    final onDutyStaffIds = onDuty.map((r) => r['profile_id'] as String).toSet();
    
    // Filter staff who are on duty
    final onDutyStaff = _allStaff.where((staff) {
      return onDutyStaffIds.contains(staff['id'] as String);
    }).toList();

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Text('Date:  ${_dateFormat.format(_selectedDate)}'),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    initialDate: _selectedDate,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(2035),
                  );
                  if (picked != null) setState(() => _selectedDate = picked);
                },
                icon: const Icon(Icons.calendar_today),
                label: const Text('Pick Date'),
              ),
              const Spacer(),
              Text('${onDutyStaff.length} on duty'),
            ],
          ),
        ),
        Expanded(
          child: onDutyStaff.isEmpty
              ? const Center(child: Text('No staff on duty for selected date'))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: onDutyStaff.length,
                  itemBuilder: (context, i) {
                    final u = onDutyStaff[i];
              final roles = (u['roles'] as List<dynamic>? ?? []).join(', ');
              final staffId = u['id'] as String;
              final attendanceRecord = onDuty.firstWhere(
                (r) => r['profile_id'] == staffId,
                orElse: () => <String, dynamic>{},
              );
              final clockInTime = attendanceRecord['clock_in_time'] as String?;
              final clockIn = clockInTime != null 
                  ? DateTime.parse(clockInTime)
                  : null;
              
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.badge),
                  title: Text(u['full_name']?.toString() ?? 'Unnamed'),
                  subtitle: Text(
                    'Roles: $roles\nClocked in: ${clockIn != null ? DateFormat('HH:mm').format(clockIn) : 'N/A'}',
                  ),
                  isThreeLine: true,
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ---------- Performance ----------
  Widget _buildPerformanceTab(BuildContext context) {
    // Load performance metrics if not loaded
    if (_performanceMetrics == null) {
      _loadPerformanceMetrics();
    }
    
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpiCard(
                'Today Attendance', 
                _performanceMetrics?['today_attendance']?.toString() ?? '0', 
                Colors.green
              ),
              _kpiCard(
                'This Week', 
                _performanceMetrics?['week_attendance']?.toString() ?? '0', 
                Colors.blue
              ),
              _kpiCard(
                'This Month', 
                _performanceMetrics?['month_attendance']?.toString() ?? '0', 
                Colors.purple
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('Top Performers', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          _buildTopPerformers(),
        ],
      ),
    );
  }
  
  Future<void> _loadPerformanceMetrics() async {
    try {
      final now = DateTime.now();
      final today = now.toIso8601String().split('T')[0];
      final weekAgo = now.subtract(const Duration(days: 7)).toIso8601String().split('T')[0];
      final monthAgo = now.subtract(const Duration(days: 30)).toIso8601String().split('T')[0];
      
      final attendanceRecords = await _dataService.getAttendanceRecords();
      
      final todayCount = attendanceRecords.where((r) {
        final date = r['date'] as String?;
        return date != null && date.startsWith(today);
      }).length;
      
      final weekCount = attendanceRecords.where((r) {
        final date = r['date'] as String?;
        if (date == null) return false;
        // Compare date strings (ISO format can be compared lexicographically)
        final dateStr = date.split('T')[0];
        return dateStr.compareTo(weekAgo) >= 0;
      }).length;
      
      final monthCount = attendanceRecords.where((r) {
        final date = r['date'] as String?;
        if (date == null) return false;
        // Compare date strings (ISO format can be compared lexicographically)
        final dateStr = date.split('T')[0];
        return dateStr.compareTo(monthAgo) >= 0;
      }).length;
      
      if (mounted) {
        setState(() {
          _performanceMetrics = {
            'today_attendance': todayCount,
            'week_attendance': weekCount,
            'month_attendance': monthCount,
          };
        });
      }
    } catch (e) {
      // Handle error silently
    }
  }
  
  Widget _buildTopPerformers() {
    // Calculate attendance count per staff member
    final staffAttendanceCount = <String, int>{};
    
    for (var record in _attendanceRecords) {
      final staffId = record['profile_id'] as String?;
      if (staffId != null) {
        staffAttendanceCount[staffId] = (staffAttendanceCount[staffId] ?? 0) + 1;
      }
    }
    
    // Sort staff by attendance count
    final sortedStaff = _allStaff.toList()
      ..sort((a, b) {
        final aId = a['id'] as String;
        final bId = b['id'] as String;
        final aCount = staffAttendanceCount[aId] ?? 0;
        final bCount = staffAttendanceCount[bId] ?? 0;
        return bCount.compareTo(aCount);
      });
    
    return Column(
      children: sortedStaff.take(5).map((u) {
        final staffId = u['id'] as String;
        final attendanceCount = staffAttendanceCount[staffId] ?? 0;
        return ListTile(
          leading: const Icon(Icons.emoji_events, color: Colors.amber),
          title: Text(u['full_name']?.toString() ?? 'Unnamed'),
          subtitle: Text('$attendanceCount attendance records this month'),
        );
      }).toList(),
    );
  }

  Widget _kpiCard(String label, String value, Color color) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              const SizedBox(width: 6),
              const Text('/ 100'),
            ],
          ),
        ],
      ),
    );
  }

  // ---------- Roles & Positions ----------
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

  // ---------- Dialogs / Actions ----------
  Future<void> _showPromoteDemoteDialog(
    Map<String, dynamic> user, {
    required bool isPromote,
  }) async {
    final roles = (user['roles'] as List<dynamic>? ?? [])
        .map((e) => e.toString())
        .toList();
    final available = AppRole.values
        .where((r) => r != AppRole.owner && r != AppRole.guest)
        .toList();
    AppRole? selected;
    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(isPromote ? 'Promote Staff' : 'Demote Staff'),
        content: DropdownButtonFormField<AppRole>(
          decoration: const InputDecoration(labelText: 'Select Role'),
          items: available
              .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
              .toList(),
          onChanged: (v) => selected = v,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (selected != null) {
                await _dataService.assignRoleToStaff(
                  user['id'] as String,
                  selected!.name,
                  isTemporary: false,
                );
                if (!mounted) return;
                Navigator.pop(context);
                _loadStaff();
                if (mounted) {
                  ErrorHandler.showSuccessMessage(
                    context,
                    'Updated role to ${selected!.name} for ${user['full_name']}',
                  );
                }
              }
            },
            child: Text(isPromote ? 'Promote' : 'Demote'),
          ),
        ],
      ),
    );
  }

  Future<void> _showAssignRoleDialog(Map<String, dynamic>? user) async {
    String? staffId = user?['id'] as String?;
    AppRole? selectedRole;
    bool isTemporary = false;
    DateTime? expiry;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
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
                  onChanged: (v) => selectedRole = v,
                ),
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (staffId != null && selectedRole != null) {
                  await _dataService.assignRoleToStaff(
                    staffId!,
                    selectedRole!.name,
                    isTemporary: isTemporary,
                    expiryDate: expiry,
                  );
                  if (!mounted) return;
                  Navigator.pop(context);
                  _loadStaff();
                  if (mounted) {
                    ErrorHandler.showSuccessMessage(
                      context,
                      'Role assigned successfully',
                    );
                  }
                }
              },
              child: const Text('Assign'),
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
      builder: (context) => AlertDialog(
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
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Sanitize position inputs
              final positionName = InputSanitizer.sanitizeText(nameController.text.trim());
              final benefits = InputSanitizer.sanitizeDescription(benefitsController.text.trim());
              
              if (positionName.isEmpty) {
                if (mounted) {
                  ErrorHandler.showWarningMessage(
                    context,
                    'Please enter a position name',
                  );
                }
                return;
              }

              try {
                // Store position in database
                final authService = Provider.of<AuthService>(context, listen: false);
                final createdBy = authService.currentUser?.id;
                
                await _dataService.createPosition({
                  'name': positionName,
                  'benefits': benefits,
                  'created_by': createdBy,
                });
                
                Navigator.pop(context);
                if (mounted) {
                  ErrorHandler.showSuccessMessage(context, 'Position created successfully!');
                  // Reload positions if needed
                  setState(() {});
                }
              } catch (e) {
                if (mounted) {
                  ErrorHandler.handleError(
                    context,
                    e,
                    customMessage: 'Failed to create position. Please try again.',
                  );
                }
              }
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

  // Attendance Tab - Shows who's clocked in and their transactions
  Widget _buildAttendanceTab(BuildContext context) {
    final startDate = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
    final endDate = startDate.add(const Duration(days: 1));
    
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dataService.getAttendanceRecords(
        startDate: startDate,
        endDate: endDate,
      ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        
        if (snapshot.hasError) {
          return ErrorHandler.buildErrorWidget(
            context,
            snapshot.error,
            message: 'Failed to load attendance records',
          );
        }
        
        final attendanceRecords = snapshot.data ?? [];
        
        // Filter by selected date
        final filteredRecords = attendanceRecords.where((record) {
          final clockInTime = DateTime.tryParse(record['clock_in_time']?.toString() ?? '');
          if (clockInTime == null) return false;
          final recordDate = DateTime(
            clockInTime.year,
            clockInTime.month,
            clockInTime.day,
          );
          final selectedDay = DateTime(
            _selectedDate.year,
            _selectedDate.month,
            _selectedDate.day,
          );
          return recordDate == selectedDay;
        }).toList();

        // Separate clocked in vs clocked out
        final clockedIn = filteredRecords
            .where((r) => r['clock_out_time'] == null)
            .toList();
        final clockedOut = filteredRecords
            .where((r) => r['clock_out_time'] != null)
            .toList();

        return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Date selector
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.calendar_today, color: Colors.green[700]),
                  const SizedBox(width: 12),
                  Text(
                    'Viewing: ${_dateFormat.format(_selectedDate)}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton.icon(
                    onPressed: () async {
                      final picked = await showDatePicker(
                        context: context,
                        initialDate: _selectedDate,
                        firstDate: DateTime(2020),
                        lastDate: DateTime.now(),
                      );
                      if (picked != null) {
                        setState(() => _selectedDate = picked);
                      }
                    },
                    icon: const Icon(Icons.edit_calendar),
                    label: const Text('Change Date'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[700],
                      foregroundColor: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Summary cards
          Row(
            children: [
              Expanded(
                child: _buildAttendanceSummaryCard(
                  'Currently Clocked In',
                  '${clockedIn.length}',
                  Icons.login,
                  Colors.green,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildAttendanceSummaryCard(
                  'Clocked Out',
                  '${clockedOut.length}',
                  Icons.logout,
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: _buildAttendanceSummaryCard(
                  'Total Staff',
                  '${filteredRecords.length}',
                  Icons.people,
                  Colors.purple,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          // Clocked In Staff
          if (clockedIn.isNotEmpty) ...[
            Text(
              'Currently Clocked In',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.green[800],
              ),
            ),
            const SizedBox(height: 12),
            ...clockedIn.map((record) => _buildAttendanceCard(record, true)),
            const SizedBox(height: 24),
          ],

          // Clocked Out Staff
          if (clockedOut.isNotEmpty) ...[
            Text(
              'Clocked Out',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: Colors.blue[800],
              ),
            ),
            const SizedBox(height: 12),
            ...clockedOut.map((record) => _buildAttendanceCard(record, false)),
          ],

          if (filteredRecords.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(48),
                child: Column(
                  children: [
                    Icon(Icons.event_busy, size: 64, color: Colors.grey[400]),
                    const SizedBox(height: 16),
                    Text(
                      'No attendance records for this date',
                      style: TextStyle(color: Colors.grey[600], fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
      },
    );
  }

  Widget _buildAttendanceSummaryCard(
    String title,
    String value,
    IconData icon,
    Color color,
  ) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String? _getStaffRole(Map<String, dynamic> record) {
    final profiles = record['profiles'] as Map<String, dynamic>?;
    if (profiles != null) {
      final roles = profiles['roles'] as List<dynamic>?;
      if (roles != null && roles.isNotEmpty) {
        return roles.first.toString();
      }
    }
    return record['staff_role']?.toString();
  }

  Widget _buildAttendanceCard(Map<String, dynamic> record, bool isClockedIn) {
    final clockInTimeStr = record['clock_in_time']?.toString();
    final clockInTime = clockInTimeStr != null ? DateTime.tryParse(clockInTimeStr) : null;
    final clockOutTimeStr = record['clock_out_time']?.toString();
    final clockOutTime = clockOutTimeStr != null ? DateTime.tryParse(clockOutTimeStr) : null;

    Duration? duration;
    if (clockInTime != null && clockOutTime != null) {
      duration = clockOutTime.difference(clockInTime);
    } else if (clockInTime != null && isClockedIn) {
      duration = DateTime.now().difference(clockInTime);
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ExpansionTile(
        leading: CircleAvatar(
          backgroundColor: isClockedIn ? Colors.green[100] : Colors.blue[100],
          child: Icon(
            isClockedIn ? Icons.check_circle : Icons.access_time,
            color: isClockedIn ? Colors.green[700] : Colors.blue[700],
          ),
        ),
        title: Text(
          (record['profiles'] as Map<String, dynamic>?)?['full_name'] ?? 
          record['staff_name'] ?? 
          'Unknown',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Role: ${_getStaffRole(record) ?? 'Unknown'}'),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(Icons.login, size: 14, color: Colors.grey[600]),
                const SizedBox(width: 4),
                Text(
                  clockInTime != null
                      ? DateFormat('hh:mm a').format(clockInTime)
                      : 'N/A',
                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                ),
                if (clockOutTime != null) ...[
                  const SizedBox(width: 12),
                  Icon(Icons.logout, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(
                    DateFormat('hh:mm a').format(clockOutTime),
                    style: TextStyle(color: Colors.grey[600], fontSize: 12),
                  ),
                ],
              ],
            ),
            if (duration != null)
              Text(
                'Duration: ${duration.inHours}h ${duration.inMinutes % 60}m',
                style: TextStyle(
                  color: isClockedIn ? Colors.green[700] : Colors.blue[700],
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
          ],
        ),
        trailing: Chip(
          label: Text(
            isClockedIn ? 'Active' : 'Completed',
            style: const TextStyle(fontSize: 10),
          ),
          backgroundColor: isClockedIn ? Colors.green[100] : Colors.blue[100],
          padding: EdgeInsets.zero,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Divider(),
                const SizedBox(height: 8),
                Text(
                  'Transactions Made',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                const SizedBox(height: 12),
                _buildStaffTransactions(
                  record['profile_id'] ?? record['staff_id'],
                  clockInTime,
                  clockOutTime,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStaffTransactions(
    String? staffId,
    DateTime? clockIn,
    DateTime? clockOut,
  ) {
    if (staffId == null || clockIn == null) {
      return Text(
        'No transaction data available',
        style: TextStyle(color: Colors.grey[600], fontSize: 12),
      );
    }

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _dataService.getStockTransactions(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final allTransactions = snapshot.data!;
        final staffTransactions = allTransactions.where((t) {
          final transactionTime = DateTime.tryParse(
            t['created_at']?.toString() ?? t['date']?.toString() ?? '',
          );
          if (transactionTime == null) return false;

          // Check if transaction was made by this staff during their clock-in period
          final isAfterClockIn = transactionTime.isAfter(clockIn);
          final isBeforeClockOut =
              clockOut == null || transactionTime.isBefore(clockOut);
          final isStaffTransaction = (t['staff_profile_id'] ?? t['staff_id']) == staffId;

          return isStaffTransaction && isAfterClockIn && isBeforeClockOut;
        }).toList();

        if (staffTransactions.isEmpty) {
          return Text(
            'No transactions made during this shift',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          );
        }

        final totalAmount = staffTransactions.fold<double>(
          0,
          (sum, t) => sum + ((t['total_amount'] as num?)?.toDouble() ?? 0),
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total Transactions: ${staffTransactions.length}',
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  Text(
                    'Total: ₦${NumberFormat('#,##0.00').format(totalAmount)}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[700],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ...staffTransactions.take(5).map((transaction) {
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(
                  Icons.shopping_cart,
                  color: Colors.green[700],
                  size: 20,
                ),
                title: Text(
                  transaction['item_name'] ?? 'Unknown Item',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  DateFormat('hh:mm a').format(
                    DateTime.tryParse(transaction['date']?.toString() ?? '') ??
                        DateTime.now(),
                  ),
                  style: const TextStyle(fontSize: 11),
                ),
                trailing: Text(
                  '₦${NumberFormat('#,##0.00').format((transaction['total_amount'] as num?)?.abs() ?? 0)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              );
            }).toList(),
            if (staffTransactions.length > 5)
              TextButton(
                onPressed: () {
                  // Show all transactions dialog
                  _showAllTransactionsDialog(staffTransactions);
                },
                child: Text(
                  'View all ${staffTransactions.length} transactions',
                ),
              ),
          ],
        );
      },
    );
  }

  void _showAllTransactionsDialog(List<Map<String, dynamic>> transactions) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('All Transactions'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: transactions.length,
            itemBuilder: (context, index) {
              final transaction = transactions[index];
              return ListTile(
                leading: Icon(Icons.shopping_cart, color: Colors.green[700]),
                title: Text(transaction['item_name'] ?? 'Unknown Item'),
                subtitle: Text(
                  DateFormat('MMM dd, hh:mm a').format(
                    DateTime.tryParse(transaction['date']?.toString() ?? '') ??
                        DateTime.now(),
                  ),
                ),
                trailing: Text(
                  '₦${NumberFormat('#,##0.00').format((transaction['total_amount'] as num?)?.abs() ?? 0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  // Suspend Staff Dialog
  void _showSuspendDialog(Map<String, dynamic> staff) {
    final reasonController = TextEditingController();
    DateTime? suspensionEndDate;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                            context: context,
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (reasonController.text.isEmpty) {
                  if (mounted) {
                    ErrorHandler.showWarningMessage(
                      context,
                      'Please provide a reason for suspension',
                    );
                  }
                  return;
                }
                if (suspensionEndDate == null) {
                  if (mounted) {
                    ErrorHandler.showWarningMessage(
                      context,
                      'Please select suspension end date',
                    );
                  }
                  return;
                }

                // Update staff status in database
                try {
                  await _dataService.updateStaffStatus(
                    staff['id'] as String,
                    'Suspended',
                  );
                  
                  // Optionally: Store suspension end date (would require schema update)
                  // For now, status change is sufficient
                  
                  Navigator.pop(context);
                  if (mounted) {
                    ErrorHandler.showSuccessMessage(
                      context,
                      '${staff['full_name'] ?? staff['name'] ?? 'Staff'} has been suspended until ${DateFormat('MMM dd, yyyy').format(suspensionEndDate!)}',
                    );
                    _loadStaff();
                  }
                } catch (e) {
                  Navigator.pop(context);
                  if (mounted) {
                    ErrorHandler.handleError(
                      context,
                      e,
                      customMessage: 'Failed to suspend staff. Please try again.',
                    );
                  }
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

  // Terminate Staff Dialog
  void _showTerminateDialog(Map<String, dynamic> staff) {
    final reasonController = TextEditingController();
    bool confirmTermination = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: confirmTermination && reasonController.text.isNotEmpty
                  ? () async {
                      // Update staff status in database
                      try {
                        await _dataService.updateStaffStatus(
                          staff['id'] as String,
                          'Terminated',
                        );
                        
                        Navigator.pop(context);
                        if (mounted) {
                          ErrorHandler.showSuccessMessage(
                            context,
                            '${staff['full_name'] ?? staff['name'] ?? 'Staff'} has been terminated',
                          );
                          _loadStaff();
                        }
                      } catch (e) {
                        Navigator.pop(context);
                        if (mounted) {
                          ErrorHandler.handleError(
                            context,
                            e,
                            customMessage: 'Failed to terminate staff. Please try again.',
                          );
                        }
                      }
                    }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[700],
                foregroundColor: Colors.white,
              ),
              child: const Text('Terminate Staff'),
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

  // Hire New Staff Dialog (Owner and Manager Only)
  void _showHireNewStaffDialog() {
    final fullNameController = TextEditingController();
    final emailController = TextEditingController();
    final phoneController = TextEditingController();
    String? selectedRole;
    bool isLoading = false;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
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
                            'Default password will be: Password123',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedRole,
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
                        value: 'bartender',
                        child: Text('Bartender'),
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
                        _buildStaffBenefit('Login credentials via email'),
                        _buildStaffBenefit('Access to assigned role features'),
                        _buildStaffBenefit('Default password: Password123'),
                        _buildStaffBenefit(
                          'Must change password on first login',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: isLoading ? null : () async {
                // Validation
                if (fullNameController.text.trim().isEmpty) {
                  if (mounted) {
                    ErrorHandler.showWarningMessage(
                      context,
                      'Please enter full name',
                    );
                  }
                  return;
                }
                if (emailController.text.trim().isEmpty) {
                  if (mounted) {
                    ErrorHandler.showWarningMessage(
                      context,
                      'Please enter email',
                    );
                  }
                  return;
                }
                if (selectedRole == null) {
                  if (mounted) {
                    ErrorHandler.showWarningMessage(
                      context,
                      'Please select a role',
                    );
                  }
                  return;
                }

                // Create staff profile
                setDialogState(() => isLoading = true);
                try {
                  final authService = Provider.of<AuthService>(context, listen: false);
                  final currentUser = authService.currentUser;
                  
                  // Allow owner, HR manager, and manager to create staff profiles
                  if (currentUser?.role != AppRole.owner && 
                      currentUser?.role != AppRole.hr && 
                      currentUser?.role != AppRole.manager) {
                    throw Exception('Only owner, HR manager, or manager can create staff profiles');
                  }

                  // Save and sanitize values before disposing controllers
                  final staffName = InputSanitizer.sanitizeText(fullNameController.text.trim());
                  final staffEmail = InputSanitizer.sanitizeEmail(emailController.text.trim());
                  final staffPhone = phoneController.text.trim().isEmpty 
                      ? null 
                      : InputSanitizer.sanitizePhone(phoneController.text.trim());
                  final staffRole = selectedRole!; // This is already a String from the dropdown
                  
                  if (staffName.isEmpty) {
                    throw Exception('Staff name cannot be empty');
                  }
                  if (staffEmail.isEmpty || !staffEmail.contains('@')) {
                    throw Exception('Please enter a valid email address');
                  }

                  // Generate secure random password with "Pzed" prefix
                  final securePassword = _generateSecurePassword();
                  
                  // CRITICAL: Save current user's session token before creating staff account
                  // This allows us to restore the current user's session after creating the staff account
                  // Works for owner, HR manager, or manager
                  final supabase = Supabase.instance.client;
                  final currentUserSession = supabase.auth.currentSession;
                  final currentUserAccessToken = currentUserSession?.accessToken;
                  final currentUserRefreshToken = currentUserSession?.refreshToken;
                  
                  // Set flag to ignore auth state changes during staff creation
                  authService.setCreatingStaffAccount(true);
                  
                  // Declare userId outside try block so it's accessible later
                  String? userId;
                  
                  try {
                    // Create auth user (this will create guest profile via trigger)
                    // NOTE: This will temporarily switch the session to the new user,
                    // but the auth state listener will be ignored due to the flag above
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
                    
                    // Wait a moment for trigger to create profile
                    await Future.delayed(const Duration(milliseconds: 1000));
                    
                    // Immediately sign out the new user
                    // The flag _isCreatingStaffAccount prevents the auth state listener
                    // from switching to the new user
                    await supabase.auth.signOut();
                    
                    // Wait a moment for sign out to complete
                    await Future.delayed(const Duration(milliseconds: 500));
                    
                    // CRITICAL: Restore current user's session using the saved refresh token
                    // setSession expects a refresh token string
                    // Works for owner, HR manager, or manager
                    if (currentUserRefreshToken != null) {
                      try {
                        // Use setSession with the refresh token string
                        await supabase.auth.setSession(currentUserRefreshToken);
                      } catch (e) {
                        // If setSession fails, the user will need to log in again
                        if (mounted) {
                          ErrorHandler.showWarningMessage(
                            context,
                            'Please log in again to continue. Your session was reset during staff creation.',
                          );
                        }
                      }
                    }
                  } finally {
                    // Always clear the flag, even if there was an error
                    // This will allow the auth state listener to process any session changes
                    authService.setCreatingStaffAccount(false);
                    
                    // Verify current user's session is restored
                    final restoredSession = supabase.auth.currentSession;
                    if (restoredSession == null && currentUserSession != null) {
                      // Current user's session was lost - they'll need to log in again
                      // This applies to owner, HR manager, or manager
                      if (mounted) {
                        ErrorHandler.showWarningMessage(
                          context,
                          'Please log in again to continue. Your session was reset during staff creation.',
                        );
                      }
                    }
                  }

                  // Update profile to staff role using the user ID directly
                  try {
                    await _dataService.createStaffProfile(
                      email: staffEmail,
                      password: securePassword, // Not used in function but kept for consistency
                      fullName: staffName,
                      role: staffRole, // staffRole is already a String
                      phone: staffPhone,
                      department: null,
                      userId: userId, // Pass the user ID directly to avoid querying auth.users
                    );
                  } catch (profileError) {
                    // If profile update fails, wait a bit more and retry
                    // This handles cases where the trigger hasn't created the profile yet
                    try {
                      await Future.delayed(const Duration(milliseconds: 1000));
                      await _dataService.createStaffProfile(
                        email: staffEmail,
                        password: securePassword,
                        fullName: staffName,
                        role: staffRole, // staffRole is already a String
                        phone: staffPhone,
                        department: null,
                        userId: userId!,
                      );
                    } catch (retryError) {
                      // If it still fails, throw the original error
                      throw Exception('Failed to update staff profile: $profileError');
                    }
                  }

                  // Send password reset email to the new staff member
                  // This allows them to set their own password and log in
                  try {
                    final supabase = Supabase.instance.client;
                    await supabase.auth.resetPasswordForEmail(
                      staffEmail,
                      redirectTo: _getPasswordResetUrl(),
                    );
                    if (kDebugMode) {
                      debugPrint('Password reset email sent to $staffEmail');
                    }
                  } catch (emailError) {
                    // Log but don't fail - password was already generated and shown to owner
                    // Staff can use "Forgot Password" later if needed
                    if (kDebugMode) {
                      debugPrint('Warning: Could not send password reset email to $staffEmail: $emailError');
                    }
                  }

                  fullNameController.dispose();
                  emailController.dispose();
                  phoneController.dispose();

                  if (mounted) {
                    Navigator.pop(context);
                    // Show password to owner (they should communicate it securely to staff)
                    showDialog(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Staff Account Created'),
                        content: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('$staffName hired as ${staffRole.replaceAll('_', ' ')}'),
                            const SizedBox(height: 16),
                            const Text(
                              'Temporary Password:',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            SelectableText(
                              securePassword,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              '⚠️ Please securely communicate this password to the staff member. They should change it on first login.',
                              style: TextStyle(fontSize: 12, color: Colors.orange),
                            ),
                          ],
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text('OK'),
                          ),
                        ],
                      ),
                    );
                    _loadStaff();
                  }
                } catch (e) {
                  setDialogState(() => isLoading = false);
                  if (mounted) {
                    // Provide specific error messages for common issues
                    String errorMsg = 'Failed to create staff account';
                    final errorString = e.toString().toLowerCase();
                    
                    if (errorString.contains('already registered') || 
                        errorString.contains('already exists') ||
                        errorString.contains('user already registered')) {
                      errorMsg = 'Email address is already registered. Please use a different email or reset the password for this account.';
                    } else if (errorString.contains('invalid email') || 
                               errorString.contains('email format')) {
                      errorMsg = 'Invalid email format. Please enter a valid email address.';
                    } else if (errorString.contains('network') || 
                               errorString.contains('connection') ||
                               errorString.contains('timeout')) {
                      errorMsg = 'Network connection error. Please check your internet connection and try again.';
                    } else if (errorString.contains('database') || 
                               errorString.contains('supabase')) {
                      errorMsg = 'Database error. Please contact support if the problem persists.';
                    } else if (errorString.contains('profile') || 
                               errorString.contains('createstaffprofile')) {
                      errorMsg = 'Failed to create staff profile. Please verify all information is correct and try again.';
                    } else if (errorString.contains('only owner') || errorString.contains('Only owner')) {
                      errorMsg = 'Only owner or manager can create staff profiles';
                    } else {
                      errorMsg = 'Failed to create staff account: ${e.toString()}';
                    }
                    
                    ErrorHandler.handleError(
                      context,
                      e,
                      customMessage: errorMsg,
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
        ),
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
