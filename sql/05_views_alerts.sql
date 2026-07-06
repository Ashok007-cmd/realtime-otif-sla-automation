-- =============================================================
-- Alert-Triggering Views
-- These views power Power BI data-driven alerts. Each returns
-- rows only when a threshold is breached, making them ideal
-- for "is any row returned?" alert conditions.
-- =============================================================

-- ---------------------------------------------------------
-- 1. v_alert_otif_below_threshold
-- Alerts when rolling 7-day OTIF drops below 92% SLA threshold
-- ---------------------------------------------------------
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
        ROW_NUMBER() OVER (
            PARTITION BY vendor_code
            ORDER BY metric_date DESC
        ) AS rn
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
    END                                                      AS alert_severity,
    (SELECT max_delivery_date FROM v_otif_date_anchor)       AS alert_generated_at
FROM latest
WHERE rn = 1
  AND rolling_7d_otif_pct < 92.00
ORDER BY gap_to_threshold ASC;

COMMENT ON VIEW v_alert_otif_below_threshold IS
    'Alerts vendors whose 7-day rolling OTIF has dropped below 92% SLA threshold.';


-- ---------------------------------------------------------
-- 2. v_alert_backorder_threshold
-- Alerts when open backorder costs exceed financial threshold
-- (default: $10,000 vendor-level, $50,000 aggregate)
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_alert_backorder_threshold;

CREATE VIEW v_alert_backorder_threshold AS
WITH vendor_backorder_total AS (
    SELECT
        s.vendor_code,
        SUM(bo.backorder_qty * p.unit_price) AS total_open_backorder_cost,
        COUNT(DISTINCT bo.backorder_id)      AS open_backorder_count,
        MAX(bo.created_at)                   AS latest_backorder_date
    FROM backorders bo
    JOIN delivery_lines dl ON dl.order_number = bo.order_number
                          AND dl.line_number = bo.line_number
    JOIN products p ON p.sku = dl.sku
    JOIN shipments s ON s.order_number = bo.order_number
    WHERE bo.status = 'open'
    GROUP BY s.vendor_code
)
SELECT
    vendor_code,
    ROUND(total_open_backorder_cost, 2)                      AS total_open_backorder_cost,
    open_backorder_count,
    latest_backorder_date,
    10000.00                                                 AS vendor_threshold,
    50000.00                                                 AS aggregate_threshold,
    CASE
        WHEN total_open_backorder_cost >= 50000.00 THEN 'CRITICAL'
        WHEN total_open_backorder_cost >= 10000.00 THEN 'EXCEEDED'
        ELSE 'WITHIN_LIMITS'
    END                                                      AS alert_severity,
    CASE
        WHEN total_open_backorder_cost >= 50000.00 THEN 'Aggregate backorder cost exceeds $50K'
        WHEN total_open_backorder_cost >= 10000.00 THEN 'Vendor backorder cost exceeds $10K'
        ELSE 'NONE'
    END                                                      AS alert_reason,
    latest_backorder_date                                    AS alert_generated_at
FROM vendor_backorder_total
WHERE total_open_backorder_cost >= 10000.00
ORDER BY total_open_backorder_cost DESC;

COMMENT ON VIEW v_alert_backorder_threshold IS
    'Alerts when vendor open backorder costs exceed $10K or aggregate exceeds $50K.';


-- ---------------------------------------------------------
-- 3. v_alert_consecutive_failures
-- Alerts when a vendor has 3+ consecutive OTIF failures
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_alert_consecutive_failures;

CREATE VIEW v_alert_consecutive_failures AS
SELECT
    vendor_code,
    actual_delivery_date,
    delivery_rank,
    failure_streak_label,
    failure_reason,
    CASE
        WHEN failure_streak_label LIKE '4+%' THEN 'CRITICAL'
        WHEN failure_streak_label LIKE '3 %' THEN 'HIGH'
        WHEN failure_streak_label LIKE '2 %' THEN 'WARNING'
        ELSE 'INFO'
    END                                                      AS alert_severity,
    actual_delivery_date                                     AS alert_generated_at
FROM v_consecutive_failures
WHERE failure_streak_label IN ('3 CONSECUTIVE FAILURES', '4+ CONSECUTIVE FAILURES')
ORDER BY actual_delivery_date DESC;

COMMENT ON VIEW v_alert_consecutive_failures IS
    'Alerts when a vendor has 3 or more consecutive OTIF failures.';


-- ---------------------------------------------------------
-- 4. v_alert_carrier_performance
-- Alerts when a carrier's 4-week rolling on-time rate drops
-- below 85%
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_alert_carrier_performance;

CREATE VIEW v_alert_carrier_performance AS
WITH latest_carrier AS (
    SELECT
        carrier_code,
        carrier_name,
        carrier_mode,
        delivery_week,
        rolling_4wk_on_time_pct,
        ROW_NUMBER() OVER (
            PARTITION BY carrier_code
            ORDER BY delivery_week DESC
        ) AS rn
    FROM v_otif_carrier_scorecard
)
SELECT
    carrier_code,
    carrier_name,
    carrier_mode,
    delivery_week,
    rolling_4wk_on_time_pct,
    85.00                                                    AS carrier_sla_threshold,
    CASE
        WHEN rolling_4wk_on_time_pct < 80.00 THEN 'CRITICAL'
        WHEN rolling_4wk_on_time_pct < 85.00 THEN 'BREACHED'
        ELSE 'WARNING'
    END                                                      AS alert_severity,
    (SELECT max_delivery_date FROM v_otif_date_anchor)       AS alert_generated_at
FROM latest_carrier
WHERE rn = 1
  AND rolling_4wk_on_time_pct < 85.00
ORDER BY rolling_4wk_on_time_pct ASC;

COMMENT ON VIEW v_alert_carrier_performance IS
    'Alerts when a carrier 4-week rolling on-time rate drops below 85%.';


-- ---------------------------------------------------------
-- 5. v_alert_dwell_time_spike
-- Alerts when average dwell times spike significantly
-- (week-over-week increase > 50%)
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_alert_dwell_time_spike;

CREATE VIEW v_alert_dwell_time_spike AS
WITH weekly AS (
    SELECT
        order_week,
        avg_total_lead_time,
        avg_order_to_ship,
        avg_ship_to_delivery,
        LAG(avg_total_lead_time, 1) OVER (ORDER BY order_week) AS prev_avg_lead_time,
        LAG(avg_order_to_ship, 1) OVER (ORDER BY order_week) AS prev_avg_order_to_ship
    FROM v_dwell_time_trends
)
SELECT
    order_week,
    ROUND(avg_total_lead_time, 1)                              AS avg_total_lead_time,
    ROUND(avg_order_to_ship, 1)                                AS avg_order_to_ship,
    ROUND(avg_ship_to_delivery, 1)                             AS avg_ship_to_delivery,
    ROUND(prev_avg_lead_time, 1)                               AS prev_avg_lead_time,
    CASE
        WHEN prev_avg_lead_time > 0
            THEN ROUND(100.0 * (avg_total_lead_time - prev_avg_lead_time) / prev_avg_lead_time, 1)
        ELSE 0
    END                                                         AS lead_time_wow_pct_change,
    CASE
        WHEN prev_avg_lead_time > 0
             AND (avg_total_lead_time - prev_avg_lead_time) / prev_avg_lead_time > 0.50
            THEN 'SPIKE_DETECTED'
        ELSE 'NORMAL'
    END                                                         AS lead_time_alert,
    (SELECT max_delivery_date FROM v_otif_date_anchor)           AS alert_generated_at
FROM weekly
CROSS JOIN v_otif_date_anchor a
WHERE order_week >= a.window_start_30d
  AND prev_avg_lead_time > 0
  AND (avg_total_lead_time - prev_avg_lead_time) / prev_avg_lead_time > 0.50
ORDER BY order_week DESC;

COMMENT ON VIEW v_alert_dwell_time_spike IS
    'Alerts when weekly average lead time spikes more than 50% week-over-week.';


-- ---------------------------------------------------------
-- 6. v_alert_dashboard_summary
-- Master alert summary view — consolidates all alert types
-- for a single Power BI alert data source
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_alert_dashboard_summary;

CREATE VIEW v_alert_dashboard_summary AS
SELECT
    'OTIF_THRESHOLD'                                         AS alert_type,
    vendor_code                                              AS entity,
    alert_severity,
    rolling_7d_otif_pct                                      AS metric_value,
    sla_threshold,
    gap_to_threshold,
    last_metric_date                                         AS event_date,
    alert_generated_at,
    'Rolling 7-day OTIF below 92% SLA'                       AS alert_description
FROM v_alert_otif_below_threshold

UNION ALL

SELECT
    'BACKORDER_COST',
    vendor_code,
    alert_severity,
    total_open_backorder_cost,
    vendor_threshold,
    total_open_backorder_cost - vendor_threshold,
    latest_backorder_date,
    alert_generated_at,
    alert_reason
FROM v_alert_backorder_threshold

UNION ALL

SELECT
    'CONSECUTIVE_FAILURES',
    vendor_code,
    alert_severity,
    delivery_rank,
    0,
    0,
    actual_delivery_date,
    alert_generated_at,
    failure_streak_label || ': ' || failure_reason
FROM v_alert_consecutive_failures

UNION ALL

SELECT
    'CARRIER_PERFORMANCE',
    carrier_code,
    alert_severity,
    rolling_4wk_on_time_pct,
    carrier_sla_threshold,
    carrier_sla_threshold - rolling_4wk_on_time_pct,
    delivery_week,
    alert_generated_at,
    carrier_name || ' (' || carrier_mode || ') below carrier SLA'
FROM v_alert_carrier_performance

UNION ALL

SELECT
    'DWELL_TIME_SPIKE',
    'GLOBAL',
    'WARNING',
    avg_total_lead_time,
    prev_avg_lead_time,
    lead_time_wow_pct_change,
    order_week,
    alert_generated_at,
    'Lead time spike: ' || lead_time_wow_pct_change || '% week-over-week'
FROM v_alert_dwell_time_spike;

COMMENT ON VIEW v_alert_dashboard_summary IS
    'Unified alert view for Power BI data-driven alert integration. All alert types in one place.';
