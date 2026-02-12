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
  // Unified: Room Bookings + Mini Mart + Kitchen/Restaurant + Bar Sales
  // Expenses: Inventory Restocking + Staff Payroll + General Maintenance + Utility bills
  Future<PLData> getProfitAndLoss({
    required TimePeriod period,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    try {
      final now = DateTime.now();
      final dateRange = _getDateRange(period, now, customStart, customEnd);
      final startStr = dateRange.start.toIso8601String().split('T')[0];
      final endStr = dateRange.end.toIso8601String().split('T')[0];

      // 1. Room Bookings (checked-out)
      final revenueResponse = await _supabase
          .from('bookings')
          .select('''
            id, total_amount, paid_amount, extra_charges, status,
            rooms!inner(type)
          ''')
          .inFilter('status', ['Checked-out', 'checked_out', 'checked-out', 'Checked out', 'checked out'])
          .gte('check_out_date', dateRange.start.toIso8601String())
          .lte('check_out_date', dateRange.end.toIso8601String());
      final revenueItemsRaw = revenueResponse as List<Map<String, dynamic>>;
      final revenueItems = revenueItemsRaw
          .where((b) => _normalizeBookingStatus(b['status']?.toString()) == 'checked-out')
          .toList();

      // 2. Department revenue: Mini Mart, Kitchen/Restaurant, VIP Bar, Outside Bar, Reception
      // Primary: department_sales (aligned with dashboard). Fallback: income_records, mini_mart_sales, kitchen_sales
      int miniMartSales = 0;
      int kitchenSales = 0;
      int vipBarSales = 0;
      int outsideBarSales = 0;
      int receptionSales = 0;

      try {
        final deptResp = await _supabase
            .from('department_sales')
            .select('department, total_sales')
            .inFilter('department', ['vip_bar', 'outside_bar', 'mini_mart', 'restaurant', 'reception'])
            .gte('date', startStr)
            .lte('date', endStr);
        for (final r in deptResp as List) {
          final dept = r['department']?.toString() ?? '';
          final amt = (r['total_sales'] as num?)?.toInt() ?? 0;
          if (dept == 'vip_bar') vipBarSales += amt;
          else if (dept == 'outside_bar') outsideBarSales += amt;
          else if (dept == 'mini_mart') miniMartSales += amt;
          else if (dept == 'restaurant') kitchenSales += amt;
          else if (dept == 'reception') receptionSales += amt;
        }
      } catch (_) {}

      if (miniMartSales == 0) {
        try {
          final mmResp = await _supabase
              .from('mini_mart_sales')
              .select('total_amount')
              .gte('sale_date', startStr)
              .lte('sale_date', endStr);
          miniMartSales = (mmResp as List).fold<int>(0, (s, r) => s + ((r['total_amount'] as num?)?.toInt() ?? 0));
        } catch (_) {}
      }
      if (kitchenSales == 0) {
        try {
          final kResp = await _supabase
              .from('kitchen_sales')
              .select('total_amount')
              .gte('created_at', dateRange.start.toIso8601String())
              .lte('created_at', dateRange.end.toIso8601String());
          kitchenSales = (kResp as List).fold<int>(0, (s, r) => s + ((r['total_amount'] as num?)?.toInt() ?? 0));
        } catch (_) {}
      }
      if (vipBarSales == 0 && outsideBarSales == 0) {
        try {
          final incResp = await _supabase
              .from('income_records')
              .select('department, amount')
              .gte('date', startStr)
              .lte('date', endStr);
          for (final r in incResp as List) {
            final dept = (r['department']?.toString() ?? '').toLowerCase();
            var amt = (r['amount'] as num?)?.toInt() ?? 0;
            if (amt == 0) amt = (r['amount'] as num?)?.toDouble()?.round() ?? 0;
            if (amt > 0 && amt < 100000) amt = amt * 100;
            if (dept == 'vip_bar') vipBarSales += amt;
            else if (dept == 'outside_bar') outsideBarSales += amt;
            else if (dept == 'mini_mart') miniMartSales += amt;
            else if (dept == 'restaurant' || dept == 'kitchen') kitchenSales += amt;
            else if (dept == 'reception') receptionSales += amt;
          }
        } catch (_) {}
      }

      // 5. Expenses
      final expenseResponse = await _supabase
          .from('expenses')
          .select('*')
          .gte('transaction_date', startStr)
          .lte('transaction_date', endStr);
      final expenseItems = expenseResponse as List<Map<String, dynamic>>;

      // 6. Payroll
      final payrollResponse = await _supabase
          .from('payroll_records')
          .select('amount')
          .gte('month', startStr)
          .lte('month', endStr);
      final payrollTotal = (payrollResponse as List).fold<int>(0, (s, r) => s + ((r['amount'] as num?)?.toInt() ?? 0));

      // 7. Load room type prices for breakdown
      if (_roomTypePrices == null || _roomTypeCacheTime == null ||
          DateTime.now().difference(_roomTypeCacheTime!).inMinutes > _cacheExpiryMinutes) {
        await _loadRoomTypePrices();
      }

      // 8. Room revenue from bookings
      int roomRevenueTotal = revenueItems.fold<int>(0, (sum, booking) {
        final totalAmount = (booking['total_amount'] as num?)?.toInt();
        final paidAmount = (booking['paid_amount'] as num?)?.toInt() ?? 0;
        final extras = ((booking['extra_charges'] ?? []) as List).fold<int>(0, (s, c) => s + ((c['price'] ?? 0) as int));
        final baseTotal = totalAmount ?? paidAmount;
        final normalizedTotal = baseTotal >= extras ? baseTotal : baseTotal + extras;
        return sum + normalizedTotal;
      });

      final totalRevenue = roomRevenueTotal + miniMartSales + kitchenSales + vipBarSales + outsideBarSales + receptionSales;
      var totalExpenses = expenseItems.fold<int>(0, (s, e) => s + ((e['amount'] ?? 0) as int)) + payrollTotal;

      // 9. Revenue breakdown (always include all categories, use ₦0 if zero)
      final revenueBreakdown = _generateUnifiedRevenueBreakdown(
        revenueItems,
        miniMartSales,
        kitchenSales,
        vipBarSales,
        outsideBarSales,
        receptionSales,
      );

      // 10. Inventory restocking (purchase orders) and maintenance
      int inventoryRestocking = 0;
      int maintenanceTotal = 0;
      try {
        final poResp = await _supabase
            .from('purchase_orders')
            .select('purchase_order_items(quantity, unit_price), total_cost')
            .gte('created_at', dateRange.start.toIso8601String())
            .lte('created_at', dateRange.end.toIso8601String());
        for (final po in poResp as List) {
          final items = po['purchase_order_items'] as List?;
          if (items != null && items.isNotEmpty) {
            for (final it in items) {
              inventoryRestocking += ((it['quantity'] as num?) ?? 0).toInt() * ((it['unit_price'] as num?) ?? 0).toInt();
            }
          } else {
            inventoryRestocking += ((po['total_cost'] as num?) ?? 0).toInt();
          }
        }
      } catch (_) {}
      try {
        final mwoResp = await _supabase
            .from('maintenance_work_orders')
            .select('actual_cost')
            .eq('status', 'Completed')
            .gte('created_at', dateRange.start.toIso8601String())
            .lte('created_at', dateRange.end.toIso8601String());
        maintenanceTotal = (mwoResp as List).fold<int>(0, (s, r) => s + ((r['actual_cost'] as num?)?.toInt() ?? 0));
      } catch (_) {}

      final totalExpensesWithExtras = totalExpenses + inventoryRestocking + maintenanceTotal;

      // 11. Expense breakdown (always include standard categories, use ₦0 if zero)
      final expenseBreakdown = _generateUnifiedExpenseBreakdown(
        expenseItems,
        payrollTotal,
        inventoryRestocking,
        maintenanceTotal,
      );

      return PLData(
        totalRevenue: totalRevenue,
        totalExpenses: totalExpensesWithExtras,
        netProfit: totalRevenue - totalExpensesWithExtras,
        revenueItems: revenueItems,
        expenseItems: expenseItems,
        revenueBreakdown: revenueBreakdown,
        expenseBreakdown: expenseBreakdown,
      );
    } catch (e) {
      rethrow;
    }
  }

  List<CategoryAmount> _generateUnifiedRevenueBreakdown(
    List<Map<String, dynamic>> revenueItems,
    int miniMartSales,
    int kitchenSales,
    int vipBarSales,
    int outsideBarSales,
    int receptionSales,
  ) {
    final breakdown = <String, int>{};

    // Room bookings by type
    for (var booking in revenueItems) {
      final rooms = booking['rooms'];
      String roomType = 'Standard Room';
      if (rooms is Map && rooms['type'] != null) {
        roomType = rooms['type'] as String;
      } else if (rooms is List && rooms.isNotEmpty && rooms.first is Map) {
        roomType = (rooms.first as Map)['type'] as String? ?? roomType;
      }
      final totalAmount = (booking['total_amount'] as num?)?.toInt();
      final paidAmount = (booking['paid_amount'] as num?)?.toInt() ?? 0;
      final extras = ((booking['extra_charges'] ?? []) as List).fold<int>(0, (s, c) => s + ((c['price'] ?? 0) as int));
      final baseTotal = totalAmount ?? paidAmount;
      final roomRevenue = baseTotal >= extras ? baseTotal - extras : baseTotal;
      breakdown[roomType] = (breakdown[roomType] ?? 0) + roomRevenue;
    }

    // Add fixed revenue categories (always show, even if zero - data safety)
    breakdown['Mini Mart'] = miniMartSales;
    breakdown['Kitchen/Restaurant'] = kitchenSales;
    breakdown['VIP Bar'] = vipBarSales;
    breakdown['Outside Bar'] = outsideBarSales;
    breakdown['Reception'] = receptionSales;

    const deptOrder = [
      'Mini Mart',
      'Kitchen/Restaurant',
      'VIP Bar',
      'Outside Bar',
      'Reception',
    ];
    final result = <CategoryAmount>[];
    final roomEntries = breakdown.entries.where((e) => !deptOrder.contains(e.key)).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in roomEntries) {
      result.add(CategoryAmount(category: e.key, amount: e.value));
    }
    for (final cat in deptOrder) {
      result.add(CategoryAmount(category: cat, amount: breakdown[cat] ?? 0));
    }
    return result;
  }

  List<CategoryAmount> _generateUnifiedExpenseBreakdown(
    List<Map<String, dynamic>> expenseItems,
    int payrollTotal,
    int inventoryRestockingFromPO,
    int maintenanceFromMWO,
  ) {
    const standardCategories = [
      'Inventory Restocking',
      'Staff Payroll',
      'General Maintenance',
      'Utility bills',
    ];
    final breakdown = <String, int>{};
    for (final cat in standardCategories) {
      breakdown[cat] = 0;
    }
    breakdown['Other'] = 0;

    breakdown['Inventory Restocking'] = inventoryRestockingFromPO;
    breakdown['General Maintenance'] = maintenanceFromMWO;

    // Map expense category/department to standard categories
    for (var expense in expenseItems) {
      final category = (expense['category'] as String?)?.toLowerCase() ?? '';
      final department = (expense['department'] as String?)?.toLowerCase() ?? '';
      final amount = (expense['amount'] ?? 0) as int;

      if (category.contains('inventory') || category.contains('restock') ||
          department.contains('storekeeping') || department.contains('purchasing')) {
        breakdown['Inventory Restocking'] = (breakdown['Inventory Restocking'] ?? 0) + amount;
      } else if (category.contains('payroll') || category.contains('salary') || department.contains('hr')) {
        breakdown['Staff Payroll'] = (breakdown['Staff Payroll'] ?? 0) + amount;
      } else if (category.contains('maintenance') || category.contains('repair')) {
        breakdown['General Maintenance'] = (breakdown['General Maintenance'] ?? 0) + amount;
      } else if (category.contains('utility') || category.contains('electric') || category.contains('water')) {
        breakdown['Utility bills'] = (breakdown['Utility bills'] ?? 0) + amount;
      } else {
        breakdown['Other'] = (breakdown['Other'] ?? 0) + amount;
      }
    }
    breakdown['Staff Payroll'] = (breakdown['Staff Payroll'] ?? 0) + payrollTotal;

    const allCategories = [
      'Inventory Restocking',
      'Staff Payroll',
      'General Maintenance',
      'Utility bills',
      'Other',
    ];
    return allCategories.map((cat) => CategoryAmount(
      category: cat,
      amount: breakdown[cat] ?? 0,
    )).toList();
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