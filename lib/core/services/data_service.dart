import 'dart:async';
import 'package:supabase_flutter/supabase_flutter.dart';

class DataService {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  final _supabase = Supabase.instance.client;
  static const int _maxRetries = 3;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const Duration _queryTimeout = Duration(seconds: 30);

  // Getter to expose supabase client for direct access when needed
  SupabaseClient get supabase => _supabase;

  // Retry wrapper for network operations
  Future<T> _retryOperation<T>(
    Future<T> Function() operation, {
    int retries = _maxRetries,
  }) async {
    int attempts = 0;
    while (attempts < retries) {
      try {
        return await operation().timeout(_queryTimeout);
      } on TimeoutException {
        if (attempts == retries - 1) rethrow;
        await Future.delayed(_retryDelay * (attempts + 1));
        attempts++;
      } on PostgrestException catch (e) {
        // Don't retry on client errors (4xx)
        if (e.code != null && e.code!.startsWith('4')) {
          rethrow;
        }
        if (attempts == retries - 1) rethrow;
        await Future.delayed(_retryDelay * (attempts + 1));
        attempts++;
      } catch (e) {
        if (attempts == retries - 1) rethrow;
        await Future.delayed(_retryDelay * (attempts + 1));
        attempts++;
      }
    }
    throw Exception('Operation failed after $retries attempts');
  }

  // Bookings
  Future<List<Map<String, dynamic>>> getBookings() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('bookings')
          .select('*, rooms(*), profiles!guest_profile_id(*)')
          .order('created_at', ascending: false)
          .limit(100); // Limit for performance
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> createBooking(Map<String, dynamic> booking) async {
    await _retryOperation(() async {
      // booking should contain 'guest_profile_id' (not guest_name/email/phone)
      // If it doesn't, we need to create/get the profile first
      String? guestProfileId = booking['guest_profile_id'] as String?;
      
      if (guestProfileId == null && booking['guest_email'] != null) {
        // Get or create profile
        final existing = await _supabase
            .from('profiles')
            .select('id')
            .eq('email', booking['guest_email'] as String)
            .maybeSingle();
        
        if (existing != null) {
          guestProfileId = existing['id'] as String;
        } else {
          // Profile doesn't exist - need to create auth user first
          // Generate a secure temporary password
          final tempPassword = _generateSecurePassword();
          final fullName = booking['guest_name'] as String? ?? 'Guest';
          final email = booking['guest_email'] as String;
          final phone = booking['guest_phone'] as String?;
          
          // Create auth user - this will trigger the profile creation via database trigger
          final authResponse = await _supabase.auth.signUp(
            email: email,
            password: tempPassword,
            data: {
              'full_name': fullName,
              'phone': phone ?? '',
            },
          );

          if (authResponse.user == null) {
            throw Exception('Failed to create auth user for guest');
          }

          guestProfileId = authResponse.user!.id;

          // Wait a moment for the trigger to create the profile
          await Future.delayed(const Duration(milliseconds: 500));

          // Update phone if it wasn't set by trigger
          if (phone != null && phone.isNotEmpty) {
            await _supabase
                .from('profiles')
                .update({'phone': phone})
                .eq('id', guestProfileId);
          }
        }
      }
      
      if (guestProfileId == null) {
        throw Exception('guest_profile_id or guest_email is required');
      }
      
      await _supabase.from('bookings').insert({
        'guest_profile_id': guestProfileId,
        'room_id': booking['room_id'],
        'requested_room_type': booking['requested_room_type'],
        'check_in_date': booking['check_in'],
        'check_out_date': booking['check_out'],
        'status': booking['status'] ?? 'Pending Check-in',
        'total_amount': booking['total_amount'],
        'paid_amount': booking['paid_amount'],
      });
    });
  }

  Future<void> updateBookingStatus(String bookingId, String newStatus) async {
    await _retryOperation(() async {
      await _supabase
          .from('bookings')
          .update({'status': newStatus})
          .eq('id', bookingId);
    });
  }

  // Room Types
  Future<List<Map<String, dynamic>>> getRoomTypes() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('room_types')
          .select()
          .order('price');
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // Rooms
  Future<List<Map<String, dynamic>>> getRooms() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('rooms')
          .select()
          .order('room_number')
          .limit(500); // Limit for performance
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> updateRoomStatus(String roomId, String newStatus) async {
    await _retryOperation(() async {
      await _supabase
          .from('rooms')
          .update({'status': newStatus})
          .eq('id', roomId);
    });
  }

  // Staff Profiles (using profiles table with role filtering)
  Future<List<Map<String, dynamic>>> getStaffProfiles() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('profiles')
          .select()
          .neq('roles', ['guest']) // Exclude guests
          .eq('status', 'Active') // Only active staff
          .order('full_name')
          .limit(500); // Limit for performance
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // Inventory & Stock
  Future<List<Map<String, dynamic>>> getInventoryItems() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('inventory_items')
          .select()
          .order('name')
          .limit(1000); // Limit for performance
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> addInventoryItem(Map<String, dynamic> item) async {
    await _retryOperation(() async {
      await _supabase.from('inventory_items').insert({
        'name': item['name'],
        'description': item['description'],
        'current_stock': item['current_stock'] ?? 0,
        'unit': item['unit'],
        'vip_bar_price': item['vip_bar_price'],
        'outside_bar_price': item['outside_bar_price'],
        'category': item['category'],
        'department': item['department'] ?? 'both',
      });
    });
  }

  Future<List<Map<String, dynamic>>> getStockTransactions() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('stock_transactions')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> recordStockTransaction(Map<String, dynamic> transaction) async {
    await _retryOperation(() async {
      await _supabase.from('stock_transactions').insert({
        'stock_item_id': transaction['stock_item_id'], // Required: references stock_items
        'location_id': transaction['location_id'], // Required: references locations
        'staff_profile_id': transaction['staff_profile_id'], // Required: references profiles
        'transaction_type': transaction['transaction_type'], // Required: 'Purchase', 'Transfer_In', 'Transfer_Out', 'Sale', 'Wastage'
        'quantity': transaction['quantity'], // Required: positive or negative
        'notes': transaction['notes'], // Optional
      });
    });
  }

  // Financial Data
  Future<List<Map<String, dynamic>>> getExpenses() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('expenses')
          .select()
          .order('transaction_date', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> addExpense(Map<String, dynamic> expense) async {
    await _retryOperation(() async {
      await _supabase.from('expenses').insert({
        'description': expense['description'],
        'amount': expense['amount'],
        'category': expense['category'],
        'transaction_date': expense['transaction_date'] ?? expense['date'] ?? DateTime.now().toIso8601String().split('T')[0],
        'department': expense['department'] ?? 'all',
        'payment_method': expense['payment_method'] ?? 'cash',
        'staff_id': expense['staff_id'],
      });
    });
  }

  Future<List<Map<String, dynamic>>> getIncomeRecords() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('income_records')
          .select()
          .order('date', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> addIncomeRecord(Map<String, dynamic> income) async {
    await _retryOperation(() async {
      await _supabase.from('income_records').insert({
        'description': income['description'],
        'amount': income['amount'],
        'source': income['source'],
        'date': income['date'] ?? DateTime.now().toIso8601String().split('T')[0],
        'department': income['department'] ?? 'finance',
        'payment_method': income['payment_method'] ?? 'cash',
      });
    });
  }

  Future<List<Map<String, dynamic>>> getPayrollRecords() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('payroll_records')
          .select()
          .order('month', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> addPayrollRecord(Map<String, dynamic> payroll) async {
    await _retryOperation(() async {
      await _supabase.from('payroll_records').insert({
        'staff_id': payroll['staff_id'],
        'amount': payroll['amount'],
        'month': payroll['month'],
        'status': payroll['status'] ?? 'pending',
        'payment_method': payroll['payment_method'] ?? 'bank_transfer',
      });
    });
  }

  Future<List<Map<String, dynamic>>> getCashDeposits() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('cash_deposits')
          .select()
          .order('date', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> addCashDeposit(Map<String, dynamic> deposit) async {
    await _retryOperation(() async {
      await _supabase.from('cash_deposits').insert({
        'amount': deposit['amount'],
        'bank_name': deposit['bank_name'],
        'account_type': deposit['account_type'],
        'bank_charges': deposit['bank_charges'] ?? 0,
        'net_amount': deposit['net_amount'] ?? deposit['amount'] - (deposit['bank_charges'] ?? 0),
        'date': deposit['date'] ?? DateTime.now().toIso8601String().split('T')[0],
        'description': deposit['description'],
        'staff_id': deposit['staff_id'],
      });
    });
  }

  Future<List<Map<String, dynamic>>> getDebts() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('debts')
          .select()
          .order('date', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> recordDebt(Map<String, dynamic> debt) async {
    await _retryOperation(() async {
      await _supabase.from('debts').insert({
        'debtor_name': debt['debtor_name'],
        'debtor_type': debt['debtor_type'],
        'amount': debt['amount'],
        'owed_to': debt['owed_to'],
        'reason': debt['reason'],
        'date': debt['date'] ?? DateTime.now().toIso8601String().split('T')[0],
        'status': debt['status'] ?? 'pending',
      });
    });
  }

  // Financial Summary
  Future<Map<String, dynamic>> getFinancialSummary() async {
    return await _retryOperation(() async {
      final income = await _supabase
          .from('income_records')
          .select('amount')
          .gte('date', DateTime.now().subtract(const Duration(days: 30)).toIso8601String().split('T')[0]);
      
      final expenses = await _supabase
          .from('expenses')
          .select('amount')
          .gte('transaction_date', DateTime.now().subtract(const Duration(days: 30)).toIso8601String().split('T')[0]);

      final totalIncome = (income as List).fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));
      final totalExpenses = (expenses as List).fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));

      return {
        'total_income': totalIncome,
        'total_expenses': totalExpenses,
        'net_profit': totalIncome - totalExpenses,
        'available_cash': totalIncome - totalExpenses, // Simplified
      };
    });
  }

  Future<List<Map<String, dynamic>>> getDepartmentPerformance() async {
    return await _retryOperation(() async {
      // Get income by department
      final incomeRecords = await _supabase
          .from('income_records')
          .select('department, amount')
          .gte('date', DateTime.now().subtract(const Duration(days: 30)).toIso8601String().split('T')[0]);
      
      // Get expenses by department
      final expenses = await _supabase
          .from('expenses')
          .select('department, amount')
          .gte('date', DateTime.now().subtract(const Duration(days: 30)).toIso8601String().split('T')[0]);
      
      // Calculate totals by department
      final Map<String, double> revenueByDept = {};
      final Map<String, double> expensesByDept = {};
      
      for (var record in incomeRecords as List) {
        final dept = record['department'] as String? ?? 'Other';
        final amount = (record['amount'] as num?)?.toDouble() ?? 0.0;
        revenueByDept[dept] = (revenueByDept[dept] ?? 0) + amount;
      }
      
      for (var expense in expenses as List) {
        final dept = expense['department'] as String? ?? 'Other';
        final amount = (expense['amount'] as num?)?.toDouble() ?? 0.0;
        expensesByDept[dept] = (expensesByDept[dept] ?? 0) + amount;
      }
      
      // Combine all departments
      final allDepartments = <String>{...revenueByDept.keys, ...expensesByDept.keys};
      
      return allDepartments.map((dept) {
        final revenue = revenueByDept[dept] ?? 0.0;
        final expense = expensesByDept[dept] ?? 0.0;
        final profit = revenue - expense;
        final profitMargin = revenue > 0 ? (profit / revenue * 100) : 0.0;
        
        String performance;
        if (profitMargin >= 50) {
          performance = 'excellent';
        } else if (profitMargin >= 30) {
          performance = 'good';
        } else if (profitMargin >= 10) {
          performance = 'fair';
        } else {
          performance = 'poor';
        }
        
        return {
          'department': dept,
          'revenue': revenue,
          'expenses': expense,
          'profit': profit,
          'performance': performance,
        };
      }).toList();
    });
  }

  // Dashboard Statistics
  Future<Map<String, dynamic>> getDashboardStats() async {
    return await _retryOperation(() async {
      final bookings = await _supabase
          .from('bookings')
          .select('status');
      
      final rooms = await _supabase
          .from('rooms')
          .select('id');

      final checkedIn = (bookings as List).where((b) => b['status'] == 'Checked-in').length;
      final pending = (bookings as List).where((b) => b['status'] == 'Pending Check-in').length;
      final totalRooms = (rooms as List).length;
      final occupancyRate = totalRooms > 0 ? ((checkedIn / totalRooms) * 100).round() : 0;

      // Get revenue from income records
      final revenue = await _supabase
          .from('income_records')
          .select('amount')
          .gte('date', DateTime.now().subtract(const Duration(days: 30)).toIso8601String().split('T')[0]);
      
      final totalRevenue = (revenue as List).fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));

      return {
        'pending_count': pending,
        'checked_in_count': checkedIn,
        'occupancy_rate': occupancyRate,
        'total_revenue': totalRevenue,
        'available_rooms': totalRooms - checkedIn,
        'total_rooms': totalRooms,
      };
    });
  }

  Future<List<Map<String, dynamic>>> getRecentActivities() async {
    return await _retryOperation(() async {
      // Combine recent activities from multiple tables
      final recentBookings = await _supabase
          .from('bookings')
          .select('id, guest_name, created_at, status')
          .order('created_at', ascending: false)
          .limit(10);

      return (recentBookings as List).map((b) => {
        'id': b['id'],
        'type': 'booking',
        'description': 'New booking for ${b['guest_name']}',
        'timestamp': b['created_at'],
        'status': b['status'],
      }).toList();
    });
  }

  // Mini Mart
  Future<List<Map<String, dynamic>>> getMiniMartItems() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('mini_mart_items')
          .select()
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<List<Map<String, dynamic>>> getMiniMartSales() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('mini_mart_sales')
          .select('*, mini_mart_items(name, price), profiles!sold_by(full_name)')
          .order('sale_date', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> recordMiniMartSale(Map<String, dynamic> sale) async {
    return await _retryOperation(() async {
      await _supabase.from('mini_mart_sales').insert({
        'item_id': sale['item_id'],
        'quantity': sale['quantity'] ?? 1,
        'unit_price': sale['unit_price'],
        'total_amount': sale['total_amount'] ?? (sale['quantity'] ?? 1) * sale['unit_price'],
        'sale_date': sale['sale_date'] ?? DateTime.now().toIso8601String(),
        'payment_method': sale['payment_method'] ?? 'cash',
        'customer_name': sale['customer_name'],
        'booking_id': sale['booking_id'],
        'sold_by': sale['sold_by'],
        'notes': sale['notes'],
      });
    });
  }

  // Kitchen
  Future<List<Map<String, dynamic>>> getKitchenOrders() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('kitchen_orders')
          .select()
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<List<Map<String, dynamic>>> getMenuItems() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('menu_items')
          .select('id, name, price, department, barcode')
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // POS methods
  Future<List<Map<String, dynamic>>> getPosMenuItems() async {
    return getMenuItems();
  }

  Future<List<Map<String, dynamic>>> getPosCheckedInGuests() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('bookings')
          .select('id, guest_name, rooms!inner(room_number)')
          .eq('status', 'checked_in');
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // Checked-in Guests
  Future<List<Map<String, dynamic>>> getCheckedInGuests() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('bookings')
          .select('id, guest_name, rooms!inner(room_number), processed_by, check_in_date')
          .eq('status', 'checked_in')
          .order('check_in_date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // Department Sales
  Future<List<Map<String, dynamic>>> getDepartmentSales(String department) async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('department_sales')
          .select()
          .eq('department', department)
          .gte('date', DateTime.now().toIso8601String().split('T')[0])
          .order('date', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // Recent Purchases
  Future<List<Map<String, dynamic>>> getRecentPurchases() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('purchase_orders')
          .select('*, profiles!purchaser_id(full_name)')
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // HR methods
  Future<void> assignRoleToStaff(String staffId, String role, {bool isTemporary = false, DateTime? expiryDate}) async {
    await _retryOperation(() async {
      await _supabase.from('staff_role_assignments').insert({
        'staff_id': staffId,
        'assigned_role': role,
        'is_temporary': isTemporary,
        'assigned_by': _supabase.auth.currentUser?.id,
        'assigned_date': DateTime.now().toIso8601String().split('T')[0],
        'expiry_date': expiryDate?.toIso8601String().split('T')[0],
        'reason': isTemporary ? 'Temporary role assignment' : 'Permanent role assignment',
      });
    });
  }

  // Department Transfers (Kitchen Dispatch)
  Future<List<Map<String, dynamic>>> getDepartmentTransfers() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('department_transfers')
          .select('*, menu_items(name), profiles!dispatched_by_id(full_name)')
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> createDepartmentTransfer(Map<String, dynamic> transfer) async {
    await _retryOperation(() async {
      await _supabase.from('department_transfers').insert({
        'source_department': transfer['source_department'],
        'destination_department': transfer['destination_department'],
        'menu_item_id': transfer['menu_item_id'],
        'quantity': transfer['quantity'],
        'dispatched_by_id': transfer['dispatched_by_id'],
        'status': transfer['status'] ?? 'Pending',
      });
    });
  }

  // Maintenance Work Orders
  Future<List<Map<String, dynamic>>> getMaintenanceWorkOrders() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('maintenance_work_orders')
          .select('*, assets(name), profiles!reported_by_id(full_name), profiles!assigned_to(full_name)')
          .order('created_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> createMaintenanceWorkOrder(Map<String, dynamic> workOrder) async {
    await _retryOperation(() async {
      await _supabase.from('maintenance_work_orders').insert({
        'asset_id': workOrder['asset_id'],
        'reported_by_id': workOrder['reported_by_id'],
        'issue_description': workOrder['issue_description'],
        'location': workOrder['location'],
        'priority': workOrder['priority'] ?? 'Medium',
        'status': workOrder['status'] ?? 'Open',
        'assigned_to': workOrder['assigned_to'],
        'estimated_cost': workOrder['estimated_cost'],
        'due_date': workOrder['due_date'],
      });
    });
  }

  Future<void> updateMaintenanceWorkOrderStatus(String workOrderId, String status, {Map<String, dynamic>? updates}) async {
    await _retryOperation(() async {
      final updateData = {'status': status, ...?updates};
      if (status == 'Completed') {
        updateData['completed_at'] = DateTime.now().toIso8601String();
      }
      await _supabase
          .from('maintenance_work_orders')
          .update(updateData)
          .eq('id', workOrderId);
    });
  }

  // Purchase Orders
  Future<List<Map<String, dynamic>>> getPurchaseOrders({String? status}) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('purchase_orders')
          .select('*, purchase_order_items(*, stock_items(name)), profiles!purchaser_id(full_name), profiles!storekeeper_id(full_name)');
      
      if (status != null) {
        query = query.eq('status', status);
      }
      
      final response = await query.order('created_at', ascending: false).limit(100);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> createPurchaseOrder(Map<String, dynamic> order) async {
    await _retryOperation(() async {
      final orderResponse = await _supabase
          .from('purchase_orders')
          .insert({
            'purchaser_id': order['purchaser_id'],
            'supplier_name': order['supplier_name'],
            'total_cost': order['total_cost'],
            'status': 'Pending',
          })
          .select('id')
          .single();

      final orderId = orderResponse['id'] as String;
      
      // Insert items
      if (order['items'] != null) {
        final items = order['items'] as List;
        for (var item in items) {
          await _supabase.from('purchase_order_items').insert({
            'purchase_order_id': orderId,
            'stock_item_id': item['stock_item_id'],
            'quantity': item['quantity'],
            'unit_cost': item['unit_cost'],
          });
        }
      }
    });
  }

  // Posts/Announcements
  Future<List<Map<String, dynamic>>> getPosts({bool? isAnnouncement}) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('posts')
          .select('*, profiles!author_profile_id(full_name)');
      
      if (isAnnouncement != null) {
        query = query.eq('is_announcement', isAnnouncement);
      }
      
      final response = await query.order('created_at', ascending: false).limit(100);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> createPost(Map<String, dynamic> post) async {
    await _retryOperation(() async {
      await _supabase.from('posts').insert({
        'author_profile_id': post['author_profile_id'],
        'title': post['title'],
        'content': post['content'],
        'department': post['department'],
        'is_announcement': post['is_announcement'] ?? false,
      });
    });
  }

  Future<List<Map<String, dynamic>>> getStaffRoleAssignments() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('staff_role_assignments')
          .select('*, profiles!staff_id(full_name), profiles!assigned_by(full_name)')
          .eq('is_active', true)
          .order('created_at', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> createStaffRoleAssignment(Map<String, dynamic> assignment) async {
    await _retryOperation(() async {
      await _supabase.from('staff_role_assignments').insert({
        'staff_id': assignment['staff_id'],
        'assigned_role': assignment['assigned_role'],
        'assigned_by': assignment['assigned_by'],
        'start_date': assignment['start_date'],
        'end_date': assignment['end_date'],
        'is_active': assignment['is_active'] ?? true,
        'notes': assignment['notes'],
      });
    });
  }

  // Bartender Shift Management
  Future<Map<String, dynamic>?> getActiveShift(String bartenderId) async {
    return await _retryOperation(() async {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      
      final response = await _supabase
          .from('bartender_shifts')
          .select()
          .eq('bartender_id', bartenderId)
          .eq('status', 'active')
          .gte('start_time', startOfDay.toIso8601String())
          .maybeSingle();
      return response != null ? Map<String, dynamic>.from(response) : null;
    });
  }

  Future<void> startShift({
    required String bartenderId,
    int? openingCash,
  }) async {
    await _retryOperation(() async {
      await _supabase.from('bartender_shifts').insert({
        'bartender_id': bartenderId,
        'opening_cash': openingCash ?? 0,
        'status': 'active',
        'start_time': DateTime.now().toIso8601String(),
        'date': DateTime.now().toIso8601String().split('T')[0],
      });
    });
  }

  Future<void> endShift({
    required String shiftId,
    int? closingCash,
    int? totalSales,
  }) async {
    await _retryOperation(() async {
      await _supabase
          .from('bartender_shifts')
          .update({
            'closing_cash': closingCash,
            'total_sales': totalSales,
            'status': 'closed',
            'end_time': DateTime.now().toIso8601String(),
          })
          .eq('id', shiftId);
    });
  }

  // Pending Purchases (for Store View)
  Future<List<Map<String, dynamic>>> getPendingPurchases() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('purchase_orders')
          .select('*, purchase_order_items(*, stock_items(name)), profiles!purchaser_id(full_name)')
          .eq('status', 'Pending')
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // Attendance Records
  Future<Map<String, dynamic>?> getCurrentAttendance(String profileId) async {
    return await _retryOperation(() async {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      
      final response = await _supabase
          .from('attendance_records')
          .select('*, profiles!profile_id(full_name, roles)')
          .eq('profile_id', profileId)
          .gte('clock_in_time', startOfDay.toIso8601String())
          .isFilter('clock_out_time', null)
          .order('clock_in_time', ascending: false)
          .limit(1)
          .maybeSingle();
      
      return response != null ? Map<String, dynamic>.from(response) : null;
    });
  }

  Future<List<Map<String, dynamic>>> getAttendanceRecords({
    String? profileId,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('attendance_records')
          .select('*, profiles!profile_id(full_name, roles)');
      
      if (profileId != null) {
        query = query.eq('profile_id', profileId);
      }
      
      if (startDate != null) {
        query = query.gte('date', startDate.toIso8601String().split('T')[0]);
      }
      
      if (endDate != null) {
        query = query.lte('date', endDate.toIso8601String().split('T')[0]);
      }
      
      final response = await query
          .order('clock_in_time', ascending: false)
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // Create staff profile (Owner only - requires Admin API)
  // Note: This requires Supabase Admin API access
  // The auth user must be created first via Admin API, then this updates the profile
  Future<Map<String, dynamic>> createStaffProfile({
    required String email,
    required String password,
    required String fullName,
    required String role,
    String? phone,
    String? department,
  }) async {
    return await _retryOperation(() async {
      // First, create auth user via Admin API (requires service role key)
      // Note: This should be done server-side or via a Supabase Edge Function
      // For now, we'll use a database function that expects the user to exist
      
      // Call the database function to update profile
      final response = await _supabase.rpc('create_staff_profile', params: {
        'p_email': email,
        'p_password': password, // Not used in function, but kept for API consistency
        'p_full_name': fullName,
        'p_phone': phone,
        'p_role': role,
        'p_department': department,
      });
      
      // Get the created profile
      final profile = await _supabase
          .from('profiles')
          .select()
          .eq('email', email)
          .single();
      
      return Map<String, dynamic>.from(profile);
    });
  }

  // Update staff status (for resigning/terminating staff)
  Future<void> updateStaffStatus(String profileId, String status) async {
    await _retryOperation(() async {
      await _supabase
          .from('profiles')
          .update({
            'status': status,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', profileId);
    });
  }

  /// Generate a secure temporary password for guest accounts
  String _generateSecurePassword() {
    // Generate a random password - guest can reset via email if needed
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#\$%^&*';
    final random = DateTime.now().millisecondsSinceEpoch;
    final password = StringBuffer();
    for (int i = 0; i < 16; i++) {
      password.write(chars[(random + i) % chars.length]);
    }
    return password.toString();
  }
}
