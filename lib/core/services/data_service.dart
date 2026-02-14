import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Lightweight in-memory cache with short TTL, stale-while-revalidate, and memoization.
class _DataServiceCache {
  static const _ttl = Duration(seconds: 30);
  final Map<String, _CacheEntry> _entries = {};
  final Map<String, Future> _inFlight = {};
  final Map<String, Set<String>> _keysByTable = {};

  Future<T> getOrFetch<T>({
    required String key,
    required List<String> tables,
    required Future<T> Function() fetch,
  }) async {
    final entry = _entries[key] as _CacheEntry<T>?;
    final now = DateTime.now();

    if (entry != null && now.difference(entry.fetchedAt) < _ttl) {
      return entry.data;
    }

    if (entry != null) {
      _revalidateInBackground(key, tables, fetch);
      return entry.data;
    }

    final existing = _inFlight[key] as Future<T>?;
    if (existing != null) return existing;

    final future = fetch().then((data) {
      _entries[key] = _CacheEntry<T>(data, DateTime.now());
      for (final t in tables) {
        _keysByTable.putIfAbsent(t, () => {}).add(key);
      }
      _inFlight.remove(key);
      return data;
    });
    _inFlight[key] = future;
    return future;
  }

  void _revalidateInBackground<T>(String key, List<String> tables, Future<T> Function() fetch) {
    fetch().then((data) {
      _entries[key] = _CacheEntry<T>(data, DateTime.now());
    }).catchError((_) {});
  }

  void invalidateForTable(String table) {
    final keys = _keysByTable[table];
    if (keys != null) {
      for (final k in keys) {
        _entries.remove(k);
      }
      _keysByTable.remove(table);
    }
  }

  void invalidateAll() {
    _entries.clear();
    _keysByTable.clear();
  }
}

class _CacheEntry<T> {
  final T data;
  final DateTime fetchedAt;
  _CacheEntry(this.data, this.fetchedAt);
}

class DataService {
  static final DataService _instance = DataService._internal();
  factory DataService() => _instance;
  DataService._internal();

  final _cache = _DataServiceCache();
  SupabaseClient? _supabaseClient;

  /// Invalidates cached data for the given table. Call when realtime events indicate the table changed.
  void invalidateCacheForTable(String table) {
    _cache.invalidateForTable(table);
  }

  /// Clears all cached data. Use sparingly (e.g. on logout).
  void invalidateAllCache() {
    _cache.invalidateAll();
  }
  SupabaseClient get _supabase {
    if (_supabaseClient != null) return _supabaseClient!;
    try {
      _supabaseClient = Supabase.instance.client;
      return _supabaseClient!;
    } catch (_) {
      throw Exception('Supabase not initialized');
    }
  }
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
      } catch (e, stack) {
        if (kDebugMode) debugPrint('DEBUG retry attempt $attempts: $e\n$stack');
        if (attempts == retries - 1) rethrow;
        await Future.delayed(_retryDelay * (attempts + 1));
        attempts++;
      }
    }
    throw Exception('Operation failed after $retries attempts');
  }

  // Bookings
  // Auto-update expired bookings (runs before fetching bookings to ensure accuracy)
  Future<void> updateExpiredBookings() async {
    await _retryOperation(() async {
      try {
        await _supabase.rpc('auto_update_expired_bookings');
      } catch (e, stack) {
        if (kDebugMode) debugPrint('DEBUG auto_update_expired_bookings: $e\n$stack');
      }
    });
  }

  /// Fetches bookings with pagination. Use limit 20-50 per page for list screens.
  /// Each page is cached separately; invalidate via invalidateCacheForTable('bookings').
  Future<List<Map<String, dynamic>>> getBookings({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 1000,
    int offset = 0,
  }) async {
    final key = 'getBookings:${startDate?.toIso8601String()}:${endDate?.toIso8601String()}:$limit:$offset';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['bookings'],
      fetch: () async {
        await updateExpiredBookings();
        return _retryOperation(() async {
          var query = _supabase
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
                discount_applied,
                discount_amount,
                discount_percentage,
                discount_reason,
                discount_applied_by,
                rooms(*),
                profiles!guest_profile_id(*),
                created_by_profile:profiles!created_by(full_name)
              ''');
          if (startDate != null) {
            query = query.gte('created_at', startDate.toIso8601String());
          }
          if (endDate != null) {
            query = query.lte('created_at', endDate.toIso8601String());
          }
          final response = await query
              .order('created_at', ascending: false)
              .range(offset, offset + limit - 1);
          return List<Map<String, dynamic>>.from(response);
        });
      },
    );
  }

  Future<void> addBookingCharge({
    required String bookingId,
    required String itemName,
    required int priceKobo,
    int quantity = 1,
    String? department,
    String? addedBy,
  }) async {
    await _retryOperation(() async {
      await _supabase.from('booking_charges').insert({
        'booking_id': bookingId,
        'item_name': itemName,
        'price': priceKobo,
        'quantity': quantity,
        'department': department,
        'added_by': addedBy,
      });
    });
  }

  Future<List<Map<String, dynamic>>> getBookingCharges(String bookingId) async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('booking_charges')
          .select()
          .eq('booking_id', bookingId)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<String> createBooking(Map<String, dynamic> booking) async {
    return await _retryOperation(() async {
      final payload = <String, dynamic>{
        'room_id': booking['room_id'],
        'requested_room_type': booking['requested_room_type'],
        'check_in_date': booking['check_in'],
        'check_out_date': booking['check_out'],
        'status': booking['status'] ?? 'Pending Check-in',
        'total_amount': booking['total_amount'],
        'paid_amount': booking['paid_amount'],
        'payment_method': booking['payment_method'] ?? 'cash',
        'guest_name': booking['guest_name'],
        'guest_email': booking['guest_email'],
        'guest_phone': booking['guest_phone'],
        'discount_applied': booking['discount_applied'] ?? false,
        'discount_amount': booking['discount_amount'] ?? 0,
        'discount_percentage': booking['discount_percentage'] ?? 0.0,
        'discount_reason': booking['discount_reason'],
        'discount_applied_by': booking['discount_applied_by'],
      };

      final guestProfileId = booking['guest_profile_id'] as String?;
      if (guestProfileId != null) {
        payload['guest_profile_id'] = guestProfileId;
      }

      final response = await _supabase
          .from('bookings')
          .insert(payload)
          .select('id')
          .single();

      return response['id'] as String;
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
  /// Fetches rooms with pagination. Use limit 20-50 per page for list screens.
  /// Each page is cached separately; invalidate via invalidateCacheForTable('rooms').
  Future<List<Map<String, dynamic>>> getRooms({
    int limit = 500,
    int offset = 0,
  }) async {
    final key = 'getRooms:$limit:$offset';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['rooms'],
      fetch: () => _retryOperation(() async {
        final response = await _supabase
            .from('rooms')
            .select()
            .order('room_number')
            .range(offset, offset + limit - 1);
        return List<Map<String, dynamic>>.from(response);
      }),
    );
  }

  Future<void> updateRoomStatus(String roomId, String newStatus, {String? priority}) async {
    await _retryOperation(() async {
      final updates = <String, dynamic>{'status': newStatus};
      if (priority != null) {
        updates['priority'] = priority;
      }
      await _supabase
          .from('rooms')
          .update(updates)
          .eq('id', roomId);
    });
  }

  // Stock Items
  Future<List<Map<String, dynamic>>> getStockItems() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('stock_items')
          .select()
          .order('name')
          .limit(500);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<String> addStockItem({
    required String name,
    String? description,
    String? unit,
    int? minStock,
    String? category,
    String? preferredSupplierId,
    String? preferredSupplierName,
  }) async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('stock_items')
          .insert({
            'name': name,
            'description': description,
            'category': category?.trim().isNotEmpty == true ? category?.trim() : null,
            'preferred_supplier_id':
                preferredSupplierId?.trim().isNotEmpty == true ? preferredSupplierId?.trim() : null,
            'preferred_supplier_name':
                preferredSupplierName?.trim().isNotEmpty == true ? preferredSupplierName?.trim() : null,
            'unit': unit?.isNotEmpty == true ? unit : 'units',
            'min_stock': minStock ?? 10,
          })
          .select('id')
          .single();
      return response['id'] as String;
    });
  }

  // Suppliers
  Future<List<Map<String, dynamic>>> getSuppliers() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('suppliers')
          .select()
          .order('name')
          .limit(500);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<Map<String, dynamic>> addSupplier({
    required String name,
    String? description,
    String? contactPhone,
    String? contactEmail,
  }) async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('suppliers')
          .insert({
            'name': name.trim(),
            'description': description?.trim().isNotEmpty == true ? description?.trim() : null,
            'contact_phone': contactPhone?.trim().isNotEmpty == true ? contactPhone?.trim() : null,
            'contact_email': contactEmail?.trim().isNotEmpty == true ? contactEmail?.trim() : null,
          })
          .select()
          .single();
      return Map<String, dynamic>.from(response);
    });
  }

  // Locations
  Future<List<Map<String, dynamic>>> getLocations() async {
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: 'getLocations',
      tables: const ['locations'],
      fetch: () => _retryOperation(() async {
        final response = await _supabase
            .from('locations')
            .select()
            .order('name')
            .limit(100);
        return List<Map<String, dynamic>>.from(response);
      }),
    );
  }

  // Departments
  Future<List<Map<String, dynamic>>> getDepartments() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('departments')
          .select()
          .order('name')
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // Stock Levels (per location)
  Future<List<Map<String, dynamic>>> getStockLevels({String? locationName}) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('stock_levels')
          .select('id, name, location_name, current_stock, min_stock');

      if (locationName != null && locationName.isNotEmpty) {
        query = query.eq('location_name', locationName);
      }

      final response = await query.order('name');
      return List<Map<String, dynamic>>.from(response);
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
        'unit': item['unit'],
        'vip_bar_price': item['vip_bar_price'],
        'outside_bar_price': item['outside_bar_price'],
        'category': item['category'],
        'department': item['department'] ?? 'both',
      });
    });
  }

  /// Fetches stock transactions with pagination. Use limit 20-50 per page for list screens.
  /// Each page is cached separately; invalidate via invalidateCacheForTable('stock_transactions').
  Future<List<Map<String, dynamic>>> getStockTransactions({
    String? locationId,
    String? staffId,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 1000,
    int offset = 0,
  }) async {
    final key = 'getStockTransactions:$locationId:$staffId:${startDate?.toIso8601String()}:${endDate?.toIso8601String()}:$limit:$offset';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['stock_transactions'],
      fetch: () => _retryOperation(() async {
        var query = _supabase
            .from('stock_transactions')
            .select('''
              *,
              stock_items(name, unit),
              locations(name),
              profiles!staff_profile_id(full_name)
            ''');
        if (locationId != null) {
          query = query.eq('location_id', locationId);
        }
        if (staffId != null) {
          query = query.eq('staff_profile_id', staffId);
        }
        if (startDate != null) {
          query = query.gte('created_at', startDate.toIso8601String());
        }
        if (endDate != null) {
          query = query.lte('created_at', endDate.toIso8601String());
        }
        final response = await query
            .order('created_at', ascending: false)
            .range(offset, offset + limit - 1);
        return List<Map<String, dynamic>>.from(response);
      }),
    );
  }

  Future<void> recordStockTransaction(Map<String, dynamic> transaction) async {
    await _retryOperation(() async {
      // Validate foreign key relationships before insert
      final stockItemId = transaction['stock_item_id'] as String?;
      final locationId = transaction['location_id'] as String?;
      final staffProfileId = transaction['staff_profile_id'] as String?;
      
      if (stockItemId == null) {
        throw Exception('stock_item_id is required');
      }
      if (locationId == null) {
        throw Exception('location_id is required');
      }
      if (staffProfileId == null) {
        throw Exception('staff_profile_id is required');
      }
      
      // Verify stock_item exists
      final stockItemExists = await _supabase
          .from('stock_items')
          .select('id')
          .eq('id', stockItemId)
          .maybeSingle();
      
      if (stockItemExists == null) {
        throw Exception('Stock item not found. Please verify the stock_item_id is valid.');
      }
      
      // Verify location exists
      final locationExists = await _supabase
          .from('locations')
          .select('id')
          .eq('id', locationId)
          .maybeSingle();
      
      if (locationExists == null) {
        throw Exception('Location not found. Please verify the location_id is valid.');
      }
      
      // Verify staff profile exists
      final staffExists = await _supabase
          .from('profiles')
          .select('id')
          .eq('id', staffProfileId)
          .maybeSingle();
      
      if (staffExists == null) {
        throw Exception('Staff profile not found. Please verify the staff_profile_id is valid.');
      }
      
      // All validations passed, insert transaction
      await _supabase.from('stock_transactions').insert({
        'stock_item_id': stockItemId,
        'location_id': locationId,
        'staff_profile_id': staffProfileId,
        'transaction_type': transaction['transaction_type'], // Required: 'Purchase', 'Transfer_In', 'Transfer_Out', 'Sale', 'Wastage'
        'quantity': transaction['quantity'], // Required: positive or negative
        'notes': transaction['notes'], // Optional
        // shift_id removed - bartender_shifts table no longer exists
      });
    });
  }

  // Stock Transfers (Main Store -> Department)
  Future<void> createStockTransfer({
    required String stockItemId,
    required String sourceLocationId,
    required String destinationLocationId,
    required int quantity,
    required String issuedById,
    required String receivedById,
    String? notes,
  }) async {
    await _retryOperation(() async {
      await _supabase.rpc('create_stock_transfer', params: {
        'p_stock_item_id': stockItemId,
        'p_source_location_id': sourceLocationId,
        'p_destination_location_id': destinationLocationId,
        'p_quantity': quantity,
        'p_issued_by_id': issuedById,
        'p_received_by_id': receivedById,
        'p_notes': notes,
      });
    });
  }

  // Financial Data
  Future<List<Map<String, dynamic>>> getExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    int limit = 200,
  }) async {
    final key = 'getExpenses:${startDate?.toIso8601String()}:${endDate?.toIso8601String()}:$status:$limit';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['expenses'],
      fetch: () => _retryOperation(() async {
        var query = _supabase.from('expenses').select();
        if (status != null && status.isNotEmpty) {
          query = query.eq('status', status);
        }
        if (startDate != null) {
          query = query.gte('transaction_date', startDate.toIso8601String().split('T')[0]);
        }
        if (endDate != null) {
          query = query.lte('transaction_date', endDate.toIso8601String().split('T')[0]);
        }
        final response = await query.order('transaction_date', ascending: false).limit(limit);
        return List<Map<String, dynamic>>.from(response);
      }),
    );
  }

  Future<void> addExpense(Map<String, dynamic> expense) async {
    await _retryOperation(() async {
      await _supabase.from('expenses').insert({
        'description': expense['description'],
        'amount': expense['amount'], // Should be in kobo
        'category': expense['category'],
        'transaction_date': expense['transaction_date'] ?? expense['date'] ?? DateTime.now().toIso8601String().split('T')[0],
        'department': expense['department'] ?? 'all',
        'payment_method': expense['payment_method'] ?? 'cash',
        'profile_id': expense['profile_id'] ?? expense['staff_id'], // Schema uses profile_id
        'status': expense['status'] ?? 'Pending',
      });
    });
  }

  Future<void> approveExpense({
    required String expenseId,
    required String approvedBy,
  }) async {
    await _retryOperation(() async {
      await _supabase.from('expenses').update({
        'status': 'Approved',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
        'rejected_by': null,
        'rejected_at': null,
        'rejection_reason': null,
      }).eq('id', expenseId);
    });
  }

  Future<void> rejectExpense({
    required String expenseId,
    required String rejectedBy,
    String? reason,
  }) async {
    await _retryOperation(() async {
      await _supabase.from('expenses').update({
        'status': 'Rejected',
        'rejected_by': rejectedBy,
        'rejected_at': DateTime.now().toIso8601String(),
        'rejection_reason': reason,
      }).eq('id', expenseId);
    });
  }

  Future<List<Map<String, dynamic>>> getIncomeRecords({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 200,
  }) async {
    final key = 'getIncomeRecords:${startDate?.toIso8601String()}:${endDate?.toIso8601String()}:$limit';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['income_records'],
      fetch: () => _retryOperation(() async {
        var query = _supabase.from('income_records').select();
        if (startDate != null) {
          query = query.gte('date', startDate.toIso8601String().split('T')[0]);
        }
        if (endDate != null) {
          query = query.lte('date', endDate.toIso8601String().split('T')[0]);
        }
        final response = await query.order('date', ascending: false).limit(limit);
        return List<Map<String, dynamic>>.from(response);
      }),
    );
  }

  Future<void> addIncomeRecord(Map<String, dynamic> income) async {
    await _retryOperation(() async {
      await _supabase.from('income_records').insert({
        'description': income['description'],
        'amount': income['amount'], // Should be in kobo
        'source': income['source'],
        'date': income['date'] ?? DateTime.now().toIso8601String().split('T')[0],
        'department': income['department'] ?? 'finance',
        'payment_method': income['payment_method'] ?? 'cash',
        'staff_id': income['staff_id'], // Add staff_id if provided
        'created_by': income['created_by'] ?? income['staff_id'], // Track who created
        'booking_id': income['booking_id'], // Optional booking link
      });
    });
  }

  Future<List<Map<String, dynamic>>> getPayrollRecords({
    DateTime? startMonth,
    DateTime? endMonth,
    String? approvalStatus,
    int limit = 200,
  }) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('payroll_records')
          .select('*, staff:profiles!staff_id(full_name)');
      if (approvalStatus != null && approvalStatus.isNotEmpty) {
        query = query.eq('approval_status', approvalStatus);
      }
      if (startMonth != null) {
        query = query.gte('month', DateTime(startMonth.year, startMonth.month, 1).toIso8601String().split('T')[0]);
      }
      if (endMonth != null) {
        query = query.lte('month', DateTime(endMonth.year, endMonth.month, 1).toIso8601String().split('T')[0]);
      }
      final response = await query.order('month', ascending: false).limit(limit);
      return List<Map<String, dynamic>>.from(response).map((row) {
        final mapped = Map<String, dynamic>.from(row);
        mapped['staff_name'] = (row['staff'] as Map?)?['full_name'];
        return mapped;
      }).toList();
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
        'processed_by': payroll['processed_by'],
        'notes': payroll['notes'],
        'approval_status': payroll['approval_status'] ?? 'pending',
      });
    });
  }

  Future<void> approvePayroll({
    required String payrollId,
    required String approvedBy,
  }) async {
    await _retryOperation(() async {
      await _supabase.from('payroll_records').update({
        'approval_status': 'approved',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
        'rejection_reason': null,
      }).eq('id', payrollId);
    });
  }

  Future<void> rejectPayroll({
    required String payrollId,
    required String rejectedBy,
    String? reason,
  }) async {
    await _retryOperation(() async {
      await _supabase.from('payroll_records').update({
        'approval_status': 'rejected',
        'approved_by': rejectedBy,
        'approved_at': DateTime.now().toIso8601String(),
        'rejection_reason': reason,
      }).eq('id', payrollId);
    });
  }

  Future<List<Map<String, dynamic>>> getCashDeposits({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 200,
  }) async {
    return await _retryOperation(() async {
      var query = _supabase.from('cash_deposits').select();
      if (startDate != null) {
        query = query.gte('date', startDate.toIso8601String().split('T')[0]);
      }
      if (endDate != null) {
        query = query.lte('date', endDate.toIso8601String().split('T')[0]);
      }
      final response = await query.order('date', ascending: false).limit(limit);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<List<Map<String, dynamic>>> getFinanceAuditLogs({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 200,
  }) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('finance_audit_logs')
          .select('*, actor:profiles!actor_id(full_name)');
      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate.toIso8601String());
      }
      final response = await query.order('created_at', ascending: false).limit(limit);
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

  Future<List<Map<String, dynamic>>> getDebts({
    String? soldBy,
    String? createdBy,
    String? department,
    String? bookingId,
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 200,
  }) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('debts')
          .select('*, sold_by_profile:profiles!sold_by(full_name), created_by_profile:profiles!created_by(full_name)');
      if (soldBy != null && soldBy.isNotEmpty) {
        query = query.eq('sold_by', soldBy);
      }
      if (createdBy != null && createdBy.isNotEmpty) {
        query = query.eq('created_by', createdBy);
      }
      if (department != null && department.isNotEmpty) {
        query = query.eq('department', department);
      }
      if (bookingId != null && bookingId.isNotEmpty) {
        query = query.eq('booking_id', bookingId);
      }
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }
      if (startDate != null) {
        query = query.gte('date', startDate.toIso8601String().split('T')[0]);
      }
      if (endDate != null) {
        query = query.lte('date', endDate.toIso8601String().split('T')[0]);
      }
      final response = await query
          .order('date', ascending: false)
          .limit(limit);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<void> recordDebt(Map<String, dynamic> debt) async {
    await _retryOperation(() async {
      await _supabase.from('debts').insert({
        'debtor_name': debt['debtor_name'],
        'debtor_phone': debt['debtor_phone'], // Phone number of debtor
        'debtor_type': debt['debtor_type'],
        'amount': debt['amount'],
        'owed_to': debt['owed_to'],
        'department': debt['department'],
        'source_department': debt['source_department'],
        'source_type': debt['source_type'],
        'reference_id': debt['reference_id'],
        'reason': debt['reason'],
        'date': debt['date'] ?? DateTime.now().toIso8601String().split('T')[0],
        'due_date': debt['due_date'],
        'status': debt['status'] ?? 'outstanding',
        'sold_by': debt['sold_by'], // Staff who made the credit sale
        'approved_by': debt['approved_by'], // Manually entered name (optional)
        'booking_id': debt['booking_id'], // Link to booking if applicable
        'sale_id': debt['sale_id'], // Link to sale if applicable
        'notes': debt['notes'], // Optional notes
        'created_by': debt['created_by'],
      });
    });
  }

  /// Record a payment for a debt
  /// Updates debt paid_amount, status, and linked booking automatically
  Future<void> recordDebtPayment({
    required String debtId,
    required int amount, // Amount in kobo
    required String paymentMethod, // 'cash', 'transfer', 'card', 'other'
    required String collectedBy, // UUID of staff who collected payment
    required String createdBy, // UUID of staff who recorded payment
    DateTime? paymentDate,
    String? notes,
  }) async {
    await _retryOperation(() async {
      // Insert payment record (trigger will auto-update debt)
      await _supabase.from('debt_payments').insert({
        'debt_id': debtId,
        'amount': amount,
        'payment_method': paymentMethod.toLowerCase(),
        'payment_date': paymentDate?.toIso8601String().split('T')[0] ?? DateTime.now().toIso8601String().split('T')[0],
        'collected_by': collectedBy,
        'created_by': createdBy,
        'notes': notes,
      });
    });
  }

  /// Record a debt payment claim (staff). Requires management approval before balance is updated.
  Future<void> recordDebtPaymentClaim({
    required String debtId,
    required int amount,
    required String paymentMethod,
    required String recordedBy,
    DateTime? paymentDate,
    String? notes,
  }) async {
    await _retryOperation(() async {
      await _supabase.from('debt_payment_claims').insert({
        'debt_id': debtId,
        'amount': amount,
        'payment_method': paymentMethod.toLowerCase(),
        'payment_date': paymentDate?.toIso8601String().split('T')[0] ?? DateTime.now().toIso8601String().split('T')[0],
        'recorded_by': recordedBy,
        'notes': notes,
        'status': 'pending',
      });
    });
  }

  /// Get debt payment claims (optionally filtered by status)
  Future<List<Map<String, dynamic>>> getDebtPaymentClaims({String? status}) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('debt_payment_claims')
          .select('*, debts(id, debtor_name, debtor_phone, amount, paid_amount, department, source_department, reason), recorded_by_profile:profiles!recorded_by(full_name)');
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }
      final response = await query.order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  /// Approve a debt payment claim: moves it to debt_payments (trigger updates debt)
  Future<void> approveDebtPaymentClaim(String claimId, String approvedBy) async {
    await _retryOperation(() async {
      final claim = await _supabase.from('debt_payment_claims').select().eq('id', claimId).single();
      if (claim['status'] != 'pending') {
        throw Exception('Claim is no longer pending');
      }
      await _supabase.from('debt_payments').insert({
        'debt_id': claim['debt_id'],
        'amount': claim['amount'],
        'payment_method': claim['payment_method'],
        'payment_date': claim['payment_date'],
        'collected_by': claim['recorded_by'],
        'created_by': approvedBy,
        'notes': claim['notes'],
      });
      await _supabase.from('debt_payment_claims').update({
        'status': 'approved',
        'approved_by': approvedBy,
        'approved_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', claimId);
    });
  }

  /// Reject a debt payment claim
  Future<void> rejectDebtPaymentClaim(String claimId, String rejectedBy) async {
    await _retryOperation(() async {
      await _supabase.from('debt_payment_claims').update({
        'status': 'rejected',
        'approved_by': rejectedBy,
        'rejected_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', claimId).eq('status', 'pending');
    });
  }

  /// Get payment history for a debt
  Future<List<Map<String, dynamic>>> getDebtPayments(String debtId) async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('debt_payments')
          .select('*, collected_by_profile:profiles!collected_by(full_name), created_by_profile:profiles!created_by(full_name)')
          .eq('debt_id', debtId)
          .order('payment_date', ascending: false)
          .order('created_at', ascending: false);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  /// Get debt with full details including payment history
  Future<Map<String, dynamic>?> getDebtDetails(String debtId) async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('debts')
          .select('*, sold_by_profile:profiles!sold_by(full_name), created_by_profile:profiles!created_by(full_name)')
          .eq('id', debtId)
          .maybeSingle();
      return response;
    });
  }

  Future<void> updateDebtStatus(String debtId, String status) async {
    await _retryOperation(() async {
      await _supabase
          .from('debts')
          .update({
            'status': status,
            'last_payment_date': status == 'paid' ? DateTime.now().toIso8601String().split('T')[0] : null,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', debtId);
    });
  }

  // Financial Summary
  /// Total Income = Manual Income + Kitchen + Mini Mart + Bar Sales (VIP/Outside) + Room Revenue.
  /// Available Cash = (Opening Balance + Period Inflows) - Period Outflows.
  Future<Map<String, dynamic>> getFinancialSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return await _retryOperation(() async {
      final rangeStart = startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final rangeEnd = endDate ?? DateTime.now();
      final startStr = rangeStart.toIso8601String().split('T')[0];
      final endStr = rangeEnd.toIso8601String().split('T')[0];

      // 1. Manual income records
      final incomeResp = await _supabase
          .from('income_records')
          .select('amount')
          .gte('date', startStr)
          .lte('date', endStr);
      var totalIncome = (incomeResp as List).fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));

      // 2. Department sales (Kitchen, Mini Mart, VIP Bar, Outside Bar) - try department_sales first
      int deptSalesTotal = 0;
      try {
        final deptResp = await _supabase
            .from('department_sales')
            .select('department, total_sales')
            .inFilter('department', ['vip_bar', 'outside_bar', 'mini_mart', 'restaurant'])
            .gte('date', startStr)
            .lte('date', endStr);
        for (final r in deptResp as List) {
          deptSalesTotal += (r['total_sales'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
      if (deptSalesTotal == 0) {
        try {
          final kResp = await _supabase
              .from('kitchen_sales')
              .select('total_amount')
              .gte('created_at', rangeStart.toIso8601String())
              .lte('created_at', rangeEnd.toIso8601String());
          for (final r in kResp as List) {
            deptSalesTotal += (r['total_amount'] as num?)?.toInt() ?? 0;
          }
          final mmResp = await _supabase
              .from('mini_mart_sales')
              .select('total_amount')
              .gte('sale_date', startStr)
              .lte('sale_date', endStr);
          for (final r in mmResp as List) {
            deptSalesTotal += (r['total_amount'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {}
      }
      totalIncome += deptSalesTotal.toDouble();

      // 3. Room booking revenue (checked-out bookings)
      int roomRevenue = 0;
      try {
        final bookResp = await _supabase
            .from('bookings')
            .select('total_amount, paid_amount')
            .inFilter('status', ['Checked-out', 'checked_out', 'checked-out', 'Checked out', 'checked out'])
            .gte('check_out_date', startStr)
            .lte('check_out_date', endStr);
        for (final b in bookResp as List) {
          final total = (b['total_amount'] as num?)?.toInt();
          final paid = (b['paid_amount'] as num?)?.toInt() ?? 0;
          roomRevenue += total ?? paid;
        }
      } catch (_) {}
      totalIncome += roomRevenue.toDouble();

      // 4. Period expenses (all, for P&L display)
      final expensesResp = await _supabase
          .from('expenses')
          .select('amount')
          .gte('transaction_date', startStr)
          .lte('transaction_date', endStr);
      final totalExpenses = (expensesResp as List).fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));

      // 5. Cash outflows: Approved expenses + approved payroll
      var approvedExpenses = 0.0;
      var approvedPayroll = 0.0;
      try {
        final expApproved = await _supabase
            .from('expenses')
            .select('amount')
            .gte('transaction_date', startStr)
            .lte('transaction_date', endStr)
            .eq('status', 'Approved');
        approvedExpenses = (expApproved as List).fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));
      } catch (_) {}
      try {
        final payrollResp = await _supabase
            .from('payroll_records')
            .select('amount')
            .gte('month', startStr)
            .lte('month', endStr)
            .eq('approval_status', 'approved');
        approvedPayroll = (payrollResp as List).fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));
      } catch (_) {}
      final totalOutflows = approvedExpenses + approvedPayroll;

      // 6. Available Cash: (Opening Balance + Period Inflows) - Period Outflows
      final opening = await _computeOpeningCashBalance(startStr);
      final periodInflows = totalIncome;
      final availableCash = opening + periodInflows - totalOutflows;

      return {
        'total_income': totalIncome,
        'total_expenses': totalExpenses,
        'net_profit': totalIncome - totalExpenses,
        'available_cash': availableCash,
      };
    });
  }

  /// Opening balance = sum of all inflows - outflows from beginning until (excluding) startDate.
  Future<double> _computeOpeningCashBalance(String beforeDate) async {
    try {
      double inflows = 0;
      double outflows = 0;
      final incomeResp = await _supabase
          .from('income_records')
          .select('amount')
          .lt('date', beforeDate);
      inflows += (incomeResp as List).fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));

      int deptSales = 0;
      try {
        final deptResp = await _supabase
            .from('department_sales')
            .select('total_sales')
            .inFilter('department', ['vip_bar', 'outside_bar', 'mini_mart', 'restaurant'])
            .lt('date', beforeDate);
        for (final r in deptResp as List) {
          deptSales += (r['total_sales'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
      if (deptSales == 0) {
        try {
          final kResp = await _supabase.from('kitchen_sales').select('total_amount').lt('created_at', '${beforeDate}T00:00:00');
          for (final r in kResp as List) {
            deptSales += (r['total_amount'] as num?)?.toInt() ?? 0;
          }
          final mmResp = await _supabase.from('mini_mart_sales').select('total_amount').lt('sale_date', beforeDate);
          for (final r in mmResp as List) {
            deptSales += (r['total_amount'] as num?)?.toInt() ?? 0;
          }
        } catch (_) {}
      }
      inflows += deptSales.toDouble();

      try {
        final bookResp = await _supabase
            .from('bookings')
            .select('total_amount, paid_amount')
            .inFilter('status', ['Checked-out', 'checked_out', 'checked-out', 'Checked out', 'checked out'])
            .lt('check_out_date', beforeDate);
        for (final b in bookResp as List) {
          final total = (b['total_amount'] as num?)?.toInt();
          final paid = (b['paid_amount'] as num?)?.toInt() ?? 0;
          inflows += (total ?? paid).toDouble();
        }
      } catch (_) {}

      final expResp = await _supabase
          .from('expenses')
          .select('amount')
          .lt('transaction_date', beforeDate)
          .eq('status', 'Approved');
      outflows += (expResp as List).fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));

      try {
        final payResp = await _supabase
            .from('payroll_records')
            .select('amount')
            .lt('month', beforeDate)
            .eq('approval_status', 'approved');
        outflows += (payResp as List).fold<double>(0, (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0));
      } catch (_) {}

      return inflows - outflows;
    } catch (_) {
      return 0;
    }
  }

  /// Department Performance based on actual operational sales (getDepartmentSales).
  /// Uses department_sales / kitchen_sales / mini_mart_sales, plus expenses by department.
  Future<List<Map<String, dynamic>>> getDepartmentPerformance({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return await _retryOperation(() async {
      final rangeStart = startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final rangeEnd = endDate ?? DateTime.now();
      final startStr = rangeStart.toIso8601String().split('T')[0];
      final endStr = rangeEnd.toIso8601String().split('T')[0];

      // 1. Operational sales by department (department_sales, with fallbacks)
      final Map<String, double> revenueByDept = {};
      try {
        final deptResp = await _supabase
            .from('department_sales')
            .select('department, total_sales')
            .inFilter('department', ['vip_bar', 'outside_bar', 'mini_mart', 'restaurant'])
            .gte('date', startStr)
            .lte('date', endStr);
        for (final r in deptResp as List) {
          final dept = (r['department'] as String?) ?? 'Other';
          final amt = (r['total_sales'] as num?)?.toDouble() ?? 0.0;
          revenueByDept[dept] = (revenueByDept[dept] ?? 0) + amt;
        }
      } catch (_) {}
      if (revenueByDept.isEmpty || revenueByDept.values.every((v) => v == 0)) {
        try {
          final kResp = await _supabase
              .from('kitchen_sales')
              .select('total_amount')
              .gte('created_at', rangeStart.toIso8601String())
              .lte('created_at', rangeEnd.toIso8601String());
          var kitchenTotal = 0.0;
          for (final r in kResp as List) {
            kitchenTotal += (r['total_amount'] as num?)?.toDouble() ?? 0;
          }
          if (kitchenTotal > 0) revenueByDept['restaurant'] = kitchenTotal;
          final mmResp = await _supabase
              .from('mini_mart_sales')
              .select('total_amount')
              .gte('sale_date', startStr)
              .lte('sale_date', endStr);
          var mmTotal = 0.0;
          for (final r in mmResp as List) {
            mmTotal += (r['total_amount'] as num?)?.toDouble() ?? 0;
          }
          if (mmTotal > 0) revenueByDept['mini_mart'] = mmTotal;
        } catch (_) {}
      }

      // 2. Expenses by department
      final Map<String, double> expensesByDept = {};
      try {
        final expenses = await _supabase
            .from('expenses')
            .select('department, amount')
            .gte('transaction_date', startStr)
            .lte('transaction_date', endStr);
        for (var expense in expenses as List) {
          final dept = (expense['department'] as String?) ?? 'Other';
          final amount = (expense['amount'] as num?)?.toDouble() ?? 0.0;
          expensesByDept[dept] = (expensesByDept[dept] ?? 0) + amount;
        }
      } catch (_) {}

      final allDepartments = <String>{...revenueByDept.keys, ...expensesByDept.keys};
      if (allDepartments.isEmpty) return [];

      const displayNames = {
        'vip_bar': 'VIP Bar',
        'outside_bar': 'Outside Bar',
        'mini_mart': 'Mini Mart',
        'restaurant': 'Kitchen',
        'other': 'Other (Miscellaneous)',
      };

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
          'department': displayNames[dept] ?? dept,
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
          .order('name')
          .limit(500); // Limit for performance
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<List<Map<String, dynamic>>> getMiniMartSales({
    DateTime? startDate,
    DateTime? endDate,
    String? staffId,
    int limit = 1000,
    int offset = 0,
  }) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('mini_mart_sales')
          .select('*, mini_mart_items(name, price), sold_by_profile:profiles!sold_by(full_name)');

      if (startDate != null) {
        query = query.gte('sale_date', startDate.toIso8601String().split('T')[0]);
      }
      if (endDate != null) {
        query = query.lte('sale_date', endDate.toIso8601String().split('T')[0]);
      }
      if (staffId != null && staffId != 'all') {
        query = query.eq('sold_by', staffId);
      }

      final response = await query
          .order('sale_date', ascending: false)
          .range(offset, offset + limit - 1);
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
          .select('id, name, price, department, barcode, stock_item_id')
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
          .eq('status', 'Checked-in');
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // Checked-in Guests
  Future<List<Map<String, dynamic>>> getCheckedInGuests() async {
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: 'getCheckedInGuests',
      tables: const ['bookings'],
      fetch: () => _retryOperation(() async {
        final response = await _supabase
            .from('bookings')
            .select('id, guest_name, rooms!inner(room_number), created_by, check_in_date')
            .eq('status', 'Checked-in')
            .order('check_in_date', ascending: false);
        return List<Map<String, dynamic>>.from(response);
      }),
    );
  }

  // Department Sales
  Future<List<Map<String, dynamic>>> getDepartmentSales({
    String? department,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 1000,
  }) async {
    final key = 'getDepartmentSales:$department:${startDate?.toIso8601String()}:${endDate?.toIso8601String()}:$limit';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['department_sales'],
      fetch: () => _retryOperation(() async {
        var query = _supabase
            .from('department_sales')
            .select();
        if (department != null && department.isNotEmpty) {
          query = query.eq('department', department);
        }
        if (startDate != null && endDate != null) {
          final startCalendarDate = startDate.toIso8601String().split('T')[0];
          final endCalendarDate = endDate.toIso8601String().split('T')[0];
          query = query.gte('date', startCalendarDate).lte('date', endCalendarDate);
        } else if (startDate != null) {
          query = query.gte('date', startDate.toIso8601String().split('T')[0]);
        } else if (endDate != null) {
          query = query.lte('date', endDate.toIso8601String().split('T')[0]);
        }
        final response = await query
            .order('date', ascending: false)
            .limit(limit);
        return List<Map<String, dynamic>>.from(response);
      }),
    );
  }

  Future<List<Map<String, dynamic>>> getDepartmentSalesByDepartment(String department) async {
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

  // Recent Purchases (purchase_orders level: supplier_name, total_cost, created_at; items in purchase_order_items)
  Future<List<Map<String, dynamic>>> getRecentPurchases() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('purchase_orders')
          .select(
            'id, created_at, supplier_name, total_cost, status, purchaser_name, '
            'purchase_order_items(quantity, stock_items(name)), profiles!purchaser_id(full_name)',
          )
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  // HR methods
  Future<void> assignRoleToStaff(String staffId, String role, {bool isTemporary = false, DateTime? expiryDate}) async {
    await _retryOperation(() async {
      final assignedBy = _supabase.auth.currentUser?.id;
      if (assignedBy == null) {
        throw Exception('No active user session found');
      }

      if (!isTemporary) {
        await _supabase
            .from('profiles')
            .update({
              'roles': [role],
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', staffId);
      }

      await _supabase.from('staff_role_assignments').insert({
        'staff_id': staffId,
        'assigned_role': role,
        'assigned_by': assignedBy,
        'start_date': DateTime.now().toIso8601String().split('T')[0],
        'end_date': expiryDate?.toIso8601String().split('T')[0],
        'is_active': true,
        'notes': isTemporary ? 'Temporary role assignment' : 'Permanent role assignment',
      });
    });
  }

  // Department Transfers (Kitchen Dispatch)
  Future<List<Map<String, dynamic>>> getDepartmentTransfers({
    DateTime? startDate,
    DateTime? endDate,
    String? staffId,
    String? destinationDepartment,
    String? paymentStatus,
    int limit = 1000,
    int offset = 0,
  }) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('department_transfers')
          .select('*, menu_items(name), dispatched_by_profile:profiles!dispatched_by_id(full_name), bookings(id, guest_name, rooms(room_number))');

      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate.toIso8601String());
      }
      if (staffId != null && staffId != 'all') {
        query = query.eq('dispatched_by_id', staffId);
      }
      if (destinationDepartment != null && destinationDepartment != 'all') {
        query = query.eq('destination_department', destinationDepartment);
      }
      if (paymentStatus != null && paymentStatus != 'all') {
        query = query.eq('payment_status', paymentStatus);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<String> createDepartmentTransfer(Map<String, dynamic> transfer) async {
    return await _retryOperation(() async {
      final response = await _supabase.from('department_transfers').insert({
        'source_department': transfer['source_department'],
        'destination_department': transfer['destination_department'],
        'menu_item_id': transfer['menu_item_id'],
        'quantity': transfer['quantity'],
        'dispatched_by_id': transfer['dispatched_by_id'],
        'status': transfer['status'] ?? 'Pending',
        'unit_price': transfer['unit_price'],
        'total_amount': transfer['total_amount'],
        'payment_method': transfer['payment_method'],
        'payment_status': transfer['payment_status'],
        'booking_id': transfer['booking_id'],
        'notes': transfer['notes'],
      }).select('id').single();
      return response['id'] as String;
    });
  }

  // Kitchen Sales (dedicated history)
  Future<List<Map<String, dynamic>>> getKitchenSalesHistory({
    DateTime? startDate,
    DateTime? endDate,
    String? staffId,
    String? paymentMethod,
    int limit = 1000,
    int offset = 0,
  }) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('kitchen_sales')
          .select('*, menu_items(name), sold_by_profile:profiles!sold_by(full_name), bookings(id, guest_name, rooms(room_number))');

      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('created_at', endDate.toIso8601String());
      }
      if (staffId != null && staffId != 'all') {
        query = query.eq('sold_by', staffId);
      }
      if (paymentMethod != null && paymentMethod != 'all') {
        query = query.eq('payment_method', paymentMethod);
      }

      final response = await query
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);
      return List<Map<String, dynamic>>.from(response);
    });
  }

  Future<String> createKitchenSale(Map<String, dynamic> sale) async {
    return await _retryOperation(() async {
      final response = await _supabase.from('kitchen_sales').insert({
        'menu_item_id': sale['menu_item_id'],
        'item_name': sale['item_name'],
        'quantity': sale['quantity'],
        'unit_price': sale['unit_price'],
        'total_amount': sale['total_amount'],
        'payment_method': sale['payment_method'],
        'booking_id': sale['booking_id'],
        'sold_by': sale['sold_by'],
        'notes': sale['notes'],
      }).select('id').single();
      return response['id'] as String;
    });
  }

  // Maintenance Work Orders
  Future<List<Map<String, dynamic>>> getMaintenanceWorkOrders({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 200,
  }) async {
    final key = 'getMaintenanceWorkOrders:${startDate?.toIso8601String()}:${endDate?.toIso8601String()}:$limit';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['maintenance_work_orders'],
      fetch: () => _retryOperation(() async {
        var query = _supabase
            .from('maintenance_work_orders')
            .select('*, assets(name), reported_by:profiles!reported_by_id(full_name), assigned_to:profiles!assigned_to(full_name)');
        if (startDate != null) {
          query = query.gte('created_at', startDate.toIso8601String());
        }
        if (endDate != null) {
          query = query.lte('created_at', endDate.toIso8601String());
        }
        final response = await query
            .order('created_at', ascending: false)
            .limit(limit);
        return List<Map<String, dynamic>>.from(response);
      }),
    );
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
  Future<List<Map<String, dynamic>>> getPurchaseOrders({
    String? status,
    DateTime? startDate,
    DateTime? endDate,
    int limit = 200,
  }) async {
    final key = 'getPurchaseOrders:$status:${startDate?.toIso8601String()}:${endDate?.toIso8601String()}:$limit';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['purchase_orders'],
      fetch: () => _retryOperation(() async {
        var query = _supabase
            .from('purchase_orders')
            .select(
              '*, purchase_order_items(*, stock_items(name, unit)), purchaser:profiles!purchaser_id(full_name), storekeeper:profiles!storekeeper_id(full_name)',
            );
        if (status != null && status.isNotEmpty) {
          query = query.eq('status', status);
        }
        if (startDate != null) {
          query = query.gte('created_at', startDate.toIso8601String());
        }
        if (endDate != null) {
          query = query.lte('created_at', endDate.toIso8601String());
        }
        final response = await query
            .order('created_at', ascending: false)
            .limit(limit);
        return List<Map<String, dynamic>>.from(response);
      }),
    );
  }

  Future<Map<String, dynamic>?> getMonthlyPurchaseBudget(DateTime monthStart) async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('purchase_budgets')
          .select()
          .eq('month_start', monthStart.toIso8601String().split('T')[0])
          .maybeSingle();
      if (response == null) return null;
      return Map<String, dynamic>.from(response);
    });
  }

  Future<void> upsertMonthlyPurchaseBudget({
    required DateTime monthStart,
    required int amountKobo,
    required String updatedBy,
  }) async {
    await _retryOperation(() async {
      await _supabase.from('purchase_budgets').upsert({
        'month_start': monthStart.toIso8601String().split('T')[0],
        'amount': amountKobo,
        'updated_by': updatedBy,
      }, onConflict: 'month_start');
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
          .select('*, staff:profiles!staff_id(full_name), assigned_by:profiles!assigned_by(full_name)')
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
  Future<Map<String, dynamic>?> getActiveShift({
    required String bartenderId,
    required String bar,
  }) async {
    return await _retryOperation(() async {
      final today = DateTime.now();
      final startOfDay = DateTime(today.year, today.month, today.day);
      
      final response = await _supabase
          .from('bartender_shifts')
          .select('*, profiles!bartender_id(full_name)')
          .eq('bartender_id', bartenderId)
          .eq('bar', bar)
          .eq('status', 'active')
          .gte('start_time', startOfDay.toIso8601String())
          .maybeSingle();
      if (response == null) return null;
      final mapped = Map<String, dynamic>.from(response);
      final profile = response['profiles'] as Map<String, dynamic>?;
      if (profile != null) {
        mapped['staff_name'] = profile['full_name'];
      }
      return mapped;
    });
  }

  Future<void> startShift({
    required String bartenderId,
    required String bar,
    List<Map<String, dynamic>>? openingStock,
    int? openingCash,
  }) async {
    await _retryOperation(() async {
      await _supabase.from('bartender_shifts').insert({
        'bartender_id': bartenderId,
        'bar': bar,
        'opening_cash': openingCash ?? 0,
        'opening_stock': openingStock ?? [],
        'transfers': [],
        'closing_stock': [],
        'status': 'active',
        'start_time': DateTime.now().toIso8601String(),
        'date': DateTime.now().toIso8601String().split('T')[0],
      });
    });
  }

  Future<void> endShift({
    required String shiftId,
    List<Map<String, dynamic>>? closingStock,
    List<Map<String, dynamic>>? transfers,
    int? closingCash,
    int? totalSales,
    String? closedBy,
  }) async {
    await _retryOperation(() async {
      await _supabase
          .from('bartender_shifts')
          .update({
            'closing_cash': closingCash,
            'total_sales': totalSales,
            'closing_stock': closingStock ?? [],
            'transfers': transfers ?? [],
            'status': 'closed',
            'end_time': DateTime.now().toIso8601String(),
            'closed_by': closedBy,
          })
          .eq('id', shiftId);
    });
  }

  Future<void> createDirectSupplyRequest({
    required String stockItemId,
    required String bar,
    required int quantity,
    required String requestedBy,
    String? notes,
  }) async {
    await _retryOperation(() async {
      await _supabase.from('direct_supply_requests').insert({
        'stock_item_id': stockItemId,
        'bar': bar,
        'quantity': quantity,
        'requested_by': requestedBy,
        'notes': notes,
        'status': 'pending',
      });
    });
  }

  Future<List<Map<String, dynamic>>> getDirectSupplyRequests({
    String? status,
    String? bar,
  }) async {
    final key = 'getDirectSupplyRequests:$status:$bar';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['direct_supply_requests'],
      fetch: () => _retryOperation(() async {
        var query = _supabase
            .from('direct_supply_requests')
            .select(
              '*, stock_items(name), requested_by_profile:profiles!requested_by(full_name), approved_by_profile:profiles!approved_by(full_name)',
            );
        if (status != null) {
          query = query.eq('status', status);
        }
        if (bar != null) {
          query = query.eq('bar', bar);
        }
        final response = await query.order('created_at', ascending: false);
        return List<Map<String, dynamic>>.from(response);
      }),
    );
  }

  Future<void> approveDirectSupplyRequest({
    required String requestId,
    required bool approve,
    String? notes,
  }) async {
    await _retryOperation(() async {
      await _supabase.rpc('approve_direct_supply', params: {
        'p_request_id': requestId,
        'p_action': approve ? 'approve' : 'deny',
        'p_notes': notes,
      });
    });
  }

  Future<void> updateShiftTransfers({
    required String shiftId,
    required List<Map<String, dynamic>> transfers,
  }) async {
    await _retryOperation(() async {
      await _supabase
          .from('bartender_shifts')
          .update({'transfers': transfers, 'updated_at': DateTime.now().toIso8601String()})
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
          .limit(500); // Limit for performance
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
    String? userId, // Optional: if provided, use it directly instead of querying
  }) async {
    return await _retryOperation(() async {
      // Always use the database function instead of direct UPDATE
      // The function uses SECURITY DEFINER and bypasses RLS, which is more reliable
      // especially after signOut() when the session might be lost
      final response = await _supabase.rpc('create_staff_profile', params: {
        'p_email': email,
        'p_full_name': fullName,
        'p_phone': phone,
        'p_role': role,
        'p_department': department,
      });
      
      // Get the created/updated profile
      // Use userId if provided, otherwise use email
      final profile = userId != null
          ? await _supabase
              .from('profiles')
              .select()
              .eq('id', userId)
              .single()
          : await _supabase
              .from('profiles')
              .select()
              .eq('email', email)
              .single();
      
      return Map<String, dynamic>.from(profile);
    });
  }

  // Position management
  Future<void> createPosition(Map<String, dynamic> position) async {
    await _retryOperation(() async {
      await _supabase.from('positions').insert({
        'name': position['name'],
        'benefits': position['benefits'],
        'department': position['department'],
        'created_by': position['created_by'],
      });
    });
  }

  Future<List<Map<String, dynamic>>> getPositions() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('positions')
          .select()
          .order('name')
          .limit(100);
      return List<Map<String, dynamic>>.from(response);
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

}
