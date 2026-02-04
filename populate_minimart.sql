-- ==============================================
-- POPULATE MINI MART ITEMS (REAL ITEMS)
-- Prices are stored in Kobo (₦ x 100) via * 100 in inserts
-- Stock uses mini_mart_items.stock_quantity (non-ledger)
-- ==============================================

-- CLEANUP: Delete existing mini-mart items
-- This ensures a fresh start when re-running the populate script
WITH seed_names AS (
  SELECT name FROM (VALUES
    ('Shaving Stick'), ('Toothbrush'), ('Toothpaste'), ('Male Condom'),
    ('SH Plus Type-C Cable'), ('iPhone Cable'), ('Oramo Android Cable'),
    ('Oramo iPhone Cable'), ('Oramo Type-C Cable'), ('USB to USB-C Cable'),
    ('Benco Fast Cable'), ('Oramo Compact 24W Charger'),
    ('iPhone 14 Pro Max Power Adapter'), ('iPhone X USB Power Adapter'),
    ('SH Plus Double Fast Charger'), ('iPhone Charger'),
    ('Intelligent Sleek Fast Charger'), ('Sweet Double Fast Charger'),
    ('Super Charger'), ('Samsung PD Fast Charger'),
    ('iPhone Earphone'), ('Stereo Sound Earphone'), ('Oramo Strong Bass Earphone'),
    ('Chin Chin'), ('Peanut')
  ) AS v(name)
)
DELETE FROM public.mini_mart_items
WHERE name IN (SELECT name FROM seed_names);

WITH data AS (
  SELECT * FROM (VALUES
    -- Toiletries (prices in Naira, will be converted to kobo)
    ('Shaving Stick', 'Shaving stick', 200, 150, 'toiletries', 10, 3, true),
    ('Toothbrush', 'Adult toothbrush', 500, 400, 'toiletries', 10, 3, true),
    ('Toothpaste', 'Toothpaste tube', 1500, 1000, 'toiletries', 10, 3, true),
    ('Male Condom', 'Pack of male condoms', 500, 300, 'toiletries', 10, 3, true),

    -- Phone Accessories (prices in Naira, will be converted to kobo)
    ('SH Plus Type-C Cable', 'SH Plus USB-C cable', 2500, 1800, 'other', 10, 3, true),
    ('iPhone Cable', 'Generic iPhone charging cable', 3000, 2200, 'other', 10, 3, true),
    ('Oramo Android Cable', 'Oramo Android charging cable', 2800, 2000, 'other', 10, 3, true),
    ('Oramo iPhone Cable', 'Oramo iPhone charging cable', 3500, 2600, 'other', 10, 3, true),
    ('Oramo Type-C Cable', 'Oramo USB-C fast cable', 3000, 2200, 'other', 10, 3, true),
    ('USB to USB-C Cable', 'USB to Type-C cable', 2000, 1500, 'other', 10, 3, true),
    ('Benco Fast Cable', 'Benco fast charging cable', 2800, 2000, 'other', 10, 3, true),

    -- Chargers (prices in Naira, will be converted to kobo)
    ('Oramo Compact 24W Charger', 'Oramo 24W Type-C charger', 5500, 4200, 'other', 10, 3, true),
    ('iPhone 14 Pro Max Power Adapter', 'iPhone power adapter', 7500, 6000, 'other', 10, 3, true),
    ('iPhone X USB Power Adapter', 'iPhone X power adapter', 6500, 5000, 'other', 10, 3, true),
    ('SH Plus Double Fast Charger', 'SH Plus dual fast charger', 6000, 4800, 'other', 10, 3, true),
    ('iPhone Charger', 'Generic iPhone charger', 5000, 3800, 'other', 10, 3, true),
    ('Intelligent Sleek Fast Charger', 'Fast charging adapter', 5500, 4200, 'other', 10, 3, true),
    ('Sweet Double Fast Charger', 'Dual fast charger', 5800, 4500, 'other', 10, 3, true),
    ('Super Charger', 'High-speed phone charger', 6000, 4800, 'other', 10, 3, true),
    ('Samsung PD Fast Charger', 'Samsung PD fast charger', 7000, 5500, 'other', 10, 3, true),

    -- Earphones (prices in Naira, will be converted to kobo)
    ('iPhone Earphone', 'iPhone wired earphone', 4500, 3500, 'other', 10, 3, true),
    ('Stereo Sound Earphone', 'Stereo wired earphone', 2500, 1800, 'other', 10, 3, true),
    ('Oramo Strong Bass Earphone', 'Oramo bass earphone', 3500, 2600, 'other', 10, 3, true),

    -- Snacks (prices in Naira, will be converted to kobo)
    ('Chin Chin', 'Pack of chin chin snack', 300, 180, 'snacks', 10, 3, true),
    ('Peanut', 'Roasted peanuts', 250, 150, 'snacks', 10, 3, true)
  ) AS v(name, description, price_naira, cost_price_naira, category, stock_quantity, min_stock_level, is_available)
)
INSERT INTO public.mini_mart_items (
  name,
  description,
  price,
  cost_price,
  category,
  stock_quantity,
  min_stock_level,
  is_available
)
SELECT
  d.name,
  d.description,
  (d.price_naira * 100), -- Convert Naira to Kobo
  (d.cost_price_naira * 100), -- Convert Naira to Kobo
  d.category,
  d.stock_quantity,
  d.min_stock_level,
  d.is_available
FROM data d
WHERE NOT EXISTS (
  SELECT 1 FROM public.mini_mart_items m WHERE m.name = d.name
);

-- Verify
SELECT
  name,
  category,
  price / 100.0 AS price_ngn,
  stock_quantity
FROM public.mini_mart_items
ORDER BY category, name;
