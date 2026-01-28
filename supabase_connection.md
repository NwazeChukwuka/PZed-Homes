-- ==============================================
-- P-ZED Homes Complete Database Schema for Supabase
-- ==============================================

-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ==============================================
-- DROP ALL EXISTING OBJECTS (Safe Update)
-- ==============================================

-- Drop Views
DROP VIEW IF EXISTS public.daily_sales CASCADE;
DROP VIEW IF EXISTS public.stock_levels CASCADE;
DROP VIEW IF EXISTS public.low_stock_alerts CASCADE;
DROP VIEW IF EXISTS public.room_occupancy CASCADE;
DROP VIEW IF EXISTS public.bookings_needing_room_assignment CASCADE;

-- Drop Functions
DROP FUNCTION IF EXISTS public.get_daily_revenue(DATE);
DROP FUNCTION IF EXISTS public.get_occupancy_rate();
DROP FUNCTION IF EXISTS public.calculate_stock_level(UUID, UUID) CASCADE;
DROP FUNCTION IF EXISTS public.check_out_guest(UUID);
DROP FUNCTION IF EXISTS public.check_in_guest(UUID);
DROP FUNCTION IF EXISTS public.assign_room_to_booking(UUID, UUID);
DROP FUNCTION IF EXISTS public.get_available_room_types(text, text);
DROP FUNCTION IF EXISTS public.confirm_purchase_order(uuid, uuid);
DROP FUNCTION IF EXISTS public.perform_stock_transfer(uuid, uuid, uuid, int, uuid);
DROP FUNCTION IF EXISTS public.create_stock_transfer(uuid, uuid, uuid, int, uuid, uuid, text);
DROP FUNCTION IF EXISTS public.has_delegated_permission(TEXT);
DROP FUNCTION IF EXISTS public.update_updated_at_column() CASCADE;
DROP FUNCTION IF EXISTS public.create_public_profile_for_new_user() CASCADE;
DROP FUNCTION IF EXISTS public.create_staff_profile(TEXT, TEXT, TEXT, TEXT, TEXT);

-- Drop Triggers
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP TRIGGER IF EXISTS update_posts_updated_at ON public.posts;
DROP TRIGGER IF EXISTS update_maintenance_work_orders_updated_at ON public.maintenance_work_orders;
DROP TRIGGER IF EXISTS update_work_orders_updated_at ON public.work_orders;
-- Note: kitchen_orders trigger will be dropped automatically when table is dropped with CASCADE
DROP TRIGGER IF EXISTS update_assets_updated_at ON public.assets;
DROP TRIGGER IF EXISTS update_expenses_updated_at ON public.expenses;
DROP TRIGGER IF EXISTS update_inventory_items_updated_at ON public.inventory_items;
DROP TRIGGER IF EXISTS update_stock_items_updated_at ON public.stock_items;
DROP TRIGGER IF EXISTS update_menu_items_updated_at ON public.menu_items;
DROP TRIGGER IF EXISTS update_bookings_updated_at ON public.bookings;
DROP TRIGGER IF EXISTS update_rooms_updated_at ON public.rooms;
DROP TRIGGER IF EXISTS update_room_types_updated_at ON public.room_types;
DROP TRIGGER IF EXISTS update_profiles_updated_at ON public.profiles;

-- Drop Policies (Drop all policies on each table)
DO $$ 
DECLARE
    r RECORD;
BEGIN
    FOR r IN (SELECT tablename FROM pg_tables WHERE schemaname = 'public') LOOP
        EXECUTE 'DROP POLICY IF EXISTS "Public profiles are viewable by everyone" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Users can update own profile" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Users can insert their own profile" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Staff view all bookings" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Guests view own bookings" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Staff can insert bookings" ON public.' || quote_ident(r.tablename);
  EXECUTE 'DROP POLICY IF EXISTS "Staff can update bookings" ON public.' || quote_ident(r.tablename);
  EXECUTE 'DROP POLICY IF EXISTS "Public can check availability" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Allow read access" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Staff view stock" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Staff can insert stock transactions" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Staff view transfers" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Admin finance access" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Staff access" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Staff can view attendance records" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Staff can insert attendance records" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Staff read posts" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Staff can insert posts" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Users can view their own notifications" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Users can update their own notifications" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Authorized view logs" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Public read" ON public.' || quote_ident(r.tablename);
        EXECUTE 'DROP POLICY IF EXISTS "Admin write" ON public.' || quote_ident(r.tablename);
    END LOOP;
END $$;

-- Drop Tables (in reverse dependency order)
DROP TABLE IF EXISTS public.kitchen_orders CASCADE;
DROP TABLE IF EXISTS public.kitchen_sales CASCADE;
DROP TABLE IF EXISTS public.booking_charges CASCADE;
DROP TABLE IF EXISTS public.bookings CASCADE;
DROP TABLE IF EXISTS public.smartlock_logs CASCADE;
DROP TABLE IF EXISTS public.access_delegations CASCADE;
DROP TABLE IF EXISTS public.notifications CASCADE;
DROP TABLE IF EXISTS public.posts CASCADE;
DROP TABLE IF EXISTS public.attendance_records CASCADE;
DROP TABLE IF EXISTS public.work_orders CASCADE;
DROP TABLE IF EXISTS public.maintenance_work_orders CASCADE;
DROP TABLE IF EXISTS public.assets CASCADE;
DROP TABLE IF EXISTS public.income_records CASCADE;
DROP TABLE IF EXISTS public.payroll_records CASCADE;
DROP TABLE IF EXISTS public.cash_deposits CASCADE;
DROP TABLE IF EXISTS public.debts CASCADE;
DROP TABLE IF EXISTS public.mini_mart_sales CASCADE;
DROP TABLE IF EXISTS public.mini_mart_items CASCADE;
DROP TABLE IF EXISTS public.department_sales CASCADE;
DROP TABLE IF EXISTS public.bartender_shifts CASCADE;
DROP TABLE IF EXISTS public.staff_role_assignments CASCADE;
DROP TABLE IF EXISTS public.expenses CASCADE;
DROP TABLE IF EXISTS public.purchase_order_items CASCADE;
DROP TABLE IF EXISTS public.purchase_orders CASCADE;
DROP TABLE IF EXISTS public.department_transfers CASCADE;
DROP TABLE IF EXISTS public.stock_transfers CASCADE;
DROP TABLE IF EXISTS public.stock_transactions CASCADE;
DROP TABLE IF EXISTS public.inventory_items CASCADE;
DROP TABLE IF EXISTS public.stock_items CASCADE;
DROP TABLE IF EXISTS public.menu_items CASCADE;
DROP TABLE IF EXISTS public.rooms CASCADE;
DROP TABLE IF EXISTS public.room_types CASCADE;
DROP TABLE IF EXISTS public.gallery_media CASCADE;
DROP TABLE IF EXISTS public.site_media CASCADE;
DROP TABLE IF EXISTS public.categories CASCADE;
DROP TABLE IF EXISTS public.expense_categories CASCADE;
DROP TABLE IF EXISTS public.departments CASCADE;
DROP TABLE IF EXISTS public.locations CASCADE;
DROP TABLE IF EXISTS public.profiles CASCADE;

-- ==============================================
-- 1. PROFILES TABLE (Linked to Auth)
-- ==============================================
CREATE TABLE public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    created_at TIMESTAMPTZ DEFAULT now() NOT NULL,
    full_name TEXT,
    phone TEXT,
    email TEXT, -- Optional, often helpful to mirror here
    roles TEXT[] DEFAULT '{guest}', -- Array of roles: 'owner', 'manager', 'receptionist', 'vip_bartender', 'outside_bartender', etc.
    status TEXT DEFAULT 'Active' CHECK (status IN ('Active', 'Inactive', 'Resigned', 'Terminated', 'Suspended')),
    department TEXT, -- e.g., 'reception', 'vip_bar', 'outside_bar', 'restaurant', 'laundry', 'mini_mart', 'storekeeping', 'purchasing', 'general'
    avatar_url TEXT,
    address TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

-- Profile Policies
-- CRITICAL: Users must be able to view their own profile for login to work
CREATE POLICY "Users can view own profile" 
ON public.profiles FOR SELECT USING (
  auth.uid() = id
);

-- Only active staff can view other profiles (resigned/terminated staff are blocked)
-- Updated to use helper functions to prevent infinite recursion
CREATE POLICY "Active staff can view profiles" 
ON public.profiles FOR SELECT USING (
  is_user_active(auth.uid())
);

CREATE POLICY "Users can update own profile" 
ON public.profiles FOR UPDATE USING (
  auth.uid() = id 
  AND status = 'Active' -- Can't update if resigned/terminated
);

CREATE POLICY "Users can insert their own profile" 
ON public.profiles FOR INSERT WITH CHECK (auth.uid() = id);

-- Owner/HR/Manager can create staff profiles (for HR screen)
-- Updated to use helper functions to prevent infinite recursion
CREATE POLICY "Owner HR and Manager can create staff profiles" 
ON public.profiles FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'hr')
    OR user_has_role(auth.uid(), 'manager')
  )
);

-- Owner/HR/Manager can update staff profiles
CREATE POLICY "Owner HR and Manager can update staff profiles" 
ON public.profiles FOR UPDATE 
USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'hr')
    OR user_has_role(auth.uid(), 'manager')
  )
)
WITH CHECK (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'hr')
    OR user_has_role(auth.uid(), 'manager')
  )
);

-- Auth Trigger (Automatically create profile on Sign Up)
CREATE OR REPLACE FUNCTION public.create_public_profile_for_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, email, roles)
  VALUES (
    new.id,
    new.raw_user_meta_data->>'full_name',
    new.email,
    ARRAY['guest'] -- Default role is ALWAYS guest
  );
  RETURN new;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE PROCEDURE public.create_public_profile_for_new_user();

-- ==============================================
-- 1b. RLS HELPER FUNCTIONS (Prevent Infinite Recursion)
-- ==============================================
-- These functions bypass RLS to prevent infinite recursion in policies

-- Helper function to check if user is active (bypasses RLS)
CREATE OR REPLACE FUNCTION public.is_user_active(user_id UUID)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = user_id
    AND status = 'Active'
  );
$$;

-- Helper function to check if user has role (bypasses RLS)
CREATE OR REPLACE FUNCTION public.user_has_role(user_id UUID, role_name TEXT)
RETURNS BOOLEAN
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = user_id
    AND status = 'Active'
    AND role_name = ANY(roles)
  );
$$;

-- Grant execute permission on the helper functions
GRANT EXECUTE ON FUNCTION public.is_user_active(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.user_has_role(UUID, TEXT) TO anon, authenticated;

-- ==============================================
-- 2. HELPER TABLES
-- ==============================================
CREATE TABLE public.locations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), 
    name TEXT UNIQUE NOT NULL,
    type TEXT CHECK (type IN ('Kitchen', 'Bar', 'Storage', 'Office', 'Other')),
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.departments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), 
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    manager_id UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.positions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    benefits TEXT, -- Comma-separated or JSON
    department TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_by_name TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.positions ENABLE ROW LEVEL SECURITY;

-- Positions policies
CREATE POLICY "Active staff can view positions" ON public.positions FOR SELECT USING (
  is_user_active(auth.uid())
);

CREATE POLICY "Active HR/Manager can manage positions" ON public.positions FOR ALL USING (
  is_user_active(auth.uid())
  AND user_has_role(auth.uid(), 'hr')
  OR user_has_role(auth.uid(), 'manager')
  OR user_has_role(auth.uid(), 'owner')
);

CREATE TABLE public.expense_categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(), 
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.categories (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

-- ==============================================
-- 2.1 SUPPLIERS (Purchasing)
-- ==============================================
CREATE TABLE public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    contact_phone TEXT,
    contact_email TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Purchasing can view suppliers" ON public.suppliers FOR SELECT USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'purchaser')
    OR user_has_role(auth.uid(), 'storekeeper')
    OR user_has_role(auth.uid(), 'accountant')
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
  )
);

CREATE POLICY "Purchaser can add suppliers" ON public.suppliers FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'purchaser')
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'accountant')
  )
);

CREATE POLICY "Management can manage suppliers" ON public.suppliers FOR ALL USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'accountant')
  )
);

-- ==============================================
-- 3. ROOM TYPES AND ROOMS
-- ==============================================
CREATE TABLE public.room_types (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    type TEXT NOT NULL UNIQUE,
    description TEXT,
    price INT8 NOT NULL, -- Stored in Kobo/Cents
    capacity INTEGER DEFAULT 1,
    amenities TEXT[] DEFAULT '{}',
    image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.rooms (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_number TEXT UNIQUE NOT NULL,
    type_id UUID REFERENCES public.room_types(id),
    type TEXT NOT NULL, -- 'Standard', 'Deluxe', etc. (denormalized for quick access)
    status TEXT DEFAULT 'Vacant' CHECK (status IN ('Vacant', 'Occupied', 'Dirty', 'Cleaning', 'Maintenance')),
    floor INTEGER,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.room_types ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.rooms ENABLE ROW LEVEL SECURITY;

-- Basic Read Policies
CREATE POLICY "Allow read access" ON public.room_types FOR SELECT USING (true);
CREATE POLICY "Allow read access" ON public.rooms FOR SELECT USING (true);
CREATE POLICY "Staff update rooms" ON public.rooms
FOR UPDATE
USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'receptionist')
    OR user_has_role(auth.uid(), 'housekeeper')
    OR user_has_role(auth.uid(), 'cleaner')
  )
)
WITH CHECK (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'receptionist')
    OR user_has_role(auth.uid(), 'housekeeper')
    OR user_has_role(auth.uid(), 'cleaner')
  )
);

-- Room status audit log
CREATE TABLE public.room_status_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
    old_status TEXT,
    new_status TEXT,
    changed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    changed_by_name TEXT,
    changed_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.room_status_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Staff read room status logs" ON public.room_status_logs
FOR SELECT
USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'receptionist')
    OR user_has_role(auth.uid(), 'housekeeper')
    OR user_has_role(auth.uid(), 'cleaner')
  )
);

CREATE OR REPLACE FUNCTION public.log_room_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'UPDATE' AND NEW.status IS DISTINCT FROM OLD.status THEN
        INSERT INTO public.room_status_logs (
            room_id,
            old_status,
            new_status,
            changed_by
        ) VALUES (
            NEW.id,
            OLD.status,
            NEW.status,
            auth.uid()
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER room_status_change_log
AFTER UPDATE ON public.rooms
FOR EACH ROW
EXECUTE FUNCTION public.log_room_status_change();

-- ==============================================
-- 4. INVENTORY AND STOCK
-- ==============================================
CREATE TABLE public.stock_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    preferred_supplier_id UUID REFERENCES public.suppliers(id),
    preferred_supplier_name TEXT,
    unit TEXT DEFAULT 'units', -- 'kg', 'bottles', 'packs'
    min_stock INT DEFAULT 10,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.inventory_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    category TEXT,
    unit_price INT8, -- Stored in Kobo/Cents (legacy/fallback)
    vip_bar_price INT8, -- Stored in Kobo/Cents (VIP Bar pricing)
    outside_bar_price INT8, -- Stored in Kobo/Cents (Outside Bar pricing)
    current_stock INTEGER DEFAULT 0,
    min_stock_level INTEGER DEFAULT 0,
    unit TEXT DEFAULT 'units', -- 'bottles', 'packs', 'kg', etc.
    department TEXT DEFAULT 'both', -- 'vip_bar', 'outside_bar', or 'both'
    location_id UUID REFERENCES public.locations(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.stock_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.inventory_items ENABLE ROW LEVEL SECURITY;

-- Policies
-- Stock items are visible to management/store staff and to departments that hold stock at their location
CREATE POLICY "Active staff view stock items" ON public.stock_items FOR SELECT USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'supervisor')
    OR user_has_role(auth.uid(), 'storekeeper')
    OR user_has_role(auth.uid(), 'purchaser')
    OR user_has_role(auth.uid(), 'accountant')
    OR EXISTS (
      SELECT 1
      FROM public.stock_transactions st
      JOIN public.locations l ON l.id = st.location_id
      WHERE st.stock_item_id = stock_items.id
      AND (
        (l.name = 'VIP Bar' AND user_has_role(auth.uid(), 'vip_bartender'))
        OR (l.name = 'Outside Bar' AND user_has_role(auth.uid(), 'outside_bartender'))
        OR (l.name = 'Kitchen' AND user_has_role(auth.uid(), 'kitchen_staff'))
        OR (l.name = 'Mini Mart' AND user_has_role(auth.uid(), 'receptionist'))
        OR (l.name = 'Housekeeping' AND (user_has_role(auth.uid(), 'housekeeper') OR user_has_role(auth.uid(), 'cleaner')))
        OR (l.name = 'Laundry' AND user_has_role(auth.uid(), 'laundry_attendant'))
      )
    )
  )
);

-- Management can manage stock items; purchasers can create new ones
CREATE POLICY "Management can manage stock items" ON public.stock_items FOR ALL USING (
  is_user_active(auth.uid())
  AND (user_has_role(auth.uid(), 'owner') OR user_has_role(auth.uid(), 'manager'))
);
CREATE POLICY "Purchaser can create stock items" ON public.stock_items FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND user_has_role(auth.uid(), 'purchaser')
);

-- Inventory items (bar items) are visible only to bar staff and management
CREATE POLICY "Bar staff view inventory items" ON public.inventory_items FOR SELECT USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'manager')
    OR (department = 'vip_bar' AND user_has_role(auth.uid(), 'vip_bartender'))
    OR (department = 'outside_bar' AND user_has_role(auth.uid(), 'outside_bartender'))
  )
);
CREATE POLICY "Management can manage inventory items" ON public.inventory_items FOR ALL USING (
  is_user_active(auth.uid())
  AND (user_has_role(auth.uid(), 'owner') OR user_has_role(auth.uid(), 'manager'))
);

-- ==============================================
-- 5. MENU ITEMS (Food, Drinks, AND Room Prices)
-- ==============================================
CREATE TABLE public.menu_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    description TEXT,
    price INT8 NOT NULL, -- Stored in Kobo/Cents
    department TEXT, -- 'reception', 'vip_bar', 'outside_bar', 'restaurant', 'laundry', 'mini_mart', 'storekeeping', 'purchasing', 'general'
    category TEXT,
    category_id UUID REFERENCES public.categories(id),
    image_url TEXT,
    stock_item_id UUID REFERENCES public.stock_items(id), -- Link to inventory for auto-deduction
    barcode TEXT,
    is_available BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.menu_items ENABLE ROW LEVEL SECURITY;

-- Basic Read Policies
CREATE POLICY "Allow read access" ON public.menu_items FOR SELECT USING (true);

-- ==============================================
-- 6. BOOKINGS TABLE (FIXED: Added requested_room_type)
-- ==============================================
CREATE TABLE public.bookings (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    guest_profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    room_id UUID REFERENCES public.rooms(id), -- NULL until receptionist assigns room
    requested_room_type TEXT, -- Room type requested by guest (e.g., 'Standard', 'Deluxe')
    check_in_date TIMESTAMPTZ NOT NULL,
    check_out_date TIMESTAMPTZ NOT NULL,
    status TEXT DEFAULT 'Pending Check-in' CHECK (status IN ('Pending Check-in', 'Checked-in', 'Checked-out', 'Cancelled')),
    total_amount INT8 DEFAULT 0, -- Stored in Kobo/Cents
    paid_amount INT8 DEFAULT 0, -- Stored in Kobo/Cents
    payment_method TEXT DEFAULT 'cash', -- 'cash', 'card', 'transfer', 'credit'
    payment_reference TEXT,
    payment_provider TEXT,
    payment_verified BOOLEAN DEFAULT false,
    terms_accepted BOOLEAN DEFAULT false,
    terms_version TEXT,
    guest_name TEXT,
    guest_email TEXT,
    guest_phone TEXT,
    discount_applied BOOLEAN DEFAULT false,
    discount_amount INT8 DEFAULT 0,
    discount_percentage NUMERIC(5,2) DEFAULT 0,
    discount_reason TEXT,
    discount_applied_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    discount_applied_by_name TEXT,
    extra_charges JSONB DEFAULT '[]'::jsonb, -- Stores POS orders: [{item: "Coke", price: 500, qty: 2}]
    notes TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_by_name TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.bookings ENABLE ROW LEVEL SECURITY;

-- Booking Policies
-- Only active staff can view bookings (resigned/terminated staff are blocked)
-- Updated to use helper functions to prevent infinite recursion
CREATE POLICY "Active staff view all bookings" ON public.bookings FOR SELECT 
USING (
  is_user_active(auth.uid())
  AND NOT user_has_role(auth.uid(), 'guest')
);

-- Allow public/anon access to bookings for availability checking
-- Note: This allows reading booking dates and room info for availability checking
-- Sensitive data (guest_profile_id, amounts) are still protected as they require joins
-- Public availability should be served via RPC only (no direct bookings access)

CREATE POLICY "Guests view own bookings" ON public.bookings FOR SELECT 
USING (auth.uid() = guest_profile_id);

CREATE POLICY "Active staff can insert bookings" ON public.bookings FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND (user_has_role(auth.uid(), 'receptionist') OR user_has_role(auth.uid(), 'guest'))
);

CREATE POLICY "Active staff can update bookings" ON public.bookings FOR UPDATE USING (
  is_user_active(auth.uid())
  AND user_has_role(auth.uid(), 'receptionist')
);

-- Booking Charges Table (Alternative to JSONB for complex charges)
CREATE TABLE public.booking_charges (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    booking_id UUID REFERENCES public.bookings(id) ON DELETE CASCADE,
    item_name TEXT NOT NULL,
    price INT8 NOT NULL, -- Stored in Kobo/Cents
    quantity INTEGER DEFAULT 1,
    department TEXT,
    added_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    added_by_name TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.booking_charges ENABLE ROW LEVEL SECURITY;

-- Booking charges policies
CREATE POLICY "Active staff view booking charges" ON public.booking_charges FOR SELECT
USING (is_user_active(auth.uid()));

CREATE POLICY "Staff can insert booking charges" ON public.booking_charges FOR INSERT
WITH CHECK (
  is_user_active(auth.uid())
  AND added_by = auth.uid()
  AND (
    user_has_role(auth.uid(), 'receptionist')
    OR user_has_role(auth.uid(), 'kitchen_staff')
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
  )
);

CREATE POLICY "Management can update booking charges" ON public.booking_charges FOR UPDATE
USING (
  is_user_active(auth.uid())
  AND (user_has_role(auth.uid(), 'manager') OR user_has_role(auth.uid(), 'owner'))
);

-- ==============================================
-- 7. STOCK TRANSACTIONS (Multi-Location Ledger)
-- ==============================================
CREATE TABLE public.stock_transactions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    stock_item_id UUID REFERENCES public.stock_items(id) NOT NULL,
    location_id UUID REFERENCES public.locations(id) NOT NULL,
    staff_profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    staff_name TEXT,
    transaction_type TEXT NOT NULL, -- 'Purchase', 'Transfer_In', 'Transfer_Out', 'Sale', 'Wastage', 'Adjustment', 'Direct_Supply'
    quantity INT NOT NULL, -- Positive or Negative
    shift_id UUID REFERENCES public.bartender_shifts(id),
    notes TEXT
);

ALTER TABLE public.stock_transactions ENABLE ROW LEVEL SECURITY;

-- Policies
-- Only active staff can view stock for their locations (management can view all)
CREATE POLICY "Active staff view stock" ON public.stock_transactions FOR SELECT USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'supervisor')
    OR user_has_role(auth.uid(), 'storekeeper')
    OR user_has_role(auth.uid(), 'purchaser')
    OR user_has_role(auth.uid(), 'accountant')
    OR location_id IN (
      SELECT l.id
      FROM public.locations l
      WHERE (
        (l.name = 'VIP Bar' AND user_has_role(auth.uid(), 'vip_bartender'))
        OR (l.name = 'Outside Bar' AND user_has_role(auth.uid(), 'outside_bartender'))
        OR (l.name = 'Kitchen' AND user_has_role(auth.uid(), 'kitchen_staff'))
        OR (l.name = 'Mini Mart' AND user_has_role(auth.uid(), 'receptionist'))
        OR (l.name = 'Housekeeping' AND (user_has_role(auth.uid(), 'housekeeper') OR user_has_role(auth.uid(), 'cleaner')))
        OR (l.name = 'Laundry' AND user_has_role(auth.uid(), 'laundry_attendant'))
      )
    )
  )
);
CREATE POLICY "Active staff can insert stock transactions" ON public.stock_transactions FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (
      'storekeeper' = ANY(p.roles) OR
      'purchaser' = ANY(p.roles) OR
      'manager' = ANY(p.roles) OR
      'owner' = ANY(p.roles) OR
      ('vip_bartender' = ANY(p.roles) AND location_id IN (SELECT id FROM public.locations WHERE name = 'VIP Bar')) OR
      ('outside_bartender' = ANY(p.roles) AND location_id IN (SELECT id FROM public.locations WHERE name = 'Outside Bar')) OR
      ('kitchen_staff' = ANY(p.roles) AND location_id IN (SELECT id FROM public.locations WHERE name = 'Kitchen')) OR
      ('receptionist' = ANY(p.roles) AND location_id IN (SELECT id FROM public.locations WHERE name = 'Mini Mart'))
    )
    AND (
      transaction_type <> 'Direct_Supply'
      OR user_has_role(auth.uid(), 'owner')
      OR user_has_role(auth.uid(), 'manager')
      OR user_has_role(auth.uid(), 'storekeeper')
    )
  )
);
-- ==============================================
-- 8.1. DIRECT SUPPLY REQUESTS (Bartender -> Management Approval)
-- ==============================================
CREATE TABLE public.direct_supply_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    stock_item_id UUID REFERENCES public.stock_items(id) NOT NULL,
    bar TEXT NOT NULL CHECK (bar IN ('vip_bar', 'outside_bar')),
    quantity INT NOT NULL CHECK (quantity > 0),
    requested_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    requested_by_name TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'denied')),
    approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    approved_by_name TEXT,
    approved_at TIMESTAMPTZ,
    notes TEXT
);

ALTER TABLE public.direct_supply_requests ENABLE ROW LEVEL SECURITY;

-- Bartenders can request for their own bar, management can view all
CREATE POLICY "Direct supply requests view" ON public.direct_supply_requests FOR SELECT USING (
  is_user_active(auth.uid())
  AND (
    requested_by = auth.uid()
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
  )
);

CREATE POLICY "Direct supply requests insert" ON public.direct_supply_requests FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND (
    (user_has_role(auth.uid(), 'vip_bartender') AND bar = 'vip_bar' AND requested_by = auth.uid())
    OR (user_has_role(auth.uid(), 'outside_bartender') AND bar = 'outside_bar' AND requested_by = auth.uid())
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
  )
);

CREATE POLICY "Direct supply requests update" ON public.direct_supply_requests FOR UPDATE USING (
  is_user_active(auth.uid())
  AND (user_has_role(auth.uid(), 'manager') OR user_has_role(auth.uid(), 'owner'))
);

-- Approval function (management only)
CREATE OR REPLACE FUNCTION public.approve_direct_supply(
    p_request_id uuid,
    p_action text,
    p_notes text DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_request record;
    v_location_id uuid;
    v_item_name text;
    v_inventory_id uuid;
BEGIN
    IF NOT (user_has_role(auth.uid(), 'manager') OR user_has_role(auth.uid(), 'owner')) THEN
        RAISE EXCEPTION 'Not authorized to approve direct supply';
    END IF;

    SELECT * INTO v_request
    FROM public.direct_supply_requests
    WHERE id = p_request_id
    FOR UPDATE;

    IF v_request IS NULL THEN
        RAISE EXCEPTION 'Request not found';
    END IF;

    IF v_request.status <> 'pending' THEN
        RAISE EXCEPTION 'Request already processed';
    END IF;

    IF p_action = 'deny' THEN
        UPDATE public.direct_supply_requests
        SET status = 'denied',
            approved_by = auth.uid(),
            approved_at = now(),
            notes = COALESCE(p_notes, notes)
        WHERE id = p_request_id;

        INSERT INTO public.notifications (user_id, title, message, type, data)
        VALUES (
            v_request.requested_by,
            'Direct supply denied',
            'Your direct supply request was denied.',
            'warning',
            jsonb_build_object('request_id', v_request.id, 'bar', v_request.bar)
        );
        RETURN;
    END IF;

    IF p_action <> 'approve' THEN
        RAISE EXCEPTION 'Invalid action';
    END IF;

    SELECT name INTO v_item_name
    FROM public.stock_items
    WHERE id = v_request.stock_item_id;

    SELECT id INTO v_location_id
    FROM public.locations
    WHERE name = CASE WHEN v_request.bar = 'vip_bar' THEN 'VIP Bar' ELSE 'Outside Bar' END;

    IF v_location_id IS NULL THEN
        RAISE EXCEPTION 'Destination location not found';
    END IF;

    INSERT INTO public.stock_transactions (
        stock_item_id,
        location_id,
        staff_profile_id,
        transaction_type,
        quantity,
        notes
    ) VALUES (
        v_request.stock_item_id,
        v_location_id,
        auth.uid(),
        'Direct_Supply',
        v_request.quantity,
        COALESCE(p_notes, 'Direct supply approved')
    );

    UPDATE public.direct_supply_requests
    SET status = 'approved',
        approved_by = auth.uid(),
        approved_at = now(),
        notes = COALESCE(p_notes, notes)
    WHERE id = p_request_id;

    INSERT INTO public.notifications (user_id, title, message, type, data)
    VALUES (
        v_request.requested_by,
        'Direct supply approved',
        'Your direct supply request was approved.',
        'success',
        jsonb_build_object('request_id', v_request.id, 'bar', v_request.bar)
    );
END;
$$;

-- Notify management when a direct supply request is created
CREATE OR REPLACE FUNCTION public.notify_direct_supply_request()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.notifications (user_id, title, message, type, data)
  SELECT p.id,
         'Direct supply request',
         'A new direct supply request requires approval.',
         'info',
         jsonb_build_object('request_id', NEW.id, 'bar', NEW.bar)
  FROM public.profiles p
  WHERE p.status = 'Active'
  AND ( 'owner' = ANY(p.roles) OR 'manager' = ANY(p.roles) );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_direct_supply_request ON public.direct_supply_requests;
CREATE TRIGGER trg_notify_direct_supply_request
AFTER INSERT ON public.direct_supply_requests
FOR EACH ROW EXECUTE FUNCTION public.notify_direct_supply_request();

-- ==============================================
-- 8. STOCK TRANSFERS (Main Store -> Departments)
-- ==============================================
CREATE TABLE public.stock_transfers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    stock_item_id UUID REFERENCES public.stock_items(id) NOT NULL,
    source_location_id UUID REFERENCES public.locations(id) NOT NULL,
    destination_location_id UUID REFERENCES public.locations(id) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    issued_by_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    issued_by_name TEXT,
    received_by_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    received_by_name TEXT,
    notes TEXT,
    status TEXT DEFAULT 'Confirmed' CHECK (status IN ('Pending', 'Confirmed', 'Cancelled'))
);

ALTER TABLE public.stock_transfers ENABLE ROW LEVEL SECURITY;

-- Allow active staff to view transfers
CREATE POLICY "Active staff view stock transfers" ON public.stock_transfers FOR SELECT USING (
  is_user_active(auth.uid())
);

-- Allow storekeeper/manager/owner to create transfers
CREATE POLICY "Storekeeper can create stock transfers" ON public.stock_transfers FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND (user_has_role(auth.uid(), 'storekeeper') OR user_has_role(auth.uid(), 'manager') OR user_has_role(auth.uid(), 'owner'))
);

-- Function to create transfer + write ledger entries
CREATE OR REPLACE FUNCTION public.create_stock_transfer(
    p_stock_item_id uuid,
    p_source_location_id uuid,
    p_destination_location_id uuid,
    p_quantity int,
    p_issued_by_id uuid,
    p_received_by_id uuid,
    p_notes text DEFAULT NULL
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_transfer_id uuid;
    v_is_management boolean;
    v_is_bartender boolean;
    v_source_allowed boolean;
    v_destination_allowed boolean;
BEGIN
    IF NOT is_user_active(auth.uid()) THEN
        RAISE EXCEPTION 'User not active';
    END IF;

    v_is_management := user_has_role(auth.uid(), 'storekeeper')
        OR user_has_role(auth.uid(), 'manager')
        OR user_has_role(auth.uid(), 'owner');
    v_is_bartender := user_has_role(auth.uid(), 'vip_bartender')
        OR user_has_role(auth.uid(), 'outside_bartender');

    IF NOT (v_is_management OR v_is_bartender) THEN
        RAISE EXCEPTION 'Not authorized to create stock transfer';
    END IF;

    IF v_is_bartender AND NOT v_is_management THEN
        IF p_issued_by_id <> auth.uid() THEN
            RAISE EXCEPTION 'Bartenders can only issue transfers for themselves';
        END IF;
        SELECT EXISTS(
            SELECT 1 FROM public.locations l
            WHERE l.id = p_source_location_id AND l.name IN ('VIP Bar', 'Outside Bar')
        ) INTO v_source_allowed;
        SELECT EXISTS(
            SELECT 1 FROM public.locations l
            WHERE l.id = p_destination_location_id AND l.name IN ('VIP Bar', 'Outside Bar')
        ) INTO v_destination_allowed;
        IF NOT (v_source_allowed AND v_destination_allowed) THEN
            RAISE EXCEPTION 'Bartenders can only transfer between VIP Bar and Outside Bar';
        END IF;
    END IF;

    INSERT INTO public.stock_transfers (
        stock_item_id,
        source_location_id,
        destination_location_id,
        quantity,
        issued_by_id,
        received_by_id,
        notes,
        status
    ) VALUES (
        p_stock_item_id,
        p_source_location_id,
        p_destination_location_id,
        p_quantity,
        p_issued_by_id,
        p_received_by_id,
        p_notes,
        'Confirmed'
    ) RETURNING id INTO v_transfer_id;

    -- Ledger entries (out/in)
    PERFORM public.perform_stock_transfer(
        p_stock_item_id,
        p_source_location_id,
        p_destination_location_id,
        p_quantity,
        p_issued_by_id
    );

    RETURN v_transfer_id;
END;
$$;

CREATE INDEX IF NOT EXISTS idx_stock_transfers_source ON public.stock_transfers(source_location_id);
CREATE INDEX IF NOT EXISTS idx_stock_transfers_destination ON public.stock_transfers(destination_location_id);
CREATE INDEX IF NOT EXISTS idx_stock_transfers_item ON public.stock_transfers(stock_item_id);

-- ==============================================
-- 9. DEPARTMENT TRANSFERS (Kitchen to Bar Workflow)
-- ==============================================
CREATE TABLE public.department_transfers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    source_department TEXT,
    destination_department TEXT,
    menu_item_id UUID REFERENCES public.menu_items(id),
    quantity INT,
    dispatched_by_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    dispatched_by_name TEXT,
    status TEXT DEFAULT 'Pending', -- 'Pending', 'Confirmed'
    unit_price INT8 DEFAULT 0, -- Stored in Kobo/Cents
    total_amount INT8 DEFAULT 0, -- quantity * unit_price
    payment_method TEXT DEFAULT 'cash', -- 'cash', 'card', 'transfer', 'credit'
    payment_status TEXT DEFAULT 'paid', -- 'paid', 'unpaid'
    booking_id UUID REFERENCES public.bookings(id),
    notes TEXT
);

ALTER TABLE public.department_transfers ENABLE ROW LEVEL SECURITY;

-- Policies
-- Only active staff can view transfers (resigned/terminated staff are blocked)
CREATE POLICY "Active staff view transfers" ON public.department_transfers FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
  )
);

-- Atomic Transfer Function (Critical for Inventory Integrity)
CREATE OR REPLACE FUNCTION public.perform_stock_transfer(
    p_stock_item_id uuid,
    p_source_location_id uuid,
    p_destination_location_id uuid,
    p_quantity int,
    p_staff_id uuid
)
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
    -- Out
    INSERT INTO public.stock_transactions (stock_item_id, location_id, staff_profile_id, transaction_type, quantity, notes)
    VALUES (p_stock_item_id, p_source_location_id, p_staff_id, 'Transfer_Out', -p_quantity, 'Internal Transfer');
    -- In
    INSERT INTO public.stock_transactions (stock_item_id, location_id, staff_profile_id, transaction_type, quantity, notes)
    VALUES (p_stock_item_id, p_destination_location_id, p_staff_id, 'Transfer_In', p_quantity, 'Internal Transfer');
END;
$$;

-- ==============================================
-- 9. PURCHASE ORDERS (Purchaser -> Storekeeper Workflow)
-- ==============================================
CREATE TABLE public.purchase_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    purchaser_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    purchaser_name TEXT,
    storekeeper_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    storekeeper_name TEXT,
    status TEXT DEFAULT 'Pending',
    supplier_name TEXT,
    total_cost INT8 -- Stored in Kobo/Cents
);

CREATE TABLE public.purchase_order_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    purchase_order_id UUID REFERENCES public.purchase_orders(id) ON DELETE CASCADE,
    stock_item_id UUID REFERENCES public.stock_items(id),
    quantity INT,
    unit_cost INT8 -- Stored in Kobo/Cents
);

-- ==============================================
-- 9.1 PURCHASE BUDGETS (Monthly)
-- ==============================================
CREATE TABLE public.purchase_budgets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    month_start DATE NOT NULL UNIQUE,
    amount INT8 NOT NULL, -- Stored in Kobo/Cents
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_by_name TEXT,
    updated_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    updated_by_name TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.purchase_budgets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Management can manage purchase budgets" ON public.purchase_budgets FOR ALL USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'accountant')
  )
);

CREATE POLICY "Purchaser can view purchase budgets" ON public.purchase_budgets FOR SELECT USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'purchaser')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'accountant')
  )
);

ALTER TABLE public.purchase_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_order_items ENABLE ROW LEVEL SECURITY;

-- Policies (Purchaser -> Storekeeper workflow)
CREATE POLICY "Purchaser can create purchase orders" ON public.purchase_orders FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND (
    (user_has_role(auth.uid(), 'purchaser') AND purchaser_id = auth.uid())
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
  )
);

CREATE POLICY "Purchaser/storekeeper can view purchase orders" ON public.purchase_orders FOR SELECT USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'storekeeper')
    OR (user_has_role(auth.uid(), 'purchaser') AND purchaser_id = auth.uid())
  )
);

CREATE POLICY "Storekeeper can update purchase orders" ON public.purchase_orders FOR UPDATE USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'storekeeper')
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
  )
);

CREATE POLICY "Purchaser can add purchase order items" ON public.purchase_order_items FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR (
      user_has_role(auth.uid(), 'purchaser')
      AND EXISTS (
        SELECT 1 FROM public.purchase_orders po
        WHERE po.id = purchase_order_items.purchase_order_id
        AND po.purchaser_id = auth.uid()
      )
    )
  )
);

CREATE POLICY "Purchaser/storekeeper can view purchase order items" ON public.purchase_order_items FOR SELECT USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'storekeeper')
    OR EXISTS (
      SELECT 1 FROM public.purchase_orders po
      WHERE po.id = purchase_order_items.purchase_order_id
      AND po.purchaser_id = auth.uid()
    )
  )
);

-- Function to Confirm Purchase Order (Updates Status & Adds Stock)
CREATE OR REPLACE FUNCTION public.confirm_purchase_order(order_id uuid, storekeeper_id uuid, location_id uuid DEFAULT NULL)
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_location_id uuid;
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (
      user_has_role(auth.uid(), 'storekeeper')
      OR user_has_role(auth.uid(), 'manager')
      OR user_has_role(auth.uid(), 'owner')
    )
  ) THEN
    RAISE EXCEPTION 'Only storekeeper or management can confirm purchase orders';
  END IF;

  IF location_id IS NOT NULL THEN
    v_location_id := location_id;
  ELSE
    SELECT id INTO v_location_id
    FROM public.locations
    WHERE lower(name) IN ('main store', 'main storeroom')
    ORDER BY name
    LIMIT 1;
  END IF;

  IF v_location_id IS NULL THEN
    RAISE EXCEPTION 'Main Store location not found. Please select a location.';
  END IF;

  UPDATE public.purchase_orders
  SET status = 'Confirmed', storekeeper_id = confirm_purchase_order.storekeeper_id
  WHERE id = order_id;
  
  INSERT INTO public.stock_transactions (stock_item_id, location_id, staff_profile_id, transaction_type, quantity, notes)
  SELECT poi.stock_item_id, v_location_id, storekeeper_id, 'Purchase', poi.quantity, 'PO Confirmed'
  FROM public.purchase_order_items poi WHERE poi.purchase_order_id = order_id;
END;
$$;

-- ==============================================
-- 10. EXPENSES
-- ==============================================
CREATE TABLE public.expenses (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    profile_name TEXT,
    amount INT8 NOT NULL, -- Stored in Kobo/Cents
    description TEXT,
    category TEXT,
    category_id UUID REFERENCES public.expense_categories(id),
    department TEXT,
    transaction_date DATE,
    receipt_url TEXT,
    payment_method TEXT DEFAULT 'cash', -- 'cash', 'bank_transfer', 'card'
    status TEXT DEFAULT 'Pending' CHECK (status IN ('Pending', 'Approved', 'Rejected')),
    approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    approved_by_name TEXT,
    approved_at TIMESTAMPTZ,
    rejected_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    rejected_by_name TEXT,
    rejected_at TIMESTAMPTZ,
    rejection_reason TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.expenses ENABLE ROW LEVEL SECURITY;

-- Only active admin can access finances (resigned/terminated staff are blocked)
CREATE POLICY "Active admin finance access" ON public.expenses FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
  )
);

-- ==============================================
-- 10.1. INCOME RECORDS
-- ==============================================
CREATE TABLE public.income_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    description TEXT NOT NULL,
    amount INT8 NOT NULL, -- Stored in Kobo/Cents
    source TEXT, -- e.g., 'Room Booking', 'POS Sales', 'Mini Mart'
    date DATE DEFAULT CURRENT_DATE,
    department TEXT DEFAULT 'finance',
    payment_method TEXT DEFAULT 'cash', -- 'cash', 'card', 'bank_transfer'
    staff_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    staff_name TEXT,
    booking_id UUID REFERENCES public.bookings(id), -- Optional link to booking
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_by_name TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.income_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active admin finance access income" ON public.income_records FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
  )
);

-- ==============================================
-- 10.2. PAYROLL RECORDS
-- ==============================================
CREATE TABLE public.payroll_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    staff_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    staff_name TEXT,
    amount INT8 NOT NULL, -- Stored in Kobo/Cents
    month DATE NOT NULL, -- First day of the month
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'paid', 'cancelled')),
    payment_method TEXT DEFAULT 'bank_transfer', -- 'bank_transfer', 'cash'
    notes TEXT,
    approval_status TEXT DEFAULT 'pending' CHECK (approval_status IN ('pending', 'approved', 'rejected')),
    approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    approved_by_name TEXT,
    approved_at TIMESTAMPTZ,
    rejection_reason TEXT,
    processed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    processed_by_name TEXT,
    processed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.payroll_records ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active admin finance access payroll" ON public.payroll_records FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner', 'accountant', 'hr'])
  )
);

-- Staff can view their own payroll records
CREATE POLICY "Staff view own payroll" ON public.payroll_records FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND p.id = staff_id
  )
);

-- ==============================================
-- 10.3. CASH DEPOSITS
-- ==============================================
CREATE TABLE public.cash_deposits (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    amount INT8 NOT NULL, -- Stored in Kobo/Cents
    bank_name TEXT NOT NULL,
    account_type TEXT, -- 'savings', 'current', 'business'
    bank_charges INT8 DEFAULT 0, -- Stored in Kobo/Cents
    net_amount INT8 NOT NULL, -- amount - bank_charges
    date DATE DEFAULT CURRENT_DATE,
    description TEXT,
    staff_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    staff_name TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_by_name TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.cash_deposits ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active admin finance access deposits" ON public.cash_deposits FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
  )
);

-- ==============================================
-- 10.4. DEBTS
-- ==============================================
CREATE TABLE public.debts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    debtor_name TEXT NOT NULL,
    debtor_phone TEXT, -- Phone number of debtor
    debtor_type TEXT DEFAULT 'customer', -- 'customer', 'supplier', 'staff', 'other'
    amount INT8 NOT NULL, -- Stored in Kobo/Cents
    owed_to TEXT, -- Who is owed the money
    department TEXT, -- e.g., 'reception', 'mini_mart', 'restaurant'
    reason TEXT,
    date DATE DEFAULT CURRENT_DATE,
    due_date DATE,
    status TEXT DEFAULT 'outstanding' CHECK (status IN ('outstanding', 'partially_paid', 'paid', 'written_off')),
    paid_amount INT8 DEFAULT 0, -- Stored in Kobo/Cents
    last_payment_date DATE,
    notes TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_by_name TEXT,
    sold_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL, -- Staff who made the credit sale
    sold_by_name TEXT,
    approved_by TEXT, -- Manually entered name of supervisor/staff who approved (optional)
    booking_id UUID REFERENCES public.bookings(id), -- Link to booking if debt from room booking
    sale_id UUID, -- Generic sale ID (can link to department_sales or mini_mart_sales)
    source_department TEXT, -- Originating department for traceability
    source_type TEXT, -- e.g. 'kitchen_sale', 'kitchen_dispatch'
    reference_id UUID, -- Reference to source record (sale/transfer)
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- ==============================================
-- 10.5. FINANCE AUDIT LOGS
-- ==============================================
CREATE TABLE public.finance_audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    actor_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    actor_name TEXT,
    action TEXT NOT NULL, -- 'INSERT', 'UPDATE', 'DELETE'
    table_name TEXT NOT NULL,
    record_id UUID,
    before_data JSONB,
    after_data JSONB
);

ALTER TABLE public.finance_audit_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active admin finance access audit logs" ON public.finance_audit_logs FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
  )
);

CREATE OR REPLACE FUNCTION public.log_finance_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.finance_audit_logs (
    actor_id,
    action,
    table_name,
    record_id,
    before_data,
    after_data
  )
  VALUES (
    auth.uid(),
    TG_OP,
    TG_TABLE_NAME,
    COALESCE((CASE WHEN TG_OP = 'DELETE' THEN OLD.id ELSE NEW.id END), NULL),
    (CASE WHEN TG_OP = 'UPDATE' OR TG_OP = 'DELETE' THEN to_jsonb(OLD) ELSE NULL END),
    (CASE WHEN TG_OP = 'INSERT' OR TG_OP = 'UPDATE' THEN to_jsonb(NEW) ELSE NULL END)
  );
  RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS trg_finance_audit_expenses ON public.expenses;
CREATE TRIGGER trg_finance_audit_expenses
AFTER INSERT OR UPDATE OR DELETE ON public.expenses
FOR EACH ROW EXECUTE FUNCTION public.log_finance_change();

DROP TRIGGER IF EXISTS trg_finance_audit_income ON public.income_records;
CREATE TRIGGER trg_finance_audit_income
AFTER INSERT OR UPDATE OR DELETE ON public.income_records
FOR EACH ROW EXECUTE FUNCTION public.log_finance_change();

DROP TRIGGER IF EXISTS trg_finance_audit_payroll ON public.payroll_records;
CREATE TRIGGER trg_finance_audit_payroll
AFTER INSERT OR UPDATE OR DELETE ON public.payroll_records
FOR EACH ROW EXECUTE FUNCTION public.log_finance_change();

DROP TRIGGER IF EXISTS trg_finance_audit_cash_deposits ON public.cash_deposits;
CREATE TRIGGER trg_finance_audit_cash_deposits
AFTER INSERT OR UPDATE OR DELETE ON public.cash_deposits
FOR EACH ROW EXECUTE FUNCTION public.log_finance_change();

DROP TRIGGER IF EXISTS trg_finance_audit_debts ON public.debts;
CREATE TRIGGER trg_finance_audit_debts
AFTER INSERT OR UPDATE OR DELETE ON public.debts
FOR EACH ROW EXECUTE FUNCTION public.log_finance_change();

DROP TRIGGER IF EXISTS trg_finance_audit_debt_payments ON public.debt_payments;
CREATE TRIGGER trg_finance_audit_debt_payments
AFTER INSERT OR UPDATE OR DELETE ON public.debt_payments
FOR EACH ROW EXECUTE FUNCTION public.log_finance_change();

ALTER TABLE public.debts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active admin finance access debts" ON public.debts FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
  )
);

-- Allow sales staff to create debts for their own credit sales
CREATE POLICY "Staff can insert debts" ON public.debts FOR INSERT
WITH CHECK (
  is_user_active(auth.uid())
  AND sold_by = auth.uid()
  AND (
    user_has_role(auth.uid(), 'receptionist')
    OR user_has_role(auth.uid(), 'kitchen_staff')
    OR user_has_role(auth.uid(), 'vip_bartender')
    OR user_has_role(auth.uid(), 'outside_bartender')
    -- legacy bartender role removed
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'accountant')
  )
);

-- Allow staff who created debt to update it
CREATE POLICY "Staff can update own debts" ON public.debts FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (
      debts.sold_by = auth.uid() -- Staff who created the debt
      OR (p.roles && ARRAY['manager', 'owner', 'accountant']) -- Or accountant/manager/owner
    )
  )
);

-- ==============================================
-- 10.4.1. DEBT PAYMENTS
-- ==============================================
CREATE TABLE public.debt_payments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    debt_id UUID REFERENCES public.debts(id) ON DELETE CASCADE NOT NULL,
    amount INT8 NOT NULL, -- Payment amount in Kobo/Cents
    payment_method TEXT NOT NULL CHECK (payment_method IN ('cash', 'transfer', 'card', 'other')),
    payment_date DATE DEFAULT CURRENT_DATE NOT NULL,
    collected_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL, -- Staff who collected the payment
    collected_by_name TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL, -- Staff who recorded the payment
    created_by_name TEXT,
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.debt_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Active admin finance access debt payments" ON public.debt_payments FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
  )
);

-- Allow staff who created debt to record payments
CREATE POLICY "Staff can record payments for own debts" ON public.debt_payments FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (
      EXISTS (
        SELECT 1 FROM public.debts d
        WHERE d.id = debt_payments.debt_id
        AND d.sold_by = auth.uid()
      )
      OR (p.roles && ARRAY['manager', 'owner', 'accountant'])
    )
  )
);

-- Allow accountant to record payments for any debt
CREATE POLICY "Accountant can record payments" ON public.debt_payments FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
  )
);

-- Auto-update debt status, booking paid_amount, and department sales on payment
CREATE OR REPLACE FUNCTION public.handle_debt_payment()
RETURNS TRIGGER AS $$
DECLARE
  v_debt RECORD;
  v_department TEXT;
  v_existing RECORD;
  v_breakdown JSONB;
  v_new_amount INT8;
BEGIN
  SELECT * INTO v_debt FROM public.debts WHERE id = NEW.debt_id;
  IF v_debt IS NULL THEN
    RETURN NEW;
  END IF;

  v_new_amount := COALESCE(v_debt.paid_amount, 0) + NEW.amount;

  UPDATE public.debts
  SET paid_amount = v_new_amount,
      last_payment_date = NEW.payment_date,
      status = CASE
        WHEN v_new_amount >= v_debt.amount THEN 'paid'
        ELSE 'partially_paid'
      END,
      updated_at = now()
  WHERE id = NEW.debt_id;

  IF v_debt.booking_id IS NOT NULL THEN
    UPDATE public.bookings
    SET paid_amount = COALESCE(paid_amount, 0) + NEW.amount,
        updated_at = now()
    WHERE id = v_debt.booking_id;
  END IF;

  v_department := COALESCE(v_debt.source_department, v_debt.department);
  IF v_department IS NOT NULL THEN
    SELECT * INTO v_existing
    FROM public.department_sales
    WHERE department = v_department
      AND date = NEW.payment_date;

    v_breakdown := COALESCE(v_existing.payment_method_breakdown, '{}'::jsonb);
    v_breakdown := jsonb_set(
      v_breakdown,
      ARRAY[NEW.payment_method],
      to_jsonb(COALESCE((v_breakdown->>NEW.payment_method)::int, 0) + NEW.amount),
      true
    );

    IF v_existing IS NOT NULL THEN
      UPDATE public.department_sales
      SET total_sales = COALESCE(total_sales, 0) + NEW.amount,
          transaction_count = COALESCE(transaction_count, 0) + 1,
          payment_method_breakdown = v_breakdown,
          updated_at = now()
      WHERE id = v_existing.id;
    ELSE
      INSERT INTO public.department_sales(
        department, date, total_sales, transaction_count, payment_method_breakdown, recorded_by, staff_id
      ) VALUES (
        v_department, NEW.payment_date, NEW.amount, 1, v_breakdown, NEW.created_by, NEW.collected_by
      );
    END IF;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS handle_debt_payment_trigger ON public.debt_payments;
CREATE TRIGGER handle_debt_payment_trigger
AFTER INSERT ON public.debt_payments
FOR EACH ROW EXECUTE FUNCTION public.handle_debt_payment();

-- ==============================================
-- 10.5. MINI MART ITEMS (Reception Subdepartment)
-- ==============================================
CREATE TABLE public.mini_mart_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    name TEXT NOT NULL,
    description TEXT,
    price INT8 NOT NULL, -- Stored in Kobo/Cents
    cost_price INT8, -- Stored in Kobo/Cents (for profit calculation)
    category TEXT, -- 'snacks', 'drinks', 'toiletries', 'other'
    barcode TEXT,
    stock_quantity INTEGER DEFAULT 0,
    min_stock_level INTEGER DEFAULT 5,
    image_url TEXT,
    is_available BOOLEAN DEFAULT true,
    supplier TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.mini_mart_items ENABLE ROW LEVEL SECURITY;

-- Reception staff can view mini mart items (read-only)
CREATE POLICY "Reception staff access mini mart items" ON public.mini_mart_items FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND ('receptionist' = ANY(p.roles) OR 'manager' = ANY(p.roles) OR 'owner' = ANY(p.roles))
  )
);

-- Only management can manage mini mart items
CREATE POLICY "Management can manage mini mart items" ON public.mini_mart_items FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner'])
  )
);

-- ==============================================
-- 10.6. MINI MART SALES (Reception Subdepartment)
-- ==============================================
CREATE TABLE public.mini_mart_sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    item_id UUID REFERENCES public.mini_mart_items(id) NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price INT8 NOT NULL, -- Stored in Kobo/Cents (price at time of sale)
    total_amount INT8 NOT NULL, -- quantity * unit_price
    sale_date TIMESTAMPTZ DEFAULT now(),
    payment_method TEXT DEFAULT 'cash', -- 'cash', 'card', 'mobile_money'
    customer_name TEXT, -- Optional: for walk-in customers
    booking_id UUID REFERENCES public.bookings(id), -- Optional: if linked to guest booking
    sold_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    sold_by_name TEXT,
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.mini_mart_sales ENABLE ROW LEVEL SECURITY;

-- Reception staff can view and create mini mart sales
CREATE POLICY "Reception staff access mini mart sales" ON public.mini_mart_sales FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND ('receptionist' = ANY(p.roles) OR 'manager' = ANY(p.roles) OR 'owner' = ANY(p.roles))
  )
);

-- ==============================================
-- 10.7. DEPARTMENT SALES
-- ==============================================
CREATE TABLE public.department_sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    department TEXT NOT NULL, -- 'reception', 'vip_bar', 'outside_bar', 'restaurant', 'laundry', 'mini_mart', 'storekeeping', 'purchasing', 'general'
    date DATE DEFAULT CURRENT_DATE,
    total_sales INT8 NOT NULL, -- Stored in Kobo/Cents
    total_cost INT8, -- Stored in Kobo/Cents (for profit calculation)
    transaction_count INTEGER DEFAULT 0,
    payment_method_breakdown JSONB DEFAULT '{}'::jsonb, -- {'cash': 50000, 'card': 30000}
    recorded_by UUID REFERENCES public.profiles(id),
    staff_id UUID REFERENCES public.profiles(id), -- References the staff member who made the sales. NULL indicates aggregate department sales not attributed to a specific staff member.
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.department_sales ENABLE ROW LEVEL SECURITY;

-- Management and department staff can view their department sales
CREATE POLICY "Department staff access sales" ON public.department_sales FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (
      'manager' = ANY(p.roles) OR 
      'owner' = ANY(p.roles) OR 
      'accountant' = ANY(p.roles) OR
      (department = 'restaurant' AND 'kitchen_staff' = ANY(p.roles)) OR
      (department = 'vip_bar' AND ('vip_bartender' = ANY(p.roles))) OR
      (department = 'outside_bar' AND ('outside_bartender' = ANY(p.roles))) OR
      (department = 'mini_mart' AND 'receptionist' = ANY(p.roles)) OR
      (department = 'reception' AND 'receptionist' = ANY(p.roles)) OR
      (department = 'laundry' AND 'laundry_attendant' = ANY(p.roles)) OR
      (department = 'storekeeping' AND 'storekeeper' = ANY(p.roles)) OR
      (department = 'purchasing' AND 'purchaser' = ANY(p.roles))
    )
  )
);

-- Only management can insert/update department sales
CREATE POLICY "Management can insert sales" ON public.department_sales FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
  )
);

CREATE POLICY "Management can update sales" ON public.department_sales FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
  )
);

-- Department staff can insert/update their own department sales
CREATE POLICY "Department staff can insert sales" ON public.department_sales FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'accountant')
    OR (department = 'restaurant' AND (user_has_role(auth.uid(), 'kitchen_staff') OR user_has_role(auth.uid(), 'receptionist')))
    OR (department = 'vip_bar' AND user_has_role(auth.uid(), 'vip_bartender'))
    OR (department = 'outside_bar' AND user_has_role(auth.uid(), 'outside_bartender'))
    OR (department = 'mini_mart' AND user_has_role(auth.uid(), 'receptionist'))
    OR (department = 'reception' AND user_has_role(auth.uid(), 'receptionist'))
    OR (department = 'laundry' AND user_has_role(auth.uid(), 'laundry_attendant'))
    OR (department = 'storekeeping' AND user_has_role(auth.uid(), 'storekeeper'))
    OR (department = 'purchasing' AND user_has_role(auth.uid(), 'purchaser'))
    OR (
      (user_has_role(auth.uid(), 'kitchen_staff') OR user_has_role(auth.uid(), 'receptionist'))
      AND department IN ('vip_bar', 'outside_bar', 'mini_mart', 'reception', 'restaurant')
    )
  )
);

CREATE POLICY "Department staff can update sales" ON public.department_sales FOR UPDATE USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'accountant')
    OR (department = 'restaurant' AND (user_has_role(auth.uid(), 'kitchen_staff') OR user_has_role(auth.uid(), 'receptionist')))
    OR (department = 'vip_bar' AND user_has_role(auth.uid(), 'vip_bartender'))
    OR (department = 'outside_bar' AND user_has_role(auth.uid(), 'outside_bartender'))
    OR (department = 'mini_mart' AND user_has_role(auth.uid(), 'receptionist'))
    OR (department = 'reception' AND user_has_role(auth.uid(), 'receptionist'))
    OR (department = 'laundry' AND user_has_role(auth.uid(), 'laundry_attendant'))
    OR (department = 'storekeeping' AND user_has_role(auth.uid(), 'storekeeper'))
    OR (department = 'purchasing' AND user_has_role(auth.uid(), 'purchaser'))
    OR (
      (user_has_role(auth.uid(), 'kitchen_staff') OR user_has_role(auth.uid(), 'receptionist'))
      AND department IN ('vip_bar', 'outside_bar', 'mini_mart', 'reception', 'restaurant')
    )
  )
);

-- ==============================================
-- 10.7b. KITCHEN SALES (Itemized History)
-- ==============================================
CREATE TABLE public.kitchen_sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    menu_item_id UUID REFERENCES public.menu_items(id),
    item_name TEXT, -- For custom items
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price INT8 NOT NULL, -- Stored in Kobo/Cents
    total_amount INT8 NOT NULL, -- quantity * unit_price
    payment_method TEXT DEFAULT 'cash', -- 'cash', 'card', 'transfer', 'credit'
    booking_id UUID REFERENCES public.bookings(id),
    sold_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    sold_by_name TEXT,
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.kitchen_sales ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Kitchen staff access kitchen sales" ON public.kitchen_sales FOR SELECT
USING (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'kitchen_staff')
    OR user_has_role(auth.uid(), 'receptionist')
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
    OR user_has_role(auth.uid(), 'accountant')
  )
);

CREATE POLICY "Kitchen staff can insert kitchen sales" ON public.kitchen_sales FOR INSERT
WITH CHECK (
  is_user_active(auth.uid())
  AND (
    user_has_role(auth.uid(), 'kitchen_staff')
    OR user_has_role(auth.uid(), 'receptionist')
    OR user_has_role(auth.uid(), 'manager')
    OR user_has_role(auth.uid(), 'owner')
  )
  AND sold_by = auth.uid()
);

CREATE POLICY "Management can update kitchen sales" ON public.kitchen_sales FOR UPDATE
USING (
  is_user_active(auth.uid())
  AND (user_has_role(auth.uid(), 'manager') OR user_has_role(auth.uid(), 'owner'))
);

-- ==============================================
-- 10.8. BARTENDER SHIFTS
-- ==============================================
CREATE TABLE public.bartender_shifts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    bartender_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    bartender_name TEXT,
    bar TEXT NOT NULL CHECK (bar IN ('vip_bar', 'outside_bar')),
    start_time TIMESTAMPTZ NOT NULL,
    end_time TIMESTAMPTZ,
    date DATE DEFAULT CURRENT_DATE,
    opening_cash INT8 DEFAULT 0, -- Stored in Kobo/Cents
    closing_cash INT8, -- Stored in Kobo/Cents
    total_sales INT8, -- Stored in Kobo/Cents
    opening_stock JSONB DEFAULT '[]'::jsonb,
    transfers JSONB DEFAULT '[]'::jsonb,
    closing_stock JSONB DEFAULT '[]'::jsonb,
    notes TEXT,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'closed', 'cancelled')),
    closed_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    closed_by_name TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.bartender_shifts ENABLE ROW LEVEL SECURITY;

-- Bartenders can view their own shifts, management can view all
CREATE POLICY "Bartenders view own shifts" ON public.bartender_shifts FOR SELECT 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (
      bartender_id = auth.uid() OR
      'vip_bartender' = ANY(p.roles) OR
      'outside_bartender' = ANY(p.roles) OR
      'manager' = ANY(p.roles) OR
      'owner' = ANY(p.roles)
    )
  )
);

CREATE POLICY "Bartenders can insert shifts" ON public.bartender_shifts FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (
      (bartender_id = auth.uid() AND ('vip_bartender' = ANY(p.roles) OR 'outside_bartender' = ANY(p.roles))) OR
      'manager' = ANY(p.roles) OR
      'owner' = ANY(p.roles)
    )
  )
);

CREATE POLICY "Bartenders can update shifts" ON public.bartender_shifts FOR UPDATE USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (
      (bartender_id = auth.uid() AND ('vip_bartender' = ANY(p.roles) OR 'outside_bartender' = ANY(p.roles))) OR
      'manager' = ANY(p.roles) OR
      'owner' = ANY(p.roles)
    )
  )
);

-- ==============================================
-- 10.9. STAFF ROLE ASSIGNMENTS (For Delegation/Temporary Roles)
-- ==============================================
CREATE TABLE public.staff_role_assignments (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    staff_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    staff_name TEXT,
    assigned_role TEXT NOT NULL, -- Role being assigned
    assigned_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    assigned_by_name TEXT,
    start_date DATE,
    end_date DATE, -- NULL for permanent assignments
    is_active BOOLEAN DEFAULT true,
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.staff_role_assignments ENABLE ROW LEVEL SECURITY;

-- Only HR and management can view/manage role assignments
CREATE POLICY "HR and management access role assignments" ON public.staff_role_assignments FOR ALL 
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
    AND (p.roles && ARRAY['hr', 'manager', 'owner'])
  )
);

-- ==============================================
-- 11. MAINTENANCE
-- ==============================================
CREATE TABLE public.assets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT NOT NULL,
    location TEXT,
    category TEXT,
    purchase_price INT8, -- Stored in Kobo/Cents
    current_value INT8, -- Stored in Kobo/Cents
    status TEXT DEFAULT 'Operational',
    purchase_date DATE,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE public.maintenance_work_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    asset_id UUID REFERENCES public.assets(id),
    reported_by_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    reported_by_name TEXT,
    issue_description TEXT,
    location TEXT, -- Specific location text
    priority TEXT DEFAULT 'Medium' CHECK (priority IN ('Low', 'Medium', 'High', 'Urgent')),
    status TEXT DEFAULT 'Open' CHECK (status IN ('Open', 'In Progress', 'Completed', 'Cancelled')),
    assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    assigned_to_name TEXT,
    estimated_cost INT8, -- Stored in Kobo/Cents
    actual_cost INT8, -- Stored in Kobo/Cents
    due_date DATE,
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- General Work Orders (separate from maintenance)
CREATE TABLE public.work_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT NOT NULL,
    description TEXT,
    priority TEXT DEFAULT 'Medium' CHECK (priority IN ('Low', 'Medium', 'High', 'Urgent')),
    status TEXT DEFAULT 'Open' CHECK (status IN ('Open', 'In Progress', 'Completed', 'Cancelled')),
    assigned_to UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    assigned_to_name TEXT,
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_by_name TEXT,
    room_id UUID REFERENCES public.rooms(id),
    estimated_cost INT8, -- Stored in Kobo/Cents
    actual_cost INT8, -- Stored in Kobo/Cents
    due_date DATE,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.assets ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.maintenance_work_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.work_orders ENABLE ROW LEVEL SECURITY;

-- Basic policies (Only active staff can access)
CREATE POLICY "Active staff access assets" ON public.assets FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
  )
);
CREATE POLICY "Active staff access maintenance" ON public.maintenance_work_orders FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
  )
);
CREATE POLICY "Active staff access work orders" ON public.work_orders FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
  )
);

-- ==============================================
-- 12. HR (ATTENDANCE)
-- ==============================================
CREATE TABLE public.attendance_records (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    profile_name TEXT,
    clock_in_time TIMESTAMPTZ DEFAULT now(),
    clock_out_time TIMESTAMPTZ,
    date DATE DEFAULT CURRENT_DATE,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.attendance_records ENABLE ROW LEVEL SECURITY;

-- Only active staff can view attendance records (resigned/terminated staff are blocked)
CREATE POLICY "Active staff can view attendance records" ON public.attendance_records FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() 
    AND p.status = 'Active'
    AND ('hr' = ANY(p.roles) OR 'manager' = ANY(p.roles))
  )
);

CREATE POLICY "Active staff can insert attendance records" ON public.attendance_records FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND (
    profile_id = auth.uid() OR profile_id IS NULL
  )
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() 
    AND p.status = 'Active'
    AND p.roles IS NOT NULL
    AND array_length(p.roles, 1) > 0
  )
);

CREATE POLICY "Active staff can update own attendance records" ON public.attendance_records FOR UPDATE USING (
  is_user_active(auth.uid())
  AND (
    profile_id = auth.uid()
    OR EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() 
      AND p.status = 'Active'
      AND ('hr' = ANY(p.roles) OR 'manager' = ANY(p.roles) OR 'owner' = ANY(p.roles))
    )
  )
);

-- ==============================================
-- 13. INTERNAL COMMUNICATIONS
-- ==============================================
CREATE TABLE public.posts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    author_profile_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    author_name TEXT,
    title TEXT,
    content TEXT,
    department TEXT,
    is_announcement BOOLEAN DEFAULT false,
    target_user_ids UUID[] DEFAULT NULL,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.posts ENABLE ROW LEVEL SECURITY;

-- Only active staff can read posts (resigned/terminated staff are blocked)
CREATE POLICY "Active staff read posts" ON public.posts FOR SELECT USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() 
    AND p.status = 'Active'
  )
  AND (
    author_profile_id = auth.uid()
    OR target_user_ids IS NULL
    OR array_length(target_user_ids, 1) = 0
    OR auth.uid() = ANY(target_user_ids)
  )
);
CREATE POLICY "Active staff can insert posts" ON public.posts FOR INSERT WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() 
    AND p.status = 'Active'
    AND array_length(p.roles, 1) > 0
  )
);

-- ==============================================
-- 13b. KITCHEN ORDERS (Food Orders from Guests)
-- ==============================================
CREATE TABLE IF NOT EXISTS public.kitchen_orders (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    booking_id UUID REFERENCES public.bookings(id),
    room_number TEXT,
    guest_name TEXT,
    items JSONB, -- Array of {menu_item_id, quantity, notes}
    status TEXT DEFAULT 'Pending' CHECK (status IN ('Pending', 'Preparing', 'Ready', 'Delivered', 'Cancelled')),
    priority TEXT DEFAULT 'Normal' CHECK (priority IN ('Low', 'Normal', 'High', 'Urgent')),
    estimated_time INT, -- Minutes
    completed_at TIMESTAMPTZ,
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.kitchen_orders ENABLE ROW LEVEL SECURITY;
-- Only active staff can access kitchen orders (resigned/terminated staff are blocked)
CREATE POLICY "Active staff access kitchen orders" ON public.kitchen_orders FOR ALL USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
  )
);

-- ==============================================
-- 14. NOTIFICATIONS
-- ==============================================
CREATE TABLE public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    user_name TEXT,
    title TEXT NOT NULL,
    message TEXT,
    type TEXT DEFAULT 'info' CHECK (type IN ('info', 'warning', 'error', 'success')),
    is_read BOOLEAN DEFAULT false,
    data JSONB DEFAULT '{}',
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Notify all staff when an announcement is posted
CREATE OR REPLACE FUNCTION public.notify_on_announcement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.is_announcement IS TRUE THEN
    IF NEW.target_user_ids IS NULL OR array_length(NEW.target_user_ids, 1) = 0 THEN
      INSERT INTO public.notifications (user_id, title, message, type, data)
      SELECT p.id,
             NEW.title,
             NEW.content,
             'info',
             jsonb_build_object('post_id', NEW.id)
      FROM public.profiles p
      WHERE p.status = 'Active';
    ELSE
      INSERT INTO public.notifications (user_id, title, message, type, data)
      SELECT p.id,
             NEW.title,
             NEW.content,
             'info',
             jsonb_build_object('post_id', NEW.id)
      FROM public.profiles p
      WHERE p.status = 'Active'
      AND p.id = ANY(NEW.target_user_ids);
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_announcement ON public.posts;
CREATE TRIGGER trg_notify_on_announcement
AFTER INSERT ON public.posts
FOR EACH ROW EXECUTE FUNCTION public.notify_on_announcement();

ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Only active users can view notifications (resigned/terminated staff are blocked)
CREATE POLICY "Active users can view own notifications" ON public.notifications FOR SELECT USING (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
  )
);
CREATE POLICY "Active users can update own notifications" ON public.notifications FOR UPDATE USING (
  auth.uid() = user_id
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
  )
);

-- ==============================================
-- 14.1. MANAGEMENT NOTIFICATIONS (Quiet Alerts)
-- ==============================================
CREATE OR REPLACE FUNCTION public.notify_management(
  p_title text,
  p_message text,
  p_type text DEFAULT 'info',
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.notifications (user_id, title, message, type, data)
  SELECT p.id, p_title, p_message, p_type, p_data
  FROM public.profiles p
  WHERE p.status = 'Active'
  AND ( 'owner' = ANY(p.roles) OR 'manager' = ANY(p.roles) );
END;
$$;

CREATE OR REPLACE FUNCTION public.send_management_daily_digest()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_start timestamptz := date_trunc('day', now()) - interval '1 day';
  v_end timestamptz := date_trunc('day', now());
  v_booking_count int := 0;
  v_payment_updates int := 0;
  v_credit_sales int := 0;
  v_debt_updates int := 0;
  v_price_updates int := 0;
  v_supply_requests int := 0;
  v_supply_decisions int := 0;
  v_message text;
  v_digest_date text := to_char(v_start::date, 'YYYY-MM-DD');
BEGIN
  IF EXISTS (
    SELECT 1 FROM public.notifications
    WHERE title = 'Daily summary'
    AND (data->>'digest_date') = v_digest_date
  ) THEN
    RETURN;
  END IF;

  SELECT COUNT(DISTINCT (data->>'booking_id')) INTO v_booking_count
  FROM public.notifications
  WHERE title = 'New booking created'
  AND created_at >= v_start AND created_at < v_end;

  SELECT COUNT(DISTINCT (data->>'booking_id')) INTO v_payment_updates
  FROM public.notifications
  WHERE title = 'Booking payment updated'
  AND created_at >= v_start AND created_at < v_end;

  SELECT COUNT(DISTINCT (data->>'debt_id')) INTO v_credit_sales
  FROM public.notifications
  WHERE title = 'Credit sale recorded'
  AND created_at >= v_start AND created_at < v_end;

  SELECT COUNT(DISTINCT (data->>'debt_id')) INTO v_debt_updates
  FROM public.notifications
  WHERE title = 'Debt updated'
  AND created_at >= v_start AND created_at < v_end;

  SELECT COUNT(DISTINCT (COALESCE(data->>'inventory_item_id', data->>'room_type_id'))) INTO v_price_updates
  FROM public.notifications
  WHERE (title = 'Price updated' OR title = 'Room price updated')
  AND created_at >= v_start AND created_at < v_end;

  SELECT COUNT(DISTINCT (data->>'request_id')) INTO v_supply_requests
  FROM public.notifications
  WHERE title = 'Direct supply request'
  AND created_at >= v_start AND created_at < v_end;

  SELECT COUNT(DISTINCT (data->>'request_id')) INTO v_supply_decisions
  FROM public.notifications
  WHERE (title = 'Direct supply approved' OR title = 'Direct supply denied')
  AND created_at >= v_start AND created_at < v_end;

  v_message := 'Summary for ' || v_digest_date || ': '
    || v_booking_count || ' new bookings, '
    || v_payment_updates || ' payment updates, '
    || v_credit_sales || ' credit sales, '
    || v_debt_updates || ' debt updates, '
    || v_price_updates || ' price changes, '
    || v_supply_requests || ' supply requests, '
    || v_supply_decisions || ' supply decisions.';

  PERFORM public.notify_management(
    'Daily summary',
    v_message,
    'info',
    jsonb_build_object('digest_date', v_digest_date)
  );
END;
$$;

-- Attempt to schedule daily digest at 7am if pg_cron is available
DO $$
BEGIN
  PERFORM 1 FROM pg_extension WHERE extname = 'pg_cron';
  IF NOT FOUND THEN
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_cron;
    EXCEPTION
      WHEN OTHERS THEN
        RETURN;
    END;
  END IF;
  PERFORM cron.schedule(
    'daily_management_digest',
    '0 7 * * *',
    'SELECT public.send_management_daily_digest()'
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Schedule guest lookup cleanup (weekly)
DO $$
BEGIN
  PERFORM cron.schedule(
    'guest_lookup_cleanup',
    '0 3 * * 0',
    'SELECT public.cleanup_guest_lookup_attempts()'
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

CREATE OR REPLACE FUNCTION public.notify_on_booking_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_guest_name text;
BEGIN
  v_guest_name := COALESCE(NEW.guest_name, 'Guest');
  PERFORM public.notify_management(
    'New booking created',
    'Booking created for ' || v_guest_name || '.',
    'info',
    jsonb_build_object('booking_id', NEW.id)
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_booking_created ON public.bookings;
CREATE TRIGGER trg_notify_on_booking_created
AFTER INSERT ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.notify_on_booking_created();

CREATE OR REPLACE FUNCTION public.notify_on_booking_payment_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_guest_name text;
BEGIN
  IF NEW.paid_amount IS DISTINCT FROM OLD.paid_amount
     OR NEW.status IS DISTINCT FROM OLD.status THEN
    v_guest_name := COALESCE(NEW.guest_name, 'Guest');
    PERFORM public.notify_management(
      'Booking payment updated',
      'Payment/status updated for booking of ' || v_guest_name || '.',
      'info',
      jsonb_build_object(
        'booking_id', NEW.id,
        'old_paid_amount', OLD.paid_amount,
        'new_paid_amount', NEW.paid_amount,
        'old_status', OLD.status,
        'new_status', NEW.status
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_booking_payment_change ON public.bookings;
CREATE TRIGGER trg_notify_on_booking_payment_change
AFTER UPDATE ON public.bookings
FOR EACH ROW EXECUTE FUNCTION public.notify_on_booking_payment_change();

CREATE OR REPLACE FUNCTION public.notify_roles(
  p_roles text[],
  p_title text,
  p_message text,
  p_type text DEFAULT 'info',
  p_data jsonb DEFAULT '{}'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.notifications (user_id, title, message, type, data)
  SELECT p.id, p_title, p_message, p_type, p_data
  FROM public.profiles p
  WHERE p.status = 'Active'
  AND p.roles && p_roles;
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_on_inventory_price_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_actor_name text;
  v_roles text[];
  v_title text;
  v_message text;
BEGIN
  IF COALESCE(NEW.vip_bar_price, 0) = COALESCE(OLD.vip_bar_price, 0)
     AND COALESCE(NEW.outside_bar_price, 0) = COALESCE(OLD.outside_bar_price, 0)
     AND COALESCE(NEW.unit_price, 0) = COALESCE(OLD.unit_price, 0) THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(p.full_name, 'Staff') INTO v_actor_name
  FROM public.profiles p
  WHERE p.id = auth.uid();

  v_title := 'Price updated';
  v_message := 'Price for "' || COALESCE(NEW.name, 'Item') || '" was updated by ' || v_actor_name || '.';

  PERFORM public.notify_management(
    v_title,
    v_message,
    'info',
    jsonb_build_object('inventory_item_id', NEW.id)
  );

  IF NEW.department = 'vip_bar' THEN
    v_roles := ARRAY['vip_bartender', 'accountant', 'supervisor'];
  ELSIF NEW.department = 'outside_bar' THEN
    v_roles := ARRAY['outside_bartender', 'accountant', 'supervisor'];
  ELSE
    v_roles := ARRAY['vip_bartender', 'outside_bartender', 'accountant', 'supervisor'];
  END IF;

  PERFORM public.notify_roles(
    v_roles,
    v_title,
    v_message,
    'info',
    jsonb_build_object('inventory_item_id', NEW.id)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_inventory_price_change ON public.inventory_items;
CREATE TRIGGER trg_notify_on_inventory_price_change
AFTER UPDATE ON public.inventory_items
FOR EACH ROW EXECUTE FUNCTION public.notify_on_inventory_price_change();

CREATE OR REPLACE FUNCTION public.notify_on_room_type_price_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_actor_name text;
  v_title text;
  v_message text;
BEGIN
  IF COALESCE(NEW.price, 0) = COALESCE(OLD.price, 0) THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(p.full_name, 'Staff') INTO v_actor_name
  FROM public.profiles p
  WHERE p.id = auth.uid();

  v_title := 'Room price updated';
  v_message := 'Room "' || COALESCE(NEW.type, 'Room') || '" price was updated by ' || v_actor_name || '.';

  PERFORM public.notify_management(
    v_title,
    v_message,
    'info',
    jsonb_build_object('room_type_id', NEW.id)
  );

  PERFORM public.notify_roles(
    ARRAY['receptionist', 'accountant', 'supervisor'],
    v_title,
    v_message,
    'info',
    jsonb_build_object('room_type_id', NEW.id)
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_room_type_price_change ON public.room_types;
CREATE TRIGGER trg_notify_on_room_type_price_change
AFTER UPDATE ON public.room_types
FOR EACH ROW EXECUTE FUNCTION public.notify_on_room_type_price_change();

CREATE OR REPLACE FUNCTION public.notify_on_debt_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.status IN ('outstanding', 'partially_paid') AND NEW.sold_by IS NOT NULL THEN
    PERFORM public.notify_management(
      'Credit sale recorded',
      'Credit sale for ' || COALESCE(NEW.debtor_name, 'Customer') || ' (' || NEW.amount || ' kobo).',
      'warning',
      jsonb_build_object('debt_id', NEW.id, 'department', NEW.department)
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_debt_created ON public.debts;
CREATE TRIGGER trg_notify_on_debt_created
AFTER INSERT ON public.debts
FOR EACH ROW EXECUTE FUNCTION public.notify_on_debt_created();

CREATE OR REPLACE FUNCTION public.notify_on_debt_updated()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_actor_name text;
BEGIN
  SELECT COALESCE(p.full_name, 'Staff') INTO v_actor_name
  FROM public.profiles p
  WHERE p.id = auth.uid();

  IF NEW.amount IS DISTINCT FROM OLD.amount
     OR NEW.status IS DISTINCT FROM OLD.status
     OR NEW.paid_amount IS DISTINCT FROM OLD.paid_amount
     OR NEW.notes IS DISTINCT FROM OLD.notes THEN
    PERFORM public.notify_management(
      'Debt updated',
      'Debt for ' || COALESCE(NEW.debtor_name, 'Customer') || ' was updated by ' || v_actor_name || '.',
      'warning',
      jsonb_build_object(
        'debt_id', NEW.id,
        'old_amount', OLD.amount,
        'new_amount', NEW.amount,
        'old_status', OLD.status,
        'new_status', NEW.status,
        'old_paid_amount', OLD.paid_amount,
        'new_paid_amount', NEW.paid_amount
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_debt_updated ON public.debts;
CREATE TRIGGER trg_notify_on_debt_updated
AFTER UPDATE ON public.debts
FOR EACH ROW EXECUTE FUNCTION public.notify_on_debt_updated();

-- ==============================================
-- 15. SECURITY DELEGATION
-- ==============================================
CREATE TABLE public.access_delegations (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE,
    permission TEXT NOT NULL, -- e.g. 'view_smartlock_logs'
    granted_by_id UUID REFERENCES public.profiles(id),
    UNIQUE(user_id, permission)
);

-- Smart Lock Logs
CREATE TABLE public.smartlock_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    room_id UUID REFERENCES public.rooms(id),
    event_type TEXT,
    user_identifier TEXT,
    room_status_at_event TEXT -- 'Occupied' or 'Vacant' (Audit Trail)
);

ALTER TABLE public.smartlock_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.access_delegations ENABLE ROW LEVEL SECURITY;

-- Delegation Helper Function
CREATE OR REPLACE FUNCTION public.has_delegated_permission(permission_key TEXT)
RETURNS BOOLEAN LANGUAGE sql SECURITY DEFINER AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.profiles WHERE id = auth.uid() AND 'owner' = ANY(roles)
        UNION ALL
        SELECT 1 FROM public.access_delegations WHERE user_id = auth.uid() AND permission = permission_key
    );
$$;

-- Secure Policy for Logs (Only active authorized staff)
CREATE POLICY "Active authorized view logs" ON public.smartlock_logs FOR SELECT 
USING (
  has_delegated_permission('view_smartlock_logs')
  AND EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid()
    AND p.status = 'Active'
  )
);

-- ==============================================
-- 16. CMS MEDIA TABLES
-- ==============================================
CREATE TABLE public.site_media (
    content_key TEXT PRIMARY KEY, 
    title TEXT, 
    media_url TEXT, 
    description TEXT
);

CREATE TABLE public.gallery_media (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    title TEXT,
    media_url TEXT,
    is_video BOOLEAN DEFAULT false,
    sort_order INT DEFAULT 0
);

ALTER TABLE public.site_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.gallery_media ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Public read" ON public.site_media FOR SELECT USING (true);
CREATE POLICY "Public read" ON public.gallery_media FOR SELECT USING (true);
CREATE POLICY "Admin write" ON public.site_media FOR ALL USING (auth.uid() IN (SELECT id FROM profiles WHERE roles && ARRAY['owner', 'it_admin']));

-- ==============================================
-- 17. HELPER FUNCTIONS (FIXED FOR DISCONNECTIONS)
-- ==============================================

-- FIXED: Function to check available rooms (without parameters - simpler version)
-- Fixed to use room_types.price instead of menu_items.price
CREATE OR REPLACE FUNCTION public.get_available_room_types()
RETURNS TABLE (
    type TEXT,
    price INT8,
    image_url TEXT,
    available_count INT
) 
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
    RETURN QUERY
    WITH total_rooms_by_type AS (
        SELECT rt.type, COUNT(*) as total_count
        FROM public.rooms r
        JOIN public.room_types rt ON r.type_id = rt.id
        WHERE r.status = 'Vacant' OR r.status IS NULL
        GROUP BY rt.type
    ),
    total_booked_by_type AS (
        SELECT b.requested_room_type as type, COUNT(*) as total_booked
        FROM public.bookings b
        WHERE b.status IN ('confirmed', 'checked_in')
        AND b.check_in_date <= CURRENT_DATE
        AND b.check_out_date > CURRENT_DATE
        GROUP BY b.requested_room_type
    )
    SELECT
        COALESCE(tr.type, tb.type) as type,
        -- FIX: Use room_types.price instead of menu_items.price
        (SELECT rt.price 
         FROM public.room_types rt 
         WHERE rt.type = COALESCE(tr.type, tb.type) 
         LIMIT 1) as price,
        (SELECT sm.media_url 
         FROM public.site_media sm 
         WHERE sm.content_key LIKE 'room_' || lower(COALESCE(tr.type, tb.type)) || '_1' 
         LIMIT 1) as image_url,
        COALESCE(tr.total_count, 0) - COALESCE(tb.total_booked, 0) as available_count
    FROM total_rooms_by_type tr
    FULL OUTER JOIN total_booked_by_type tb ON tr.type = tb.type
    WHERE COALESCE(tr.total_count, 0) - COALESCE(tb.total_booked, 0) > 0;
END;
$$;

-- FIXED: Function to check available rooms (with date parameters)
-- Fixed to use room_types.price instead of menu_items.price
CREATE OR REPLACE FUNCTION public.get_available_room_types(start_date text, end_date text)
RETURNS TABLE (type text, price int8, image_url text, available_count bigint)
LANGUAGE sql
SECURITY DEFINER
AS $$
    WITH booked_rooms_by_type AS (
        -- Count rooms that are directly assigned to bookings
        SELECT r.type, COUNT(DISTINCT r.id) as booked_count
        FROM public.rooms r
        INNER JOIN public.bookings b ON r.id = b.room_id
        WHERE (b.check_in_date, b.check_out_date) OVERLAPS (start_date::timestamptz, end_date::timestamptz)
        AND b.status IN ('Pending Check-in', 'Checked-in', 'confirmed', 'checked_in')
        GROUP BY r.type
        
        UNION ALL
        
        -- Count bookings by requested room type (bookings without room_id)
        SELECT b.requested_room_type as type, COUNT(*) as booked_count
        FROM public.bookings b
        WHERE b.room_id IS NULL
        AND b.requested_room_type IS NOT NULL
        AND (b.check_in_date, b.check_out_date) OVERLAPS (start_date::timestamptz, end_date::timestamptz)
        AND b.status IN ('Pending Check-in', 'Checked-in', 'confirmed', 'checked_in')
        GROUP BY b.requested_room_type
    ),
    total_booked_by_type AS (
        SELECT type, SUM(booked_count) as total_booked
        FROM booked_rooms_by_type
        GROUP BY type
    ),
    total_rooms_by_type AS (
        SELECT type, COUNT(*) as total_count
        FROM public.rooms
        WHERE status = 'Vacant'
        GROUP BY type
    )
    SELECT
        COALESCE(tr.type, tb.type) as type,
        -- FIX: Use room_types.price instead of menu_items.price
        (SELECT rt.price 
         FROM public.room_types rt 
         WHERE rt.type = COALESCE(tr.type, tb.type) 
         LIMIT 1) as price,
        (SELECT sm.media_url 
         FROM public.site_media sm 
         WHERE sm.content_key LIKE 'room_' || lower(COALESCE(tr.type, tb.type)) || '_1' 
         LIMIT 1) as image_url,
        COALESCE(tr.total_count, 0) - COALESCE(tb.total_booked, 0) as available_count
    FROM total_rooms_by_type tr
    FULL OUTER JOIN total_booked_by_type tb ON tr.type = tb.type
    WHERE COALESCE(tr.total_count, 0) - COALESCE(tb.total_booked, 0) > 0;
$$;

-- Add comments to document both function versions
COMMENT ON FUNCTION public.get_available_room_types() IS 
'Returns available room types with their prices from room_types table, available count, and image URLs. Fixed to use room_types.price instead of menu_items.price.';

COMMENT ON FUNCTION public.get_available_room_types(text, text) IS 
'Returns available room types with their prices from room_types table for a date range. Fixed to use room_types.price instead of menu_items.price.';

-- NEW: Function to assign room to booking (For receptionist use)
CREATE OR REPLACE FUNCTION public.assign_room_to_booking(booking_id UUID, room_id UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
AS $$
DECLARE
    booking_room_type TEXT;
    room_type TEXT;
BEGIN
    -- Get requested room type from booking
    SELECT requested_room_type INTO booking_room_type
    FROM public.bookings
    WHERE id = booking_id;
    
    -- Get room type
    SELECT type INTO room_type
    FROM public.rooms
    WHERE id = room_id;
    
    -- Verify room type matches (if booking has requested_room_type)
    IF booking_room_type IS NOT NULL AND room_type != booking_room_type THEN
        RAISE EXCEPTION 'Room type mismatch. Booking requested % but room is %', booking_room_type, room_type;
    END IF;
    
    -- Verify room is available
    IF NOT EXISTS (
        SELECT 1 FROM public.rooms 
        WHERE id = room_id 
        AND status = 'Vacant'
    ) THEN
        RAISE EXCEPTION 'Room is not available';
    END IF;
    
    -- Verify booking is in correct status
    IF NOT EXISTS (
        SELECT 1 FROM public.bookings
        WHERE id = booking_id
        AND status = 'Pending Check-in'
        AND (room_id IS NULL OR room_id = assign_room_to_booking.room_id)
    ) THEN
        RAISE EXCEPTION 'Booking is not in valid state for room assignment';
    END IF;
    
    -- Assign room
    UPDATE public.bookings
    SET room_id = assign_room_to_booking.room_id
    WHERE id = booking_id;
    
    RETURN TRUE;
END;
$$;

-- NEW: Function to atomically check room availability and create booking
-- This prevents race conditions where multiple guests book the same room type simultaneously
CREATE OR REPLACE FUNCTION public.create_booking_with_availability_check(
    p_guest_profile_id UUID,
    p_requested_room_type TEXT,
    p_check_in_date DATE,
    p_check_out_date DATE,
    p_total_amount INT8,
    p_guest_name TEXT,
    p_guest_email TEXT,
    p_paid_amount INT8 DEFAULT 0,
    p_payment_method TEXT DEFAULT 'cash',
    p_payment_reference TEXT DEFAULT NULL,
    p_payment_provider TEXT DEFAULT 'paystack',
    p_guest_phone TEXT DEFAULT NULL,
    p_terms_accepted BOOLEAN DEFAULT false,
    p_terms_version TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_booking_id UUID;
    v_total_rooms INTEGER;
    v_assigned_rooms INTEGER;
    v_bookings_by_type INTEGER;
    v_available_count INTEGER;
BEGIN
    -- Calculate available rooms of requested type
    -- Get total rooms of this type
    SELECT COUNT(*) INTO v_total_rooms
    FROM public.rooms
    WHERE type = p_requested_room_type
    AND status = 'Vacant';
    
    IF v_total_rooms = 0 THEN
        RAISE EXCEPTION 'No rooms of type % are available', p_requested_room_type;
    END IF;
    
    -- Count rooms directly assigned to bookings during the date range
    SELECT COUNT(DISTINCT room_id) INTO v_assigned_rooms
    FROM public.bookings
    WHERE room_id IS NOT NULL
    AND status IN ('Pending Check-in', 'Checked-in', 'confirmed', 'checked_in')
    AND check_in_date < p_check_out_date
    AND check_out_date > p_check_in_date;
    
    -- Count bookings by requested room type (without room_id) during the date range
    SELECT COUNT(*) INTO v_bookings_by_type
    FROM public.bookings
    WHERE room_id IS NULL
    AND requested_room_type = p_requested_room_type
    AND status IN ('Pending Check-in', 'Checked-in', 'confirmed', 'checked_in')
    AND check_in_date < p_check_out_date
    AND check_out_date > p_check_in_date;
    
    -- Calculate available count
    v_available_count := v_total_rooms - v_assigned_rooms - v_bookings_by_type;
    
    IF v_available_count <= 0 THEN
        RAISE EXCEPTION 'No rooms of type % are available for the selected dates', p_requested_room_type;
    END IF;
    
    -- Create booking (room_id will be assigned later by receptionist)
    INSERT INTO public.bookings (
        guest_profile_id,
        requested_room_type,
        check_in_date,
        check_out_date,
        total_amount,
        paid_amount,
        payment_method,
        payment_reference,
        payment_provider,
        guest_name,
        guest_email,
        guest_phone,
        status,
        terms_accepted,
        terms_version
    ) VALUES (
        p_guest_profile_id,
        p_requested_room_type,
        p_check_in_date,
        p_check_out_date,
        p_total_amount,
        p_paid_amount,
        p_payment_method,
        p_payment_reference,
        p_payment_provider,
        p_guest_name,
        p_guest_email,
        p_guest_phone,
        'Pending Check-in',
        p_terms_accepted,
        p_terms_version
    ) RETURNING id INTO v_booking_id;
    
    RETURN v_booking_id;
END;
$$;
COMMENT ON FUNCTION public.create_booking_with_availability_check IS 
'Atomically checks room availability and creates a booking. Prevents race conditions by performing availability check and booking creation in a single transaction.';

-- Guest booking lookup by payment reference + email (no login required)
CREATE OR REPLACE FUNCTION public.get_guest_booking_status(
    p_payment_reference TEXT,
    p_guest_email TEXT
)
RETURNS TABLE (
    booking_id UUID,
    status TEXT,
    requested_room_type TEXT,
    check_in_date TIMESTAMPTZ,
    check_out_date TIMESTAMPTZ,
    room_id UUID,
    room_number TEXT,
    paid_amount INT8,
    total_amount INT8,
    guest_name TEXT,
    guest_email TEXT,
    payment_reference TEXT,
    payment_method TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_recent_attempts INT;
BEGIN
    SELECT COUNT(*) INTO v_recent_attempts
    FROM public.guest_lookup_attempts
    WHERE guest_email = lower(p_guest_email)
      AND created_at >= now() - interval '15 minutes';

    IF v_recent_attempts >= 10 THEN
        RAISE EXCEPTION 'Too many lookup attempts. Please try again later.';
    END IF;

    INSERT INTO public.guest_lookup_attempts (guest_email)
    VALUES (lower(p_guest_email));

    RETURN QUERY
    SELECT b.id,
           b.status,
           b.requested_room_type,
           b.check_in_date,
           b.check_out_date,
           b.room_id,
           r.room_number,
           b.paid_amount,
           b.total_amount,
           b.guest_name,
           b.guest_email,
           b.payment_reference,
           b.payment_method
    FROM public.bookings b
    LEFT JOIN public.rooms r ON r.id = b.room_id
    WHERE b.payment_reference = p_payment_reference
      AND lower(COALESCE(b.guest_email, '')) = lower(p_guest_email)
    ORDER BY b.created_at DESC
    LIMIT 1;
END;
$$;

-- Guest booking lookup attempts (rate limit)
CREATE TABLE public.guest_lookup_attempts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    guest_email TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_guest_lookup_attempts_email_time
ON public.guest_lookup_attempts (guest_email, created_at DESC);

ALTER TABLE public.guest_lookup_attempts ENABLE ROW LEVEL SECURITY;

-- No public policies: access is only via SECURITY DEFINER function.

-- Cleanup old lookup attempts
CREATE OR REPLACE FUNCTION public.cleanup_guest_lookup_attempts()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    DELETE FROM public.guest_lookup_attempts
    WHERE created_at < now() - interval '7 days';
END;
$$;

-- Secure guest booking confirmation (updates payment + income)
CREATE OR REPLACE FUNCTION public.confirm_guest_booking(
    p_booking_id UUID,
    p_paid_amount INT8,
    p_payment_reference TEXT DEFAULT NULL,
    p_payment_method TEXT DEFAULT 'online',
    p_guest_email TEXT DEFAULT NULL
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_booking RECORD;
    v_room_type TEXT;
BEGIN
    SELECT * INTO v_booking
    FROM public.bookings
    WHERE id = p_booking_id
    FOR UPDATE;

    IF v_booking IS NULL THEN
        RAISE EXCEPTION 'Booking not found';
    END IF;

    IF v_booking.guest_profile_id IS NOT NULL THEN
        IF v_booking.guest_profile_id IS DISTINCT FROM auth.uid() THEN
            RAISE EXCEPTION 'Not authorized to confirm this booking';
        END IF;
    ELSE
        IF p_payment_reference IS NULL OR p_guest_email IS NULL THEN
            RAISE EXCEPTION 'Missing payment reference or guest email';
        END IF;
        IF v_booking.payment_reference IS DISTINCT FROM p_payment_reference THEN
            RAISE EXCEPTION 'Invalid payment reference';
        END IF;
        IF lower(COALESCE(v_booking.guest_email, '')) <> lower(p_guest_email) THEN
            RAISE EXCEPTION 'Guest email mismatch';
        END IF;
    END IF;

    UPDATE public.bookings
    SET status = 'Pending Check-in',
        paid_amount = p_paid_amount,
        payment_method = p_payment_method,
        payment_reference = COALESCE(p_payment_reference, payment_reference),
        payment_verified = true,
        updated_at = now()
    WHERE id = p_booking_id;

    v_room_type := COALESCE(v_booking.requested_room_type, 'Room');
    IF NOT EXISTS (
        SELECT 1 FROM public.income_records
        WHERE booking_id = p_booking_id
          AND source = 'Room Booking'
    ) THEN
        INSERT INTO public.income_records (
            description,
            amount,
            source,
            date,
            department,
            payment_method,
            booking_id,
            created_by
        ) VALUES (
            'Room booking - ' || v_room_type,
            p_paid_amount,
            'Room Booking',
            CURRENT_DATE,
            'reception',
            p_payment_method,
            p_booking_id,
            auth.uid()
        );
    END IF;
END;
$$;

-- FIXED: Function to check in guest (Requires room_id to be assigned first)
CREATE OR REPLACE FUNCTION public.check_in_guest(booking_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    -- Verify booking has room assigned
    IF NOT EXISTS (
        SELECT 1 FROM public.bookings
        WHERE id = booking_id
        AND room_id IS NOT NULL
    ) THEN
        RAISE EXCEPTION 'Room must be assigned before check-in';
    END IF;
    
    -- Update booking status
    UPDATE public.bookings 
    SET status = 'Checked-in'
    WHERE id = booking_id AND status = 'Pending Check-in';
    
    -- Update room status
    UPDATE public.rooms 
    SET status = 'Occupied'
    WHERE id = (SELECT room_id FROM public.bookings WHERE id = booking_id);
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function to check out guest
CREATE OR REPLACE FUNCTION public.check_out_guest(booking_id UUID)
RETURNS BOOLEAN AS $$
BEGIN
    -- Update booking status
    UPDATE public.bookings 
    SET status = 'Checked-out'
    WHERE id = booking_id AND status = 'Checked-in';
    
    -- Update room status
    UPDATE public.rooms 
    SET status = 'Dirty'
    WHERE id = (SELECT room_id FROM public.bookings WHERE id = booking_id);
    
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate stock levels
CREATE OR REPLACE FUNCTION public.calculate_stock_level(item_id UUID, location_id UUID)
RETURNS INTEGER AS $$
DECLARE
    total_in INTEGER;
    total_out INTEGER;
BEGIN
    SELECT COALESCE(SUM(quantity), 0) INTO total_in
    FROM public.stock_transactions 
    WHERE stock_transactions.stock_item_id = calculate_stock_level.item_id 
    AND stock_transactions.location_id = calculate_stock_level.location_id
    AND transaction_type IN ('Purchase', 'Transfer_In', 'Adjustment', 'Direct_Supply')
    AND quantity > 0;
    
    SELECT COALESCE(SUM(ABS(quantity)), 0) INTO total_out
    FROM public.stock_transactions 
    WHERE stock_transactions.stock_item_id = calculate_stock_level.item_id 
    AND stock_transactions.location_id = calculate_stock_level.location_id
    AND transaction_type IN ('Sale', 'Transfer_Out', 'Wastage', 'Adjustment')
    AND quantity < 0;
    
    RETURN total_in - total_out;
END;
$$ LANGUAGE plpgsql;

-- Function to get room occupancy rate
CREATE OR REPLACE FUNCTION public.get_occupancy_rate()
RETURNS DECIMAL AS $$
DECLARE
    total_rooms INTEGER;
    occupied_rooms INTEGER;
BEGIN
    SELECT COUNT(*) INTO total_rooms FROM public.rooms;
    SELECT COUNT(*) INTO occupied_rooms FROM public.rooms WHERE status = 'Occupied';
    
    IF total_rooms = 0 THEN
        RETURN 0;
    END IF;
    
    RETURN (occupied_rooms::DECIMAL / total_rooms::DECIMAL) * 100;
END;
$$ LANGUAGE plpgsql;

-- Function to get daily revenue
CREATE OR REPLACE FUNCTION public.get_daily_revenue(target_date DATE DEFAULT CURRENT_DATE)
RETURNS INT8 AS $$
DECLARE
    daily_revenue INT8;
BEGIN
    SELECT COALESCE(SUM(paid_amount), 0) INTO daily_revenue
    FROM public.bookings 
    WHERE DATE(created_at) = target_date;
    
    RETURN daily_revenue;
END;
$$ LANGUAGE plpgsql;

-- Function to create staff profile (for HR screen - Owner/HR/Manager)
-- Note: This requires the auth user to be created first via Supabase Admin API
-- Then this function updates the profile with staff role
CREATE OR REPLACE FUNCTION public.create_staff_profile(
    p_email TEXT,
    p_full_name TEXT,
    p_role TEXT,
    p_phone TEXT DEFAULT NULL,
    p_department TEXT DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
BEGIN
    -- Verify caller is owner, hr, or manager
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() 
        AND status = 'Active'
        AND ('owner' = ANY(roles) OR 'hr' = ANY(roles) OR 'manager' = ANY(roles))
    ) THEN
        RAISE EXCEPTION 'Only owner, HR manager, or manager can create staff profiles';
    END IF;

    -- Get the user ID (user must be created via Admin API first)
    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = p_email;
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User with email % does not exist. Please create auth user first via Supabase Admin API.', p_email;
    END IF;

    -- Create or update profile with staff role
    INSERT INTO public.profiles (id, full_name, email, phone, roles, status, department)
    VALUES (v_user_id, p_full_name, p_email, p_phone, ARRAY[p_role], 'Active', p_department)
    ON CONFLICT (id) DO UPDATE
    SET 
        full_name = EXCLUDED.full_name,
        email = EXCLUDED.email,
        phone = EXCLUDED.phone,
        roles = EXCLUDED.roles,
        status = 'Active',
        department = EXCLUDED.department,
        updated_at = now();
    
    RETURN v_user_id;
END;
$$;

-- ==============================================
-- 18. TRIGGERS
-- ==============================================

-- Function for automatic updated_at
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Cleanup references before deleting a profile (testing support)
CREATE OR REPLACE FUNCTION public.cleanup_profile_references()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
BEGIN
    -- Bookings
    UPDATE public.bookings
    SET created_by_name = COALESCE(created_by_name, OLD.full_name),
        created_by = NULL
    WHERE created_by = OLD.id;
    UPDATE public.bookings
    SET discount_applied_by_name = COALESCE(discount_applied_by_name, OLD.full_name),
        discount_applied_by = NULL
    WHERE discount_applied_by = OLD.id;
    UPDATE public.bookings
    SET guest_profile_id = NULL
    WHERE guest_profile_id = OLD.id;

    -- Booking charges
    UPDATE public.booking_charges
    SET added_by_name = COALESCE(added_by_name, OLD.full_name),
        added_by = NULL
    WHERE added_by = OLD.id;

    -- Stock transactions
    UPDATE public.stock_transactions
    SET staff_name = COALESCE(staff_name, OLD.full_name),
        staff_profile_id = NULL
    WHERE staff_profile_id = OLD.id;

    -- Direct supply requests
    UPDATE public.direct_supply_requests
    SET requested_by_name = COALESCE(requested_by_name, OLD.full_name),
        requested_by = NULL
    WHERE requested_by = OLD.id;
    UPDATE public.direct_supply_requests
    SET approved_by_name = COALESCE(approved_by_name, OLD.full_name),
        approved_by = NULL
    WHERE approved_by = OLD.id;

    -- Stock transfers
    UPDATE public.stock_transfers
    SET issued_by_name = COALESCE(issued_by_name, OLD.full_name),
        issued_by_id = NULL
    WHERE issued_by_id = OLD.id;
    UPDATE public.stock_transfers
    SET received_by_name = COALESCE(received_by_name, OLD.full_name),
        received_by_id = NULL
    WHERE received_by_id = OLD.id;

    -- Department transfers
    UPDATE public.department_transfers
    SET dispatched_by_name = COALESCE(dispatched_by_name, OLD.full_name),
        dispatched_by_id = NULL
    WHERE dispatched_by_id = OLD.id;

    -- Purchase orders/budgets
    UPDATE public.purchase_orders
    SET purchaser_name = COALESCE(purchaser_name, OLD.full_name),
        purchaser_id = NULL
    WHERE purchaser_id = OLD.id;
    UPDATE public.purchase_orders
    SET storekeeper_name = COALESCE(storekeeper_name, OLD.full_name),
        storekeeper_id = NULL
    WHERE storekeeper_id = OLD.id;
    UPDATE public.purchase_budgets
    SET created_by_name = COALESCE(created_by_name, OLD.full_name),
        created_by = NULL
    WHERE created_by = OLD.id;
    UPDATE public.purchase_budgets
    SET updated_by_name = COALESCE(updated_by_name, OLD.full_name),
        updated_by = NULL
    WHERE updated_by = OLD.id;

    -- Expenses/income/payroll
    UPDATE public.expenses
    SET profile_name = COALESCE(profile_name, OLD.full_name),
        profile_id = NULL
    WHERE profile_id = OLD.id;
    UPDATE public.expenses
    SET approved_by_name = COALESCE(approved_by_name, OLD.full_name),
        approved_by = NULL
    WHERE approved_by = OLD.id;
    UPDATE public.expenses
    SET rejected_by_name = COALESCE(rejected_by_name, OLD.full_name),
        rejected_by = NULL
    WHERE rejected_by = OLD.id;
    UPDATE public.income_records
    SET staff_name = COALESCE(staff_name, OLD.full_name),
        staff_id = NULL
    WHERE staff_id = OLD.id;
    UPDATE public.income_records
    SET created_by_name = COALESCE(created_by_name, OLD.full_name),
        created_by = NULL
    WHERE created_by = OLD.id;
    UPDATE public.payroll_records
    SET staff_name = COALESCE(staff_name, OLD.full_name),
        staff_id = NULL
    WHERE staff_id = OLD.id;
    UPDATE public.payroll_records
    SET approved_by_name = COALESCE(approved_by_name, OLD.full_name),
        approved_by = NULL
    WHERE approved_by = OLD.id;
    UPDATE public.payroll_records
    SET processed_by_name = COALESCE(processed_by_name, OLD.full_name),
        processed_by = NULL
    WHERE processed_by = OLD.id;

    -- Debts/payments
    UPDATE public.debts
    SET created_by_name = COALESCE(created_by_name, OLD.full_name),
        created_by = NULL
    WHERE created_by = OLD.id;
    UPDATE public.debts
    SET sold_by_name = COALESCE(sold_by_name, OLD.full_name),
        sold_by = NULL
    WHERE sold_by = OLD.id;
    UPDATE public.debt_payments
    SET collected_by_name = COALESCE(collected_by_name, OLD.full_name),
        collected_by = NULL
    WHERE collected_by = OLD.id;
    UPDATE public.debt_payments
    SET created_by_name = COALESCE(created_by_name, OLD.full_name),
        created_by = NULL
    WHERE created_by = OLD.id;

    -- Sales/shift logs
    UPDATE public.mini_mart_sales
    SET sold_by_name = COALESCE(sold_by_name, OLD.full_name),
        sold_by = NULL
    WHERE sold_by = OLD.id;
    UPDATE public.kitchen_sales
    SET sold_by_name = COALESCE(sold_by_name, OLD.full_name),
        sold_by = NULL
    WHERE sold_by = OLD.id;
    UPDATE public.bartender_shifts
    SET bartender_name = COALESCE(bartender_name, OLD.full_name),
        bartender_id = NULL
    WHERE bartender_id = OLD.id;
    UPDATE public.bartender_shifts
    SET closed_by_name = COALESCE(closed_by_name, OLD.full_name),
        closed_by = NULL
    WHERE closed_by = OLD.id;

    -- HR/attendance/communications
    UPDATE public.positions
    SET created_by_name = COALESCE(created_by_name, OLD.full_name),
        created_by = NULL
    WHERE created_by = OLD.id;
    UPDATE public.attendance_records
    SET profile_name = COALESCE(profile_name, OLD.full_name),
        profile_id = NULL
    WHERE profile_id = OLD.id;
    UPDATE public.posts
    SET author_name = COALESCE(author_name, OLD.full_name),
        author_profile_id = NULL
    WHERE author_profile_id = OLD.id;
    UPDATE public.notifications
    SET user_name = COALESCE(user_name, OLD.full_name),
        user_id = NULL
    WHERE user_id = OLD.id;
    UPDATE public.staff_role_assignments
    SET staff_name = COALESCE(staff_name, OLD.full_name),
        staff_id = NULL
    WHERE staff_id = OLD.id;
    UPDATE public.staff_role_assignments
    SET assigned_by_name = COALESCE(assigned_by_name, OLD.full_name),
        assigned_by = NULL
    WHERE assigned_by = OLD.id;

    -- Maintenance
    UPDATE public.maintenance_work_orders
    SET reported_by_name = COALESCE(reported_by_name, OLD.full_name),
        reported_by_id = NULL
    WHERE reported_by_id = OLD.id;
    UPDATE public.maintenance_work_orders
    SET assigned_to_name = COALESCE(assigned_to_name, OLD.full_name),
        assigned_to = NULL
    WHERE assigned_to = OLD.id;
    UPDATE public.work_orders
    SET assigned_to_name = COALESCE(assigned_to_name, OLD.full_name),
        assigned_to = NULL
    WHERE assigned_to = OLD.id;
    UPDATE public.work_orders
    SET created_by_name = COALESCE(created_by_name, OLD.full_name),
        created_by = NULL
    WHERE created_by = OLD.id;

    -- Logs
    UPDATE public.room_status_logs
    SET changed_by_name = COALESCE(changed_by_name, OLD.full_name),
        changed_by = NULL
    WHERE changed_by = OLD.id;
    UPDATE public.finance_audit_logs
    SET actor_name = COALESCE(actor_name, OLD.full_name),
        actor_id = NULL
    WHERE actor_id = OLD.id;
    UPDATE public.cash_deposits
    SET staff_name = COALESCE(staff_name, OLD.full_name),
        staff_id = NULL
    WHERE staff_id = OLD.id;
    UPDATE public.cash_deposits
    SET created_by_name = COALESCE(created_by_name, OLD.full_name),
        created_by = NULL
    WHERE created_by = OLD.id;

    RETURN OLD;
END;
$$;

-- Create triggers for updated_at
CREATE TRIGGER update_profiles_updated_at BEFORE UPDATE ON public.profiles FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_room_types_updated_at BEFORE UPDATE ON public.room_types FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_rooms_updated_at BEFORE UPDATE ON public.rooms FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_bookings_updated_at BEFORE UPDATE ON public.bookings FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_menu_items_updated_at BEFORE UPDATE ON public.menu_items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_stock_items_updated_at BEFORE UPDATE ON public.stock_items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_inventory_items_updated_at BEFORE UPDATE ON public.inventory_items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_expenses_updated_at BEFORE UPDATE ON public.expenses FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_assets_updated_at BEFORE UPDATE ON public.assets FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_work_orders_updated_at BEFORE UPDATE ON public.work_orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_maintenance_work_orders_updated_at BEFORE UPDATE ON public.maintenance_work_orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_posts_updated_at BEFORE UPDATE ON public.posts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_kitchen_orders_updated_at BEFORE UPDATE ON public.kitchen_orders FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_income_records_updated_at BEFORE UPDATE ON public.income_records FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_payroll_records_updated_at BEFORE UPDATE ON public.payroll_records FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_cash_deposits_updated_at BEFORE UPDATE ON public.cash_deposits FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_debts_updated_at BEFORE UPDATE ON public.debts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_debt_payments_updated_at BEFORE UPDATE ON public.debt_payments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_mini_mart_items_updated_at BEFORE UPDATE ON public.mini_mart_items FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_mini_mart_sales_updated_at BEFORE UPDATE ON public.mini_mart_sales FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_department_sales_updated_at BEFORE UPDATE ON public.department_sales FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_bartender_shifts_updated_at BEFORE UPDATE ON public.bartender_shifts FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();
CREATE TRIGGER update_staff_role_assignments_updated_at BEFORE UPDATE ON public.staff_role_assignments FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

DROP TRIGGER IF EXISTS trg_cleanup_profile_references ON public.profiles;
CREATE TRIGGER trg_cleanup_profile_references
BEFORE DELETE ON public.profiles
FOR EACH ROW EXECUTE FUNCTION public.cleanup_profile_references();

-- ==============================================
-- 19. VIEWS (FIXED)
-- ==============================================

-- Room Occupancy View (Shows bookings with or without rooms)
CREATE VIEW public.room_occupancy AS
SELECT 
    r.room_number,
    r.type,
    r.status,
    rt.price,
    p.full_name as guest_name,
    b.check_in_date,
    b.check_out_date,
    b.status as booking_status,
    CASE WHEN b.room_id IS NULL THEN 'Room Not Assigned' ELSE 'Room Assigned' END as assignment_status
FROM public.rooms r
LEFT JOIN public.room_types rt ON r.type_id = rt.id
LEFT JOIN public.bookings b ON r.id = b.room_id AND b.status = 'Checked-in'
LEFT JOIN public.profiles p ON b.guest_profile_id = p.id;

-- View for bookings needing room assignment
CREATE VIEW public.bookings_needing_room_assignment AS
SELECT 
    b.id,
    b.created_at,
    p.full_name as guest_name,
    p.phone,
    p.email,
    b.requested_room_type,
    b.check_in_date,
    b.check_out_date,
    b.status,
    b.total_amount,
    b.paid_amount
FROM public.bookings b
INNER JOIN public.profiles p ON b.guest_profile_id = p.id
WHERE b.room_id IS NULL
AND b.status = 'Pending Check-in'
AND b.requested_room_type IS NOT NULL
ORDER BY b.check_in_date ASC;

-- Stock Levels View
CREATE VIEW public.stock_levels AS
SELECT 
    si.id,
    si.name,
    l.name as location_name,
    public.calculate_stock_level(si.id, l.id) as current_stock,
    si.min_stock
FROM public.stock_items si
CROSS JOIN public.locations l
WHERE public.calculate_stock_level(si.id, l.id) > 0;

-- Daily Sales View
CREATE VIEW public.daily_sales AS
SELECT 
    DATE(created_at) as sale_date,
    COUNT(*) as total_bookings,
    SUM(total_amount) as total_revenue,
    SUM(paid_amount) as paid_revenue
FROM public.bookings
GROUP BY DATE(created_at)
ORDER BY sale_date DESC;

-- ==============================================
-- 20. INDEXES
-- ==============================================

-- Bookings indexes
CREATE INDEX IF NOT EXISTS idx_bookings_room_id ON public.bookings(room_id);
CREATE INDEX IF NOT EXISTS idx_bookings_status ON public.bookings(status);
CREATE INDEX IF NOT EXISTS idx_bookings_dates ON public.bookings(check_in_date, check_out_date);
CREATE INDEX IF NOT EXISTS idx_bookings_guest_profile_id ON public.bookings(guest_profile_id);
CREATE INDEX IF NOT EXISTS idx_bookings_guest_status ON public.bookings(guest_profile_id, status);
CREATE INDEX IF NOT EXISTS idx_bookings_created_at ON public.bookings(created_at);
CREATE INDEX IF NOT EXISTS idx_bookings_requested_room_type ON public.bookings(requested_room_type);
CREATE INDEX IF NOT EXISTS idx_bookings_room_id_null ON public.bookings(room_id) WHERE room_id IS NULL;

-- Rooms indexes
CREATE INDEX IF NOT EXISTS idx_rooms_status ON public.rooms(status);
CREATE INDEX IF NOT EXISTS idx_rooms_type ON public.rooms(type);

-- Stock transactions indexes
CREATE INDEX IF NOT EXISTS idx_stock_transactions_item ON public.stock_transactions(stock_item_id);
CREATE INDEX IF NOT EXISTS idx_stock_transactions_location ON public.stock_transactions(location_id);
CREATE INDEX IF NOT EXISTS idx_stock_transactions_created_at ON public.stock_transactions(created_at);
CREATE INDEX IF NOT EXISTS idx_stock_transactions_staff_created ON public.stock_transactions(staff_profile_id, created_at);

-- Inventory items indexes (for bar-specific queries)
CREATE INDEX IF NOT EXISTS idx_inventory_items_department ON public.inventory_items(department);
CREATE INDEX IF NOT EXISTS idx_inventory_items_category ON public.inventory_items(category);
CREATE INDEX IF NOT EXISTS idx_inventory_items_location ON public.inventory_items(location_id);

-- Attendance indexes
CREATE INDEX IF NOT EXISTS idx_attendance_staff ON public.attendance_records(profile_id);
CREATE INDEX IF NOT EXISTS idx_attendance_date ON public.attendance_records(date);
CREATE INDEX IF NOT EXISTS idx_attendance_staff_date ON public.attendance_records(profile_id, date);

-- Notifications indexes
CREATE INDEX IF NOT EXISTS idx_notifications_user ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_user_created ON public.notifications(user_id, created_at);

-- Additional indexes for new tables (performance optimization)
CREATE INDEX IF NOT EXISTS idx_income_records_date ON public.income_records(date);
CREATE INDEX IF NOT EXISTS idx_income_records_staff ON public.income_records(staff_id);
CREATE INDEX IF NOT EXISTS idx_payroll_staff_month ON public.payroll_records(staff_id, month);
CREATE INDEX IF NOT EXISTS idx_payroll_status ON public.payroll_records(status);
CREATE INDEX IF NOT EXISTS idx_cash_deposits_date ON public.cash_deposits(date);
CREATE INDEX IF NOT EXISTS idx_debts_status ON public.debts(status);
CREATE INDEX IF NOT EXISTS idx_debts_debtor ON public.debts(debtor_name);
CREATE INDEX IF NOT EXISTS idx_debts_sold_by ON public.debts(sold_by);
CREATE INDEX IF NOT EXISTS idx_debts_booking_id ON public.debts(booking_id);
CREATE INDEX IF NOT EXISTS idx_debts_sale_id ON public.debts(sale_id);
CREATE INDEX IF NOT EXISTS idx_debt_payments_debt_id ON public.debt_payments(debt_id);
CREATE INDEX IF NOT EXISTS idx_debt_payments_date ON public.debt_payments(payment_date);
CREATE INDEX IF NOT EXISTS idx_debt_payments_collected_by ON public.debt_payments(collected_by);
CREATE INDEX IF NOT EXISTS idx_mini_mart_items_name ON public.mini_mart_items(name);
CREATE INDEX IF NOT EXISTS idx_mini_mart_items_barcode ON public.mini_mart_items(barcode);
CREATE INDEX IF NOT EXISTS idx_mini_mart_sales_date ON public.mini_mart_sales(sale_date);
CREATE INDEX IF NOT EXISTS idx_mini_mart_sales_item ON public.mini_mart_sales(item_id);
CREATE INDEX IF NOT EXISTS idx_mini_mart_sales_sold_by ON public.mini_mart_sales(sold_by);
CREATE INDEX IF NOT EXISTS idx_department_sales_date_dept ON public.department_sales(date, department);
CREATE INDEX IF NOT EXISTS idx_department_sales_staff_id ON public.department_sales(staff_id);
CREATE INDEX IF NOT EXISTS idx_department_sales_date_staff_id ON public.department_sales(date, staff_id);
CREATE INDEX IF NOT EXISTS idx_bartender_shifts_bartender ON public.bartender_shifts(bartender_id);
CREATE INDEX IF NOT EXISTS idx_bartender_shifts_date ON public.bartender_shifts(date);
CREATE INDEX IF NOT EXISTS idx_bartender_shifts_status ON public.bartender_shifts(status);
CREATE INDEX IF NOT EXISTS idx_bartender_shifts_bartender_date ON public.bartender_shifts(bartender_id, date);
CREATE INDEX IF NOT EXISTS idx_staff_role_assignments_staff ON public.staff_role_assignments(staff_id);
CREATE INDEX IF NOT EXISTS idx_staff_role_assignments_active ON public.staff_role_assignments(is_active) WHERE is_active = true;
CREATE INDEX IF NOT EXISTS idx_expenses_date ON public.expenses(transaction_date);
CREATE INDEX IF NOT EXISTS idx_expenses_profile ON public.expenses(profile_id);
CREATE INDEX IF NOT EXISTS idx_profiles_email ON public.profiles(email);
CREATE INDEX IF NOT EXISTS idx_profiles_status ON public.profiles(status);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_status ON public.purchase_orders(status);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_purchaser ON public.purchase_orders(purchaser_id);
CREATE INDEX IF NOT EXISTS idx_maintenance_work_orders_status ON public.maintenance_work_orders(status);
CREATE INDEX IF NOT EXISTS idx_maintenance_work_orders_reported ON public.maintenance_work_orders(reported_by_id);

-- ==============================================
-- 21. INITIAL DATA
-- ==============================================

-- Populate Locations
INSERT INTO public.locations (name, type) VALUES 
('Main Storeroom', 'Storage'), 
('VIP Bar', 'Bar'), 
('Outside Bar', 'Bar'), 
('Kitchen', 'Kitchen'), 
('Mini Mart', 'Other')
ON CONFLICT (name) DO NOTHING;

-- Populate Departments
-- Note: Department names use lowercase with underscores to match code usage
INSERT INTO public.departments (name) VALUES 
('reception'), 
('vip_bar'), 
('outside_bar'), 
('restaurant'), 
('laundry'), 
('mini_mart'), 
('storekeeping'), 
('purchasing'), 
('general')
ON CONFLICT (name) DO NOTHING;

-- Populate Expense Categories
INSERT INTO public.expense_categories (name) VALUES 
('Utilities'), 
('Salaries'), 
('Supplies'), 
('Maintenance')
ON CONFLICT (name) DO NOTHING;

-- Populate Site Media Keys (Empty placeholders)
INSERT INTO public.site_media (content_key, title, media_url) VALUES 
('hero_image', 'Hero Image', ''),
('facility_vip_bar', 'VIP Bar Image', ''),
('facility_kitchen', 'Kitchen Image', '')
ON CONFLICT (content_key) DO NOTHING;

-- ==============================================
-- 22. GRANT PERMISSIONS
-- ==============================================

GRANT USAGE ON SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL TABLES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL SEQUENCES IN SCHEMA public TO anon, authenticated;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA public TO anon, authenticated;

-- ==============================================
-- END OF SCHEMA
-- ==============================================