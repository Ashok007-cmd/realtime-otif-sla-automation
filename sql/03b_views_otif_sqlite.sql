-- =============================================================
-- SQLite-Compatible OTIF Views — Dev / Fast-Iteration Path
-- =============================================================
-- The views in 03_views_otif.sql through 08_views_sap_transformation.sql
-- use PostgreSQL-only syntax (INTERVAL arithmetic, DATE_TRUNC, LATERAL
-- joins, materialized views, RLS) and are NOT portable to SQLite despite
-- earlier comments claiming "SQLite 3.25+" compatibility. Materialized
-- views, RLS, and SAP LATERAL joins are inherently Postgres-only features
-- and are intentionally NOT reproduced here.
--
-- This file provides a portable subset of the core OTIF calculations
-- (base line-level OTIF, 7-day rolling %, alert threshold, consecutive
-- failures) so the SQLite "no license needed" dev path in the setup
-- guide has real, queryable views instead of raw tables only.
--
-- Apply with:
--   sqlite3 data/otif_seed.db < sql/03b_views_otif_sqlite.sql
-- or:
--   make views-sqlite
--
-- Requires SQLite 3.25+ (window function support).
-- =============================================================

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
    CASE
        WHEN s.actual_delivery_date IS NULL THEN 0
        WHEN date(s.actual_delivery_date) <= date(o.requested_delivery_date)
             AND date(s.actual_delivery_date) >= date(o.requested_delivery_date, '-1 day')
        THEN 1
        ELSE 0
    END                                               AS is_on_time,

    CASE
        WHEN dl.delivered_qty IS NULL THEN 0
        WHEN (dl.delivered_qty - COALESCE(dl.damage_qty, 0)) >= ol.ordered_qty THEN 1
        ELSE 0
    END                                               AS is_in_full,

    CASE
        WHEN s.actual_delivery_date IS NULL THEN 0
        WHEN (    date(s.actual_delivery_date) <= date(o.requested_delivery_date)
              AND date(s.actual_delivery_date) >= date(o.requested_delivery_date, '-1 day')
              AND (dl.delivered_qty - COALESCE(dl.damage_qty, 0)) >= ol.ordered_qty)
        THEN 1
        ELSE 0
    END                                               AS is_otif,

    (ol.ordered_qty - COALESCE(dl.delivered_qty, 0)) * ol.unit_price AS backorder_value

FROM shipments s
JOIN orders o                ON o.order_number = s.order_number
JOIN order_lines ol          ON ol.order_number = s.order_number
JOIN delivery_lines dl       ON dl.shipment_number = s.shipment_number
                            AND dl.order_number = s.order_number
                            AND dl.line_number = ol.line_number
WHERE s.actual_delivery_date IS NOT NULL;


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

    ROUND(
        AVG(100.0 * otif_lines / NULLIF(total_lines, 0))
            OVER (
                PARTITION BY vendor_code
                ORDER BY metric_date
                ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
            ), 2
    )                                                                     AS rolling_7d_otif_pct,

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


DROP VIEW IF EXISTS v_consecutive_failures;

CREATE VIEW v_consecutive_failures AS
WITH ranked_deliveries AS (
    SELECT
        vendor_code,
        actual_delivery_date,
        is_otif,
        is_on_time,
        is_in_full,
        shipment_number,
        ROW_NUMBER() OVER (
            PARTITION BY vendor_code
            ORDER BY actual_delivery_date
        ) AS delivery_rank
    FROM v_otif_line_level
    WHERE actual_delivery_date IS NOT NULL
),
failure_streaks AS (
    SELECT
        *,
        LAG(is_otif, 1) OVER (PARTITION BY vendor_code ORDER BY actual_delivery_date) AS prev_otif,
        LAG(is_otif, 2) OVER (PARTITION BY vendor_code ORDER BY actual_delivery_date) AS prev_otif_2,
        LAG(is_otif, 3) OVER (PARTITION BY vendor_code ORDER BY actual_delivery_date) AS prev_otif_3
    FROM ranked_deliveries
)
SELECT
    vendor_code,
    actual_delivery_date,
    delivery_rank,
    is_otif,
    CASE
        WHEN is_otif = 0 AND prev_otif = 0 AND prev_otif_2 = 0 AND prev_otif_3 = 0
            THEN '4+ CONSECUTIVE FAILURES'
        WHEN is_otif = 0 AND prev_otif = 0 AND prev_otif_2 = 0
            THEN '3 CONSECUTIVE FAILURES'
        WHEN is_otif = 0 AND prev_otif = 0
            THEN '2 CONSECUTIVE FAILURES'
        WHEN is_otif = 0
            THEN 'SINGLE FAILURE'
        ELSE 'PASS'
    END AS failure_streak_label,
    CASE
        WHEN is_otif = 0 THEN
            CASE
                WHEN is_on_time = 0 AND is_in_full = 0 THEN 'LATE + SHORT'
                WHEN is_on_time = 0 THEN 'LATE'
                WHEN is_in_full = 0 THEN 'SHORT'
                ELSE 'UNKNOWN'
            END
        ELSE 'NONE'
    END AS failure_reason
FROM failure_streaks
WHERE is_otif = 0
ORDER BY vendor_code, actual_delivery_date DESC;


DROP VIEW IF EXISTS v_alert_otif_below_threshold;

CREATE VIEW v_alert_otif_below_threshold AS
WITH latest AS (
    SELECT
        vendor_code,
        vendor_region,
        metric_date,
        rolling_7d_otif_pct,
        rolling_7d_line_count,
        rolling_7d_backorder_cost,
        ROW_NUMBER() OVER (PARTITION BY vendor_code ORDER BY metric_date DESC) AS rn
    FROM v_otif_rolling_7d
)
SELECT
    vendor_code,
    vendor_region,
    metric_date                                              AS last_metric_date,
    rolling_7d_otif_pct,
    rolling_7d_line_count,
    rolling_7d_backorder_cost,
    92.00                                                    AS sla_threshold,
    ROUND(92.00 - rolling_7d_otif_pct, 2)                    AS gap_to_threshold,
    CASE
        WHEN rolling_7d_otif_pct < 85.00 THEN 'CRITICAL'
        WHEN rolling_7d_otif_pct < 92.00 THEN 'BREACHED'
        ELSE 'WARNING'
    END                                                      AS alert_severity
FROM latest
WHERE rn = 1
  AND rolling_7d_otif_pct < 92.00
ORDER BY gap_to_threshold ASC;
