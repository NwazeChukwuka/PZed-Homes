import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/data/mock_data.dart';
import 'package:pzed_homes/core/services/mock_auth_service.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:pzed_homes/data/models/user.dart';

class HousekeepingScreen extends StatefulWidget {
  const HousekeepingScreen({super.key});

  @override
  State<HousekeepingScreen> createState() => _HousekeepingScreenState();
}

class _HousekeepingScreenState extends State<HousekeepingScreen> {
  bool _isLoading = false;

  // Pagination state
  int _rowsPerPage = 10;
  int _currentPage = 0;
  List<Map<String, dynamic>> _allRooms = [];
  List<Map<String, dynamic>> _currentPageRooms = [];

  @override
  void initState() {
    super.initState();
    _loadRooms();
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);
    await Future.delayed(const Duration(milliseconds: 250));
    final rooms = MockData.getRooms().map((r) {
      // Adapt keys to UI expectations
      return {
        'id': r['id'],
        'room_number': r['id'],
        'type': r['type'],
        'status': _mapStatus(r['status']?.toString() ?? 'available'),
      };
    }).toList();
    setState(() {
      _allRooms = rooms;
      _isLoading = false;
    });
    _updatePagination();
  }

  String _mapStatus(String s) {
    switch (s.toLowerCase()) {
      case 'available':
        return 'Vacant';
      case 'occupied':
        return 'Occupied';
      case 'maintenance':
        return 'Maintenance';
      case 'dirty':
        return 'Dirty';
      default:
        return 'Vacant';
    }
  }

  Future<void> _updateRoomStatus(String roomId, String newStatus) async {
    // Mock: update locally
    final idx = _allRooms.indexWhere((r) => r['id'] == roomId);
    if (idx != -1) {
      setState(() {
        _allRooms[idx]['status'] = newStatus;
      });
      _updatePagination();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('[Mock] Room status updated to $newStatus'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'Vacant':
        return Colors.green;
      case 'Occupied':
        return Colors.red;
      case 'Dirty':
        return Colors.orange;
      case 'Cleaning':
        return Colors.blue;
      case 'Maintenance':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  String _getPriority(String status) {
    switch (status) {
      case 'Dirty':
        return 'High';
      case 'Cleaning':
        return 'Medium';
      case 'Maintenance':
        return 'High';
      case 'Vacant':
        return 'Low';
      case 'Occupied':
        return 'Low';
      default:
        return 'Low';
    }
  }

  Color _getPriorityColor(String priority) {
    switch (priority) {
      case 'High':
        return Colors.red;
      case 'Medium':
        return Colors.orange;
      case 'Low':
        return Colors.green;
      default:
        return Colors.grey;
    }
  }

  void _showStatusUpdateOptions(Map<String, dynamic> room) {
    final currentStatus = room['status'] as String? ?? 'Unknown';

    showModalBottomSheet(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  'Room ${room['room_number']} - ${room['type'] ?? 'Unknown'}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Divider(),
              if (currentStatus == 'Dirty') ...[
                _buildStatusOption(
                  ctx,
                  'Start Cleaning',
                  Icons.cleaning_services,
                  'Cleaning',
                  room['id'],
                ),
              ],
              if (currentStatus == 'Cleaning') ...[
                _buildStatusOption(
                  ctx,
                  'Mark as Clean/Vacant',
                  Icons.check_circle,
                  'Vacant',
                  room['id'],
                ),
                _buildStatusOption(
                  ctx,
                  'Needs Maintenance',
                  Icons.build,
                  'Maintenance',
                  room['id'],
                ),
              ],
              if (currentStatus == 'Vacant') ...[
                _buildStatusOption(
                  ctx,
                  'Report Issue',
                  Icons.warning,
                  'Maintenance',
                  room['id'],
                ),
              ],
              if (currentStatus == 'Maintenance') ...[
                _buildStatusOption(
                  ctx,
                  'Maintenance Complete',
                  Icons.check_circle,
                  'Vacant',
                  room['id'],
                ),
              ],
              ListTile(
                leading: const Icon(Icons.close),
                title: const Text('Cancel'),
                onTap: () => context.pop(),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusOption(BuildContext context, String title, IconData icon, String status, String roomId) {
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      onTap: () {
        context.pop();
        _updateRoomStatus(roomId, status);
      },
    );
  }

  void _updatePagination() {
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, _allRooms.length);
    setState(() {
      _currentPageRooms = _allRooms.sublist(startIndex, endIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Builder(builder: (context) {
              if (_allRooms.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Image.asset(
                        'assets/images/PZED logo.png',
                        height: 64,
                        width: 64,
                        fit: BoxFit.contain,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'No rooms found',
                        style: TextStyle(fontSize: 18, color: Colors.grey),
                      ),
                    ],
                  ),
                );
              }

              return SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeader(context),
                      const SizedBox(height: 24),
                      SizedBox(
                        height: MediaQuery.of(context).size.height - 500,
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
                                  'Room Status Overview',
                                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.grey[800],
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.refresh),
                                  onPressed: _loadRooms,
                                ),
                              ],
                            ),
                          ),
                          columns: const [
                            DataColumn(
                              label: Text('Room #'),
                              numeric: false,
                            ),
                            DataColumn(
                              label: Text('Room Type'),
                              numeric: false,
                            ),
                            DataColumn(
                              label: Text('Priority'),
                              numeric: false,
                            ),
                            DataColumn(
                              label: Text('Status'),
                              numeric: false,
                            ),
                            DataColumn(
                              label: Text('Actions'),
                              numeric: false,
                            ),
                          ],
                          source: _RoomDataSource(
                            rooms: _currentPageRooms,
                            onStatusUpdate: _showStatusUpdateOptions,
                            getStatusColor: _getStatusColor,
                            getPriority: _getPriority,
                            getPriorityColor: _getPriorityColor,
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
                      ),
                    ],
                  ),
                ),
              );
            }),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Housekeeping',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Manage room status and housekeeping operations',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 8,
          children: [
            const ContextAwareRoleButton(suggestedRole: AppRole.receptionist),
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
                  Icon(Icons.info_outline, color: Colors.green[700], size: 16),
                  const SizedBox(width: 8),
                  Text(
                    '${_allRooms.length} Total Rooms',
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
      ],
    );
  }
}

class _RoomDataSource extends DataTableSource {
  final List<Map<String, dynamic>> rooms;
  final Function(Map<String, dynamic>) onStatusUpdate;
  final Color Function(String) getStatusColor;
  final String Function(String) getPriority;
  final Color Function(String) getPriorityColor;

  _RoomDataSource({
    required this.rooms,
    required this.onStatusUpdate,
    required this.getStatusColor,
    required this.getPriority,
    required this.getPriorityColor,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= rooms.length) return null;
    
    final room = rooms[index];
    final status = room['status'] as String? ?? 'Unknown';
    final priority = getPriority(status);
    
    return DataRow(
      cells: [
        DataCell(
          Text(
            room['room_number']?.toString() ?? 'Unknown',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ),
        DataCell(
          Text(room['type']?.toString() ?? 'Unknown'),
        ),
        DataCell(
          Chip(
            label: Text(
              priority,
              style: TextStyle(
                color: getPriorityColor(priority),
                fontWeight: FontWeight.w500,
                fontSize: 12,
              ),
            ),
            backgroundColor: getPriorityColor(priority).withOpacity(0.1),
            side: BorderSide(color: getPriorityColor(priority).withOpacity(0.3)),
          ),
        ),
        DataCell(
          Chip(
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
        DataCell(
          IconButton(
            icon: const Icon(Icons.more_vert),
            onPressed: () => onStatusUpdate(room),
            tooltip: 'Update Status',
          ),
        ),
      ],
    );
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => rooms.length;

  @override
  int get selectedRowCount => 0;
}