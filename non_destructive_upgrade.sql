-- ==============================================
-- NON-DESTRUCTIVE UPGRADE SCRIPT (TEST PERIOD)
-- ==============================================
-- This script applies the latest fixes without dropping tables or data.
-- Safe to run multiple times.
-- ==============================================

-- 1) RLS helper functions
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

GRANT EXECUTE ON FUNCTION public.is_user_active(UUID) TO anon, authenticated;
GRANT EXECUTE ON FUNCTION public.user_has_role(UUID, TEXT) TO anon, authenticated;

-- 2) Profiles policies (owner/hr/manager)
DO $$
BEGIN
  ALTER TABLE public.posts
    ADD COLUMN IF NOT EXISTS target_user_ids UUID[] DEFAULT NULL;

  DROP POLICY IF EXISTS "Active staff read posts" ON public.posts;
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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

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

-- Management notifications (quiet alerts)
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
DO $$
BEGIN
  DROP POLICY IF EXISTS "Owner can create staff profiles" ON public.profiles;
  DROP POLICY IF EXISTS "Owner and HR can create staff profiles" ON public.profiles;
  DROP POLICY IF EXISTS "Owner HR and Manager can create staff profiles" ON public.profiles;

  CREATE POLICY "Owner HR and Manager can create staff profiles"
  ON public.profiles FOR INSERT WITH CHECK (
    is_user_active(auth.uid())
    AND (
      user_has_role(auth.uid(), 'owner')
      OR user_has_role(auth.uid(), 'hr')
      OR user_has_role(auth.uid(), 'manager')
    )
  );

  DROP POLICY IF EXISTS "Owner can update staff profiles" ON public.profiles;
  DROP POLICY IF EXISTS "Owner HR and Manager can update staff profiles" ON public.profiles;

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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Security hardening: remove public bookings read policy (availability via RPC only)
DO $$
BEGIN
  DROP POLICY IF EXISTS "Public can check availability" ON public.bookings;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Debts: add department column for departmental debt summaries
DO $$
BEGIN
  ALTER TABLE public.debts ADD COLUMN IF NOT EXISTS department TEXT;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Mini mart items: receptionist read-only, management full access
DO $$
BEGIN
  DROP POLICY IF EXISTS "Reception staff access mini mart items" ON public.mini_mart_items;
  DROP POLICY IF EXISTS "Management can manage mini mart items" ON public.mini_mart_items;
  CREATE POLICY "Reception staff access mini mart items" ON public.mini_mart_items FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.status = 'Active'
      AND ('receptionist' = ANY(p.roles) OR 'manager' = ANY(p.roles) OR 'owner' = ANY(p.roles))
    )
  );
  CREATE POLICY "Management can manage mini mart items" ON public.mini_mart_items FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.status = 'Active'
      AND (p.roles && ARRAY['manager', 'owner'])
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 10.4) Debts: allow sales staff to insert debts they created
DO $$
BEGIN
  DROP POLICY IF EXISTS "Staff can insert debts" ON public.debts;
  CREATE POLICY "Staff can insert debts" ON public.debts FOR INSERT
  WITH CHECK (
    is_user_active(auth.uid())
    AND sold_by = auth.uid()
    AND (
      user_has_role(auth.uid(), 'receptionist')
      OR user_has_role(auth.uid(), 'kitchen_staff')
      OR user_has_role(auth.uid(), 'vip_bartender')
      OR user_has_role(auth.uid(), 'outside_bartender')
      OR user_has_role(auth.uid(), 'manager')
      OR user_has_role(auth.uid(), 'owner')
      OR user_has_role(auth.uid(), 'accountant')
    )
  );

  -- Staff can view debts they created or kitchen debts (vip_bartender, receptionist, kitchen_staff can all record kitchen credit)
  DROP POLICY IF EXISTS "Staff can view relevant debts" ON public.debts;
  CREATE POLICY "Staff can view relevant debts" ON public.debts FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.status = 'Active'
      AND (
        debts.sold_by = auth.uid()
        OR (p.roles && ARRAY['manager', 'owner', 'accountant'])
        OR (
          COALESCE(debts.source_department, debts.department) = 'restaurant'
          AND ('kitchen_staff' = ANY(p.roles) OR 'vip_bartender' = ANY(p.roles) OR 'receptionist' = ANY(p.roles))
        )
      )
    )
  );

  -- Staff can update kitchen debts: vip_bartender, receptionist, or kitchen_staff (any can record kitchen credit sales)
  DROP POLICY IF EXISTS "Staff can update own debts" ON public.debts;
  CREATE POLICY "Staff can update own debts" ON public.debts FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.status = 'Active'
      AND (
        debts.sold_by = auth.uid()
        OR (p.roles && ARRAY['manager', 'owner', 'accountant'])
        OR (
          COALESCE(debts.source_department, debts.department) = 'restaurant'
          AND ('kitchen_staff' = ANY(p.roles) OR 'vip_bartender' = ANY(p.roles) OR 'receptionist' = ANY(p.roles))
        )
      )
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 3) Update create_staff_profile function
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
    IF NOT EXISTS (
        SELECT 1 FROM public.profiles 
        WHERE id = auth.uid() 
        AND status = 'Active'
        AND ('owner' = ANY(roles) OR 'hr' = ANY(roles) OR 'manager' = ANY(roles))
    ) THEN
        RAISE EXCEPTION 'Only owner, HR manager, or manager can create staff profiles';
    END IF;

    SELECT id INTO v_user_id
    FROM auth.users
    WHERE email = p_email;
    
    IF v_user_id IS NULL THEN
        RAISE EXCEPTION 'User with email % does not exist. Please create auth user first via Supabase Admin API.', p_email;
    END IF;

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

-- 4) Guest booking creation (atomic)
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
    SELECT COUNT(*) INTO v_total_rooms
    FROM public.rooms
    WHERE type = p_requested_room_type
    AND status = 'Vacant';

    IF v_total_rooms = 0 THEN
        RAISE EXCEPTION 'No rooms of type % are available', p_requested_room_type;
    END IF;

    SELECT COUNT(DISTINCT room_id) INTO v_assigned_rooms
    FROM public.bookings
    WHERE room_id IS NOT NULL
    AND status IN ('Pending Check-in', 'Checked-in', 'confirmed', 'checked_in')
    AND check_in_date < p_check_out_date
    AND check_out_date > p_check_in_date;

    SELECT COUNT(*) INTO v_bookings_by_type
    FROM public.bookings
    WHERE room_id IS NULL
    AND requested_room_type = p_requested_room_type
    AND status IN ('Pending Check-in', 'Checked-in', 'confirmed', 'checked_in')
    AND check_in_date < p_check_out_date
    AND check_out_date > p_check_in_date;

    v_available_count := v_total_rooms - v_assigned_rooms - v_bookings_by_type;

    IF v_available_count <= 0 THEN
        RAISE EXCEPTION 'No rooms of type % are available for the selected dates', p_requested_room_type;
    END IF;

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

-- 4.0) Guest booking lookup by payment reference + email
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

-- 4.0.1) Guest booking lookup attempts (rate limit)
DO $$
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public'
      AND table_name = 'guest_lookup_attempts'
  ) THEN
      CREATE TABLE public.guest_lookup_attempts (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          guest_email TEXT NOT NULL,
          created_at TIMESTAMPTZ DEFAULT now()
      );
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_guest_lookup_attempts_email_time
ON public.guest_lookup_attempts (guest_email, created_at DESC);

ALTER TABLE public.guest_lookup_attempts ENABLE ROW LEVEL SECURITY;

-- 4.1) Booking confirmation + columns
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

-- Helper: drop FK constraint for a given table+column
DO $$
DECLARE
  r RECORD;
BEGIN
  FOR r IN
    SELECT con.conname AS constraint_name,
           con.conrelid::regclass AS table_name
    FROM pg_constraint con
    JOIN pg_attribute att
      ON att.attrelid = con.conrelid
     AND att.attnum = ANY (con.conkey)
    WHERE con.contype = 'f'
      AND (
        (con.conrelid::regclass = 'public.bookings'::regclass AND att.attname IN ('guest_profile_id','discount_applied_by','created_by')) OR
        (con.conrelid::regclass = 'public.booking_charges'::regclass AND att.attname IN ('added_by')) OR
        (con.conrelid::regclass = 'public.stock_transactions'::regclass AND att.attname IN ('staff_profile_id')) OR
        (con.conrelid::regclass = 'public.direct_supply_requests'::regclass AND att.attname IN ('requested_by','approved_by')) OR
        (con.conrelid::regclass = 'public.stock_transfers'::regclass AND att.attname IN ('issued_by_id','received_by_id')) OR
        (con.conrelid::regclass = 'public.department_transfers'::regclass AND att.attname IN ('dispatched_by_id')) OR
        (con.conrelid::regclass = 'public.purchase_orders'::regclass AND att.attname IN ('purchaser_id','storekeeper_id')) OR
        (con.conrelid::regclass = 'public.purchase_budgets'::regclass AND att.attname IN ('created_by','updated_by')) OR
        (con.conrelid::regclass = 'public.expenses'::regclass AND att.attname IN ('profile_id','approved_by','rejected_by')) OR
        (con.conrelid::regclass = 'public.income_records'::regclass AND att.attname IN ('staff_id','created_by')) OR
        (con.conrelid::regclass = 'public.payroll_records'::regclass AND att.attname IN ('staff_id','approved_by','processed_by')) OR
        (con.conrelid::regclass = 'public.debts'::regclass AND att.attname IN ('created_by','sold_by')) OR
        (con.conrelid::regclass = 'public.debt_payments'::regclass AND att.attname IN ('collected_by','created_by')) OR
        (con.conrelid::regclass = 'public.mini_mart_sales'::regclass AND att.attname IN ('sold_by')) OR
        (con.conrelid::regclass = 'public.kitchen_sales'::regclass AND att.attname IN ('sold_by')) OR
        (con.conrelid::regclass = 'public.positions'::regclass AND att.attname IN ('created_by')) OR
        (con.conrelid::regclass = 'public.attendance_records'::regclass AND att.attname IN ('profile_id')) OR
        (con.conrelid::regclass = 'public.posts'::regclass AND att.attname IN ('author_profile_id')) OR
        (con.conrelid::regclass = 'public.notifications'::regclass AND att.attname IN ('user_id')) OR
        (con.conrelid::regclass = 'public.staff_role_assignments'::regclass AND att.attname IN ('staff_id','assigned_by')) OR
        (con.conrelid::regclass = 'public.maintenance_work_orders'::regclass AND att.attname IN ('reported_by_id','assigned_to')) OR
        (con.conrelid::regclass = 'public.work_orders'::regclass AND att.attname IN ('assigned_to','created_by'))
      )
  LOOP
    EXECUTE format('ALTER TABLE %s DROP CONSTRAINT IF EXISTS %I', r.table_name, r.constraint_name);
  END LOOP;
END $$;

-- Add snapshot columns + re-add FKs with ON DELETE SET NULL
DO $$
BEGIN
  ALTER TABLE public.bookings
    ADD COLUMN IF NOT EXISTS discount_applied_by_name TEXT,
    ADD COLUMN IF NOT EXISTS created_by_name TEXT;
  ALTER TABLE public.booking_charges ADD COLUMN IF NOT EXISTS added_by_name TEXT;
  ALTER TABLE public.stock_transactions ADD COLUMN IF NOT EXISTS staff_name TEXT;
  ALTER TABLE public.direct_supply_requests
    ADD COLUMN IF NOT EXISTS requested_by_name TEXT,
    ADD COLUMN IF NOT EXISTS approved_by_name TEXT;
  ALTER TABLE public.stock_transfers
    ADD COLUMN IF NOT EXISTS issued_by_name TEXT,
    ADD COLUMN IF NOT EXISTS received_by_name TEXT;
  ALTER TABLE public.department_transfers ADD COLUMN IF NOT EXISTS dispatched_by_name TEXT;
  ALTER TABLE public.purchase_orders
    ADD COLUMN IF NOT EXISTS purchaser_name TEXT,
    ADD COLUMN IF NOT EXISTS storekeeper_name TEXT;
  ALTER TABLE public.purchase_budgets
    ADD COLUMN IF NOT EXISTS created_by_name TEXT,
    ADD COLUMN IF NOT EXISTS updated_by_name TEXT;
  ALTER TABLE public.expenses
    ADD COLUMN IF NOT EXISTS profile_name TEXT,
    ADD COLUMN IF NOT EXISTS approved_by_name TEXT,
    ADD COLUMN IF NOT EXISTS rejected_by_name TEXT;
  ALTER TABLE public.income_records
    ADD COLUMN IF NOT EXISTS staff_name TEXT,
    ADD COLUMN IF NOT EXISTS created_by_name TEXT;
  ALTER TABLE public.payroll_records
    ADD COLUMN IF NOT EXISTS staff_name TEXT,
    ADD COLUMN IF NOT EXISTS approved_by_name TEXT,
    ADD COLUMN IF NOT EXISTS processed_by_name TEXT;
  ALTER TABLE public.debts
    ADD COLUMN IF NOT EXISTS created_by_name TEXT,
    ADD COLUMN IF NOT EXISTS sold_by_name TEXT;
  ALTER TABLE public.debt_payments
    ADD COLUMN IF NOT EXISTS collected_by_name TEXT,
    ADD COLUMN IF NOT EXISTS created_by_name TEXT;
  ALTER TABLE public.mini_mart_sales ADD COLUMN IF NOT EXISTS sold_by_name TEXT;
  ALTER TABLE public.kitchen_sales ADD COLUMN IF NOT EXISTS sold_by_name TEXT;
  ALTER TABLE public.positions ADD COLUMN IF NOT EXISTS created_by_name TEXT;
  ALTER TABLE public.attendance_records ADD COLUMN IF NOT EXISTS profile_name TEXT;
  ALTER TABLE public.posts ADD COLUMN IF NOT EXISTS author_name TEXT;
  ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS user_name TEXT;
  ALTER TABLE public.staff_role_assignments
    ADD COLUMN IF NOT EXISTS staff_name TEXT,
    ADD COLUMN IF NOT EXISTS assigned_by_name TEXT;
  ALTER TABLE public.maintenance_work_orders
    ADD COLUMN IF NOT EXISTS reported_by_name TEXT,
    ADD COLUMN IF NOT EXISTS assigned_to_name TEXT;
  ALTER TABLE public.work_orders
    ADD COLUMN IF NOT EXISTS assigned_to_name TEXT,
    ADD COLUMN IF NOT EXISTS created_by_name TEXT;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Recreate FK constraints with ON DELETE SET NULL
DO $$
BEGIN
  ALTER TABLE public.bookings
    ADD CONSTRAINT bookings_guest_profile_id_fkey FOREIGN KEY (guest_profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT bookings_discount_applied_by_fkey FOREIGN KEY (discount_applied_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT bookings_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.booking_charges
    ADD CONSTRAINT booking_charges_added_by_fkey FOREIGN KEY (added_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.stock_transactions
    ADD CONSTRAINT stock_transactions_staff_profile_id_fkey FOREIGN KEY (staff_profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.direct_supply_requests
    ADD CONSTRAINT direct_supply_requests_requested_by_fkey FOREIGN KEY (requested_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT direct_supply_requests_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.stock_transfers
    ADD CONSTRAINT stock_transfers_issued_by_id_fkey FOREIGN KEY (issued_by_id) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT stock_transfers_received_by_id_fkey FOREIGN KEY (received_by_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.department_transfers
    ADD CONSTRAINT department_transfers_dispatched_by_id_fkey FOREIGN KEY (dispatched_by_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.purchase_orders
    ADD CONSTRAINT purchase_orders_purchaser_id_fkey FOREIGN KEY (purchaser_id) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT purchase_orders_storekeeper_id_fkey FOREIGN KEY (storekeeper_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.purchase_budgets
    ADD CONSTRAINT purchase_budgets_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT purchase_budgets_updated_by_fkey FOREIGN KEY (updated_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.expenses
    ADD CONSTRAINT expenses_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT expenses_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT expenses_rejected_by_fkey FOREIGN KEY (rejected_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.income_records
    ADD CONSTRAINT income_records_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT income_records_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.payroll_records
    ADD CONSTRAINT payroll_records_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT payroll_records_approved_by_fkey FOREIGN KEY (approved_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT payroll_records_processed_by_fkey FOREIGN KEY (processed_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.debts
    ADD CONSTRAINT debts_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT debts_sold_by_fkey FOREIGN KEY (sold_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.debt_payments
    ADD CONSTRAINT debt_payments_collected_by_fkey FOREIGN KEY (collected_by) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT debt_payments_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.mini_mart_sales
    ADD CONSTRAINT mini_mart_sales_sold_by_fkey FOREIGN KEY (sold_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.kitchen_sales
    ADD CONSTRAINT kitchen_sales_sold_by_fkey FOREIGN KEY (sold_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.positions
    ADD CONSTRAINT positions_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.attendance_records
    ADD CONSTRAINT attendance_records_profile_id_fkey FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.posts
    ADD CONSTRAINT posts_author_profile_id_fkey FOREIGN KEY (author_profile_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.notifications
    ADD CONSTRAINT notifications_user_id_fkey FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.staff_role_assignments
    ADD CONSTRAINT staff_role_assignments_staff_id_fkey FOREIGN KEY (staff_id) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT staff_role_assignments_assigned_by_fkey FOREIGN KEY (assigned_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.maintenance_work_orders
    ADD CONSTRAINT maintenance_work_orders_reported_by_id_fkey FOREIGN KEY (reported_by_id) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT maintenance_work_orders_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(id) ON DELETE SET NULL;
  ALTER TABLE public.work_orders
    ADD CONSTRAINT work_orders_assigned_to_fkey FOREIGN KEY (assigned_to) REFERENCES public.profiles(id) ON DELETE SET NULL,
    ADD CONSTRAINT work_orders_created_by_fkey FOREIGN KEY (created_by) REFERENCES public.profiles(id) ON DELETE SET NULL;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;
-- 4.1) Bookings columns and guest_profile_id nullable
DO $$
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'payment_reference'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN payment_reference TEXT;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'payment_provider'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN payment_provider TEXT;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'payment_verified'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN payment_verified BOOLEAN DEFAULT false;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'terms_accepted'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN terms_accepted BOOLEAN DEFAULT false;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'terms_version'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN terms_version TEXT;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'payment_method'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN payment_method TEXT DEFAULT 'cash';
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'guest_name'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN guest_name TEXT;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'guest_email'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN guest_email TEXT;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'guest_phone'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN guest_phone TEXT;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'discount_applied'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN discount_applied BOOLEAN DEFAULT false;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'discount_amount'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN discount_amount INT8 DEFAULT 0;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'discount_percentage'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN discount_percentage NUMERIC(5,2) DEFAULT 0;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'discount_reason'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN discount_reason TEXT;
  END IF;

  IF NOT EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'discount_applied_by'
  ) THEN
      ALTER TABLE public.bookings ADD COLUMN discount_applied_by UUID REFERENCES public.profiles(id);
  END IF;

  IF EXISTS (
      SELECT 1 FROM information_schema.columns 
      WHERE table_schema = 'public' 
      AND table_name = 'bookings' 
      AND column_name = 'guest_profile_id'
      AND is_nullable = 'NO'
  ) THEN
      ALTER TABLE public.bookings ALTER COLUMN guest_profile_id DROP NOT NULL;
  END IF;
END $$;

-- Rooms UPDATE policy for staff (housekeeping + reception + management)
DO $$
BEGIN
  BEGIN
    DROP POLICY IF EXISTS "Staff update rooms" ON public.rooms;
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;

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
END $$;

-- Room status audit log
DO $$
BEGIN
  IF NOT EXISTS (
      SELECT 1 FROM information_schema.tables
      WHERE table_schema = 'public'
      AND table_name = 'room_status_logs'
  ) THEN
      CREATE TABLE public.room_status_logs (
          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
          room_id UUID NOT NULL REFERENCES public.rooms(id) ON DELETE CASCADE,
          old_status TEXT,
          new_status TEXT,
          changed_by UUID REFERENCES public.profiles(id),
          changed_at TIMESTAMPTZ DEFAULT now()
      );
  END IF;
END $$;

ALTER TABLE public.room_status_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  BEGIN
    DROP POLICY IF EXISTS "Staff read room status logs" ON public.room_status_logs;
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;

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
END $$;

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

DO $$
BEGIN
  BEGIN
    DROP TRIGGER IF EXISTS room_status_change_log ON public.rooms;
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;
  CREATE TRIGGER room_status_change_log
  AFTER UPDATE ON public.rooms
  FOR EACH ROW
  EXECUTE FUNCTION public.log_room_status_change();
END $$;

-- Add priority column to rooms table if it doesn't exist
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'rooms'
    AND column_name = 'priority'
  ) THEN
    ALTER TABLE public.rooms
    ADD COLUMN priority TEXT DEFAULT 'Low' CHECK (priority IN ('Low', 'Medium', 'High', 'Urgent'));
    
    -- Set initial priority based on status
    UPDATE public.rooms
    SET priority = CASE
      WHEN status = 'Dirty' THEN 'High'
      WHEN status = 'Cleaning' THEN 'Medium'
      WHEN status = 'Maintenance' THEN 'High'
      ELSE 'Low'
    END;
  END IF;
END $$;

-- Update assign_room_to_booking to automatically set status to Checked-in
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
    
    -- Assign room and automatically set status to Checked-in
    UPDATE public.bookings
    SET room_id = assign_room_to_booking.room_id,
        status = 'Checked-in',
        updated_at = now()
    WHERE id = booking_id;
    
    -- Update room status to Occupied
    UPDATE public.rooms
    SET status = 'Occupied',
        updated_at = now()
    WHERE id = assign_room_to_booking.room_id;
    
    RETURN TRUE;
END;
$$;

-- Function to automatically update expired bookings to Checked-out
-- A booking expires at 12:00 PM on the check-out date
CREATE OR REPLACE FUNCTION public.auto_update_expired_bookings()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_now TIMESTAMPTZ;
    v_expired_count INT;
BEGIN
    v_now := now();
    
    -- Update bookings where check-out date has passed 12:00 PM
    -- and status is still 'Checked-in' or 'Pending Check-in'
    UPDATE public.bookings
    SET status = 'Checked-out',
        updated_at = v_now
    WHERE status IN ('Checked-in', 'Pending Check-in')
      AND check_out_date IS NOT NULL
      AND (
          -- Check if current time is past 12:00 PM on check-out date
          v_now > (
              DATE(check_out_date) + INTERVAL '12 hours'
          )
      );
    
    GET DIAGNOSTICS v_expired_count = ROW_COUNT;
    
    -- Update room status to Dirty for rooms that were occupied by expired bookings
    UPDATE public.rooms
    SET status = 'Dirty',
        updated_at = v_now
    WHERE id IN (
        SELECT room_id
        FROM public.bookings
        WHERE status = 'Checked-out'
          AND check_out_date IS NOT NULL
          AND v_now > (DATE(check_out_date) + INTERVAL '12 hours')
          AND room_id IS NOT NULL
    )
    AND status = 'Occupied';
END;
$$;

-- Trigger to automatically check and update expired bookings on UPDATE
-- This ensures status is always accurate when bookings are accessed
CREATE OR REPLACE FUNCTION public.ensure_booking_status_accuracy()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    v_check_out_expiry TIMESTAMPTZ;
BEGIN
    -- Only process if check_out_date exists
    IF NEW.check_out_date IS NOT NULL THEN
        -- Calculate expiry time (12:00 PM on check-out date)
        v_check_out_expiry := DATE(NEW.check_out_date) + INTERVAL '12 hours';
        
        -- If current time is past expiry and booking is still active, mark as Checked-out
        IF now() > v_check_out_expiry AND NEW.status IN ('Checked-in', 'Pending Check-in') THEN
            NEW.status := 'Checked-out';
            NEW.updated_at := now();
            
            -- Also update room status if room is assigned
            IF NEW.room_id IS NOT NULL THEN
                UPDATE public.rooms
                SET status = 'Dirty',
                    updated_at = now()
                WHERE id = NEW.room_id
                  AND status = 'Occupied';
            END IF;
        END IF;
    END IF;
    
    RETURN NEW;
END;
$$;

-- Create trigger to ensure booking status accuracy on UPDATE
DO $$
BEGIN
  BEGIN
    DROP TRIGGER IF EXISTS trg_ensure_booking_status_accuracy ON public.bookings;
  EXCEPTION WHEN undefined_object THEN
    NULL;
  END;
  
  CREATE TRIGGER trg_ensure_booking_status_accuracy
  BEFORE UPDATE ON public.bookings
  FOR EACH ROW
  EXECUTE FUNCTION public.ensure_booking_status_accuracy();
END $$;

-- Schedule automatic update of expired bookings (runs every hour)
DO $$
BEGIN
  PERFORM cron.schedule(
    'auto_update_expired_bookings',
    '0 * * * *', -- Every hour at minute 0
    'SELECT public.auto_update_expired_bookings()'
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL; -- pg_cron might not be available, ignore
END $$;

-- 5) Stock transfers + function
CREATE TABLE IF NOT EXISTS public.stock_transfers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    stock_item_id UUID REFERENCES public.stock_items(id) NOT NULL,
    source_location_id UUID REFERENCES public.locations(id) NOT NULL,
    destination_location_id UUID REFERENCES public.locations(id) NOT NULL,
    quantity INT NOT NULL CHECK (quantity > 0),
    issued_by_id UUID REFERENCES public.profiles(id) NOT NULL,
    received_by_id UUID REFERENCES public.profiles(id) NOT NULL,
    notes TEXT,
    status TEXT DEFAULT 'Confirmed' CHECK (status IN ('Pending', 'Confirmed', 'Cancelled'))
);

ALTER TABLE public.stock_transfers ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Active staff view stock transfers" ON public.stock_transfers;
CREATE POLICY "Active staff view stock transfers" ON public.stock_transfers FOR SELECT USING (
  is_user_active(auth.uid())
);

DROP POLICY IF EXISTS "Storekeeper can create stock transfers" ON public.stock_transfers;
CREATE POLICY "Storekeeper can create stock transfers" ON public.stock_transfers FOR INSERT WITH CHECK (
  is_user_active(auth.uid())
  AND (user_has_role(auth.uid(), 'storekeeper') OR user_has_role(auth.uid(), 'manager') OR user_has_role(auth.uid(), 'owner'))
);

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

-- 6) Stock transaction insert policy (sales roles)
DO $$
BEGIN
  DROP POLICY IF EXISTS "Active staff can insert stock transactions" ON public.stock_transactions;
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
        ('vip_bartender' = ANY(p.roles) AND location_id IN (SELECT id FROM public.locations WHERE name IN ('VIP Bar', 'Kitchen'))) OR
        ('outside_bartender' = ANY(p.roles) AND location_id IN (SELECT id FROM public.locations WHERE name = 'Outside Bar')) OR
        ('kitchen_staff' = ANY(p.roles) AND location_id IN (SELECT id FROM public.locations WHERE name = 'Kitchen')) OR
        ('receptionist' = ANY(p.roles) AND location_id IN (SELECT id FROM public.locations WHERE name IN ('Mini Mart', 'Kitchen')))
      )
      AND (
        transaction_type <> 'Direct_Supply'
        OR user_has_role(auth.uid(), 'owner')
        OR user_has_role(auth.uid(), 'manager')
        OR user_has_role(auth.uid(), 'storekeeper')
      )
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;
-- 6h) Direct supply requests (bartender -> management approval)
DO $$
BEGIN
  CREATE TABLE IF NOT EXISTS public.direct_supply_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    stock_item_id UUID REFERENCES public.stock_items(id) NOT NULL,
    bar TEXT NOT NULL,
    quantity INT NOT NULL,
    requested_by UUID REFERENCES public.profiles(id) NOT NULL,
    status TEXT DEFAULT 'pending',
    approved_by UUID REFERENCES public.profiles(id),
    approved_at TIMESTAMPTZ,
    notes TEXT
  );

  ALTER TABLE public.direct_supply_requests ENABLE ROW LEVEL SECURITY;

  ALTER TABLE public.direct_supply_requests
    ADD CONSTRAINT direct_supply_requests_bar_check
    CHECK (bar IN ('vip_bar', 'outside_bar'));
  ALTER TABLE public.direct_supply_requests
    ADD CONSTRAINT direct_supply_requests_quantity_check
    CHECK (quantity > 0);
  ALTER TABLE public.direct_supply_requests
    ADD CONSTRAINT direct_supply_requests_status_check
    CHECK (status IN ('pending', 'approved', 'denied'));

  DROP POLICY IF EXISTS "Direct supply requests view" ON public.direct_supply_requests;
  DROP POLICY IF EXISTS "Direct supply requests insert" ON public.direct_supply_requests;
  DROP POLICY IF EXISTS "Direct supply requests update" ON public.direct_supply_requests;

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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

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
-- Announcement notifications
CREATE OR REPLACE FUNCTION public.notify_on_announcement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  IF NEW.is_announcement IS TRUE THEN
    INSERT INTO public.notifications (user_id, title, message, type, data)
    SELECT p.id,
           NEW.title,
           NEW.content,
           'info',
           jsonb_build_object('post_id', NEW.id)
    FROM public.profiles p
    WHERE p.status = 'Active';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_notify_on_announcement ON public.posts;
CREATE TRIGGER trg_notify_on_announcement
AFTER INSERT ON public.posts
FOR EACH ROW EXECUTE FUNCTION public.notify_on_announcement();

-- 6b) Stock transaction view policy (location-restricted)
DO $$
BEGIN
  DROP POLICY IF EXISTS "Active staff view stock" ON public.stock_transactions;
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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 6c) Stock items & inventory items policies (management + department visibility)
DO $$
BEGIN
  DROP POLICY IF EXISTS "Allow read access" ON public.stock_items;
  DROP POLICY IF EXISTS "Allow read access" ON public.inventory_items;
  DROP POLICY IF EXISTS "Active staff view stock items" ON public.stock_items;
  DROP POLICY IF EXISTS "Management can manage stock items" ON public.stock_items;
  DROP POLICY IF EXISTS "Purchaser can create stock items" ON public.stock_items;
  DROP POLICY IF EXISTS "Bar staff view inventory items" ON public.inventory_items;
  DROP POLICY IF EXISTS "Management can manage inventory items" ON public.inventory_items;

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

  CREATE POLICY "Management can manage stock items" ON public.stock_items FOR ALL USING (
    is_user_active(auth.uid())
    AND (user_has_role(auth.uid(), 'owner') OR user_has_role(auth.uid(), 'manager'))
  );
  CREATE POLICY "Purchaser can create stock items" ON public.stock_items FOR INSERT WITH CHECK (
    is_user_active(auth.uid())
    AND user_has_role(auth.uid(), 'purchaser')
  );

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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 6b) Department transfers add payment/booking fields
DO $$
BEGIN
  ALTER TABLE public.department_transfers
    ADD COLUMN IF NOT EXISTS unit_price INT8 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS total_amount INT8 DEFAULT 0,
    ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'cash',
    ADD COLUMN IF NOT EXISTS payment_status TEXT DEFAULT 'paid',
    ADD COLUMN IF NOT EXISTS booking_id UUID REFERENCES public.bookings(id),
    ADD COLUMN IF NOT EXISTS notes TEXT;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 6c) Debts traceability fields
DO $$
BEGIN
  ALTER TABLE public.debts
    ADD COLUMN IF NOT EXISTS source_department TEXT,
    ADD COLUMN IF NOT EXISTS source_type TEXT,
    ADD COLUMN IF NOT EXISTS reference_id UUID;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 6d) Booking charges policies
DO $$
BEGIN
  ALTER TABLE public.booking_charges ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Active staff view booking charges" ON public.booking_charges;
  DROP POLICY IF EXISTS "Staff can insert booking charges" ON public.booking_charges;
  DROP POLICY IF EXISTS "Management can update booking charges" ON public.booking_charges;

  CREATE POLICY "Active staff view booking charges" ON public.booking_charges FOR SELECT
  USING (is_user_active(auth.uid()));

  CREATE POLICY "Staff can insert booking charges" ON public.booking_charges FOR INSERT
  WITH CHECK (
    is_user_active(auth.uid())
    AND added_by = auth.uid()
    AND (
      user_has_role(auth.uid(), 'receptionist')
      OR user_has_role(auth.uid(), 'kitchen_staff')
      OR user_has_role(auth.uid(), 'vip_bartender')
      OR user_has_role(auth.uid(), 'manager')
      OR user_has_role(auth.uid(), 'owner')
    )
  );

  CREATE POLICY "Management can update booking charges" ON public.booking_charges FOR UPDATE
  USING (
    is_user_active(auth.uid())
    AND (user_has_role(auth.uid(), 'manager') OR user_has_role(auth.uid(), 'owner'))
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 6e) Debt payment trigger for revenue recognition
DO $$
BEGIN
  CREATE OR REPLACE FUNCTION public.handle_debt_payment()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  AS $func$
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
  $func$;

  DROP TRIGGER IF EXISTS handle_debt_payment_trigger ON public.debt_payments;
  CREATE TRIGGER handle_debt_payment_trigger
  AFTER INSERT ON public.debt_payments
  FOR EACH ROW EXECUTE FUNCTION public.handle_debt_payment();
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;


-- 6g.1) Direct supply transaction type note (no schema change)

-- 7) Department sales policy (VIP/Outside roles)
DO $$
BEGIN
  DROP POLICY IF EXISTS "Department staff access sales" ON public.department_sales;
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
        (department = 'restaurant' AND ('kitchen_staff' = ANY(p.roles) OR 'vip_bartender' = ANY(p.roles))) OR
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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 7b) Department sales insert/update for department staff
DO $$
BEGIN
  DROP POLICY IF EXISTS "Department staff can insert sales" ON public.department_sales;
  DROP POLICY IF EXISTS "Department staff can update sales" ON public.department_sales;

  CREATE POLICY "Department staff can insert sales" ON public.department_sales FOR INSERT WITH CHECK (
    is_user_active(auth.uid())
    AND (
      user_has_role(auth.uid(), 'manager')
      OR user_has_role(auth.uid(), 'owner')
      OR user_has_role(auth.uid(), 'accountant')
      OR (department = 'restaurant' AND (user_has_role(auth.uid(), 'kitchen_staff') OR user_has_role(auth.uid(), 'receptionist') OR user_has_role(auth.uid(), 'vip_bartender')))
      OR (department = 'vip_bar' AND user_has_role(auth.uid(), 'vip_bartender'))
      OR (department = 'outside_bar' AND user_has_role(auth.uid(), 'outside_bartender'))
      OR (department = 'mini_mart' AND user_has_role(auth.uid(), 'receptionist'))
      OR (department = 'reception' AND user_has_role(auth.uid(), 'receptionist'))
      OR (department = 'laundry' AND user_has_role(auth.uid(), 'laundry_attendant'))
      OR (department = 'storekeeping' AND user_has_role(auth.uid(), 'storekeeper'))
      OR (department = 'purchasing' AND user_has_role(auth.uid(), 'purchaser'))
      OR (
        (user_has_role(auth.uid(), 'kitchen_staff') OR user_has_role(auth.uid(), 'receptionist') OR user_has_role(auth.uid(), 'vip_bartender'))
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
      OR (department = 'restaurant' AND (user_has_role(auth.uid(), 'kitchen_staff') OR user_has_role(auth.uid(), 'receptionist') OR user_has_role(auth.uid(), 'vip_bartender')))
      OR (department = 'vip_bar' AND user_has_role(auth.uid(), 'vip_bartender'))
      OR (department = 'outside_bar' AND user_has_role(auth.uid(), 'outside_bartender'))
      OR (department = 'mini_mart' AND user_has_role(auth.uid(), 'receptionist'))
      OR (department = 'reception' AND user_has_role(auth.uid(), 'receptionist'))
      OR (department = 'laundry' AND user_has_role(auth.uid(), 'laundry_attendant'))
      OR (department = 'storekeeping' AND user_has_role(auth.uid(), 'storekeeper'))
      OR (department = 'purchasing' AND user_has_role(auth.uid(), 'purchaser'))
      OR (
        (user_has_role(auth.uid(), 'kitchen_staff') OR user_has_role(auth.uid(), 'receptionist') OR user_has_role(auth.uid(), 'vip_bartender'))
        AND department IN ('vip_bar', 'outside_bar', 'mini_mart', 'reception', 'restaurant')
      )
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 7c) Kitchen sales table + policies
DO $$
BEGIN
  CREATE TABLE IF NOT EXISTS public.kitchen_sales (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    menu_item_id UUID REFERENCES public.menu_items(id),
    item_name TEXT,
    quantity INTEGER NOT NULL DEFAULT 1,
    unit_price INT8 NOT NULL,
    total_amount INT8 NOT NULL,
    payment_method TEXT DEFAULT 'cash',
    booking_id UUID REFERENCES public.bookings(id),
    sold_by UUID REFERENCES public.profiles(id) NOT NULL,
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT now()
  );

  ALTER TABLE public.kitchen_sales ENABLE ROW LEVEL SECURITY;

  DROP POLICY IF EXISTS "Kitchen staff access kitchen sales" ON public.kitchen_sales;
  DROP POLICY IF EXISTS "Kitchen staff can insert kitchen sales" ON public.kitchen_sales;
  DROP POLICY IF EXISTS "Management can update kitchen sales" ON public.kitchen_sales;

  CREATE POLICY "Kitchen staff access kitchen sales" ON public.kitchen_sales FOR SELECT
  USING (
    is_user_active(auth.uid())
    AND (
      user_has_role(auth.uid(), 'kitchen_staff')
      OR user_has_role(auth.uid(), 'receptionist')
      OR user_has_role(auth.uid(), 'vip_bartender') -- VIP bartenders can assist with kitchen sales
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
      OR user_has_role(auth.uid(), 'vip_bartender') -- VIP bartenders can assist with kitchen sales
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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;


-- 8.5) Purchase orders policies + confirm function
DO $$
BEGIN
  DROP POLICY IF EXISTS "Purchaser can create purchase orders" ON public.purchase_orders;
  DROP POLICY IF EXISTS "Purchaser/storekeeper can view purchase orders" ON public.purchase_orders;
  DROP POLICY IF EXISTS "Storekeeper can update purchase orders" ON public.purchase_orders;
  DROP POLICY IF EXISTS "Purchaser can add purchase order items" ON public.purchase_order_items;
  DROP POLICY IF EXISTS "Purchaser/storekeeper can view purchase order items" ON public.purchase_order_items;

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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 8.5.1) Purchase budgets (monthly)
-- 8.5) Suppliers (Purchasing)
CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name TEXT UNIQUE NOT NULL,
    description TEXT,
    contact_phone TEXT,
    contact_email TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
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
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Purchaser can add suppliers" ON public.suppliers FOR INSERT WITH CHECK (
    is_user_active(auth.uid())
    AND (
      user_has_role(auth.uid(), 'purchaser')
      OR user_has_role(auth.uid(), 'manager')
      OR user_has_role(auth.uid(), 'owner')
      OR user_has_role(auth.uid(), 'accountant')
    )
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Management can manage suppliers" ON public.suppliers FOR ALL USING (
    is_user_active(auth.uid())
    AND (
      user_has_role(auth.uid(), 'manager')
      OR user_has_role(auth.uid(), 'owner')
      OR user_has_role(auth.uid(), 'accountant')
    )
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE public.stock_items ADD COLUMN IF NOT EXISTS category TEXT;
ALTER TABLE public.stock_items ADD COLUMN IF NOT EXISTS preferred_supplier_id UUID REFERENCES public.suppliers(id);
ALTER TABLE public.stock_items ADD COLUMN IF NOT EXISTS preferred_supplier_name TEXT;

-- 8.5.1) Purchase budgets (monthly)
CREATE TABLE IF NOT EXISTS public.purchase_budgets (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    month_start DATE NOT NULL UNIQUE,
    amount INT8 NOT NULL, -- Stored in Kobo/Cents
    created_by UUID REFERENCES public.profiles(id),
    updated_by UUID REFERENCES public.profiles(id),
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Finance approvals and audit logs
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS payment_method TEXT DEFAULT 'cash';
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES public.profiles(id);
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS rejected_by UUID REFERENCES public.profiles(id);
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS rejected_at TIMESTAMPTZ;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS rejection_reason TEXT;
ALTER TABLE public.expenses ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT now();

ALTER TABLE public.payroll_records ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'pending';
ALTER TABLE public.payroll_records ADD COLUMN IF NOT EXISTS approved_by UUID REFERENCES public.profiles(id);
ALTER TABLE public.payroll_records ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;
ALTER TABLE public.payroll_records ADD COLUMN IF NOT EXISTS rejection_reason TEXT;

ALTER TABLE public.debts ADD COLUMN IF NOT EXISTS due_date DATE;

CREATE TABLE IF NOT EXISTS public.finance_audit_logs (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    created_at TIMESTAMPTZ DEFAULT now(),
    actor_id UUID REFERENCES public.profiles(id),
    action TEXT NOT NULL,
    table_name TEXT NOT NULL,
    record_id UUID,
    before_data JSONB,
    after_data JSONB
);

ALTER TABLE public.finance_audit_logs ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "Active admin finance access audit logs" ON public.finance_audit_logs FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.status = 'Active'
      AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
    )
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

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

-- Create debt_payments table if it doesn't exist
DO $$
BEGIN
  CREATE TABLE IF NOT EXISTS public.debt_payments (
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

  -- RLS Policies for debt_payments
  DROP POLICY IF EXISTS "Active admin finance access debt payments" ON public.debt_payments;
  CREATE POLICY "Active admin finance access debt payments" ON public.debt_payments FOR ALL 
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.status = 'Active'
      AND (p.roles && ARRAY['manager', 'owner', 'accountant'])
    )
  );

  DROP POLICY IF EXISTS "Staff can record payments for own debts" ON public.debt_payments;
  CREATE POLICY "Staff can record payments for own debts" ON public.debt_payments FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      INNER JOIN public.debts d ON d.id = debt_payments.debt_id
      WHERE p.id = auth.uid()
      AND p.status = 'Active'
      AND (
        d.sold_by = auth.uid()
        OR (p.roles && ARRAY['manager', 'owner', 'accountant'])
        OR (
          COALESCE(d.source_department, d.department) = 'restaurant'
          AND ('kitchen_staff' = ANY(p.roles) OR 'vip_bartender' = ANY(p.roles) OR 'receptionist' = ANY(p.roles))
        )
      )
    )
  );

  DROP POLICY IF EXISTS "Accountant can record payments" ON public.debt_payments;
  CREATE POLICY "Accountant can record payments" ON public.debt_payments FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
      AND p.status = 'Active'
      AND ('accountant' = ANY(p.roles) OR 'manager' = ANY(p.roles) OR 'owner' = ANY(p.roles))
    )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

DROP TRIGGER IF EXISTS trg_finance_audit_debt_payments ON public.debt_payments;
CREATE TRIGGER trg_finance_audit_debt_payments
AFTER INSERT OR UPDATE OR DELETE ON public.debt_payments
FOR EACH ROW EXECUTE FUNCTION public.log_finance_change();

-- debt_payment_claims: staff record collections; management approves to move into debt_payments
CREATE TABLE IF NOT EXISTS public.debt_payment_claims (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  created_at TIMESTAMPTZ DEFAULT now(),
  debt_id UUID REFERENCES public.debts(id) ON DELETE CASCADE NOT NULL,
  amount INT8 NOT NULL,
  payment_method TEXT NOT NULL CHECK (payment_method IN ('cash', 'transfer', 'card', 'other')),
  payment_date DATE DEFAULT CURRENT_DATE NOT NULL,
  recorded_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL NOT NULL,
  notes TEXT,
  status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
  approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
  approved_at TIMESTAMPTZ,
  rejected_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT now()
);

ALTER TABLE public.debt_payment_claims ENABLE ROW LEVEL SECURITY;

-- Management: full access
DROP POLICY IF EXISTS "Management access debt payment claims" ON public.debt_payment_claims;
CREATE POLICY "Management access debt payment claims" ON public.debt_payment_claims FOR ALL
USING (
  EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.status = 'Active'
    AND (p.roles && ARRAY['owner', 'manager', 'accountant'])
  )
);

-- Staff: INSERT for debts where source_department matches their role
DROP POLICY IF EXISTS "Staff can insert debt payment claims for department" ON public.debt_payment_claims;
CREATE POLICY "Staff can insert debt payment claims for department" ON public.debt_payment_claims FOR INSERT
WITH CHECK (
  EXISTS (
    SELECT 1 FROM public.profiles p
    INNER JOIN public.debts d ON d.id = debt_id
    WHERE p.id = auth.uid() AND p.status = 'Active'
    AND recorded_by = auth.uid()
    AND (
      (COALESCE(d.source_department, d.department) = 'reception' AND 'receptionist' = ANY(p.roles))
      OR (COALESCE(d.source_department, d.department) = 'mini_mart' AND 'receptionist' = ANY(p.roles))
      OR (COALESCE(d.source_department, d.department) = 'restaurant' AND ('kitchen_staff' = ANY(p.roles) OR 'vip_bartender' = ANY(p.roles) OR 'receptionist' = ANY(p.roles)))
      OR (COALESCE(d.source_department, d.department) = 'vip_bar' AND 'vip_bartender' = ANY(p.roles))
      OR (COALESCE(d.source_department, d.department) = 'outside_bar' AND 'outside_bartender' = ANY(p.roles))
      OR (COALESCE(d.source_department, d.department) = 'housekeeping' AND ('housekeeper' = ANY(p.roles) OR 'cleaner' = ANY(p.roles)))
      OR (COALESCE(d.source_department, d.department) = 'laundry' AND 'laundry_attendant' = ANY(p.roles))
    )
  )
);

-- Staff: SELECT own claims
DROP POLICY IF EXISTS "Staff can view own debt payment claims" ON public.debt_payment_claims;
CREATE POLICY "Staff can view own debt payment claims" ON public.debt_payment_claims FOR SELECT
USING (
  recorded_by = auth.uid()
  OR EXISTS (
    SELECT 1 FROM public.profiles p
    WHERE p.id = auth.uid() AND p.status = 'Active'
    AND (p.roles && ARRAY['owner', 'manager', 'accountant'])
  )
);

DROP TRIGGER IF EXISTS trg_debt_payment_claims_updated ON public.debt_payment_claims;
CREATE TRIGGER trg_debt_payment_claims_updated
BEFORE UPDATE ON public.debt_payment_claims
FOR EACH ROW EXECUTE FUNCTION public.update_updated_at_column();

ALTER TABLE public.purchase_budgets ENABLE ROW LEVEL SECURITY;

DO $$ BEGIN
  CREATE POLICY "Management can manage purchase budgets" ON public.purchase_budgets FOR ALL USING (
    is_user_active(auth.uid())
    AND (
      user_has_role(auth.uid(), 'owner')
      OR user_has_role(auth.uid(), 'manager')
      OR user_has_role(auth.uid(), 'accountant')
    )
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

DO $$ BEGIN
  CREATE POLICY "Purchaser can view purchase budgets" ON public.purchase_budgets FOR SELECT USING (
    is_user_active(auth.uid())
    AND (
      user_has_role(auth.uid(), 'purchaser')
      OR user_has_role(auth.uid(), 'owner')
      OR user_has_role(auth.uid(), 'manager')
      OR user_has_role(auth.uid(), 'accountant')
    )
  );
EXCEPTION
  WHEN duplicate_object THEN NULL;
END $$;

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

-- 8.6) Stock level calculation updated for adjustments
CREATE OR REPLACE FUNCTION public.calculate_stock_level(item_id UUID, location_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
AS $calc$
DECLARE
    total_in INTEGER;
    total_out INTEGER;
BEGIN
    SELECT COALESCE(SUM(quantity), 0) INTO total_in
    FROM public.stock_transactions 
    WHERE stock_transactions.stock_item_id = calculate_stock_level.item_id 
    AND stock_transactions.location_id = calculate_stock_level.location_id
    AND transaction_type IN ('Purchase', 'Transfer_In', 'Adjustment')
    AND quantity > 0;
    
    SELECT COALESCE(SUM(ABS(quantity)), 0) INTO total_out
    FROM public.stock_transactions 
    WHERE stock_transactions.stock_item_id = calculate_stock_level.item_id 
    AND stock_transactions.location_id = calculate_stock_level.location_id
    AND transaction_type IN ('Sale', 'Transfer_Out', 'Wastage', 'Adjustment')
    AND quantity < 0;
    
    RETURN total_in - total_out;
  END;
$calc$;

-- 9) Views (refresh)
DROP VIEW IF EXISTS public.room_occupancy CASCADE;
DROP VIEW IF EXISTS public.bookings_needing_room_assignment CASCADE;
DROP VIEW IF EXISTS public.daily_sales CASCADE;
DROP VIEW IF EXISTS public.stock_levels CASCADE;

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

CREATE VIEW public.daily_sales AS
SELECT 
    DATE(created_at) as sale_date,
    COUNT(*) as total_bookings,
    SUM(paid_amount) as total_revenue,
    SUM(total_amount) as base_revenue,
    SUM(paid_amount) as paid_revenue
FROM public.bookings
GROUP BY DATE(created_at)
ORDER BY sale_date DESC;

GRANT SELECT ON public.room_occupancy TO anon, authenticated;
GRANT SELECT ON public.bookings_needing_room_assignment TO anon, authenticated;
GRANT SELECT ON public.stock_levels TO anon, authenticated;
GRANT SELECT ON public.daily_sales TO anon, authenticated;

-- Fix attendance_records INSERT policy to allow staff to clock in
DO $$
BEGIN
  DROP POLICY IF EXISTS "Active staff can insert attendance records" ON public.attendance_records;
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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Add UPDATE policy for clock-out functionality
DO $$
BEGIN
  DROP POLICY IF EXISTS "Active staff can update own attendance records" ON public.attendance_records;
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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- ==============================================
-- PENDING STOCK COUNTS SYSTEM
-- Allows departments to submit stock counts for management approval
-- ==============================================

-- Create pending_stock_counts table
CREATE TABLE IF NOT EXISTS public.pending_stock_counts (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    location_id UUID REFERENCES public.locations(id) NOT NULL,
    count_type TEXT NOT NULL, -- 'Opening' or 'Closing'
    count_date DATE NOT NULL DEFAULT CURRENT_DATE,
    submitted_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL NOT NULL,
    submitted_at TIMESTAMPTZ DEFAULT now(),
    status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
    approved_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    approved_at TIMESTAMPTZ,
    rejected_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    rejected_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT now(),
    updated_at TIMESTAMPTZ DEFAULT now()
);

-- Create stock_count_items table (individual items in a count)
CREATE TABLE IF NOT EXISTS public.stock_count_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    stock_count_id UUID REFERENCES public.pending_stock_counts(id) ON DELETE CASCADE NOT NULL,
    stock_item_id UUID REFERENCES public.stock_items(id) NOT NULL,
    counted_quantity INT NOT NULL DEFAULT 0,
    system_quantity INT NOT NULL DEFAULT 0, -- System calculated stock at time of count
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Create stock_count_custom_items table (items not in database yet)
CREATE TABLE IF NOT EXISTS public.stock_count_custom_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    stock_count_id UUID REFERENCES public.pending_stock_counts(id) ON DELETE CASCADE NOT NULL,
    item_name TEXT NOT NULL, -- Name of the item seen but not in database
    quantity INT NOT NULL DEFAULT 0,
    unit TEXT DEFAULT 'units', -- Unit of measurement
    notes TEXT, -- Additional notes about the item
    created_at TIMESTAMPTZ DEFAULT now()
);

-- Enable RLS
ALTER TABLE public.pending_stock_counts ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stock_count_items ENABLE ROW LEVEL SECURITY;

-- RLS Policies for pending_stock_counts
-- All active staff can view pending counts for their locations
DO $$
BEGIN
  DROP POLICY IF EXISTS "Active staff view pending stock counts" ON public.pending_stock_counts;
  CREATE POLICY "Active staff view pending stock counts" ON public.pending_stock_counts FOR SELECT USING (
      is_user_active(auth.uid())
      AND (
          user_has_role(auth.uid(), 'owner')
          OR user_has_role(auth.uid(), 'manager')
          OR user_has_role(auth.uid(), 'supervisor')
          OR user_has_role(auth.uid(), 'storekeeper')
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
                  OR (l.name = 'Store' AND (user_has_role(auth.uid(), 'storekeeper') OR user_has_role(auth.uid(), 'purchaser')))
              )
          )
      )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Staff can submit stock counts (management CANNOT submit - they only review)
DO $$
BEGIN
  DROP POLICY IF EXISTS "Active staff can submit stock counts" ON public.pending_stock_counts;
  CREATE POLICY "Active staff can submit stock counts" ON public.pending_stock_counts FOR INSERT WITH CHECK (
      is_user_active(auth.uid())
      AND submitted_by = auth.uid()
      AND NOT (user_has_role(auth.uid(), 'owner') OR user_has_role(auth.uid(), 'manager') OR user_has_role(auth.uid(), 'supervisor'))
      AND location_id IN (
          SELECT l.id
          FROM public.locations l
          WHERE (
              (l.name = 'VIP Bar' AND user_has_role(auth.uid(), 'vip_bartender'))
              OR (l.name = 'Outside Bar' AND user_has_role(auth.uid(), 'outside_bartender'))
              OR (l.name = 'Kitchen' AND user_has_role(auth.uid(), 'kitchen_staff'))
              OR (l.name = 'Mini Mart' AND user_has_role(auth.uid(), 'receptionist'))
              OR (l.name = 'Housekeeping' AND (user_has_role(auth.uid(), 'housekeeper') OR user_has_role(auth.uid(), 'cleaner')))
              OR (l.name = 'Laundry' AND user_has_role(auth.uid(), 'laundry_attendant'))
              OR (l.name = 'Store' AND (user_has_role(auth.uid(), 'storekeeper') OR user_has_role(auth.uid(), 'purchaser')))
          )
      )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Only management can update (approve/reject) pending counts
DO $$
BEGIN
  DROP POLICY IF EXISTS "Management can approve/reject stock counts" ON public.pending_stock_counts;
  CREATE POLICY "Management can approve/reject stock counts" ON public.pending_stock_counts FOR UPDATE USING (
      is_user_active(auth.uid())
      AND (
          user_has_role(auth.uid(), 'owner')
          OR user_has_role(auth.uid(), 'manager')
          OR user_has_role(auth.uid(), 'supervisor')
          OR user_has_role(auth.uid(), 'storekeeper')
      )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- RLS Policies for stock_count_items
DO $$
BEGIN
  DROP POLICY IF EXISTS "Active staff view stock count items" ON public.stock_count_items;
  CREATE POLICY "Active staff view stock count items" ON public.stock_count_items FOR SELECT USING (
      is_user_active(auth.uid())
      AND EXISTS (
          SELECT 1 FROM public.pending_stock_counts psc
          WHERE psc.id = stock_count_items.stock_count_id
          AND (
              user_has_role(auth.uid(), 'owner')
              OR user_has_role(auth.uid(), 'manager')
              OR user_has_role(auth.uid(), 'supervisor')
              OR user_has_role(auth.uid(), 'storekeeper')
              OR psc.location_id IN (
                  SELECT l.id
                  FROM public.locations l
                  WHERE (
                      (l.name = 'VIP Bar' AND user_has_role(auth.uid(), 'vip_bartender'))
                      OR (l.name = 'Outside Bar' AND user_has_role(auth.uid(), 'outside_bartender'))
                      OR (l.name = 'Kitchen' AND user_has_role(auth.uid(), 'kitchen_staff'))
                      OR (l.name = 'Mini Mart' AND user_has_role(auth.uid(), 'receptionist'))
                      OR (l.name = 'Housekeeping' AND (user_has_role(auth.uid(), 'housekeeper') OR user_has_role(auth.uid(), 'cleaner')))
                      OR (l.name = 'Laundry' AND user_has_role(auth.uid(), 'laundry_attendant'))
                      OR (l.name = 'Store' AND (user_has_role(auth.uid(), 'storekeeper') OR user_has_role(auth.uid(), 'purchaser')))
                  )
              )
          )
      )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

DO $$
BEGIN
  DROP POLICY IF EXISTS "Active staff can insert stock count items" ON public.stock_count_items;
  CREATE POLICY "Active staff can insert stock count items" ON public.stock_count_items FOR INSERT WITH CHECK (
      is_user_active(auth.uid())
      AND EXISTS (
          SELECT 1 FROM public.pending_stock_counts psc
          WHERE psc.id = stock_count_items.stock_count_id
          AND psc.submitted_by = auth.uid()
          AND psc.status = 'pending'
      )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- RLS Policies for stock_count_custom_items
DO $$
BEGIN
  DROP POLICY IF EXISTS "Active staff view custom items" ON public.stock_count_custom_items;
  CREATE POLICY "Active staff view custom items" ON public.stock_count_custom_items FOR SELECT USING (
      is_user_active(auth.uid())
      AND EXISTS (
          SELECT 1 FROM public.pending_stock_counts psc
          WHERE psc.id = stock_count_custom_items.stock_count_id
          AND (
              user_has_role(auth.uid(), 'owner')
              OR user_has_role(auth.uid(), 'manager')
              OR user_has_role(auth.uid(), 'supervisor')
              OR user_has_role(auth.uid(), 'storekeeper')
              OR psc.submitted_by = auth.uid()
          )
      )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

DO $$
BEGIN
  DROP POLICY IF EXISTS "Active staff can insert custom items" ON public.stock_count_custom_items;
  CREATE POLICY "Active staff can insert custom items" ON public.stock_count_custom_items FOR INSERT WITH CHECK (
      is_user_active(auth.uid())
      AND EXISTS (
          SELECT 1 FROM public.pending_stock_counts psc
          WHERE psc.id = stock_count_custom_items.stock_count_id
          AND psc.submitted_by = auth.uid()
          AND psc.status = 'pending'
      )
  );
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- Function to approve a stock count and create adjustment transactions
CREATE OR REPLACE FUNCTION public.approve_stock_count(count_id UUID, approver_id UUID, approval_notes TEXT DEFAULT NULL)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
DECLARE
    count_record RECORD;
    count_item RECORD;
    adjustment_quantity INT;
    location_name TEXT;
    mini_mart_item_id UUID;
BEGIN
    -- Get the pending count record
    SELECT * INTO count_record
    FROM public.pending_stock_counts
    WHERE id = count_id AND status = 'pending';
    
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Stock count not found or already processed';
    END IF;
    
    -- Get location name
    SELECT name INTO location_name
    FROM public.locations
    WHERE id = count_record.location_id;
    
    -- Update the count status to approved
    UPDATE public.pending_stock_counts
    SET status = 'approved',
        approved_by = approver_id,
        approved_at = now(),
        notes = COALESCE(approval_notes, notes),
        updated_at = now()
    WHERE id = count_id;
    
    -- Create adjustment transactions for each item
    FOR count_item IN 
        SELECT * FROM public.stock_count_items WHERE stock_count_id = count_id
    LOOP
        -- Calculate the adjustment needed (counted - system)
        adjustment_quantity := count_item.counted_quantity - count_item.system_quantity;
        
        -- Only process if there's a difference
        IF adjustment_quantity != 0 THEN
            -- For Mini Mart location, also update mini_mart_items.stock_quantity
            IF location_name = 'Mini Mart' THEN
                -- Find corresponding mini_mart_item by matching stock_item name
                SELECT id INTO mini_mart_item_id
                FROM public.mini_mart_items
                WHERE name = (
                    SELECT name FROM public.stock_items WHERE id = count_item.stock_item_id
                )
                LIMIT 1;
                
                IF mini_mart_item_id IS NOT NULL THEN
                    -- Update mini_mart_items.stock_quantity directly
                    UPDATE public.mini_mart_items
                    SET stock_quantity = count_item.counted_quantity,
                        updated_at = now()
                    WHERE id = mini_mart_item_id;
                END IF;
            END IF;
            
            -- Create stock_transaction for ledger-based locations (bars, kitchen, etc.)
            INSERT INTO public.stock_transactions (
                stock_item_id,
                location_id,
                staff_profile_id,
                transaction_type,
                quantity,
                notes
            ) VALUES (
                count_item.stock_item_id,
                count_record.location_id,
                count_record.submitted_by,
                'Adjustment',
                adjustment_quantity,
                format('Daily stock count (%s) - Approved by management', count_record.count_type)
            );
        END IF;
    END LOOP;
END;
$$;

-- Grant execute permission on the function
GRANT EXECUTE ON FUNCTION public.approve_stock_count(UUID, UUID, TEXT) TO authenticated;

-- ==============================================
-- Add stock_item_id column to inventory_items for proper stock tracking
-- ==============================================
DO $$
BEGIN
  -- Add stock_item_id column if it doesn't exist
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_schema = 'public' 
    AND table_name = 'inventory_items' 
    AND column_name = 'stock_item_id'
  ) THEN
    ALTER TABLE public.inventory_items
    ADD COLUMN stock_item_id UUID REFERENCES public.stock_items(id);
    
    -- Create index for better query performance
    CREATE INDEX IF NOT EXISTS idx_inventory_items_stock_item_id 
    ON public.inventory_items(stock_item_id);
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;
