import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';

class HousekeepingScreen extends StatefulWidget {
  const HousekeepingScreen({super.key});

  @override
  State<HousekeepingScreen> createState() => _HousekeepingScreenState();
}

class _HousekeepingScreenState extends State<HousekeepingScreen> with SingleTickerProviderStateMixin {
  bool _isLoading = false;
  final _dataService = DataService();
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
  StreamSubscription<List<Map<String, dynamic>>>? _roomsSub;
  Timer? _refreshDebounce;

  // Pagination state
  int _rowsPerPage = 10;
  int _currentPage = 0;
  List<Map<String, dynamic>> _allRooms = [];
  List<Map<String, dynamic>> _currentPageRooms = [];
  
  // Booking history state
  List<Map<String, dynamic>> _bookings = [];
  DateTimeRange? _bookingFilterRange;
  late TabController _tabController;

  bool get _isReceptionist {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    final effectiveRole = authService.isRoleAssumed
        ? (authService.assumedRole ?? currentUser?.role)
        : currentUser?.role;
    return effectiveRole == AppRole.receptionist;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadRooms();
    _loadBookings();
    _startRoomRealtime();
  }
  
  Future<void> _loadBookings() async {
    try {
      final bookings = await _dataService.getBookings();
      setState(() {
        _bookings = bookings;
      });
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load booking history.',
        );
      }
    }
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);
    try {
      final rooms = await _dataService.getRooms();
      final adaptedRooms = rooms.map((r) {
        // Adapt keys to UI expectations
        return {
          'id': r['id'],
          'room_number': r['room_number'] ?? r['id'],
          'type': r['type'],
          'status': _mapStatus(r['status']?.toString() ?? 'Vacant'),
          'priority': r['priority']?.toString() ?? _getPriority(_mapStatus(r['status']?.toString() ?? 'Vacant'), existingPriority: null),
        };
      }).toList();
      setState(() {
        _allRooms = adaptedRooms;
        _isLoading = false;
      });
      _updatePagination();
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load rooms. Please check your connection and try again.',
          onRetry: _loadRooms,
        );
      }
    }
  }

  void _startRoomRealtime() {
    final supabase = _supabase;
    if (supabase == null) return;
    _roomsSub?.cancel();
    _roomsSub = supabase
        .from('rooms')
        .stream(primaryKey: ['id'])
        .listen((_) {
          _refreshDebounce?.cancel();
          _refreshDebounce = Timer(const Duration(milliseconds: 500), () {
            if (mounted) {
              _loadRooms();
            }
          });
        });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _roomsSub?.cancel();
    _refreshDebounce?.cancel();
    super.dispose();
  }

  String _mapStatus(String s) {
    switch (s.toLowerCase()) {
      case 'vacant':
      case 'available':
        return 'Vacant';
      case 'occupied':
        return 'Occupied';
      case 'maintenance':
        return 'Maintenance';
      case 'dirty':
        return 'Dirty';
      case 'cleaning':
        return 'Cleaning';
      default:
        return 'Vacant';
    }
  }

  Future<void> _updateRoomStatus(String roomId, String newStatus, {String? priority}) async {
    try {
      setState(() => _isLoading = true);
      await _dataService.updateRoomStatus(roomId, newStatus, priority: priority);
      final idx = _allRooms.indexWhere((r) => r['id'] == roomId);
      if (idx != -1) {
        setState(() {
          _allRooms[idx]['status'] = newStatus;
          if (priority != null) {
            _allRooms[idx]['priority'] = priority;
          } else {
            // Auto-calculate priority if not provided
            _allRooms[idx]['priority'] = _getPriority(newStatus);
          }
          _isLoading = false;
        });
        _updatePagination();
      } else {
        setState(() => _isLoading = false);
      }
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          'Room status updated to $newStatus${priority != null ? ' with priority $priority' : ''}',
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update room status. Please try again.',
        );
      }
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

  String _getPriority(String status, {String? existingPriority}) {
    // Use existing priority if provided, otherwise calculate from status
    if (existingPriority != null && existingPriority.isNotEmpty) {
      return existingPriority;
    }
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

  DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    try {
      return DateTime.parse(timestamp.toString());
    } catch (e) {
      return null;
    }
  }

  void _showReceptionistUpdateDialog(Map<String, dynamic> room) {
    final currentStatus = room['status'] as String? ?? 'Vacant';
    final currentPriority = room['priority'] as String? ?? 'Low';
    
    String selectedStatus = currentStatus;
    String selectedPriority = currentPriority;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text('Update Room ${room['room_number']}'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Status:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedStatus,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Vacant', child: Text('Vacant')),
                        DropdownMenuItem(value: 'Occupied', child: Text('Occupied')),
                        DropdownMenuItem(value: 'Dirty', child: Text('Dirty')),
                        DropdownMenuItem(value: 'Cleaning', child: Text('Cleaning')),
                        DropdownMenuItem(value: 'Maintenance', child: Text('Maintenance')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedStatus = value;
                            // Auto-update priority based on status if not manually set
                            if (selectedPriority == currentPriority) {
                              selectedPriority = _getPriority(value);
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Priority:',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      value: selectedPriority,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      ),
                      items: const [
                        DropdownMenuItem(value: 'Low', child: Text('Low')),
                        DropdownMenuItem(value: 'Medium', child: Text('Medium')),
                        DropdownMenuItem(value: 'High', child: Text('High')),
                        DropdownMenuItem(value: 'Urgent', child: Text('Urgent')),
                      ],
                      onChanged: (value) {
                        if (value != null) {
                          setDialogState(() {
                            selectedPriority = value;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.of(ctx).pop();
                    _updateRoomStatus(
                      room['id'],
                      selectedStatus,
                      priority: selectedPriority,
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[700],
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Update'),
                ),
              ],
            );
          },
        );
      },
    );
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
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildHeader(context),
                ),
                TabBar(
                  controller: _tabController,
                  labelColor: Colors.green[800],
                  unselectedLabelColor: Colors.grey[600],
                  indicatorColor: Colors.green[800],
                  tabs: const [
                    Tab(text: 'Room Status', icon: Icon(Icons.hotel)),
                    Tab(text: 'Booking History', icon: Icon(Icons.history)),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildRoomStatusTab(context),
                      _buildBookingHistoryTab(context),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
  
  Widget _buildRoomStatusTab(BuildContext context) {
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

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Container(
        height: MediaQuery.of(context).size.height - 200,
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
                onStatusUpdate: _isReceptionist ? _showReceptionistUpdateDialog : _showStatusUpdateOptions,
                getStatusColor: _getStatusColor,
                getPriority: _getPriority,
                getPriorityColor: _getPriorityColor,
                isReceptionist: _isReceptionist,
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
      );
  }
  
  Widget _buildBookingHistoryTab(BuildContext context) {
    // Filter bookings by date range if set
    List<Map<String, dynamic>> filteredBookings = _bookings;
    if (_bookingFilterRange != null) {
      filteredBookings = _bookings.where((booking) {
        final checkIn = _parseTimestamp(booking['check_in_date']);
        final checkOut = _parseTimestamp(booking['check_out_date']);
        if (checkIn == null && checkOut == null) return false;
        
        // Check if booking overlaps with filter range
        final bookingStart = checkIn ?? checkOut!;
        final bookingEnd = checkOut ?? checkIn!;
        
        return (bookingStart.isBefore(_bookingFilterRange!.end) || bookingStart.isAtSameMomentAs(_bookingFilterRange!.end))
            && (bookingEnd.isAfter(_bookingFilterRange!.start) || bookingEnd.isAtSameMomentAs(_bookingFilterRange!.start));
      }).toList();
    }
    
    // Sort by check-in date (most recent first)
    filteredBookings.sort((a, b) {
      final aTime = _parseTimestamp(a['check_in_date']);
      final bTime = _parseTimestamp(b['check_in_date']);
      if (aTime == null && bTime == null) return 0;
      if (aTime == null) return 1;
      if (bTime == null) return -1;
      return bTime.compareTo(aTime);
    });
    
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Text(
                    'Room Booking History',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const Spacer(),
                  Text(
                    '${filteredBookings.length} bookings',
                    style: TextStyle(color: Colors.grey[600]),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(now.year - 2),
                    lastDate: DateTime(now.year + 1),
                    initialDateRange: _bookingFilterRange,
                  );
                  if (picked != null) {
                    setState(() => _bookingFilterRange = picked);
                  }
                },
                icon: const Icon(Icons.date_range, size: 18),
                label: Text(
                  _bookingFilterRange == null
                      ? 'Filter by date range'
                      : '${DateFormat('MMM dd, yyyy').format(_bookingFilterRange!.start)} - ${DateFormat('MMM dd, yyyy').format(_bookingFilterRange!.end)}',
                ),
              ),
              if (_bookingFilterRange != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () => setState(() => _bookingFilterRange = null),
                      child: const Text('Clear filter'),
                    ),
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: filteredBookings.isEmpty
              ? ErrorHandler.buildEmptyWidget(
                  context,
                  message: 'No bookings found',
                )
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemCount: filteredBookings.length,
                  itemBuilder: (context, index) {
                    final booking = filteredBookings[index];
                    final guestName = (booking['profiles'] as Map<String, dynamic>?)?['full_name'] 
                        ?? booking['guest_name'] 
                        ?? 'Unknown Guest';
                    final roomNumber = (booking['rooms'] as Map<String, dynamic>?)?['room_number'] 
                        ?? booking['room_id']?.toString() 
                        ?? 'N/A';
                    final status = booking['status']?.toString() ?? 'Unknown';
                    final checkIn = _parseTimestamp(booking['check_in_date']);
                    final checkOut = _parseTimestamp(booking['check_out_date']);
                    final checkInStr = checkIn != null 
                        ? DateFormat('MMM dd, yyyy HH:mm').format(checkIn)
                        : 'N/A';
                    final checkOutStr = checkOut != null 
                        ? DateFormat('MMM dd, yyyy HH:mm').format(checkOut)
                        : 'N/A';
                    
                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 4),
                      child: ListTile(
                        leading: Icon(
                          _getBookingStatusIcon(status),
                          color: _getBookingStatusColor(status),
                        ),
                        title: Text(guestName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Room: $roomNumber'),
                            Text('Check-in: $checkInStr'),
                            if (checkOut != null) Text('Check-out: $checkOutStr'),
                            Text(
                              'Status: ${status.toUpperCase()}',
                              style: TextStyle(
                                color: _getBookingStatusColor(status),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        trailing: Chip(
                          label: Text(status.toUpperCase()),
                          backgroundColor: _getBookingStatusColor(status).withOpacity(0.1),
                          labelStyle: TextStyle(
                            color: _getBookingStatusColor(status),
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
  
  IconData _getBookingStatusIcon(String status) {
    switch (status.toLowerCase()) {
      case 'checked-in':
        return Icons.login;
      case 'checked-out':
        return Icons.logout;
      case 'pending':
        return Icons.pending;
      case 'cancelled':
        return Icons.cancel;
      default:
        return Icons.hotel;
    }
  }
  
  Color _getBookingStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'checked-in':
        return Colors.green[700]!;
      case 'checked-out':
        return Colors.blue[700]!;
      case 'pending':
        return Colors.orange[700]!;
      case 'cancelled':
        return Colors.red[700]!;
      default:
        return Colors.grey[700]!;
    }
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
  final String Function(String, {String? existingPriority}) getPriority;
  final Color Function(String) getPriorityColor;
  final bool isReceptionist;

  _RoomDataSource({
    required this.rooms,
    required this.onStatusUpdate,
    required this.getStatusColor,
    required this.getPriority,
    required this.getPriorityColor,
    this.isReceptionist = false,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= rooms.length) return null;
    
    final room = rooms[index];
    final status = room['status'] as String? ?? 'Unknown';
    final existingPriority = room['priority'] as String?;
    final priority = getPriority(status, existingPriority: existingPriority);
    
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
          isReceptionist
              ? Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit, size: 18),
                      onPressed: () => onStatusUpdate(room),
                      tooltip: 'Update Status & Priority',
                      color: Colors.blue[700],
                    ),
                  ],
                )
              : IconButton(
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