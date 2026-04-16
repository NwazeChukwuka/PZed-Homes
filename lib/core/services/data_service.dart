import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pzed_homes/core/utils/room_number_sort.dart';

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
      throw Exception('Service is currently unavailable. Please try again.');
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
        // Reconcile stale records where room is already assigned but booking stayed pending.
        await _supabase.rpc('reconcile_assigned_bookings');
      } catch (_) {
        // Backward-compatible fallback when migration function is not yet available.
        try {
          await _supabase
              .from('bookings')
              .update({
                'status': 'Checked-in',
                'updated_at': DateTime.now().toIso8601String(),
              })
              .inFilter('status', ['Pending Check-in', 'pending check-in', 'pending_check_in', 'pending'])
              .not('room_id', 'is', null);
        } catch (e, stack) {
          if (kDebugMode) debugPrint('DEBUG reconcile_assigned_bookings fallback: $e\n$stack');
        }
      }

      try {
        await _supabase.rpc('auto_update_expired_bookings');
      } catch (e, stack) {
        if (kDebugMode) debugPrint('DEBUG auto_update_expired_bookings: $e\n$stack');
      }
    });
  }

  /// Fetches bookings with pagination. Use limit 20-50 per page for list screens.
  /// Each page is cached separately; invalidate via invalidateCacheForTable('bookings').
  /// When [filterByStayOverlap] is true, [startDate] and [endDate] filter by stay overlap
  /// (check_out_date >= startDate AND check_in_date <= endDate) instead of created_at.
  /// Use this for dashboard to fetch only bookings overlapping a date range (~20-50 rows).
  Future<List<Map<String, dynamic>>> getBookings({
    DateTime? startDate,
    DateTime? endDate,
    String? createdBy,
    int limit = 1000,
    int offset = 0,
    bool filterByStayOverlap = false,
  }) async {
    final key = 'getBookings:${startDate?.toIso8601String()}:${endDate?.toIso8601String()}:$createdBy:$limit:$offset:$filterByStayOverlap';
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
          if (startDate != null && endDate != null) {
            if (filterByStayOverlap) {
              final startStr = startDate.toIso8601String().split('T')[0];
              final endStr = endDate.toIso8601String().split('T')[0];
              query = query
                  .gte('check_out_date', startStr)
                  .lte('check_in_date', endStr);
            } else {
              query = query
                  .gte('created_at', startDate.toIso8601String())
                  .lte('created_at', endDate.toIso8601String());
            }
          } else if (startDate != null) {
            if (filterByStayOverlap) {
              final startStr = startDate.toIso8601String().split('T')[0];
              query = query.gte('check_out_date', startStr);
            } else {
              query = query.gte('created_at', startDate.toIso8601String());
            }
          } else if (endDate != null) {
            if (filterByStayOverlap) {
              final endStr = endDate.toIso8601String().split('T')[0];
              query = query.lte('check_in_date', endStr);
            } else {
              query = query.lte('created_at', endDate.toIso8601String());
            }
          }
          if (createdBy != null && createdBy.isNotEmpty) {
            query = query.eq('created_by', createdBy);
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

  /// Atomically creates a staff booking as [Checked-in] and marks the room [Occupied]
  /// (see `staff_create_booking_and_check_in` in non_destructive_upgrade.sql).
  Future<String> staffCreateBookingAndCheckIn({
    required String roomId,
    String? requestedRoomType,
    required DateTime checkIn,
    required DateTime checkOut,
    required int totalAmountKobo,
    required int paidAmountKobo,
    required String paymentMethod,
    String? guestName,
    String? guestPhone,
    String? guestEmail,
    bool discountApplied = false,
    int discountAmountKobo = 0,
    double discountPercentage = 0,
    String? discountReason,
    String? discountAppliedByProfileId,
  }) async {
    return await _retryOperation(() async {
      final res = await _supabase.rpc(
        'staff_create_booking_and_check_in',
        params: {
          'p_room_id': roomId,
          'p_requested_room_type': requestedRoomType,
          'p_check_in_date': checkIn.toIso8601String(),
          'p_check_out_date': checkOut.toIso8601String(),
          'p_total_amount': totalAmountKobo,
          'p_paid_amount': paidAmountKobo,
          'p_payment_method': paymentMethod,
          'p_guest_name': guestName,
          'p_guest_phone': guestPhone,
          'p_guest_email': guestEmail,
          'p_discount_applied': discountApplied,
          'p_discount_amount': discountAmountKobo,
          'p_discount_percentage': discountPercentage,
          'p_discount_reason': discountReason,
          'p_discount_applied_by': discountAppliedByProfileId,
        },
      );
      final id = res?.toString();
      if (id == null || id.isEmpty) {
        throw Exception('Booking was not created. Please try again.');
      }
      return id;
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

  /// Updates a room type's price (in kobo). Management only.
  Future<void> updateRoomTypePrice(String typeId, int priceKobo) async {
    await _retryOperation(() async {
      await _supabase
          .from('room_types')
          .update({'price': priceKobo, 'updated_at': DateTime.now().toIso8601String()})
          .eq('id', typeId);
    });
    invalidateCacheForTable('room_types');
  }

  // Rooms
  /// Returns room IDs that currently have a Checked-in booking (for dynamic status display).
  Future<Set<String>> getCheckedInRoomIds() async {
    return _retryOperation(() async {
      final response = await _supabase
          .from('bookings')
          .select('room_id')
          .inFilter('status', ['Checked-in', 'checked_in', 'Checked_in'])
          .not('room_id', 'is', null);
      final ids = <String>{};
      for (final row in response as List) {
        final id = row['room_id']?.toString();
        if (id != null && id.isNotEmpty) ids.add(id);
      }
      return ids;
    });
  }

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
        final list = List<Map<String, dynamic>>.from(response);
        // Postgres TEXT room_number sorts lexicographically; normalize to numeric 101→212 for UI parity.
        sortRoomMapsByNumber(list);
        return list;
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

  /// Adds a room. [typeId] and [type] from room_types; [type] is the display name (e.g. "Classic Room").
  Future<void> addRoom({
    required String roomNumber,
    required String typeId,
    required String type,
    String? floor,
    String status = 'Vacant',
  }) async {
    await _retryOperation(() async {
      final payload = <String, dynamic>{
        'room_number': roomNumber.trim(),
        'type_id': typeId,
        'type': type,
        'status': status,
      };
      if (floor != null && floor.trim().isNotEmpty) {
        final floorNum = int.tryParse(floor.trim());
        if (floorNum != null) payload['floor'] = floorNum;
      }
      await _supabase.from('rooms').insert(payload);
    });
    invalidateCacheForTable('rooms');
  }

  /// Logs an operational activity for audit. Call after successful Add/Update in Inventory, Kitchen, Reception, MiniMart.
  /// [staffProfileId] must be a valid profiles.id (e.g. from StaffAuthHelper.requireStaffProfileId at call site).
  /// No-op if [staffProfileId] is null or empty.
  Future<void> logActivity(
    String? staffProfileId,
    String action,
    String department,
    String details,
  ) async {
    if (staffProfileId == null || staffProfileId.isEmpty) return;
    await _retryOperation(() async {
      await _supabase.from('staff_activities').insert({
        'staff_profile_id': staffProfileId,
        'action': action,
        'department': department,
        'details': details,
      });
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
      return response['id']?.toString() ?? '';
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

  // Staff Profiles (using profiles table with role filtering).
  // Excludes guests and owners; owners are administrative only, not employable staff.
  Future<List<Map<String, dynamic>>> getStaffProfiles() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('profiles')
          .select()
          .neq('roles', ['guest']) // Exclude guests
          .eq('status', 'Active') // Only active staff
          .order('full_name')
          .limit(500); // Limit for performance
      final list = List<Map<String, dynamic>>.from(response);
      // Exclude owner: owners are not staff (no payroll, suspend, sack, etc.)
      return list.where((p) {
        final roles = (p['roles'] as List<dynamic>? ?? [])
            .map((e) => e.toString().toLowerCase())
            .toList();
        return !roles.contains('owner');
      }).toList();
    });
  }

  /// Guest-only profiles (single role `guest`) for hire-from-guest conversion.
  Future<List<Map<String, dynamic>>> getGuestProfilesForHiring() async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('profiles')
          .select('id, full_name, email, phone, roles, status')
          .eq('status', 'Active')
          .contains('roles', ['guest'])
          .order('full_name')
          .limit(500);
      final list = List<Map<String, dynamic>>.from(response);
      return list.where(_profileIsGuestOnly).toList();
    });
  }

  static bool _profileIsGuestOnly(Map<String, dynamic> p) {
    final roles = (p['roles'] as List<dynamic>? ?? [])
        .map((e) => e.toString().toLowerCase().trim())
        .where((r) => r.isNotEmpty)
        .toList();
    return roles.length == 1 && roles.first == 'guest';
  }

  /// Sum of positive (total_amount - paid_amount) across all bookings for this guest (kobo).
  Future<int> getGuestOutstandingBalanceKobo(String guestProfileId) async {
    return await _retryOperation(() async {
      final response = await _supabase
          .from('bookings')
          .select('total_amount, paid_amount')
          .eq('guest_profile_id', guestProfileId);
      final rows = List<Map<String, dynamic>>.from(response as List);
      var sum = 0;
      for (final b in rows) {
        final total = (b['total_amount'] as num?)?.toInt() ?? 0;
        final paid = (b['paid_amount'] as num?)?.toInt() ?? 0;
        final diff = total - paid;
        if (diff > 0) sum += diff;
      }
      return sum;
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

  /// Adds an inventory item (bar sellable product). Optionally link to an existing
  /// [stock_item_id] for stock tracking; if provided, stock levels will use that stock item.
  Future<void> addInventoryItem(Map<String, dynamic> item) async {
    await _retryOperation(() async {
      final payload = <String, dynamic>{
        'name': item['name'],
        'description': item['description'],
        'unit': item['unit'],
        'vip_bar_price': item['vip_bar_price'],
        'outside_bar_price': item['outside_bar_price'],
        'category': item['category'],
        'department': item['department'] ?? 'both',
      };
      final stockItemId = item['stock_item_id'] as String?;
      if (stockItemId != null && stockItemId.isNotEmpty) {
        payload['stock_item_id'] = stockItemId;
      }
      await _supabase.from('inventory_items').insert(payload);
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

  Future<bool> claimClientMutationRequest({
    required String requestId,
    required String kind,
    required String staffProfileId,
  }) async {
    return _retryOperation(() async {
      final res = await _supabase.rpc(
        'claim_client_mutation_request',
        params: {
          'p_id': requestId,
          'p_kind': kind,
          'p_staff_id': staffProfileId,
        },
      );
      if (res is bool) return res;
      return res == true;
    });
  }

  /// Single atomic sale mutation across flow-specific tables and department totals.
  /// Returns {applied: bool, duplicate: bool, ...}.
  Future<Map<String, dynamic>> processUnifiedSale({
    required List<Map<String, dynamic>> items,
    required Map<String, dynamic> paymentData,
    required String transactionId,
  }) async {
    return _retryOperation(() async {
      final res = await _supabase.rpc(
        'process_unified_sale',
        params: {
          'p_items': items,
          'p_payment_data': paymentData,
          'p_transaction_id': transactionId,
        },
      );
      if (res is Map<String, dynamic>) return res;
      if (res is Map) return Map<String, dynamic>.from(res);
      throw Exception('Invalid unified sale response from server');
    });
  }

  /// Ledger insert for storekeeper restock. [clientRequestId] enables server-side deduplication.
  /// Returns false if this request id was already applied.
  Future<bool> recordDirectStockEntry({
    required String clientRequestId,
    required String stockItemId,
    required String locationId,
    required String staffProfileId,
    required int quantity,
    String? notes,
  }) async {
    return _retryOperation(() async {
      final res = await _supabase.rpc(
        'record_direct_stock_entry',
        params: {
          'p_client_request_id': clientRequestId,
          'p_staff_profile_id': staffProfileId,
          'p_stock_item_id': stockItemId,
          'p_location_id': locationId,
          'p_quantity': quantity,
          'p_notes': notes,
        },
      );
      if (res is bool) return res;
      return res == true;
    });
  }

  Future<bool> recordStockTransaction(Map<String, dynamic> transaction) async {
    return await _retryOperation(() async {
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
      return true;
    });
  }

  // Stock Transfers (Main Store -> Department)
  /// Returns null if [clientRequestId] was already used (idempotent duplicate).
  Future<String?> createStockTransfer({
    required String stockItemId,
    required String sourceLocationId,
    required String destinationLocationId,
    required int quantity,
    required String issuedById,
    required String receivedById,
    String? notes,
    String? clientRequestId,
  }) async {
    return _retryOperation(() async {
      final params = <String, dynamic>{
        'p_stock_item_id': stockItemId,
        'p_source_location_id': sourceLocationId,
        'p_destination_location_id': destinationLocationId,
        'p_quantity': quantity,
        'p_issued_by_id': issuedById,
        'p_received_by_id': receivedById,
        'p_notes': notes,
      };
      if (clientRequestId != null && clientRequestId.isNotEmpty) {
        params['p_client_request_id'] = clientRequestId;
      }
      final res = await _supabase.rpc('create_stock_transfer', params: params);
      if (res == null) return null;
      return res.toString();
    });
  }

  // Financial Data
  /// When [light] is true, only fetches columns needed for dashboard totals (smaller payload).
  /// Default false for Finance screen and other callers that need full rows (e.g. description).
  Future<List<Map<String, dynamic>>> getExpenses({
    DateTime? startDate,
    DateTime? endDate,
    String? status,
    int limit = 200,
    bool light = false,
  }) async {
    final key = 'getExpenses:${startDate?.toIso8601String()}:${endDate?.toIso8601String()}:$status:$limit:$light';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['expenses'],
      fetch: () => _retryOperation(() async {
        final select = light
            ? 'id, amount, transaction_date, department, category, status'
            : '*';
        var query = _supabase.from('expenses').select(select);
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

  /// When [light] is true, only fetches id, amount, date (smaller payload for dashboard).
  /// Default false for Finance screen and other callers that need full rows.
  Future<List<Map<String, dynamic>>> getIncomeRecords({
    DateTime? startDate,
    DateTime? endDate,
    int limit = 200,
    bool light = false,
  }) async {
    final key = 'getIncomeRecords:${startDate?.toIso8601String()}:${endDate?.toIso8601String()}:$limit:$light';
    return _cache.getOrFetch<List<Map<String, dynamic>>>(
      key: key,
      tables: const ['income_records'],
      fetch: () => _retryOperation(() async {
        final select = light ? 'id, amount, date' : '*';
        var query = _supabase.from('income_records').select(select);
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
      final monthRaw = payroll['month']?.toString();
      final monthDate = DateTime.tryParse(monthRaw ?? '');
      final monthStart = monthDate == null
          ? monthRaw
          : DateTime(monthDate.year, monthDate.month, 1)
              .toIso8601String()
              .split('T')[0];

      final response = await _supabase.rpc('create_payroll_record', params: {
        'p_staff_id': payroll['staff_id'],
        'p_amount': payroll['amount'],
        'p_month': monthStart,
        'p_payment_method': payroll['payment_method'] ?? 'bank_transfer',
        'p_notes': payroll['notes'],
        'p_processed_by': payroll['processed_by'],
        'p_approval_status': payroll['approval_status'] ?? 'pending',
        // Optional idempotency key if caller provides one.
        'p_client_request_id': payroll['client_request_id'],
      });

      final mapped = response is Map<String, dynamic>
          ? response
          : (response is Map ? Map<String, dynamic>.from(response) : <String, dynamic>{});
      final applied = mapped['applied'] == true;
      final duplicate = mapped['duplicate'] == true;
      if (!applied && duplicate) {
        throw Exception('Payroll already recorded for this staff and month.');
      }
      if (!applied && !duplicate) {
        throw Exception('Failed to save payroll record.');
      }
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

  /// Updates a staff profile's monthly gross salary (in kobo). Used to prefill payroll entry and configuration checks only — not for financial totals.
  Future<void> updateStaffMonthlySalary(String profileId, int amountKobo) async {
    await _retryOperation(() async {
      await _supabase.from('profiles').update({
        'monthly_salary': amountKobo,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', profileId);
    });
  }

  /// Sums **approved** `payroll_records` only (kobo). No imputation from `monthly_salary`.
  /// Uses the same month window as [getPayrollRecords] (first-of-month bounds). If multiple
  /// approved rows exist for the same staff and calendar month, keeps the latest by `approved_at` then `created_at`.
  Future<num> calculatePeriodPayroll(DateTime start, DateTime end) async {
    final startMonth = DateTime(start.year, start.month, 1);
    final endMonth = DateTime(end.year, end.month, 1);
    final records = await getPayrollRecords(
      startMonth: startMonth,
      endMonth: endMonth,
      approvalStatus: 'approved',
      limit: 5000,
    );
    String monthKeyFromRow(Map<String, dynamic> r) {
      final raw = r['month']?.toString() ?? '';
      if (raw.length >= 7) return raw.substring(0, 7);
      return raw;
    }
    final byKey = <String, Map<String, dynamic>>{};
    for (final r in records) {
      final staffId = r['staff_id']?.toString();
      if (staffId == null || staffId.isEmpty) continue;
      final mk = monthKeyFromRow(r);
      if (mk.isEmpty) continue;
      final key = '$staffId|$mk';
      final existing = byKey[key];
      if (existing == null) {
        byKey[key] = r;
        continue;
      }
      final at = r['approved_at']?.toString() ?? r['created_at']?.toString() ?? '';
      final bt = existing['approved_at']?.toString() ?? existing['created_at']?.toString() ?? '';
      if (at.compareTo(bt) > 0) byKey[key] = r;
    }
    num total = 0;
    for (final r in byKey.values) {
      final a = r['amount'];
      total += a is int ? a.toDouble() : (double.tryParse(a?.toString() ?? '') ?? 0);
    }
    return total;
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

  DateTime _endOfDay(DateTime value) {
    return DateTime(value.year, value.month, value.day, 23, 59, 59, 999);
  }

  int _toIntKobo(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  String _auditChangeSummary(Map<String, dynamic> before, Map<String, dynamic> after) {
    final watchedFields = <String>[
      'name',
      'item_name',
      'price',
      'vip_bar_price',
      'outside_bar_price',
      'unit_price',
      'total_amount',
      'quantity',
      'unit_price_kobo',
      'line_total_kobo',
      'payment_status',
      'payment_method',
      'is_available',
      'department',
      'status',
    ];
    final changes = <String>[];
    for (final field in watchedFields) {
      final oldVal = before[field];
      final newVal = after[field];
      if ('$oldVal' != '$newVal') {
        changes.add('$field: ${oldVal ?? 'null'} -> ${newVal ?? 'null'}');
      }
    }
    if (changes.isEmpty) return 'Record updated';
    return changes.take(3).join('; ');
  }

  /// Returns a unified auditor activity feed:
  /// - sales/collections lines (kitchen, mini mart, bars, dispatches, booking charges, debt claims)
  /// - catalog changes and sales mutations from finance_audit_logs
  Future<List<Map<String, dynamic>>> getAuditorTransactions({
    DateTime? startDate,
    DateTime? endDate,
    int limitPerSource = 600,
  }) async {
    return await _retryOperation(() async {
      final effectiveEnd = endDate != null ? _endOfDay(endDate) : null;
      final results = await Future.wait<List<Map<String, dynamic>>>([
        getFinanceAuditLogs(startDate: startDate, endDate: effectiveEnd, limit: limitPerSource),
        getMiniMartSales(startDate: startDate, endDate: effectiveEnd, limit: limitPerSource),
        getKitchenSalesHistory(startDate: startDate, endDate: effectiveEnd, limit: limitPerSource),
        getDebtPaymentClaims(startDate: startDate, endDate: effectiveEnd),
        _supabase
            .from('stock_transactions')
            .select('*, stock_items(name), profiles!staff_profile_id(full_name), locations(name)')
            .eq('transaction_type', 'Sale')
            .gte('created_at', startDate?.toIso8601String() ?? '1970-01-01T00:00:00.000Z')
            .lte('created_at', effectiveEnd?.toIso8601String() ?? DateTime.now().toIso8601String())
            .order('created_at', ascending: false)
            .limit(limitPerSource),
        _supabase
            .from('department_transfers')
            .select('*, menu_items(name), dispatched_by_profile:profiles!dispatched_by_id(full_name)')
            .gte('created_at', startDate?.toIso8601String() ?? '1970-01-01T00:00:00.000Z')
            .lte('created_at', effectiveEnd?.toIso8601String() ?? DateTime.now().toIso8601String())
            .order('created_at', ascending: false)
            .limit(limitPerSource),
        _supabase
            .from('booking_charges')
            .select('*, added_by_profile:profiles!added_by(full_name), bookings(id, guest_name)')
            .gte('created_at', startDate?.toIso8601String() ?? '1970-01-01T00:00:00.000Z')
            .lte('created_at', effectiveEnd?.toIso8601String() ?? DateTime.now().toIso8601String())
            .order('created_at', ascending: false)
            .limit(limitPerSource),
      ]);

      final unified = <Map<String, dynamic>>[];

      final financeLogs = results[0];
      unified.addAll(financeLogs.map((row) {
        final action = row['action']?.toString().toUpperCase() ?? '';
        final tableName = row['table_name']?.toString() ?? '';
        final afterData = (row['after_data'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final beforeData = (row['before_data'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{};
        final actor = row['actor'] as Map<String, dynamic>?;

        final isCatalogTable =
            tableName == 'inventory_items' ||
            tableName == 'mini_mart_items' ||
            tableName == 'menu_items' ||
            tableName == 'room_types';

        final isSalesMutationTable =
            tableName == 'kitchen_sales' ||
            tableName == 'mini_mart_sales' ||
            tableName == 'department_transfers' ||
            tableName == 'booking_charges' ||
            tableName == 'stock_transactions';

        if (!isCatalogTable && !isSalesMutationTable) {
          return {
            ...row,
            'source': 'finance_audit',
          };
        }

        final isDelete = action == 'DELETE';
        final effective = isDelete ? beforeData : afterData;
        final quantity = _toIntKobo(effective['quantity']);
        final unitPrice = _toIntKobo(
          effective['unit_price'] ??
              effective['price'] ??
              effective['unit_price_kobo'] ??
              effective['vip_bar_price'],
        );
        final lineTotal = _toIntKobo(
          effective['total_amount'] ??
              effective['line_total_kobo'] ??
              ((quantity > 0 && unitPrice > 0) ? quantity * unitPrice : null),
        );

        return {
          'id': row['id'],
          'created_at': row['created_at'],
          'action': action,
          'table_name': tableName,
          'record_id': row['record_id'],
          'amount': lineTotal > 0 ? lineTotal : null,
          'unit_price': unitPrice > 0 ? unitPrice : null,
          'quantity': quantity > 0 ? quantity : null,
          'line_total': lineTotal > 0 ? lineTotal : null,
          'actor_name': actor?['full_name']?.toString() ?? 'Unknown',
          'description': action == 'UPDATE'
              ? _auditChangeSummary(beforeData, afterData)
              : (effective['name']?.toString() ??
                  effective['item_name']?.toString() ??
                  '${action.toLowerCase()} on $tableName'),
          'source': isCatalogTable ? 'catalog_changes' : 'sales_mutation',
          'audit_stream': isCatalogTable ? 'Catalog Changes' : 'Sales/Collections Activity',
        };
      }));

      final miniMartSales = results[1];
      unified.addAll(miniMartSales.map((row) {
        final actor = row['sold_by_profile'] as Map<String, dynamic>?;
        final item = row['mini_mart_items'] as Map<String, dynamic>?;
        final qty = _toIntKobo(row['quantity']);
        final unitPrice = _toIntKobo(row['unit_price']);
        final total = _toIntKobo(row['total_amount']);
        return {
          'id': row['id'],
          'created_at': row['sale_date'] ?? row['created_at'],
          'action': 'SALE_CREATED',
          'table_name': 'mini_mart_sales',
          'record_id': row['id'],
          'amount': total,
          'unit_price': unitPrice,
          'quantity': qty,
          'line_total': total,
          'actor_name': actor?['full_name']?.toString() ?? 'Unknown',
          'description': item?['name']?.toString() ?? row['notes']?.toString() ?? row['customer_name']?.toString() ?? 'Mini mart sale',
          'source': 'sales_collections',
          'audit_stream': 'Sales/Collections Activity',
        };
      }));

      final kitchenSales = results[2];
      unified.addAll(kitchenSales.map((row) {
        final actor = row['sold_by_profile'] as Map<String, dynamic>?;
        final menuItem = row['menu_items'] as Map<String, dynamic>?;
        final qty = _toIntKobo(row['quantity']);
        final unitPrice = _toIntKobo(row['unit_price']);
        final total = _toIntKobo(row['total_amount']);
        return {
          'id': row['id'],
          'created_at': row['created_at'],
          'action': 'SALE_CREATED',
          'table_name': 'kitchen_sales',
          'record_id': row['id'],
          'amount': total,
          'unit_price': unitPrice,
          'quantity': qty,
          'line_total': total,
          'actor_name': actor?['full_name']?.toString() ?? 'Unknown',
          'description': row['item_name']?.toString() ?? menuItem?['name']?.toString() ?? row['notes']?.toString() ?? 'Kitchen sale',
          'source': 'sales_collections',
          'audit_stream': 'Sales/Collections Activity',
        };
      }));

      final debtClaims = results[3];
      unified.addAll(debtClaims.map((row) {
        final actor = row['recorded_by_profile'] as Map<String, dynamic>?;
        final amount = _toIntKobo(row['amount']);
        return {
          'id': row['id'],
          'created_at': row['created_at'],
          'action': (row['status']?.toString() ?? 'pending').toUpperCase(),
          'table_name': 'debt_payment_claims',
          'record_id': row['id'],
          'amount': amount,
          'line_total': amount,
          'actor_name': actor?['full_name']?.toString() ?? 'Unknown',
          'description': row['notes']?.toString() ?? '',
          'source': 'sales_collections',
          'audit_stream': 'Sales/Collections Activity',
        };
      }));

      final stockSales = List<Map<String, dynamic>>.from(results[4] as List);
      unified.addAll(stockSales.map((row) {
        final actor = row['profiles'] as Map<String, dynamic>?;
        final stockItem = row['stock_items'] as Map<String, dynamic>?;
        final location = row['locations'] as Map<String, dynamic>?;
        final qty = (_toIntKobo(row['quantity'])).abs();
        final unitPrice = _toIntKobo(row['unit_price_kobo']);
        final fallbackTotal = qty > 0 && unitPrice > 0 ? qty * unitPrice : 0;
        final lineTotal = _toIntKobo(row['line_total_kobo']) > 0 ? _toIntKobo(row['line_total_kobo']) : fallbackTotal;
        return {
          'id': row['id'],
          'created_at': row['created_at'],
          'action': 'SALE_CREATED',
          'table_name': 'stock_transactions',
          'record_id': row['id'],
          'amount': lineTotal > 0 ? lineTotal : null,
          'unit_price': unitPrice > 0 ? unitPrice : null,
          'quantity': qty > 0 ? qty : null,
          'line_total': lineTotal > 0 ? lineTotal : null,
          'actor_name': actor?['full_name']?.toString() ?? row['staff_name']?.toString() ?? 'Unknown',
          'description': 'Bar sale: ${stockItem?['name']?.toString() ?? 'Item'} (${location?['name']?.toString() ?? 'Unknown location'})',
          'source': 'sales_collections',
          'audit_stream': 'Sales/Collections Activity',
        };
      }));

      final transfers = List<Map<String, dynamic>>.from(results[5] as List);
      unified.addAll(transfers.map((row) {
        final actor = row['dispatched_by_profile'] as Map<String, dynamic>?;
        final menuItem = row['menu_items'] as Map<String, dynamic>?;
        final qty = _toIntKobo(row['quantity']);
        final unitPrice = _toIntKobo(row['unit_price']);
        final total = _toIntKobo(row['total_amount']);
        return {
          'id': row['id'],
          'created_at': row['created_at'],
          'action': 'DISPATCH_CREATED',
          'table_name': 'department_transfers',
          'record_id': row['id'],
          'amount': total,
          'unit_price': unitPrice,
          'quantity': qty,
          'line_total': total,
          'actor_name': actor?['full_name']?.toString() ?? 'Unknown',
          'description': 'Dispatch ${menuItem?['name']?.toString() ?? 'item'} to ${row['destination_department']?.toString() ?? 'department'} (${row['payment_status']?.toString() ?? 'paid'})',
          'source': 'sales_collections',
          'audit_stream': 'Sales/Collections Activity',
        };
      }));

      final bookingCharges = List<Map<String, dynamic>>.from(results[6] as List);
      unified.addAll(bookingCharges.map((row) {
        final actor = row['added_by_profile'] as Map<String, dynamic>?;
        final booking = row['bookings'] as Map<String, dynamic>?;
        final qty = _toIntKobo(row['quantity']);
        final unitPrice = _toIntKobo(row['price']);
        final total = unitPrice * (qty <= 0 ? 1 : qty);
        return {
          'id': row['id'],
          'created_at': row['created_at'],
          'action': 'CHARGE_CREATED',
          'table_name': 'booking_charges',
          'record_id': row['id'],
          'amount': total,
          'unit_price': unitPrice,
          'quantity': qty,
          'line_total': total,
          'actor_name': actor?['full_name']?.toString() ?? row['added_by_name']?.toString() ?? 'Unknown',
          'description': 'Room charge: ${row['item_name']?.toString() ?? 'Item'} (${booking?['guest_name']?.toString() ?? 'Guest'})',
          'source': 'sales_collections',
          'audit_stream': 'Sales/Collections Activity',
        };
      }));

      unified.sort((a, b) {
        final aTime = DateTime.tryParse(a['created_at']?.toString() ?? '');
        final bTime = DateTime.tryParse(b['created_at']?.toString() ?? '');
        if (aTime == null && bTime == null) return 0;
        if (aTime == null) return 1;
        if (bTime == null) return -1;
        return bTime.compareTo(aTime);
      });

      return unified;
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
  Future<List<Map<String, dynamic>>> getDebtPaymentClaims({
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return await _retryOperation(() async {
      var query = _supabase
          .from('debt_payment_claims')
          .select('*, debts(id, debtor_name, debtor_phone, amount, paid_amount, department, source_department, reason), recorded_by_profile:profiles!recorded_by(full_name)');
      if (status != null && status.isNotEmpty) {
        query = query.eq('status', status);
      }
      if (startDate != null) {
        query = query.gte('created_at', startDate.toIso8601String());
      }
      if (endDate != null) {
        query = query.lte('created_at', _endOfDay(endDate).toIso8601String());
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
  /// Available Cash (cash-on-hand for selected period) =
  ///   cash sales inflows + other cash income - approved cash expenses - cash deposits.
  /// Payroll is intentionally excluded from available cash (hotel policy: salaries are not paid in cash).
  Future<Map<String, dynamic>> getFinancialSummary({
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    return await _retryOperation(() async {
      final rangeStart = startDate ?? DateTime.now().subtract(const Duration(days: 30));
      final rangeEnd = endDate ?? DateTime.now();
      final startStr = rangeStart.toIso8601String().split('T')[0];
      final endStr = rangeEnd.toIso8601String().split('T')[0];

      // Build typed futures so that Future.wait receives an Iterable<Future>.
      final Future<dynamic> incomeFuture = _supabase
          .from('income_records')
          .select('amount')
          .gte('date', startStr)
          .lte('date', endStr);

      final Future<dynamic> deptSalesFuture = _supabase
          .from('department_sales')
          .select('department, total_sales, payment_method_breakdown')
          .inFilter('department', ['vip_bar', 'outside_bar', 'mini_mart', 'restaurant', 'reception'])
          .gte('date', startStr)
          .lte('date', endStr);

      final Future<dynamic> kitchenSalesFuture = _supabase
          .from('kitchen_sales')
          .select('total_amount')
          .gte('created_at', rangeStart.toIso8601String())
          .lte('created_at', rangeEnd.toIso8601String());

      final Future<dynamic> miniMartSalesFuture = _supabase
          .from('mini_mart_sales')
          .select('total_amount')
          .gte('sale_date', startStr)
          .lte('sale_date', endStr);

      // Cash-only flows for available_cash.
      final Future<dynamic> cashIncomeFuture = _supabase
          .from('income_records')
          .select('amount')
          .eq('payment_method', 'cash')
          .gte('date', startStr)
          .lte('date', endStr);

      final Future<dynamic> cashKitchenSalesFuture = _supabase
          .from('kitchen_sales')
          .select('total_amount')
          .eq('payment_method', 'cash')
          .gte('created_at', rangeStart.toIso8601String())
          .lte('created_at', rangeEnd.toIso8601String());

      final Future<dynamic> cashMiniMartSalesFuture = _supabase
          .from('mini_mart_sales')
          .select('total_amount')
          .eq('payment_method', 'cash')
          .gte('sale_date', startStr)
          .lte('sale_date', endStr);

      final Future<dynamic> cashRoomSalesFuture = _supabase
          .from('bookings')
          .select('total_amount, paid_amount')
          .eq('payment_method', 'cash')
          .inFilter('status', ['Checked-out', 'checked_out', 'checked-out', 'Checked out', 'checked out'])
          .gte('check_out_date', startStr)
          .lte('check_out_date', endStr);

      final Future<dynamic> bookingsFuture = _supabase
          .from('bookings')
          .select('total_amount, paid_amount')
          .inFilter('status', ['Checked-out', 'checked_out', 'checked-out', 'Checked out', 'checked out'])
          .gte('check_out_date', startStr)
          .lte('check_out_date', endStr);

      final Future<dynamic> expensesFuture = _supabase
          .from('expenses')
          .select('amount')
          .gte('transaction_date', startStr)
          .lte('transaction_date', endStr);

      final Future<dynamic> cashApprovedExpensesFuture = _supabase
          .from('expenses')
          .select('amount')
          .eq('payment_method', 'cash')
          .gte('transaction_date', startStr)
          .lte('transaction_date', endStr)
          .eq('status', 'Approved');

      final Future<dynamic> cashDepositsFuture = _supabase
          .from('cash_deposits')
          .select('amount')
          .gte('date', startStr)
          .lte('date', endStr);

      final results = await Future.wait([
        incomeFuture,
        deptSalesFuture,
        kitchenSalesFuture,
        miniMartSalesFuture,
        bookingsFuture,
        expensesFuture,
        cashIncomeFuture,
        cashKitchenSalesFuture,
        cashMiniMartSalesFuture,
        cashRoomSalesFuture,
        cashApprovedExpensesFuture,
        cashDepositsFuture,
      ]);

      // Unpack results with safe typing.
      final incomeResp = results[0] as List;
      final deptResp = results[1] as List;
      final kResp = results[2] as List;
      final mmResp = results[3] as List;
      final bookResp = results[4] as List;
      final expensesResp = results[5] as List;
      final cashIncomeResp = results[6] as List;
      final cashKitchenResp = results[7] as List;
      final cashMiniMartResp = results[8] as List;
      final cashRoomResp = results[9] as List;
      final cashExpApproved = results[10] as List;
      final cashDepositsResp = results[11] as List;

      var totalIncome = incomeResp.fold<double>(
        0,
        (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
      );

      int deptSalesTotal = 0;
      for (final r in deptResp) {
        deptSalesTotal += (r['total_sales'] as num?)?.toInt() ?? 0;
      }
      if (deptSalesTotal == 0) {
        for (final r in kResp) {
          deptSalesTotal += (r['total_amount'] as num?)?.toInt() ?? 0;
        }
        for (final r in mmResp) {
          deptSalesTotal += (r['total_amount'] as num?)?.toInt() ?? 0;
        }
      }
      totalIncome += deptSalesTotal.toDouble();

      int roomRevenue = 0;
      for (final b in bookResp) {
        final total = (b['total_amount'] as num?)?.toInt();
        final paid = (b['paid_amount'] as num?)?.toInt();
        roomRevenue += _collectedAmountKobo(total, paid);
      }
      totalIncome += roomRevenue.toDouble();

      final totalExpenses = expensesResp.fold<double>(
        0,
        (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
      );

      // Cash-only inflows/outflows for available cash.
      double cashSalesByDepartment = 0;
      for (final row in deptResp) {
        final breakdownRaw = row['payment_method_breakdown'];
        if (breakdownRaw is Map) {
          final breakdown = Map<String, dynamic>.from(breakdownRaw);
          final cashPart = (breakdown['cash'] as num?)?.toDouble() ??
              (breakdown['Cash'] as num?)?.toDouble() ??
              0;
          cashSalesByDepartment += cashPart;
        }
      }

      // Fallback to source sales tables if department breakdown has no cash values.
      if (cashSalesByDepartment == 0) {
        for (final r in cashKitchenResp) {
          cashSalesByDepartment += (r['total_amount'] as num?)?.toDouble() ?? 0;
        }
        for (final r in cashMiniMartResp) {
          cashSalesByDepartment += (r['total_amount'] as num?)?.toDouble() ?? 0;
        }
        for (final b in cashRoomResp) {
          final paid = (b['paid_amount'] as num?)?.toDouble();
          final total = (b['total_amount'] as num?)?.toDouble() ?? 0;
          cashSalesByDepartment += paid ?? total;
        }
      }

      final cashOtherIncome = cashIncomeResp.fold<double>(
        0,
        (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
      );
      final cashApprovedExpenseTotal = cashExpApproved.fold<double>(
        0,
        (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
      );
      final cashDepositedTotal = cashDepositsResp.fold<double>(
        0,
        (sum, item) => sum + ((item['amount'] as num?)?.toDouble() ?? 0),
      );

      final cashInflows = cashSalesByDepartment + cashOtherIncome;
      final availableCash = cashInflows - cashApprovedExpenseTotal - cashDepositedTotal;

      return {
        'total_income': totalIncome,
        'total_expenses': totalExpenses,
        'net_profit': totalIncome - totalExpenses,
        'available_cash': availableCash,
        // Cash deposits tab breakdown fields (same period as selected range).
        'cash_sales_inflow': cashSalesByDepartment,
        'cash_other_income': cashOtherIncome,
        'cash_total_inflow': cashInflows,
        'cash_expenses': cashApprovedExpenseTotal,
        'cash_deposits': cashDepositedTotal,
      };
    });
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

      // 1b. Reception room bookings revenue (bookings)
      // We treat room bookings like a "department" called `reception` for performance calculations.
      // Use checked-in bookings (money realized at check-in), not checked-out.
      try {
        final bookingResp = await _supabase
            .from('bookings')
            .select('total_amount, paid_amount')
            .inFilter('status', ['Checked-in', 'checked_in', 'checked-in', 'Checked in', 'checked in'])
            // Money is realized at check-in for reception revenue.
            .gte('check_in_date', startStr)
            .lte('check_in_date', endStr);

        double receptionTotal = 0.0;
        for (final b in bookingResp as List) {
          final total = b['total_amount'] as num?;
          final paid = b['paid_amount'] as num?;
          final val = _collectedAmountKobo(total?.toInt(), paid?.toInt());
          receptionTotal += val.toDouble();
        }

        if (receptionTotal > 0) {
          revenueByDept['reception'] = receptionTotal;
        }
      } catch (_) {}

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
        'reception': 'Reception',
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

      final checkedIn = (bookings as List).where((b) => _normalizeBookingStatus(b['status']?.toString()) == 'checked-in').length;
      final pending = (bookings as List).where((b) => _normalizeBookingStatus(b['status']?.toString()) == 'pending').length;
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

  /// Adds a mini-mart item. Price in kobo.
  Future<void> addMiniMartItem({
    required String name,
    String? description,
    required int priceKobo,
    String? category,
    int stockQuantity = 0,
    int minStockLevel = 0,
    bool isAvailable = true,
  }) async {
    await _retryOperation(() async {
      final payload = <String, dynamic>{
        'name': name.trim(),
        'price': priceKobo,
        'stock_quantity': stockQuantity,
        'min_stock_level': minStockLevel,
        'is_available': isAvailable,
      };
      if (description != null && description.trim().isNotEmpty) {
        payload['description'] = description.trim();
      }
      if (category != null && category.trim().isNotEmpty) {
        payload['category'] = category.trim();
      }
      await _supabase.from('mini_mart_items').insert(payload);
    });
    invalidateCacheForTable('mini_mart_items');
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
          .select('id, name, price, department, barcode, stock_item_id, category')
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    });
  }

  /// Adds a menu item (kitchen/restaurant). Price in kobo.
  Future<void> addMenuItem({
    required String name,
    String? description,
    required int priceKobo,
    String department = 'restaurant',
    String? category,
    bool isAvailable = true,
    String? stockItemId,
  }) async {
    await _retryOperation(() async {
      final payload = <String, dynamic>{
        'name': name,
        'price': priceKobo,
        'department': department,
        'is_available': isAvailable,
      };
      if (description != null && description.trim().isNotEmpty) {
        payload['description'] = description.trim();
      }
      if (category != null && category.trim().isNotEmpty) {
        payload['category'] = category.trim();
      }
      if (stockItemId != null && stockItemId.isNotEmpty) {
        payload['stock_item_id'] = stockItemId;
      }
      await _supabase.from('menu_items').insert(payload);
    });
    invalidateCacheForTable('menu_items');
  }

  /// Generic update for product tables (inventory_items, mini_mart_items, menu_items, stock_items).
  /// [updates] must contain only valid columns for [tableName]. Adds updated_at when supported.
  /// If the table does not have updated_at, the update is retried without it (no crash).
  Future<void> updateProduct(String tableName, String id, Map<String, dynamic> updates) async {
    final payload = Map<String, dynamic>.from(updates);
    if (!payload.containsKey('updated_at')) {
      payload['updated_at'] = DateTime.now().toIso8601String();
    }
    try {
      await _retryOperation(() async {
        await _supabase.from(tableName).update(payload).eq('id', id);
      });
    } on PostgrestException catch (e) {
      if (kDebugMode) debugPrint('PostgrestException in updateProduct: code=${e.code} message=${e.message} tableName=$tableName id=$id');
      final msg = e.message.toLowerCase();
      final isColumnError = e.code == '42703' ||
          msg.contains('updated_at') ||
          (msg.contains('column') && msg.contains('does not exist'));
      if (isColumnError && payload.containsKey('updated_at')) {
        payload.remove('updated_at');
        await _retryOperation(() async {
          await _supabase.from(tableName).update(payload).eq('id', id);
        });
      } else {
        rethrow;
      }
    }
    invalidateCacheForTable(tableName);
  }

  /// Generic delete for product tables. Use with caution: ensure no foreign key references.
  Future<void> deleteProduct(String tableName, String id) async {
    await _retryOperation(() async {
      await _supabase.from(tableName).delete().eq('id', id);
    });
    invalidateCacheForTable(tableName);
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
        // Thin select: dashboard only needs these for totals and range filtering
        const selectCols = 'id, department, total_sales, date, created_at, updated_at';
        var query = _supabase
            .from('department_sales')
            .select(selectCols);
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
          .select('id, department, total_sales, date, created_at, updated_at')
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

  /// Uses SECURITY DEFINER RPC (claim + insert). Returns null if [clientRequestId] was already applied.
  Future<String?> createDepartmentTransfer(
    Map<String, dynamic> transfer, {
    String? clientRequestId,
  }) async {
    return _retryOperation(() async {
      final params = <String, dynamic>{
        'p_source_department': transfer['source_department'],
        'p_destination_department': transfer['destination_department'],
        'p_menu_item_id': transfer['menu_item_id'],
        'p_quantity': transfer['quantity'],
        'p_dispatched_by_id': transfer['dispatched_by_id'],
        'p_status': transfer['status'] ?? 'Pending',
        'p_unit_price': transfer['unit_price'],
        'p_total_amount': transfer['total_amount'],
        'p_payment_method': transfer['payment_method'],
        'p_payment_status': transfer['payment_status'],
        'p_booking_id': transfer['booking_id'],
        'p_notes': transfer['notes'],
      };
      if (clientRequestId != null && clientRequestId.isNotEmpty) {
        params['p_client_request_id'] = clientRequestId;
      }
      final res = await _supabase.rpc('create_department_transfer', params: params);
      if (res == null) return null;
      return res.toString();
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

      final orderId = orderResponse['id']?.toString() ?? '';
      if (orderId.isEmpty) throw Exception('Failed to create purchase order: no id returned');

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
      await _supabase.rpc('create_staff_profile', params: {
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

  int _collectedAmountKobo(int? totalAmount, int? paidAmount) {
    // Collected-first rule: if paid_amount exists (including 0 for credit), it is the truth.
    if (paidAmount != null) return paidAmount;
    return totalAmount ?? 0;
  }

}
