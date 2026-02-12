import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pzed_homes/core/utils/debug_logger.dart';
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
import 'package:pzed_homes/core/services/payment_service.dart';

enum TimeRange { today, week, month, custom }

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final _searchController = TextEditingController();
  final _activitiesSearchController = TextEditingController();
  SupabaseClient? get _supabase {
    try {
      return Supabase.instance.client;
    } catch (_) {
      return null;
    }
  }
  final DataService _dataService = DataService();
  RealtimeChannel? _realtimeChannel;
  Timer? _realtimeDebounceTimer;
  final Set<String> _pendingRealtimeSlices = {};
  static const _realtimeDebounceMs = 500;

  List<Map<String, dynamic>> _bookings = [];
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
  List<Map<String, dynamic>> _stockLevels = [];
  List<Map<String, dynamic>> _payrollRecords = [];
  List<Map<String, dynamic>> _cashDeposits = [];
  List<Map<String, dynamic>> _purchaseOrders = [];
  List<Map<String, dynamic>> _maintenanceOrders = [];

  // Calendar state
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;
  CalendarFormat _calendarFormat = CalendarFormat.month;

  // View focus state: 'financial' or 'performance'
  String _focus = 'performance';

  // Presentation: checked-in guests and department sales
  List<Map<String, dynamic>> _checkedInGuests = [];
  List<Map<String, dynamic>> _pendingDirectSupplies = [];
  Map<String, num> _deptSalesTotals = {
    'VIP Bar': 0,
    'Outside Bar': 0,
    'Mini Mart': 0,
    'Kitchen': 0,
    'Reception': 0,
  };
  
  // Previous period data for trend calculation
  Map<String, num> _previousDeptSalesTotals = {
    'VIP Bar': 0,
    'Outside Bar': 0,
    'Mini Mart': 0,
    'Kitchen': 0,
    'Reception': 0,
  };
  num _previousIncome = 0;
  num _previousExpenses = 0;
  num _previousProfit = 0;
  int _previousCheckedInCount = 0;
  
  // Pagination state
  int _activitiesDisplayCount = 5;
  final ScrollController _activitiesScrollController = ScrollController();

  // Memoized activities: recompute only when source data or search changes
  List<Map<String, dynamic>>? _cachedFilteredActivities;
  String _activitiesSearchQuery = '';
  Timer? _activitiesSearchDebounce;
  static const _activitiesSearchDebounceMs = 300;

  // Cached chart data: recompute only when _bookings changes
  List<BarChartGroupData>? _cachedBarGroups;
  List<String>? _cachedChartRoomTypes;

  void _onActivitiesScroll() {
    if (!_activitiesScrollController.hasClients) return;
    if (_activitiesScrollController.position.pixels >=
        _activitiesScrollController.position.maxScrollExtent * 0.9) {
      if (_activitiesDisplayCount < _checkedInGuests.length) {
        setState(() {
          _activitiesDisplayCount = (_activitiesDisplayCount + 5).clamp(5, _checkedInGuests.length);
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _activitiesScrollController.addListener(_onActivitiesScroll);
    _loadData();
    _activitiesSearchController.addListener(_filterActivitiesDebounced);
    _setupRealtimeSubscriptions();
    // Set default focus by role and sync clock-in status
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = Provider.of<AuthService>(context, listen: false);
      // Sync clock-in status with AuthService
      if (mounted) {
        setState(() {
          _isClockedIn = auth.isClockedIn;
        });
      }
      final role = auth.userRole;
      if (role == AppRole.owner || role == AppRole.accountant) {
        setState(() { _focus = 'financial'; });
      } else {
        setState(() { _focus = 'performance'; });
      }
    });
  }
  
  void _setupRealtimeSubscriptions() {
    if (_supabase == null) return;
    
    try {
      _realtimeChannel = _supabase!.channel('dashboard_updates')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'bookings',
          callback: (_) => _onRealtimeEvent('bookings'),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          callback: (_) => _onRealtimeEvent('bookings'),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'department_sales',
          callback: (_) => _onRealtimeEvent('sales'),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'department_sales',
          callback: (_) => _onRealtimeEvent('sales'),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'stock_transactions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'transaction_type',
            value: 'Sale',
          ),
          callback: (_) => _onRealtimeEvent('sales'),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'mini_mart_sales',
          callback: (_) => _onRealtimeEvent('sales'),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'kitchen_sales',
          callback: (_) => _onRealtimeEvent('sales'),
        )
        .subscribe();
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG realtime setup: $e\n$stack');
      if (mounted) ErrorHandler.showWarningMessage(context, ErrorHandler.getFriendlyErrorMessage(e));
    }
  }

  void _onRealtimeEvent(String slice) {
    try {
      if (mounted) _scheduleRealtimeRefresh(slice);
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG realtime callback: $e\n$stack');
      if (mounted) ErrorHandler.showWarningMessage(context, ErrorHandler.getFriendlyErrorMessage(e));
    }
  }

  void _scheduleRealtimeRefresh(String slice) {
    _pendingRealtimeSlices.add(slice);
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = Timer(
      const Duration(milliseconds: _realtimeDebounceMs),
      _runPendingRealtimeRefresh,
    );
  }

  Future<void> _runPendingRealtimeRefresh() async {
    final slices = _pendingRealtimeSlices.toList();
    _pendingRealtimeSlices.clear();
    _realtimeDebounceTimer = null;
    if (!mounted || slices.isEmpty || !_hasLoadedOnce) return;
    try {
      if (slices.contains('bookings')) {
        _dataService.invalidateCacheForTable('bookings');
        await _refreshBookingsSlice();
      }
      if (slices.contains('sales') && mounted) {
        _dataService.invalidateCacheForTable('department_sales');
        _dataService.invalidateCacheForTable('stock_transactions');
        _dataService.invalidateCacheForTable('mini_mart_sales');
        _dataService.invalidateCacheForTable('kitchen_sales');
        await _refreshSalesSlice();
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG realtime slice refresh: $e\n$stack');
      if (mounted) ErrorHandler.showWarningMessage(context, ErrorHandler.getFriendlyErrorMessage(e));
    }
  }

  Future<void> _refreshBookingsSlice() async {
    if (!mounted) return;
    try {
      final results = await Future.wait([
        _dataService.getCheckedInGuests(),
        _dataService.getBookings(),
      ]);
      final checkedInGuests = results[0] as List<Map<String, dynamic>>;
      final bookings = results[1] as List<Map<String, dynamic>>;
      if (mounted) {
        setState(() {
          _checkedInGuests = checkedInGuests;
          _bookings = bookings;
          _stats = {
            'checked_in_count': checkedInGuests.length,
          };
          _cachedFilteredActivities = null;
          _cachedBarGroups = null;
          _cachedChartRoomTypes = null;
        });
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _refreshBookingsSlice: $e\n$stack');
      if (mounted) ErrorHandler.showWarningMessage(context, ErrorHandler.getFriendlyErrorMessage(e));
    }
  }

  Future<void> _refreshSalesSlice() async {
    if (!mounted) return;
    try {
      final timeRange = _currentRange();
      final previousRange = _getPreviousRange(timeRange);
      final results = await Future.wait([
        _dataService.getDepartmentSales(department: 'vip_bar', startDate: timeRange.start, endDate: timeRange.end),
        _dataService.getDepartmentSales(department: 'outside_bar', startDate: timeRange.start, endDate: timeRange.end),
        _dataService.getDepartmentSales(department: 'mini_mart', startDate: timeRange.start, endDate: timeRange.end),
        _dataService.getDepartmentSales(department: 'restaurant', startDate: timeRange.start, endDate: timeRange.end),
        _dataService.getDepartmentSales(department: 'reception', startDate: timeRange.start, endDate: timeRange.end),
        _dataService.getDepartmentSales(department: 'vip_bar', startDate: previousRange.start, endDate: previousRange.end),
        _dataService.getDepartmentSales(department: 'outside_bar', startDate: previousRange.start, endDate: previousRange.end),
        _dataService.getDepartmentSales(department: 'mini_mart', startDate: previousRange.start, endDate: previousRange.end),
        _dataService.getDepartmentSales(department: 'restaurant', startDate: previousRange.start, endDate: previousRange.end),
        _dataService.getDepartmentSales(department: 'reception', startDate: previousRange.start, endDate: previousRange.end),
      ]);
      final vipSales = results[0] as List<Map<String, dynamic>>;
      final outsideSales = results[1] as List<Map<String, dynamic>>;
      final miniMartSales = results[2] as List<Map<String, dynamic>>;
      final kitchenSales = results[3] as List<Map<String, dynamic>>;
      final receptionSales = results[4] as List<Map<String, dynamic>>;
      final previousVipSales = results[5] as List<Map<String, dynamic>>;
      final previousOutsideSales = results[6] as List<Map<String, dynamic>>;
      final previousMiniMartSales = results[7] as List<Map<String, dynamic>>;
      final previousKitchenSales = results[8] as List<Map<String, dynamic>>;
      final previousReceptionSales = results[9] as List<Map<String, dynamic>>;
      final vipBarTotal = _sumFilteredDeptSales(vipSales, timeRange);
      final outsideBarTotal = _sumFilteredDeptSales(outsideSales, timeRange);
      final miniMartTotal = _sumFilteredDeptSales(miniMartSales, timeRange);
      final kitchenTotal = _sumFilteredDeptSales(kitchenSales, timeRange);
      final receptionTotal = _sumFilteredDeptSales(receptionSales, timeRange);
      final previousVipBarTotal = _sumFilteredDeptSales(previousVipSales, previousRange);
      final previousOutsideBarTotal = _sumFilteredDeptSales(previousOutsideSales, previousRange);
      final previousMiniMartTotal = _sumFilteredDeptSales(previousMiniMartSales, previousRange);
      final previousKitchenTotal = _sumFilteredDeptSales(previousKitchenSales, previousRange);
      final previousReceptionTotal = _sumFilteredDeptSales(previousReceptionSales, previousRange);
      final newPreviousDeptSalesSum = previousVipBarTotal + previousOutsideBarTotal + previousMiniMartTotal + previousKitchenTotal + previousReceptionTotal;
      final oldPreviousDeptSalesSum = _previousDeptSalesTotals.values.fold<num>(0, (s, v) => s + v);
      final newPreviousIncome = _previousIncome - oldPreviousDeptSalesSum + newPreviousDeptSalesSum;
      final newPreviousProfit = newPreviousIncome - _previousExpenses;
      if (mounted) {
        setState(() {
          _deptSalesTotals = {
            'VIP Bar': vipBarTotal,
            'Outside Bar': outsideBarTotal,
            'Mini Mart': miniMartTotal,
            'Kitchen': kitchenTotal,
            'Reception': receptionTotal,
          };
          _previousDeptSalesTotals = {
            'VIP Bar': previousVipBarTotal,
            'Outside Bar': previousOutsideBarTotal,
            'Mini Mart': previousMiniMartTotal,
            'Kitchen': previousKitchenTotal,
            'Reception': previousReceptionTotal,
          };
          _previousIncome = newPreviousIncome;
          _previousProfit = newPreviousProfit;
        });
      }
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _refreshSalesSlice: $e\n$stack');
      if (mounted) ErrorHandler.showWarningMessage(context, ErrorHandler.getFriendlyErrorMessage(e));
    }
  }

  DateTimeRange _getPreviousRange(DateTimeRange current) {
    final duration = current.end.difference(current.start);
    return DateTimeRange(
      start: current.start.subtract(duration),
      end: current.start.subtract(const Duration(milliseconds: 1)),
    );
  }

  num _sumFilteredDeptSales(List<Map<String, dynamic>> list, DateTimeRange range) {
    final filtered = list.where((sale) {
      final createdAt = _parseTimestamp(sale['created_at']);
      if (createdAt != null && _isDateInRange(createdAt, range)) return true;
      final updatedAt = _parseTimestamp(sale['updated_at']);
      if (updatedAt != null && _isDateInRange(updatedAt, range)) return true;
      final saleDate = _parseTimestamp(sale['date']);
      if (saleDate != null && _isDateInRange(saleDate, range)) return true;
      return false;
    }).toList();
    return filtered.fold<num>(0, (s, e) => s + (double.tryParse(e['total_sales']?.toString() ?? '') ?? 0));
  }

  bool _isDateInRange(DateTime date, DateTimeRange range) {
    return (date.isAfter(range.start) || date.isAtSameMomentAs(range.start)) 
        && (date.isBefore(range.end) || date.isAtSameMomentAs(range.end));
  }

  bool _hasLoadedOnce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Removed automatic refresh to prevent flickering
    // Real-time subscriptions handle updates, and pull-to-refresh is available
  }

  @override
  void dispose() {
    _realtimeDebounceTimer?.cancel();
    _realtimeDebounceTimer = null;
    _activitiesScrollController.removeListener(_onActivitiesScroll);
    _activitiesScrollController.dispose();
    _activitiesSearchController.removeListener(_filterActivitiesDebounced);
    _activitiesSearchDebounce?.cancel();
    _activitiesSearchDebounce = null;
    _activitiesSearchController.dispose();
    _searchController.dispose();
    if (_realtimeChannel != null) {
      _realtimeChannel!.unsubscribe();
      _supabase?.removeChannel(_realtimeChannel!);
    }
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final effectiveRole = authService.isRoleAssumed
          ? (authService.assumedRole ?? authService.userRole)
          : authService.userRole;
      final canApproveSupplies =
          effectiveRole == AppRole.owner || effectiveRole == AppRole.manager;

      DateTimeRange timeRange;
      try {
        timeRange = _currentRange();
        if (timeRange.start.isAfter(timeRange.end)) {
          throw Exception('Invalid date range: start date is after end date');
        }
      } catch (e, stackTrace) {
        if (kDebugMode) debugPrint('DEBUG date range: $e\n$stackTrace');
        if (mounted) {
          ErrorHandler.handleError(
            context,
            e,
            customMessage: 'Invalid date range selected. Please try again.',
            stackTrace: stackTrace,
          );
        }
        return;
      }

      DateTimeRange getPreviousRange(DateTimeRange current) {
        final duration = current.end.difference(current.start);
        return DateTimeRange(
          start: current.start.subtract(duration),
          end: current.start.subtract(const Duration(milliseconds: 1)),
        );
      }
      final previousRange = getPreviousRange(timeRange);

      // Run all independent sections in parallel
      final bookingsSection = Future.wait([
        _dataService.getCheckedInGuests(),
        _dataService.getBookings(),
      ]);

      final salesSection = Future.wait([
        _dataService.getDepartmentSales(
          department: 'vip_bar',
          startDate: timeRange.start,
          endDate: timeRange.end,
        ),
        _dataService.getDepartmentSales(
          department: 'outside_bar',
          startDate: timeRange.start,
          endDate: timeRange.end,
        ),
        _dataService.getDepartmentSales(
          department: 'mini_mart',
          startDate: timeRange.start,
          endDate: timeRange.end,
        ),
        _dataService.getDepartmentSales(
          department: 'restaurant',
          startDate: timeRange.start,
          endDate: timeRange.end,
        ),
        _dataService.getDepartmentSales(
          department: 'reception',
          startDate: timeRange.start,
          endDate: timeRange.end,
        ),
        _dataService.getDepartmentSales(
          department: 'vip_bar',
          startDate: previousRange.start,
          endDate: previousRange.end,
        ),
        _dataService.getDepartmentSales(
          department: 'outside_bar',
          startDate: previousRange.start,
          endDate: previousRange.end,
        ),
        _dataService.getDepartmentSales(
          department: 'mini_mart',
          startDate: previousRange.start,
          endDate: previousRange.end,
        ),
        _dataService.getDepartmentSales(
          department: 'restaurant',
          startDate: previousRange.start,
          endDate: previousRange.end,
        ),
        _dataService.getDepartmentSales(
          department: 'reception',
          startDate: previousRange.start,
          endDate: previousRange.end,
        ),
        _dataService.getStockTransactions(),
      ]);

      final financeSection = Future.wait([
        _dataService.getIncomeRecords(
          startDate: timeRange.start,
          endDate: timeRange.end,
        ),
        _dataService.getIncomeRecords(
          startDate: previousRange.start,
          endDate: previousRange.end,
        ),
        _dataService.getExpenses(
          startDate: timeRange.start,
          endDate: timeRange.end,
          status: 'Approved',
        ),
        _dataService.getExpenses(
          startDate: previousRange.start,
          endDate: previousRange.end,
          status: 'Approved',
        ),
        _dataService.getPurchaseOrders(
          startDate: timeRange.start,
          endDate: timeRange.end,
        ),
        _dataService.getPurchaseOrders(
          startDate: previousRange.start,
          endDate: previousRange.end,
        ),
        _dataService.getMaintenanceWorkOrders(
          startDate: timeRange.start,
          endDate: timeRange.end,
        ),
        _dataService.getMaintenanceWorkOrders(
          startDate: previousRange.start,
          endDate: previousRange.end,
        ),
      ]);

      final otherSection = Future.wait([
        _dataService.getLocations(),
        canApproveSupplies
            ? _dataService.getDirectSupplyRequests(status: 'pending')
            : Future<List<Map<String, dynamic>>>.value([]),
      ]);

      final results = await Future.wait([
        bookingsSection,
        salesSection,
        financeSection,
        otherSection,
      ]);

      final bookingsResults = results[0] as List;
      final checkedInGuests = bookingsResults[0] as List<Map<String, dynamic>>;
      final bookings = bookingsResults[1] as List<Map<String, dynamic>>;

      final salesResults = results[1] as List;
      final vipSales = salesResults[0] as List<Map<String, dynamic>>;
      final outsideSales = salesResults[1] as List<Map<String, dynamic>>;
      final miniMartSales = salesResults[2] as List<Map<String, dynamic>>;
      final kitchenSales = salesResults[3] as List<Map<String, dynamic>>;
      final receptionSales = salesResults[4] as List<Map<String, dynamic>>;
      final previousVipSales = salesResults[5] as List<Map<String, dynamic>>;
      final previousOutsideSales = salesResults[6] as List<Map<String, dynamic>>;
      final previousMiniMartSales = salesResults[7] as List<Map<String, dynamic>>;
      final previousKitchenSales = salesResults[8] as List<Map<String, dynamic>>;
      final previousReceptionSales = salesResults[9] as List<Map<String, dynamic>>;
      final stockTransactions = salesResults[10] as List<Map<String, dynamic>>;

      final financeResults = results[2] as List;
      final incomeRecords = financeResults[0] as List<Map<String, dynamic>>;
      final previousIncomeRecords = financeResults[1] as List<Map<String, dynamic>>;
      final expenses = financeResults[2] as List<Map<String, dynamic>>;
      final previousExpensesList = financeResults[3] as List<Map<String, dynamic>>;
      final purchaseOrders = financeResults[4] as List<Map<String, dynamic>>;
      final previousPurchaseOrders = financeResults[5] as List<Map<String, dynamic>>;
      final maintenanceOrders = financeResults[6] as List<Map<String, dynamic>>;
      final previousMaintenanceOrders = financeResults[7] as List<Map<String, dynamic>>;

      final otherResults = results[3] as List;
      final locations = otherResults[0] as List<Map<String, dynamic>>;
      final pendingSupplies = otherResults[1] as List<Map<String, dynamic>>;

      final checkedInCount = checkedInGuests.length;
      final previousBookings = bookings;
      final previousCheckedInCount = previousBookings.where((b) {
        final checkIn = _parseTimestamp(b['check_in_date']);
        if (checkIn == null) return false;
        return (checkIn.isAfter(previousRange.start) || checkIn.isAtSameMomentAs(previousRange.start)) 
            && (checkIn.isBefore(previousRange.end) || checkIn.isAtSameMomentAs(previousRange.end));
      }).length;

      if (mounted) {
        final vipBarLocation = locations.firstWhere(
          (l) => (l['name'] as String?)?.toLowerCase() == 'vip bar',
          orElse: () => <String, dynamic>{},
        );
        final outsideBarLocation = locations.firstWhere(
          (l) => (l['name'] as String?)?.toLowerCase() == 'outside bar',
          orElse: () => <String, dynamic>{},
        );
        
        // Filter department sales by business day logic
        // Since department_sales.date is calendar date, we need to filter by created_at/updated_at
        // to determine which records actually fall within the business day range
        List<Map<String, dynamic>> filterByBusinessDay(List<Map<String, dynamic>> sales) {
          return sales.where((sale) {
            // Try to use created_at first (most accurate)
            final createdAt = _parseTimestamp(sale['created_at']);
            if (createdAt != null && _isInRange(createdAt)) {
              return true;
            }
            // Fallback to updated_at
            final updatedAt = _parseTimestamp(sale['updated_at']);
            if (updatedAt != null && _isInRange(updatedAt)) {
              return true;
            }
            // If no timestamp available, use date field as fallback
            // This is less accurate but better than nothing
            final saleDate = _parseTimestamp(sale['date']);
            if (saleDate != null) {
              // Check if the calendar date falls within the business day range
              // This is approximate - assumes sales happen during business hours
              return _isInRange(saleDate);
            }
            return false;
          }).toList();
        }
        
        // Helper to filter sales by previous business day range
        List<Map<String, dynamic>> filterByPreviousBusinessDay(List<Map<String, dynamic>> sales) {
          return sales.where((sale) {
            final createdAt = _parseTimestamp(sale['created_at']);
            if (createdAt != null) {
              return (createdAt.isAfter(previousRange.start) || createdAt.isAtSameMomentAs(previousRange.start)) 
                  && (createdAt.isBefore(previousRange.end) || createdAt.isAtSameMomentAs(previousRange.end));
            }
            final updatedAt = _parseTimestamp(sale['updated_at']);
            if (updatedAt != null) {
              return (updatedAt.isAfter(previousRange.start) || updatedAt.isAtSameMomentAs(previousRange.start)) 
                  && (updatedAt.isBefore(previousRange.end) || updatedAt.isAtSameMomentAs(previousRange.end));
            }
            final saleDate = _parseTimestamp(sale['date']);
            if (saleDate != null) {
              return (saleDate.isAfter(previousRange.start) || saleDate.isAtSameMomentAs(previousRange.start)) 
                  && (saleDate.isBefore(previousRange.end) || saleDate.isAtSameMomentAs(previousRange.end));
            }
            return false;
          }).toList();
        }
        
        // Calculate department sales totals (using total_sales field from department_sales table)
        num sumDeptSales(List<Map<String, dynamic>> list) {
          final filtered = filterByBusinessDay(list);
          return filtered.fold<num>(0, (s, e) => s + (double.tryParse(e['total_sales']?.toString() ?? '') ?? 0));
        }
        
        num sumPreviousDeptSales(List<Map<String, dynamic>> list) {
          final filtered = filterByPreviousBusinessDay(list);
          return filtered.fold<num>(0, (s, e) => s + (double.tryParse(e['total_sales']?.toString() ?? '') ?? 0));
        }
        
        final vipBarTotal = sumDeptSales(vipSales);
        final outsideBarTotal = sumDeptSales(outsideSales);
        final miniMartTotal = sumDeptSales(miniMartSales);
        final kitchenTotal = sumDeptSales(kitchenSales);
        final receptionTotal = sumDeptSales(receptionSales);
        
        // Calculate previous period totals
        final previousVipBarTotal = sumPreviousDeptSales(previousVipSales);
        final previousOutsideBarTotal = sumPreviousDeptSales(previousOutsideSales);
        final previousMiniMartTotal = sumPreviousDeptSales(previousMiniMartSales);
        final previousKitchenTotal = sumPreviousDeptSales(previousKitchenSales);
        final previousReceptionTotal = sumPreviousDeptSales(previousReceptionSales);
        
        // Calculate previous period income
        num previousIncomeFromRecords = previousIncomeRecords.fold<num>(0, (s, e) => s + (double.tryParse(e['amount']?.toString() ?? '') ?? 0));
        num previousIncomeFromBookings = previousBookings.where((b) {
          final checkIn = _parseTimestamp(b['check_in_date']);
          if (checkIn == null) return false;
          return (checkIn.isAfter(previousRange.start) || checkIn.isAtSameMomentAs(previousRange.start)) 
              && (checkIn.isBefore(previousRange.end) || checkIn.isAtSameMomentAs(previousRange.end));
        }).fold<num>(0, (s, b) => s + (double.tryParse(b['paid_amount']?.toString() ?? '') ?? 0));
        num previousIncomeFromDeptSales = previousVipBarTotal + previousOutsideBarTotal + previousMiniMartTotal + previousKitchenTotal + previousReceptionTotal;
        final previousIncome = previousIncomeFromRecords + previousIncomeFromBookings + previousIncomeFromDeptSales;
        
        // Calculate previous period expenses
        num previousExpensesFromTable = previousExpensesList.fold<num>(0, (s, e) => s + (double.tryParse(e['amount']?.toString() ?? '') ?? 0));
        num previousExpensesFromPurchases = previousPurchaseOrders.where((po) {
          final created = _parseTimestamp(po['created_at']);
          if (created == null) return false;
          return (created.isAfter(previousRange.start) || created.isAtSameMomentAs(previousRange.start)) 
              && (created.isBefore(previousRange.end) || created.isAtSameMomentAs(previousRange.end));
        }).fold<num>(0, (sum, po) {
          final items = po['purchase_order_items'] as List?;
          if (items != null && items.isNotEmpty) {
            final itemsTotal = items.fold<num>(0, (itemSum, item) {
              final qty = (item['quantity'] as num?) ?? 0;
              final unitPrice = (item['unit_price'] as num?) ?? 0;
              return itemSum + (qty * unitPrice);
            });
            return sum + itemsTotal;
          }
          return sum + ((po['total_cost'] as num?) ?? 0);
        });
        num previousExpensesFromMaintenance = previousMaintenanceOrders.where((mo) {
          final created = _parseTimestamp(mo['created_at']);
          if (created == null) return false;
          return (created.isAfter(previousRange.start) || created.isAtSameMomentAs(previousRange.start)) 
              && (created.isBefore(previousRange.end) || created.isAtSameMomentAs(previousRange.end))
              && (mo['status'] == 'Completed');
        }).fold<num>(0, (s, mo) => s + ((mo['actual_cost'] as num?) ?? 0));
        final previousExpenses = previousExpensesFromTable + previousExpensesFromPurchases + previousExpensesFromMaintenance;
        final previousProfit = previousIncome - previousExpenses;
        
        setState(() {
          _bookings = bookings;
          _checkedInGuests = checkedInGuests;
          _cachedFilteredActivities = null;
          _cachedBarGroups = null;
          _cachedChartRoomTypes = null;
          _pendingDirectSupplies = pendingSupplies;
          _isLoading = false;
          _isLoadingAttendance = false;
          
          // Store current period totals
          _deptSalesTotals = {
            'VIP Bar': vipBarTotal,
            'Outside Bar': outsideBarTotal,
            'Mini Mart': miniMartTotal,
            'Kitchen': kitchenTotal,
            'Reception': receptionTotal,
          };
          
          // Store previous period totals for trend calculation
          _previousDeptSalesTotals = {
            'VIP Bar': previousVipBarTotal,
            'Outside Bar': previousOutsideBarTotal,
            'Mini Mart': previousMiniMartTotal,
            'Kitchen': previousKitchenTotal,
            'Reception': previousReceptionTotal,
          };
          _previousIncome = previousIncome;
          _previousExpenses = previousExpenses;
          _previousProfit = previousProfit;
          _previousCheckedInCount = previousCheckedInCount;
          
          // Debug: Log if totals are zero
          if (kDebugMode) {
            print('Dashboard Sales Totals (Current):');
            print('VIP Bar: $vipBarTotal (${vipSales.length} records, filtered: ${filterByBusinessDay(vipSales).length})');
            print('Outside Bar: $outsideBarTotal (${outsideSales.length} records, filtered: ${filterByBusinessDay(outsideSales).length})');
            print('Mini Mart: $miniMartTotal (${miniMartSales.length} records, filtered: ${filterByBusinessDay(miniMartSales).length})');
            print('Kitchen: $kitchenTotal (${kitchenSales.length} records, filtered: ${filterByBusinessDay(kitchenSales).length})');
            print('Reception: $receptionTotal (${receptionSales.length} records, filtered: ${filterByBusinessDay(receptionSales).length})');
            print('Date Range: ${timeRange.start.toIso8601String()} to ${timeRange.end.toIso8601String()}');
            print('Previous Range: ${previousRange.start.toIso8601String()} to ${previousRange.end.toIso8601String()}');
            if (vipSales.isNotEmpty) {
              print('Sample VIP Bar record: ${vipSales.first}');
            }
          }
          
          // Store checked-in count in stats for display
          _stats = {
            'checked_in_count': checkedInCount,
          };
          
          // Store income and expenses for financial cards
          _incomeRecords = incomeRecords;
          _expenseRecords = expenses;
          
          // Store additional data for income/expense calculation
          _bookings = bookings;
          _purchaseOrders = purchaseOrders;
          _maintenanceOrders = maintenanceOrders;
          _stockTransactions = stockTransactions;
          
          _hasLoadedOnce = true;
        });
      }
    } catch (e, stackTrace) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isLoadingAttendance = false;
        });
        if (kDebugMode) debugPrint('DEBUG dashboard load: $e\n$stackTrace');
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to load dashboard data. Please check your date range and try again.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<Map<String, dynamic>> _calculateDashboardStats() async {
    // Calculate stats from actual bookings
      return {
      'checked_in_count': _bookings.where((b) => _normalizeBookingStatus(b['status']?.toString()) == 'checked-in').length,
      'pending_count': _bookings.where((b) => _normalizeBookingStatus(b['status']?.toString()) == 'pending').length,
      'occupancy_rate': (_stats['occupancy_rate'] ?? 65),
      'total_revenue': _stats['total_revenue'] ?? 0,
    };
  }


  String _normalizeBookingStatus(String? raw) {
    if (raw == null) return '';
    final normalized = raw.trim().toLowerCase().replaceAll('_', '-');
    switch (normalized) {
      case 'pending':
      case 'pending check-in':
      case 'pending checkin':
        return 'pending';
      case 'checked-in':
      case 'checked in':
        return 'checked-in';
      case 'checked-out':
      case 'checked out':
        return 'checked-out';
      case 'cancelled':
        return 'cancelled';
      case 'confirmed':
        return 'confirmed';
      default:
        return normalized;
    }
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
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _fetchLastAttendance: $e\n$stack');
      final authService = Provider.of<AuthService>(context, listen: false);
      if (mounted) {
        setState(() {
          _isClockedIn = authService.isClockedIn;
        });
      }
      return null;
    }
  }

  void _filterActivitiesDebounced() {
    _activitiesSearchDebounce?.cancel();
    _activitiesSearchDebounce = Timer(const Duration(milliseconds: _activitiesSearchDebounceMs), () {
      if (!mounted) return;
      setState(() {
        _activitiesSearchQuery = _activitiesSearchController.text.trim();
        _cachedFilteredActivities = null;
      });
    });
  }

  List<Map<String, dynamic>> _getFilteredActivities() {
    if (_cachedFilteredActivities != null) return _cachedFilteredActivities!;
    final sorted = List<Map<String, dynamic>>.from(_checkedInGuests)
      ..sort((a, b) {
        final aTime = a['check_in_date'] != null ? DateTime.tryParse(a['check_in_date'].toString()) : null;
        final bTime = b['check_in_date'] != null ? DateTime.tryParse(b['check_in_date'].toString()) : null;
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });
    final query = _activitiesSearchQuery.toLowerCase();
    final filtered = query.isEmpty
        ? sorted
        : sorted.where((guest) {
            final roomNumber = (guest['rooms']?['room_number'] as String? ?? guest['room_number'] as String? ?? '').toLowerCase();
            String guestName = '';
            if (guest['profiles'] != null) {
              if (guest['profiles'] is Map) {
                guestName = (guest['profiles']['full_name'] as String? ?? guest['profiles']['guest_profile_id']?['full_name'] as String? ?? '').toLowerCase();
              }
            } else {
              guestName = (guest['guest_name'] as String? ?? '').toLowerCase();
            }
            return guestName.contains(query) || roomNumber.contains(query);
          }).toList();
    _cachedFilteredActivities = filtered;
    return filtered;
  }


  String _formatKobo(num value) {
    // Ensure value is never null and handle edge cases
    final safeValue = value ?? 0;
    final intValue = safeValue.toInt();
    final nairaValue = PaymentService.koboToNaira(intValue);
    // Always return a formatted string, even for zero
    final formatted = NumberFormat('#,##0.00').format(nairaValue);
    // Ensure we never return an empty string
    return formatted.isEmpty ? '0.00' : formatted;
  }

  Future<void> _handleClockIn() async {
    // #region agent log
    debugLog({"location":"dashboard_screen.dart:267","message":"Clock-in button clicked (dashboard)","data":{"timestamp":DateTime.now().millisecondsSinceEpoch},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"A"});
    print('DEBUG: Clock-in button clicked in dashboard');
    // #endregion
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      // #region agent log
      debugLog({"location":"dashboard_screen.dart:270","message":"Before clockIn call (dashboard)","data":{"userId":authService.currentUser?.id,"isClockedIn":authService.isClockedIn},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"B"});
      print('DEBUG: Before clockIn - userId: ${authService.currentUser?.id}, isClockedIn: ${authService.isClockedIn}');
      // #endregion
      await authService.clockIn();
      // #region agent log
      debugLog({"location":"dashboard_screen.dart:272","message":"After clockIn call - success (dashboard)","data":{"clockInTime":authService.clockInTime?.toIso8601String(),"isClockedIn":authService.isClockedIn},"timestamp":DateTime.now().millisecondsSinceEpoch,"sessionId":"debug-session","runId":"run1","hypothesisId":"C"});
      print('DEBUG: ClockIn success - clockInTime: ${authService.clockInTime}');
      // #endregion
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
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG ClockIn: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          stackTrace: stackTrace,
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
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG ClockOut: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to clock out. Please try again.',
          stackTrace: stackTrace,
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
          : RefreshIndicator(
              onRefresh: _loadData,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final screenWidth = constraints.maxWidth;
                  final isMobile = screenWidth < 600;
                  if (screenWidth > 1200) {
                    return _buildDesktopLayout(context, screenWidth, isMobile);
                  } else if (screenWidth > 800) {
                    return _buildTabletLayout(context, screenWidth, isMobile);
                  } else {
                    return _buildMobileLayout(context, screenWidth, isMobile);
                  }
                },
              ),
            ),
    );
  }

  Widget _buildDesktopLayout(BuildContext context, double screenWidth, bool isMobile) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(24),
      child: AppAnimations.staggeredList(
        scrollable: false,
        children: [
          _buildHeader(context, isMobile),
          const SizedBox(height: 12),
          _buildQuickNav(context, isMobile),
          const SizedBox(height: 12),
          _buildTimeRangeToolbar(context, isMobile),
          const SizedBox(height: 24),
          _buildAllCards(context, screenWidth, isMobile),
          const SizedBox(height: 24),
          _buildCheckedInGuestsCard(context),
          const SizedBox(height: 24),
          _buildCalendarLauncher(context, isMobile),
          const SizedBox(height: 24),
          _buildRecentActivities(context, isMobile: isMobile, screenWidth: screenWidth),
        ],
      ),
    );
  }

  Widget _buildTabletLayout(BuildContext context, double screenWidth, bool isMobile) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(), // Required for RefreshIndicator
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, isMobile),
          const SizedBox(height: 12),
          _buildQuickNav(context, isMobile),
          const SizedBox(height: 16),
          _buildTimeRangeToolbar(context, isMobile),
          const SizedBox(height: 16),
          _buildAllCards(context, screenWidth, isMobile),
          const SizedBox(height: 16),
          _buildCheckedInGuestsCard(context),
          const SizedBox(height: 16),
          _buildCalendarLauncher(context, isMobile),
          const SizedBox(height: 16),
          _buildRecentActivities(context, isMobile: isMobile, screenWidth: screenWidth),
        ],
      ),
    );
  }

  Widget _buildMobileLayout(BuildContext context, double screenWidth, bool isMobile) {
    return SingleChildScrollView(
      physics: const AlwaysScrollableScrollPhysics(), // Required for RefreshIndicator
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(context, isMobile),
          const SizedBox(height: 16),
          _buildQuickNav(context, isMobile),
          const SizedBox(height: 16),
          _buildTimeRangeToolbar(context, isMobile),
          const SizedBox(height: 16),
          _buildAllCards(context, screenWidth, isMobile),
          const SizedBox(height: 16),
          _buildCheckedInGuestsCard(context),
          const SizedBox(height: 16),
          _buildCalendarLauncher(context, isMobile),
          const SizedBox(height: 16),
          _buildRecentActivities(context, isMobile: isMobile, screenWidth: screenWidth),
        ],
      ),
    );
  }

  Widget _buildCalendarLauncher(BuildContext context, bool isMobile) {
    final titleWidget = Text(
      'Booking Calendar',
      style: Theme.of(context).textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: Colors.black87,
      ),
    );
    final viewCalendarBtn = ElevatedButton.icon(
      onPressed: _showCalendarDialog,
      icon: const Icon(Icons.calendar_today),
      label: const Text('View Calendar'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
      ),
    );
    final bookingCalendarBtn = ElevatedButton.icon(
      onPressed: _showFrontDeskCalendarDialog,
      icon: const Icon(Icons.view_timeline),
      label: const Text('Booking Calendar'),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.green[800],
        foregroundColor: Colors.white,
      ),
    );

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
      child: isMobile
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: titleWidget),
                  ],
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: viewCalendarBtn,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: bookingCalendarBtn,
                ),
              ],
            )
          : Row(
              children: [
                Expanded(child: titleWidget),
                viewCalendarBtn,
                const SizedBox(width: 8),
                bookingCalendarBtn,
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
      } catch (e, stack) {
        if (kDebugMode) debugPrint('DEBUG rooms query: $e\n$stack');
        rooms = [];
      }
    }

    Color statusColor(String status) {
      switch (_normalizeBookingStatus(status)) {
        case 'booked':
          return const Color(0xFF3B82F6);
        case 'checked-in':
          return const Color(0xFF22C55E);
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


 

  Widget _buildHeader(BuildContext context, bool isMobile) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final role = auth.userRole;
    final isManagement = role == AppRole.owner || role == AppRole.manager || role == AppRole.accountant || role == AppRole.hr || role == AppRole.supervisor;

    final welcomeSection = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Dashboard',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: Colors.green[800],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Welcome back! Here\'s what\'s happening at P-ZED Luxury Hotels & Suites.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Colors.grey[700],
          ),
        ),
      ],
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          welcomeSection,
          const SizedBox(height: 16),
          if (isManagement) _buildFocusToggle(),
          if (!isManagement) _buildAttendanceCard(),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: welcomeSection),
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

  int _getCrossAxisCount(double screenWidth) {
    if (screenWidth < 800) return 2;
    if (screenWidth < 1200) return 3;
    return 4;
  }

  Widget _buildAllCards(BuildContext context, double screenWidth, bool isMobile) {
    final crossAxisCount = _getCrossAxisCount(screenWidth);
    final padding = screenWidth < 600 ? 16.0 : 24.0;
    final spacing = 12.0;
    final cardWidth = (screenWidth - (padding * 2) - (spacing * (crossAxisCount - 1))) / crossAxisCount;
    
    // Calculate income from all sources (already filtered by date in query)
    // 1. Income records
    num incomeFromRecords = _incomeRecords.fold<num>(0, (s, e) => s + (double.tryParse(e['amount']?.toString() ?? '') ?? 0));
    
    // 2. Bookings (paid amounts)
    num incomeFromBookings = _bookings.where((b) {
      final checkIn = _parseTimestamp(b['check_in_date']);
      return checkIn != null && _isInRange(checkIn);
    }).fold<num>(0, (s, b) => s + ((b['paid_amount'] as num?) ?? 0));
    
    // 3. Department sales (already filtered by date in query)
    num incomeFromDeptSales = _deptSalesTotals.values.fold<num>(0, (s, v) => s + v);
    
    // Total income
    final income = incomeFromRecords + incomeFromBookings + incomeFromDeptSales;
    
    // Calculate expenses from all sources (already filtered by date in query)
    // 1. Expenses table
    num expensesFromTable = _expenseRecords.fold<num>(0, (s, e) => s + (double.tryParse(e['amount']?.toString() ?? '') ?? 0));
    
    // 2. Purchase orders (total_cost)
    num expensesFromPurchases = _purchaseOrders.where((po) {
      final created = _parseTimestamp(po['created_at']);
      return created != null && _isInRange(created);
    }).fold<num>(0, (sum, po) {
      // Calculate total from purchase_order_items if available
      final items = po['purchase_order_items'] as List?;
      if (items != null && items.isNotEmpty) {
        final itemsTotal = items.fold<num>(0, (itemSum, item) {
          final qty = (item['quantity'] as num?) ?? 0;
          final unitPrice = (item['unit_price'] as num?) ?? 0;
          return itemSum + (qty * unitPrice);
        });
        return sum + itemsTotal;
      }
      // Fallback to total_cost if available
      return sum + ((po['total_cost'] as num?) ?? 0);
    });
    
    // 3. Maintenance work orders (actual_cost, only completed ones)
    num expensesFromMaintenance = _maintenanceOrders.where((mo) {
      final created = _parseTimestamp(mo['created_at']);
      return created != null && _isInRange(created) && (mo['status'] == 'Completed');
    }).fold<num>(0, (s, mo) => s + ((mo['actual_cost'] as num?) ?? 0));
    
    // Total expenses
    final expenses = expensesFromTable + expensesFromPurchases + expensesFromMaintenance;
    
    // Net profit
    final profit = income - expenses;
    
    // Build all cards in specified order: Checked In, Reception, VIP Bar, Outside Bar, Kitchen, Mini Mart, Income, Expenses, Profit
    final allCards = <Widget>[
      // 1. Checked In
      _buildKPICard(
        context,
        'Checked In',
        _stats['checked_in_count'] ?? 0,
        _previousCheckedInCount,
        Icons.login,
        Colors.green[700]!,
        false,
      ),
      // 2. Reception
      _buildKPICard(
        context,
        'Reception',
        (_deptSalesTotals['Reception'] as num?) ?? 0,
        (_previousDeptSalesTotals['Reception'] as num?) ?? 0,
        Icons.point_of_sale,
        Colors.green[700]!,
        true,
      ),
      // 3. VIP Bar
      _buildKPICard(
        context,
        'VIP Bar',
        (_deptSalesTotals['VIP Bar'] as num?) ?? 0,
        (_previousDeptSalesTotals['VIP Bar'] as num?) ?? 0,
        Icons.point_of_sale,
        Colors.green[700]!,
        true,
      ),
      // 4. Outside Bar
      _buildKPICard(
        context,
        'Outside Bar',
        (_deptSalesTotals['Outside Bar'] as num?) ?? 0,
        (_previousDeptSalesTotals['Outside Bar'] as num?) ?? 0,
        Icons.point_of_sale,
        Colors.green[700]!,
        true,
      ),
      // 5. Kitchen
      _buildKPICard(
        context,
        'Kitchen',
        (_deptSalesTotals['Kitchen'] as num?) ?? 0,
        (_previousDeptSalesTotals['Kitchen'] as num?) ?? 0,
        Icons.point_of_sale,
        Colors.green[700]!,
        true,
      ),
      // 6. Mini Mart
      _buildKPICard(
        context,
        'Mini Mart',
        (_deptSalesTotals['Mini Mart'] as num?) ?? 0,
        (_previousDeptSalesTotals['Mini Mart'] as num?) ?? 0,
        Icons.point_of_sale,
        Colors.green[700]!,
        true,
      ),
      // 7. Income
      _buildKPICard(
        context,
        'Income',
        income,
        _previousIncome,
        Icons.trending_up,
        Colors.green[700]!,
        true,
      ),
      // 8. Expenses (trend is inverted - lower is better, so we invert the trend)
      _buildKPICardWithInvertedTrend(
        context,
        'Expenses',
        expenses,
        _previousExpenses,
        Icons.trending_down,
        Colors.orange[700]!,
        true,
      ),
      // 9. Profit
      _buildKPICard(
        context,
        'Net Profit',
        profit,
        _previousProfit,
        Icons.account_balance,
        Colors.blue[700]!,
        true,
      ),
    ];
    
    // RepaintBoundary isolates KPI card grid from parent scroll/repaint cascades
    return RepaintBoundary(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: cardWidth / 140, // Fixed height of 140px for consistency
        ),
        itemCount: allCards.length,
        itemBuilder: (context, index) => allCards[index],
      ),
    );
  }
  
  // Calculate trend percentage change
  double _calculateTrend(num current, num previous) {
    if (previous == 0) {
      return current > 0 ? 100.0 : 0.0;
    }
    return ((current - previous) / previous) * 100;
  }
  
  // Unified KPI card builder with stable layout
  Widget _buildKPICard(
    BuildContext context,
    String title,
    num currentValue,
    num previousValue,
    IconData icon,
    Color color,
    bool isCurrency,
  ) {
    final trend = _calculateTrend(currentValue, previousValue);
    final isPositive = trend >= 0;
    final trendColor = isPositive ? Colors.green[700]! : Colors.red[700]!;
    final trendIcon = isPositive ? Icons.trending_up : Icons.trending_down;
    
    final displayValue = isCurrency
        ? '₦${_formatKobo(currentValue)}'
        : '${currentValue.toInt()}';
    
    final trendText = trend.abs() < 0.01
        ? 'No change'
        : '${isPositive ? '+' : ''}${trend.toStringAsFixed(1)}%';
    
    return AppAnimations.animatedCard(
      child: Container(
        height: 140, // Fixed height for consistency
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
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: Icon (left) and Trend badge (right)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon container (top-left)
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                // Trend badge (top-right)
                if (previousValue != 0 || currentValue != 0)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: trendColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(trendIcon, color: trendColor, size: 12),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              trendText,
                              style: TextStyle(
                                color: trendColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            // Primary KPI value (large font, single line)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                displayValue,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0A0A0A),
                      fontSize: 24,
                      height: 1.2,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            // Card label (small, muted text)
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF666666),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
  
  // KPI card builder with inverted trend (for expenses where lower is better)
  Widget _buildKPICardWithInvertedTrend(
    BuildContext context,
    String title,
    num currentValue,
    num previousValue,
    IconData icon,
    Color color,
    bool isCurrency,
  ) {
    // Invert trend: if expenses decreased, that's positive
    final rawTrend = _calculateTrend(currentValue, previousValue);
    final trend = -rawTrend; // Invert: decrease in expenses is positive
    final isPositive = trend >= 0;
    final trendColor = isPositive ? Colors.green[700]! : Colors.red[700]!;
    final trendIcon = isPositive ? Icons.trending_down : Icons.trending_up; // Inverted icons
    
    final displayValue = isCurrency
        ? '₦${_formatKobo(currentValue)}'
        : '${currentValue.toInt()}';
    
    final trendText = trend.abs() < 0.01
        ? 'No change'
        : '${isPositive ? '' : '+'}${rawTrend.toStringAsFixed(1)}%'; // Show actual change (decrease is positive)
    
    return AppAnimations.animatedCard(
      child: Container(
        height: 140, // Fixed height for consistency
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
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row: Icon (left) and Trend badge (right)
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Icon container (top-left)
                Container(
                  width: 40,
                  height: 40,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                // Trend badge (top-right)
                if (previousValue != 0 || currentValue != 0)
                  Flexible(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      decoration: BoxDecoration(
                        color: trendColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(trendIcon, color: trendColor, size: 12),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              trendText,
                              style: TextStyle(
                                color: trendColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(),
            // Primary KPI value (large font, single line)
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                displayValue,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF0A0A0A),
                      fontSize: 24,
                      height: 1.2,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 4),
            // Card label (small, muted text)
            Text(
              title,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: const Color(0xFF666666),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDepartmentSalesQuickCards(BuildContext context, double screenWidth) {
    final crossAxisCount = _getCrossAxisCount(screenWidth);
    final padding = screenWidth < 600 ? 16.0 : 24.0;
    final spacing = 12.0;
    final cardWidth = (screenWidth - (padding * 2) - (spacing * (crossAxisCount - 1))) / crossAxisCount;
    
    // RepaintBoundary isolates department sales grid from parent repaints
    return RepaintBoundary(
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: crossAxisCount,
          crossAxisSpacing: spacing,
          mainAxisSpacing: spacing,
          childAspectRatio: cardWidth / 120, // Adjust height based on card width
        ),
        itemCount: _deptSalesTotals.length,
        itemBuilder: (context, index) {
          final entry = _deptSalesTotals.entries.elementAt(index);
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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                Flexible(
                  child: Text(
                    '₦${_formatKobo(entry.value)}',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: const Color(0xFF0A0A0A),
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.key,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: const Color(0xFF666666),
                      ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        );
      },
    ),
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
                    Text('by Staff', style: const TextStyle(color: Colors.black45)),
                  ],
                ),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }


  Widget _buildMetricCard(BuildContext context, String title, String value, IconData icon, Color color) {
    return AppAnimations.animatedCard(
      child: Container(
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
    // RepaintBoundary isolates entire chart card from scroll-triggered repaints
    return RepaintBoundary(
      child: Container(
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
          // RepaintBoundary isolates chart from parent repaints; duration: Duration.zero avoids repeat animations on rebuild
          RepaintBoundary(
            child: SizedBox(
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
              duration: Duration.zero,
            ),
          ),
        ),
        ],
      ),
    ),
    );
  }

  List<BarChartGroupData> _generateBarGroups() {
    if (_cachedBarGroups != null) return _cachedBarGroups!;
    final roomTypeCounts = <String, int>{};
    int totalOccupied = 0;
    for (var booking in _bookings) {
      if (_normalizeBookingStatus(booking['status']?.toString()) == 'checked-in' &&
          booking['room_id'] != null) {
        totalOccupied++;
        final roomType = booking['rooms']?['type'] as String? ?? booking['requested_room_type'] as String? ?? 'Unknown';
        roomTypeCounts[roomType] = (roomTypeCounts[roomType] ?? 0) + 1;
      }
    }
    if (roomTypeCounts.isEmpty || totalOccupied == 0) {
      _cachedBarGroups = List.generate(5, (index) => BarChartGroupData(
        x: index + 1,
        barRods: [BarChartRodData(
          toY: 0,
          color: Colors.grey[300]!,
          width: 20,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
        )],
      ));
      return _cachedBarGroups!;
    }
    final sortedTypes = roomTypeCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final chartData = sortedTypes.take(5).toList();
    _cachedBarGroups = chartData.asMap().entries.map((entry) {
      final count = entry.value.value;
      final percentage = (count / totalOccupied * 100).clamp(0.0, 100.0);
      return BarChartGroupData(
        x: entry.key + 1,
        barRods: [BarChartRodData(
          toY: percentage,
          color: Colors.green[400]!,
          width: 20,
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(4), topRight: Radius.circular(4)),
        )],
      );
    }).toList();
    return _cachedBarGroups!;
  }

  List<String> _getRoomTypesForChart() {
    if (_cachedChartRoomTypes != null) return _cachedChartRoomTypes!;
    final roomTypeCounts = <String, int>{};
    for (var booking in _bookings) {
      if (_normalizeBookingStatus(booking['status']?.toString()) == 'checked-in' && booking['room_id'] != null) {
        final roomType = booking['rooms']?['type'] as String? ?? booking['requested_room_type'] as String? ?? 'Unknown';
        roomTypeCounts[roomType] = (roomTypeCounts[roomType] ?? 0) + 1;
      }
    }
    final sortedTypes = roomTypeCounts.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    _cachedChartRoomTypes = sortedTypes.take(5).map((e) => e.key).toList();
    return _cachedChartRoomTypes!;
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

  Widget _buildRecentActivities(BuildContext context, {required bool isMobile, required double screenWidth}) {
    final filteredActivities = _getFilteredActivities();
    final displayedActivities = filteredActivities.take(_activitiesDisplayCount).toList();
    
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
          Row(
            children: [
              Text(
                'Recent Activities',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.green[800],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: isMobile ? 200 : 300,
                child: TextField(
                  controller: _activitiesSearchController,
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
          const SizedBox(height: 16),
          if (filteredActivities.isEmpty)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text('No recent activities'),
            )
          else
            // RepaintBoundary isolates activities list from parent repaints during scroll
            RepaintBoundary(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 400),
                child: ListView.builder(
                  controller: _activitiesScrollController,
                shrinkWrap: true,
                itemCount: displayedActivities.length,
                itemBuilder: (context, index) {
                  final guest = displayedActivities[index];
                  
                  // Extract room number
                  final roomNumber = guest['rooms']?['room_number'] as String? ?? 
                                    guest['room_number'] as String? ?? 
                                    'N/A';
                  
                  // Extract guest name
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
                },
              ),
            ),
            ),
        ],
      ),
    );
  }


  Widget _buildAttendanceCard() {
    // Clock-in/clock-out functionality removed - return empty widget
    return const SizedBox.shrink();
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
    switch (_normalizeBookingStatus(status)) {
      case 'checked-in':
        return Colors.green;
      case 'pending':
        return Colors.orange;
      case 'checked-out':
        return Colors.blue;
      case 'cancelled':
        return Colors.red;
      case 'confirmed':
        return Colors.purple;
      default:
        return Colors.grey;
    }
  }

  // Toolbar to select time range filters
  Widget _buildTimeRangeToolbar(BuildContext context, bool isMobile) {
    final chipSpacing = isMobile ? 4.0 : 8.0;
    final chipPadding = isMobile ? const EdgeInsets.symmetric(horizontal: 8, vertical: 4) : null;
    final labelStyle = isMobile ? const TextStyle(fontSize: 11) : null;

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

    return Wrap(
      spacing: chipSpacing,
      runSpacing: chipSpacing,
      children: TimeRange.values.map((r) {
        final selected = _timeRange == r;
        return ChoiceChip(
          label: Text(labelFor(r), style: labelStyle),
          padding: chipPadding,
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
                  _isLoading = true;
                });
                _loadData();
              }
            } else {
              setState(() {
                _timeRange = r;
                _customRange = null;
                _isLoading = true;
              });
              _loadData();
            }
          },
          selectedColor: Colors.green[700],
        );
      }).toList(),
    );
  }

  // Role-specific metrics section
  Widget _buildRoleSpecificSection(BuildContext context, double screenWidth) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final effectiveRole = auth.userRole;

    switch (effectiveRole) {
      case AppRole.owner:
        return _focus == 'financial' ? _buildManagementAggregate(context) : _buildPerformanceAggregate(context, screenWidth);
      case AppRole.accountant:
        return _buildManagementAggregate(context);
      case AppRole.manager:
        return _focus == 'financial' ? _buildManagementAggregate(context) : _buildPerformanceAggregate(context, screenWidth);
      case AppRole.receptionist:
        return _buildReceptionistPanel(context, screenWidth);
      case AppRole.vip_bartender:
        return _buildBartenderPanel(context, screenWidth);
      case AppRole.outside_bartender:
        return _buildBartenderPanel(context, screenWidth);
      case AppRole.kitchen_staff:
        return _buildKitchenPanel(context, screenWidth);
      case AppRole.storekeeper:
        return _buildStorekeeperPanel(context, screenWidth);
      case AppRole.purchaser:
        return _buildPurchaserPanel(context, screenWidth);
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
  Widget _buildPerformanceAggregate(BuildContext context, double screenWidth) {
    return _buildReceptionistPanel(context, screenWidth); // reuse a performance-like panel as placeholder
  }

  // Quick navigation for department and key areas
  Widget _buildQuickNav(BuildContext context, bool isMobile) {
    final auth = Provider.of<AuthService>(context, listen: false);
    final role = auth.userRole;
    final isManagement = role == AppRole.owner || role == AppRole.manager || role == AppRole.accountant || role == AppRole.hr || role == AppRole.supervisor;

    if (!isManagement) {
      return Wrap(
        spacing: isMobile ? 6 : 8,
        runSpacing: isMobile ? 8 : 8,
        children: [
          _quickButton(context, 'My Department', Icons.domain, () {
            if (role == AppRole.storekeeper) context.go('/storekeeping');
            else if (role == AppRole.purchaser) context.go('/purchasing');
            else if (role == AppRole.kitchen_staff) context.go('/kitchen');
            else if (role == AppRole.vip_bartender || role == AppRole.outside_bartender) context.go('/inventory');
            else if (role == AppRole.housekeeper || role == AppRole.cleaner || role == AppRole.laundry_attendant) context.go('/housekeeping');
            else context.go('/dashboard');
          }, isMobile),
          _quickButton(context, 'My Profile', Icons.person, () { context.push('/profile'); }, isMobile),
        ],
      );
    }

    final managementButtons = <Widget>[
      if (role == AppRole.owner || role == AppRole.manager || role == AppRole.hr)
        _quickButton(context, 'HR', Icons.people_alt, () { context.go('/hr'); }, isMobile),
      _quickButton(context, 'Finance', Icons.account_balance, () { context.go('/finance'); }, isMobile),
      _quickButton(context, 'Reporting', Icons.insights, () { context.go('/reporting'); }, isMobile),
    ];

    if (isMobile) {
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < managementButtons.length; i++) ...[
              if (i > 0) SizedBox(width: isMobile ? 6 : 8),
              managementButtons[i],
            ],
          ],
        ),
      );
    }
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: managementButtons,
    );
  }

  Widget _quickButton(BuildContext context, String label, IconData icon, VoidCallback onTap, [bool isMobile = false]) {
    final padding = isMobile ? const EdgeInsets.symmetric(horizontal: 8, vertical: 8) : const EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final iconSpacing = isMobile ? 6.0 : 8.0;
    final fontSize = isMobile ? 12.0 : null;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: padding,
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
            Icon(icon, color: Colors.green[700], size: isMobile ? 18 : null),
            SizedBox(width: iconSpacing),
            Text(label, style: TextStyle(color: Colors.grey[800], fontSize: fontSize)),
          ],
        ),
      ),
    );
  }

  DateTimeRange _currentRange() {
    final now = DateTime.now();
    
    // Business day starts at 5:00 AM, not midnight
    // If current time is before 5 AM, "today" is from 5 AM yesterday to 4:59:59 AM today
    // If current time is 5 AM or later, "today" is from 5 AM today to 4:59:59 AM tomorrow
    DateTime getBusinessDayStart(DateTime date) {
      if (date.hour < 5) {
        // Before 5 AM, business day started yesterday at 5 AM
        final yesterday = date.subtract(const Duration(days: 1));
        return DateTime(yesterday.year, yesterday.month, yesterday.day, 5, 0, 0);
      } else {
        // 5 AM or later, business day started today at 5 AM
        return DateTime(date.year, date.month, date.day, 5, 0, 0);
      }
    }
    
    DateTime getBusinessDayEnd(DateTime date) {
      if (date.hour < 5) {
        // Before 5 AM, business day ends today at 4:59:59 AM
        return DateTime(date.year, date.month, date.day, 4, 59, 59, 999);
      } else {
        // 5 AM or later, business day ends tomorrow at 4:59:59 AM
        final tomorrow = date.add(const Duration(days: 1));
        return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, 4, 59, 59, 999);
      }
    }
    
    switch (_timeRange) {
      case TimeRange.today:
        // Today: from 5 AM (business day start) to 4:59:59 AM next day
        final start = getBusinessDayStart(now);
        final end = getBusinessDayEnd(now);
        return DateTimeRange(start: start, end: end);
      case TimeRange.week:
        // This week: from 5 AM of Monday (or 7 days ago if before 5 AM) to end of current business day
        final weekStart = now.subtract(Duration(days: now.weekday - 1));
        final businessWeekStart = getBusinessDayStart(weekStart);
        final businessWeekEnd = getBusinessDayEnd(now);
        return DateTimeRange(start: businessWeekStart, end: businessWeekEnd);
      case TimeRange.month:
        // This month: from 5 AM of first day of month to end of current business day
        final monthStart = DateTime(now.year, now.month, 1);
        final businessMonthStart = getBusinessDayStart(monthStart);
        final businessMonthEnd = getBusinessDayEnd(now);
        return DateTimeRange(start: businessMonthStart, end: businessMonthEnd);
      case TimeRange.custom:
        return _customRange ?? DateTimeRange(start: DateTime(now.year, now.month, 1), end: now);
    }
  }

  bool _isInRange(DateTime date) {
    final r = _currentRange();
    // Compare full datetime (including time) to respect 5 AM business day boundary
    // Business day: 5:00 AM to 4:59:59.999 AM next calendar day
    // Transaction at 4:59 AM belongs to previous business day
    // Transaction at 5:00 AM belongs to current business day
    return (date.isAfter(r.start) || date.isAtSameMomentAs(r.start)) 
        && (date.isBefore(r.end) || date.isAtSameMomentAs(r.end));
  }
  
  // Helper to parse timestamp from various formats
  DateTime? _parseTimestamp(dynamic timestamp) {
    if (timestamp == null) return null;
    
    try {
      final str = timestamp.toString().trim();
      if (str.isEmpty) return null;
      
      // Try ISO 8601 format first
      if (str.contains('T') || str.contains('Z')) {
        return DateTime.parse(str);
      }
      
      // Try space-separated format (replace space with T)
      if (str.contains(' ')) {
        final normalized = str.replaceFirst(' ', 'T');
        return DateTime.parse(normalized);
      }
      
      // Try date-only format
      if (str.length == 10 && str.contains('-')) {
        return DateTime.parse(str);
      }
      
      // Try parsing as-is
      return DateTime.parse(str);
    } catch (e, stack) {
      if (kDebugMode) debugPrint('DEBUG _parseTimestamp: $e\n$stack');
      return null;
    }
  }

  // Aggregate for owner/manager
  Widget _buildManagementAggregate(BuildContext context) {
    // Removed - no longer needed as we only show department sales cards
    return const SizedBox.shrink();
  }

  Widget _buildPendingDirectSuppliesCard() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pending Direct Supply Approvals',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ..._pendingDirectSupplies.map((req) {
              final itemName = (req['stock_items']?['name'] as String?) ?? 'Unknown Item';
              final qty = req['quantity']?.toString() ?? '0';
              final bar = req['bar'] == 'vip_bar' ? 'VIP Bar' : 'Outside Bar';
              final requester = (req['requested_by_profile']?['full_name'] as String?) ?? 'Unknown';
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text('$itemName x$qty'),
                  subtitle: Text('Bar: $bar • Requested by $requester'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.check_circle, color: Colors.green),
                        onPressed: () => _handleApproveDirectSupply(req['id'] as String, true),
                      ),
                      IconButton(
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        onPressed: () => _handleApproveDirectSupply(req['id'] as String, false),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _handleApproveDirectSupply(String requestId, bool approve) async {
    try {
      await _dataService.approveDirectSupplyRequest(
        requestId: requestId,
        approve: approve,
        notes: approve ? 'Approved' : 'Denied',
      );
      await _loadData();
      if (mounted) {
        ErrorHandler.showSuccessMessage(
          context,
          approve ? 'Direct supply approved' : 'Direct supply denied',
        );
      }
    } catch (e, stackTrace) {
      if (kDebugMode) debugPrint('DEBUG supply request: $e\n$stackTrace');
      if (mounted) {
        ErrorHandler.handleError(
          context,
          e,
          customMessage: 'Failed to update direct supply request.',
          stackTrace: stackTrace,
        );
      }
    }
  }

  Widget _buildStockLevelsSummary() {
    if (_stockLevels.isEmpty) {
      return const SizedBox.shrink();
    }

    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final item in _stockLevels) {
      final location = item['location_name']?.toString() ?? 'Unknown';
      grouped.putIfAbsent(location, () => []).add(item);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Department Stock Overview',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: () {
                    // Navigate to inventory screen for detailed view
                    context.go('/inventory');
                  },
                  icon: const Icon(Icons.visibility, size: 16),
                  label: const Text('View Details'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: grouped.entries.map((entry) {
                final location = entry.key;
                final items = entry.value;
                
                // Calculate aggregates
                final totalItems = items.length;
                final lowStockItems = items.where((item) {
                  final stock = (item['current_stock'] as num?) ?? 0;
                  return stock < 20; // Low stock threshold
                }).length;
                final outOfStockItems = items.where((item) {
                  final stock = (item['current_stock'] as num?) ?? 0;
                  return stock <= 0;
                }).length;
                final totalStockValue = items.fold<num>(0, (sum, item) {
                  final stock = (item['current_stock'] as num?) ?? 0;
                  final price = (item['price'] as num?) ?? 0;
                  return sum + (stock * price);
                });
                
                return Container(
                  width: 280,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey[200]!),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        location,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Total Items',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  '$totalItems',
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Low Stock',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey[600],
                                  ),
                                ),
                                Text(
                                  '$lowStockItems',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    color: lowStockItems > 0 ? Colors.orange[700] : Colors.green[700],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      if (outOfStockItems > 0) ...[
                        const SizedBox(height: 4),
                        Text(
                          '$outOfStockItems out of stock',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red[700],
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  // Accountant extra insights
  Widget _buildAccountantInsights(BuildContext context) {
    final r = _currentRange();
    int countInRange(List<Map<String, dynamic>> list, String dateKey) {
      return list.where((e) {
        final d = _parseTimestamp(e[dateKey]);
        return d != null && _isInRange(d);
      }).length;
    }

    final depositsInRange = countInRange(_cashDeposits, 'date');
    final payrollInRange = _payrollRecords.where((p) {
      final month = p['month']?.toString() ?? '';
      return month.startsWith('${r.start.year}-${r.start.month.toString().padLeft(2, '0')}');
    }).length;

    return _inlineCards(context, MediaQuery.sizeOf(context).width, [
      ('Cash Deposits', '$depositsInRange', Icons.savings),
      ('Payroll Runs', '$payrollInRange', Icons.payments),
    ]);
  }

  // Receptionist personal metrics
  Widget _buildReceptionistPanel(BuildContext context, double screenWidth) {
    // Using bookings as proxy for processed rooms in range
    final processed = _bookings.where((b) {
      final ci = _parseTimestamp(b['check_in'] ?? b['check_in_date']);
      return ci != null && _isInRange(ci);
    }).length;
    return _inlineCards(context, screenWidth, [
      ('Rooms Processed', '$processed', Icons.meeting_room),
    ]);
  }

  // Bartender metrics (sales from stock transactions; schema: transaction_type, created_at, quantity)
  Widget _buildBartenderPanel(BuildContext context, double screenWidth) {
    final sales = _stockTransactions.where((t) {
      final ts = _parseTimestamp(t['created_at'] ?? t['timestamp']);
      return (t['transaction_type']?.toString() == 'Sale') && ts != null && _isInRange(ts);
    }).toList();
    final qty = sales.fold<int>(0, (s, e) => s + ((e['quantity'] as num?)?.abs().toInt() ?? 0));
    return _inlineCards(context, screenWidth, [
      ('Sales', '${sales.length}', Icons.local_bar),
      ('Units Sold', '$qty', Icons.point_of_sale),
    ]);
  }

  // Kitchen metrics
  Widget _buildKitchenPanel(BuildContext context, double screenWidth) {
    // Proxy using income records from vip/outside bar as dispatched
    final inRange = _incomeRecords.where((e) {
      final d = _parseTimestamp(e['date']);
      final dept = e['department']?.toString() ?? '';
      final isBar = dept == 'vip_bar' || dept == 'outside_bar';
      return d != null && _isInRange(d) && isBar;
    }).toList();
    final total = inRange.fold<num>(0, (s, e) => s + (e['amount'] as num));
    return _inlineCards(context, screenWidth, [
      ('Food Dispatched', '${inRange.length}', Icons.restaurant),
      ('Value', '₦${_formatKobo(total)}', Icons.attach_money),
    ]);
  }

  // Storekeeper metrics (schema: created_at)
  Widget _buildStorekeeperPanel(BuildContext context, double screenWidth) {
    final movements = _stockTransactions.where((t) {
      final ts = _parseTimestamp(t['created_at'] ?? t['timestamp']);
      return ts != null && _isInRange(ts);
    }).length;
    return _inlineCards(context, screenWidth, [
      ('Stock Movements', '$movements', Icons.inventory_2),
    ]);
  }

  // Purchaser metrics
  Widget _buildPurchaserPanel(BuildContext context, double screenWidth) {
    final kitchenExpenses = _expenseRecords.where((e) {
      final d = _parseTimestamp(e['date']);
      return d != null && _isInRange(d) && (e['department'] == 'kitchen');
    }).toList();
    final total = kitchenExpenses.fold<num>(0, (s, e) => s + (e['amount'] as num));
    return _inlineCards(context, screenWidth, [
      ('Kitchen Purchases', '₦${_formatKobo(total)}', Icons.shopping_cart),
    ]);
  }

  Widget _inlineCards(BuildContext context, double screenWidth, List<(String, String, IconData)> items) {
    final crossAxisCount = _getCrossAxisCount(screenWidth);
    final padding = screenWidth < 600 ? 16.0 : 24.0;
    final spacing = 12.0;
    final cardWidth = (screenWidth - (padding * 2) - (spacing * (crossAxisCount - 1))) / crossAxisCount;
    
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
        childAspectRatio: cardWidth / 120, // Adjust height based on card width
      ),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final (title, value, icon) = items[index];
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
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
              Flexible(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: const Color(0xFF0A0A0A)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: const Color(0xFF666666)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        );
      },
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