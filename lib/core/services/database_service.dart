import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  final _supabase = Supabase.instance.client;

  // Fetch all bookings with related room and guest info
  Future<List<Map<String, dynamic>>> getBookings() async {
    final response = await _supabase
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
          rooms(*),
          profiles!guest_profile_id(*)
        ''');
    return response;
  }

  // Update a booking's status
  Future<void> updateBookingStatus(String bookingId, String newStatus) async {
    await _supabase.from('bookings').update({'status': newStatus}).eq('id', bookingId);
  }

  // Add extra charges to a booking
  Future<void> addExtraCharges(String bookingId, List<dynamic> newCharges) async {
    await _supabase.from('bookings').update({'extra_charges': newCharges}).eq('id', bookingId);
  }

  // Fetch all rooms
  Future<List<Map<String, dynamic>>> getRooms() async {
    final response = await _supabase.from('rooms').select().order('room_number');
    return response;
  }

  // Update a room's status
  Future<void> updateRoomStatus(String roomId, String newStatus) async {
    await _supabase.from('rooms').update({'status': newStatus}).eq('id', roomId);
  }

  // Fetch all stock items
  Future<List<Map<String, dynamic>>> getStockItems() async {
    final response = await _supabase.from('stock_items').select().order('name');
    return response;
  }

  // Update a stock item's quantity
  // NOTE: stock_items table doesn't have current_quantity - stock is calculated from transactions
  // This method is deprecated. Use stock_transactions instead.
  @deprecated
  Future<void> updateStockQuantity(String stockItemId, int newQuantity) async {
    // Stock items don't have a current_quantity column
    // Stock levels are calculated from stock_transactions
    throw UnimplementedError('Stock quantity is calculated from transactions, not stored directly. Use stock_transactions table instead.');
  }

  // Fetch all menu items
  Future<List<Map<String, dynamic>>> getMenuItems() async {
    final response = await _supabase.from('menu_items').select().order('name');
    return response;
  }

  // Create a new booking
  Future<void> createBooking({
    required String guestProfileId,
    required String roomId,
    required DateTime checkIn,
    required DateTime checkOut,
  }) async {
    await _supabase.from('bookings').insert({
      'guest_profile_id': guestProfileId,
      'room_id': roomId,
      'check_in_date': checkIn.toIso8601String(),
      'check_out_date': checkOut.toIso8601String(),
    });
  }
}