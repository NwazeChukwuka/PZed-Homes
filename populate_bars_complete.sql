-- ==============================================
-- POPULATE BAR ITEMS (VIP + OUTSIDE)
-- Aligned with ledger-based stock (stock_transactions + stock_levels)
-- Prices are stored in Kobo (₦ x 100) via * 100 in inserts
-- ==============================================

-- CLEANUP: Delete existing bar items and related stock transactions
-- This ensures a fresh start when re-running the populate script
WITH seed_names AS (
  SELECT name FROM (VALUES
    ('33 Export'), ('Amstel Malt (Bottle)'), ('Budweiser'), ('Budweiser Royale'),
    ('Desperado (Bottle)'), ('Desperado (Can)'), ('Farouz (Bottle)'), ('Farouz (Can)'),
    ('Gulder'), ('Hero'), ('Guinness Malt (Bottle)'), ('Life Beer'), ('Origin Beer'),
    ('Star Beer'), ('Star Raddler'), ('Tiger'), ('Trophy Beer'), ('Trophy Stout'),
    ('Castle (Lite)'), ('Heineken (Big)'), ('Heineken (Medium)'), ('Stout (Big)'),
    ('Stout (Medium)'), ('Stout (Small)'), ('Amstel Malt (Can)'), ('Guinness Malt (Can)'),
    ('Action Bitter'), ('Black Bullet'), ('Blue Bullet'), ('Campari Medium'),
    ('Campari Small'), ('Climax'), ('De-General'), ('Exotic'), ('Fearless'),
    ('Flying Fish'), ('Green Jameson'), ('Imperial Blue'), ('Jameson Black'),
    ('Legend'), ('Legend (Twist Bottle)'), ('Long Rider'), ('Magic Moment'),
    ('Olmeca Tequila'), ('Origin Bitter'), ('Power Horse'), ('Predator'),
    ('Red Label'), ('Royal Circle'), ('Smirnoff (Big)'), ('Smirnoff Double Black'),
    ('Smirnoff (Small)'), ('Smirnoff Double Black (Small)'), ('William Lawson'),
    ('Gordons (Big)'), ('Gordons (Medium)'), ('Gordons (Small)'), ('Andre'),
    ('Asconi Agor'), ('Blue Train'), ('Carlo Rossi'), ('Four Cousins'),
    ('Red Train'), ('Bottled Water'), ('Mineral (Plastic)'), ('Schweppes'),
    ('Monster'), ('Smirnoff Ice X1'), ('Smirnoff Ice X1 (Big)'), ('Besty Yoghurt'),
    ('Fanny Yoghurt'), ('Hollandia'), ('Nutri-Milk'), ('Nutri-Choco'),
    ('Nutri-Yo'), ('VitaMilk')
  ) AS v(name)
),
bar_items AS (
  SELECT i.id FROM public.inventory_items i
  JOIN seed_names s ON s.name = i.name
  WHERE i.department IN ('vip_bar', 'outside_bar')
)
DELETE FROM public.inventory_items WHERE id IN (SELECT id FROM bar_items);

DELETE FROM public.stock_transactions
WHERE notes = 'Initial stock load (populate_bars_complete)';

-- Note: We keep stock_items as they may be referenced by other tables
-- Only delete stock_items if they're not used elsewhere
WITH seed_names AS (
  SELECT name FROM (VALUES
    ('33 Export'), ('Amstel Malt (Bottle)'), ('Budweiser'), ('Budweiser Royale'),
    ('Desperado (Bottle)'), ('Desperado (Can)'), ('Farouz (Bottle)'), ('Farouz (Can)'),
    ('Gulder'), ('Hero'), ('Guinness Malt (Bottle)'), ('Life Beer'), ('Origin Beer'),
    ('Star Beer'), ('Star Raddler'), ('Tiger'), ('Trophy Beer'), ('Trophy Stout'),
    ('Castle (Lite)'), ('Heineken (Big)'), ('Heineken (Medium)'), ('Stout (Big)'),
    ('Stout (Medium)'), ('Stout (Small)'), ('Amstel Malt (Can)'), ('Guinness Malt (Can)'),
    ('Action Bitter'), ('Black Bullet'), ('Blue Bullet'), ('Campari Medium'),
    ('Campari Small'), ('Climax'), ('De-General'), ('Exotic'), ('Fearless'),
    ('Flying Fish'), ('Green Jameson'), ('Imperial Blue'), ('Jameson Black'),
    ('Legend'), ('Legend (Twist Bottle)'), ('Long Rider'), ('Magic Moment'),
    ('Olmeca Tequila'), ('Origin Bitter'), ('Power Horse'), ('Predator'),
    ('Red Label'), ('Royal Circle'), ('Smirnoff (Big)'), ('Smirnoff Double Black'),
    ('Smirnoff (Small)'), ('Smirnoff Double Black (Small)'), ('William Lawson'),
    ('Gordons (Big)'), ('Gordons (Medium)'), ('Gordons (Small)'), ('Andre'),
    ('Asconi Agor'), ('Blue Train'), ('Carlo Rossi'), ('Four Cousins'),
    ('Red Train'), ('Bottled Water'), ('Mineral (Plastic)'), ('Schweppes'),
    ('Monster'), ('Smirnoff Ice X1'), ('Smirnoff Ice X1 (Big)'), ('Besty Yoghurt'),
    ('Fanny Yoghurt'), ('Hollandia'), ('Nutri-Milk'), ('Nutri-Choco'),
    ('Nutri-Yo'), ('VitaMilk')
  ) AS v(name)
)
DELETE FROM public.stock_items s
USING seed_names n
WHERE s.name = n.name
AND NOT EXISTS (
  SELECT 1 FROM public.menu_items m WHERE m.stock_item_id = s.id
  UNION
  SELECT 1 FROM public.stock_transactions st WHERE st.stock_item_id = s.id
  UNION
  SELECT 1 FROM public.inventory_items i WHERE i.stock_item_id = s.id
);

-- Ensure bar locations exist
INSERT INTO public.locations (name, type, description)
SELECT v.name, v.type, v.description
FROM (VALUES
  ('VIP Bar', 'Bar', 'VIP bar service area'),
  ('Outside Bar', 'Bar', 'Outside bar service area')
) AS v(name, type, description)
WHERE NOT EXISTS (
  SELECT 1 FROM public.locations l WHERE l.name = v.name
);

-- 1) Create stock_items (used by ledger) if missing
WITH data AS (
  SELECT * FROM (VALUES
    -- ==================== BEERS ====================
    ('33 Export', '33 Export beer', 'Beers', 'bottle', 15, 1700, 1300, 20, 20),
    ('Amstel Malt (Bottle)', 'Amstel Malt in bottle', 'Beers', 'bottle', 15, 1200, 900, 20, 20),
    ('Budweiser', 'Budweiser beer', 'Beers', 'bottle', 15, 1800, 1400, 20, 20),
    ('Budweiser Royale', 'Budweiser Royale premium', 'Beers', 'bottle', 15, 2000, 1500, 20, 20),
    ('Desperado (Bottle)', 'Desperado beer in bottle', 'Beers', 'bottle', 15, 1800, 1400, 20, 20),
    ('Desperado (Can)', 'Desperado beer in can', 'Beers', 'can', 15, 1700, 1300, 20, 20),
    ('Farouz (Bottle)', 'Farouz beer in bottle', 'Beers', 'bottle', 15, 1100, 800, 20, 20),
    ('Farouz (Can)', 'Farouz beer in can', 'Beers', 'can', 15, 1000, 800, 20, 20),
    ('Gulder', 'Gulder beer', 'Beers', 'bottle', 15, 1800, 1400, 20, 20),
    ('Hero', 'Hero beer', 'Beers', 'bottle', 15, 1700, 1300, 20, 20),
    ('Guinness Malt (Bottle)', 'Guinness Malt in bottle', 'Beers', 'bottle', 15, 1200, 900, 20, 20),
    ('Life Beer', 'Life Beer', 'Beers', 'bottle', 15, 1700, 1300, 20, 20),
    ('Origin Beer', 'Origin Beer', 'Beers', 'bottle', 15, 1800, 1400, 20, 20),
    ('Star Beer', 'Star Beer', 'Beers', 'bottle', 15, 2000, 1500, 20, 20),
    ('Star Raddler', 'Star Raddler beer', 'Beers', 'bottle', 15, 1600, 1200, 20, 20),
    ('Tiger', 'Tiger beer', 'Beers', 'bottle', 15, 1700, 1300, 20, 20),
    ('Trophy Beer', 'Trophy Beer', 'Beers', 'bottle', 15, 1700, 1300, 20, 20),
    ('Trophy Stout', 'Trophy Stout', 'Beers', 'bottle', 15, 1800, 1400, 20, 20),
    ('Castle (Lite)', 'Castle Lite beer', 'Beers', 'bottle', 15, 1800, 1300, 20, 20),
    ('Heineken (Big)', 'Large Heineken beer', 'Beers', 'bottle', 15, 2000, 1500, 20, 20),
    ('Flying Fish', 'Flying Fish spirit', 'Beers', 'bottle', 15, 1500, 1000, 20, 20),
    ('Heineken (Medium)', 'Medium Heineken beer', 'Beers', 'bottle', 15, 1600, 1200, 20, 20),
    ('Stout (Big)', 'Large Stout', 'Beers', 'bottle', 15, 2100, 1700, 20, 20),
    ('Stout (Medium)', 'Medium Stout', 'Beers', 'bottle', 15, 1800, 1500, 20, 20),
    ('Stout (Small)', 'Small Stout', 'Beers', 'bottle', 15, 1500, 1200, 20, 20),

    -- Outside Bar only (cans)
    ('Amstel Malt (Can)', 'Amstel Malt in can', 'Beers', 'can', 15, NULL, 900, NULL, 20),
    ('Guinness Malt (Can)', 'Guinness Malt in can', 'Beers', 'can', 15, NULL, 900, NULL, 20),

    -- ==================== SPIRITS ====================
    ('Action Bitter', 'Action Bitter', 'Spirits', 'bottle', 15, 2000, 1500, 20, 20),
    ('Black Bullet', 'Black Bullet spirit', 'Spirits', 'bottle', 15, 2500, 2000, 20, 20),
    ('Blue Bullet', 'Blue Bullet spirit', 'Spirits', 'bottle', 15, 2000, 1500, 20, 20),
    ('Campari Medium', 'Medium Campari', 'Spirits', 'bottle', 15, 30000, 27000, 20, 20),
    ('Campari Small', 'Small Campari', 'Spirits', 'bottle', 15, 18000, 16000, 20, 20),
    ('Climax', 'Climax spirit', 'Spirits', 'bottle', 15, 1500, 1000, 20, 20),
    ('De-General', 'De-General spirit', 'Spirits', 'bottle', 15, 2000, 1500, 20, 20),
    ('Exotic', 'Exotic spirit', 'Spirits', 'bottle', 15, 2500, 2000, 20, 20),
    ('Fearless', 'Fearless spirit', 'Spirits', 'bottle', 15, 1500, 1000, 20, 20),
    ('Green Jameson', 'Green Jameson whiskey', 'Spirits', 'bottle', 15, 30000, 30000, 20, 20),
    ('Imperial Blue', 'Imperial Blue whiskey', 'Spirits', 'bottle', 15, 11000, 9000, 20, 20),
    ('Jameson Black', 'Jameson Black whiskey', 'Spirits', 'bottle', 15, 45000, 40000, 20, 20),
    ('Legend', 'Legend spirit', 'Spirits', 'bottle', 15, 2000, 1500, 20, 20),
    ('Legend (Twist Bottle)', 'Legend in twist bottle', 'Spirits', 'bottle', 15, 1500, 1000, 20, 20),
    ('Long Rider', 'Long Rider spirit', 'Spirits', 'bottle', 15, 3000, 2500, 20, 20),
    ('Magic Moment', 'Magic Moment spirit', 'Spirits', 'bottle', 15, 15000, 15000, 20, 20),
    ('Olmeca Tequila', 'Olmeca Tequila', 'Spirits', 'bottle', 15, 30000, 28000, 20, 20),
    ('Origin Bitter', 'Origin Bitter', 'Spirits', 'bottle', 15, 2000, 1500, 20, 20),
    ('Power Horse', 'Power Horse energy drink', 'Spirits', 'bottle', 15, 2200, 1700, 20, 20),
    ('Predator', 'Predator spirit', 'Spirits', 'bottle', 15, 1500, 1000, 20, 20),
    ('Red Label', 'Red Label whiskey', 'Spirits', 'bottle', 15, 30000, 27000, 20, 20),
    ('Royal Circle', 'Royal Circle spirit', 'Spirits', 'bottle', 15, 15000, 14000, 20, 20),
    ('Smirnoff (Big)', 'Large Smirnoff vodka', 'Spirits', 'bottle', 15, 2000, 1500, 20, 20),
    ('Smirnoff Double Black', 'Smirnoff Double Black', 'Spirits', 'bottle', 15, 2000, 1500, 20, 20),
    ('Smirnoff (Small)', 'Small Smirnoff vodka', 'Spirits', 'bottle', 15, 1500, 1200, 20, 20),
    ('Smirnoff Double Black (Small)', 'Small Smirnoff Double Black', 'Spirits', 'bottle', 15, 1500, 1200, 20, 20),
    ('William Lawson', 'William Lawson whiskey', 'Spirits', 'bottle', 15, 25000, 22000, 20, 20),
    ('Gordons (Big)', 'Large Gordons gin', 'Spirits', 'bottle', 15, 15000, 12000, 20, 20),
    ('Gordons (Medium)', 'Medium Gordons gin', 'Spirits', 'bottle', 15, 8000, 5000, 20, 20),
    ('Gordons (Small)', 'Small Gordons gin', 'Spirits', 'bottle', 15, 5000, 3500, 20, 20),

    -- ==================== WINES ====================
    ('Andre', 'Andre wine', 'Wines', 'bottle', 15, 20000, 19000, 20, 20),
    ('Asconi Agor', 'Asconi Agor wine', 'Wines', 'bottle', 15, 18000, 16000, 20, 20),
    ('Blue Train', 'Blue Train wine', 'Wines', 'bottle', 15, 12000, 11000, 20, 20),
    ('Carlo Rossi', 'Carlo Rossi wine', 'Wines', 'bottle', 15, 18000, 15000, 20, 20),
    ('Four Cousins', 'Four Cousins wine', 'Wines', 'bottle', 15, 18000, 15000, 20, 20),
    ('Red Train', 'Red Train wine', 'Wines', 'bottle', 15, 12000, 11000, 20, 20),

    -- ==================== SOFT DRINKS ====================
    ('Bottled Water', 'Bottled water', 'Soft Drinks', 'bottle', 15, 500, 400, 20, 20),
    ('Mineral (Plastic)', 'Mineral water in plastic', 'Soft Drinks', 'bottle', 15, 1000, 800, 20, 20),
    ('Schweppes', 'Schweppes soft drink', 'Soft Drinks', 'bottle', 15, 1100, 800, 20, 20),
    ('Monster', 'Monster energy drink', 'Soft Drinks', 'bottle', 15, 2000, 1500, 20, 20),
    ('Smirnoff Ice X1', 'Smirnoff Ice X1', 'Soft Drinks', 'bottle', 15, 5000, 3500, 20, 20),
    ('Smirnoff Ice X1 (Big)', 'Large Smirnoff Ice X1', 'Soft Drinks', 'bottle', 15, 15000, 12000, 20, 20),

    -- ==================== DAIRY ====================
    ('Besty Yoghurt', 'Besty yoghurt', 'Dairy', 'bottle', 15, 2000, 1500, 20, 20),
    ('Fanny Yoghurt', 'Fanny yoghurt', 'Dairy', 'bottle', 15, 2500, 2000, 20, 20),
    ('Hollandia', 'Hollandia dairy drink', 'Dairy', 'bottle', 15, 3000, 2500, 20, 20),
    ('Nutri-Milk', 'Nutri-Milk', 'Dairy', 'bottle', 15, 1500, 1000, 20, 20),
    ('Nutri-Choco', 'Nutri-Choco chocolate milk', 'Dairy', 'bottle', 15, 1500, 1000, 20, 20),
    ('Nutri-Yo', 'Nutri-Yo yoghurt', 'Dairy', 'bottle', 15, 1500, 1000, 20, 20),
    ('VitaMilk', 'VitaMilk', 'Dairy', 'bottle', 15, 3000, 2500, 20, 20)
  ) AS v(name, description, category, unit, min_stock, vip_price_naira, outside_price_naira, initial_stock_vip, initial_stock_outside)
)
INSERT INTO public.stock_items (name, description, category, unit, min_stock)
SELECT d.name, d.description, d.category, d.unit, d.min_stock
FROM data d
WHERE NOT EXISTS (
  SELECT 1 FROM public.stock_items s WHERE s.name = d.name
);

-- 2) Create inventory_items for VIP bar
WITH data AS (
  SELECT * FROM (VALUES
    ('33 Export', '33 Export beer', 'Beers', 'bottle', 15, 1700, 1300),
    ('Amstel Malt (Bottle)', 'Amstel Malt in bottle', 'Beers', 'bottle', 15, 1200, 900),
    ('Budweiser', 'Budweiser beer', 'Beers', 'bottle', 15, 1800, 1400),
    ('Budweiser Royale', 'Budweiser Royale premium', 'Beers', 'bottle', 15, 2000, 1500),
    ('Desperado (Bottle)', 'Desperado beer in bottle', 'Beers', 'bottle', 15, 1800, 1400),
    ('Desperado (Can)', 'Desperado beer in can', 'Beers', 'can', 15, 1700, 1300),
    ('Farouz (Bottle)', 'Farouz beer in bottle', 'Beers', 'bottle', 15, 1100, 800),
    ('Farouz (Can)', 'Farouz beer in can', 'Beers', 'can', 15, 1000, 800),
    ('Gulder', 'Gulder beer', 'Beers', 'bottle', 15, 1800, 1400),
    ('Hero', 'Hero beer', 'Beers', 'bottle', 15, 1700, 1300),
    ('Guinness Malt (Bottle)', 'Guinness Malt in bottle', 'Beers', 'bottle', 15, 1200, 900),
    ('Life Beer', 'Life Beer', 'Beers', 'bottle', 15, 1700, 1300),
    ('Origin Beer', 'Origin Beer', 'Beers', 'bottle', 15, 1800, 1400),
    ('Star Beer', 'Star Beer', 'Beers', 'bottle', 15, 2000, 1500),
    ('Star Raddler', 'Star Raddler beer', 'Beers', 'bottle', 15, 1600, 1200),
    ('Tiger', 'Tiger beer', 'Beers', 'bottle', 15, 1700, 1300),
    ('Trophy Beer', 'Trophy Beer', 'Beers', 'bottle', 15, 1700, 1300),
    ('Trophy Stout', 'Trophy Stout', 'Beers', 'bottle', 15, 1800, 1400),
    ('Castle (Lite)', 'Castle Lite beer', 'Beers', 'bottle', 15, 1800, 1300),
    ('Heineken (Big)', 'Large Heineken beer', 'Beers', 'bottle', 15, 2000, 1500),
    ('Heineken (Medium)', 'Medium Heineken beer', 'Beers', 'bottle', 15, 1600, 1200),
    ('Stout (Big)', 'Large Stout', 'Beers', 'bottle', 15, 2100, 1700),
    ('Stout (Medium)', 'Medium Stout', 'Beers', 'bottle', 15, 1800, 1500),
    ('Stout (Small)', 'Small Stout', 'Beers', 'bottle', 15, 1500, 1200),
    ('Action Bitter', 'Action Bitter', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Black Bullet', 'Black Bullet spirit', 'Spirits', 'bottle', 15, 2500, 2000),
    ('Blue Bullet', 'Blue Bullet spirit', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Campari Medium', 'Medium Campari', 'Spirits', 'bottle', 15, 30000, 27000),
    ('Campari Small', 'Small Campari', 'Spirits', 'bottle', 15, 18000, 16000),
    ('Climax', 'Climax spirit', 'Spirits', 'bottle', 15, 1500, 1000),
    ('De-General', 'De-General spirit', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Exotic', 'Exotic spirit', 'Spirits', 'bottle', 15, 2500, 2000),
    ('Fearless', 'Fearless spirit', 'Spirits', 'bottle', 15, 1500, 1000),
    ('Flying Fish', 'Flying Fish spirit', 'Spirits', 'bottle', 15, 1500, 1000),
    ('Green Jameson', 'Green Jameson whiskey', 'Spirits', 'bottle', 15, 30000, 30000),
    ('Imperial Blue', 'Imperial Blue whiskey', 'Spirits', 'bottle', 15, 11000, 9000),
    ('Jameson Black', 'Jameson Black whiskey', 'Spirits', 'bottle', 15, 45000, 40000),
    ('Legend', 'Legend spirit', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Legend (Twist Bottle)', 'Legend in twist bottle', 'Spirits', 'bottle', 15, 1500, 1000),
    ('Long Rider', 'Long Rider spirit', 'Spirits', 'bottle', 15, 3000, 2500),
    ('Magic Moment', 'Magic Moment spirit', 'Spirits', 'bottle', 15, 15000, 15000),
    ('Olmeca Tequila', 'Olmeca Tequila', 'Spirits', 'bottle', 15, 30000, 28000),
    ('Origin Bitter', 'Origin Bitter', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Power Horse', 'Power Horse energy drink', 'Spirits', 'bottle', 15, 2200, 1700),
    ('Predator', 'Predator spirit', 'Spirits', 'bottle', 15, 1500, 1000),
    ('Red Label', 'Red Label whiskey', 'Spirits', 'bottle', 15, 30000, 27000),
    ('Royal Circle', 'Royal Circle spirit', 'Spirits', 'bottle', 15, 15000, 14000),
    ('Smirnoff (Big)', 'Large Smirnoff vodka', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Smirnoff Double Black', 'Smirnoff Double Black', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Smirnoff (Small)', 'Small Smirnoff vodka', 'Spirits', 'bottle', 15, 1500, 1200),
    ('Smirnoff Double Black (Small)', 'Small Smirnoff Double Black', 'Spirits', 'bottle', 15, 1500, 1200),
    ('William Lawson', 'William Lawson whiskey', 'Spirits', 'bottle', 15, 25000, 22000),
    ('Gordons (Big)', 'Large Gordons gin', 'Spirits', 'bottle', 15, 15000, 12000),
    ('Gordons (Medium)', 'Medium Gordons gin', 'Spirits', 'bottle', 15, 8000, 5000),
    ('Gordons (Small)', 'Small Gordons gin', 'Spirits', 'bottle', 15, 5000, 3500),
    ('Andre', 'Andre wine', 'Wines', 'bottle', 15, 20000, 19000),
    ('Asconi Agor', 'Asconi Agor wine', 'Wines', 'bottle', 15, 18000, 16000),
    ('Blue Train', 'Blue Train wine', 'Wines', 'bottle', 15, 12000, 11000),
    ('Carlo Rossi', 'Carlo Rossi wine', 'Wines', 'bottle', 15, 18000, 15000),
    ('Four Cousins', 'Four Cousins wine', 'Wines', 'bottle', 15, 18000, 15000),
    ('Red Train', 'Red Train wine', 'Wines', 'bottle', 15, 12000, 11000),
    ('Bottled Water', 'Bottled water', 'Soft Drinks', 'bottle', 15, 500, 400),
    ('Mineral (Plastic)', 'Mineral water in plastic', 'Soft Drinks', 'bottle', 15, 1000, 800),
    ('Schweppes', 'Schweppes soft drink', 'Soft Drinks', 'bottle', 15, 1100, 800),
    ('Monster', 'Monster energy drink', 'Soft Drinks', 'bottle', 15, 2000, 1500),
    ('Smirnoff Ice X1', 'Smirnoff Ice X1', 'Soft Drinks', 'bottle', 15, 5000, 3500),
    ('Smirnoff Ice X1 (Big)', 'Large Smirnoff Ice X1', 'Soft Drinks', 'bottle', 15, 15000, 12000),
    ('Besty Yoghurt', 'Besty yoghurt', 'Dairy', 'bottle', 15, 2000, 1500),
    ('Fanny Yoghurt', 'Fanny yoghurt', 'Dairy', 'bottle', 15, 2500, 2000),
    ('Hollandia', 'Hollandia dairy drink', 'Dairy', 'bottle', 15, 3000, 2500),
    ('Nutri-Milk', 'Nutri-Milk', 'Dairy', 'bottle', 15, 1500, 1000),
    ('Nutri-Choco', 'Nutri-Choco chocolate milk', 'Dairy', 'bottle', 15, 1500, 1000),
    ('Nutri-Yo', 'Nutri-Yo yoghurt', 'Dairy', 'bottle', 15, 1500, 1000),
    ('VitaMilk', 'VitaMilk', 'Dairy', 'bottle', 15, 3000, 2500)
  ) AS v(name, description, category, unit, min_stock, vip_price_naira, outside_price_naira)
)
INSERT INTO public.inventory_items (
  name, description, category, vip_bar_price, outside_bar_price, min_stock_level, unit, department, location_id, stock_item_id
)
SELECT
  d.name,
  d.description,
  d.category,
  (d.vip_price_naira * 100),
  NULL,
  d.min_stock,
  d.unit,
  'vip_bar',
  (SELECT id FROM public.locations WHERE name = 'VIP Bar'),
  (SELECT id FROM public.stock_items s WHERE s.name = d.name)
FROM data d
WHERE d.vip_price_naira IS NOT NULL
AND NOT EXISTS (
  SELECT 1 FROM public.inventory_items i
  WHERE i.name = d.name AND i.department = 'vip_bar'
);

-- 3) Create inventory_items for Outside bar
WITH data AS (
  SELECT * FROM (VALUES
    ('33 Export', '33 Export beer', 'Beers', 'bottle', 15, 1700, 1300),
    ('Amstel Malt (Bottle)', 'Amstel Malt in bottle', 'Beers', 'bottle', 15, 1200, 900),
    ('Budweiser', 'Budweiser beer', 'Beers', 'bottle', 15, 1800, 1400),
    ('Budweiser Royale', 'Budweiser Royale premium', 'Beers', 'bottle', 15, 2000, 1500),
    ('Desperado (Bottle)', 'Desperado beer in bottle', 'Beers', 'bottle', 15, 1800, 1400),
    ('Desperado (Can)', 'Desperado beer in can', 'Beers', 'can', 15, 1700, 1300),
    ('Farouz (Bottle)', 'Farouz beer in bottle', 'Beers', 'bottle', 15, 1100, 800),
    ('Farouz (Can)', 'Farouz beer in can', 'Beers', 'can', 15, 1000, 800),
    ('Gulder', 'Gulder beer', 'Beers', 'bottle', 15, 1800, 1400),
    ('Hero', 'Hero beer', 'Beers', 'bottle', 15, 1700, 1300),
    ('Guinness Malt (Bottle)', 'Guinness Malt in bottle', 'Beers', 'bottle', 15, 1200, 900),
    ('Life Beer', 'Life Beer', 'Beers', 'bottle', 15, 1700, 1300),
    ('Origin Beer', 'Origin Beer', 'Beers', 'bottle', 15, 1800, 1400),
    ('Star Beer', 'Star Beer', 'Beers', 'bottle', 15, 2000, 1500),
    ('Star Raddler', 'Star Raddler beer', 'Beers', 'bottle', 15, 1600, 1200),
    ('Tiger', 'Tiger beer', 'Beers', 'bottle', 15, 1700, 1300),
    ('Trophy Beer', 'Trophy Beer', 'Beers', 'bottle', 15, 1700, 1300),
    ('Trophy Stout', 'Trophy Stout', 'Beers', 'bottle', 15, 1800, 1400),
    ('Castle (Lite)', 'Castle Lite beer', 'Beers', 'bottle', 15, 1800, 1300),
    ('Heineken (Big)', 'Large Heineken beer', 'Beers', 'bottle', 15, 2000, 1500),
    ('Heineken (Medium)', 'Medium Heineken beer', 'Beers', 'bottle', 15, 1600, 1200),
    ('Stout (Big)', 'Large Stout', 'Beers', 'bottle', 15, 2100, 1700),
    ('Stout (Medium)', 'Medium Stout', 'Beers', 'bottle', 15, 1800, 1500),
    ('Stout (Small)', 'Small Stout', 'Beers', 'bottle', 15, 1500, 1200),
    ('Amstel Malt (Can)', 'Amstel Malt in can', 'Beers', 'can', 15, NULL, 900),
    ('Guinness Malt (Can)', 'Guinness Malt in can', 'Beers', 'can', 15, NULL, 900),
    ('Action Bitter', 'Action Bitter', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Black Bullet', 'Black Bullet spirit', 'Spirits', 'bottle', 15, 2500, 2000),
    ('Blue Bullet', 'Blue Bullet spirit', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Campari Medium', 'Medium Campari', 'Spirits', 'bottle', 15, 30000, 27000),
    ('Campari Small', 'Small Campari', 'Spirits', 'bottle', 15, 18000, 16000),
    ('Climax', 'Climax spirit', 'Spirits', 'bottle', 15, 1500, 1000),
    ('De-General', 'De-General spirit', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Exotic', 'Exotic spirit', 'Spirits', 'bottle', 15, 2500, 2000),
    ('Fearless', 'Fearless spirit', 'Spirits', 'bottle', 15, 1500, 1000),
    ('Flying Fish', 'Flying Fish spirit', 'Spirits', 'bottle', 15, 1500, 1000),
    ('Green Jameson', 'Green Jameson whiskey', 'Spirits', 'bottle', 15, 30000, 30000),
    ('Imperial Blue', 'Imperial Blue whiskey', 'Spirits', 'bottle', 15, 11000, 9000),
    ('Jameson Black', 'Jameson Black whiskey', 'Spirits', 'bottle', 15, 45000, 40000),
    ('Legend', 'Legend spirit', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Legend (Twist Bottle)', 'Legend in twist bottle', 'Spirits', 'bottle', 15, 1500, 1000),
    ('Long Rider', 'Long Rider spirit', 'Spirits', 'bottle', 15, 3000, 2500),
    ('Magic Moment', 'Magic Moment spirit', 'Spirits', 'bottle', 15, 15000, 15000),
    ('Olmeca Tequila', 'Olmeca Tequila', 'Spirits', 'bottle', 15, 30000, 28000),
    ('Origin Bitter', 'Origin Bitter', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Power Horse', 'Power Horse energy drink', 'Spirits', 'bottle', 15, 2200, 1700),
    ('Predator', 'Predator spirit', 'Spirits', 'bottle', 15, 1500, 1000),
    ('Red Label', 'Red Label whiskey', 'Spirits', 'bottle', 15, 30000, 27000),
    ('Royal Circle', 'Royal Circle spirit', 'Spirits', 'bottle', 15, 15000, 14000),
    ('Smirnoff (Big)', 'Large Smirnoff vodka', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Smirnoff Double Black', 'Smirnoff Double Black', 'Spirits', 'bottle', 15, 2000, 1500),
    ('Smirnoff (Small)', 'Small Smirnoff vodka', 'Spirits', 'bottle', 15, 1500, 1200),
    ('Smirnoff Double Black (Small)', 'Small Smirnoff Double Black', 'Spirits', 'bottle', 15, 1500, 1200),
    ('William Lawson', 'William Lawson whiskey', 'Spirits', 'bottle', 15, 25000, 22000),
    ('Gordons (Big)', 'Large Gordons gin', 'Spirits', 'bottle', 15, 15000, 12000),
    ('Gordons (Medium)', 'Medium Gordons gin', 'Spirits', 'bottle', 15, 8000, 5000),
    ('Gordons (Small)', 'Small Gordons gin', 'Spirits', 'bottle', 15, 5000, 3500),
    ('Andre', 'Andre wine', 'Wines', 'bottle', 15, 20000, 19000),
    ('Asconi Agor', 'Asconi Agor wine', 'Wines', 'bottle', 15, 18000, 16000),
    ('Blue Train', 'Blue Train wine', 'Wines', 'bottle', 15, 12000, 11000),
    ('Carlo Rossi', 'Carlo Rossi wine', 'Wines', 'bottle', 15, 18000, 15000),
    ('Four Cousins', 'Four Cousins wine', 'Wines', 'bottle', 15, 18000, 15000),
    ('Red Train', 'Red Train wine', 'Wines', 'bottle', 15, 12000, 11000),
    ('Bottled Water', 'Bottled water', 'Soft Drinks', 'bottle', 15, 500, 400),
    ('Mineral (Plastic)', 'Mineral water in plastic', 'Soft Drinks', 'bottle', 15, 1000, 800),
    ('Schweppes', 'Schweppes soft drink', 'Soft Drinks', 'bottle', 15, 1100, 800),
    ('Monster', 'Monster energy drink', 'Soft Drinks', 'bottle', 15, 2000, 1500),
    ('Smirnoff Ice X1', 'Smirnoff Ice X1', 'Soft Drinks', 'bottle', 15, 5000, 3500),
    ('Smirnoff Ice X1 (Big)', 'Large Smirnoff Ice X1', 'Soft Drinks', 'bottle', 15, 15000, 12000),
    ('Besty Yoghurt', 'Besty yoghurt', 'Dairy', 'bottle', 15, 2000, 1500),
    ('Fanny Yoghurt', 'Fanny yoghurt', 'Dairy', 'bottle', 15, 2500, 2000),
    ('Hollandia', 'Hollandia dairy drink', 'Dairy', 'bottle', 15, 3000, 2500),
    ('Nutri-Milk', 'Nutri-Milk', 'Dairy', 'bottle', 15, 1500, 1000),
    ('Nutri-Choco', 'Nutri-Choco chocolate milk', 'Dairy', 'bottle', 15, 1500, 1000),
    ('Nutri-Yo', 'Nutri-Yo yoghurt', 'Dairy', 'bottle', 15, 1500, 1000),
    ('VitaMilk', 'VitaMilk', 'Dairy', 'bottle', 15, 3000, 2500)
  ) AS v(name, description, category, unit, min_stock, vip_price_naira, outside_price_naira)
)
INSERT INTO public.inventory_items (
  name, description, category, vip_bar_price, outside_bar_price, min_stock_level, unit, department, location_id, stock_item_id
)
SELECT
  d.name,
  d.description,
  d.category,
  NULL,
  (d.outside_price_naira * 100),
  d.min_stock,
  d.unit,
  'outside_bar',
  (SELECT id FROM public.locations WHERE name = 'Outside Bar'),
  (SELECT id FROM public.stock_items s WHERE s.name = d.name)
FROM data d
WHERE d.outside_price_naira IS NOT NULL
AND NOT EXISTS (
  SELECT 1 FROM public.inventory_items i
  WHERE i.name = d.name AND i.department = 'outside_bar'
);

-- 4) Seed initial stock via ledger (Adjustment)
WITH data AS (
  SELECT * FROM (VALUES
    ('33 Export', 20, 20),
    ('Amstel Malt (Bottle)', 20, 20),
    ('Budweiser', 20, 20),
    ('Budweiser Royale', 20, 20),
    ('Desperado (Bottle)', 20, 20),
    ('Desperado (Can)', 20, 20),
    ('Farouz (Bottle)', 20, 20),
    ('Farouz (Can)', 20, 20),
    ('Gulder', 20, 20),
    ('Hero', 20, 20),
    ('Guinness Malt (Bottle)', 20, 20),
    ('Life Beer', 20, 20),
    ('Origin Beer', 20, 20),
    ('Star Beer', 20, 20),
    ('Star Raddler', 20, 20),
    ('Tiger', 20, 20),
    ('Trophy Beer', 20, 20),
    ('Trophy Stout', 20, 20),
    ('Castle (Lite)', 20, 20),
    ('Heineken (Big)', 20, 20),
    ('Heineken (Medium)', 20, 20),
    ('Stout (Big)', 20, 20),
    ('Stout (Medium)', 20, 20),
    ('Stout (Small)', 20, 20),
    ('Amstel Malt (Can)', NULL, 20),
    ('Guinness Malt (Can)', NULL, 20),
    ('Action Bitter', 20, 20),
    ('Black Bullet', 20, 20),
    ('Blue Bullet', 20, 20),
    ('Campari Medium', 20, 20),
    ('Campari Small', 20, 20),
    ('Climax', 20, 20),
    ('De-General', 20, 20),
    ('Exotic', 20, 20),
    ('Fearless', 20, 20),
    ('Flying Fish', 20, 20),
    ('Green Jameson', 20, 20),
    ('Imperial Blue', 20, 20),
    ('Jameson Black', 20, 20),
    ('Legend', 20, 20),
    ('Legend (Twist Bottle)', 20, 20),
    ('Long Rider', 20, 20),
    ('Magic Moment', 20, 20),
    ('Olmeca Tequila', 20, 20),
    ('Origin Bitter', 20, 20),
    ('Power Horse', 20, 20),
    ('Predator', 20, 20),
    ('Red Label', 20, 20),
    ('Royal Circle', 20, 20),
    ('Smirnoff (Big)', 20, 20),
    ('Smirnoff Double Black', 20, 20),
    ('Smirnoff (Small)', 20, 20),
    ('Smirnoff Double Black (Small)', 20, 20),
    ('William Lawson', 20, 20),
    ('Gordons (Big)', 20, 20),
    ('Gordons (Medium)', 20, 20),
    ('Gordons (Small)', 20, 20),
    ('Andre', 20, 20),
    ('Asconi Agor', 20, 20),
    ('Blue Train', 20, 20),
    ('Carlo Rossi', 20, 20),
    ('Four Cousins', 20, 20),
    ('Red Train', 20, 20),
    ('Bottled Water', 20, 20),
    ('Mineral (Plastic)', 20, 20),
    ('Schweppes', 20, 20),
    ('Monster', 20, 20),
    ('Smirnoff Ice X1', 20, 20),
    ('Smirnoff Ice X1 (Big)', 20, 20),
    ('Besty Yoghurt', 20, 20),
    ('Fanny Yoghurt', 20, 20),
    ('Hollandia', 20, 20),
    ('Nutri-Milk', 20, 20),
    ('Nutri-Choco', 20, 20),
    ('Nutri-Yo', 20, 20),
    ('VitaMilk', 20, 20)
  ) AS v(name, initial_stock_vip, initial_stock_outside)
),
staff AS (
  SELECT id
  FROM public.profiles
  WHERE status = 'Active'
    AND (
      roles @> ARRAY['owner']::text[]
      OR roles @> ARRAY['manager']::text[]
      OR roles @> ARRAY['supervisor']::text[]
    )
  ORDER BY created_at
  LIMIT 1
),
vip_loc AS (
  SELECT id FROM public.locations WHERE name = 'VIP Bar'
),
outside_loc AS (
  SELECT id FROM public.locations WHERE name = 'Outside Bar'
)
INSERT INTO public.stock_transactions (
  stock_item_id,
  location_id,
  staff_profile_id,
  transaction_type,
  quantity,
  notes
)
SELECT
  s.id,
  v.id,
  staff.id,
  'Adjustment',
  d.initial_stock_vip,
  'Initial stock load (populate_bars_complete)'
FROM data d
JOIN public.stock_items s ON s.name = d.name
JOIN vip_loc v ON d.initial_stock_vip IS NOT NULL
JOIN staff ON staff.id IS NOT NULL
WHERE d.initial_stock_vip > 0
AND NOT EXISTS (
  SELECT 1 FROM public.stock_transactions st
  WHERE st.stock_item_id = s.id
    AND st.location_id = v.id
    AND st.transaction_type = 'Adjustment'
    AND st.notes = 'Initial stock load (populate_bars_complete)'
);

WITH data AS (
  SELECT * FROM (VALUES
    ('33 Export', 20),
    ('Amstel Malt (Bottle)', 20),
    ('Budweiser', 20),
    ('Budweiser Royale', 20),
    ('Desperado (Bottle)', 20),
    ('Desperado (Can)', 20),
    ('Farouz (Bottle)', 20),
    ('Farouz (Can)', 20),
    ('Gulder', 20),
    ('Hero', 20),
    ('Guinness Malt (Bottle)', 20),
    ('Life Beer', 20),
    ('Origin Beer', 20),
    ('Star Beer', 20),
    ('Star Raddler', 20),
    ('Tiger', 20),
    ('Trophy Beer', 20),
    ('Trophy Stout', 20),
    ('Castle (Lite)', 20),
    ('Heineken (Big)', 20),
    ('Heineken (Medium)', 20),
    ('Stout (Big)', 20),
    ('Stout (Medium)', 20),
    ('Stout (Small)', 20),
    ('Amstel Malt (Can)', 20),
    ('Guinness Malt (Can)', 20),
    ('Action Bitter', 20),
    ('Black Bullet', 20),
    ('Blue Bullet', 20),
    ('Campari Medium', 20),
    ('Campari Small', 20),
    ('Climax', 20),
    ('De-General', 20),
    ('Exotic', 20),
    ('Fearless', 20),
    ('Flying Fish', 20),
    ('Green Jameson', 20),
    ('Imperial Blue', 20),
    ('Jameson Black', 20),
    ('Legend', 20),
    ('Legend (Twist Bottle)', 20),
    ('Long Rider', 20),
    ('Magic Moment', 20),
    ('Olmeca Tequila', 20),
    ('Origin Bitter', 20),
    ('Power Horse', 20),
    ('Predator', 20),
    ('Red Label', 20),
    ('Royal Circle', 20),
    ('Smirnoff (Big)', 20),
    ('Smirnoff Double Black', 20),
    ('Smirnoff (Small)', 20),
    ('Smirnoff Double Black (Small)', 20),
    ('William Lawson', 20),
    ('Gordons (Big)', 20),
    ('Gordons (Medium)', 20),
    ('Gordons (Small)', 20),
    ('Andre', 20),
    ('Asconi Agor', 20),
    ('Blue Train', 20),
    ('Carlo Rossi', 20),
    ('Four Cousins', 20),
    ('Red Train', 20),
    ('Bottled Water', 20),
    ('Mineral (Plastic)', 20),
    ('Schweppes', 20),
    ('Monster', 20),
    ('Smirnoff Ice X1', 20),
    ('Smirnoff Ice X1 (Big)', 20),
    ('Besty Yoghurt', 20),
    ('Fanny Yoghurt', 20),
    ('Hollandia', 20),
    ('Nutri-Milk', 20),
    ('Nutri-Choco', 20),
    ('Nutri-Yo', 20),
    ('VitaMilk', 20)
  ) AS v(name, initial_stock_outside)
),
staff AS (
  SELECT id
  FROM public.profiles
  WHERE status = 'Active'
    AND (
      roles @> ARRAY['owner']::text[]
      OR roles @> ARRAY['manager']::text[]
      OR roles @> ARRAY['supervisor']::text[]
    )
  ORDER BY created_at
  LIMIT 1
),
outside_loc AS (
  SELECT id FROM public.locations WHERE name = 'Outside Bar'
)
INSERT INTO public.stock_transactions (
  stock_item_id,
  location_id,
  staff_profile_id,
  transaction_type,
  quantity,
  notes
)
SELECT
  s.id,
  o.id,
  staff.id,
  'Adjustment',
  d.initial_stock_outside,
  'Initial stock load (populate_bars_complete)'
FROM data d
JOIN public.stock_items s ON s.name = d.name
JOIN outside_loc o ON d.initial_stock_outside IS NOT NULL
JOIN staff ON staff.id IS NOT NULL
WHERE d.initial_stock_outside > 0
AND NOT EXISTS (
  SELECT 1 FROM public.stock_transactions st
  WHERE st.stock_item_id = s.id
    AND st.location_id = o.id
    AND st.transaction_type = 'Adjustment'
    AND st.notes = 'Initial stock load (populate_bars_complete)'
);

-- Verification
SELECT category, count(*) AS item_count
FROM public.inventory_items
WHERE department IN ('vip_bar', 'outside_bar')
GROUP BY category
ORDER BY category;
