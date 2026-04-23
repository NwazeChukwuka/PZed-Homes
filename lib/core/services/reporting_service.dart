import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/data/models/room.dart';
import 'package:pzed_homes/data/models/menu_item.dart';

enum TimePeriod { today, thisWeek, thisMonth, lastMonth, last30Days, yearly, custom }

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

class PLData {
  final int totalRevenue;
  final int totalExpenses;
  final int netProfit;
  final List<Map<String, dynamic>> revenueItems; // First page of detail (e.g. 10)
  final List<Map<String, dynamic>> expenseItems; // First page of detail
  final int totalRevenueCount;
  final int totalExpenseCount;
  final List<CategoryAmount> revenueBreakdown;
  final List<CategoryAmount> expenseBreakdown;
  final List<Map<String, dynamic>> payrollPdfRows;

  PLData({
    required this.totalRevenue,
    required this.totalExpenses,
    required this.netProfit,
    required this.revenueItems,
    required this.expenseItems,
    required this.totalRevenueCount,
    required this.totalExpenseCount,
    required this.revenueBreakdown,
    required this.expenseBreakdown,
    required this.payrollPdfRows,
  });
}

class CategoryAmount {
  final String category;
  final int amount;

  CategoryAmount({
    required this.category,
    required this.amount,
  });
}

class _UnifiedRevenueData {
  final List<Map<String, dynamic>> rows;
  final List<Map<String, dynamic>> checkedInBookings;
  final int miniMartSales;
  final int kitchenSales;
  final int vipBarSales;
  final int outsideBarSales;

  const _UnifiedRevenueData({
    required this.rows,
    required this.checkedInBookings,
    required this.miniMartSales,
    required this.kitchenSales,
    required this.vipBarSales,
    required this.outsideBarSales,
  });
}

class ReportingService {
  final _supabase = Supabase.instance.client;
  
  Map<String, int>? _roomTypePrices;
  DateTime? _roomTypeCacheTime;
  static const _cacheExpiryMinutes = 5;

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
      case TimePeriod.last30Days:
        startDate = now.subtract(const Duration(days: 30));
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
      case 'rejected':
        return 'rejected';
      case 'expired':
      case 'no-show':
      case 'no show':
        return 'expired';
      case 'confirmed':
        return 'confirmed';
      default:
        return normalized;
    }
  }

  int _calculateTotalRevenue(List<Map<String, dynamic>> filteredBookings) {
    return filteredBookings.fold(0, (total, booking) {
      final roomType = booking['roomType'] as String;
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
        }
      }
    }
    return sales;
  }

  Future<PLData> getProfitAndLoss({
    required TimePeriod period,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    try {
      await _ensureBookingLifecycleUpToDate();
      final now = DateTime.now();
      final dateRange = _getDateRange(period, now, customStart, customEnd);
      final startStr = dateRange.start.toIso8601String().split('T')[0];
      final endStr = dateRange.end.toIso8601String().split('T')[0];

      final unifiedRevenue = await _buildUnifiedRevenueData(
        start: dateRange.start,
        end: dateRange.end,
      );
      final revenueItems = unifiedRevenue.rows;
      final miniMartSales = unifiedRevenue.miniMartSales;
      final kitchenSales = unifiedRevenue.kitchenSales;
      final vipBarSales = unifiedRevenue.vipBarSales;
      final outsideBarSales = unifiedRevenue.outsideBarSales;

      final expenseResponse = await _supabase
          .from('expenses')
          .select('*')
          .gte('transaction_date', startStr)
          .lte('transaction_date', endStr)
          .order('transaction_date', ascending: false);
      final expenseItems = expenseResponse;

      final payrollResponse = await _supabase
          .from('payroll_records')
          .select('amount')
          .eq('approval_status', 'approved')
          .gte('month', startStr)
          .lte('month', endStr);
      final payrollTotal = (payrollResponse as List).fold<int>(0, (s, r) => s + ((r['amount'] as num?)?.toInt() ?? 0));

      List<Map<String, dynamic>> payrollPdfRows = [];
      try {
        final payrollDetailResp = await _supabase
            .from('payroll_records')
            .select('month, amount, approval_status, rejection_reason, staff:profiles!staff_id(full_name)')
            .gte('month', startStr)
            .lte('month', endStr)
            .order('month', ascending: false)
            .limit(60);
        payrollPdfRows = (payrollDetailResp as List).map((row) {
          final r = Map<String, dynamic>.from(row as Map);
          final staff = r.remove('staff') as Map?;
          r['staff_name'] = staff?['full_name'];
          return r;
        }).toList();
      } catch (_) {}

      if (_roomTypePrices == null || _roomTypeCacheTime == null ||
          DateTime.now().difference(_roomTypeCacheTime!).inMinutes > _cacheExpiryMinutes) {
        await _loadRoomTypePrices();
      }

      final totalRevenue = revenueItems.fold<int>(
        0,
        (sum, row) => sum + ((row['amount'] as num?)?.toInt() ?? 0),
      );

      var totalExpenses = expenseItems.fold<int>(0, (s, e) => s + ((e['amount'] ?? 0) as int)) + payrollTotal;

      final revenueBreakdown = _generateUnifiedRevenueBreakdown(
        unifiedRevenue.checkedInBookings,
        miniMartSales,
        kitchenSales,
        vipBarSales,
        outsideBarSales,
      );

      int inventoryRestocking = 0;
      int maintenanceTotal = 0;
      try {
        final poResp = await _supabase
            .from('purchase_orders')
            .select('purchase_order_items(quantity, unit_cost), total_cost')
            .gte('created_at', dateRange.start.toIso8601String())
            .lte('created_at', dateRange.end.toIso8601String());
        for (final po in poResp as List) {
          final items = po['purchase_order_items'] as List?;
          if (items != null && items.isNotEmpty) {
            for (final it in items) {
              inventoryRestocking += ((it['quantity'] as num?) ?? 0).toInt() * ((it['unit_cost'] as num?) ?? 0).toInt();
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

      final expenseBreakdown = _generateUnifiedExpenseBreakdown(
        expenseItems,
        payrollTotal,
        inventoryRestocking,
        maintenanceTotal,
      );

      const pageSize = 10;
      return PLData(
        totalRevenue: totalRevenue,
        totalExpenses: totalExpensesWithExtras,
        netProfit: totalRevenue - totalExpensesWithExtras,
        revenueItems: revenueItems.take(pageSize).toList(),
        expenseItems: expenseItems.take(pageSize).toList(),
        totalRevenueCount: revenueItems.length,
        totalExpenseCount: expenseItems.length,
        revenueBreakdown: revenueBreakdown,
        expenseBreakdown: expenseBreakdown,
        payrollPdfRows: payrollPdfRows,
      );
    } catch (e) {
      rethrow;
    }
  }

  static const int detailPageSize = 10;

  Future<List<Map<String, dynamic>>> getRevenueItemsPage({
    required TimePeriod period,
    DateTime? customStart,
    DateTime? customEnd,
    int offset = 0,
    int limit = detailPageSize,
  }) async {
    final now = DateTime.now();
    final dateRange = _getDateRange(period, now, customStart, customEnd);
    final unifiedRevenue = await _buildUnifiedRevenueData(
      start: dateRange.start,
      end: dateRange.end,
    );
    if (offset >= unifiedRevenue.rows.length) return [];
    final endIndex = (offset + limit) > unifiedRevenue.rows.length
        ? unifiedRevenue.rows.length
        : (offset + limit);
    return unifiedRevenue.rows.sublist(offset, endIndex);
  }

  Future<List<Map<String, dynamic>>> getExpenseItemsPage({
    required TimePeriod period,
    DateTime? customStart,
    DateTime? customEnd,
    int offset = 0,
    int limit = detailPageSize,
  }) async {
    final now = DateTime.now();
    final dateRange = _getDateRange(period, now, customStart, customEnd);
    final startStr = dateRange.start.toIso8601String().split('T')[0];
    final endStr = dateRange.end.toIso8601String().split('T')[0];
    final response = await _supabase
        .from('expenses')
        .select('*')
        .gte('transaction_date', startStr)
        .lte('transaction_date', endStr)
        .order('transaction_date', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(response as List);
  }

  static const _roomTypes = [
    'Standard Room',
    'Classic Room',
    'Diplomatic Room',
    'Deluxe Room',
    'Executive Room',
  ];

  String _normalizeRoomType(String? raw) {
    if (raw == null || raw.trim().isEmpty) return 'Standard Room';
    final s = raw.trim();
    for (final rt in _roomTypes) {
      if (s.toLowerCase() == rt.toLowerCase()) return rt;
    }
    final lower = s.toLowerCase();
    if (lower.contains('standard')) return 'Standard Room';
    if (lower.contains('classic')) return 'Classic Room';
    if (lower.contains('diplomatic')) return 'Diplomatic Room';
    if (lower.contains('deluxe')) return 'Deluxe Room';
    if (lower.contains('executive')) return 'Executive Room';
    return s; // Unknown type - will go to "Other Room Types"
  }

  List<CategoryAmount> _generateUnifiedRevenueBreakdown(
    List<Map<String, dynamic>> checkedInBookings,
    int miniMartSales,
    int kitchenSales,
    int vipBarSales,
    int outsideBarSales,
  ) {
    final roomRevenue = <String, int>{};
    for (final rt in _roomTypes) {
      roomRevenue[rt] = 0;
    }
    int otherRoomRevenue = 0;

    for (var booking in checkedInBookings) {
      String rawType = 'Standard Room';
      final rooms = booking['rooms'];
      if (rooms is Map && rooms['type'] != null) {
        rawType = rooms['type'] as String;
      } else if (rooms is List && rooms.isNotEmpty && rooms.first is Map) {
        rawType = (rooms.first as Map)['type'] as String? ?? rawType;
      } else {
        rawType = booking['requested_room_type']?.toString() ?? rawType;
      }
      final totalAmount = (booking['total_amount'] as num?)?.toInt();
      final paidAmount = (booking['paid_amount'] as num?)?.toInt();
      final extras = ((booking['extra_charges'] ?? []) as List).fold<int>(0, (s, c) => s + ((c['price'] ?? 0) as int));
      final baseTotal = _collectedAmountKobo(totalAmount, paidAmount);
      final rev = baseTotal >= extras ? baseTotal - extras : baseTotal;
      final normalized = _normalizeRoomType(rawType);
      if (_roomTypes.contains(normalized)) {
        roomRevenue[normalized] = (roomRevenue[normalized] ?? 0) + rev;
      } else {
        otherRoomRevenue += rev;
      }
    }

    final result = <CategoryAmount>[];
    for (final rt in _roomTypes) {
      result.add(CategoryAmount(category: rt, amount: roomRevenue[rt] ?? 0));
    }
    if (otherRoomRevenue > 0) {
      result.add(CategoryAmount(category: 'Other Room Types', amount: otherRoomRevenue));
    }
    result.add(CategoryAmount(category: 'Mini Mart', amount: miniMartSales));
    result.add(CategoryAmount(category: 'Kitchen/Restaurant', amount: kitchenSales));
    result.add(CategoryAmount(category: 'VIP Bar', amount: vipBarSales));
    result.add(CategoryAmount(category: 'Outside Bar', amount: outsideBarSales));
    return result;
  }

  Future<_UnifiedRevenueData> _buildUnifiedRevenueData({
    required DateTime start,
    required DateTime end,
  }) async {
    final startStr = start.toIso8601String().split('T')[0];
    final endStr = end.toIso8601String().split('T')[0];

    final bookingResp = await _supabase
        .from('bookings')
        .select('''
          id, guest_name, total_amount, paid_amount, extra_charges, status, requested_room_type,
          check_in_date,
          rooms(type)
        ''')
        .inFilter('status', ['Checked-in', 'checked_in', 'checked-in', 'Checked in', 'checked in'])
        .gte('check_in_date', startStr)
        .lte('check_in_date', endStr)
        .order('check_in_date', ascending: false);

    final checkedInBookings = List<Map<String, dynamic>>.from(bookingResp as List);
    final rows = <Map<String, dynamic>>[];

    for (final b in checkedInBookings) {
      final totalAmount = (b['total_amount'] as num?)?.toInt();
      final paidAmount = (b['paid_amount'] as num?)?.toInt();
      final amount = _collectedAmountKobo(totalAmount, paidAmount);
      final rooms = b['rooms'];
      String roomType = '';
      if (rooms is Map && rooms['type'] != null) {
        roomType = rooms['type']?.toString() ?? '';
      } else if (rooms is List && rooms.isNotEmpty && rooms.first is Map) {
        roomType = (rooms.first as Map)['type']?.toString() ?? '';
      } else {
        roomType = b['requested_room_type']?.toString() ?? '';
      }
      rows.add({
        'event_date': b['check_in_date'],
        'source': 'Room Booking',
        'description': '${b['guest_name'] ?? 'Guest'} • ${roomType.isEmpty ? 'Room' : roomType}',
        'status': b['status']?.toString() ?? 'Checked-in',
        'amount': amount,
      });
    }

    final miniResp = await _supabase
        .from('mini_mart_sales')
        .select('sale_date, total_amount, quantity, unit_price, customer_name, mini_mart_items(name)')
        .gte('sale_date', startStr)
        .lte('sale_date', endStr)
        .order('sale_date', ascending: false);
    final miniList = List<Map<String, dynamic>>.from(miniResp as List);
    int miniMartSales = 0;
    for (final s in miniList) {
      final total = (s['total_amount'] as num?)?.toInt() ?? 0;
      miniMartSales += total;
      final item = s['mini_mart_items'];
      final itemName = item is Map ? item['name']?.toString() ?? '' : '';
      final qty = (s['quantity'] as num?)?.toInt() ?? 0;
      rows.add({
        'event_date': s['sale_date'],
        'source': 'Mini Mart',
        'description': '${itemName.isEmpty ? 'Sale' : itemName}${qty > 0 ? ' x$qty' : ''}${(s['customer_name']?.toString() ?? '').isNotEmpty ? ' • ${s['customer_name']}' : ''}',
        'status': 'Completed',
        'amount': total,
      });
    }

    final kitchenResp = await _supabase
        .from('kitchen_sales')
        .select('created_at, total_amount, quantity, item_name, menu_items(name)')
        .gte('created_at', start.toIso8601String())
        .lte('created_at', end.toIso8601String())
        .order('created_at', ascending: false);
    final kitchenList = List<Map<String, dynamic>>.from(kitchenResp as List);
    int kitchenSales = 0;
    for (final s in kitchenList) {
      final total = (s['total_amount'] as num?)?.toInt() ?? 0;
      kitchenSales += total;
      final menuItem = s['menu_items'];
      final itemName = (s['item_name']?.toString() ?? '').isNotEmpty
          ? s['item_name']?.toString() ?? ''
          : (menuItem is Map ? menuItem['name']?.toString() ?? '' : '');
      final qty = (s['quantity'] as num?)?.toInt() ?? 0;
      rows.add({
        'event_date': s['created_at'],
        'source': 'Kitchen/Restaurant',
        'description': '${itemName.isEmpty ? 'Sale' : itemName}${qty > 0 ? ' x$qty' : ''}',
        'status': 'Completed',
        'amount': total,
      });
    }

    int vipBarSales = 0;
    int outsideBarSales = 0;
    bool barLineLevelLoaded = false;
    try {
      List<Map<String, dynamic>> barSales;
      try {
        final barResp = await _supabase
            .from('stock_transactions')
            .select('created_at, quantity, total_cost, unit_price_kobo, line_total_kobo, transaction_type, stock_items(name), locations(name)')
            .eq('transaction_type', 'Sale')
            .gte('created_at', start.toIso8601String())
            .lte('created_at', end.toIso8601String())
            .order('created_at', ascending: false);
        barSales = List<Map<String, dynamic>>.from(barResp as List);
      } catch (_) {
        final barResp = await _supabase
            .from('stock_transactions')
            .select('created_at, quantity, total_cost, transaction_type, stock_items(name), locations(name)')
            .eq('transaction_type', 'Sale')
            .gte('created_at', start.toIso8601String())
            .lte('created_at', end.toIso8601String())
            .order('created_at', ascending: false);
        barSales = List<Map<String, dynamic>>.from(barResp as List);
      }

      for (final s in barSales) {
        final qty = ((s['quantity'] as num?)?.toInt() ?? 0).abs();
        final locationData = s['locations'];
        final locationName = locationData is Map
            ? (locationData['name']?.toString() ?? '')
            : (locationData is List && locationData.isNotEmpty && locationData.first is Map)
                ? ((locationData.first as Map)['name']?.toString() ?? '')
                : '';
        final locationLower = locationName.toLowerCase();
        final isVip = locationLower.contains('vip');
        final source = isVip ? 'VIP Bar' : 'Outside Bar';

        final itemData = s['stock_items'];
        final itemName = itemData is Map
            ? (itemData['name']?.toString() ?? '')
            : (itemData is List && itemData.isNotEmpty && itemData.first is Map)
                ? ((itemData.first as Map)['name']?.toString() ?? '')
                : '';

        var lineTotal = _toIntValue(s['line_total_kobo']);
        if (lineTotal <= 0) {
          lineTotal = (s['total_cost'] as num?)?.toInt() ?? 0;
        }
        lineTotal = lineTotal.abs();

        if (isVip) {
          vipBarSales += lineTotal;
        } else {
          outsideBarSales += lineTotal;
        }

        rows.add({
          'event_date': s['created_at'],
          'source': source,
          'description': '${itemName.isEmpty ? 'Bar sale' : itemName}${qty > 0 ? ' x$qty' : ''}${locationName.isEmpty ? '' : ' • $locationName'}',
          'status': 'Completed',
          'amount': lineTotal,
        });
      }
      barLineLevelLoaded = true;
    } catch (_) {
      barLineLevelLoaded = false;
    }

    if (!barLineLevelLoaded) {
      try {
        final deptResp = await _supabase
            .from('department_sales')
            .select('department, total_sales, date')
            .inFilter('department', ['vip_bar', 'outside_bar'])
            .gte('date', startStr)
            .lte('date', endStr)
            .order('date', ascending: false);
        final deptList = List<Map<String, dynamic>>.from(deptResp as List);
        for (final r in deptList) {
          final dept = r['department']?.toString() ?? '';
          final total = (r['total_sales'] as num?)?.toInt() ?? 0;
          if (dept == 'vip_bar') {
            vipBarSales += total;
          } else if (dept == 'outside_bar') {
            outsideBarSales += total;
          }
          rows.add({
            'event_date': r['date'],
            'source': dept == 'vip_bar' ? 'VIP Bar' : 'Outside Bar',
            'description': 'Department sales aggregate',
            'status': 'Completed',
            'amount': total,
          });
        }
      } catch (_) {
      }
    }

    rows.sort((a, b) {
      final at = DateTime.tryParse(a['event_date']?.toString() ?? '');
      final bt = DateTime.tryParse(b['event_date']?.toString() ?? '');
      if (at == null && bt == null) return 0;
      if (at == null) return 1;
      if (bt == null) return -1;
      return bt.compareTo(at);
    });

    return _UnifiedRevenueData(
      rows: rows,
      checkedInBookings: checkedInBookings,
      miniMartSales: miniMartSales,
      kitchenSales: kitchenSales,
      vipBarSales: vipBarSales,
      outsideBarSales: outsideBarSales,
    );
  }

  int _toIntValue(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
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

  Future<void> _loadRoomTypePrices() async {
    try {
      final response = await _supabase
          .from('room_types')
          .select('type, price');
      
      _roomTypePrices = {};
      for (var row in response) {
        final type = row['type'] as String;
        final price = row['price'] as int;
        _roomTypePrices![type] = price;
      }
      _roomTypeCacheTime = DateTime.now();
    } catch (e) {
      _roomTypePrices = {};
      _roomTypeCacheTime = DateTime.now();
    }
  }

  Future<Map<String, dynamic>> getGuestStats({
    required TimePeriod period,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    await _ensureBookingLifecycleUpToDate();
    final now = DateTime.now();
    final range = _getDateRange(period, now, customStart, customEnd);
    final rowsRaw = await _supabase
        .from('bookings')
        .select('id, guest_name, status, total_amount, paid_amount, check_in_date, check_out_date')
        .gte('created_at', range.start.toIso8601String())
        .lte('created_at', range.end.toIso8601String())
        .order('created_at', ascending: false);
    final rows = rowsRaw as List;

    int total = 0, checkedIn = 0, checkedOut = 0, pending = 0, cancelled = 0, rejected = 0, expired = 0, confirmed = 0;
    int revenueSum = 0;
    int totalNights = 0;

    for (final b in rows) {
      total++;
      final status = _normalizeBookingStatus(b['status']?.toString());
      if (status == 'checked-in') {
        checkedIn++;
      } else if (status == 'checked-out') {
        checkedOut++;
      } else if (status == 'pending') {
        pending++;
      } else if (status == 'cancelled') {
        cancelled++;
      } else if (status == 'rejected') {
        rejected++;
      } else if (status == 'expired') {
        expired++;
      } else if (status == 'confirmed') {
        confirmed++;
      }

      revenueSum += _collectedAmountKobo(
        (b['total_amount'] as num?)?.toInt(),
        (b['paid_amount'] as num?)?.toInt(),
      );
      try {
        final ci = DateTime.parse(b['check_in_date'] as String);
        final co = DateTime.parse(b['check_out_date'] as String);
        totalNights += co.difference(ci).inDays.abs();
      } catch (_) {}
    }

    return {
      'total': total,
      'checked_in': checkedIn,
      'checked_out': checkedOut,
      'pending': pending,
      'cancelled': cancelled,
      'rejected': rejected,
      'expired': expired,
      'confirmed': confirmed,
      'revenue': revenueSum,
      'avg_revenue': total > 0 ? (revenueSum / total).round() : 0,
      'avg_nights': total > 0 ? (totalNights / total).toStringAsFixed(1) : '0',
      'rows': rows.take(detailPageSize).map((e) => e as Map<String, dynamic>).toList(),
      'total_rows_count': rows.length,
    };
  }

  Future<List<Map<String, dynamic>>> getGuestBookingRowsPage({
    required TimePeriod period,
    DateTime? customStart,
    DateTime? customEnd,
    int offset = 0,
    int limit = detailPageSize,
  }) async {
    await _ensureBookingLifecycleUpToDate();
    final now = DateTime.now();
    final range = _getDateRange(period, now, customStart, customEnd);
    final response = await _supabase
        .from('bookings')
        .select('id, guest_name, status, total_amount, paid_amount, check_in_date, check_out_date')
        .gte('created_at', range.start.toIso8601String())
        .lte('created_at', range.end.toIso8601String())
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(response as List);
  }

  Future<void> _ensureBookingLifecycleUpToDate() async {
    try {
      await _supabase.rpc('reconcile_assigned_bookings');
    } catch (_) {
    }
    try {
      await _supabase.rpc('auto_update_expired_bookings');
    } catch (_) {
    }
  }

  int _collectedAmountKobo(int? totalAmount, int? paidAmount) {
    if (paidAmount != null) return paidAmount;
    return totalAmount ?? 0;
  }

  Future<Map<String, dynamic>> getOperationsStats({
    required TimePeriod period,
    DateTime? customStart,
    DateTime? customEnd,
  }) async {
    final now = DateTime.now();
    final range = _getDateRange(period, now, customStart, customEnd);

    int activityCount = 0;
    int uniqueStaff = 0;
    String topDepartment = 'N/A';
    int negativeAdjustments = 0;
    List<dynamic> activities = [];

    try {
      final activitiesAll = await _supabase
          .from('staff_activities')
          .select('id, staff_profile_id, department, action, details, created_at, staff_profile:profiles!staff_profile_id(full_name)')
          .gte('created_at', range.start.toIso8601String())
          .lte('created_at', range.end.toIso8601String())
          .order('created_at', ascending: false);
      activities = activitiesAll;

      activityCount = activities.length;
      final staffIds = <String>{};
      final deptCounts = <String, int>{};
      for (final a in activities) {
        final sid = a['staff_profile_id']?.toString();
        if (sid != null) staffIds.add(sid);
        final dept = a['department']?.toString() ?? 'Unknown';
        deptCounts[dept] = (deptCounts[dept] ?? 0) + 1;
      }
      uniqueStaff = staffIds.length;
      if (deptCounts.isNotEmpty) {
        topDepartment = deptCounts.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
      }
    } catch (_) {}

    try {
      final transactions = await _supabase
          .from('stock_transactions')
          .select('id, quantity, transaction_type')
          .gte('created_at', range.start.toIso8601String())
          .lte('created_at', range.end.toIso8601String());

      for (final t in transactions) {
        final qty = (t['quantity'] as num?)?.toInt() ?? 0;
        final type = t['transaction_type']?.toString() ?? '';
        if (qty < 0 || type == 'Wastage') negativeAdjustments++;
      }
    } catch (_) {}

    return {
      'activity_count': activityCount,
      'unique_staff': uniqueStaff,
      'top_department': topDepartment,
      'negative_adjustments': negativeAdjustments,
      'activities': activities.take(detailPageSize).toList(),
      'total_activities_count': activities.length,
    };
  }

  Future<List<Map<String, dynamic>>> getOperationsActivitiesPage({
    required TimePeriod period,
    DateTime? customStart,
    DateTime? customEnd,
    int offset = 0,
    int limit = detailPageSize,
  }) async {
    final now = DateTime.now();
    final range = _getDateRange(period, now, customStart, customEnd);
    final response = await _supabase
        .from('staff_activities')
        .select('id, staff_profile_id, department, action, details, created_at, staff_profile:profiles!staff_profile_id(full_name)')
        .gte('created_at', range.start.toIso8601String())
        .lte('created_at', range.end.toIso8601String())
        .order('created_at', ascending: false)
        .range(offset, offset + limit - 1);
    return List<Map<String, dynamic>>.from(response as List);
  }

  ({DateTime start, DateTime end}) _getDateRange(
    TimePeriod period,
    DateTime now,
    DateTime? customStart,
    DateTime? customEnd,
  ) {
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
      case TimePeriod.last30Days:
        startDate = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 30));
        endDate = DateTime(now.year, now.month, now.day, 23, 59, 59);
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