/* ============================================
   PRODUCTS & BOXES
   ============================================ */

-- Product names (e.g., "Airbrush Stencil")
CREATE TABLE product_types (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

-- Box sizes (e.g., "9 x 7")
CREATE TABLE boxes (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    inner_l_in NUMERIC(10,2) NOT NULL CHECK (inner_l_in > 0),
    inner_w_in NUMERIC(10,2) NOT NULL CHECK (inner_w_in > 0),
    inner_h_in NUMERIC(10,2) NOT NULL CHECK (inner_h_in > 0),
    active BOOLEAN NOT NULL DEFAULT TRUE
);

-- All product and box combinations (which boxes can fit which products)
CREATE TABLE products (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL,
    product_type_id BIGINT NOT NULL REFERENCES product_types(id) ON DELETE RESTRICT,
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (product_type_id, name)
);

CREATE TABLE product_box (
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE CASCADE,
    box_id BIGINT NOT NULL REFERENCES boxes(id) ON DELETE RESTRICT,
    is_default BOOLEAN NOT NULL DEFAULT FALSE,
    note TEXT,
    PRIMARY KEY (product_id, box_id)
);

-- Default box per product (partial-unique)
CREATE UNIQUE INDEX ux_product_box_default
    ON product_box(product_id) WHERE is_default;


/* ============================================
   ORDERS & ITEMS
   ============================================ */

-- Order status enum
CREATE TYPE order_status AS ENUM ('draft', 'paid', 'fulfilled', 'cancelled');

-- Orders
CREATE TABLE orders (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    status order_status NOT NULL DEFAULT 'draft',
    date DATE,
    shipped_at TIMESTAMPTZ,                    -- optional roll-up; not used for strict shipped logic
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Items contained in an order
CREATE TABLE order_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id BIGINT NOT NULL REFERENCES products(id) ON DELETE RESTRICT,
    qty INTEGER NOT NULL CHECK (qty > 0),
    unit_price_cents INTEGER NOT NULL DEFAULT 0 CHECK (unit_price_cents >= 0),
    shipping_note TEXT,
    proof_sent TEXT,
    -- Generated line total for easy reporting
    line_total_cents INTEGER GENERATED ALWAYS AS (qty * unit_price_cents) STORED
);


/* ============================================
   SHIPMENTS (1:N PER ORDER)
   ============================================ */

-- One order can have many parcels (split shipments)
CREATE TABLE shipments (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    order_id BIGINT NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    box_id BIGINT NOT NULL REFERENCES boxes(id) ON DELETE RESTRICT,
    carrier TEXT,
    tracking_no TEXT,
    shipped_at TIMESTAMPTZ,                    -- NULL until actually shipped
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Unique tracking numbers, allowing NULLs
CREATE UNIQUE INDEX IF NOT EXISTS ux_shipments_tracking_no
    ON shipments (tracking_no)
    WHERE tracking_no IS NOT NULL;

-- Shipment lookups
CREATE INDEX IF NOT EXISTS idx_shipments_order_id ON shipments (order_id);
CREATE INDEX IF NOT EXISTS idx_shipments_box_id   ON shipments (box_id);


/* ============================================
   INVENTORY
   ============================================ */

CREATE TABLE inventory_items (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    name TEXT NOT NULL UNIQUE,
    category TEXT,
    unit TEXT DEFAULT 'count',
    active BOOLEAN NOT NULL DEFAULT TRUE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE inventory_purchase_history (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    inventory_item_id BIGINT NOT NULL REFERENCES inventory_items(id) ON DELETE RESTRICT,
    quantity INTEGER NOT NULL CHECK (quantity > 0),
    purchase_date DATE NOT NULL DEFAULT CURRENT_DATE
);

-- Consumption rules: apply per order item (by product) or per box (by box)
CREATE TABLE inventory_consumption_rules (
    id BIGINT GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    applies_to TEXT NOT NULL CHECK (applies_to IN ('per_order_item','per_box')),
    product_id BIGINT REFERENCES products(id) ON DELETE CASCADE,
    box_id BIGINT REFERENCES boxes(id) ON DELETE CASCADE,
    inventory_item_id BIGINT NOT NULL REFERENCES inventory_items(id) ON DELETE RESTRICT,
    qty_per_unit INTEGER NOT NULL CHECK (qty_per_unit > 0),
    -- Exactly one target must be set, matching applies_to
    CONSTRAINT icr_exact_target_chk CHECK (
        (applies_to = 'per_order_item' AND product_id IS NOT NULL AND box_id IS NULL)
        OR
        (applies_to = 'per_box'       AND box_id IS NOT NULL    AND product_id IS NULL)
    )
);

-- Uniqueness without NULL pitfalls
CREATE UNIQUE INDEX IF NOT EXISTS ux_icr_item_per_order_item
    ON inventory_consumption_rules (applies_to, product_id, inventory_item_id)
    WHERE applies_to = 'per_order_item' AND box_id IS NULL;

CREATE UNIQUE INDEX IF NOT EXISTS ux_icr_item_per_box
    ON inventory_consumption_rules (applies_to, box_id, inventory_item_id)
    WHERE applies_to = 'per_box' AND product_id IS NULL;

-- Helpful lookups
CREATE INDEX IF NOT EXISTS idx_icr_inventory_item_id ON inventory_consumption_rules (inventory_item_id);
CREATE INDEX IF NOT EXISTS idx_icr_product_id        ON inventory_consumption_rules (product_id);
CREATE INDEX IF NOT EXISTS idx_icr_box_id            ON inventory_consumption_rules (box_id);


/* ============================================
   TRIGGERS & FUNCTIONS
   ============================================ */

-- updated_at hygiene for products and orders
CREATE OR REPLACE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER products_updated_at_trg
BEFORE UPDATE ON products FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER orders_updated_at_trg
BEFORE UPDATE ON orders FOR EACH ROW EXECUTE FUNCTION set_updated_at();


/* ============================================
   REPORTING (STRICT "ALL PARCELS SHIPPED")
   ============================================ */

-- An order is considered shipped only when:
--   (a) it has at least one shipment, AND
--   (b) none of its shipments are unshipped (shipped_at IS NULL)
DROP VIEW IF EXISTS order_history_v;
CREATE VIEW order_history_v AS
SELECT o.*
FROM orders o
WHERE EXISTS (SELECT 1 FROM shipments s WHERE s.order_id = o.id)
  AND NOT EXISTS (SELECT 1 FROM shipments s WHERE s.order_id = o.id AND s.shipped_at IS NULL);

-- Weekly order tracking MV using strict logic
DROP MATERIALIZED VIEW IF EXISTS weekly_order_tracking_mv;
CREATE MATERIALIZED VIEW weekly_order_tracking_mv AS
SELECT
    DATE_TRUNC('week', COALESCE(o.date, o.created_at))::DATE AS week_start,
    (DATE_TRUNC('week', COALESCE(o.date, o.created_at)) + INTERVAL '6 days')::DATE AS week_end,
    COUNT(*) FILTER (
        WHERE EXISTS (SELECT 1 FROM shipments s WHERE s.order_id = o.id)
          AND NOT EXISTS (SELECT 1 FROM shipments s WHERE s.order_id = o.id AND s.shipped_at IS NULL)
    ) AS shipped_count,
    COUNT(*) FILTER (
        WHERE NOT EXISTS (SELECT 1 FROM shipments s WHERE s.order_id = o.id)
           OR EXISTS (SELECT 1 FROM shipments s WHERE s.order_id = o.id AND s.shipped_at IS NULL)
    ) AS open_count
FROM orders o
GROUP BY 1, 2;

CREATE UNIQUE INDEX IF NOT EXISTS weekly_order_tracking_mv_pk
    ON weekly_order_tracking_mv (week_start, week_end);


/* ============================================
   GENERAL INDEXES
   ============================================ */

-- FKs / lookups
CREATE INDEX IF NOT EXISTS idx_products_product_type_id ON products (product_type_id);
CREATE INDEX IF NOT EXISTS idx_product_box_product_id   ON product_box (product_id);
CREATE INDEX IF NOT EXISTS idx_product_box_box_id       ON product_box (box_id);
CREATE INDEX IF NOT EXISTS idx_order_items_order_id     ON order_items (order_id);
CREATE INDEX IF NOT EXISTS idx_order_items_product_id   ON order_items (product_id);

-- Orders filtering + dates
CREATE INDEX IF NOT EXISTS idx_orders_status     ON orders (status);
CREATE INDEX IF NOT EXISTS idx_orders_dates      ON orders (date, created_at);
CREATE INDEX IF NOT EXISTS idx_orders_shipped_at ON orders (shipped_at);
