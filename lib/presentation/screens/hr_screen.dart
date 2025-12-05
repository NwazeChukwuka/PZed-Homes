import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: 5,
      vsync: this,
    ); // Staff, Duty, Attendance, Performance, Roles/Positions
    _loadStaff();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
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
              // Only owner can hire new staff
              Consumer<AuthService>(
                builder: (context, authService, _) {
                  final isOwner =
                      authService.currentUser?.role == AppRole.owner;
                  if (!isOwner) return const SizedBox.shrink();

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
    final onDuty = _allStaff.where((u) {
      // Simple mock: alternate staff on odd/even days
      final idHash = (u['id']?.hashCode ?? 0).abs();
      return (_selectedDate.day % 2 == idHash % 2);
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
              Text('${onDuty.length} on duty'),
            ],
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: onDuty.length,
            itemBuilder: (context, i) {
              final u = onDuty[i];
              final roles = (u['roles'] as List<dynamic>? ?? []).join(', ');
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.badge),
                  title: Text(u['full_name']?.toString() ?? 'Unnamed'),
                  subtitle: Text(
                    'Roles: $roles\nLast duty: ${_dateFormat.format(_selectedDate.subtract(const Duration(days: 7)))}',
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
    // Simple mock KPI cards
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              _kpiCard('Today Score', '92', Colors.green),
              _kpiCard('This Week', '88', Colors.blue),
              _kpiCard('This Month', '90', Colors.purple),
            ],
          ),
          const SizedBox(height: 16),
          Text('Top Performers', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          ..._allStaff
              .take(5)
              .map(
                (u) => ListTile(
                  leading: const Icon(Icons.emoji_events, color: Colors.amber),
                  title: Text(u['full_name']?.toString() ?? 'Unnamed'),
                  subtitle: const Text('Consistent performance across duties'),
                ),
              ),
        ],
      ),
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
            onPressed: () {
              // Placeholder for persistence; scalable for backend integration
              Navigator.pop(context);
              if (mounted) {
                ErrorHandler.showSuccessMessage(context, 'Position created');
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
              onPressed: () {
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

                Navigator.pop(context);
                if (mounted) {
                  ErrorHandler.showWarningMessage(
                    context,
                    'Staff suspended until ${DateFormat('MMM dd, yyyy').format(suspensionEndDate!)}',
                  );
                }
                _loadStaff();
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
                  ? () {
                      Navigator.pop(context);
                      if (mounted) {
                        ErrorHandler.showWarningMessage(
                          context,
                          '${staff['full_name'] ?? staff['name'] ?? 'Staff'} has been terminated',
                        );
                        _loadStaff();
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

  // Hire New Staff Dialog (Owner Only)
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
                  
                  if (currentUser?.role != AppRole.owner) {
                    throw Exception('Only owner can create staff profiles');
                  }

                  // Save values before disposing controllers
                  final staffName = fullNameController.text.trim();
                  final staffEmail = emailController.text.trim();
                  final staffPhone = phoneController.text.trim().isEmpty ? null : phoneController.text.trim();
                  final staffRole = selectedRole!;

                  // Create auth user (this will create guest profile via trigger)
                  final supabase = Supabase.instance.client;
                  final signUpResponse = await supabase.auth.signUp(
                    email: staffEmail,
                    password: 'Password123', // Default password
                    data: {
                      'full_name': staffName,
                    },
                  );

                  if (signUpResponse.user == null) {
                    throw Exception('Failed to create user account');
                  }

                  // Wait a moment for trigger to create profile
                  await Future.delayed(const Duration(milliseconds: 500));

                  // Update profile to staff role using database function
                  await _dataService.createStaffProfile(
                    email: staffEmail,
                    password: 'Password123', // Not used in function
                    fullName: staffName,
                    role: staffRole,
                    phone: staffPhone,
                    department: null,
                  );

                  fullNameController.dispose();
                  emailController.dispose();
                  phoneController.dispose();

                  if (mounted) {
                    Navigator.pop(context);
                    ErrorHandler.showSuccessMessage(
                      context,
                      '$staffName hired as ${staffRole.replaceAll('_', ' ')}. Default password: Password123',
                    );
                    _loadStaff();
                  }
                } catch (e) {
                  setDialogState(() => isLoading = false);
                  if (mounted) {
                    String errorMsg = 'Failed to create staff profile';
                    if (e.toString().contains('already registered')) {
                      errorMsg = 'Email already exists. Please use a different email.';
                    } else if (e.toString().contains('Only owner')) {
                      errorMsg = 'Only owner can create staff profiles';
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
