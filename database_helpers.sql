-- P-ZED Homes Database Helper Scripts
-- Additional SQL scripts for common operations and maintenance

-- ==============================================
-- HELPER FUNCTIONS
-- ==============================================

-- Function to get user permissions
CREATE OR REPLACE FUNCTION get_user_permissions(user_id UUID)
RETURNS TABLE(permission TEXT) AS $$
BEGIN
    RETURN QUERY
    SELECT unnest(roles) as permission
    FROM profiles
    WHERE profiles.id = user_id;
END;
$$ LANGUAGE plpgsql;

-- Function to check if user has role
CREATE OR REPLACE FUNCTION user_has_role(user_id UUID, role_name TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM profiles 
        WHERE profiles.id = user_id 
        AND role_name = ANY(roles)
    );
END;
$$ LANGUAGE plpgsql;

-- Function to get room availability
CREATE OR REPLACE FUNCTION get_available_rooms(check_in DATE, check_out DATE)
RETURNS TABLE(
    room_id UUID,
    room_number TEXT,
    room_type TEXT,
    price DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        r.id,
        r.room_number,
        rt.type,
        rt.price
    FROM rooms r
    JOIN room_types rt ON r.type_id = rt.id
    WHERE r.status = 'Vacant'
    AND NOT EXISTS (
        SELECT 1 FROM bookings b
        WHERE b.room_id = r.id
        AND b.status IN ('Checked-in', 'Pending Check-in')
        AND (
            (b.check_in_date <= check_in AND b.check_out_date > check_in) OR
            (b.check_in_date < check_out AND b.check_out_date >= check_out) OR
            (b.check_in_date >= check_in AND b.check_out_date <= check_out)
        )
    );
END;
$$ LANGUAGE plpgsql;

-- Function to calculate booking total
CREATE OR REPLACE FUNCTION calculate_booking_total(booking_id UUID)
RETURNS DECIMAL AS $$
DECLARE
    base_amount DECIMAL;
    extra_charges DECIMAL;
BEGIN
    -- Get base room amount
    SELECT rt.price * (b.check_out_date - b.check_in_date) INTO base_amount
    FROM bookings b
    JOIN rooms r ON b.room_id = r.id
    JOIN room_types rt ON r.type_id = rt.id
    WHERE b.id = booking_id;
    
    -- Get extra charges
    SELECT COALESCE(SUM(price * quantity), 0) INTO extra_charges
    FROM booking_charges
    WHERE booking_id = calculate_booking_total.booking_id;
    
    RETURN COALESCE(base_amount, 0) + COALESCE(extra_charges, 0);
END;
$$ LANGUAGE plpgsql;

-- Function to update booking total
CREATE OR REPLACE FUNCTION update_booking_total()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE bookings 
    SET total_amount = calculate_booking_total(NEW.booking_id)
    WHERE id = NEW.booking_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger to auto-update booking totals
CREATE TRIGGER update_booking_total_trigger
    AFTER INSERT OR UPDATE OR DELETE ON booking_charges
    FOR EACH ROW EXECUTE FUNCTION update_booking_total();

-- ==============================================
-- REPORTING FUNCTIONS
-- ==============================================

-- Function to get daily revenue report
CREATE OR REPLACE FUNCTION get_daily_revenue_report(report_date DATE DEFAULT CURRENT_DATE)
RETURNS TABLE(
    total_bookings INTEGER,
    total_revenue DECIMAL,
    paid_revenue DECIMAL,
    pending_revenue DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        COUNT(*)::INTEGER as total_bookings,
        COALESCE(SUM(total_amount), 0) as total_revenue,
        COALESCE(SUM(paid_amount), 0) as paid_revenue,
        COALESCE(SUM(total_amount - paid_amount), 0) as pending_revenue
    FROM bookings
    WHERE DATE(created_at) = report_date;
END;
$$ LANGUAGE plpgsql;

-- Function to get occupancy report
CREATE OR REPLACE FUNCTION get_occupancy_report(start_date DATE, end_date DATE)
RETURNS TABLE(
    date DATE,
    total_rooms INTEGER,
    occupied_rooms INTEGER,
    occupancy_rate DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    WITH date_series AS (
        SELECT generate_series(start_date, end_date, '1 day'::interval)::DATE as date
    ),
    daily_occupancy AS (
        SELECT 
            ds.date,
            COUNT(DISTINCT r.id) as total_rooms,
            COUNT(DISTINCT CASE 
                WHEN b.status = 'Checked-in' 
                AND ds.date BETWEEN b.check_in_date AND b.check_out_date - 1
                THEN r.id 
            END) as occupied_rooms
        FROM date_series ds
        CROSS JOIN rooms r
        LEFT JOIN bookings b ON r.id = b.room_id
        GROUP BY ds.date
    )
    SELECT 
        date,
        total_rooms,
        occupied_rooms,
        CASE 
            WHEN total_rooms > 0 THEN (occupied_rooms::DECIMAL / total_rooms::DECIMAL) * 100
            ELSE 0 
        END as occupancy_rate
    FROM daily_occupancy
    ORDER BY date;
END;
$$ LANGUAGE plpgsql;

-- Function to get stock movement report
CREATE OR REPLACE FUNCTION get_stock_movement_report(
    item_id UUID DEFAULT NULL,
    location_id UUID DEFAULT NULL,
    start_date DATE DEFAULT CURRENT_DATE - INTERVAL '30 days',
    end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
    item_name TEXT,
    location_name TEXT,
    transaction_type TEXT,
    quantity INTEGER,
    staff_name TEXT,
    transaction_date TIMESTAMP
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        st.item_name,
        st.location_name,
        st.transaction_type,
        st.quantity,
        st.staff_name,
        st.created_at
    FROM stock_transactions st
    WHERE (item_id IS NULL OR st.item_id = get_stock_movement_report.item_id)
    AND (location_id IS NULL OR st.location_id = get_stock_movement_report.location_id)
    AND DATE(st.created_at) BETWEEN start_date AND end_date
    ORDER BY st.created_at DESC;
END;
$$ LANGUAGE plpgsql;

-- ==============================================
-- NOTIFICATION FUNCTIONS
-- ==============================================

-- Function to create notification
CREATE OR REPLACE FUNCTION create_notification(
    target_user_id UUID,
    notification_title TEXT,
    notification_message TEXT,
    notification_type TEXT DEFAULT 'info'
)
RETURNS UUID AS $$
DECLARE
    notification_id UUID;
BEGIN
    INSERT INTO notifications (user_id, title, message, type)
    VALUES (target_user_id, notification_title, notification_message, notification_type)
    RETURNING id INTO notification_id;
    
    RETURN notification_id;
END;
$$ LANGUAGE plpgsql;

-- Function to create system-wide notification
CREATE OR REPLACE FUNCTION create_system_notification(
    notification_title TEXT,
    notification_message TEXT,
    notification_type TEXT DEFAULT 'info'
)
RETURNS INTEGER AS $$
DECLARE
    notification_count INTEGER;
BEGIN
    INSERT INTO notifications (user_id, title, message, type)
    SELECT 
        p.id,
        notification_title,
        notification_message,
        notification_type
    FROM profiles p
    WHERE array_length(p.roles, 1) > 0;
    
    GET DIAGNOSTICS notification_count = ROW_COUNT;
    RETURN notification_count;
END;
$$ LANGUAGE plpgsql;

-- ==============================================
-- ATTENDANCE FUNCTIONS
-- ==============================================

-- Function to clock in
CREATE OR REPLACE FUNCTION clock_in(staff_id UUID)
RETURNS UUID AS $$
DECLARE
    attendance_id UUID;
BEGIN
    -- Check if already clocked in today
    IF EXISTS (
        SELECT 1 FROM attendance_records 
        WHERE attendance_records.staff_id = clock_in.staff_id 
        AND DATE(clock_in_time) = CURRENT_DATE 
        AND clock_out_time IS NULL
    ) THEN
        RAISE EXCEPTION 'Staff member is already clocked in today';
    END IF;
    
    INSERT INTO attendance_records (staff_id, clock_in_time)
    VALUES (staff_id, CURRENT_TIMESTAMP)
    RETURNING id INTO attendance_id;
    
    RETURN attendance_id;
END;
$$ LANGUAGE plpgsql;

-- Function to clock out
CREATE OR REPLACE FUNCTION clock_out(staff_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE attendance_records 
    SET clock_out_time = CURRENT_TIMESTAMP
    WHERE attendance_records.staff_id = clock_out.staff_id 
    AND DATE(clock_in_time) = CURRENT_DATE 
    AND clock_out_time IS NULL;
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function to get staff attendance summary
CREATE OR REPLACE FUNCTION get_attendance_summary(
    staff_id UUID DEFAULT NULL,
    start_date DATE DEFAULT CURRENT_DATE - INTERVAL '30 days',
    end_date DATE DEFAULT CURRENT_DATE
)
RETURNS TABLE(
    staff_name TEXT,
    date DATE,
    clock_in_time TIMESTAMP,
    clock_out_time TIMESTAMP,
    hours_worked DECIMAL
) AS $$
BEGIN
    RETURN QUERY
    SELECT 
        p.full_name,
        DATE(ar.clock_in_time) as date,
        ar.clock_in_time,
        ar.clock_out_time,
        CASE 
            WHEN ar.clock_out_time IS NOT NULL 
            THEN EXTRACT(EPOCH FROM (ar.clock_out_time - ar.clock_in_time)) / 3600
            ELSE NULL 
        END as hours_worked
    FROM attendance_records ar
    JOIN profiles p ON ar.staff_id = p.id
    WHERE (staff_id IS NULL OR ar.staff_id = get_attendance_summary.staff_id)
    AND DATE(ar.clock_in_time) BETWEEN start_date AND end_date
    ORDER BY ar.clock_in_time DESC;
END;
$$ LANGUAGE plpgsql;

-- ==============================================
-- STOCK MANAGEMENT FUNCTIONS
-- ==============================================

-- Function to add stock
CREATE OR REPLACE FUNCTION add_stock(
    item_id UUID,
    location_id UUID,
    quantity INTEGER,
    staff_id UUID,
    notes TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    transaction_id UUID;
    item_name TEXT;
    location_name TEXT;
    staff_name TEXT;
BEGIN
    -- Get item name
    SELECT name INTO item_name FROM stock_items WHERE id = item_id;
    
    -- Get location name
    SELECT name INTO location_name FROM locations WHERE id = location_id;
    
    -- Get staff name
    SELECT full_name INTO staff_name FROM profiles WHERE id = staff_id;
    
    INSERT INTO stock_transactions (
        item_id, item_name, location_id, location_name, 
        quantity, transaction_type, staff_id, staff_name, notes
    )
    VALUES (
        item_id, item_name, location_id, location_name,
        quantity, 'IN', staff_id, staff_name, notes
    )
    RETURNING id INTO transaction_id;
    
    RETURN transaction_id;
END;
$$ LANGUAGE plpgsql;

-- Function to remove stock
CREATE OR REPLACE FUNCTION remove_stock(
    item_id UUID,
    location_id UUID,
    quantity INTEGER,
    staff_id UUID,
    department TEXT,
    notes TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    transaction_id UUID;
    item_name TEXT;
    location_name TEXT;
    staff_name TEXT;
    current_stock INTEGER;
BEGIN
    -- Check current stock level
    SELECT calculate_stock_level(item_id, location_id) INTO current_stock;
    
    IF current_stock < quantity THEN
        RAISE EXCEPTION 'Insufficient stock. Current: %, Requested: %', current_stock, quantity;
    END IF;
    
    -- Get item name
    SELECT name INTO item_name FROM stock_items WHERE id = item_id;
    
    -- Get location name
    SELECT name INTO location_name FROM locations WHERE id = location_id;
    
    -- Get staff name
    SELECT full_name INTO staff_name FROM profiles WHERE id = staff_id;
    
    INSERT INTO stock_transactions (
        item_id, item_name, location_id, location_name, 
        quantity, transaction_type, staff_id, staff_name, department, notes
    )
    VALUES (
        item_id, item_name, location_id, location_name,
        quantity, 'OUT', staff_id, staff_name, department, notes
    )
    RETURNING id INTO transaction_id;
    
    RETURN transaction_id;
END;
$$ LANGUAGE plpgsql;

-- Function to transfer stock between departments
CREATE OR REPLACE FUNCTION transfer_stock(
    item_id UUID,
    from_department TEXT,
    to_department TEXT,
    quantity INTEGER,
    staff_id UUID,
    notes TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    transfer_id UUID;
    item_name TEXT;
    staff_name TEXT;
    from_location_id UUID;
    to_location_id UUID;
BEGIN
    -- Get item name
    SELECT name INTO item_name FROM stock_items WHERE id = item_id;
    
    -- Get staff name
    SELECT full_name INTO staff_name FROM profiles WHERE id = staff_id;
    
    -- Find locations for departments (simplified - you might need more complex logic)
    SELECT id INTO from_location_id FROM locations WHERE name ILIKE '%' || from_department || '%' LIMIT 1;
    SELECT id INTO to_location_id FROM locations WHERE name ILIKE '%' || to_department || '%' LIMIT 1;
    
    -- Remove from source
    PERFORM remove_stock(item_id, from_location_id, quantity, staff_id, from_department, notes);
    
    -- Add to destination
    PERFORM add_stock(item_id, to_location_id, quantity, staff_id, notes);
    
    -- Record transfer
    INSERT INTO department_transfers (
        item_id, item_name, from_department, to_department, 
        quantity, transferred_by, notes
    )
    VALUES (
        item_id, item_name, from_department, to_department,
        quantity, staff_id, notes
    )
    RETURNING id INTO transfer_id;
    
    RETURN transfer_id;
END;
$$ LANGUAGE plpgsql;

-- ==============================================
-- BOOKING FUNCTIONS
-- ==============================================

-- Function to create booking
CREATE OR REPLACE FUNCTION create_booking(
    guest_name TEXT,
    guest_email TEXT,
    guest_phone TEXT,
    room_id UUID,
    check_in_date DATE,
    check_out_date DATE,
    created_by UUID,
    notes TEXT DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    booking_id UUID;
    room_number TEXT;
    room_type_id UUID;
    room_price DECIMAL;
    total_days INTEGER;
    total_amount DECIMAL;
BEGIN
    -- Get room details
    SELECT r.room_number, r.type_id, rt.price 
    INTO room_number, room_type_id, room_price
    FROM rooms r
    JOIN room_types rt ON r.type_id = rt.id
    WHERE r.id = room_id;
    
    -- Calculate total days and amount
    total_days := check_out_date - check_in_date;
    total_amount := room_price * total_days;
    
    -- Create booking
    INSERT INTO bookings (
        guest_name, guest_email, guest_phone, room_id, room_number,
        check_in_date, check_out_date, total_amount, created_by, notes
    )
    VALUES (
        guest_name, guest_email, guest_phone, room_id, room_number,
        check_in_date, check_out_date, total_amount, created_by, notes
    )
    RETURNING id INTO booking_id;
    
    RETURN booking_id;
END;
$$ LANGUAGE plpgsql;

-- Function to check in guest
CREATE OR REPLACE FUNCTION check_in_guest(booking_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    -- Update booking status
    UPDATE bookings 
    SET status = 'Checked-in'
    WHERE id = booking_id AND status = 'Pending Check-in';
    
    -- Update room status
    UPDATE rooms 
    SET status = 'Occupied'
    WHERE id = (SELECT room_id FROM bookings WHERE id = booking_id);
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function to check out guest
CREATE OR REPLACE FUNCTION check_out_guest(booking_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    -- Update booking status
    UPDATE bookings 
    SET status = 'Checked-out'
    WHERE id = booking_id AND status = 'Checked-in';
    
    -- Update room status
    UPDATE rooms 
    SET status = 'Dirty'
    WHERE id = (SELECT room_id FROM bookings WHERE id = booking_id);
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- ==============================================
-- MAINTENANCE FUNCTIONS
-- ==============================================

-- Function to create work order
CREATE OR REPLACE FUNCTION create_work_order(
    title TEXT,
    description TEXT,
    priority TEXT,
    room_id UUID DEFAULT NULL,
    assigned_to UUID DEFAULT NULL,
    created_by UUID,
    estimated_cost DECIMAL DEFAULT NULL,
    due_date DATE DEFAULT NULL
)
RETURNS UUID AS $$
DECLARE
    work_order_id UUID;
BEGIN
    INSERT INTO work_orders (
        title, description, priority, room_id, 
        assigned_to, created_by, estimated_cost, due_date
    )
    VALUES (
        title, description, priority, room_id,
        assigned_to, created_by, estimated_cost, due_date
    )
    RETURNING id INTO work_order_id;
    
    RETURN work_order_id;
END;
$$ LANGUAGE plpgsql;

-- Function to complete work order
CREATE OR REPLACE FUNCTION complete_work_order(
    work_order_id UUID,
    actual_cost DECIMAL DEFAULT NULL,
    completion_notes TEXT DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE work_orders 
    SET 
        status = 'Completed',
        actual_cost = COALESCE(complete_work_order.actual_cost, estimated_cost),
        completed_at = CURRENT_TIMESTAMP
    WHERE id = work_order_id AND status IN ('Open', 'In Progress');
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- ==============================================
-- CLEANUP AND MAINTENANCE
-- ==============================================

-- Function to clean old notifications
CREATE OR REPLACE FUNCTION clean_old_notifications(days_to_keep INTEGER DEFAULT 30)
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM notifications 
    WHERE created_at < CURRENT_DATE - INTERVAL '1 day' * days_to_keep
    AND is_read = true;
    
    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

-- Function to archive old bookings
CREATE OR REPLACE FUNCTION archive_old_bookings(days_to_keep INTEGER DEFAULT 365)
RETURNS INTEGER AS $$
DECLARE
    archived_count INTEGER;
BEGIN
    -- This would typically move data to an archive table
    -- For now, we'll just delete very old cancelled bookings
    DELETE FROM bookings 
    WHERE status = 'Cancelled' 
    AND created_at < CURRENT_DATE - INTERVAL '1 day' * days_to_keep;
    
    GET DIAGNOSTICS archived_count = ROW_COUNT;
    RETURN archived_count;
END;
$$ LANGUAGE plpgsql;

-- ==============================================
-- VIEWS FOR COMMON QUERIES
-- ==============================================

-- View for current room status
CREATE OR REPLACE VIEW current_room_status AS
SELECT 
    r.id,
    r.room_number,
    rt.type as room_type,
    r.status,
    rt.price,
    b.guest_name,
    b.check_in_date,
    b.check_out_date,
    b.total_amount,
    b.paid_amount
FROM rooms r
JOIN room_types rt ON r.type_id = rt.id
LEFT JOIN bookings b ON r.id = b.room_id 
    AND b.status IN ('Checked-in', 'Pending Check-in')
ORDER BY r.room_number;

-- View for low stock alerts
CREATE OR REPLACE VIEW low_stock_alerts AS
SELECT 
    si.id,
    si.name as item_name,
    l.name as location_name,
    calculate_stock_level(si.id, l.id) as current_stock,
    si.min_stock_level,
    (si.min_stock_level - calculate_stock_level(si.id, l.id)) as shortage
FROM stock_items si
CROSS JOIN locations l
WHERE calculate_stock_level(si.id, l.id) <= si.min_stock_level
AND calculate_stock_level(si.id, l.id) > 0;

-- View for staff performance
CREATE OR REPLACE VIEW staff_performance AS
SELECT 
    p.id,
    p.full_name,
    COUNT(DISTINCT ar.id) as attendance_days,
    AVG(EXTRACT(EPOCH FROM (ar.clock_out_time - ar.clock_in_time)) / 3600) as avg_hours_per_day,
    COUNT(DISTINCT b.id) as bookings_handled,
    COUNT(DISTINCT st.id) as stock_transactions
FROM profiles p
LEFT JOIN attendance_records ar ON p.id = ar.staff_id 
    AND ar.clock_in_time >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN bookings b ON p.id = b.created_by 
    AND b.created_at >= CURRENT_DATE - INTERVAL '30 days'
LEFT JOIN stock_transactions st ON p.id = st.staff_id 
    AND st.created_at >= CURRENT_DATE - INTERVAL '30 days'
WHERE array_length(p.roles, 1) > 0
GROUP BY p.id, p.full_name;

-- Grant permissions on new functions and views
GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO authenticated;
GRANT SELECT ON ALL SEQUENCES IN SCHEMA public TO authenticated;
