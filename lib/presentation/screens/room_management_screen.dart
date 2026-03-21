import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/core/utils/staff_auth_helper.dart';
import 'package:pzed_homes/presentation/widgets/context_aware_role_button.dart';
import 'package:pzed_homes/presentation/widgets/scrollable_list_with_arrows.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';

const List<String> _kRoomStatusOptions = ['Vacant', 'Occupied', 'Dirty', 'Cleaning', 'Maintenance'];

class RoomManagementScreen extends StatefulWidget {
  const RoomManagementScreen({super.key});

  @override
  State<RoomManagementScreen> createState() => _RoomManagementScreenState();
}

class _RoomManagementScreenState extends State<RoomManagementScreen> with SingleTickerProviderStateMixin {
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

  // Room pagination state (UI pagination; rooms fetched in chunks)
  int _rowsPerPage = 10;
  int _currentPage = 0;
  List<Map<String, dynamic>> _allRooms = [];
  List<Map<String, dynamic>> _currentPageRooms = [];
  Set<String> _checkedInRoomIds = {};

  // Room Status tab: bulk edit
  bool _roomStatusBulkEditMode = false;
  final Set<String> _roomStatusSelectedIds = {};
  bool _roomStatusBatchUpdating = false;

  // Manage Rooms tab (management only): filter, add room, bulk, room type prices
  final _manageFilterRoomNumberController = TextEditingController();
  String? _manageFilterStatus;
  bool _manageBulkEditMode = false;
  final Set<String> _manageSelectedIds = {};
  bool _manageBatchUpdating = false;
  List<Map<String, dynamic>> _manageRoomTypes = [];
  bool _manageRoomsLoading = false;
  final _roomNumberController = TextEditingController();
  final _floorController = TextEditingController();
  String? _selectedTypeId;
  String? _selectedTypeName;

  // Booking history: infinite scroll, paginated load (performance: no full preload)
  static const int _bookingsPageSize = 30;
  List<Map<String, dynamic>> _bookings = [];
  bool _bookingsHasMore = true;
  bool _bookingsLoadingMore = false;
  int _bookingsOffset = 0;
  final ScrollController _bookingsScrollController = ScrollController();
  DateTimeRange? _bookingFilterRange;
  final TextEditingController _bookingSearchController = TextEditingController();
  String _bookingSearchQuery = '';
  String _bookingStatusFilter = 'all';
  late TabController _tabController;

  bool get _isReceptionist {
    final authService = Provider.of<AuthService>(context, listen: false);
    final currentUser = authService.currentUser;
    return currentUser?.role == AppRole.receptionist ||
        authService.hasAssumedRole(AppRole.receptionist);
  }

  bool get _isManagement {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    return user?.roles.any((r) => r == AppRole.owner || r == AppRole.manager) ?? false;
  }

  bool get _isPorter {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    return user?.roles.any((r) => r == AppRole.porter) ?? false;
  }

  /// Receptionist, housekeeper, or management (when assuming receptionist) can update room status.
  bool get _canUpdateRoomStatus {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    if (user == null) return false;
    if (user.roles.any((r) => r == AppRole.receptionist || r == AppRole.housekeeper || r == AppRole.cleaner || r == AppRole.owner || r == AppRole.manager)) return true;
    if (authService.hasAssumedRole(AppRole.receptionist)) return true;
    return false;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);
    _loadRooms();
    _loadBookings();
    _startRoomRealtime();
    _bookingsScrollController.addListener(_onBookingsScroll);
  }

  void _onTabChanged() {
    if (mounted) setState(() {});
  }

  void _onBookingsScroll() {
    if (!_bookingsScrollController.hasClients) return;
    final pos = _bookingsScrollController.position;
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _loadMoreBookings();
    }
  }

  /// Loads first page of bookings (performance: small chunk, cached in DataService).
  /// Passes date filter when set; filter changes trigger reload.
  Future<void> _loadBookings() async {
    if (_isPorter) return;
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      final start = _bookingFilterRange?.start;
      final end = _bookingFilterRange?.end;
      final bookings = await _dataService.getBookings(
        limit: _bookingsPageSize,
        offset: 0,
        startDate: start,
        endDate: end,
        createdBy: _isManagement ? null : currentUserId,
      );
      if (!mounted) return;
      setState(() {
        _bookings = bookings;
        _bookingsOffset = bookings.length;
        _bookingsHasMore = bookings.length >= _bookingsPageSize;
      });
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG load booking history: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load booking history.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  /// Loads next page when user scrolls near bottom (infinite scroll).
  Future<void> _loadMoreBookings() async {
    if (_isPorter) return;
    if (_bookingsLoadingMore || !_bookingsHasMore) return;
    _bookingsLoadingMore = true;
    setState(() {});
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final currentUserId = authService.currentUser?.id;
      final start = _bookingFilterRange?.start;
      final end = _bookingFilterRange?.end;
      final bookings = await _dataService.getBookings(
        limit: _bookingsPageSize,
        offset: _bookingsOffset,
        startDate: start,
        endDate: end,
        createdBy: _isManagement ? null : currentUserId,
      );
      if (!mounted) return;
      setState(() {
        _bookings.addAll(bookings);
        _bookingsOffset += bookings.length;
        _bookingsHasMore = bookings.length >= _bookingsPageSize;
        _bookingsLoadingMore = false;
      });
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG load more bookings: $e\n$stackTrace');
      if (mounted) {
        setState(() => _bookingsLoadingMore = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load more bookings.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _loadRooms() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _dataService.getRooms(limit: 500, offset: 0),
        _dataService.getCheckedInRoomIds(),
      ]);
      final rooms = results[0] as List<Map<String, dynamic>>;
      final checkedInIds = results[1] as Set<String>;
      final adaptedRooms = rooms.map((r) {
        return {
          'id': r['id'],
          'room_number': r['room_number'] ?? r['id'],
          'type': r['type'],
          'status': _mapStatus(r['status']?.toString() ?? 'Vacant'),
        };
      }).toList();
      setState(() {
        _allRooms = adaptedRooms;
        _checkedInRoomIds = checkedInIds;
        _isLoading = false;
      });
      _updatePagination();
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG _loadRooms: $e\n$stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load rooms. Please check your connection and try again.',
          onRetry: _loadRooms,
          stackTrace: stackTrace,
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
    _tabController.removeListener(_onTabChanged);
    _bookingsScrollController.removeListener(_onBookingsScroll);
    _bookingsScrollController.dispose();
    _tabController.dispose();
    _roomsSub?.cancel();
    _refreshDebounce?.cancel();
    _bookingSearchController.dispose();
    _manageFilterRoomNumberController.dispose();
    _roomNumberController.dispose();
    _floorController.dispose();
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

  Future<void> _updateRoomStatus(String roomId, String newStatus) async {
    try {
    setState(() => _isLoading = true);
      await _dataService.updateRoomStatus(roomId, newStatus);
      final idx = _allRooms.indexWhere((r) => r['id'] == roomId);
      if (idx != -1) {
        setState(() {
          _allRooms[idx]['status'] = newStatus;
          _isLoading = false;
        });
        _updatePagination();
      } else {
        setState(() => _isLoading = false);
      }
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Room status updated to $newStatus.');
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG update room status: $e\n$stackTrace');
      if (mounted) {
        setState(() => _isLoading = false);
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update room status. Please try again.',
          stackTrace: stackTrace,
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

  DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    try {
      return DateTime.parse(timestamp.toString());
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _parseTimestamp: $e\n$stack');
      return null;
    }
  }

  // Calculate correct booking status based on check-out date (12:00 PM rule)
  String _calculateBookingStatus(Map<String, dynamic> booking) {
    final dbStatus = booking['status']?.toString().toLowerCase() ?? 'unknown';
    
    // If already terminal, return as is.
    if (dbStatus == 'checked-out' || dbStatus == 'checked_out') return 'Checked Out';
    if (dbStatus == 'cancelled') return 'Cancelled';
    if (dbStatus == 'rejected') return 'Rejected';
    if (dbStatus == 'expired' || dbStatus == 'no-show' || dbStatus == 'no show') {
      return 'Expired';
    }
    
    // Check if check-out date has passed 12:00 PM
    final checkOut = _parseTimestamp(booking['check_out_date']);
    if (checkOut != null) {
      // Set check-out time to 12:00 PM on the check-out date
      final checkOutExpiry = DateTime(
        checkOut.year,
        checkOut.month,
        checkOut.day,
        12, // 12:00 PM
        0,
      );
      
      final now = DateTime.now();
      
      // If elapsed (inclusive at 12:00 PM):
      // - checked-in stays are checked out
      // - pending bookings are expired/no-show
      if (!now.isBefore(checkOutExpiry)) {
        if (dbStatus == 'checked-in' || dbStatus == 'checked_in') return 'Checked Out';
        if (dbStatus == 'pending check-in' || dbStatus == 'pending_check_in' || dbStatus == 'pending') {
          return 'Expired';
        }
      }
    }
    
    // Return the database status for other cases
    switch (dbStatus) {
      case 'checked-in':
      case 'checked_in':
        return 'Checked In';
      case 'pending check-in':
      case 'pending_check_in':
      case 'pending':
        return 'Pending Check-In';
      default:
        return dbStatus.split('_').map((s) => s[0].toUpperCase() + s.substring(1)).join(' ');
    }
  }

  String _normalizeBookingStatusLabel(String status) {
    final s = status.trim().toLowerCase().replaceAll('_', '-');
    if (s == 'pending' || s == 'pending check-in' || s == 'pending checkin') return 'pending';
    if (s == 'checked-in' || s == 'checked in') return 'checked-in';
    if (s == 'checked-out' || s == 'checked out') return 'checked-out';
    if (s == 'cancelled') return 'cancelled';
    if (s == 'rejected') return 'rejected';
    if (s == 'expired' || s == 'no-show' || s == 'no show') return 'expired';
    return s;
  }

  /// Single status-update dialog for receptionist, housekeeper, or management (assuming receptionist).
  void _showUpdateStatusDialog(Map<String, dynamic> room) {
    final effectiveStatus = _checkedInRoomIds.contains(room['id']?.toString())
        ? 'Occupied'
        : (room['status'] as String? ?? 'Vacant');
    String selectedStatus = effectiveStatus;

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
                        if (value != null) setDialogState(() => selectedStatus = value);
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
                    _updateRoomStatus(room['id'], selectedStatus);
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

  void _updatePagination() {
    final startIndex = _currentPage * _rowsPerPage;
    final endIndex = (startIndex + _rowsPerPage).clamp(0, _allRooms.length);
    setState(() {
      _currentPageRooms = _allRooms.sublist(startIndex, endIndex);
    });
  }

  List<Map<String, dynamic>> get _manageFilteredRooms {
    var list = _allRooms;
    final q = _manageFilterRoomNumberController.text.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((r) => (r['room_number']?.toString() ?? '').toLowerCase().contains(q)).toList();
    }
    if (_manageFilterStatus != null && _manageFilterStatus!.isNotEmpty) {
      list = list.where((r) => (r['status']?.toString() ?? '') == _manageFilterStatus).toList();
    }
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final tabCount = _isPorter ? 1 : (_isManagement ? 3 : 2);
    if (_tabController.length != tabCount) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
        _tabController.dispose();
        _tabController = TabController(length: tabCount, vsync: this);
        setState(() {});
      });
    }
    final tabController = _tabController;
    return Scaffold(
      backgroundColor: Colors.grey[50],
      floatingActionButton: _isManagement && tabController.index == 2 && !_manageBulkEditMode
          ? FloatingActionButton(
              onPressed: _showAddRoomDialog,
              backgroundColor: Colors.blue[700],
              child: const Icon(Icons.add, color: Colors.white),
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: _buildHeader(context),
                ),
                TabBar(
                  controller: tabController,
                  labelColor: Colors.green[800],
                  unselectedLabelColor: Colors.grey[600],
                  indicatorColor: Colors.green[800],
                  tabs: [
                    if (!_isPorter) const Tab(text: 'Booking History', icon: Icon(Icons.history)),
                    const Tab(text: 'Room Status', icon: Icon(Icons.hotel)),
                    if (_isManagement) const Tab(text: 'Manage Rooms', icon: Icon(Icons.settings)),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: tabController,
                    children: [
                      if (!_isPorter) _buildBookingHistoryTab(context),
                      _buildRoomStatusTab(context),
                      if (_isManagement) _buildManageRoomsTab(context),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        return Column(
          children: [
            Expanded(
              child: Padding(
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
                  child: Scrollbar(
                    thumbVisibility: true,
                    child: SingleChildScrollView(
                      scrollDirection: Axis.vertical,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(
                          minHeight: MediaQuery.sizeOf(context).height - 200,
                          minWidth: constraints.maxWidth,
                        ),
                        child: PaginatedDataTable(
                          header: Container(
                            padding: const EdgeInsets.all(20),
                            child: isNarrow
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Room Status Overview',
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          IconButton(
                                            icon: Icon(_roomStatusBulkEditMode ? Icons.close : Icons.checklist),
                                            onPressed: () {
      setState(() {
                                                _roomStatusBulkEditMode = !_roomStatusBulkEditMode;
                                                if (!_roomStatusBulkEditMode) _roomStatusSelectedIds.clear();
                                              });
                                            },
                                            tooltip: _roomStatusBulkEditMode ? 'Exit bulk edit' : 'Bulk edit',
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.refresh),
                                            onPressed: _loadRooms,
                                            tooltip: 'Refresh',
                                          ),
                                        ],
                                      ),
                                    ],
                                  )
                                : Row(
                                    children: [
                                      Text(
                                        'Room Status Overview',
                                        style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                          fontWeight: FontWeight.bold,
                                          color: Colors.grey[800],
                                        ),
                                      ),
                                      const Spacer(),
                                      TextButton.icon(
                                        icon: Icon(_roomStatusBulkEditMode ? Icons.close : Icons.checklist),
                                        label: Text(_roomStatusBulkEditMode ? 'Exit bulk edit' : 'Bulk edit'),
                                        onPressed: () {
                                          setState(() {
                                            _roomStatusBulkEditMode = !_roomStatusBulkEditMode;
                                            if (!_roomStatusBulkEditMode) _roomStatusSelectedIds.clear();
                                          });
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.refresh),
                                        onPressed: _loadRooms,
                                        tooltip: 'Refresh',
                                      ),
                                    ],
                                  ),
                          ),
                          columns: [
                if (_roomStatusBulkEditMode)
                  const DataColumn(
                    label: Text('Select'),
                    numeric: false,
                  ),
                const DataColumn(
                  label: Text('Room #'),
                  numeric: false,
                ),
                const DataColumn(
                  label: Text('Room Type'),
                  numeric: false,
                ),
                const DataColumn(
                  label: Text('Status'),
                  numeric: false,
                ),
                const DataColumn(
                  label: Text('Actions'),
                  numeric: false,
                ),
              ],
              source: _RoomDataSource(
                // Feed the full list so PaginatedDataTable controls pagination correctly.
                rooms: _allRooms,
                checkedInRoomIds: _checkedInRoomIds,
                onStatusUpdate: _showUpdateStatusDialog,
                canUpdateStatus: _canUpdateRoomStatus,
                getStatusColor: _getStatusColor,
                bulkEditMode: _roomStatusBulkEditMode,
                selectedIds: _roomStatusSelectedIds,
                onSelectionChanged: (roomId, selected) {
                  setState(() {
                    if (selected) {
                      _roomStatusSelectedIds.add(roomId);
                    } else {
                      _roomStatusSelectedIds.remove(roomId);
                    }
                  });
                },
              ),
              rowsPerPage: _rowsPerPage,
              onPageChanged: (_) {},
              onRowsPerPageChanged: (newRowsPerPage) {
                setState(() {
                  _rowsPerPage = newRowsPerPage ?? 10;
                });
              },
              availableRowsPerPage: const [5, 10, 20, 50],
              showFirstLastButtons: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            if (_roomStatusBulkEditMode) _buildRoomStatusBulkBar(),
          ],
        );
      },
    );
  }

  Widget _buildRoomStatusBulkBar() {
    final count = _roomStatusSelectedIds.length;
    final setAvailable = TextButton.icon(
      onPressed: _roomStatusBatchUpdating || count == 0 ? null : () => _applyRoomStatusBatch('Vacant'),
      icon: const Icon(Icons.check_circle_outline, size: 20),
      label: const Text('Set to Available'),
    );
    final setMaintenance = TextButton.icon(
      onPressed: _roomStatusBatchUpdating || count == 0 ? null : () => _applyRoomStatusBatch('Maintenance'),
      icon: const Icon(Icons.build, size: 20),
      label: const Text('Set to Maintenance'),
    );
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.green[100],
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, -2))],
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 400;
            if (isNarrow) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    count == 0 ? 'Select rooms' : '$count selected',
                    style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[900]),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [setAvailable, setMaintenance],
                  ),
                ],
              );
            }
            return Row(
              children: [
                Text(
                  count == 0 ? 'Select rooms' : '$count selected',
                  style: TextStyle(fontWeight: FontWeight.w600, color: Colors.green[900]),
                ),
                const Spacer(),
                setAvailable,
                const SizedBox(width: 8),
                setMaintenance,
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _applyRoomStatusBatch(String newStatus) async {
    if (_roomStatusSelectedIds.isEmpty) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final staffId = StaffAuthHelper.requireStaffProfileId(
      context,
      authService: authService,
      supabase: _dataService.supabase,
    );
    if (staffId == null) return;
    final totalSelected = _roomStatusSelectedIds.length;
    setState(() => _roomStatusBatchUpdating = true);
    var successCount = 0;
    try {
      for (final id in _roomStatusSelectedIds) {
        try {
          await _dataService.updateRoomStatus(id, newStatus);
          successCount++;
        } catch (_) {}
      }
      await _dataService.logActivity(
        staffId,
        'Batch room status',
        'Room Management',
        'Set $successCount room(s) to $newStatus',
      );
      if (mounted) {
        setState(() {
          _roomStatusBatchUpdating = false;
          _roomStatusSelectedIds.clear();
          _roomStatusBulkEditMode = false;
        });
        ErrorHandler.showSuccessMessage(
          context,
          successCount == totalSelected
              ? 'Updated $successCount room(s) to ${newStatus == 'Vacant' ? 'Available' : newStatus}.'
              : 'Updated $successCount of $totalSelected room(s).',
        );
        _loadRooms();
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() => _roomStatusBatchUpdating = false);
        ErrorHandler.handleError(context, e, stackTrace: stackTrace);
      }
    }
  }

  Future<void> _loadManageRoomTypes() async {
    try {
      final types = await _dataService.getRoomTypes();
      if (mounted) setState(() {
        _manageRoomTypes = types;
        _manageRoomsLoading = false;
        if (_manageRoomTypes.isNotEmpty && _selectedTypeId == null) {
          _selectedTypeId = _manageRoomTypes.first['id']?.toString();
          _selectedTypeName = _manageRoomTypes.first['type']?.toString();
        }
      });
    } catch (e) {
      if (mounted) setState(() => _manageRoomsLoading = false);
    }
  }

  Widget _buildManageRoomsTab(BuildContext context) {
    if (_manageRoomTypes.isEmpty && !_manageRoomsLoading) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _manageRoomTypes.isEmpty && !_manageRoomsLoading) {
          setState(() => _manageRoomsLoading = true);
          _loadManageRoomTypes();
        }
      });
      return const Center(child: CircularProgressIndicator());
    }
    if (_manageRoomsLoading) return const Center(child: CircularProgressIndicator());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildManageFilterBar(),
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await _loadRooms();
              await _loadManageRoomTypes();
            },
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
              children: [
                _buildRoomTypePricesSection(),
                const SizedBox(height: 24),
                Text(
                  'Rooms',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (_manageFilteredRooms.isEmpty)
                  const Center(child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No rooms match the filter'),
                  ))
                else
                  ..._manageFilteredRooms.map((room) {
                    final roomId = room['id']?.toString() ?? '';
                    final selected = _manageSelectedIds.contains(roomId);
                    final number = room['room_number']?.toString() ?? '—';
                    final type = room['type']?.toString() ?? '—';
                    final status = room['status']?.toString() ?? '—';
                    final floor = room['floor']?.toString();
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: _manageBulkEditMode
                            ? Checkbox(
                                value: selected,
                                onChanged: (v) => setState(() {
                                  if (v == true) _manageSelectedIds.add(roomId);
                                  else _manageSelectedIds.remove(roomId);
                                }),
                              )
                            : CircleAvatar(
                                backgroundColor: Colors.blue[100],
                                child: Icon(Icons.door_front_door, color: Colors.blue[800]),
                              ),
                        title: Text('Room $number'),
                        subtitle: Text('$type • $status${floor != null && floor.isNotEmpty ? ' • Floor $floor' : ''}'),
                      ),
                    );
                  }),
              ],
            ),
          ),
        ),
        if (_manageBulkEditMode) _buildManageBulkBar(),
      ],
    );
  }

  Widget _buildManageFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.blue[50],
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: TextField(
              controller: _manageFilterRoomNumberController,
              decoration: const InputDecoration(
                labelText: 'Room number',
                hintText: 'Filter by number',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DropdownButtonFormField<String?>(
              value: _manageFilterStatus,
              decoration: const InputDecoration(
                labelText: 'Status',
                isDense: true,
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('All')),
                ..._kRoomStatusOptions.map((s) => DropdownMenuItem<String?>(value: s, child: Text(s))),
              ],
              onChanged: (v) => setState(() => _manageFilterStatus = v),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: _manageBulkEditMode ? 'Exit bulk edit' : 'Bulk edit',
            onPressed: () => setState(() {
              _manageBulkEditMode = !_manageBulkEditMode;
              if (!_manageBulkEditMode) _manageSelectedIds.clear();
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildRoomTypePricesSection() {
    if (_manageRoomTypes.isEmpty) return const SizedBox.shrink();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Room type prices',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._manageRoomTypes.map((rt) {
              final typeName = rt['type']?.toString() ?? 'Unknown';
              final priceKobo = (rt['price'] as num?)?.toInt() ?? 0;
              final priceNaira = PaymentService.koboToNaira(priceKobo);
              return ListTile(
                title: Text(typeName),
                subtitle: Text('₦${NumberFormat('#,##0.00').format(priceNaira)}'),
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () => _showEditRoomTypePriceDialog(rt),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  void _showEditRoomTypePriceDialog(Map<String, dynamic> roomType) {
    final id = roomType['id']?.toString();
    final typeName = roomType['type']?.toString() ?? 'Unknown';
    final priceKobo = int.tryParse(roomType['price']?.toString() ?? '0') ?? 0;
    final priceNaira = PaymentService.koboToNaira(priceKobo);
    final controller = TextEditingController(text: priceNaira.toStringAsFixed(2));
    final saving = [false];
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text('Edit price: $typeName'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Price (₦)'),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
          ),
          actions: [
            TextButton(
              onPressed: saving[0] ? null : () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: saving[0]
                  ? null
                  : () async {
                      final naira = double.tryParse(controller.text);
                      if (naira == null || naira < 0 || id == null) return;
                      setDialogState(() => saving[0] = true);
                      try {
                        await _dataService.updateRoomTypePrice(id, PaymentService.nairaToKobo(naira));
                        if (ctx.mounted) Navigator.pop(ctx);
                        if (mounted) {
                          ErrorHandler.showSuccessMessage(context, 'Price updated.');
                          _loadManageRoomTypes();
                        }
                      } on PostgrestException catch (e) {
                        if (mounted) {
                          setDialogState(() => saving[0] = false);
                          final message = e.code == '42501'
                              ? 'Permission Denied: Only Managers or Owners can update room type prices.'
                              : null;
                          ErrorHandler.handleError(context, e, customMessage: message, stackTrace: StackTrace.current);
                        }
                      } catch (e, stackTrace) {
                        if (mounted) {
                          setDialogState(() => saving[0] = false);
                          ErrorHandler.handleError(context, e, stackTrace: stackTrace);
                        }
                      }
                    },
              child: Text(saving[0] ? 'Saving...' : 'Save'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManageBulkBar() {
    final count = _manageSelectedIds.length;
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.blue[100],
          boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4, offset: const Offset(0, -2))],
        ),
        child: Row(
          children: [
            Text('$count selected', style: TextStyle(fontWeight: FontWeight.w600, color: Colors.blue[900])),
            const Spacer(),
            TextButton.icon(
              onPressed: _manageBatchUpdating || count == 0 ? null : () => _applyManageBatchStatus('Vacant'),
              icon: const Icon(Icons.check_circle_outline, size: 20),
              label: const Text('Set to Available'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: _manageBatchUpdating || count == 0 ? null : () => _applyManageBatchStatus('Maintenance'),
              icon: const Icon(Icons.build, size: 20),
              label: const Text('Set to Maintenance'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _applyManageBatchStatus(String newStatus) async {
    if (_manageSelectedIds.isEmpty) return;
    final authService = Provider.of<AuthService>(context, listen: false);
    final staffId = StaffAuthHelper.requireStaffProfileId(
      context,
      authService: authService,
      supabase: _dataService.supabase,
    );
    if (staffId == null) return;
    final totalSelected = _manageSelectedIds.length;
    setState(() => _manageBatchUpdating = true);
    var successCount = 0;
    try {
      for (final id in _manageSelectedIds) {
        try {
          await _dataService.updateRoomStatus(id, newStatus);
          successCount++;
        } catch (_) {}
      }
      await _dataService.logActivity(staffId, 'Batch room status', 'Room Management', 'Set $successCount room(s) to $newStatus');
      if (mounted) {
        setState(() {
          _manageBatchUpdating = false;
          _manageSelectedIds.clear();
          _manageBulkEditMode = false;
        });
        ErrorHandler.showSuccessMessage(
          context,
          successCount == totalSelected
              ? 'Updated $successCount room(s) to ${newStatus == 'Vacant' ? 'Available' : newStatus}.'
              : 'Updated $successCount of $totalSelected room(s).',
        );
        _loadRooms();
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() => _manageBatchUpdating = false);
        ErrorHandler.handleError(context, e, stackTrace: stackTrace);
      }
    }
  }

  void _showAddRoomDialog() {
    _roomNumberController.clear();
    _floorController.clear();
    setState(() {
      _selectedTypeId = _manageRoomTypes.isNotEmpty ? _manageRoomTypes.first['id']?.toString() : null;
      _selectedTypeName = _manageRoomTypes.isNotEmpty ? _manageRoomTypes.first['type']?.toString() : null;
    });
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Add Room'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: _roomNumberController,
                  decoration: const InputDecoration(labelText: 'Room Number *', hintText: 'e.g. 101, 202'),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  value: _selectedTypeId,
                  decoration: const InputDecoration(labelText: 'Room Type *'),
                  items: _manageRoomTypes
                      .map((rt) => DropdownMenuItem<String>(
                            value: rt['id']?.toString(),
                            child: Text(rt['type']?.toString() ?? 'Unknown'),
                          ))
                      .toList(),
                  onChanged: (id) {
                    if (id == null) return;
                    final rt = _manageRoomTypes.cast<Map<String, dynamic>>().firstWhere(
                          (r) => r['id']?.toString() == id,
                          orElse: () => <String, dynamic>{},
                        );
                    setDialogState(() {
                      _selectedTypeId = id;
                      _selectedTypeName = rt['type']?.toString();
                    });
                  },
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _floorController,
                  decoration: const InputDecoration(labelText: 'Floor', hintText: 'e.g. 1, 2'),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () async => await _saveNewRoom(ctx),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveNewRoom(BuildContext dialogContext) async {
    final roomNumber = _roomNumberController.text.trim();
    if (roomNumber.isEmpty) {
      ErrorHandler.showWarningMessage(context, 'Room number is required.');
      return;
    }
    if (_selectedTypeId == null || _selectedTypeName == null) {
      ErrorHandler.showWarningMessage(context, 'Please select a room type.');
      return;
    }
    final authService = Provider.of<AuthService>(context, listen: false);
    final staffId = StaffAuthHelper.requireStaffProfileId(
      context,
      authService: authService,
      supabase: _dataService.supabase,
    );
    if (staffId == null) return;
    try {
      await _dataService.addRoom(
        roomNumber: roomNumber,
        typeId: _selectedTypeId!,
        type: _selectedTypeName!,
        floor: _floorController.text.trim().isEmpty ? null : _floorController.text.trim(),
        status: 'Vacant',
      );
      await _dataService.logActivity(staffId, 'Added room', 'Room Management', 'Added Room $roomNumber');
      if (dialogContext.mounted) Navigator.pop(dialogContext);
      if (mounted) {
        ErrorHandler.showSuccessMessage(context, 'Room added successfully.');
        _loadRooms();
        _loadManageRoomTypes();
      }
    } on PostgrestException catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: e.code == '23505' ? 'Room "$roomNumber" already exists.' : ErrorHandler.getAdminErrorMessage(e, itemName: roomNumber, department: 'Room Management'),
        );
      }
    } catch (e, stackTrace) {
      if (mounted) ErrorHandler.handleError(context, e, customMessage: 'Failed to add room.', stackTrace: stackTrace);
    }
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
    
    // Filter by search query (guest name or room number)
    final searchQuery = _bookingSearchQuery.toLowerCase().trim();
    if (searchQuery.isNotEmpty) {
      filteredBookings = filteredBookings.where((booking) {
        final guestName = ((booking['profiles'] as Map<String, dynamic>?)?['full_name'] 
            ?? booking['guest_name'] 
            ?? 'Unknown Guest').toString().toLowerCase();
        final roomNumber = ((booking['rooms'] as Map<String, dynamic>?)?['room_number'] 
            ?? booking['room_id']?.toString() 
            ?? 'N/A').toString().toLowerCase();
        return guestName.contains(searchQuery) || roomNumber.contains(searchQuery);
      }).toList();
    }

    // Filter by booking status label
    if (_bookingStatusFilter != 'all') {
      filteredBookings = filteredBookings.where((booking) {
        final calculatedStatus = _calculateBookingStatus(booking);
        return _normalizeBookingStatusLabel(calculatedStatus) == _bookingStatusFilter;
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
              // Search field
              TextField(
                controller: _bookingSearchController,
                decoration: InputDecoration(
                  hintText: 'Search by guest name or room number...',
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _bookingSearchQuery.isNotEmpty
            ? IconButton(
                          icon: const Icon(Icons.clear),
                          onPressed: () {
                            setState(() {
                              _bookingSearchController.clear();
                              _bookingSearchQuery = '';
                            });
                          },
              )
            : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                onChanged: (value) {
                  setState(() {
                    _bookingSearchQuery = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _bookingStatusFilter,
                decoration: InputDecoration(
                  labelText: 'Status filter',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'all', child: Text('All statuses')),
                  DropdownMenuItem(value: 'pending', child: Text('Pending')),
                  DropdownMenuItem(value: 'checked-in', child: Text('Checked In')),
                  DropdownMenuItem(value: 'checked-out', child: Text('Checked Out')),
                  DropdownMenuItem(value: 'expired', child: Text('Expired')),
                  DropdownMenuItem(value: 'cancelled', child: Text('Cancelled')),
                  DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() => _bookingStatusFilter = value);
                },
              ),
              const SizedBox(height: 12),
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
                    _loadBookings(); // Reload with date filter (performance: server-side filter)
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
                      onPressed: () {
                        setState(() {
                          _bookingFilterRange = null;
                          _bookingStatusFilter = 'all';
                        });
                        _loadBookings(); // Reload without date filter
                      },
                      child: const Text('Clear filters'),
                    ),
                  ),
          ),
        ],
      ),
        ),
        Expanded(
          child: filteredBookings.isEmpty && !_bookingsLoadingMore
              ? ErrorHandler.buildEmptyWidget(
                  context,
                  message: 'No bookings found',
                )
              : ScrollableListViewWithArrows(
                  controller: _bookingsScrollController,
                  itemCount: filteredBookings.length + (_bookingsHasMore && _bookingsLoadingMore ? 1 : 0),
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  itemBuilder: (context, index) {
                    if (index >= filteredBookings.length) {
                      return const Padding(
                        padding: EdgeInsets.symmetric(vertical: 16),
                        child: Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    }
                    final booking = filteredBookings[index];
                    final guestName = (booking['profiles'] as Map<String, dynamic>?)?['full_name'] 
                        ?? booking['guest_name'] 
                        ?? 'Unknown Guest';
                    final roomNumber = (booking['rooms'] as Map<String, dynamic>?)?['room_number'] 
                        ?? booking['room_id']?.toString() 
                        ?? 'N/A';
                    // Calculate correct status based on check-out date (12:00 PM rule)
                    final calculatedStatus = _calculateBookingStatus(booking);
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
                          _getBookingStatusIcon(calculatedStatus),
                          color: _getBookingStatusColor(calculatedStatus),
                        ),
                        title: Text(guestName),
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Room: $roomNumber'),
                            Text('Check-in: $checkInStr'),
                            if (checkOut != null) Text('Check-out: $checkOutStr'),
                            Text(
                              'Status: ${calculatedStatus.toUpperCase()}',
                              style: TextStyle(
                                color: _getBookingStatusColor(calculatedStatus),
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        trailing: Chip(
                          label: Text(calculatedStatus.toUpperCase()),
                          backgroundColor: _getBookingStatusColor(calculatedStatus).withOpacity(0.1),
                          labelStyle: TextStyle(
                            color: _getBookingStatusColor(calculatedStatus),
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
      case 'checked in':
      case 'checked-in':
        return Icons.login;
      case 'checked out':
      case 'checked-out':
        return Icons.logout;
      case 'pending check-in':
      case 'pending':
        return Icons.pending;
      case 'cancelled':
        return Icons.cancel;
      case 'rejected':
        return Icons.block;
      case 'expired':
      case 'no-show':
      case 'no show':
        return Icons.history_toggle_off;
      default:
        return Icons.hotel;
    }
  }
  
  Color _getBookingStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'checked in':
      case 'checked-in':
        return Colors.green[700]!;
      case 'checked out':
      case 'checked-out':
        return Colors.blue[700]!;
      case 'pending check-in':
      case 'pending':
        return Colors.orange[700]!;
      case 'cancelled':
        return Colors.red[700]!;
      case 'rejected':
        return Colors.red[900]!;
      case 'expired':
      case 'no-show':
      case 'no show':
        return Colors.blueGrey[700]!;
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
                    'Room Management',
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green[800],
                    ),
                  ),
                        const SizedBox(height: 8),
                  Text(
                    'Booking history, room status, and housekeeping',
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
  final Set<String> checkedInRoomIds;
  final Function(Map<String, dynamic>) onStatusUpdate;
  final bool canUpdateStatus;
  final Color Function(String) getStatusColor;
  final bool bulkEditMode;
  final Set<String> selectedIds;
  final void Function(String roomId, bool selected) onSelectionChanged;

  _RoomDataSource({
    required this.rooms,
    required this.checkedInRoomIds,
    required this.onStatusUpdate,
    required this.canUpdateStatus,
    required this.getStatusColor,
    required this.bulkEditMode,
    required this.selectedIds,
    required this.onSelectionChanged,
  });

  @override
  DataRow? getRow(int index) {
    if (index >= rooms.length) return null;
    final room = rooms[index];
    final roomId = room['id']?.toString() ?? '';
    final effectiveStatus = checkedInRoomIds.contains(roomId)
        ? 'Occupied'
        : (room['status'] as String? ?? 'Unknown');
    final cells = <DataCell>[];
    if (bulkEditMode) {
      cells.add(
        DataCell(
          Checkbox(
            value: selectedIds.contains(roomId),
            onChanged: (v) => onSelectionChanged(roomId, v == true),
                  ),
                ),
    );
  }
    cells.addAll([
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
            effectiveStatus,
            style: TextStyle(
              color: getStatusColor(effectiveStatus),
              fontWeight: FontWeight.w500,
              fontSize: 12,
            ),
          ),
          backgroundColor: getStatusColor(effectiveStatus).withOpacity(0.1),
          side: BorderSide(color: getStatusColor(effectiveStatus).withOpacity(0.3)),
        ),
      ),
      DataCell(
        canUpdateStatus
            ? IconButton(
                icon: const Icon(Icons.edit, size: 18),
                onPressed: () => onStatusUpdate(room),
                tooltip: 'Update Status',
                color: Colors.blue[700],
              )
            : const SizedBox.shrink(),
      ),
    ]);
    return DataRow(cells: cells);
  }

  @override
  bool get isRowCountApproximate => false;

  @override
  int get rowCount => rooms.length;

  @override
  int get selectedRowCount => 0;
}