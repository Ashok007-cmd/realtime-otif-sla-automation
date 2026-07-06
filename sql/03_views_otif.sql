-- =============================================================
-- OTIF Views — Core On-Time In-Full Calculations
-- Uses window functions for rolling metrics
-- Compatible with PostgreSQL 13+ and SQLite 3.25+ (requires
-- window function support). Minor dialect adjustments noted.
-- =============================================================
-- NOTE: All views are deterministic (no CURRENT_DATE/CURRENT_TIMESTAMP)
-- to support materialized views and query plan stability.
-- Anchor windows to max date in v_otif_line_level instead.

-- ---------------------------------------------------------
-- 0. v_otif_date_anchor
-- Single-row anchor for max delivery date — used by all
-- rolling window views to avoid non-deterministic CURRENT_DATE
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_otif_date_anchor;

CREATE VIEW v_otif_date_anchor AS
SELECT
    max(actual_delivery_date) AS max_delivery_date,
    max(actual_delivery_date) - INTERVAL '30 days' AS window_start_30d,
    max(actual_delivery_date) - INTERVAL '90 days' AS window_start_90d,
    max(actual_delivery_date) - INTERVAL '180 days' AS window_start_180d
FROM v_otif_line_level;

COMMENT ON VIEW v_otif_date_anchor IS
    'Deterministic date anchor for rolling window calculations.';


-- ---------------------------------------------------------
-- 1. v_otif_line_level
-- Base view: OTIF flag per delivery line against its order line
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_otif_line_level;

CREATE VIEW v_otif_line_level AS
SELECT
    s.shipment_id,
    s.shipment_number,
    s.order_number,
    s.carrier_code,
    s.carrier_name,
    s.carrier_mode,
    s.vendor_code,
    s.vendor_region,
    s.shipping_point,
    s.route,
    o.order_date,
    o.requested_delivery_date                         AS requested_date,
    s.actual_ship_date,
    s.actual_delivery_date                             AS actual_delivery_date,
    ol.line_number,
    ol.sku,
    ol.category,
    ol.ordered_qty,
    ol.confirmed_qty,
    dl.delivered_qty,
    dl.damage_qty,

    -- Tolerance window: allow 1 day early, 0 days late
    -- (business SLA: must arrive on or before requested date)
    CASE
        WHEN s.actual_delivery_date IS NULL THEN 0
        WHEN s.actual_delivery_date <= o.requested_delivery_date
             AND s.actual_delivery_date >= o.requested_delivery_date - INTERVAL '1 day'
        THEN 1
        ELSE 0
    END                                               AS is_on_time,

    -- In-Full: delivered >= ordered (accounting for damages)
    CASE
        WHEN dl.delivered_qty IS NULL THEN 0
        WHEN (dl.delivered_qty - dl.damage_qty) >= ol.ordered_qty THEN 1
        ELSE 0
    END                                               AS is_in_full,

    -- Composite OTIF
    CASE
        WHEN s.actual_delivery_date IS NULL THEN 0
        WHEN (    (s.actual_delivery_date <= o.requested_delivery_date
               AND s.actual_delivery_date >= o.requested_delivery_date - INTERVAL '1 day')
              AND (dl.delivered_qty - COALESCE(dl.damage_qty, 0)) >= ol.ordered_qty)
        THEN 1
        ELSE 0
    END                                               AS is_otif,

    -- Monetary impact
    (ol.ordered_qty - COALESCE(dl.delivered_qty, 0)) * ol.unit_price AS backorder_value

FROM shipments s
JOIN orders o                ON o.order_number = s.order_number
JOIN order_lines ol          ON ol.order_number = s.order_number
JOIN delivery_lines dl       ON dl.shipment_number = s.shipment_number
                            AND dl.order_number = s.order_number
                            AND dl.line_number = ol.line_number
WHERE s.actual_delivery_date IS NOT NULL;

COMMENT ON VIEW v_otif_line_level IS
    'Per-delivery-line OTIF calculation with tolerances. Used by all downstream views.';


-- ---------------------------------------------------------
-- 2. v_otif_rolling_7d
-- 7-day rolling OTIF percentage per vendor
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_otif_rolling_7d;

CREATE VIEW v_otif_rolling_7d AS
WITH daily_otif AS (
    SELECT
        vendor_code,
        vendor_region,
        actual_delivery_date                             AS metric_date,
        COUNT(*)                                         AS total_lines,
        SUM(is_on_time)                                  AS on_time_lines,
        SUM(is_in_full)                                  AS in_full_lines,
        SUM(is_otif)                                     AS otif_lines,
        SUM(backorder_value)                             AS backorder_value_total
    FROM v_otif_line_level
    CROSS JOIN v_otif_date_anchor a
    WHERE actual_delivery_date >= a.window_start_90d
    GROUP BY vendor_code, vendor_region, actual_delivery_date
)
SELECT
    vendor_code,
    vendor_region,
    metric_date,
    total_lines,
    on_time_lines,
    in_full_lines,
    otif_lines,
    ROUND(100.0 * otif_lines / NULLIF(total_lines, 0), 2)                AS otif_pct,
    ROUND(100.0 * on_time_lines / NULLIF(total_lines, 0), 2)             AS on_time_pct,
    ROUND(100.0 * in_full_lines / NULLIF(total_lines, 0), 2)             AS in_full_pct,

    -- 7-day rolling OTIF
    ROUND(
        AVG(100.0 * otif_lines / NULLIF(total_lines, 0))
            OVER (
                PARTITION BY vendor_code
                ORDER BY metric_date
                ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
            ), 2
    )                                                                     AS rolling_7d_otif_pct,

    -- 7-day rolling line count
    SUM(total_lines)
        OVER (
            PARTITION BY vendor_code
            ORDER BY metric_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        )                                                                 AS rolling_7d_line_count,

    ROUND(SUM(backorder_value_total)
        OVER (
            PARTITION BY vendor_code
            ORDER BY metric_date
            ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
        ), 2)                                                             AS rolling_7d_backorder_cost

FROM daily_otif;

COMMENT ON VIEW v_otif_rolling_7d IS
    'Daily OTIF with 7-day rolling average per vendor.';


-- ---------------------------------------------------------
-- 3. v_otif_rolling_30d
-- 30-day rolling OTIF percentage per vendor
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_otif_rolling_30d;

CREATE VIEW v_otif_rolling_30d AS
WITH daily_otif AS (
    SELECT
        vendor_code,
        vendor_region,
        metric_date,
        total_lines,
        otif_lines,
        on_time_lines,
        in_full_lines,
        backorder_value_total
    FROM v_otif_rolling_7d
)
SELECT
    vendor_code,
    vendor_region,
    metric_date,
    total_lines,
    otif_lines,
    on_time_lines,
    in_full_lines,
    ROUND(100.0 * otif_lines / NULLIF(total_lines, 0), 2)                AS otif_pct,
    ROUND(100.0 * on_time_lines / NULLIF(total_lines, 0), 2)             AS on_time_pct,
    ROUND(100.0 * in_full_lines / NULLIF(total_lines, 0), 2)             AS in_full_pct,

    -- 30-day rolling OTIF
    ROUND(
        AVG(100.0 * otif_lines / NULLIF(total_lines, 0))
            OVER (
                PARTITION BY vendor_code
                ORDER BY metric_date
                ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
            ), 2
    )                                                                     AS rolling_30d_otif_pct,

    SUM(total_lines)
        OVER (
            PARTITION BY vendor_code
            ORDER BY metric_date
            ROWS BETWEEN 29 PRECEDING AND CURRENT ROW
        )                                                                 AS rolling_30d_line_count

FROM daily_otif;

COMMENT ON VIEW v_otif_rolling_30d IS
    'Daily OTIF with 30-day rolling average per vendor.';


-- ---------------------------------------------------------
-- 4. v_otif_vendor_hierarchy
-- Vendor performance rolled up by tier and region
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_otif_vendor_hierarchy;

CREATE VIEW v_otif_vendor_hierarchy AS
WITH vendor_metrics AS (
    SELECT
        v.vendor_code,
        v.vendor_name,
        v.region                                               AS vendor_region,
        v.tier,
        COALESCE(SUM(ol.ordered_qty), 0)                        AS total_ordered_qty,
        COALESCE(SUM(dl.delivered_qty), 0)                      AS total_delivered_qty,
        COUNT(DISTINCT s.shipment_id)                           AS total_shipments,
        COUNT(DISTINCT o.order_number)                          AS total_orders,
        COALESCE(SUM(v_ll.is_otif), 0)                          AS otif_pass_count,
        COUNT(v_ll.is_otif)                                     AS total_otif_lines
    FROM vendors v
    LEFT JOIN shipments s          ON s.vendor_code = v.vendor_code
    LEFT JOIN orders o             ON o.order_number = s.order_number
    LEFT JOIN order_lines ol       ON ol.order_number = o.order_number
    LEFT JOIN delivery_lines dl    ON dl.shipment_number = s.shipment_number
    LEFT JOIN v_otif_line_level v_ll ON v_ll.shipment_id = s.shipment_id
    GROUP BY v.vendor_code, v.vendor_name, v.region, v.tier
)
SELECT
    vendor_code,
    vendor_name,
    vendor_region,
    tier,
    total_ordered_qty,
    total_delivered_qty,
    total_shipments,
    total_orders,
    ROUND(100.0 * otif_pass_count / NULLIF(total_otif_lines, 0), 2) AS overall_otif_pct,

    -- Rank vendors by OTIF within their region.
    -- NULLS LAST is explicit: Postgres defaults DESC to NULLS FIRST, which
    -- would rank vendors with zero deliveries (NULL pct) as #1 in their
    -- region ahead of vendors with real, measured performance.
    ROW_NUMBER() OVER (
        PARTITION BY vendor_region
        ORDER BY 100.0 * otif_pass_count / NULLIF(total_otif_lines, 0) DESC NULLS LAST
    )                                                        AS rank_in_region,

    -- SLA classification
    CASE
        WHEN 100.0 * otif_pass_count / NULLIF(total_otif_lines, 0) >= 95 THEN 'EXCEEDING'
        WHEN 100.0 * otif_pass_count / NULLIF(total_otif_lines, 0) >= 92 THEN 'MEETING'
        WHEN 100.0 * otif_pass_count / NULLIF(total_otif_lines, 0) >= 85 THEN 'AT_RISK'
        ELSE 'CRITICAL'
    END                                                      AS sla_status
FROM vendor_metrics;

COMMENT ON VIEW v_otif_vendor_hierarchy IS
    'Vendor performance summary with OTIF scores, region ranking, and SLA classification.';


-- ---------------------------------------------------------
-- 5. v_otif_geographic
-- OTIF performance by shipping point and region
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_otif_geographic;

CREATE VIEW v_otif_geographic AS
SELECT
    s.shipping_point,
    s.vendor_region,
    s.carrier_mode,
    COUNT(*)                                              AS total_lines,
    SUM(v_ll.is_otif)                                     AS otif_pass_count,
    SUM(v_ll.is_on_time)                                  AS on_time_count,
    SUM(v_ll.is_in_full)                                  AS in_full_count,
    ROUND(100.0 * SUM(v_ll.is_otif) / NULLIF(COUNT(*), 0), 2)   AS otif_pct,
    ROUND(100.0 * SUM(v_ll.is_on_time) / NULLIF(COUNT(*), 0), 2) AS on_time_pct,
    ROUND(100.0 * SUM(v_ll.is_in_full) / NULLIF(COUNT(*), 0), 2) AS in_full_pct,

    -- Rank regions by OTIF (NULLS LAST: see note in v_otif_vendor_hierarchy)
    ROW_NUMBER() OVER (
        ORDER BY 100.0 * SUM(v_ll.is_otif) / NULLIF(COUNT(*), 0) DESC NULLS LAST
    )                                                     AS rank

FROM v_otif_line_level v_ll
JOIN shipments s ON s.shipment_id = v_ll.shipment_id
GROUP BY s.shipping_point, s.vendor_region, s.carrier_mode;

COMMENT ON VIEW v_otif_geographic IS
    'OTIF performance aggregated by shipping point, region, and carrier mode.';


-- ---------------------------------------------------------
-- 6. v_otif_carrier_scorecard
-- Carrier-level rolling OTIF
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_otif_carrier_scorecard;

CREATE VIEW v_otif_carrier_scorecard AS
WITH weekly_carrier AS (
    SELECT
        carrier_code,
        carrier_name,
        carrier_mode,
        DATE_TRUNC('week', actual_delivery_date)          AS delivery_week,
        COUNT(*)                                          AS total_deliveries,
        SUM(is_on_time)                                   AS on_time_count,
        SUM(is_otif)                                      AS otif_count
    FROM v_otif_line_level
    CROSS JOIN v_otif_date_anchor a
    WHERE actual_delivery_date IS NOT NULL
      AND actual_delivery_date >= a.window_start_180d
    GROUP BY carrier_code, carrier_name, carrier_mode,
             DATE_TRUNC('week', actual_delivery_date)
)
SELECT
    carrier_code,
    carrier_name,
    carrier_mode,
    delivery_week,
    total_deliveries,
    on_time_count,
    ROUND(100.0 * on_time_count / NULLIF(total_deliveries, 0), 2) AS on_time_pct,

    -- 4-week rolling on-time percentage
    ROUND(
        AVG(100.0 * on_time_count / NULLIF(total_deliveries, 0))
            OVER (
                PARTITION BY carrier_code
                ORDER BY delivery_week
                ROWS BETWEEN 3 PRECEDING AND CURRENT ROW
            ), 2
    )                                                     AS rolling_4wk_on_time_pct

FROM weekly_carrier;

COMMENT ON VIEW v_otif_carrier_scorecard IS
    'Weekly carrier on-time performance with 4-week rolling average.';
