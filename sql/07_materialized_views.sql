-- =============================================================
-- Materialized Views for OTIF Performance Optimization
-- PostgreSQL 13+ only. Refresh periodically via cron/agent.
-- =============================================================

-- ---------------------------------------------------------
-- 1. mv_otif_rolling_7d — cached 7-day rolling OTIF
-- Materialized to avoid recomputing the expensive window
-- function chain on every query.
-- ---------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_otif_rolling_7d CASCADE;

CREATE MATERIALIZED VIEW mv_otif_rolling_7d AS
SELECT * FROM v_otif_rolling_7d;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_otif_7d_vendor_date
    ON mv_otif_rolling_7d(vendor_code, metric_date);

CREATE INDEX IF NOT EXISTS idx_mv_otif_7d_region
    ON mv_otif_rolling_7d(vendor_region);

COMMENT ON MATERIALIZED VIEW mv_otif_rolling_7d IS
    'Materialized 7-day rolling OTIF. Refresh: REFRESH MATERIALIZED VIEW CONCURRENTLY mv_otif_rolling_7d;';

-- ---------------------------------------------------------
-- 2. mv_otif_vendor_hierarchy — vendor performance summary
-- ---------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_otif_vendor_hierarchy CASCADE;

CREATE MATERIALIZED VIEW mv_otif_vendor_hierarchy AS
SELECT * FROM v_otif_vendor_hierarchy;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_vendor_hierarchy_code
    ON mv_otif_vendor_hierarchy(vendor_code);

CREATE INDEX IF NOT EXISTS idx_mv_vendor_hierarchy_region
    ON mv_otif_vendor_hierarchy(vendor_region);

CREATE INDEX IF NOT EXISTS idx_mv_vendor_hierarchy_sla
    ON mv_otif_vendor_hierarchy(sla_status);

-- ---------------------------------------------------------
-- 3. mv_otif_carrier_scorecard — cached carrier metrics
-- ---------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_otif_carrier_scorecard CASCADE;

CREATE MATERIALIZED VIEW mv_otif_carrier_scorecard AS
SELECT * FROM v_otif_carrier_scorecard;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_carrier_week
    ON mv_otif_carrier_scorecard(carrier_code, delivery_week);

-- ---------------------------------------------------------
-- 4. mv_alert_dashboard_summary — cached alert state
-- ---------------------------------------------------------

DROP MATERIALIZED VIEW IF EXISTS mv_alert_dashboard_summary CASCADE;

CREATE MATERIALIZED VIEW mv_alert_dashboard_summary AS
SELECT * FROM v_alert_dashboard_summary;

CREATE UNIQUE INDEX IF NOT EXISTS idx_mv_alert_type
    ON mv_alert_dashboard_summary(alert_type, entity);

-- ---------------------------------------------------------
-- Refresh procedure (run via cron every 30 minutes)
-- ---------------------------------------------------------

CREATE OR REPLACE FUNCTION refresh_otif_materialized_views()
RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_otif_rolling_7d;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_otif_vendor_hierarchy;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_otif_carrier_scorecard;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_alert_dashboard_summary;
END;
$$ LANGUAGE plpgsql;

-- Cron example (requires pg_cron extension):
-- SELECT cron.schedule('refresh-otif-views', '*/30 * * * *',
--     'SELECT refresh_otif_materialized_views();');
