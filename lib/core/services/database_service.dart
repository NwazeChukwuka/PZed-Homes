// Location: lib/core/services/database_service.dart

import 'package:supabase_flutter/supabase_flutter.dart';

class DatabaseService {
  final _supabase = Supabase.instance.client;

  // Fetch all bookings with related room and guest info
  Future<List<Map<String, dynamic>>> getBookings() async {
    final response = await _supabase
        .from('bookings')
        .select('*, rooms(*), profiles!inner(*)'); // Use !inner to ensure profile exists
    return response as List<Map<String, dynamic>>;
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
    return response as List<Map<String, dynamic>>;
  }

  // Update a room's status
  Future<void> updateRoomStatus(String roomId, String newStatus) async {
    await _supabase.from('rooms').update({'status': newStatus}).eq('id', roomId);
  }

  // Fetch all stock items
  Future<List<Map<String, dynamic>>> getStockItems() async {
    final response = await _supabase.from('stock_items').select().order('name');
    return response as List<Map<String, dynamic>>;
  }

  // Update a stock item's quantity
  Future<void> updateStockQuantity(String stockItemId, int newQuantity) async {
    await _supabase.from('stock_items').update({'current_quantity': newQuantity}).eq('id', stockItemId);
  }

  // Fetch all menu items
  Future<List<Map<String, dynamic>>> getMenuItems() async {
    final response = await _supabase.from('menu_items').select().order('name');
    return response as List<Map<String, dynamic>>;
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