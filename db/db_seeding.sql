-- ===========================
-- EXAMPLE SEEDING (IDEMPOTENT)
-- ===========================

-- PRODUCT TYPES (families)
INSERT INTO product_types (name) VALUES
  ('drink stencil'),
  ('airbrush stencil'),
  ('macaron stencil'),
  ('vinyl stencil'),
  ('other')
ON CONFLICT (name) DO NOTHING;

-- BOXES (dimensions in inches; normalize names to include height)
INSERT INTO boxes (name, inner_l_in, inner_w_in, inner_h_in, active) VALUES
  ('7 x 5 x 4 (drink stencil)', 7, 5, 4, TRUE),
  ('9 x 7 x 4 (drink stencil)', 9, 7, 4, TRUE),
  ('9 x 7 x 4',                 9, 7, 4, TRUE),
  ('12 x 15 x 4',              12, 15, 4, TRUE),
  ('13 x 18 x 4',              13, 18, 4, TRUE),
  ('18 x 24 x 6',              18, 24, 6, TRUE),
  ('24 x 6 x 6',               24,  6, 6, TRUE)
ON CONFLICT (name) DO NOTHING;

-- INVENTORY ITEMS (names align to box names for per_box rules)
INSERT INTO inventory_items (name, category, unit, active) VALUES
  ('business cards',          'marketing',  'count', TRUE),
  ('inserts (generic)',       'marketing',  'count', TRUE),
  ('inserts (coffee)',        'marketing',  'count', TRUE),
  ('shakers',                 'accessory',  'count', TRUE),
  ('7 x 5 x 4 (drink stencil)','box',       'count', TRUE),
  ('9 x 7 x 4 (drink stencil)','box',       'count', TRUE),
  ('9 x 7 x 4',               'box',        'count', TRUE),
  ('12 x 15 x 4',             'box',        'count', TRUE),
  ('13 x 18 x 4',             'box',        'count', TRUE),
  ('18 x 24 x 6',             'box',        'count', TRUE),
  ('24 x 6 x 6',              'box',        'count', TRUE)
ON CONFLICT (name) DO NOTHING;

-- PRODUCTS (one canonical product per family for now)
INSERT INTO products (name, product_type_id, active)
SELECT 'drink stencil', (SELECT id FROM product_types WHERE name='drink stencil'), TRUE
ON CONFLICT (product_type_id, name) DO NOTHING;

INSERT INTO products (name, product_type_id, active)
SELECT 'airbrush stencil', (SELECT id FROM product_types WHERE name='airbrush stencil'), TRUE
ON CONFLICT (product_type_id, name) DO NOTHING;

INSERT INTO products (name, product_type_id, active)
SELECT 'macaron stencil', (SELECT id FROM product_types WHERE name='macaron stencil'), TRUE
ON CONFLICT (product_type_id, name) DO NOTHING;

INSERT INTO products (name, product_type_id, active)
SELECT 'vinyl stencil', (SELECT id FROM product_types WHERE name='vinyl stencil'), TRUE
ON CONFLICT (product_type_id, name) DO NOTHING;

-- PRODUCT -> BOX COMPATIBILITY (defaults & alternates)
INSERT INTO product_box (product_id, box_id, is_default)
SELECT (SELECT id FROM products WHERE name='drink stencil'),
       (SELECT id FROM boxes    WHERE name='7 x 5 x 4 (drink stencil)'),
       TRUE
ON CONFLICT (product_id, box_id) DO NOTHING;

INSERT INTO product_box (product_id, box_id, is_default)
SELECT (SELECT id FROM products WHERE name='drink stencil'),
       (SELECT id FROM boxes    WHERE name='9 x 7 x 4 (drink stencil)'),
       FALSE
ON CONFLICT (product_id, box_id) DO NOTHING;

INSERT INTO product_box (product_id, box_id, is_default)
SELECT (SELECT id FROM products WHERE name='airbrush stencil'),
       (SELECT id FROM boxes    WHERE name='9 x 7 x 4'),
       TRUE
ON CONFLICT (product_id, box_id) DO NOTHING;

INSERT INTO product_box (product_id, box_id, is_default)
SELECT (SELECT id FROM products WHERE name='macaron stencil'),
       (SELECT id FROM boxes    WHERE name='9 x 7 x 4'),
       TRUE
ON CONFLICT (product_id, box_id) DO NOTHING;

INSERT INTO product_box (product_id, box_id, is_default)
SELECT (SELECT id FROM products WHERE name='vinyl stencil'),
       (SELECT id FROM boxes    WHERE name='9 x 7 x 4'),
       TRUE
ON CONFLICT (product_id, box_id) DO NOTHING;

-- INVENTORY CONSUMPTION RULES

-- PER BOX: consume one inventory item with the same name as the box (if present)
INSERT INTO inventory_consumption_rules (applies_to, box_id, inventory_item_id, qty_per_unit)
SELECT 'per_box',
       b.id,
       ii.id,
       1
FROM boxes b
JOIN inventory_items ii ON LOWER(ii.name) = LOWER(b.name)
ON CONFLICT DO NOTHING;

-- PER ORDER ITEM: drink stencil → coffee insert + business card + shakers
INSERT INTO inventory_consumption_rules (applies_to, product_id, inventory_item_id, qty_per_unit)
SELECT 'per_order_item',
       p.id,
       ii.id,
       1
FROM products p
JOIN inventory_items ii ON ii.name IN ('inserts (coffee)', 'business cards', 'shakers')
WHERE p.name = 'drink stencil'
ON CONFLICT DO NOTHING;

-- PER ORDER ITEM: airbrush/macaron/vinyl → generic insert + business card
INSERT INTO inventory_consumption_rules (applies_to, product_id, inventory_item_id, qty_per_unit)
SELECT 'per_order_item', p.id, ii.id, 1
FROM products p
JOIN inventory_items ii ON ii.name IN ('inserts (generic)', 'business cards')
WHERE p.name IN ('airbrush stencil','macaron stencil','vinyl stencil')
ON CONFLICT DO NOTHING;

-- OPTIONAL: opening stock examples
-- INSERT INTO inventory_purchase_history (inventory_item_id, quantity, purchase_date)
-- SELECT id, 100, CURRENT_DATE FROM inventory_items WHERE name IN ('9 x 7 x 4','7 x 5 x 4 (drink stencil)');
