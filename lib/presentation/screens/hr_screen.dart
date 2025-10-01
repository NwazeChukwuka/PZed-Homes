import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/presentation/screens/user_profile_screen.dart';

class HrScreen extends StatefulWidget {
  const HrScreen({super.key});
  @override
  State<HrScreen> createState() => _HrScreenState();
}

class _HrScreenState extends State<HrScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _supabase = Supabase.instance.client;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
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
                Tab(text: 'Staff Members', icon: Icon(Icons.work)),
                Tab(text: 'Guests', icon: Icon(Icons.person)),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [
                UserList(isStaff: true),
                UserList(isStaff: false),
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
                  'Manage staff members and guest profiles',
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
}

class UserList extends StatefulWidget {
  final bool isStaff;
  const UserList({super.key, required this.isStaff});

  @override
  State<UserList> createState() => _UserListState();
}

class _UserListState extends State<UserList> {
  final _supabase = Supabase.instance.client;
  Future<List<Map<String, dynamic>>>? _usersFuture;
  bool _isLoading = true;
  
  // Pagination state
  int _rowsPerPage = 10;
  int _currentPage = 0;
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _currentPageUsers = [];

  @override
  void initState() {
    super.initState();
    _usersFuture = _loadUsers();
  }

  Future<List<Map<String, dynamic>>> _loadUsers() async {
    try {
      final query = _supabase.from('profiles').select();
      
      if (widget.isStaff) {
        // Staff members have roles that are not just 'guest'
        final response = await query;
        final allUsers = List<Map<String, dynamic>>.from(response);
        final staffUsers = allUsers.where((user) {
          final roles = (user['roles'] as List<dynamic>? ?? []);
          return roles.isNotEmpty && !(roles.length == 1 && roles.contains('guest'));
        }).toList();
        
        if (mounted) {
          setState(() {
            _isLoading = false;
            _allUsers = staffUsers;
            _updatePagination();
          });
        }
        return staffUsers;
      } else {
        // Guests have only the 'guest' role
        final response = await query;
        final allUsers = List<Map<String, dynamic>>.from(response);
        final guestUsers = allUsers.where((user) {
          final roles = (user['roles'] as List<dynamic>? ?? []);
          return roles.length == 1 && roles.contains('guest');
        }).toList();
        
        if (mounted) {
          setState(() {
            _isLoading = false;
            _allUsers = guestUsers;
            _updatePagination();
          });
        }
        return guestUsers;
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error loading users: $e'),
          backgroundColor: Colors.red,
        ),
      );
      return [];
    }
  }

  void _updatePagination() {
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, _allUsers.length);
    setState(() {
      _currentPageUsers = _allUsers.sublist(startIndex, endIndex);
    });
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'active':
        return Colors.green;
      case 'inactive':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    return _isLoading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: _loadUsers,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _usersFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text('Error: ${snapshot.error}'),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _loadUsers,
                          child: const Text('Try Again'),
                        ),
                      ],
                    ),
                  );
                }

                final users = snapshot.data ?? [];
                
                if (users.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          widget.isStaff ? Icons.people_outline : Icons.person_outline,
                          size: 64,
                          color: Colors.grey,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          widget.isStaff ? 'No staff members found' : 'No guests found',
                          style: const TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        const SizedBox(height: 8),
                        TextButton(
                          onPressed: _loadUsers,
                          child: const Text('Refresh'),
                        ),
                      ],
                    ),
                  );
                }

                return Padding(
                  padding: const EdgeInsets.all(24),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: PaginatedDataTable(
                      header: Container(
                        padding: const EdgeInsets.all(20),
                        child: Row(
                          children: [
                            Text(
                              widget.isStaff ? 'Staff Members' : 'Guests',
                              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: Colors.grey[800],
                              ),
                            ),
                            const Spacer(),
                            Text(
                              '${_allUsers.length} Total ${widget.isStaff ? 'Staff' : 'Guests'}',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                      columns: [
                        const DataColumn(
                          label: Text('Full Name'),
                          numeric: false,
                        ),
                        const DataColumn(
                          label: Text('Email'),
                          numeric: false,
                        ),
                        DataColumn(
                          label: Text(widget.isStaff ? 'Roles' : 'Status'),
                          numeric: false,
                        ),
                        const DataColumn(
                          label: Text('Phone'),
                          numeric: false,
                        ),
                        const DataColumn(
                          label: Text('Actions'),
                          numeric: false,
                        ),
                      ],
                      source: _UserDataSource(
                        users: _currentPageUsers,
                        isStaff: widget.isStaff,
                        onUserTap: (user) {
                          context.push('/profile', extra: user);
                        },
                        getStatusColor: _getStatusColor,
                      ),
                      rowsPerPage: _rowsPerPage,
                      onPageChanged: (pageIndex) {
                        setState(() {
                          _currentPage = pageIndex;
                        });
                        _updatePagination();
                      },
                      onRowsPerPageChanged: (newRowsPerPage) {
                        setState(() {
                          _rowsPerPage = newRowsPerPage ?? 10;
                          _currentPage = 0;
                        });
                        _updatePagination();
                      },
                      availableRowsPerPage: const [5, 10, 20, 50],
                      showFirstLastButtons: true,
                    ),
                  ),
                );
              },
            ),
          );
  }
}

class _UserDataSource extends DataTableSource {
  final List<Map<String, dynamic>> users;
  final bool isStaff;
  final Function(Map<String, dynamic>) onUserTap;
  final Color Function(String) getStatusColor;

  _UserDataSource({
    required this.users,
    required this.isStaff,
    required this.onUserTap,
    required this.getStatusColor,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= users.length) return null;
    
    final user = users[index];
    final fullName = user['full_name']?.toString() ?? 'Unnamed User';
    final email = user['email']?.toString() ?? 'N/A';
    final phone = user['phone']?.toString() ?? 'N/A';
    final status = user['status']?.toString() ?? 'Active';
    final roles = (user['roles'] as List<dynamic>? ?? []).join(', ');
    
    return DataRow(
      cells: [
        DataCell(
          Row(
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor: Colors.green[100],
                child: Icon(
                  isStaff ? Icons.work_outline : Icons.person_outline,
                  color: Colors.green[700],
                  size: 16,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                fullName,
                style: const TextStyle(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
        DataCell(Text(email)),
        DataCell(
          isStaff
              ? Text(
                  roles,
                  style: TextStyle(
                    color: Colors.green[700],
                    fontWeight: FontWeight.w500,
                  ),
                )
              : Chip(
                  label: Text(
                    status,
                    style: TextStyle(
                      color: getStatusColor(status),
                      fontWeight: FontWeight.w500,
                      fontSize: 12,
                    ),
                  ),
                  backgroundColor: getStatusColor(status).withOpacity(0.1),
                  side: BorderSide(color: getStatusColor(status).withOpacity(0.3)),
                ),
        ),
        DataCell(Text(phone)),
        DataCell(
          IconButton(
            icon: const Icon(Icons.visibility),
            onPressed: () => onUserTap(user),
            tooltip: 'View Profile',
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => users.length;

  @override
  int get selectedRowCount => 0;
}