-- Migration: Wastage Reporting and Notification System
-- This script creates the wastage_requests and notifications tables with RLS policies

-- ==============================================
-- 1. WASTAGE_REQUESTS TABLE
-- ==============================================

CREATE TABLE IF NOT EXISTS public.wastage_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    stock_item_id UUID NOT NULL REFERENCES public.stock_items(id) ON DELETE CASCADE,
    location_id UUID NOT NULL REFERENCES public.locations(id) ON DELETE CASCADE,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    reason_type TEXT NOT NULL CHECK (reason_type IN ('spoilt', 'trashed', 'destroyed', 'expired')),
    notes TEXT,
    requested_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE SET NULL,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on wastage_requests
ALTER TABLE public.wastage_requests ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Staff can view own wastage requests" ON public.wastage_requests;
DROP POLICY IF EXISTS "Management can view all wastage requests" ON public.wastage_requests;
DROP POLICY IF EXISTS "Active staff can create wastage requests" ON public.wastage_requests;
DROP POLICY IF EXISTS "Management can approve wastage requests" ON public.wastage_requests;

-- Create RLS policies for wastage_requests
CREATE POLICY "Staff can view own wastage requests"
ON public.wastage_requests FOR SELECT
USING (requested_by = auth.uid());

CREATE POLICY "Management can view all wastage requests"
ON public.wastage_requests FOR SELECT
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
    AND status = 'Active'
    AND (
      'owner' = ANY(roles) OR
      'manager' = ANY(roles) OR
      'supervisor' = ANY(roles) OR
      'accountant' = ANY(roles) OR
      'storekeeper' = ANY(roles)
    )
  )
);

CREATE POLICY "Active staff can create wastage requests"
ON public.wastage_requests FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
    AND status = 'Active'
  )
);

CREATE POLICY "Management can approve wastage requests"
ON public.wastage_requests FOR UPDATE
USING (
  EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
    AND status = 'Active'
    AND ('owner' = ANY(roles) OR 'manager' = ANY(roles) OR 'supervisor' = ANY(roles))
  )
);

-- Create updated_at trigger
CREATE OR REPLACE FUNCTION update_wastage_requests_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER wastage_requests_updated_at
BEFORE UPDATE ON public.wastage_requests
FOR EACH ROW
EXECUTE FUNCTION update_wastage_requests_updated_at();

-- ==============================================
-- 2. NOTIFICATIONS TABLE
-- ==============================================

CREATE TABLE IF NOT EXISTS public.notifications (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    type TEXT NOT NULL CHECK (type IN ('wastage_request', 'wastage_approved', 'wastage_rejected')),
    title TEXT NOT NULL,
    message TEXT NOT NULL,
    related_id UUID, -- wastage_request_id
    is_read BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable RLS on notifications
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if they exist
DROP POLICY IF EXISTS "Users can view own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can insert own notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can update own notifications" ON public.notifications;

-- Create RLS policies for notifications
CREATE POLICY "Users can view own notifications"
ON public.notifications FOR SELECT
USING (user_id = auth.uid());

CREATE POLICY "Users can insert own notifications"
ON public.notifications FOR INSERT
WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can update own notifications"
ON public.notifications FOR UPDATE
USING (user_id = auth.uid());

-- Create index for performance
CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_is_read ON public.notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created_at ON public.notifications(created_at DESC);

-- Create index for wastage_requests performance
CREATE INDEX IF NOT EXISTS idx_wastage_requests_requested_by ON public.wastage_requests(requested_by);
CREATE INDEX IF NOT EXISTS idx_wastage_requests_status ON public.wastage_requests(status);
CREATE INDEX IF NOT EXISTS idx_wastage_requests_location_id ON public.wastage_requests(location_id);
CREATE INDEX IF NOT EXISTS idx_wastage_requests_created_at ON public.wastage_requests(created_at DESC);

-- ==============================================
-- 3. AUTO-DELETION FUNCTION (14 months)
-- ==============================================

CREATE OR REPLACE FUNCTION delete_old_wastage_requests()
RETURNS void AS $$
BEGIN
    DELETE FROM public.wastage_requests
    WHERE status = 'approved'
    AND approved_at < NOW() - INTERVAL '14 months';
END;
$$ LANGUAGE plpgsql;

-- Comment: This function should be scheduled to run periodically (e.g., daily via pg_cron)
-- Example pg_cron schedule: SELECT cron.schedule('delete-old-wastage', '0 2 * * *', 'SELECT delete_old_wastage_requests()');

-- Verify table creation
SELECT 'wastage_requests table created' as status;
SELECT 'notifications table created' as status;
