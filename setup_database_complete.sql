-- P-ZED Homes Complete Database Schema
-- This file contains all the necessary tables, relationships, and sample data
-- for the P-ZED Homes Hotel Management System

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Drop existing tables if they exist (for clean setup)
DROP TABLE IF EXISTS notifications CASCADE;
DROP TABLE IF EXISTS department_transfers CASCADE;
DROP TABLE IF EXISTS inventory_transactions CASCADE;
DROP TABLE IF EXISTS stock_transactions CASCADE;
DROP TABLE IF EXISTS booking_charges CASCADE;
DROP TABLE IF EXISTS attendance_records CASCADE;
DROP TABLE IF EXISTS work_orders CASCADE;
DROP TABLE IF EXISTS maintenance_work_orders CASCADE;
DROP TABLE IF EXISTS assets CASCADE;
DROP TABLE IF EXISTS expense_categories CASCADE;
DROP TABLE IF EXISTS expenses CASCADE;
DROP TABLE IF EXISTS posts CASCADE;
DROP TABLE IF EXISTS locations CASCADE;
DROP TABLE IF EXISTS menu_items CASCADE;
DROP TABLE IF EXISTS categories CASCADE;
DROP TABLE IF EXISTS inventory_items CASCADE;
DROP TABLE IF EXISTS stock_items CASCADE;
DROP TABLE IF EXISTS departments CASCADE;
DROP TABLE IF EXISTS bookings CASCADE;
DROP TABLE IF EXISTS rooms CASCADE;
DROP TABLE IF EXISTS room_types CASCADE;
DROP TABLE IF EXISTS profiles CASCADE;

-- Create profiles table (users)
CREATE TABLE profiles (
    id UUID REFERENCES auth.users(id) PRIMARY KEY,
    full_name TEXT,
    email TEXT UNIQUE,
    phone TEXT,
    address TEXT,
    roles TEXT[] DEFAULT '{}',
    avatar_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create room_types table
CREATE TABLE room_types (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    type TEXT NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    capacity INTEGER DEFAULT 1,
    amenities TEXT[] DEFAULT '{}',
    image_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create rooms table
CREATE TABLE rooms (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    room_number TEXT UNIQUE NOT NULL,
    type_id UUID REFERENCES room_types(id),
    type TEXT,
    status TEXT DEFAULT 'Vacant' CHECK (status IN ('Vacant', 'Occupied', 'Dirty', 'Cleaning', 'Maintenance')),
    floor INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create bookings table
CREATE TABLE bookings (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    guest_name TEXT NOT NULL,
    guest_email TEXT,
    guest_phone TEXT,
    room_id UUID REFERENCES rooms(id),
    room_number TEXT,
    check_in_date DATE NOT NULL,
    check_out_date DATE NOT NULL,
    status TEXT DEFAULT 'Pending Check-in' CHECK (status IN ('Pending Check-in', 'Checked-in', 'Checked-out', 'Cancelled')),
    total_amount DECIMAL(10,2) DEFAULT 0,
    paid_amount DECIMAL(10,2) DEFAULT 0,
    extra_charges JSONB DEFAULT '{}',
    notes TEXT,
    created_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create booking_charges table
CREATE TABLE booking_charges (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    booking_id UUID REFERENCES bookings(id) ON DELETE CASCADE,
    item_name TEXT NOT NULL,
    price DECIMAL(10,2) NOT NULL,
    quantity INTEGER DEFAULT 1,
    department TEXT,
    added_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create departments table
CREATE TABLE departments (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    manager_id UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create locations table
CREATE TABLE locations (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    type TEXT CHECK (type IN ('Kitchen', 'Bar', 'Storage', 'Office', 'Other')),
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create categories table
CREATE TABLE categories (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create menu_items table
CREATE TABLE menu_items (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    price DECIMAL(10,2) NOT NULL,
    category_id UUID REFERENCES categories(id),
    department TEXT,
    barcode TEXT,
    is_available BOOLEAN DEFAULT true,
    image_url TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create stock_items table
CREATE TABLE stock_items (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    unit TEXT DEFAULT 'piece',
    min_stock_level INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create stock_transactions table
CREATE TABLE stock_transactions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    item_id UUID REFERENCES stock_items(id),
    item_name TEXT NOT NULL,
    location_id UUID REFERENCES locations(id),
    location_name TEXT,
    quantity INTEGER NOT NULL,
    transaction_type TEXT CHECK (transaction_type IN ('IN', 'OUT', 'TRANSFER', 'ADJUSTMENT')),
    reference TEXT,
    staff_id UUID REFERENCES profiles(id),
    staff_name TEXT,
    department TEXT,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create inventory_items table
CREATE TABLE inventory_items (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    unit_price DECIMAL(10,2),
    current_stock INTEGER DEFAULT 0,
    min_stock_level INTEGER DEFAULT 0,
    location_id UUID REFERENCES locations(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create inventory_transactions table
CREATE TABLE inventory_transactions (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    item_id UUID REFERENCES inventory_items(id),
    transaction_type TEXT CHECK (transaction_type IN ('IN', 'OUT', 'ADJUSTMENT')),
    quantity INTEGER NOT NULL,
    unit_price DECIMAL(10,2),
    total_amount DECIMAL(10,2),
    staff_id UUID REFERENCES profiles(id),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create department_transfers table
CREATE TABLE department_transfers (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    item_id UUID REFERENCES stock_items(id),
    item_name TEXT NOT NULL,
    from_department TEXT NOT NULL,
    to_department TEXT NOT NULL,
    quantity INTEGER NOT NULL,
    transferred_by UUID REFERENCES profiles(id),
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create expenses table
CREATE TABLE expenses (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    amount DECIMAL(10,2) NOT NULL,
    category_id UUID REFERENCES expense_categories(id),
    department TEXT,
    staff_id UUID REFERENCES profiles(id),
    receipt_url TEXT,
    status TEXT DEFAULT 'Pending' CHECK (status IN ('Pending', 'Approved', 'Rejected')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create expense_categories table
CREATE TABLE expense_categories (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create assets table
CREATE TABLE assets (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    purchase_price DECIMAL(10,2),
    current_value DECIMAL(10,2),
    location TEXT,
    status TEXT DEFAULT 'Active' CHECK (status IN ('Active', 'Maintenance', 'Retired')),
    purchase_date DATE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create work_orders table
CREATE TABLE work_orders (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    priority TEXT DEFAULT 'Medium' CHECK (priority IN ('Low', 'Medium', 'High', 'Urgent')),
    status TEXT DEFAULT 'Open' CHECK (status IN ('Open', 'In Progress', 'Completed', 'Cancelled')),
    assigned_to UUID REFERENCES profiles(id),
    created_by UUID REFERENCES profiles(id),
    room_id UUID REFERENCES rooms(id),
    estimated_cost DECIMAL(10,2),
    actual_cost DECIMAL(10,2),
    due_date DATE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create maintenance_work_orders table
CREATE TABLE maintenance_work_orders (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    title TEXT NOT NULL,
    description TEXT,
    room_id UUID REFERENCES rooms(id),
    priority TEXT DEFAULT 'Medium' CHECK (priority IN ('Low', 'Medium', 'High', 'Urgent')),
    status TEXT DEFAULT 'Open' CHECK (status IN ('Open', 'In Progress', 'Completed', 'Cancelled')),
    assigned_to UUID REFERENCES profiles(id),
    created_by UUID REFERENCES profiles(id),
    estimated_cost DECIMAL(10,2),
    actual_cost DECIMAL(10,2),
    due_date DATE,
    completed_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create attendance_records table
CREATE TABLE attendance_records (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    staff_id UUID REFERENCES profiles(id),
    clock_in_time TIMESTAMP WITH TIME ZONE,
    clock_out_time TIMESTAMP WITH TIME ZONE,
    date DATE DEFAULT CURRENT_DATE,
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create posts table (for communications)
CREATE TABLE posts (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    title TEXT NOT NULL,
    content TEXT,
    author_id UUID REFERENCES profiles(id),
    department TEXT,
    is_announcement BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create notifications table
CREATE TABLE notifications (
    id UUID DEFAULT uuid_generate_v4() PRIMARY KEY,
    user_id UUID REFERENCES profiles(id),
    title TEXT NOT NULL,
    message TEXT,
    type TEXT DEFAULT 'info' CHECK (type IN ('info', 'warning', 'error', 'success')),
    is_read BOOLEAN DEFAULT false,
    data JSONB DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Create indexes for better performance
CREATE INDEX idx_bookings_room_id ON bookings(room_id);
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_dates ON bookings(check_in_date, check_out_date);
CREATE INDEX idx_rooms_status ON rooms(status);
CREATE INDEX idx_stock_transactions_item ON stock_transactions(item_id);
CREATE INDEX idx_stock_transactions_location ON stock_transactions(location_id);
CREATE INDEX idx_attendance_staff ON attendance_records(staff_id);
CREATE INDEX idx_attendance_date ON attendance_records(date);
CREATE INDEX idx_notifications_user ON notifications(user_id);
CREATE INDEX idx_notifications_read ON notifications(is_read);

-- Insert sample data

-- Insert room types
INSERT INTO room_types (type, description, price, capacity, amenities) VALUES
('Standard', 'Comfortable standard room with basic amenities', 15000.00, 2, ARRAY['WiFi', 'TV', 'AC', 'Private Bathroom']),
('Deluxe', 'Spacious deluxe room with premium amenities', 25000.00, 2, ARRAY['WiFi', 'TV', 'AC', 'Private Bathroom', 'Mini Bar', 'Balcony']),
('Suite', 'Luxurious suite with separate living area', 45000.00, 4, ARRAY['WiFi', 'TV', 'AC', 'Private Bathroom', 'Mini Bar', 'Balcony', 'Kitchenette', 'Living Room']),
('Presidential', 'Ultimate luxury presidential suite', 75000.00, 6, ARRAY['WiFi', 'TV', 'AC', 'Private Bathroom', 'Mini Bar', 'Balcony', 'Kitchen', 'Living Room', 'Dining Room', 'Butler Service']);

-- Insert rooms
INSERT INTO rooms (room_number, type_id, type, floor) VALUES
('101', (SELECT id FROM room_types WHERE type = 'Standard'), 'Standard', 1),
('102', (SELECT id FROM room_types WHERE type = 'Standard'), 'Standard', 1),
('103', (SELECT id FROM room_types WHERE type = 'Deluxe'), 'Deluxe', 1),
('104', (SELECT id FROM room_types WHERE type = 'Deluxe'), 'Deluxe', 1),
('201', (SELECT id FROM room_types WHERE type = 'Suite'), 'Suite', 2),
('202', (SELECT id FROM room_types WHERE type = 'Suite'), 'Suite', 2),
('301', (SELECT id FROM room_types WHERE type = 'Presidential'), 'Presidential', 3),
('302', (SELECT id FROM room_types WHERE type = 'Presidential'), 'Presidential', 3);

-- Insert departments
INSERT INTO departments (name, description) VALUES
('Reception', 'Guest services, check-in/out, and front desk operations'),
('VIP Bar', 'Premium bar service for VIP guests and special events'),
('Outside Bar', 'Outdoor bar service and poolside operations'),
('Kitchen', 'Food preparation, cooking, and culinary services'),
('Laundry', 'Linen and laundry services for rooms and facilities'),
('Mini Mart', 'Retail operations and convenience store services'),
('Housekeeping', 'Room cleaning, maintenance, and housekeeping services'),
('Security', 'Hotel security, safety, and surveillance'),
('Maintenance', 'Facility maintenance and repair services'),
('Management', 'Administrative and management operations'),
('Purchasing', 'Procurement and purchasing operations'),
('Storekeeping', 'Inventory and stock management');

-- Insert locations
INSERT INTO locations (name, type, description) VALUES
('Main Kitchen', 'Kitchen', 'Primary kitchen for food preparation'),
('VIP Bar', 'Bar', 'Premium bar for VIP guests'),
('Outside Bar', 'Bar', 'Outdoor bar and poolside service'),
('Reception Desk', 'Front Desk', 'Main reception and guest services'),
('Mini Mart Store', 'Retail', 'Convenience store and retail operations'),
('Laundry Room', 'Laundry', 'Linen and laundry processing'),
('Storage Room 1', 'Storage', 'Main storage area'),
('Storage Room 2', 'Storage', 'Secondary storage area'),
('Office', 'Office', 'Administrative office');

-- Insert sample profiles (users)
INSERT INTO profiles (id, full_name, email, phone, roles) VALUES
('550e8400-e29b-41d4-a716-446655440001', 'Hotel Owner', 'owner@pzed.home', '+1234567890', ARRAY['owner']),
('550e8400-e29b-41d4-a716-446655440002', 'General Manager', 'manager@pzed.home', '+1234567891', ARRAY['manager']),
('550e8400-e29b-41d4-a716-446655440003', 'Reception Manager', 'reception@pzed.home', '+1234567892', ARRAY['receptionist', 'manager']),
('550e8400-e29b-41d4-a716-446655440004', 'VIP Bar Manager', 'vipbar@pzed.home', '+1234567893', ARRAY['bartender', 'manager']),
('550e8400-e29b-41d4-a716-446655440005', 'Outside Bar Staff', 'outsidebar@pzed.home', '+1234567894', ARRAY['bartender']),
('550e8400-e29b-41d4-a716-446655440006', 'Head Chef', 'chef@pzed.home', '+1234567895', ARRAY['kitchen_staff', 'manager']),
('550e8400-e29b-41d4-a716-446655440007', 'Laundry Supervisor', 'laundry@pzed.home', '+1234567896', ARRAY['laundry_attendant', 'manager']),
('550e8400-e29b-41d4-a716-446655440008', 'Mini Mart Manager', 'minimart@pzed.home', '+1234567897', ARRAY['receptionist', 'manager']),
('550e8400-e29b-41d4-a716-446655440009', 'Housekeeping Supervisor', 'housekeeping@pzed.home', '+1234567898', ARRAY['housekeeper', 'manager']),
('550e8400-e29b-41d4-a716-446655440010', 'Security Manager', 'security@pzed.home', '+1234567899', ARRAY['security', 'manager']),
('550e8400-e29b-41d4-a716-446655440011', 'Purchasing Manager', 'purchasing@pzed.home', '+1234567800', ARRAY['purchaser', 'manager']),
('550e8400-e29b-41d4-a716-446655440012', 'Storekeeper', 'storekeeper@pzed.home', '+1234567801', ARRAY['storekeeper']),
('550e8400-e29b-41d4-a716-446655440013', 'Accountant', 'accountant@pzed.home', '+1234567802', ARRAY['accountant']),
('550e8400-e29b-41d4-a716-446655440014', 'HR Manager', 'hr@pzed.home', '+1234567803', ARRAY['hr', 'manager']);

-- Insert categories
INSERT INTO categories (name, description) VALUES
('Food', 'Food items and meals'),
('Beverages', 'Drinks and beverages'),
('Snacks', 'Light snacks and appetizers'),
('Alcohol', 'Alcoholic beverages'),
('Non-Alcohol', 'Non-alcoholic beverages'),
('Room Service', 'In-room dining items');

-- Insert menu items
INSERT INTO menu_items (name, description, price, category_id, department, barcode) VALUES
-- Kitchen items
('Jollof Rice', 'Traditional Nigerian jollof rice', 2500.00, (SELECT id FROM categories WHERE name = 'Food'), 'Kitchen', 'FOOD001'),
('Fried Rice', 'Chinese-style fried rice', 3000.00, (SELECT id FROM categories WHERE name = 'Food'), 'Kitchen', 'FOOD002'),
('Chicken Curry', 'Spicy chicken curry', 4000.00, (SELECT id FROM categories WHERE name = 'Food'), 'Kitchen', 'FOOD003'),
('Beef Steak', 'Grilled beef steak', 5000.00, (SELECT id FROM categories WHERE name = 'Food'), 'Kitchen', 'FOOD004'),
('Club Sandwich', 'Chicken club sandwich', 3500.00, (SELECT id FROM categories WHERE name = 'Food'), 'Kitchen', 'FOOD005'),
('Caesar Salad', 'Fresh Caesar salad', 2000.00, (SELECT id FROM categories WHERE name = 'Food'), 'Kitchen', 'FOOD006'),
-- VIP Bar items
('Premium Whiskey', 'High-end whiskey selection', 8000.00, (SELECT id FROM categories WHERE name = 'Alcohol'), 'VIP Bar', 'VIP001'),
('Champagne', 'Premium champagne', 12000.00, (SELECT id FROM categories WHERE name = 'Alcohol'), 'VIP Bar', 'VIP002'),
('Craft Cocktail', 'Signature cocktail', 4500.00, (SELECT id FROM categories WHERE name = 'Alcohol'), 'VIP Bar', 'VIP003'),
-- Outside Bar items
('Heineken Beer', 'Premium lager beer', 1500.00, (SELECT id FROM categories WHERE name = 'Alcohol'), 'Outside Bar', 'ALC001'),
('Red Wine', 'House red wine', 3000.00, (SELECT id FROM categories WHERE name = 'Alcohol'), 'Outside Bar', 'ALC002'),
('Coca Cola', 'Soft drink', 500.00, (SELECT id FROM categories WHERE name = 'Non-Alcohol'), 'Outside Bar', 'BEV001'),
('Sprite', 'Lemon-lime soft drink', 500.00, (SELECT id FROM categories WHERE name = 'Non-Alcohol'), 'Outside Bar', 'BEV002'),
-- Mini Mart items
('Bottled Water', 'Pure drinking water', 200.00, (SELECT id FROM categories WHERE name = 'Non-Alcohol'), 'Mini Mart', 'MART001'),
('Snacks Pack', 'Mixed snacks selection', 800.00, (SELECT id FROM categories WHERE name = 'Snacks'), 'Mini Mart', 'MART002'),
('Toiletries', 'Basic toiletries set', 1500.00, (SELECT id FROM categories WHERE name = 'Snacks'), 'Mini Mart', 'MART003');

-- Insert stock items
INSERT INTO stock_items (name, description, unit, min_stock_level) VALUES
('Rice', 'Basmati rice for cooking', 'kg', 50),
('Chicken', 'Fresh chicken meat', 'kg', 20),
('Beef', 'Fresh beef meat', 'kg', 15),
('Vegetables', 'Fresh vegetables', 'kg', 30),
('Cooking Oil', 'Vegetable cooking oil', 'liters', 10),
('Spices', 'Various cooking spices', 'packets', 25),
('Coca Cola', 'Soft drink bottles', 'bottles', 100),
('Beer', 'Beer bottles', 'bottles', 50),
('Wine', 'Wine bottles', 'bottles', 20),
('Cleaning Supplies', 'Hotel cleaning materials', 'units', 15);

-- Insert expense categories
INSERT INTO expense_categories (name, description) VALUES
('Food & Beverage', 'Food and drink related expenses'),
('Utilities', 'Electricity, water, gas bills'),
('Maintenance', 'Repair and maintenance costs'),
('Staff', 'Staff related expenses'),
('Marketing', 'Advertising and promotional costs'),
('Administrative', 'Office supplies and administrative costs'),
('Security', 'Security related expenses'),
('Other', 'Miscellaneous expenses');

-- Insert sample bookings
INSERT INTO bookings (guest_name, guest_email, guest_phone, room_id, room_number, check_in_date, check_out_date, status, total_amount, paid_amount) VALUES
('John Doe', 'john.doe@email.com', '+2348012345678', (SELECT id FROM rooms WHERE room_number = '101'), '101', CURRENT_DATE, CURRENT_DATE + INTERVAL '3 days', 'Checked-in', 45000.00, 45000.00),
('Jane Smith', 'jane.smith@email.com', '+2348023456789', (SELECT id FROM rooms WHERE room_number = '103'), '103', CURRENT_DATE + INTERVAL '1 day', CURRENT_DATE + INTERVAL '5 days', 'Pending Check-in', 100000.00, 50000.00),
('Mike Johnson', 'mike.johnson@email.com', '+2348034567890', (SELECT id FROM rooms WHERE room_number = '201'), '201', CURRENT_DATE - INTERVAL '2 days', CURRENT_DATE + INTERVAL '2 days', 'Checked-in', 180000.00, 180000.00);

-- Insert sample stock transactions
INSERT INTO stock_transactions (item_id, item_name, location_id, location_name, quantity, transaction_type, staff_id, staff_name, department, notes) VALUES
((SELECT id FROM stock_items WHERE name = 'Rice'), 'Rice', (SELECT id FROM locations WHERE name = 'Storage Room 1'), 'Storage Room 1', 100, 'IN', NULL, 'System', 'Purchasing', 'Initial stock'),
((SELECT id FROM stock_items WHERE name = 'Chicken'), 'Chicken', (SELECT id FROM locations WHERE name = 'Storage Room 1'), 'Storage Room 1', 50, 'IN', NULL, 'System', 'Purchasing', 'Initial stock'),
((SELECT id FROM stock_items WHERE name = 'Coca Cola'), 'Coca Cola', (SELECT id FROM locations WHERE name = 'Storage Room 2'), 'Storage Room 2', 200, 'IN', NULL, 'System', 'Purchasing', 'Initial stock'),
((SELECT id FROM stock_items WHERE name = 'Rice'), 'Rice', (SELECT id FROM locations WHERE name = 'Main Kitchen'), 'Main Kitchen', 10, 'OUT', NULL, 'Kitchen Staff', 'Kitchen', 'Daily cooking'),
((SELECT id FROM stock_items WHERE name = 'Chicken'), 'Chicken', (SELECT id FROM locations WHERE name = 'Main Kitchen'), 'Main Kitchen', 5, 'OUT', NULL, 'Kitchen Staff', 'Kitchen', 'Daily cooking');

-- Insert sample attendance records
INSERT INTO attendance_records (staff_id, clock_in_time, clock_out_time, date) VALUES
(NULL, CURRENT_TIMESTAMP - INTERVAL '8 hours', NULL, CURRENT_DATE),
(NULL, CURRENT_TIMESTAMP - INTERVAL '7 hours', NULL, CURRENT_DATE),
(NULL, CURRENT_TIMESTAMP - INTERVAL '6 hours', NULL, CURRENT_DATE);

-- Insert sample posts
INSERT INTO posts (title, content, author_id, department, is_announcement) VALUES
('Welcome to P-ZED Homes', 'Welcome to our hotel management system. Please familiarize yourself with the new features.', NULL, 'Management', true),
('Kitchen Meeting', 'Kitchen staff meeting scheduled for tomorrow at 9 AM.', NULL, 'Kitchen', false),
('Security Update', 'New security protocols have been implemented. Please review the updated guidelines.', NULL, 'Security', true);

-- Create RLS (Row Level Security) policies

-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE room_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE booking_charges ENABLE ROW LEVEL SECURITY;
ALTER TABLE departments ENABLE ROW LEVEL SECURITY;
ALTER TABLE locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE menu_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE department_transfers ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE expense_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE maintenance_work_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;

-- Create policies for profiles
CREATE POLICY "Users can view their own profile" ON profiles FOR SELECT USING (auth.uid() = id);
CREATE POLICY "Users can update their own profile" ON profiles FOR UPDATE USING (auth.uid() = id);
CREATE POLICY "Users can insert their own profile" ON profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Create policies for bookings (staff can view all, guests can view their own)
CREATE POLICY "Staff can view all bookings" ON bookings FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND 'receptionist' = ANY(profiles.roles)
  )
);
CREATE POLICY "Staff can insert bookings" ON bookings FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND 'receptionist' = ANY(profiles.roles)
  )
);
CREATE POLICY "Staff can update bookings" ON bookings FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND 'receptionist' = ANY(profiles.roles)
  )
);

-- Create policies for rooms
CREATE POLICY "Staff can view all rooms" ON rooms FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND ('receptionist' = ANY(profiles.roles) OR 'housekeeper' = ANY(profiles.roles))
  )
);
CREATE POLICY "Staff can update rooms" ON rooms FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND ('receptionist' = ANY(profiles.roles) OR 'housekeeper' = ANY(profiles.roles))
  )
);

-- Create policies for stock transactions
CREATE POLICY "Staff can view stock transactions" ON stock_transactions FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND ('storekeeper' = ANY(profiles.roles) OR 'purchaser' = ANY(profiles.roles) OR 'manager' = ANY(profiles.roles))
  )
);
CREATE POLICY "Staff can insert stock transactions" ON stock_transactions FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND ('storekeeper' = ANY(profiles.roles) OR 'purchaser' = ANY(profiles.roles))
  )
);

-- Create policies for menu items
CREATE POLICY "Staff can view menu items" ON menu_items FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND ('kitchen_staff' = ANY(profiles.roles) OR 'bartender' = ANY(profiles.roles) OR 'receptionist' = ANY(profiles.roles))
  )
);

-- Create policies for notifications
CREATE POLICY "Users can view their own notifications" ON notifications FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can update their own notifications" ON notifications FOR UPDATE USING (auth.uid() = user_id);

-- Create policies for posts
CREATE POLICY "Staff can view posts" ON posts FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND array_length(profiles.roles, 1) > 0
  )
);
CREATE POLICY "Staff can insert posts" ON posts FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND array_length(profiles.roles, 1) > 0
  )
);

-- Create policies for attendance records
CREATE POLICY "Staff can view attendance records" ON attendance_records FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND ('hr' = ANY(profiles.roles) OR 'manager' = ANY(profiles.roles))
  )
);
CREATE POLICY "Staff can insert attendance records" ON attendance_records FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM profiles 
    WHERE profiles.id = auth.uid() 
    AND array_length(profiles.roles, 1) > 0
  )
);

-- Create functions for automatic updates
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Create triggers for updated_at
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON profiles FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_room_types_updated_at BEFORE UPDATE ON room_types FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_rooms_updated_at BEFORE UPDATE ON rooms FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_bookings_updated_at BEFORE UPDATE ON bookings FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_menu_items_updated_at BEFORE UPDATE ON menu_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_stock_items_updated_at BEFORE UPDATE ON stock_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_inventory_items_updated_at BEFORE UPDATE ON inventory_items FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_expenses_updated_at BEFORE UPDATE ON expenses FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_assets_updated_at BEFORE UPDATE ON assets FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_work_orders_updated_at BEFORE UPDATE ON work_orders FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_maintenance_work_orders_updated_at BEFORE UPDATE ON maintenance_work_orders FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
CREATE TRIGGER update_posts_updated_at BEFORE UPDATE ON posts FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Create function to calculate stock levels
CREATE OR REPLACE FUNCTION calculate_stock_level(item_id UUID, location_id UUID)
RETURNS INTEGER AS $$
DECLARE
    total_in INTEGER;
    total_out INTEGER;
BEGIN
    SELECT COALESCE(SUM(quantity), 0) INTO total_in
    FROM stock_transactions 
    WHERE stock_transactions.item_id = calculate_stock_level.item_id 
    AND stock_transactions.location_id = calculate_stock_level.location_id
    AND transaction_type = 'IN';
    
    SELECT COALESCE(SUM(quantity), 0) INTO total_out
    FROM stock_transactions 
    WHERE stock_transactions.item_id = calculate_stock_level.item_id 
    AND stock_transactions.location_id = calculate_stock_level.location_id
    AND transaction_type = 'OUT';
    
    RETURN total_in - total_out;
END;
$$ LANGUAGE plpgsql;

-- Create function to get room occupancy rate
CREATE OR REPLACE FUNCTION get_occupancy_rate()
RETURNS DECIMAL AS $$
DECLARE
    total_rooms INTEGER;
    occupied_rooms INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_rooms FROM rooms;
    SELECT COUNT(*) INTO occupied_rooms FROM rooms WHERE status = 'Occupied';
    
    IF total_rooms = 0 THEN
        RETURN 0;
    END IF;
    
    RETURN (occupied_rooms::DECIMAL / total_rooms::DECIMAL) * 100;
END;
$$ LANGUAGE plpgsql;

-- Create function to get daily revenue
CREATE OR REPLACE FUNCTION get_daily_revenue(target_date DATE DEFAULT CURRENT_DATE)
RETURNS DECIMAL AS $$
DECLARE
    daily_revenue DECIMAL;
BEGIN
    SELECT COALESCE(SUM(paid_amount), 0) INTO daily_revenue
    FROM bookings 
    WHERE DATE(created_at) = target_date;
    
    RETURN daily_revenue;
END;
$$ LANGUAGE plpgsql;

-- Create views for common queries
CREATE VIEW room_occupancy AS
SELECT 
    r.room_number,
    r.type,
    r.status,
    rt.price,
    b.guest_name,
    b.check_in_date,
    b.check_out_date
FROM rooms r
LEFT JOIN room_types rt ON r.type_id = rt.id
LEFT JOIN bookings b ON r.id = b.room_id AND b.status = 'Checked-in';

CREATE VIEW stock_levels AS
SELECT 
    si.id,
    si.name,
    l.name as location_name,
    calculate_stock_level(si.id, l.id) as current_stock,
    si.min_stock_level
FROM stock_items si
CROSS JOIN locations l
WHERE calculate_stock_level(si.id, l.id) > 0;

CREATE VIEW daily_sales AS
SELECT 
    DATE(created_at) as sale_date,
    COUNT(*) as total_bookings,
    SUM(total_amount) as total_revenue,
    SUM(paid_amount) as paid_revenue
FROM bookings
GROUP BY DATE(created_at)
ORDER BY sale_date DESC;

-- Grant necessary permissions
GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;

-- Create indexes for better performance
CREATE INDEX CONCURRENTLY idx_bookings_guest_email ON bookings(guest_email);
CREATE INDEX CONCURRENTLY idx_bookings_created_at ON bookings(created_at);
CREATE INDEX CONCURRENTLY idx_stock_transactions_created_at ON stock_transactions(created_at);
CREATE INDEX CONCURRENTLY idx_attendance_records_staff_date ON attendance_records(staff_id, date);
CREATE INDEX CONCURRENTLY idx_notifications_user_created ON notifications(user_id, created_at);

-- Insert sample notifications
INSERT INTO notifications (user_id, title, message, type) VALUES
(NULL, 'New Booking', 'A new booking has been created for Room 101', 'info'),
(NULL, 'Stock Alert', 'Rice stock is running low in Storage Room 1', 'warning'),
(NULL, 'Maintenance Required', 'Room 102 requires maintenance', 'info'),
(NULL, 'Payment Received', 'Payment received for Booking #12345', 'success');

COMMIT;
