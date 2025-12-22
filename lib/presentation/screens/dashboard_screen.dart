import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:pzed_homes/core/services/auth_service.dart';
import 'package:pzed_homes/core/services/data_service.dart';
import 'package:pzed_homes/core/state/app_state.dart';
import 'package:pzed_homes/data/models/user.dart';
import 'package:pzed_homes/core/animations/app_animations.dart';
import 'package:pzed_homes/core/layout/responsive_layout.dart';
import 'package:pzed_homes/core/error/error_handler.dart';
import 'package:pzed_homes/presentation/widgets/summary_card.dart';
import 'package:pzed_homes/presentation/screens/create_booking_screen.dart';
import 'package:pzed_homes/data/models/booking.dart';
import 'package:go_router/go_router.dart';
import 'package:pzed_homes/presentation/screens/user_profile_screen.dart';

enum TimeRange { today, week, month, custom }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _searchController = TextEditingController();
  // final _supabase = Supabase.instance.client; // Disabled for mock-only presentation
  final DataService _dataService = DataService();

  List<Map<String, dynamic>> _bookings = [];
  List<Map<String, dynamic>> _filteredBookings = [];
  Map<String, dynamic> _stats = {};
  Map<String, dynamic>? _lastAttendanceRecord;
  bool _isClockedIn = false;
  bool _isLoading = true;
  bool _isLoadingAttendance = true;
  
  // Time range state
  TimeRange _timeRange = TimeRange.today;
  DateTimeRange? _customRange;

  // Financial/records (mock) for role metrics
  List<Map<String, dynamic>> _incomeRecords = [];
  List<Map<String, dynamic>> _expenseRecords = [];
  List<Map<String, dynamic>> _stockTransactions = [];
  List<Map<String, dynamic>> _payrollRecords = [];
  List<Map<String, dynamic>> _cashDeposits = [];

  // Calendar state
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // View focus state: 'financial' or 'performance'
  String _focus = 'performance';

  // Presentation: checked-in guests and department sales
  List<Map<String, dynamic>> _checkedInGuests = [];
  Map<String, num> _deptSalesTotals = {
    'VIP Bar': 0,
    'Outside Bar': 0,
    'Mini Mart': 0,
    'Kitchen': 0,
  };

  @override
  void initState() {
    super.initState();
    _loadData();
    _searchController.addListener(_filterBookings);
    // Set default focus by role and sync clock-in status
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthService>(context, listen: false);
      // Sync clock-in status with AuthService
      if (mounted) {
        setState(() {
          _isClockedIn = auth.isClockedIn;
        });
      }
      final role = auth.isRoleAssumed ? (auth.assumedRole ?? auth.userRole) : auth.userRole;
      if (role == AppRole.owner || role == AppRole.accountant) {
        setState(() { _focus = 'financial'; });
      } else {
        setState(() { _focus = 'performance'; });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      // Load data using DataService
      final bookings = await _dataService.getBookings();
      final stats = await _dataService.getDashboardStats();
      final attendance = await _fetchLastAttendance();
      final income = await _dataService.getIncomeRecords();
      final expenses = await _dataService.getExpenses();
      final stockTx = await _dataService.getStockTransactions();
      final payroll = await _dataService.getPayrollRecords();
      final deposits = await _dataService.getCashDeposits();
      final checkedInGuests = await _dataService.getCheckedInGuests();
      final vipSales = await _dataService.getDepartmentSales('vip_bar');
      final outsideSales = await _dataService.getDepartmentSales('outside_bar');
      final miniMartSales = await _dataService.getDepartmentSales('mini_mart');
      final kitchenSales = await _dataService.getDepartmentSales('kitchen');

      if (mounted) {
        setState(() {
          _bookings = bookings;
          _filteredBookings = _bookings;
          _stats = stats;
          _lastAttendanceRecord = attendance;
          _isClockedIn = attendance != null && attendance['clock_out_time'] == null;
          _isLoading = false;
          _isLoadingAttendance = false;
          _incomeRecords = income;
          _expenseRecords = expenses;
          _stockTransactions = stockTx;
          _payrollRecords = payroll;
          _cashDeposits = deposits;
          _checkedInGuests = checkedInGuests;
          num sum(List<Map<String, dynamic>> list) => list.fold<num>(0, (s, e) => s + (e['total_amount'] as num));
          _deptSalesTotals = {
            'VIP Bar': sum(vipSales),
            'Outside Bar': sum(outsideSales),
            'Mini Mart': sum(miniMartSales),
            'Kitchen': sum(kitchenSales),
          };
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingAttendance = false;
        });
      }
      ErrorHandler.handleError(context, e);
    }
  }

  Future<Map<String, dynamic>> _calculateDashboardStats() async {
    // Calculate stats from actual bookings
      return {
      'checked_in_count': _bookings.where((b) => (b['status']?.toString() ?? '') == 'Checked-in').length,
      'pending_count': _bookings.where((b) => (b['status']?.toString() ?? '') == 'Pending Check-in').length,
      'occupancy_rate': (_stats['occupancy_rate'] ?? 65),
      'total_revenue': _stats['total_revenue'] ?? 0,
    };
  }

  Future<Map<String, dynamic>?> _fetchLastAttendance() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      if (authService.currentUser == null) return null;
      
      // Get current attendance from database
      final attendance = await _dataService.getCurrentAttendance(authService.currentUser!.id);
      
      // Update local state to match AuthService
      if (mounted) {
        setState(() {
          _isClockedIn = authService.isClockedIn;
        });
      }
      
      return attendance;
    } catch (e) {
      // If error, check AuthService state
      final authService = Provider.of<AuthService>(context, listen: false);
      if (mounted) {
        setState(() {
          _isClockedIn = authService.isClockedIn;
        });
      }
      return null;
    }
  }

  void _filterBookings() {
    final query = _searchController.text.toLowerCase();
    if (mounted) {
      setState(() {
        _filteredBookings = _bookings.where((booking) {
          final guestName = (booking['profiles'] as Map<String, dynamic>?)?
              ['full_name']?.toString().toLowerCase() ?? '';
          final roomNumber = (booking['rooms'] as Map<String, dynamic>?)?
              ['room_number']?.toString().toLowerCase() ?? '';
          return guestName.contains(query) || roomNumber.contains(query);
        }).toList();
      });
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth > 1200) {
                  return _buildDesktopLayout(context);
                } else if (constraints.maxWidth > 800) {
                  return _buildTabletLayout(context);
                } else {
                  return _buildMobileLayout(context);
                }
              },
            ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: AppAnimations.staggeredList(
        children: [
          AppAnimations.slideInFromBottom(
            child: _buildHeader(context),
          ),
          const SizedBox(height: 12),
          _buildQuickNav(context),
          const SizedBox(height: 12),
          _buildTimeRangeToolbar(context),
          const SizedBox(height: 24),
          AppAnimations.staggeredGrid(
            children: _buildMetricCardsList(context),
            crossAxisCount: 4,
          ),
          const SizedBox(height: 24),
          _buildDepartmentSalesQuickCards(context),
          const SizedBox(height: 24),
          _buildCheckedInGuestsCard(context),
          const SizedBox(height: 24),
          _buildRoleSpecificSection(context),
            const SizedBox(height: 24),
          // Calendar launcher
          AppAnimations.fadeTransition(
            child: _buildCalendarLauncher(context),
            animation: const AlwaysStoppedAnimation(1.0),
          ),
          const SizedBox(height: 24),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: AppAnimations.scaleTransition(
                  child: _buildOccupancyChart(context),
                  animation: AlwaysStoppedAnimation(1.0),
                ),
              ),
              const SizedBox(width: 24),
              Expanded(
                flex: 1,
                child: AppAnimations.slideTransition(
                  child: _buildRecentActivities(context),
                  animation: AlwaysStoppedAnimation(1.0),
                  direction: SlideDirection.right,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          AppAnimations.fadeTransition(
            child: _buildBookingsTable(context),
            animation: AlwaysStoppedAnimation(1.0),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 12),
          _buildQuickNav(context),
          const SizedBox(height: 16),
          _buildTimeRangeToolbar(context),
          const SizedBox(height: 16),
          _buildMetricCards(context),
          const SizedBox(height: 16),
          _buildDepartmentSalesQuickCards(context),
          const SizedBox(height: 16),
          _buildCheckedInGuestsCard(context),
          const SizedBox(height: 16),
          _buildRoleSpecificSection(context),
            const SizedBox(height: 16),
          _buildCalendarLauncher(context),
          const SizedBox(height: 16),
          _buildOccupancyChart(context),
          const SizedBox(height: 16),
          _buildRecentActivities(context),
          const SizedBox(height: 16),
          _buildBookingsTable(context),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context),
          const SizedBox(height: 12),
          _buildQuickNav(context),
          const SizedBox(height: 16),
          _buildTimeRangeToolbar(context),
          const SizedBox(height: 16),
          _buildMetricCards(context),
          const SizedBox(height: 16),
          _buildDepartmentSalesQuickCards(context),
          const SizedBox(height: 16),
          _buildCheckedInGuestsCard(context),
          const SizedBox(height: 16),
          _buildRoleSpecificSection(context),
            const SizedBox(height: 16),
          _buildCalendarLauncher(context),
          const SizedBox(height: 16),
          _buildOccupancyChart(context),
          const SizedBox(height: 16),
          _buildRecentActivities(context),
          const SizedBox(height: 16),
          _buildBookingsTable(context),
        ],
      ),
    );
  }

  Widget _buildCalendarLauncher(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Booking Calendar',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  ),
            ),
          ),
          ElevatedButton.icon(
            onPressed: _showCalendarDialog,
            icon: const Icon(Icons.calendar_today),
            label: const Text('View Calendar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[800],
              foregroundColor: Colors.white,
            ),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: _showFrontDeskCalendarDialog,
            icon: const Icon(Icons.view_timeline),
            label: const Text('Booking Calendar'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green[800],
              foregroundColor: Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  void _showCalendarDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(16),
      child: Container(
            padding: const EdgeInsets.all(16),
            constraints: const BoxConstraints(maxWidth: 900),
      child: Column(
              mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
                    const Icon(Icons.calendar_today, size: 18),
                    const SizedBox(width: 8),
          Text(
                      'Booking Calendar',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
                          ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
                const SizedBox(height: 8),
                TableCalendar(
                  firstDay: DateTime.utc(2020, 1, 1),
                  lastDay: DateTime.utc(2035, 12, 31),
                  focusedDay: _focusedDay,
                  calendarFormat: _calendarFormat,
                  selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
                  onDaySelected: (selectedDay, focusedDay) {
                  setState(() {
                      _selectedDay = selectedDay;
                      _focusedDay = focusedDay;
                    });
                  },
                  onFormatChanged: (format) {
                    setState(() => _calendarFormat = format);
                  },
                  onPageChanged: (focusedDay) {
                    _focusedDay = focusedDay;
                  },
                  eventLoader: _getEventsForDay,
                  headerStyle: const HeaderStyle(
                    formatButtonVisible: true,
                    titleCentered: true,
                  ),
                  calendarStyle: CalendarStyle(
                    todayDecoration: BoxDecoration(
                      color: Colors.green[700],
                      borderRadius: BorderRadius.circular(8),
                    ),
                    selectedDecoration: BoxDecoration(
                      color: Colors.green[700],
              borderRadius: BorderRadius.circular(8),
            ),
                    todayTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    selectedTextStyle: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    outsideDaysVisible: false,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showFrontDeskCalendarDialog() async {
    final DateTime start = DateTime.now();
    final List<DateTime> days = List.generate(7, (i) => DateTime(start.year, start.month, start.day + i));

    // Collect unique rooms from bookings
    final Set<String> roomSet = {
      ..._bookings.map((b) => ((b['rooms'] as Map<String, dynamic>?)?['room_number']?.toString() ?? 'Room ?'))
    }..removeWhere((e) => e.isEmpty);
    
    // If no rooms from bookings, load all rooms from database
    List<String> rooms = [];
    if (roomSet.isNotEmpty) {
      rooms = roomSet.toList()..sort();
    } else {
      // Load all rooms from database
      try {
        final allRooms = await _dataService.getRooms();
        final roomNumbers = allRooms
            .map((r) => r['room_number']?.toString() ?? '')
            .where((rn) => rn.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        rooms = roomNumbers;
      } catch (e) {
        // If database query fails, show empty state
        rooms = [];
      }
    }

    Color statusColor(String status) {
      switch (status.toLowerCase()) {
        case 'booked':
          return const Color(0xFF3B82F6);
        case 'checked_in':
        case 'checked-in':
          return const Color(0xFF22C55E);
        case 'checked_out':
        case 'checked-out':
          return const Color(0xFFF59E0B);
        case 'cancelled':
          return const Color(0xFFEF4444);
        case 'pending':
          return const Color(0xFFA855F7);
      default:
          return Colors.grey;
      }
    }

    String fmt(DateTime d) => DateFormat('EEE, MMM d').format(d);

    showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: const EdgeInsets.all(12),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 1200, maxHeight: 700),
      decoration: BoxDecoration(
        color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12)],
      ),
      child: Column(
        children: [
                // Top bar
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 6, offset: const Offset(0, 2))],
                  ),
                  child: Row(
                    children: [
                      const Text('Front Desk Calendar View', style: TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      // Date range label
                      Text('From: ${fmt(days.first)}', style: const TextStyle(color: Colors.black54)),
                      const SizedBox(width: 12),
                      // Filter dropdown placeholder
                      DropdownButton<String>(
                        value: 'All Reservations',
                        underline: const SizedBox(),
                        items: const [
                          DropdownMenuItem(value: 'All Reservations', child: Text('All Reservations')),
                          DropdownMenuItem(value: 'Checked-in', child: Text('Checked-in')),
                          DropdownMenuItem(value: 'Due in', child: Text('Due in')),
                          DropdownMenuItem(value: 'Due out', child: Text('Due out')),
                        ],
                        onChanged: (_) {},
                      ),
                      const SizedBox(width: 12),
                      // Search box placeholder
          SizedBox(
                        width: 220,
                        child: TextField(
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search reservations...',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      )
                    ],
                  ),
                ),

                Expanded(
                    child: Row(
                      children: [
                      // Sidebar (rooms)
                        Container(
                        width: 220,
                        color: Colors.green[800],
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              child: const Text('Rooms', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                            ),
                            const Divider(color: Colors.white24, height: 1),
                            Expanded(
                              child: rooms.isEmpty
                                  ? const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(24.0),
                                        child: Text(
                                          'No rooms available',
                                          style: TextStyle(color: Colors.white70),
                                        ),
                                      ),
                                    )
                                  : ListView.builder(
                                      itemCount: rooms.length,
                                      itemBuilder: (context, i) => Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        decoration: BoxDecoration(
                                          border: Border(bottom: BorderSide(color: Colors.white24.withOpacity(0.2))),
                                        ),
                                        child: Text(rooms[i], style: const TextStyle(color: Colors.white)),
                                      ),
                                    ),
                            ),
                      ],
                    ),
                  ),

                      // Timeline grid
                      Expanded(
      child: Column(
        children: [
                            // Sticky header for dates
                            Container(
                              color: Colors.white,
            child: Row(
              children: [
                                  for (final d in days)
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          border: Border(bottom: BorderSide(color: Colors.grey[300]!)),
                                        ),
                                        child: Center(
                                          child: Text(DateFormat('EEE\nMMM d').format(d), textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),

                            Expanded(
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    for (final room in rooms)
                                      _buildFrontDeskCalendarRow(context, room, days, _bookings, statusColor),
              ],
            ),
          ),
                    ),
                  ],
                ),
              ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
  List<dynamic> _getEventsForDay(DateTime day) {
    // Basic marker: mark days that have any booking check-in or check-out
    final hasBooking = _bookings.any((b) {
      try {
        final ci = b['check_in_date'] != null ? DateTime.parse(b['check_in_date']) : null;
        final co = b['check_out_date'] != null ? DateTime.parse(b['check_out_date']) : null;
        return (ci != null && isSameDay(ci, day)) || (co != null && isSameDay(co, day));
      } catch (_) {
        return false;
      }
    });
    return hasBooking ? ['booking'] : const [];
  }


 

  Widget _buildHeader(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final role = auth.isRoleAssumed ? (auth.assumedRole ?? auth.userRole) : auth.userRole;
    final isManagement = role == AppRole.owner || role == AppRole.manager || role == AppRole.accountant || role == AppRole.hr || role == AppRole.supervisor;

    return Row(
        children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                'Dashboard',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800], // Green for headers on light background
                ),
              ),
              const SizedBox(height: 8),
                          Text(
                'Welcome back! Here\'s what\'s happening at P-ZED Luxury Hotels & Suites.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Colors.grey[700], // Darker grey for better readability
                            ),
                          ),
                        ],
                      ),
                    ),
        if (isManagement) _buildFocusToggle(),
        if (!isManagement) ...[
          const SizedBox(width: 12),
          _buildAttendanceCard(),
        ],
      ],
    );
  }

  Widget _buildFocusToggle() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0,2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ChoiceChip(
            label: const Text('Performance'),
            selected: _focus == 'performance',
            onSelected: (v) { if (v) setState(() { _focus = 'performance'; }); },
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('Financial'),
            selected: _focus == 'financial',
            onSelected: (v) { if (v) setState(() { _focus = 'financial'; }); },
          ),
        ],
      ),
    );
  }

  List<Widget> _buildMetricCardsList(BuildContext context) {
    return [
      _buildMetricCard(
          context,
          'New Bookings',
          '${_stats['pending_count'] ?? 0}',
          Icons.book_online,
          Colors.green[700]!, // Green for better readability
        ),
        _buildMetricCard(
          context,
          'Checked In',
          '${_stats['checked_in_count'] ?? 0}',
          Icons.login,
          Colors.green[700]!, // Green for better readability
        ),
        _buildMetricCard(
          context,
          'Occupancy Rate',
          '${_stats['occupancy_rate'] ?? 0}%',
          Icons.hotel,
          Colors.green[700]!, // Green for better readability
        ),
        _buildMetricCard(
          context,
          'Total Revenue',
          '₦${_stats['total_revenue'] ?? 0}',
          Icons.attach_money,
          Colors.green[700]!, // Green for better readability
        ),
        _buildMetricCard(
          context,
          'Guests Checked-in',
          '${_checkedInGuests.length}',
          Icons.people,
          Colors.green[700]!,
        ),
    ];
  }

  Widget _buildDepartmentSalesQuickCards(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _deptSalesTotals.entries.map((e) {
        return AppAnimations.animatedCard(
          child: Container(
            width: 220,
            padding: const EdgeInsets.all(16),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green[700]!.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.point_of_sale, color: Colors.green[700], size: 18),
                    ),
                    const Spacer(),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  '₦${e.value}',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF0A0A0A),
                      ),
                ),
                const SizedBox(height: 4),
                Text(
                  e.key,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF666666),
                      ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildCheckedInGuestsCard(BuildContext context) {
    if (_checkedInGuests.isEmpty) return const SizedBox.shrink();

    return AppAnimations.animatedCard(
      child: Container(
        padding: const EdgeInsets.all(16),
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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.people, color: Colors.green[700]),
                const SizedBox(width: 8),
                Text(
                  'Checked-in Guests',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Colors.green[800],
                      ),
                ),
                const Spacer(),
                Chip(
                  label: Text('${_checkedInGuests.length}'),
                  backgroundColor: Colors.green[700]!.withOpacity(0.15),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ..._checkedInGuests.take(6).map((g) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(g['guest_name'] ?? 'Guest'),
                    ),
                    Text('Room ${g['room_id'] ?? ''}', style: const TextStyle(color: Colors.black54)),
                    const SizedBox(width: 12),
                    Text('by ${g['processed_by'] ?? 'Staff'}', style: const TextStyle(color: Colors.black45)),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCards(BuildContext context) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: _buildMetricCardsList(context),
    );
  }

  Widget _buildMetricCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return AppAnimations.animatedCard(
      child: Container(
        width: 200,
        padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const Spacer(),
              Icon(Icons.trending_up, color: Colors.green[700], size: 16),
            ],
                    ),
                    const SizedBox(height: 16),
                    Text(
            value,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: const Color(0xFF0A0A0A),
            ),
          ),
          const SizedBox(height: 4),
                      Text(
            title,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: const Color(0xFF666666),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildOccupancyChart(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Occupancy by Rooms',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 300,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: 100,
                barTouchData: BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  show: true,
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          'Room ${value.toInt()}',
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          '${value.toInt()}%',
                          style: const TextStyle(fontSize: 10),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                barGroups: _generateBarGroups(),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: 20,
                  getDrawingHorizontalLine: (value) {
                    return FlLine(
                      color: Colors.grey[200]!,
                      strokeWidth: 1,
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<BarChartGroupData> _generateBarGroups() {
    // Use real occupancy data from bookings
    // Count occupied rooms by type
    final roomTypeCounts = <String, int>{};
    int totalOccupied = 0;
    
    for (var booking in _bookings) {
      if (booking['status'] == 'Checked-in' && booking['room_id'] != null) {
        totalOccupied++;
        final roomType = booking['rooms']?['type'] as String? ?? 
                        booking['requested_room_type'] as String? ?? 
                        'Unknown';
        roomTypeCounts[roomType] = (roomTypeCounts[roomType] ?? 0) + 1;
      }
    }
    
    // If no occupied rooms, return empty chart
    if (roomTypeCounts.isEmpty || totalOccupied == 0) {
      return List.generate(5, (index) {
        return BarChartGroupData(
          x: index + 1,
          barRods: [
            BarChartRodData(
              toY: 0,
              color: Colors.grey[300]!,
              width: 20,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        );
      });
    }
    
    // Convert to chart data (limit to 5 room types, sorted by count)
    final sortedTypes = roomTypeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    final chartData = sortedTypes.take(5).toList();
    
    return chartData.asMap().entries.map((entry) {
      final index = entry.key;
      final typeEntry = entry.value;
      final count = typeEntry.value;
      final percentage = (count / totalOccupied * 100).clamp(0.0, 100.0);
      
      return BarChartGroupData(
        x: index + 1,
        barRods: [
          BarChartRodData(
            toY: percentage,
            color: Colors.green[400],
            width: 20,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(4),
              topRight: Radius.circular(4),
            ),
          ),
        ],
      );
    }).toList();
  }
  
  // Helper to get room type names for chart labels
  List<String> _getRoomTypesForChart() {
    final roomTypeCounts = <String, int>{};
    
    for (var booking in _bookings) {
      if (booking['status'] == 'Checked-in' && booking['room_id'] != null) {
        final roomType = booking['rooms']?['type'] as String? ?? 
                        booking['requested_room_type'] as String? ?? 
                        'Unknown';
        roomTypeCounts[roomType] = (roomTypeCounts[roomType] ?? 0) + 1;
      }
    }
    
    final sortedTypes = roomTypeCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    
    return sortedTypes.take(5).map((e) => e.key).toList();
  }
  
  // Helper to format time ago
  String _getTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);
    
    if (difference.inDays > 0) {
      return '${difference.inDays} day${difference.inDays > 1 ? 's' : ''} ago';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} hour${difference.inHours > 1 ? 's' : ''} ago';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} minute${difference.inMinutes > 1 ? 's' : ''} ago';
    } else {
      return 'Just now';
    }
  }

  Widget _buildRecentActivities(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Recent Activities',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
              color: Colors.green[800], // Green for headers on white background
            ),
          ),
          const SizedBox(height: 16),
          if (_checkedInGuests.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No recent activities'),
            )
          else
            ..._checkedInGuests.take(5).toList().asMap().entries.map((entry) {
              final index = entry.key;
              final guest = entry.value;
              
              // Extract room number
              final roomNumber = guest['rooms']?['room_number'] as String? ?? 
                                guest['room_number'] as String? ?? 
                                'N/A';
              
              // Extract guest name - handle both nested and flat structures
              String guestName = 'Guest';
              if (guest['profiles'] != null) {
                if (guest['profiles'] is Map) {
                  guestName = guest['profiles']['full_name'] as String? ?? 
                             guest['profiles']['guest_profile_id']?['full_name'] as String? ??
                             'Guest';
                }
              } else {
                guestName = guest['guest_name'] as String? ?? 'Guest';
              }
              
              // Extract check-in time
              final checkInTime = guest['check_in_date'] as String?;
              final timeAgo = checkInTime != null 
                  ? _getTimeAgo(DateTime.parse(checkInTime))
                  : 'Recently';
              
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: Colors.green[400],
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$guestName checked in Room $roomNumber',
                            style: const TextStyle(
                              fontWeight: FontWeight.w500,
                              fontSize: 14,
                            ),
                          ),
                          Text(
                            timeAgo,
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildBookingsTable(BuildContext context) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Text(
                  'Recent Bookings',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: Colors.green[800], // Green for headers on white background
                  ),
                ),
                const Spacer(),
                SizedBox(
                  width: 300,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search by guest name or room...',
                      prefixIcon: const Icon(Icons.search),
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_filteredBookings.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              child: Center(
                child: Column(
                  children: [
                    Image.asset(
                      'assets/images/PZED logo.png',
                      height: 64,
                      width: 64,
                      fit: BoxFit.contain,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'No bookings found',
                      style: TextStyle(fontSize: 18, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            )
          else
            DataTable(
              columns: const [
                DataColumn(label: Text('Guest Name')),
                DataColumn(label: Text('Room')),
                DataColumn(label: Text('Status')),
                DataColumn(label: Text('Check-in')),
                DataColumn(label: Text('Check-out')),
                DataColumn(label: Text('Actions')),
              ],
              rows: _filteredBookings.take(10).map((booking) {
                final guestName = (booking['profiles'] as Map<String, dynamic>?)?['full_name'] ?? 'Unknown';
                final room = booking['rooms'] as Map<String, dynamic>?;
                final roomNumber = room?['room_number']?.toString() ?? 
                                  booking['requested_room_type']?.toString() ?? 
                                  'Not Assigned';
                final status = booking['status'] as String? ?? 'Unknown';
                final checkIn = booking['check_in_date'] != null 
                    ? DateFormat('MMM dd, yyyy').format(DateTime.parse(booking['check_in_date']))
                    : 'N/A';
                final checkOut = booking['check_out_date'] != null 
                    ? DateFormat('MMM dd, yyyy').format(DateTime.parse(booking['check_out_date']))
                    : 'N/A';

                return DataRow(
                  cells: [
                    DataCell(Text(guestName)),
                    DataCell(Text(roomNumber)),
                    DataCell(
                      Chip(
                        label: Text(status),
                        backgroundColor: _getStatusColor(status).withOpacity(0.1),
                        labelStyle: TextStyle(color: _getStatusColor(status)),
                      ),
                    ),
                    DataCell(Text(checkIn)),
                    DataCell(Text(checkOut)),
                    DataCell(
                      IconButton(
                        icon: const Icon(Icons.visibility),
                        onPressed: () {
                          // Convert booking map to Booking object and navigate
                          try {
                            final bookingObj = Booking.fromMap(booking);
                            context.push('/booking/details', extra: bookingObj);
                          } catch (e) {
                            if (mounted) {
                              ErrorHandler.handleError(
                                context,
                                e,
                                customMessage: 'Failed to open booking. Please try again.',
                              );
                            }
                          }
                        },
                      ),
                    ),
                  ],
                );
              }).toList(),
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
          const SizedBox(height: 12),
          ElevatedButton(
            onPressed: _isClockedIn ? _handleClockOut : _handleClockIn,
            style: ElevatedButton.styleFrom(
              backgroundColor: _isClockedIn ? Colors.red : Colors.green,
              foregroundColor: Colors.white,
            ),
            child: Text(_isClockedIn ? 'Clock Out' : 'Clock In'),
          ),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status.toLowerCase()) {
      case 'checked-in':
        return Colors.green;
      case 'pending check-in':
        return Colors.orange;
      case 'checked-out':
        return Colors.blue;
      default:
        return Colors.grey;
  }
}

  // Toolbar to select time range filters
  Widget _buildTimeRangeToolbar(BuildContext context) {
    String labelFor(TimeRange r) {
      switch (r) {
        case TimeRange.today:
          return 'Today';
        case TimeRange.week:
          return 'This Week';
        case TimeRange.month:
          return 'This Month';
        case TimeRange.custom:
          return 'Custom';
      }
    }

    return Row(
      children: [
        Wrap(
          spacing: 8,
          children: TimeRange.values.map((r) {
            final selected = _timeRange == r;
            return ChoiceChip(
              label: Text(labelFor(r)),
              selected: selected,
              onSelected: (_) async {
                if (r == TimeRange.custom) {
                  final now = DateTime.now();
                  final picked = await showDateRangePicker(
                    context: context,
                    firstDate: DateTime(now.year - 2),
                    lastDate: DateTime(now.year + 2),
                  );
                  if (picked != null) {
                    setState(() {
                      _timeRange = r;
                      _customRange = picked;
                    });
                  }
                } else {
                  setState(() {
                    _timeRange = r;
                    _customRange = null;
                  });
                }
              },
              selectedColor: Colors.green[700],
            );
          }).toList(),
        ),
      ],
    );
  }

  // Role-specific metrics section
  Widget _buildRoleSpecificSection(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final effectiveRole = auth.isRoleAssumed ? auth.assumedRole ?? auth.userRole : auth.userRole;

    switch (effectiveRole) {
      case AppRole.owner:
        return _focus == 'financial' ? _buildManagementAggregate(context) : _buildPerformanceAggregate(context);
      case AppRole.accountant:
        return _buildManagementAggregate(context);
      case AppRole.manager:
        return _focus == 'financial' ? _buildManagementAggregate(context) : _buildPerformanceAggregate(context);
      case AppRole.receptionist:
        return _buildReceptionistPanel(context);
      case AppRole.bartender:
        return _buildBartenderPanel(context);
      case AppRole.kitchen_staff:
        return _buildKitchenPanel(context);
      case AppRole.storekeeper:
        return _buildStorekeeperPanel(context);
      case AppRole.purchaser:
        return _buildPurchaserPanel(context);
      case AppRole.security:
      case AppRole.laundry_attendant:
      case AppRole.cleaner:
      case AppRole.housekeeper:
      case AppRole.guest:
      default:
        return const SizedBox.shrink();
    }
  }

  // Performance-focused aggregate for management (non-financial emphasis)
  Widget _buildPerformanceAggregate(BuildContext context) {
    return _buildReceptionistPanel(context); // reuse a performance-like panel as placeholder
  }

  // Quick navigation for department and key areas
  Widget _buildQuickNav(BuildContext context) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final role = auth.isRoleAssumed ? (auth.assumedRole ?? auth.userRole) : auth.userRole;
    final isManagement = role == AppRole.owner || role == AppRole.manager || role == AppRole.accountant || role == AppRole.hr || role == AppRole.supervisor;

    if (!isManagement) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _quickButton(context, 'My Department', Icons.domain, () {
            if (role == AppRole.storekeeper) context.go('/storekeeping');
            else if (role == AppRole.purchaser) context.go('/purchasing');
            else if (role == AppRole.kitchen_staff || role == AppRole.bartender) context.go('/kitchen');
            else if (role == AppRole.housekeeper || role == AppRole.cleaner || role == AppRole.laundry_attendant) context.go('/housekeeping');
            else context.go('/dashboard');
          }),
          _quickButton(context, 'My Profile', Icons.person, () { context.push('/profile'); }),
        ],
      );
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (role == AppRole.owner || role == AppRole.manager || role == AppRole.hr)
          _quickButton(context, 'HR', Icons.people_alt, () { context.go('/hr'); }),
        _quickButton(context, 'Finance', Icons.account_balance, () { context.go('/finance'); }),
        _quickButton(context, 'Reporting', Icons.insights, () { context.go('/reporting'); }),
      ],
    );
  }

  Widget _quickButton(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0,2)),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.green[700]),
            const SizedBox(width: 8),
            Text(label, style: TextStyle(color: Colors.grey[800])),
          ],
        ),
      ),
    );
  }

  DateTimeRange _currentRange() {
    final now = DateTime.now();
    switch (_timeRange) {
      case TimeRange.today:
        return DateTimeRange(start: DateTime(now.year, now.month, now.day), end: now);
      case TimeRange.week:
        final start = now.subtract(Duration(days: now.weekday - 1));
        return DateTimeRange(start: DateTime(start.year, start.month, start.day), end: now);
      case TimeRange.month:
        return DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
      case TimeRange.custom:
        return _customRange ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
    }
  }

  bool _isInRange(DateTime date) {
    final r = _currentRange();
    return !date.isBefore(r.start) && !date.isAfter(r.end);
  }

  // Aggregate for owner/manager
  Widget _buildManagementAggregate(BuildContext context) {
    final inRangeIncome = _incomeRecords.where((e) {
      final d = DateTime.tryParse(e['date']?.toString() ?? '');
      return d != null && _isInRange(d);
    }).toList();
    final inRangeExpenses = _expenseRecords.where((e) {
      final d = DateTime.tryParse(e['date']?.toString() ?? '');
      return d != null && _isInRange(d);
    }).toList();

    num sumAmount(List<Map<String, dynamic>> list) => list.fold<num>(0, (s, e) => s + (e['amount'] as num));

    final income = sumAmount(inRangeIncome);
    final expenses = sumAmount(inRangeExpenses);
    final profit = income - expenses;

    return _inlineCards(context, [
      ('Income', '₦$income', Icons.trending_up),
      ('Expenses', '₦$expenses', Icons.trending_down),
      ('Net Profit', '₦$profit', Icons.account_balance),
    ]);
  }

  // Accountant extra insights
  Widget _buildAccountantInsights(BuildContext context) {
    final r = _currentRange();
    int countInRange(List<Map<String, dynamic>> list, String dateKey) {
      return list.where((e) {
        final d = DateTime.tryParse(e[dateKey]?.toString() ?? '');
        return d != null && _isInRange(d);
      }).length;
    }

    final depositsInRange = countInRange(_cashDeposits, 'date');
    final payrollInRange = _payrollRecords.where((p) {
      final month = p['month']?.toString() ?? '';
      return month.startsWith('${r.start.year}-${r.start.month.toString().padLeft(2, '0')}');
    }).length;

    return _inlineCards(context, [
      ('Cash Deposits', '$depositsInRange', Icons.savings),
      ('Payroll Runs', '$payrollInRange', Icons.payments),
    ]);
  }

  // Receptionist personal metrics
  Widget _buildReceptionistPanel(BuildContext context) {
    // Using bookings as proxy for processed rooms in range
    final processed = _bookings.where((b) {
      final ci = DateTime.tryParse(b['check_in']?.toString() ?? '');
      return ci != null && _isInRange(ci);
    }).length;
    return _inlineCards(context, [
      ('Rooms Processed', '$processed', Icons.meeting_room),
    ]);
  }

  // Bartender metrics (sales from stock transactions)
  Widget _buildBartenderPanel(BuildContext context) {
    final sales = _stockTransactions.where((t) {
      final ts = DateTime.tryParse((t['timestamp']?.toString() ?? '').replaceFirst(' ', 'T'));
      return (t['type'] == 'sale') && ts != null && _isInRange(ts);
    }).toList();
    final qty = sales.fold<int>(0, (s, e) => s + ((e['quantity'] as int).abs()));
    final value = sales.fold<num>(0, (s, e) => s + (e['total_amount'] as num));
    return _inlineCards(context, [
      ('Items Sold', '$qty', Icons.local_bar),
      ('Sales Value', '₦$value', Icons.point_of_sale),
    ]);
  }

  // Kitchen metrics
  Widget _buildKitchenPanel(BuildContext context) {
    // Proxy using income records from vip/outside bar as dispatched
    final inRange = _incomeRecords.where((e) {
      final d = DateTime.tryParse(e['date']?.toString() ?? '');
      final dept = e['department']?.toString() ?? '';
      final isBar = dept == 'vip_bar' || dept == 'outside_bar';
      return d != null && _isInRange(d) && isBar;
    }).toList();
    final total = inRange.fold<num>(0, (s, e) => s + (e['amount'] as num));
    return _inlineCards(context, [
      ('Food Dispatched', '${inRange.length}', Icons.restaurant),
      ('Value', '₦$total', Icons.attach_money),
    ]);
  }

  // Storekeeper metrics
  Widget _buildStorekeeperPanel(BuildContext context) {
    final movements = _stockTransactions.where((t) {
      final ts = DateTime.tryParse((t['timestamp']?.toString() ?? '').replaceFirst(' ', 'T'));
      return ts != null && _isInRange(ts);
    }).length;
    return _inlineCards(context, [
      ('Stock Movements', '$movements', Icons.inventory_2),
    ]);
  }

  // Purchaser metrics
  Widget _buildPurchaserPanel(BuildContext context) {
    final kitchenExpenses = _expenseRecords.where((e) {
      final d = DateTime.tryParse(e['date']?.toString() ?? '');
      return d != null && _isInRange(d) && (e['department'] == 'kitchen');
    }).toList();
    final total = kitchenExpenses.fold<num>(0, (s, e) => s + (e['amount'] as num));
    return _inlineCards(context, [
      ('Kitchen Purchases', '₦$total', Icons.shopping_cart),
    ]);
  }

  Widget _inlineCards(BuildContext context, List<(String, String, IconData)> items) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: items.map((it) {
        final (title, value, icon) = it;
        return Container(
          width: 220,
          padding: const EdgeInsets.all(16),
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.green[700]!.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(icon, color: Colors.green[700], size: 18),
                  ),
                  const Spacer(),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                value,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF0A0A0A)),
              ),
              const SizedBox(height: 4),
              Text(title, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF666666))),
            ],
          ),
        );
      }).toList(),
    );
  }

  // Inline builder for front desk calendar row to avoid nested class issues
  Widget _buildFrontDeskCalendarRow(
    BuildContext context,
    String roomName,
    List<DateTime> days,
    List<Map<String, dynamic>> bookings,
    Color Function(String status) statusColor,
  ) {
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          for (final d in days)
            Expanded(
              child: Container(
                height: 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  border: Border(
                    right: BorderSide(color: Colors.grey[300]!),
                    bottom: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: _buildReservationBlock(context, roomName, bookings, statusColor, d),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildReservationBlock(
    BuildContext context,
    String roomName,
    List<Map<String, dynamic>> bookings,
    Color Function(String status) statusColor,
    DateTime day,
  ) {
    final booking = bookings.firstWhere(
      (b) {
        final room = (b['rooms'] as Map<String, dynamic>?)?['room_number']?.toString() ?? '';
        if (room != roomName) return false;
        try {
          final ci = b['check_in_date'] != null ? DateTime.parse(b['check_in_date']) : null;
          final co = b['check_out_date'] != null ? DateTime.parse(b['check_out_date']) : null;
          if (ci == null || co == null) return false;
          final sameOrAfterCI = !day.isBefore(DateTime(ci.year, ci.month, ci.day));
          final beforeCO = day.isBefore(DateTime(co.year, co.month, co.day));
          return sameOrAfterCI && beforeCO;
        } catch (_) {
          return false;
        }
      },
      orElse: () => {},
    );

    if (booking.isEmpty) return const SizedBox.shrink();

    final status = (booking['status']?.toString().toLowerCase() ?? 'booked');
    final guestName = (booking['profiles'] as Map<String, dynamic>?)?['full_name']?.toString() ?? 'GUEST';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 8),
      child: Tooltip(
        message:
            'Guest: $guestName\nRoom: $roomName\nStatus: $status\nCheck-in: ${booking['check_in_date'] ?? ''}\nCheck-out: ${booking['check_out_date'] ?? ''}',
        child: GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Booking Details'),
                content: Text('Guest: $guestName\nRoom: $roomName\nStatus: $status'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
                ],
              ),
            );
          },
          child: Container(
            height: 40,
            decoration: BoxDecoration(
              color: statusColor(status),
              borderRadius: BorderRadius.circular(8),
            ),
            alignment: Alignment.center,
            child: Text(
              guestName,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12),
            ),
          ),
        ),
      ),
    );
  }
}