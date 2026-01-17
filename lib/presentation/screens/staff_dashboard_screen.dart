import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/core/services/payment_service.dart';
import 'package:pzed_homes/data/models/user.dart';

/// Personalized dashboard for individual staff members
/// Shows only their own sales, transactions, and department-specific data
class StaffDashboardScreen extends StatefulWidget {
  const StaffDashboardScreen({super.key});

  @override
  State<StaffDashboardScreen> createState() => _StaffDashboardScreenState();
}

class _StaffDashboardScreenState extends State<StaffDashboardScreen> {
  final DataService _dataService = DataService();
  
  bool _isLoading = true;
  bool _showDepartmentView = false; // Toggle between personal and department view
  
  // Clock-in/Clock-out state
  bool _isClockedIn = false;
  bool _isLoadingAttendance = true;
  Map<String, dynamic>? _lastAttendanceRecord;
  
  // Personal stats
  Map<String, dynamic> _personalStats = {};
  List<Map<String, dynamic>> _myTransactions = [];
  List<Map<String, dynamic>> _myDebts = [];
  
  // Department stats
  Map<String, dynamic> _departmentStats = {};
  List<Map<String, dynamic>> _departmentTransactions = [];
  List<Map<String, dynamic>> _departmentDebts = [];
  List<Map<String, dynamic>> _departmentStockLevels = [];
  
  // Receptionist booking data
  List<Map<String, dynamic>> _bookings = [];
  Map<String, dynamic> _bookingStats = {};
  
  // Housekeeper/Cleaner room data
  List<Map<String, dynamic>> _rooms = [];
  Map<String, dynamic> _roomStats = {};
  
  String _timeFilter = 'today'; // today, week, month

  @override
  void initState() {
    super.initState();
    _loadData();
    // Sync clock-in status with AuthService
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthService>(context, listen: false);
      if (mounted) {
        setState(() {
          _isClockedIn = auth.isClockedIn;
        });
      }
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final staffId = user?.id ?? 'unknown';
    final userRole = authService.isRoleAssumed 
        ? (authService.assumedRole ?? user?.role) 
        : user?.role;
    
    // Determine department based on role
    String? department = _getDepartmentFromRole(
      userRole,
      profileDepartment: user?.department,
    );
    
    try {
      // Load personal data
      await _loadPersonalData(staffId, department);
      
      // Load department data if applicable
      if (department != null) {
        await _loadDepartmentData(department);
        await _loadDepartmentStockLevels(department);
      }
      
      // Load booking data for receptionists
      if (userRole == AppRole.receptionist) {
        await _loadBookingData();
      }
      
      // Load room data for housekeepers and cleaners
      if (userRole == AppRole.housekeeper || userRole == AppRole.cleaner) {
        await _loadRoomData(staffId);
      }
      
      // Load attendance status
      await _fetchLastAttendance();
      
      if (mounted) {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingAttendance = false;
        });
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load dashboard data. Please check your connection and try again.',
          onRetry: _loadData,
        );
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchLastAttendance() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUser == null) {
        if (mounted) {
          setState(() => _isLoadingAttendance = false);
        }
        return null;
      }
      
      // Get current attendance from database
      final attendance = await _dataService.getCurrentAttendance(authService.currentUser!.id);
      
      // Update local state to match AuthService
      if (mounted) {
        setState(() {
          _isClockedIn = authService.isClockedIn;
          _lastAttendanceRecord = attendance;
          _isLoadingAttendance = false;
        });
      }
      
      return attendance;
    } catch (e) {
      // If error, check AuthService state
      final authService = Provider.of<AuthService>(context, listen: false);
      if (mounted) {
        setState(() {
          _isClockedIn = authService.isClockedIn;
          _isLoadingAttendance = false;
        });
      }
      return null;
    }
  }

  Future<void> _handleClockIn() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.clockIn();
      if (mounted) {
        setState(() {
          _isClockedIn = true;
          _lastAttendanceRecord = {
            'clock_in_time': authService.clockInTime?.toIso8601String() ?? DateTime.now().toIso8601String(),
          };
        });
        ErrorHandler.showSuccessMessage(
          context,
          'Clocked in successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to clock in. Please try again.',
        );
      }
    }
  }

  Future<void> _handleClockOut() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.clockOut();
      if (mounted) {
        setState(() {
          _isClockedIn = false;
          _lastAttendanceRecord = null;
        });
        ErrorHandler.showSuccessMessage(
          context,
          'Clocked out successfully',
        );
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to clock out. Please try again.',
        );
      }
    }
  }

  String? _getDepartmentFromRole(AppRole? role, {String? profileDepartment}) {
    switch (role) {
      case AppRole.vip_bartender:
        return 'vip_bar';
      case AppRole.outside_bartender:
        return 'outside_bar';
      case AppRole.bartender:
        // Fallback to profile department if available
        if (profileDepartment == 'vip_bar' || profileDepartment == 'outside_bar') {
          return profileDepartment;
        }
        return null;
      case AppRole.receptionist:
        return 'mini_mart';
      case AppRole.kitchen_staff:
        return 'kitchen';
      case AppRole.housekeeper:
        return 'housekeeping';
      case AppRole.laundry_attendant:
        return 'laundry';
      case AppRole.cleaner:
        return 'housekeeping';
      default:
        return null;
    }
  }

  Future<void> _loadPersonalData(String staffId, String? department) async {
    // Load all transactions
    final allTransactions = await _dataService.getStockTransactions();
    
    // Filter to only this staff member's transactions
    _myTransactions = allTransactions.where((t) => 
      t['staff_id'] == staffId
    ).toList();
    
    // Apply time filter
    _myTransactions = _filterByTime(_myTransactions);
    
    // Calculate personal stats
    double totalSales = 0;
    int transactionCount = 0;
    double cashSales = 0;
    double cardSales = 0;
    double transferSales = 0;
    double creditSales = 0;
    
    for (var transaction in _myTransactions) {
      if (transaction['type'] == 'sale') {
        final amount = (transaction['total_amount'] as num?)?.toDouble() ?? 0.0;
        totalSales += amount.abs();
        transactionCount++;
        
        final paymentMethod = transaction['payment_method']?.toString().toLowerCase();
        switch (paymentMethod) {
          case 'cash':
            cashSales += amount.abs();
            break;
          case 'card':
            cardSales += amount.abs();
            break;
          case 'transfer':
            transferSales += amount.abs();
            break;
          case 'credit':
            creditSales += amount.abs();
            break;
        }
      }
    }
    
    // Load debts created by this staff member
    final allDebts = await _dataService.getDebts();
    _myDebts = allDebts.where((d) => 
      d['recorded_by'] == staffId || 
      d['staff_id'] == staffId
    ).toList();
    
    _personalStats = {
      'total_sales': totalSales,
      'transaction_count': transactionCount,
      'cash_sales': cashSales,
      'card_sales': cardSales,
      'transfer_sales': transferSales,
      'credit_sales': creditSales,
      'pending_debts': _myDebts.where((d) => d['status'] == 'outstanding' || d['status'] == 'partially_paid').length,
      'total_debt_amount': _myDebts
          .where((d) => d['status'] == 'outstanding' || d['status'] == 'partially_paid')
          .fold<double>(0, (sum, d) => sum + ((d['amount'] as num?)?.toDouble() ?? 0)),
    };
  }

  Future<void> _loadDepartmentData(String department) async {
    // Load all transactions for the department
    final allTransactions = await _dataService.getStockTransactions();
    
    _departmentTransactions = allTransactions.where((t) => 
      t['department'] == department || 
      t['location'] == department
    ).toList();
    
    // Apply time filter
    _departmentTransactions = _filterByTime(_departmentTransactions);
    
    // Calculate department stats
    double totalSales = 0;
    int transactionCount = 0;
    Map<String, double> staffSales = {};
    
    for (var transaction in _departmentTransactions) {
      if (transaction['type'] == 'sale') {
        final amount = (transaction['total_amount'] as num?)?.toDouble() ?? 0.0;
        totalSales += amount.abs();
        transactionCount++;
        
        final staffId = transaction['staff_id']?.toString() ?? 'unknown';
        staffSales[staffId] = (staffSales[staffId] ?? 0) + amount.abs();
      }
    }
    
    // Load department debts
    final allDebts = await _dataService.getDebts();
    _departmentDebts = allDebts.where((d) => 
      d['department'] == department
    ).toList();
    
    _departmentStats = {
      'total_sales': totalSales,
      'transaction_count': transactionCount,
      'staff_sales': staffSales,
      'pending_debts': _departmentDebts.where((d) => d['status'] == 'outstanding' || d['status'] == 'partially_paid').length,
      'total_debt_amount': _departmentDebts
          .where((d) => d['status'] == 'outstanding' || d['status'] == 'partially_paid')
          .fold<double>(0, (sum, d) => sum + ((d['amount'] as num?)?.toDouble() ?? 0)),
    };
  }

  Future<void> _loadDepartmentStockLevels(String department) async {
    final locationName = _getLocationNameForDepartment(department);
    if (locationName == null) {
      _departmentStockLevels = [];
      return;
    }

    final stockLevels = await _dataService.getStockLevels(locationName: locationName);
    _departmentStockLevels = stockLevels;
  }

  Future<void> _loadBookingData() async {
    // Load all bookings
    final allBookings = await _dataService.getBookings();
    
    // Filter by time
    _bookings = _filterByTime(allBookings);
    
    // Calculate booking stats
    int pendingBookings = 0;
    int confirmedBookings = 0;
    int checkedInBookings = 0;
    int checkedOutBookings = 0;
    double totalRevenue = 0;
    
    for (var booking in _bookings) {
      final status = booking['status']?.toString().toLowerCase();
      switch (status) {
        case 'pending':
          pendingBookings++;
          break;
        case 'confirmed':
          confirmedBookings++;
          break;
        case 'checked_in':
          checkedInBookings++;
          break;
        case 'checked_out':
          checkedOutBookings++;
          // Use paid_amount instead of total_amount for actual revenue
          final amount = (booking['paid_amount'] as num?)?.toDouble() ?? 0.0;
          totalRevenue += amount;
          break;
      }
    }
    
    _bookingStats = {
      'total_bookings': _bookings.length,
      'pending': pendingBookings,
      'confirmed': confirmedBookings,
      'checked_in': checkedInBookings,
      'checked_out': checkedOutBookings,
      'total_revenue': totalRevenue,
    };
  }

  Future<void> _loadRoomData(String staffId) async {
    // Load all rooms
    final allRooms = await _dataService.getRooms();
    
    // Filter rooms cleaned by this staff member
    final myCleanedRooms = allRooms.where((r) => 
      r['cleaned_by'] == staffId || r['assigned_to'] == staffId
    ).toList();
    
    // Calculate room stats
    int roomsCleanedToday = 0;
    int roomsCleanedWeek = 0;
    int roomsNeedCleaning = 0;
    int roomsOccupied = 0;
    int roomsAvailable = 0;
    
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final weekAgo = now.subtract(const Duration(days: 7));
    
    for (var room in allRooms) {
      final status = room['status']?.toString().toLowerCase();
      final cleanedAt = room['last_cleaned']?.toString();
      
      // Count occupied vs available
      if (status == 'Occupied') {
        roomsOccupied++;
      } else if (status == 'Vacant' || status == 'Dirty') {
        roomsAvailable++;
      }
      
      // Count rooms needing cleaning
      if (status == 'dirty' || status == 'needs_cleaning') {
        roomsNeedCleaning++;
      }
      
      // Count cleaned rooms by this staff
      if (cleanedAt != null && myCleanedRooms.any((r) => r['id'] == room['id'])) {
        try {
          final cleanedDate = DateTime.parse(cleanedAt);
          if (cleanedDate.isAfter(today)) {
            roomsCleanedToday++;
          }
          if (cleanedDate.isAfter(weekAgo)) {
            roomsCleanedWeek++;
          }
        } catch (e) {
          // Invalid date format
        }
      }
    }
    
    _rooms = allRooms;
    _roomStats = {
      'cleaned_today': roomsCleanedToday,
      'cleaned_week': roomsCleanedWeek,
      'need_cleaning': roomsNeedCleaning,
      'occupied': roomsOccupied,
      'available': roomsAvailable,
      'total_rooms': allRooms.length,
    };
  }

  List<Map<String, dynamic>> _filterByTime(List<Map<String, dynamic>> transactions) {
    final now = DateTime.now();
    DateTime startDate;
    
    switch (_timeFilter) {
      case 'today':
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case 'week':
        startDate = now.subtract(const Duration(days: 7));
        break;
      case 'month':
        startDate = DateTime(now.year, now.month, 1);
        break;
      default:
        return transactions;
    }
    
    return transactions.where((t) {
      final timestamp = t['timestamp']?.toString() ?? t['date']?.toString();
      if (timestamp == null) return false;
      
      try {
        final date = DateTime.parse(timestamp);
        return date.isAfter(startDate);
      } catch (e) {
        return false;
      }
    }).toList();
  }

  String _formatKobo(num value) {
    return NumberFormat('#,##0.00').format(
      PaymentService.koboToNaira(value.toInt()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    final user = authService.currentUser;
    final userRole = authService.isRoleAssumed 
        ? (authService.assumedRole ?? user?.role) 
        : user?.role;
    final department = _getDepartmentFromRole(
      userRole,
      profileDepartment: user?.department,
    );
    
    return Scaffold(
      appBar: AppBar(
        title: Text(_showDepartmentView ? 'Department Dashboard' : 'My Dashboard'),
        backgroundColor: Colors.green[700],
        foregroundColor: Colors.white,
        actions: [
          if (department != null)
            IconButton(
              icon: Icon(_showDepartmentView ? Icons.person : Icons.people),
              tooltip: _showDepartmentView ? 'My Dashboard' : 'Department Dashboard',
              onPressed: () {
                setState(() {
                  _showDepartmentView = !_showDepartmentView;
                });
              },
            ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(user),
                  const SizedBox(height: 16),
                  _buildAttendanceCard(),
                  const SizedBox(height: 16),
                  _buildTimeFilter(),
                  const SizedBox(height: 16),
                  _showDepartmentView
                      ? _buildDepartmentView(department)
                      : _buildPersonalView(),
                ],
              ),
            ),
    );
  }

  Widget _buildHeader(AppUser? user) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Welcome, ${user?.name ?? 'Staff Member'}!',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              'Role: ${user?.role.toString().split('.').last ?? 'Unknown'}',
              style: TextStyle(color: Colors.grey[600]),
            ),
            const SizedBox(height: 4),
            Text(
              _showDepartmentView 
                  ? 'Viewing department-wide performance'
                  : 'Viewing your personal performance',
              style: TextStyle(color: Colors.blue[700], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeFilter() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(
          children: [
            const Text('Time Period: ', style: TextStyle(fontWeight: FontWeight.w500)),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Today'),
              selected: _timeFilter == 'today',
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _timeFilter = 'today';
                    _loadData();
                  });
                }
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('This Week'),
              selected: _timeFilter == 'week',
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _timeFilter = 'week';
                    _loadData();
                  });
                }
              },
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('This Month'),
              selected: _timeFilter == 'month',
              onSelected: (selected) {
                if (selected) {
                  setState(() {
                    _timeFilter = 'month';
                    _loadData();
                  });
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPersonalView() {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = authService.currentUser;
    final userRole = authService.isRoleAssumed 
        ? (authService.assumedRole ?? user?.role) 
        : user?.role;
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'My Performance',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),

        if (_departmentStockLevels.isNotEmpty) ...[
          _buildDepartmentStockLevels(),
          const SizedBox(height: 24),
        ],
        
        // Show booking stats for receptionist
        if (userRole == AppRole.receptionist) ...[
          _buildBookingStats(),
          const SizedBox(height: 24),
          _buildRecentBookings(),
          const SizedBox(height: 24),
        ],
        
        // Show room stats for housekeeper/cleaner
        if (userRole == AppRole.housekeeper || userRole == AppRole.cleaner) ...[
          _buildRoomStats(),
          const SizedBox(height: 24),
          _buildRoomsList(),
          const SizedBox(height: 24),
        ],
        
        // Show sales stats for sales roles
        if (userRole == AppRole.vip_bartender ||
            userRole == AppRole.outside_bartender ||
            userRole == AppRole.bartender ||
            userRole == AppRole.receptionist ||
            userRole == AppRole.kitchen_staff) ...[
          _buildStatsGrid(_personalStats, isPersonal: true),
          const SizedBox(height: 24),
          _buildPaymentMethodBreakdown(_personalStats),
          const SizedBox(height: 24),
          _buildMyDebts(),
          const SizedBox(height: 24),
          _buildMyTransactions(),
        ],
      ],
    );
  }

  Widget _buildDepartmentView(String? department) {
    if (department == null) {
      return const Center(
        child: Text('Department view not available for your role'),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_getDepartmentDisplayName(department)} Performance',
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        _buildStatsGrid(_departmentStats, isPersonal: false),
        const SizedBox(height: 24),
        if (_departmentStockLevels.isNotEmpty) ...[
          _buildDepartmentStockLevels(),
          const SizedBox(height: 24),
        ],
        _buildStaffPerformance(),
        const SizedBox(height: 24),
        _buildDepartmentDebts(),
        const SizedBox(height: 24),
        _buildDepartmentTransactions(),
      ],
    );
  }

  Widget _buildDepartmentStockLevels() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Department Stock Levels',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._departmentStockLevels.take(10).map((item) {
              final name = item['name']?.toString() ?? 'Unknown';
              final qty = item['current_stock']?.toString() ?? '0';
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(child: Text(name)),
                    Text(qty, style: const TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }),
            if (_departmentStockLevels.length > 10)
              Text(
                'Showing 10 of ${_departmentStockLevels.length} items',
                style: TextStyle(color: Colors.grey[600], fontSize: 12),
              ),
          ],
        ),
      ),
    );
  }

  String _getDepartmentDisplayName(String department) {
    switch (department) {
      case 'vip_bar':
        return 'VIP Bar';
      case 'outside_bar':
        return 'Outside Bar';
      case 'mini_mart':
        return 'Mini Mart';
      case 'kitchen':
        return 'Kitchen';
      default:
        return department;
    }
  }

  String? _getLocationNameForDepartment(String department) {
    switch (department) {
      case 'vip_bar':
        return 'VIP Bar';
      case 'outside_bar':
        return 'Outside Bar';
      case 'mini_mart':
        return 'Mini Mart';
      case 'kitchen':
        return 'Kitchen';
      case 'housekeeping':
        return 'Housekeeping';
      case 'laundry':
        return 'Laundry';
      case 'reception':
        return 'Reception';
      default:
        return null;
    }
  }

  Widget _buildStatsGrid(Map<String, dynamic> stats, {required bool isPersonal}) {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Total Sales',
          '₦${_formatKobo(stats['total_sales'] ?? 0)}',
          Icons.attach_money,
          Colors.green,
        ),
        _buildStatCard(
          'Transactions',
          '${stats['transaction_count'] ?? 0}',
          Icons.receipt,
          Colors.blue,
        ),
        _buildStatCard(
          'Pending Debts',
          '${stats['pending_debts'] ?? 0}',
          Icons.money_off,
          Colors.orange,
        ),
        _buildStatCard(
          'Debt Amount',
          '₦${_formatKobo(stats['total_debt_amount'] ?? 0)}',
          Icons.account_balance_wallet,
          Colors.red,
        ),
      ],
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 32),
            const SizedBox(height: 8),
            Text(
              value,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: color,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethodBreakdown(Map<String, dynamic> stats) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Payment Methods',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            _buildPaymentRow('Cash', stats['cash_sales'] ?? 0, Colors.green),
            _buildPaymentRow('Card', stats['card_sales'] ?? 0, Colors.blue),
            _buildPaymentRow('Transfer', stats['transfer_sales'] ?? 0, Colors.purple),
            _buildPaymentRow('Credit', stats['credit_sales'] ?? 0, Colors.orange),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentRow(String method, double amount, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(method)),
          Text(
            '₦${_formatKobo(amount)}',
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildMyDebts() {
    if (_myDebts.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No debts recorded',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }
    
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'My Recorded Debts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _myDebts.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final debt = _myDebts[index];
              return ListTile(
                title: Text(debt['debtor_name'] ?? 'Unknown'),
                subtitle: Text(debt['reason'] ?? ''),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₦${_formatKobo(debt['amount'] ?? 0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Chip(
                      label: Text(
                        debt['status'] ?? 'outstanding',
                        style: const TextStyle(fontSize: 10),
                      ),
                      backgroundColor: debt['status'] == 'paid' 
                          ? Colors.green[100] 
                          : Colors.orange[100],
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildMyTransactions() {
    if (_myTransactions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No transactions found',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }
    
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'My Transactions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _myTransactions.take(10).length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final transaction = _myTransactions[index];
              return ListTile(
                leading: Icon(
                  transaction['type'] == 'sale' ? Icons.shopping_cart : Icons.inventory,
                  color: Colors.green[700],
                ),
                title: Text(transaction['item_name'] ?? 'Unknown Item'),
                subtitle: Text(
                  '${transaction['payment_method'] ?? 'N/A'} • ${transaction['timestamp'] ?? ''}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  '₦${_formatKobo((transaction['total_amount'] as num?)?.abs() ?? 0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildStaffPerformance() {
    final staffSales = _departmentStats['staff_sales'] as Map<String, double>? ?? {};
    
    if (staffSales.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No staff performance data',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }
    
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Staff Performance',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...staffSales.entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text('Staff ${entry.key}')),
                    Text(
                      '₦${_formatKobo(entry.value)}',
                      style: const TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentDebts() {
    if (_departmentDebts.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No department debts',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }
    
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Department Debts',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _departmentDebts.take(10).length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final debt = _departmentDebts[index];
              return ListTile(
                title: Text(debt['debtor_name'] ?? 'Unknown'),
                subtitle: Text(debt['reason'] ?? ''),
                trailing: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₦${_formatKobo(debt['amount'] ?? 0)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Chip(
                      label: Text(
                        debt['status'] ?? 'outstanding',
                        style: const TextStyle(fontSize: 10),
                      ),
                      backgroundColor: debt['status'] == 'paid' 
                          ? Colors.green[100] 
                          : Colors.orange[100],
                      padding: EdgeInsets.zero,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ),
                onTap: debt['status'] == 'outstanding' || debt['status'] == 'partially_paid' 
                    ? () => _showMarkDebtPaidDialog(debt, index)
                    : null,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildDepartmentTransactions() {
    if (_departmentTransactions.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No department transactions',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }
    
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Department Transactions',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _departmentTransactions.take(10).length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final transaction = _departmentTransactions[index];
              return ListTile(
                leading: Icon(
                  transaction['type'] == 'sale' ? Icons.shopping_cart : Icons.inventory,
                  color: Colors.green[700],
                ),
                title: Text(transaction['item_name'] ?? 'Unknown Item'),
                subtitle: Text(
                  'Staff: ${transaction['staff_id'] ?? 'N/A'} • ${transaction['payment_method'] ?? 'N/A'}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Text(
                  '₦${_formatKobo((transaction['total_amount'] as num?)?.abs() ?? 0)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showMarkDebtPaidDialog(Map<String, dynamic> debt, int index) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Mark Debt as Paid'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Debtor: ${debt['debtor_name']}'),
            const SizedBox(height: 8),
            Text('Amount: ₦${_formatKobo(debt['amount'] ?? 0)}'),
            const SizedBox(height: 16),
            const Text('Customer has paid this debt?'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                // Use proper payment recording method instead of local state update
                final debt = _departmentDebts[index];
                final authService = Provider.of<AuthService>(context, listen: false);
                final userId = authService.currentUser?.id ?? 'system';
                
                // Record full payment
                await _dataService.recordDebtPayment(
                  debtId: debt['id'] as String,
                  amount: (debt['amount'] as int? ?? 0) - (debt['paid_amount'] as int? ?? 0), // Remaining amount
                  paymentMethod: 'cash',
                  collectedBy: userId,
                  createdBy: userId,
                  paymentDate: DateTime.now(),
                );
                
                Navigator.pop(context);
                if (mounted) {
                  ErrorHandler.showSuccessMessage(
                    context,
                    'Debt payment recorded successfully!',
                  );
                  _loadData();
                }
              } catch (e) {
                if (mounted) {
                  ErrorHandler.handleError(
                    context,
                    e,
                    customMessage: 'Failed to record payment. Please try again.',
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            child: const Text('Mark as Paid'),
          ),
        ],
      ),
    );
  }

  // Booking widgets for receptionist
  Widget _buildBookingStats() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Total Bookings',
          '${_bookingStats['total_bookings'] ?? 0}',
          Icons.book_online,
          Colors.blue,
        ),
        _buildStatCard(
          'Pending',
          '${_bookingStats['pending'] ?? 0}',
          Icons.pending,
          Colors.orange,
        ),
        _buildStatCard(
          'Confirmed',
          '${_bookingStats['confirmed'] ?? 0}',
          Icons.check_circle,
          Colors.green,
        ),
        _buildStatCard(
          'Checked In',
          '${_bookingStats['checked_in'] ?? 0}',
          Icons.login,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildRecentBookings() {
    if (_bookings.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Text(
              'No bookings found',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ),
        ),
      );
    }
    
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Recent Bookings',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _bookings.take(10).length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final booking = _bookings[index];
              final guestName = (booking['profiles'] as Map<String, dynamic>?)?['full_name'] ?? 'Unknown Guest';
              final roomNumber = (booking['rooms'] as Map<String, dynamic>?)?['room_number'] ?? 'N/A';
              final status = booking['status'] ?? 'unknown';
              
              return ListTile(
                leading: Icon(
                  Icons.hotel,
                  color: Colors.blue[700],
                ),
                title: Text(guestName),
                subtitle: Text(
                  'Room $roomNumber • ${booking['check_in_date'] ?? 'N/A'}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Chip(
                  label: Text(
                    status,
                    style: const TextStyle(fontSize: 10),
                  ),
                  backgroundColor: _getStatusColor(status),
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'pending':
        return Colors.orange[100]!;
      case 'confirmed':
        return Colors.blue[100]!;
      case 'checked_in':
        return Colors.green[100]!;
      case 'checked_out':
        return Colors.grey[300]!;
      default:
        return Colors.grey[200]!;
    }
  }

  // Room widgets for housekeeper/cleaner
  Widget _buildRoomStats() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      childAspectRatio: 1.5,
      children: [
        _buildStatCard(
          'Cleaned Today',
          '${_roomStats['cleaned_today'] ?? 0}',
          Icons.cleaning_services,
          Colors.green,
        ),
        _buildStatCard(
          'Cleaned This Week',
          '${_roomStats['cleaned_week'] ?? 0}',
          Icons.check_circle,
          Colors.blue,
        ),
        _buildStatCard(
          'Need Cleaning',
          '${_roomStats['need_cleaning'] ?? 0}',
          Icons.warning,
          Colors.orange,
        ),
        _buildStatCard(
          'Occupied Rooms',
          '${_roomStats['occupied'] ?? 0}',
          Icons.hotel,
          Colors.purple,
        ),
      ],
    );
  }

  Widget _buildRoomsList() {
    final roomsNeedingCleaning = _rooms.where((r) => 
      r['status']?.toString().toLowerCase() == 'dirty' || 
      r['status']?.toString().toLowerCase() == 'needs_cleaning'
    ).toList();
    
    if (roomsNeedingCleaning.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.check_circle, color: Colors.green[700], size: 48),
                const SizedBox(height: 8),
                Text(
                  'All rooms are clean!',
                  style: TextStyle(color: Colors.green[700], fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Rooms Needing Cleaning',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: roomsNeedingCleaning.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final room = roomsNeedingCleaning[index];
              final roomNumber = room['room_number'] ?? 'Unknown';
              final roomType = room['room_type'] ?? 'N/A';
              final status = room['status'] ?? 'unknown';
              final isOccupied = status == 'Occupied';
              
              return ListTile(
                leading: Icon(
                  isOccupied ? Icons.hotel : Icons.meeting_room,
                  color: isOccupied ? Colors.purple[700] : Colors.orange[700],
                ),
                title: Text('Room $roomNumber'),
                subtitle: Text(
                  '$roomType • ${isOccupied ? 'Occupied' : 'Vacant'}',
                  style: const TextStyle(fontSize: 12),
                ),
                trailing: Chip(
                  label: Text(
                    'Needs Cleaning',
                    style: const TextStyle(fontSize: 10),
                  ),
                  backgroundColor: Colors.orange[100],
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAttendanceCard() {
    if (_isLoadingAttendance) return const LinearProgressIndicator();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isClockedIn ? Colors.green[50] : Colors.blue[50],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isClockedIn ? Colors.green[200]! : Colors.blue[200]!,
        ),
      ),
      child: Column(
        children: [
          Text(
            'Attendance',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 8),
          Text(
            _isClockedIn ? 'You are clocked IN' : 'You are clocked OUT',
            style: TextStyle(
              color: _isClockedIn ? Colors.green[700] : Colors.blue[700],
              fontWeight: FontWeight.w500,
            ),
          ),
          if (_lastAttendanceRecord != null && _lastAttendanceRecord!['clock_in_time'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'Clocked in at: ${DateFormat('hh:mm a').format(DateTime.parse(_lastAttendanceRecord!['clock_in_time']))}',
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ],
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isClockedIn ? _handleClockOut : _handleClockIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isClockedIn ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
              minimumSize: const Size(double.infinity, 48),
            ),
            child: Text(_isClockedIn ? 'Clock Out' : 'Clock In'),
          ),
        ],
      ),
    );
  }
}
