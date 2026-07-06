-- =============================================================
-- Generic Data Warehouse Schema for OTIF Monitoring
-- Aligned with 02_seed_data_generator.py and all views
-- =============================================================

CREATE TABLE IF NOT EXISTS customers (
    customer_id INTEGER PRIMARY KEY,
    customer_code TEXT NOT NULL,
    customer_name TEXT NOT NULL,
    region TEXT,
    country TEXT DEFAULT 'US'
);

CREATE TABLE IF NOT EXISTS vendors (
    vendor_id INTEGER PRIMARY KEY,
    vendor_code TEXT NOT NULL,
    vendor_name TEXT NOT NULL,
    region TEXT,
    country TEXT DEFAULT 'US',
    tier TEXT DEFAULT 'standard',
    otif_rate REAL,
    on_time_rate REAL,
    in_full_rate REAL
);

CREATE TABLE IF NOT EXISTS products (
    product_id INTEGER PRIMARY KEY,
    sku TEXT NOT NULL,
    product_name TEXT NOT NULL,
    category TEXT,
    subcategory TEXT,
    unit_of_measure TEXT DEFAULT 'EA',
    unit_price REAL
);

CREATE TABLE IF NOT EXISTS carriers (
    carrier_id INTEGER PRIMARY KEY,
    carrier_code TEXT NOT NULL,
    carrier_name TEXT NOT NULL,
    mode TEXT DEFAULT 'truck',
    on_time_rate REAL
);

CREATE TABLE IF NOT EXISTS orders (
    order_id INTEGER PRIMARY KEY,
    order_number TEXT NOT NULL,
    customer_code TEXT,
    order_date DATE NOT NULL,
    requested_delivery_date DATE,
    order_status TEXT DEFAULT 'pending',
    channel TEXT,
    currency TEXT DEFAULT 'USD',
    total_value REAL
);

CREATE TABLE IF NOT EXISTS order_lines (
    order_line_id INTEGER PRIMARY KEY,
    order_number TEXT NOT NULL,
    line_number INTEGER NOT NULL,
    sku TEXT,
    product_name TEXT,
    category TEXT,
    ordered_qty REAL NOT NULL,
    confirmed_qty REAL,
    unit_price REAL,
    line_total REAL,
    partial_delivery_allowed INTEGER DEFAULT 1
);

CREATE TABLE IF NOT EXISTS shipments (
    shipment_id INTEGER PRIMARY KEY,
    shipment_number TEXT NOT NULL,
    order_number TEXT NOT NULL,
    carrier_code TEXT,
    carrier_name TEXT,
    carrier_mode TEXT,
    vendor_code TEXT,
    vendor_region TEXT,
    shipping_point TEXT,
    route TEXT,
    planned_ship_date DATE,
    planned_delivery_date DATE,
    actual_ship_date DATE,
    actual_delivery_date DATE,
    shipment_status TEXT DEFAULT 'pending',
    delivery_type TEXT DEFAULT 'outbound',
    incoterm TEXT
);

CREATE TABLE IF NOT EXISTS delivery_lines (
    delivery_line_id INTEGER PRIMARY KEY,
    shipment_number TEXT NOT NULL,
    order_number TEXT NOT NULL,
    line_number INTEGER,
    product_id INTEGER,
    sku TEXT,
    delivered_qty REAL NOT NULL,
    damage_qty REAL DEFAULT 0
);

CREATE TABLE IF NOT EXISTS backorders (
    backorder_id INTEGER PRIMARY KEY,
    order_number TEXT NOT NULL,
    line_number INTEGER,
    product_id INTEGER,
    backorder_qty REAL NOT NULL,
    estimated_fill_date DATE,
    status TEXT DEFAULT 'open',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- ---------------------------------------------------------
-- alert_history — audit log for all notifications dispatched
-- by the Power Automate orchestrator (Teams/Email/Slack) plus
-- acknowledgment/escalation tracking. Referenced by
-- 06_security_rls.sql (region_access, audit_read policies).
-- ---------------------------------------------------------
CREATE TABLE IF NOT EXISTS alert_history (
    alert_history_id INTEGER PRIMARY KEY,
    alert_type TEXT NOT NULL,
    entity TEXT NOT NULL,
    region TEXT,
    severity TEXT NOT NULL,
    metric_value REAL,
    threshold_value REAL,
    alert_description TEXT,
    channels TEXT,
    acknowledged INTEGER DEFAULT 0,
    acknowledged_by TEXT,
    acknowledged_at TIMESTAMP,
    escalated INTEGER DEFAULT 0,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_shipments_vendor_delivery ON shipments(vendor_code, actual_delivery_date);
CREATE INDEX IF NOT EXISTS idx_orders_order_number ON orders(order_number);
CREATE INDEX IF NOT EXISTS idx_order_lines_order_number ON order_lines(order_number);
CREATE INDEX IF NOT EXISTS idx_delivery_lines_ship_ord ON delivery_lines(shipment_number, order_number);
CREATE INDEX IF NOT EXISTS idx_backorders_order_line ON backorders(order_number, line_number);
CREATE INDEX IF NOT EXISTS idx_backorders_status ON backorders(status);
CREATE INDEX IF NOT EXISTS idx_alert_history_type_entity ON alert_history(alert_type, entity);
CREATE INDEX IF NOT EXISTS idx_alert_history_region ON alert_history(region);
CREATE INDEX IF NOT EXISTS idx_alert_history_created ON alert_history(created_at);
