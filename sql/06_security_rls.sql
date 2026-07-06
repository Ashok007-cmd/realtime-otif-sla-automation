-- =============================================================
-- Row-Level Security Policies for OTIF Data
-- PostgreSQL 13+ only. Not applicable to SQLite.
-- =============================================================

-- ---------------------------------------------------------
-- Enable RLS on base tables
-- ---------------------------------------------------------

DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'regional_manager') THEN
    CREATE ROLE regional_manager;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'reporting_user') THEN
    CREATE ROLE reporting_user;
  END IF;
  IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'auditor') THEN
    CREATE ROLE auditor;
  END IF;
END
$$;

ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE vendors   ENABLE ROW LEVEL SECURITY;
ALTER TABLE products  ENABLE ROW LEVEL SECURITY;
ALTER TABLE carriers  ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders    ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE shipments ENABLE ROW LEVEL SECURITY;
ALTER TABLE delivery_lines ENABLE ROW LEVEL SECURITY;
ALTER TABLE backorders ENABLE ROW LEVEL SECURITY;
ALTER TABLE alert_history ENABLE ROW LEVEL SECURITY;

-- ---------------------------------------------------------
-- Policy 1: Region-based access (e.g., regional managers)
-- Requires: CREATE ROLE regional_manager; and a 'region'
-- claim in the app's JWT or session variable.
-- ---------------------------------------------------------

-- Helper: safe region resolver — returns 'DENY' if app.region is not set
-- so that policies silently block all rows instead of raising an error.
CREATE OR REPLACE FUNCTION app.current_region()
RETURNS TEXT
LANGUAGE SQL
STABLE
AS $$
    SELECT COALESCE(NULLIF(current_setting('app.region', true), ''), 'DENY');
$$;

-- NOTE ON POLICY COMBINATION: PostgreSQL RLS policies are PERMISSIVE by
-- default and combined with OR within the same command type. A policy with
-- no "TO <role>" clause applies to PUBLIC (every role). Previously the
-- read_only/audit_read policies below had USING (true) with no TO clause,
-- which OR'd against region_access and made every row visible to every
-- role regardless of region — silently defeating region isolation
-- entirely. Each policy is now scoped with TO so only the intended role
-- gets the intended rule.

CREATE POLICY region_access ON customers
    FOR ALL
    TO regional_manager
    USING (region = app.current_region());

CREATE POLICY region_access ON vendors
    FOR ALL
    TO regional_manager
    USING (region = app.current_region());

CREATE POLICY region_access ON orders
    FOR ALL
    TO regional_manager
    USING (customer_code IN (
        SELECT customer_code FROM customers
        WHERE region = app.current_region()
    ));

CREATE POLICY region_access ON order_lines
    FOR ALL
    TO regional_manager
    USING (order_number IN (
        SELECT order_number FROM orders
        WHERE customer_code IN (
            SELECT customer_code FROM customers
            WHERE region = app.current_region()
        )
    ));

CREATE POLICY region_access ON shipments
    FOR ALL
    TO regional_manager
    USING (vendor_region = app.current_region());

CREATE POLICY region_access ON alert_history
    FOR ALL
    TO regional_manager
    USING (region = app.current_region());

-- ---------------------------------------------------------
-- Policy 2: Read-only access for reporting users
-- Requires: CREATE ROLE reporting_user;
-- Scoped TO reporting_user only — must NOT apply to PUBLIC/
-- regional_manager or it would bypass region_access above.
-- ---------------------------------------------------------

CREATE POLICY read_only ON customers FOR SELECT TO reporting_user USING (true);
CREATE POLICY read_only ON vendors   FOR SELECT TO reporting_user USING (true);
CREATE POLICY read_only ON products  FOR SELECT TO reporting_user USING (true);
CREATE POLICY read_only ON carriers  FOR SELECT TO reporting_user USING (true);
CREATE POLICY read_only ON orders    FOR SELECT TO reporting_user USING (true);
CREATE POLICY read_only ON order_lines FOR SELECT TO reporting_user USING (true);
CREATE POLICY read_only ON shipments FOR SELECT TO reporting_user USING (true);
CREATE POLICY read_only ON delivery_lines FOR SELECT TO reporting_user USING (true);
CREATE POLICY read_only ON backorders FOR SELECT TO reporting_user USING (true);
CREATE POLICY read_only ON alert_history FOR SELECT TO reporting_user USING (true);

-- ---------------------------------------------------------
-- Policy 3: Audit-only access (can read alert_history)
-- Requires: CREATE ROLE auditor;
-- Scoped TO auditor only.
-- ---------------------------------------------------------

CREATE POLICY audit_read ON alert_history FOR SELECT TO auditor USING (true);

-- Grant usage
GRANT USAGE ON SCHEMA public TO reporting_user, regional_manager, auditor;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO reporting_user, auditor;
GRANT SELECT ON customers, vendors, orders, order_lines, shipments, alert_history
    TO regional_manager;
