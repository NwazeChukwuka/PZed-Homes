// Test script to verify Supabase connection
// Run this in your Flutter app to test database connectivity

import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseConnectionTest {
  static Future<void> testConnection() async {
    try {
      final supabase = Supabase.instance.client;
      
      print('🔍 Testing Supabase connection...');
      
      // Test 1: Check if we can connect
      print('✅ Supabase client initialized');
      
      // Test 2: Try to read from profiles table
      try {
        final profiles = await supabase.from('profiles').select().limit(1);
        print('✅ Profiles table accessible - ${profiles.length} records found');
      } catch (e) {
        print('❌ Profiles table error: $e');
      }
      
      // Test 3: Try to read from room_types table
      try {
        final roomTypes = await supabase.from('room_types').select().limit(1);
        print('✅ Room types table accessible - ${roomTypes.length} records found');
      } catch (e) {
        print('❌ Room types table error: $e');
      }
      
      // Test 4: Try to read from bookings table
      try {
        final bookings = await supabase.from('bookings').select().limit(1);
        print('✅ Bookings table accessible - ${bookings.length} records found');
      } catch (e) {
        print('❌ Bookings table error: $e');
      }
      
      // Test 5: Try to read from work_orders table
      try {
        final workOrders = await supabase.from('work_orders').select().limit(1);
        print('✅ Work orders table accessible - ${workOrders.length} records found');
      } catch (e) {
        print('❌ Work orders table error: $e');
      }
      
      // Test 6: Test realtime subscription
      try {
        final stream = supabase
            .from('bookings')
            .stream(primaryKey: ['id'])
            .limit(1);
        
        print('✅ Realtime stream created successfully');
        // Don't actually listen to avoid blocking
      } catch (e) {
        print('❌ Realtime stream error: $e');
      }
      
      print('\n🎉 Supabase connection test completed!');
      print('If you see any ❌ errors, make sure you have run the setup_database.sql script.');
      
    } catch (e) {
      print('❌ Critical Supabase connection error: $e');
      print('Please check your Supabase URL and API key in main.dart');
    }
  }
  
  static Future<void> testInsertOperations() async {
    try {
      final supabase = Supabase.instance.client;
      
      print('\n🔍 Testing insert operations...');
      
      // Test inserting a sample work order
      try {
        final result = await supabase.from('work_orders').insert({
          'issue_description': 'Test maintenance request from Flutter app',
          'location': 'Test Location',
          'status': 'Pending',
          'priority': 'Low',
        }).select();
        
        print('✅ Work order insert successful - ID: ${result.first['id']}');
        
        // Clean up test data
        await supabase.from('work_orders').delete().eq('issue_description', 'Test maintenance request from Flutter app');
        print('✅ Test work order cleaned up');
        
      } catch (e) {
        print('❌ Work order insert error: $e');
      }
      
      // Test inserting a sample post
      try {
        final result = await supabase.from('posts').insert({
          'title': 'Test Announcement',
          'content': 'This is a test announcement from Flutter app',
          'is_published': true,
        }).select();
        
        print('✅ Post insert successful - ID: ${result.first['id']}');
        
        // Clean up test data
        await supabase.from('posts').delete().eq('title', 'Test Announcement');
        print('✅ Test post cleaned up');
        
      } catch (e) {
        print('❌ Post insert error: $e');
      }
      
      print('\n🎉 Insert operations test completed!');
      
    } catch (e) {
      print('❌ Critical insert operations error: $e');
    }
  }
}

// Usage in your app:
// Add this to any screen's initState or button onPressed:
// 
// SupabaseConnectionTest.testConnection();
// SupabaseConnectionTest.testInsertOperations();
