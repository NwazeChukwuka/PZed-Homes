-- ==============================================
-- POPULATE KITCHEN MENU ITEMS
-- Prices are stored in Kobo (₦ x 100) via * 100 in inserts
-- Enforces stock linkage via stock_items
-- ==============================================

-- CLEANUP: Delete existing kitchen menu items and related stock items
-- This ensures a fresh start when re-running the populate script
WITH seed_names AS (
  SELECT name FROM (VALUES
    ('Rice And Stew With Beef'), ('Rice And Stew With Goat Meat'), ('Rice And Stew With Chicken'),
    ('Jollof Rice And Beef'), ('Jollof Rice And Goat Meat'), ('Jollof Rice And Chicken'),
    ('Fried Rice And Beef'), ('Fried Rice And Goat Meat'), ('Fried Rice And Chicken'),
    ('Spaghetti With Egg'), ('Spaghetti With Chicken'),
    ('Indomie Only'), ('Indomie And Egg'), ('Indomie And Chicken'),
    ('Peppered Beef'), ('1/2 Peppered Beef'), ('Peppered Goat Meat'), ('1/2 Peppered Goat Meat'),
    ('Peppered Chicken'), ('Boiled Or Fried Yam With Egg Sauce'), ('Plantain With Egg Sauce'),
    ('Pepper Soup (Beef, Goat Meat Or Catfish)'), ('Soup With Swallow And Beef'),
    ('Soup With Swallow And Goat Meat'), ('Soup With Swallow And Chicken'),
    ('Vegetable Soup With Swallow and Chicken'), ('Vegetable Soup With Swallow and Goat Meat')
  ) AS v(name)
)
DELETE FROM public.menu_items
WHERE department = 'restaurant'
  AND name IN (SELECT name FROM seed_names);

-- Only delete stock_items if they're not used by other departments
WITH seed_names AS (
  SELECT name FROM (VALUES
    ('Rice And Stew With Beef'), ('Rice And Stew With Goat Meat'), ('Rice And Stew With Chicken'),
    ('Jollof Rice And Beef'), ('Jollof Rice And Goat Meat'), ('Jollof Rice And Chicken'),
    ('Fried Rice And Beef'), ('Fried Rice And Goat Meat'), ('Fried Rice And Chicken'),
    ('Spaghetti With Egg'), ('Spaghetti With Chicken'),
    ('Indomie Only'), ('Indomie And Egg'), ('Indomie And Chicken'),
    ('Peppered Beef'), ('1/2 Peppered Beef'), ('Peppered Goat Meat'), ('1/2 Peppered Goat Meat'),
    ('Peppered Chicken'), ('Boiled Or Fried Yam With Egg Sauce'), ('Plantain With Egg Sauce'),
    ('Pepper Soup (Beef, Goat Meat Or Catfish)'), ('Soup With Swallow And Beef'),
    ('Soup With Swallow And Goat Meat'), ('Soup With Swallow And Chicken'),
    ('Vegetable Soup With Swallow and Chicken'), ('Vegetable Soup With Swallow and Goat Meat')
  ) AS v(name)
)
DELETE FROM public.stock_items s
USING seed_names n
WHERE s.name = n.name
  AND NOT EXISTS (
    SELECT 1 FROM public.menu_items m
    WHERE m.stock_item_id = s.id AND m.department <> 'restaurant'
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.inventory_items i
    WHERE i.stock_item_id = s.id
  )
  AND NOT EXISTS (
    SELECT 1 FROM public.stock_transactions st
    WHERE st.stock_item_id = s.id
  );

-- 1) Create stock_items for each menu item (if missing)
WITH data AS (
  SELECT * FROM (VALUES
    -- Rice Dishes
    ('Rice And Stew With Beef', 'Rice and stew served with beef', 5500, 'restaurant', 'Rice Dishes', true),
    ('Rice And Stew With Goat Meat', 'Rice and stew served with goat meat', 5500, 'restaurant', 'Rice Dishes', true),
    ('Rice And Stew With Chicken', 'Rice and stew served with chicken', 6000, 'restaurant', 'Rice Dishes', true),
    ('Jollof Rice And Beef', 'Nigerian jollof rice with beef', 5500, 'restaurant', 'Rice Dishes', true),
    ('Jollof Rice And Goat Meat', 'Nigerian jollof rice with goat meat', 5500, 'restaurant', 'Rice Dishes', true),
    ('Jollof Rice And Chicken', 'Nigerian jollof rice with chicken', 6000, 'restaurant', 'Rice Dishes', true),
    ('Fried Rice And Beef', 'Nigerian fried rice with beef', 5500, 'restaurant', 'Rice Dishes', true),
    ('Fried Rice And Goat Meat', 'Nigerian fried rice with goat meat', 5500, 'restaurant', 'Rice Dishes', true),
    ('Fried Rice And Chicken', 'Nigerian fried rice with chicken', 6000, 'restaurant', 'Rice Dishes', true),

    -- Spaghetti Dishes
    ('Spaghetti With Egg', 'Spaghetti served with egg', 4000, 'restaurant', 'Spaghetti', true),
    ('Spaghetti With Chicken', 'Spaghetti served with chicken', 6000, 'restaurant', 'Spaghetti', true),

    -- Indomie Dishes
    ('Indomie Only', 'Plain indomie noodles', 2500, 'restaurant', 'Indomie', true),
    ('Indomie And Egg', 'Indomie noodles with egg', 3500, 'restaurant', 'Indomie', true),
    ('Indomie And Chicken', 'Indomie noodles with chicken', 5000, 'restaurant', 'Indomie', true),

    -- Grilled & Peppered
    ('Peppered Beef', 'Spicy peppered beef', 5000, 'restaurant', 'Grilled', true),
    ('1/2 Peppered Beef', 'Half portion of peppered beef', 2500, 'restaurant', 'Grilled', true),
    ('Peppered Goat Meat', 'Spicy peppered goat meat', 5000, 'restaurant', 'Grilled', true),
    ('1/2 Peppered Goat Meat', 'Half portion of peppered goat meat', 2500, 'restaurant', 'Grilled', true),
    ('Peppered Chicken', 'Spicy peppered chicken', 6000, 'restaurant', 'Grilled', true),

    -- Breakfast
    ('Boiled Or Fried Yam With Egg Sauce', 'Yam (boiled or fried) with egg sauce', 4000, 'restaurant', 'Breakfast', true),
    ('Plantain With Egg Sauce', 'Fried plantain with egg sauce', 4000, 'restaurant', 'Breakfast', true),

    -- Soups
    ('Pepper Soup (Beef, Goat Meat Or Catfish)', 'Spicy pepper soup with choice of beef, goat meat or catfish', 5000, 'restaurant', 'Soups', true),
    ('Soup With Swallow And Beef', 'Soup with swallow and beef', 5500, 'restaurant', 'Soups', true),
    ('Soup With Swallow And Goat Meat', 'Soup with swallow and goat meat', 5500, 'restaurant', 'Soups', true),
    ('Soup With Swallow And Chicken', 'Soup with swallow and chicken', 6000, 'restaurant', 'Soups', true),
    ('Vegetable Soup With Swallow and Chicken', 'Vegetable soup with swallow and chicken', 7000, 'restaurant', 'Soups', true),
    ('Vegetable Soup With Swallow and Goat Meat', 'Vegetable soup with swallow and goat meat', 6500, 'restaurant', 'Soups', true)
  ) AS v(name, description, price_naira, department, category, is_available)
)
INSERT INTO public.stock_items (name, description, category, unit, min_stock)
SELECT d.name, d.description, d.category, 'plate', 5
FROM data d
WHERE NOT EXISTS (
  SELECT 1 FROM public.stock_items s WHERE s.name = d.name
);

-- 2) Insert menu_items with stock_item_id linkage
WITH data AS (
  SELECT * FROM (VALUES
    ('Rice And Stew With Beef', 'Rice and stew served with beef', 5500, 'restaurant', 'Rice Dishes', true),
    ('Rice And Stew With Goat Meat', 'Rice and stew served with goat meat', 5500, 'restaurant', 'Rice Dishes', true),
    ('Rice And Stew With Chicken', 'Rice and stew served with chicken', 6000, 'restaurant', 'Rice Dishes', true),
    ('Jollof Rice And Beef', 'Nigerian jollof rice with beef', 5500, 'restaurant', 'Rice Dishes', true),
    ('Jollof Rice And Goat Meat', 'Nigerian jollof rice with goat meat', 5500, 'restaurant', 'Rice Dishes', true),
    ('Jollof Rice And Chicken', 'Nigerian jollof rice with chicken', 6000, 'restaurant', 'Rice Dishes', true),
    ('Fried Rice And Beef', 'Nigerian fried rice with beef', 5500, 'restaurant', 'Rice Dishes', true),
    ('Fried Rice And Goat Meat', 'Nigerian fried rice with goat meat', 5500, 'restaurant', 'Rice Dishes', true),
    ('Fried Rice And Chicken', 'Nigerian fried rice with chicken', 6000, 'restaurant', 'Rice Dishes', true),
    ('Spaghetti With Egg', 'Spaghetti served with egg', 4000, 'restaurant', 'Spaghetti', true),
    ('Spaghetti With Chicken', 'Spaghetti served with chicken', 6000, 'restaurant', 'Spaghetti', true),
    ('Indomie Only', 'Plain indomie noodles', 2500, 'restaurant', 'Indomie', true),
    ('Indomie And Egg', 'Indomie noodles with egg', 3500, 'restaurant', 'Indomie', true),
    ('Indomie And Chicken', 'Indomie noodles with chicken', 5000, 'restaurant', 'Indomie', true),
    ('Peppered Beef', 'Spicy peppered beef', 5000, 'restaurant', 'Grilled', true),
    ('1/2 Peppered Beef', 'Half portion of peppered beef', 2500, 'restaurant', 'Grilled', true),
    ('Peppered Goat Meat', 'Spicy peppered goat meat', 5000, 'restaurant', 'Grilled', true),
    ('1/2 Peppered Goat Meat', 'Half portion of peppered goat meat', 2500, 'restaurant', 'Grilled', true),
    ('Peppered Chicken', 'Spicy peppered chicken', 6000, 'restaurant', 'Grilled', true),
    ('Boiled Or Fried Yam With Egg Sauce', 'Yam (boiled or fried) with egg sauce', 4000, 'restaurant', 'Breakfast', true),
    ('Plantain With Egg Sauce', 'Fried plantain with egg sauce', 4000, 'restaurant', 'Breakfast', true),
    ('Pepper Soup (Beef, Goat Meat Or Catfish)', 'Spicy pepper soup with choice of beef, goat meat or catfish', 5000, 'restaurant', 'Soups', true),
    ('Soup With Swallow And Beef', 'Soup with swallow and beef', 5500, 'restaurant', 'Soups', true),
    ('Soup With Swallow And Goat Meat', 'Soup with swallow and goat meat', 5500, 'restaurant', 'Soups', true),
    ('Soup With Swallow And Chicken', 'Soup with swallow and chicken', 6000, 'restaurant', 'Soups', true),
    ('Vegetable Soup With Swallow and Chicken', 'Vegetable soup with swallow and chicken', 7000, 'restaurant', 'Soups', true),
    ('Vegetable Soup With Swallow and Goat Meat', 'Vegetable soup with swallow and goat meat', 6500, 'restaurant', 'Soups', true)
  ) AS v(name, description, price_naira, department, category, is_available)
)
INSERT INTO public.menu_items (
  name, description, price, department, category, is_available, stock_item_id
)
SELECT
  d.name,
  d.description,
  (d.price_naira * 100),
  d.department,
  d.category,
  d.is_available,
  (SELECT id FROM public.stock_items s WHERE s.name = d.name)
FROM data d
WHERE NOT EXISTS (
  SELECT 1 FROM public.menu_items m
  WHERE m.name = d.name AND m.department = d.department
);

-- Verify data
SELECT
  name,
  category,
  price / 100.0 AS price_ngn,
  department,
  is_available,
  stock_item_id
FROM public.menu_items
WHERE department = 'restaurant'
ORDER BY category, name;
