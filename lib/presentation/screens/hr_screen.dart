import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/data/models/user.dart';

class HrScreen extends StatefulWidget {
  const HrScreen({super.key});
  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> with SingleTickerProviderStateMixin {
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
    _tabController = TabController(length: 4, vsync: this); // Staff, Duty, Performance, Roles/Positions
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
              tabs: const [
                Tab(text: 'Staff Directory', icon: Icon(Icons.people_alt)),
                Tab(text: 'Duty Roster', icon: Icon(Icons.event_available)),
                Tab(text: 'Performance', icon: Icon(Icons.assessment)),
                Tab(text: 'Roles & Positions', icon: Icon(Icons.admin_panel_settings)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildStaffDirectoryTab(context),
                _buildDutyRosterTab(context),
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
        final roles = (s['roles'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
        return !roles.contains('owner');
        }).toList();
          setState(() {
        _allStaff = filtered;
        _applySearchFilter();
            _isLoading = false;
          });
    } catch (e) {
        setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to load staff: $e'), backgroundColor: Colors.red),
      );
    }
  }

  void _applySearchFilter() {
    final q = _searchQuery.toLowerCase();
    _filteredStaff = _allStaff.where((u) {
      final name = (u['full_name']?.toString() ?? '').toLowerCase();
      final email = (u['email']?.toString() ?? '').toLowerCase();
      final roles = (u['roles'] as List<dynamic>? ?? []).join(',').toLowerCase();
      return q.isEmpty || name.contains(q) || email.contains(q) || roles.contains(q);
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
                    final name = (u['full_name']?.toString() ?? (u['name']?.toString() ?? 'Unknown'));
                    final roles = (u['roles'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: Colors.green[100],
                          child: const Icon(Icons.person, color: Colors.green),
                        ),
                        title: Text(name.isEmpty ? 'Unknown' : name),
                        subtitle: Text(roles.isEmpty ? 'Unassigned' : roles.join(', ')),
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
                            }
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(value: 'promote', child: Text('Promote')),
                            PopupMenuItem(value: 'demote', child: Text('Demote')),
                            PopupMenuItem(value: 'assign', child: Text('Assign Role')),
                          ],
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
                  subtitle: Text('Roles: $roles\nLast duty: ${_dateFormat.format(_selectedDate.subtract(const Duration(days: 7)))}'),
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
          ..._allStaff.take(5).map((u) => ListTile(
                leading: const Icon(Icons.emoji_events, color: Colors.amber),
                title: Text(u['full_name']?.toString() ?? 'Unnamed'),
                subtitle: const Text('Consistent performance across duties'),
              )),
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
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
                    child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
                        const SizedBox(height: 8),
          Row(
                      children: [
              Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
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
                  subtitle: const Text('Define scalable positions with benefits and permissions'),
                ),
              ],
                              ),
                        ),
                      ],
                    ),
                  );
                }

  // ---------- Dialogs / Actions ----------
  Future<void> _showPromoteDemoteDialog(Map<String, dynamic> user, {required bool isPromote}) async {
    final roles = (user['roles'] as List<dynamic>? ?? []).map((e) => e.toString()).toList();
    final available = AppRole.values.where((r) => r != AppRole.owner && r != AppRole.guest).toList();
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
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Updated role to ${selected!.name} for ${user['full_name']}')),
                );
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
                    decoration: const InputDecoration(labelText: 'Select Staff (by ID)'),
                    items: _allStaff
                        .map((s) => DropdownMenuItem(value: s['id'] as String, child: Text(s['full_name']?.toString() ?? 'Unnamed')))
                        .toList(),
                    onChanged: (v) => staffId = v,
                  ),
                const SizedBox(height: 12),
                DropdownButtonFormField<AppRole>(
                  decoration: const InputDecoration(labelText: 'Role'),
                  items: AppRole.values
                      .where((r) => r != AppRole.owner && r != AppRole.guest)
                      .map((r) => DropdownMenuItem(value: r, child: Text(r.name)))
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
                        initialDate: DateTime.now().add(const Duration(days: 7)),
                        firstDate: DateTime.now(),
                        lastDate: DateTime.now().add(const Duration(days: 365)),
                      );
                      if (picked != null) setState(() => expiry = picked);
                    },
                    icon: const Icon(Icons.date_range),
                    label: Text(expiry == null ? 'Pick expiry date' : 'Expires: ${_dateFormat.format(expiry!)}'),
                            ),
                          ],
                        ),
                      ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
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
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Role assigned successfully')),
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
                decoration: const InputDecoration(labelText: 'Benefits (comma separated)'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              // Placeholder for persistence; scalable for backend integration
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Position created')),
              );
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }
}