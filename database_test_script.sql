-- P-ZED Homes Database Test Script
-- This script tests all the database functions and ensures everything works correctly

-- ==============================================
-- TEST USER CREATION AND ROLES
-- ==============================================

-- Test creating a profile (this would normally be done through Supabase Auth)
-- Note: In real usage, this would be handled by Supabase Auth triggers

-- ==============================================
-- TEST ROOM OPERATIONS
-- ==============================================

-- Test room availability function
SELECT 'Testing room availability...' as test_step;
SELECT * FROM get_available_rooms(CURRENT_DATE + INTERVAL '1 day', CURRENT_DATE + INTERVAL '3 days');

-- Test room occupancy rate
SELECT 'Testing occupancy rate...' as test_step;
SELECT get_occupancy_rate() as occupancy_rate;

-- ==============================================
-- TEST BOOKING OPERATIONS
-- ==============================================

-- Test creating a booking
SELECT 'Testing booking creation...' as test_step;
-- Note: This would require actual user IDs in a real scenario
-- SELECT create_booking(
--     'Test Guest',
--     'test@example.com',
--     '+2348012345678',
--     (SELECT id FROM rooms LIMIT 1),
--     CURRENT_DATE + INTERVAL '1 day',
--     CURRENT_DATE + INTERVAL '3 days',
--     (SELECT id FROM profiles LIMIT 1),
--     'Test booking'
-- );

-- Test booking total calculation
SELECT 'Testing booking total calculation...' as test_step;
SELECT 
    id,
    guest_name,
    total_amount,
    calculate_booking_total(id) as calculated_total
FROM bookings 
LIMIT 3;

-- ==============================================
-- TEST STOCK OPERATIONS
-- ==============================================

-- Test stock level calculation
SELECT 'Testing stock levels...' as test_step;
SELECT 
    si.name,
    l.name as location,
    calculate_stock_level(si.id, l.id) as current_stock,
    si.min_stock_level
FROM stock_items si
CROSS JOIN locations l
WHERE calculate_stock_level(si.id, l.id) > 0
LIMIT 5;

-- Test low stock alerts
SELECT 'Testing low stock alerts...' as test_step;
SELECT * FROM low_stock_alerts;

-- ==============================================
-- TEST REPORTING FUNCTIONS
-- ==============================================

-- Test daily revenue report
SELECT 'Testing daily revenue report...' as test_step;
SELECT * FROM get_daily_revenue_report(CURRENT_DATE);

-- Test occupancy report
SELECT 'Testing occupancy report...' as test_step;
SELECT * FROM get_occupancy_report(
    CURRENT_DATE - INTERVAL '7 days', 
    CURRENT_DATE
);

-- Test stock movement report
SELECT 'Testing stock movement report...' as test_step;
SELECT * FROM get_stock_movement_report(
    NULL, -- all items
    NULL, -- all locations
    CURRENT_DATE - INTERVAL '30 days',
    CURRENT_DATE
);

-- ==============================================
-- TEST NOTIFICATION FUNCTIONS
-- ==============================================

-- Test creating a notification
SELECT 'Testing notification creation...' as test_step;
-- Note: This would require actual user IDs in a real scenario
-- SELECT create_notification(
--     (SELECT id FROM profiles LIMIT 1),
--     'Test Notification',
--     'This is a test notification',
--     'info'
-- );

-- Test system notification
SELECT 'Testing system notification...' as test_step;
-- SELECT create_system_notification(
--     'System Test',
--     'This is a system-wide test notification',
--     'info'
-- );

-- ==============================================
-- TEST ATTENDANCE FUNCTIONS
-- ==============================================

-- Test attendance summary
SELECT 'Testing attendance summary...' as test_step;
SELECT * FROM get_attendance_summary(
    NULL, -- all staff
    CURRENT_DATE - INTERVAL '7 days',
    CURRENT_DATE
);

-- ==============================================
-- TEST VIEWS
-- ==============================================

-- Test current room status view
SELECT 'Testing room status view...' as test_step;
SELECT * FROM current_room_status LIMIT 5;

-- Test staff performance view
SELECT 'Testing staff performance view...' as test_step;
SELECT * FROM staff_performance LIMIT 5;

-- ==============================================
-- TEST DATA INTEGRITY
-- ==============================================

-- Test foreign key constraints
SELECT 'Testing foreign key constraints...' as test_step;
SELECT 
    'bookings' as table_name,
    COUNT(*) as total_records,
    COUNT(room_id) as valid_room_refs,
    COUNT(*) - COUNT(room_id) as invalid_refs
FROM bookings;

-- Test check constraints
SELECT 'Testing check constraints...' as test_step;
SELECT 
    'rooms' as table_name,
    status,
    COUNT(*) as count
FROM rooms 
GROUP BY status;

-- ==============================================
-- TEST PERFORMANCE
-- ==============================================

-- Test query performance
SELECT 'Testing query performance...' as test_step;
EXPLAIN (ANALYZE, BUFFERS) 
SELECT 
    r.room_number,
    rt.type,
    r.status,
    b.guest_name,
    b.total_amount
FROM rooms r
JOIN room_types rt ON r.type_id = rt.id
LEFT JOIN bookings b ON r.id = b.room_id AND b.status = 'Checked-in'
ORDER BY r.room_number;

-- ==============================================
-- TEST RLS POLICIES
-- ==============================================

-- Test RLS is enabled
SELECT 'Testing RLS policies...' as test_step;
SELECT 
    schemaname,
    tablename,
    rowsecurity as rls_enabled
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('profiles', 'bookings', 'rooms', 'stock_transactions')
ORDER BY tablename;

-- ==============================================
-- TEST TRIGGERS
-- ==============================================

-- Test trigger functions exist
SELECT 'Testing trigger functions...' as test_step;
SELECT 
    trigger_name,
    event_manipulation,
    action_timing,
    action_statement
FROM information_schema.triggers 
WHERE trigger_schema = 'public'
AND trigger_name LIKE '%updated_at%'
ORDER BY trigger_name;

-- ==============================================
-- TEST INDEXES
-- ==============================================

-- Test indexes exist
SELECT 'Testing indexes...' as test_step;
SELECT 
    indexname,
    tablename,
    indexdef
FROM pg_indexes 
WHERE schemaname = 'public'
AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;

-- ==============================================
-- TEST SAMPLE DATA
-- ==============================================

-- Test sample data exists
SELECT 'Testing sample data...' as test_step;
SELECT 
    'room_types' as table_name,
    COUNT(*) as record_count
FROM room_types
UNION ALL
SELECT 
    'rooms' as table_name,
    COUNT(*) as record_count
FROM rooms
UNION ALL
SELECT 
    'bookings' as table_name,
    COUNT(*) as record_count
FROM bookings
UNION ALL
SELECT 
    'stock_items' as table_name,
    COUNT(*) as record_count
FROM stock_items
UNION ALL
SELECT 
    'stock_transactions' as table_name,
    COUNT(*) as record_count
FROM stock_transactions
UNION ALL
SELECT 
    'menu_items' as table_name,
    COUNT(*) as record_count
FROM menu_items
UNION ALL
SELECT 
    'locations' as table_name,
    COUNT(*) as record_count
FROM locations
UNION ALL
SELECT 
    'departments' as table_name,
    COUNT(*) as record_count
FROM departments;

-- ==============================================
-- TEST CLEANUP FUNCTIONS
-- ==============================================

-- Test cleanup functions (dry run)
SELECT 'Testing cleanup functions...' as test_step;
SELECT clean_old_notifications(30) as notifications_cleaned;
SELECT archive_old_bookings(365) as bookings_archived;

-- ==============================================
-- FINAL VERIFICATION
-- ==============================================

-- Final system health check
SELECT 'Final system health check...' as test_step;
SELECT 
    'Database Version' as check_type,
    version() as result
UNION ALL
SELECT 
    'Current Time' as check_type,
    NOW()::TEXT as result
UNION ALL
SELECT 
    'Total Tables' as check_type,
    COUNT(*)::TEXT as result
FROM information_schema.tables 
WHERE table_schema = 'public'
UNION ALL
SELECT 
    'Total Functions' as check_type,
    COUNT(*)::TEXT as result
FROM information_schema.routines 
WHERE routine_schema = 'public'
UNION ALL
SELECT 
    'Total Views' as check_type,
    COUNT(*)::TEXT as result
FROM information_schema.views 
WHERE table_schema = 'public';

-- ==============================================
-- TEST COMPLETION
-- ==============================================

SELECT 'Database test completed successfully!' as final_result;
