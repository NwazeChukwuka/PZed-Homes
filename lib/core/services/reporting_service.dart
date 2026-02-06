import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/data/models/room.dart';
import 'package:pzed_homes/data/models/menu_item.dart';

// Time filters - now includes yearly and custom
enum TimePeriod { today, thisWeek, thisMonth, lastMonth, yearly, custom }

// Existing class for operational reports (keep this for backward compatibility)
class ReportData {
  final int totalRevenue;
  final double occupancyRate;
  final int restaurantSales;
  final int barSales;

  ReportData({
    required this.totalRevenue,
    required this.occupancyRate,
    required this.restaurantSales,
    required this.barSales,
  });
}

// New enhanced class for P&L data with detailed items
class PLData {
  final int totalRevenue;
  final int totalExpenses;
  final int netProfit;
  final List<Map<String, dynamic>> revenueItems; // Detailed booking data
  final List<Map<String, dynamic>> expenseItems; // Detailed expense data
  final List<CategoryAmount> revenueBreakdown;
  final List<CategoryAmount> expenseBreakdown;

  PLData({
    required this.totalRevenue,
    required this.totalExpenses,
    required this.netProfit,
    required this.revenueItems,
    required this.expenseItems,
    required this.revenueBreakdown,
    required this.expenseBreakdown,
  });
}

// Category amount class for breakdown data
class CategoryAmount {
  final String category;
  final int amount;

  CategoryAmount({
    required this.category,
    required this.amount,
  });
}

class ReportingService {
  final _supabase = Supabase.instance.client;
  
  // Cache for room types to avoid repeated queries
  Map<String, int>? _roomTypePrices;
  DateTime? _roomTypeCacheTime;
  static const _cacheExpiryMinutes = 5;

  // --- Keep existing methods for backward compatibility ---
  ReportData generateReport(
    TimePeriod period, {
    required List<Map<String, dynamic>> bookings,
    required List<Room> rooms,
    required List<MenuItem> menuItems,
  }) {
    final now = DateTime.now();
    final filteredBookings = _filterBookingsByPeriod(period, now, bookings);

    final revenue = _calculateTotalRevenue(filteredBookings);
    final sales = _calculateSalesByDepartment(filteredBookings, menuItems);

    return ReportData(
      totalRevenue: revenue,
      occupancyRate: _calculateCurrentOccupancy(rooms),
      restaurantSales: sales['Restaurant'] ?? 0,
      barSales: sales['Bar'] ?? 0,
    );
  }

  List<Map<String, dynamic>> _filterBookingsByPeriod(
    TimePeriod period,
    DateTime now,
    List<Map<String, dynamic>> bookings,
  ) {
    DateTime startDate;
    switch (period) {
      case TimePeriod.today:
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case TimePeriod.thisWeek:
        startDate = now.subtract(Duration(days: now.weekday - 1));
        break;
      case TimePeriod.thisMonth:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case TimePeriod.lastMonth:
        final lastMonth = now.month == 1 ? 12 : now.month - 1;
        final lastYear = now.month == 1 ? now.year - 1 : now.year;
        startDate = DateTime(lastYear, lastMonth, 1);
        break;
      case TimePeriod.yearly:
        startDate = DateTime(now.year, 1, 1);
        break;
      case TimePeriod.custom:
        startDate = now.subtract(const Duration(days: 30)); // Default 30 days for custom
        break;
    }

    return bookings.where((b) {
      final normalized = _normalizeBookingStatus(b['status']?.toString());
      if (normalized != 'checked-out') return false;
      final checkOutDate = DateTime.parse(b['checkOutDate'] as String);
      return checkOutDate.isAfter(startDate) &&
          checkOutDate.isBefore(now.add(const Duration(days: 1)));
    }).toList();
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

  int _calculateTotalRevenue(List<Map<String, dynamic>> filteredBookings) {
    // This method is used in the old generateReport method
    // For backward compatibility, we'll use a synchronous approach
    // but it requires room prices to be pre-loaded
    return filteredBookings.fold(0, (total, booking) {
      final roomType = booking['roomType'] as String;
      // Try to get price from cache, otherwise use 0
      final roomPrice = _roomTypePrices?[roomType] ?? 0;

      final extras = (booking['extraCharges'] as List)
          .fold<int>(0, (sum, charge) => sum + (charge['price'] as int));

      return total + roomPrice + extras;
    });
  }

  double _calculateCurrentOccupancy(List<Room> rooms) {
    final occupiedCount = rooms.where((r) => r.status == 'Occupied').length;
    return rooms.isEmpty ? 0 : (occupiedCount / rooms.length) * 100;
  }

  Map<String, int> _calculateSalesByDepartment(
    List<Map<String, dynamic>> filteredBookings,
    List<MenuItem> menuItems,
  ) {
    final sales = {'Restaurant': 0, 'Bar': 0};
    for (var booking in filteredBookings) {
      for (var charge in (booking['extraCharges'] as List)) {
        try {
          final menuItem =
              menuItems.firstWhere((item) => item.name == charge['item']);
          if (sales.containsKey(menuItem.department)) {
            sales[menuItem.department] =
                sales[menuItem.department]! + (charge['price'] as int);
          }
        } catch (_) {
          // Item not in menu, ignore
        }
      }
    }
    return sales;
  }

  // --- New Enhanced Profit & Loss Reporting with Supabase ---
  Future<PLData> getProfitAndLoss({
    required TimePeriod period,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    try {
      final now = DateTime.now();
      final dateRange = _getDateRange(period, now, customStart, customEnd);

      // 1. Fetch detailed revenue items (bookings)
      final revenueResponse = await _supabase
          .from('bookings')
          .select('''
            id,
            created_at,
            guest_profile_id,
            room_id,
            requested_room_type,
            check_in_date,
            check_out_date,
            status,
            total_amount,
            paid_amount,
            extra_charges,
            notes,
            created_by,
            updated_at,
            payment_method,
            guest_name,
            guest_email,
            guest_phone,
            rooms!inner(type),
            profiles!guest_profile_id(full_name)
          ''')
          .inFilter('status', ['Checked-out', 'checked_out', 'checked-out', 'Checked out', 'checked out'])
          .gte('check_out_date', dateRange.start.toIso8601String())
          .lte('check_out_date', dateRange.end.toIso8601String());

      final revenueItemsRaw = revenueResponse as List<Map<String, dynamic>>;
      final revenueItems = revenueItemsRaw
          .where((b) => _normalizeBookingStatus(b['status']?.toString()) == 'checked-out')
          .toList();

      // 2. Fetch detailed expense items
      final expenseResponse = await _supabase
          .from('expenses')
          .select('*')
          .gte('transaction_date', dateRange.start.toIso8601String())
          .lte('transaction_date', dateRange.end.toIso8601String());

      final expenseItems = expenseResponse as List<Map<String, dynamic>>;

      // 3. Load room type prices if not cached
      if (_roomTypePrices == null || 
          _roomTypeCacheTime == null ||
          DateTime.now().difference(_roomTypeCacheTime!).inMinutes > _cacheExpiryMinutes) {
        await _loadRoomTypePrices();
      }
      
      // 4. Calculate totals from actual booking totals
      final totalRevenue = revenueItems.fold<int>(0, (sum, booking) {
        final totalAmount = (booking['total_amount'] as num?)?.toInt();
        final paidAmount = (booking['paid_amount'] as num?)?.toInt() ?? 0;
        final extras = ((booking['extra_charges'] ?? []) as List)
            .fold<int>(0, (s, c) => s + ((c['price'] ?? 0) as int));
        final baseTotal = totalAmount ?? paidAmount;
        final normalizedTotal = baseTotal >= extras ? baseTotal : baseTotal + extras;
        return sum + normalizedTotal;
      });

      final totalExpenses = expenseItems.fold<int>(
        0,
        (sum, expense) => sum + ((expense['amount'] ?? 0) as int),
      );

      // Generate breakdown data (room prices are already loaded)
      final revenueBreakdown = _generateRevenueBreakdown(revenueItems);
      final expenseBreakdown = _generateExpenseBreakdown(expenseItems);

      return PLData(
        totalRevenue: totalRevenue,
        totalExpenses: totalExpenses,
        netProfit: totalRevenue - totalExpenses,
        revenueItems: revenueItems,
        expenseItems: expenseItems,
        revenueBreakdown: revenueBreakdown,
        expenseBreakdown: expenseBreakdown,
      );
    } catch (e) {
      rethrow;
    }
  }

  List<CategoryAmount> _generateRevenueBreakdown(List<Map<String, dynamic>> revenueItems) {
    final breakdown = <String, int>{};
    
    // Room prices should already be loaded by the caller
    // If not, use 0 as fallback
    for (var booking in revenueItems) {
      final roomType = booking['rooms']['type'] as String;
      final totalAmount = (booking['total_amount'] as num?)?.toInt();
      final paidAmount = (booking['paid_amount'] as num?)?.toInt() ?? 0;
      final extras = ((booking['extra_charges'] ?? []) as List);
      final extrasSum = extras.fold<int>(0, (s, c) => s + ((c['price'] ?? 0) as int));
      final baseTotal = totalAmount ?? paidAmount;
      final roomRevenue = baseTotal >= extrasSum ? baseTotal - extrasSum : baseTotal;

      breakdown[roomType] = (breakdown[roomType] ?? 0) + roomRevenue;

      // Add extra charges (if present)
      for (var charge in extras) {
        final item = charge['item'] as String? ?? 'Extra Service';
        breakdown[item] = (breakdown[item] ?? 0) + ((charge['price'] ?? 0) as int);
      }
    }
    
    return breakdown.entries
        .map((e) => CategoryAmount(category: e.key, amount: e.value))
        .toList();
  }

  List<CategoryAmount> _generateExpenseBreakdown(List<Map<String, dynamic>> expenseItems) {
    final breakdown = <String, int>{};
    
    for (var expense in expenseItems) {
      final category = expense['category'] as String? ?? 'Other';
      final amount = (expense['amount'] ?? 0) as int;
      breakdown[category] = (breakdown[category] ?? 0) + amount;
    }
    
    return breakdown.entries
        .map((e) => CategoryAmount(category: e.key, amount: e.value))
        .toList();
  }

  // Helper to get room price from database
  // Fetches and caches room type prices
  Future<int> _getRoomPrice(String roomType) async {
    try {
      // Check if cache is valid
      if (_roomTypePrices == null || 
          _roomTypeCacheTime == null ||
          DateTime.now().difference(_roomTypeCacheTime!).inMinutes > _cacheExpiryMinutes) {
        await _loadRoomTypePrices();
      }
      
      // Return price from cache, default to 0 if not found
      return _roomTypePrices?[roomType] ?? 0;
    } catch (e) {
      return 0;
    }
  }
  
  // Load room type prices from database
  Future<void> _loadRoomTypePrices() async {
    try {
      final response = await _supabase
          .from('room_types')
          .select('type, price');
      
      _roomTypePrices = {};
      for (var row in response) {
        final type = row['type'] as String;
        final price = row['price'] as int;
        // Convert from kobo to naira for display (divide by 100)
        // But keep in kobo for calculations
        _roomTypePrices![type] = price;
      }
      _roomTypeCacheTime = DateTime.now();
    } catch (e) {
      // If loading fails, use empty map
      _roomTypePrices = {};
      _roomTypeCacheTime = DateTime.now();
    }
  }

  // Enhanced date range helper with custom date support
  ({DateTime start, DateTime end}) _getDateRange(
    TimePeriod period,
    DateTime now,
    DateTime? customStart,
    DateTime? customEnd,
  ) {
    // Handle custom date range
    if (period == TimePeriod.custom && customStart != null && customEnd != null) {
      return (
        start: DateTime(customStart.year, customStart.month, customStart.day),
        end: DateTime(customEnd.year, customEnd.month, customEnd.day, 23, 59, 59)
      );
    }

    DateTime startDate;
    DateTime endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);

    switch (period) {
      case TimePeriod.today:
        startDate = DateTime(now.year, now.month, now.day);
        break;
      case TimePeriod.thisWeek:
        startDate = now.subtract(Duration(days: now.weekday - 1));
        break;
      case TimePeriod.thisMonth:
        startDate = DateTime(now.year, now.month, 1);
        break;
      case TimePeriod.lastMonth:
        final lastMonth = now.month == 1 ? 12 : now.month - 1;
        final lastYear = now.month == 1 ? now.year - 1 : now.year;
        startDate = DateTime(lastYear, lastMonth, 1);
        endDate = DateTime(lastYear, lastMonth + 1, 0, 23, 59, 59);
        break;
      case TimePeriod.yearly:
        startDate = DateTime(now.year, 1, 1);
        break;
      case TimePeriod.custom:
        startDate = now.subtract(const Duration(days: 30)); // Fallback
        break;
    }

    return (start: startDate, end: endDate);
  }
}