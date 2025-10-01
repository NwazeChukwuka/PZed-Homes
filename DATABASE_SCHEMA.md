# P-ZED Homes Database Schema

This document outlines the complete database schema required for the P-ZED Homes Flutter application based on the codebase analysis.

## Core Tables

### 1. **profiles** (User Management)
```sql
CREATE TABLE profiles (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    full_name VARCHAR(255) NOT NULL,
    phone VARCHAR(20),
    status VARCHAR(50) DEFAULT 'active',
    roles TEXT[] DEFAULT '{}',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 2. **room_types** (Room Categories)
```sql
CREATE TABLE room_types (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    type VARCHAR(100) NOT NULL,
    price INTEGER NOT NULL, -- Price in kobo
    description TEXT,
    image_url VARCHAR(500),
    amenities TEXT[],
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 3. **rooms** (Individual Rooms)
```sql
CREATE TABLE rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_number VARCHAR(10) UNIQUE NOT NULL,
    room_type_id UUID REFERENCES room_types(id),
    status VARCHAR(50) DEFAULT 'Available', -- Available, Occupied, Dirty, Maintenance
    floor INTEGER,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 4. **bookings** (Guest Reservations)
```sql
CREATE TABLE bookings (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    guest_profile_id UUID REFERENCES profiles(id),
    room_id UUID REFERENCES rooms(id),
    check_in_date TIMESTAMP WITH TIME ZONE NOT NULL,
    check_out_date TIMESTAMP WITH TIME ZONE NOT NULL,
    status VARCHAR(50) DEFAULT 'Pending Check-in', -- Pending Check-in, Checked-in, Checked-out
    extra_charges JSONB DEFAULT '[]',
    total_amount INTEGER, -- Total in kobo
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 5. **booking_charges** (Additional Charges)
```sql
CREATE TABLE booking_charges (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    booking_id UUID REFERENCES bookings(id) ON DELETE CASCADE,
    item_name VARCHAR(255) NOT NULL,
    quantity INTEGER DEFAULT 1,
    unit_price INTEGER NOT NULL, -- Price in kobo
    total_price INTEGER NOT NULL, -- Total in kobo
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## Inventory & Stock Management

### 6. **categories** (Inventory Categories)
```sql
CREATE TABLE categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 7. **inventory_items** (Stock Items)
```sql
CREATE TABLE inventory_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    current_stock INTEGER DEFAULT 0,
    unit VARCHAR(50) NOT NULL, -- kg, liters, pieces, etc.
    category_id UUID REFERENCES categories(id),
    min_stock_level INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 8. **stock_transactions** (Stock Movements)
```sql
CREATE TABLE stock_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_name VARCHAR(255) NOT NULL,
    quantity INTEGER NOT NULL,
    unit VARCHAR(50) NOT NULL,
    location VARCHAR(255),
    transaction_type VARCHAR(50) NOT NULL, -- purchase, usage, transfer, adjustment
    notes TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 9. **inventory_transactions** (Detailed Inventory Tracking)
```sql
CREATE TABLE inventory_transactions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_id UUID REFERENCES inventory_items(id),
    quantity INTEGER NOT NULL,
    notes TEXT,
    transaction_type VARCHAR(50) NOT NULL, -- restock, usage
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 10. **stock_items** (Alternative Stock Items)
```sql
CREATE TABLE stock_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    unit VARCHAR(50) NOT NULL,
    current_stock INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 11. **locations** (Storage Locations)
```sql
CREATE TABLE locations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 12. **department_transfers** (Inter-department Transfers)
```sql
CREATE TABLE department_transfers (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    item_name VARCHAR(255) NOT NULL,
    quantity INTEGER NOT NULL,
    source_department VARCHAR(255) NOT NULL,
    destination_department VARCHAR(255) NOT NULL,
    status VARCHAR(50) DEFAULT 'Pending', -- Pending, Approved, Completed
    requested_by UUID REFERENCES profiles(id),
    approved_by UUID REFERENCES profiles(id),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## Point of Sale & Menu

### 13. **menu_items** (POS Menu Items)
```sql
CREATE TABLE menu_items (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    price INTEGER NOT NULL, -- Price in kobo
    department VARCHAR(100), -- Kitchen, Bar, etc.
    barcode VARCHAR(100),
    description TEXT,
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## Financial Management

### 14. **expenses** (Expense Tracking)
```sql
CREATE TABLE expenses (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID REFERENCES profiles(id),
    amount INTEGER NOT NULL, -- Amount in kobo
    category VARCHAR(100) NOT NULL,
    department VARCHAR(100),
    description TEXT,
    transaction_date TIMESTAMP WITH TIME ZONE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 15. **expense_categories** (Expense Categories)
```sql
CREATE TABLE expense_categories (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 16. **departments** (Organizational Departments)
```sql
CREATE TABLE departments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(100) UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## Maintenance & Assets

### 17. **assets** (Property Assets)
```sql
CREATE TABLE assets (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name VARCHAR(255) NOT NULL,
    description TEXT,
    location VARCHAR(255),
    status VARCHAR(50) DEFAULT 'Operational', -- Operational, Maintenance, Out of Service
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 18. **work_orders** (Maintenance Work Orders)
```sql
CREATE TABLE work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    asset_id UUID REFERENCES assets(id),
    reported_by_id UUID REFERENCES profiles(id),
    issue_description TEXT NOT NULL,
    location VARCHAR(255),
    status VARCHAR(50) DEFAULT 'Pending', -- Pending, In Progress, Completed
    priority VARCHAR(50) DEFAULT 'Medium', -- Low, Medium, High, Critical
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

### 19. **maintenance_work_orders** (Alternative Maintenance Table)
```sql
CREATE TABLE maintenance_work_orders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reported_by_id UUID REFERENCES profiles(id),
    asset_id UUID REFERENCES assets(id),
    issue_description TEXT NOT NULL,
    location VARCHAR(255),
    status VARCHAR(50) DEFAULT 'Pending',
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## Communications

### 20. **posts** (Announcements)
```sql
CREATE TABLE posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    title VARCHAR(255) NOT NULL,
    content TEXT NOT NULL,
    author_id UUID REFERENCES profiles(id),
    is_published BOOLEAN DEFAULT true,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## HR & Attendance

### 21. **attendance_records** (Staff Attendance)
```sql
CREATE TABLE attendance_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    profile_id UUID REFERENCES profiles(id),
    clock_in_time TIMESTAMP WITH TIME ZONE NOT NULL,
    clock_out_time TIMESTAMP WITH TIME ZONE,
    date DATE NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);
```

## Indexes for Performance

```sql
-- Booking indexes
CREATE INDEX idx_bookings_status ON bookings(status);
CREATE INDEX idx_bookings_dates ON bookings(check_in_date, check_out_date);
CREATE INDEX idx_bookings_guest ON bookings(guest_profile_id);

-- Room indexes
CREATE INDEX idx_rooms_status ON rooms(status);
CREATE INDEX idx_rooms_type ON rooms(room_type_id);

-- Inventory indexes
CREATE INDEX idx_inventory_items_category ON inventory_items(category_id);
CREATE INDEX idx_stock_transactions_type ON stock_transactions(transaction_type);
CREATE INDEX idx_stock_transactions_date ON stock_transactions(created_at);

-- Attendance indexes
CREATE INDEX idx_attendance_profile_date ON attendance_records(profile_id, date);

-- Expense indexes
CREATE INDEX idx_expenses_date ON expenses(transaction_date);
CREATE INDEX idx_expenses_category ON expenses(category);

-- Work order indexes
CREATE INDEX idx_work_orders_status ON work_orders(status);
CREATE INDEX idx_work_orders_asset ON work_orders(asset_id);
```

## Row Level Security (RLS) Policies

Enable RLS on all tables:

```sql
-- Enable RLS on all tables
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE bookings ENABLE ROW LEVEL SECURITY;
ALTER TABLE rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE inventory_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_transactions ENABLE ROW LEVEL SECURITY;
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE attendance_records ENABLE ROW LEVEL SECURITY;

-- Example policies (customize based on your requirements)
-- Allow authenticated users to read their own profile
CREATE POLICY "Users can view own profile" ON profiles
    FOR SELECT USING (auth.uid() = id);

-- Allow staff to view all bookings
CREATE POLICY "Staff can view all bookings" ON bookings
    FOR SELECT USING (
        EXISTS (
            SELECT 1 FROM profiles 
            WHERE profiles.id = auth.uid() 
            AND 'staff' = ANY(profiles.roles)
        )
    );
```

## Sample Data

### Insert sample room types:
```sql
INSERT INTO room_types (type, price, description) VALUES
('Standard Room', 1500000, 'Comfortable and affordable'),
('Classic Room', 2000000, 'Enhanced amenities and more space'),
('Diplomatic Room', 2500000, 'Spacious and refined'),
('Deluxe Room', 3000000, 'Premium experience with superior furnishings'),
('Executive Suite', 5000000, 'The pinnacle of luxury');
```

### Insert sample categories:
```sql
INSERT INTO categories (name) VALUES
('Food & Beverage'),
('Cleaning Supplies'),
('Maintenance'),
('Office Supplies'),
('Electronics');
```

### Insert sample departments:
```sql
INSERT INTO departments (name) VALUES
('Front Desk'),
('Housekeeping'),
('Kitchen'),
('Bar'),
('Maintenance'),
('Management');
```

### Insert sample expense categories:
```sql
INSERT INTO expense_categories (name) VALUES
('Utilities'),
('Maintenance'),
('Supplies'),
('Staff'),
('Marketing'),
('Administrative');
```

## Supabase Configuration

1. **Enable Realtime** for tables that need live updates:
```sql
ALTER PUBLICATION supabase_realtime ADD TABLE bookings;
ALTER PUBLICATION supabase_realtime ADD TABLE stock_transactions;
ALTER PUBLICATION supabase_realtime ADD TABLE work_orders;
ALTER PUBLICATION supabase_realtime ADD TABLE posts;
ALTER PUBLICATION supabase_realtime ADD TABLE attendance_records;
```

2. **Configure Storage** for file uploads (if needed):
```sql
-- Create storage buckets
INSERT INTO storage.buckets (id, name, public) VALUES
('room-images', 'room-images', true),
('profile-photos', 'profile-photos', true),
('documents', 'documents', false);
```

This schema covers all the functionality found in your Flutter application and provides a solid foundation for the P-ZED Homes hotel management system.
