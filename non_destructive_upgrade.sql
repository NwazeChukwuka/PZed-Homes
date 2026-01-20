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
    $$SELECT public.send_management_daily_digest();$$
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

-- 4) Bookings columns and guest_profile_id nullable
DO $$
BEGIN
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

    SELECT id INTO v_inventory_id
    FROM public.inventory_items
    WHERE name = v_item_name
    AND department = v_request.bar;

    IF v_inventory_id IS NULL THEN
        RAISE EXCEPTION 'Inventory item not found for %', v_item_name;
    END IF;

    UPDATE public.inventory_items
    SET current_stock = current_stock + v_request.quantity
    WHERE id = v_inventory_id;

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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 6f) Bartender shifts add bar + stock fields
DO $$
BEGIN
  ALTER TABLE public.bartender_shifts
    ADD COLUMN IF NOT EXISTS bar TEXT,
    ADD COLUMN IF NOT EXISTS opening_stock JSONB DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS transfers JSONB DEFAULT '[]'::jsonb,
    ADD COLUMN IF NOT EXISTS closing_stock JSONB DEFAULT '[]'::jsonb;

  UPDATE public.bartender_shifts
  SET bar = 'vip_bar'
  WHERE bar IS NULL;

  ALTER TABLE public.bartender_shifts
    ALTER COLUMN bar SET DEFAULT 'vip_bar';
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

DO $$
BEGIN
  ALTER TABLE public.bartender_shifts
    ALTER COLUMN bar SET NOT NULL;
  ALTER TABLE public.bartender_shifts
    ADD CONSTRAINT bartender_shifts_bar_check
    CHECK (bar IN ('vip_bar', 'outside_bar'));
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 6g) Stock transactions shift link
DO $$
BEGIN
  ALTER TABLE public.stock_transactions
    ADD COLUMN IF NOT EXISTS shift_id UUID REFERENCES public.bartender_shifts(id);
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
EXCEPTION
  WHEN OTHERS THEN
    NULL;
END $$;

-- 8) Bartender shifts policies (VIP/Outside roles)
DO $$
BEGIN
  DROP POLICY IF EXISTS "Bartenders view own shifts" ON public.bartender_shifts;
  DROP POLICY IF EXISTS "Bartenders can insert shifts" ON public.bartender_shifts;
  DROP POLICY IF EXISTS "Bartenders can update shifts" ON public.bartender_shifts;

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

CREATE OR REPLACE FUNCTION public.confirm_purchase_order(order_id uuid, storekeeper_id uuid)
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = public
AS $$
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

  UPDATE public.purchase_orders
  SET status = 'Confirmed', storekeeper_id = confirm_purchase_order.storekeeper_id
  WHERE id = order_id;
  
  INSERT INTO public.stock_transactions (stock_item_id, location_id, staff_profile_id, transaction_type, quantity, notes)
  SELECT poi.stock_item_id, (SELECT id FROM public.locations WHERE name = 'Main Storeroom' LIMIT 1), storekeeper_id, 'Purchase', poi.quantity, 'PO Confirmed'
  FROM public.purchase_order_items poi WHERE poi.purchase_order_id = order_id;
END;
$$;

-- 8.6) Stock level calculation updated for adjustments
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
$$ LANGUAGE plpgsql;

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
