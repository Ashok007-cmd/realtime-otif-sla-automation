-- =============================================================
-- Advanced Analytics Views
-- Consecutive failure detection, dwell times, running totals,
-- and trend analysis using window functions.
-- All views are deterministic (no CURRENT_DATE/CURRENT_TIMESTAMP)
-- =============================================================

-- ---------------------------------------------------------
-- 1. v_consecutive_failures
-- Detects consecutive delivery failures per vendor using LAG()
-- ---------------------------------------------------------
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
        LAG(is_otif, 1) OVER (
            PARTITION BY vendor_code
            ORDER BY actual_delivery_date
        ) AS prev_otif,
        LAG(is_otif, 2) OVER (
            PARTITION BY vendor_code
            ORDER BY actual_delivery_date
        ) AS prev_otif_2,
        LAG(is_otif, 3) OVER (
            PARTITION BY vendor_code
            ORDER BY actual_delivery_date
        ) AS prev_otif_3
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

COMMENT ON VIEW v_consecutive_failures IS
    'Detects 2+, 3+, and 4+ consecutive delivery failures per vendor using LAG().';


-- ---------------------------------------------------------
-- 2. v_consecutive_failures_lead
-- Uses LEAD() to look ahead — identifies upcoming risk
-- by checking if the NEXT delivery is also likely to fail
-- based on recent patterns. (Companion to the LAG view.)
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_consecutive_failures_lead;

CREATE VIEW v_consecutive_failures_lead AS
WITH base AS (
    SELECT
        vendor_code,
        actual_delivery_date,
        is_otif,
        shipment_number,
        ROW_NUMBER() OVER (
            PARTITION BY vendor_code
            ORDER BY actual_delivery_date
        ) AS delivery_rank
    FROM v_otif_line_level
    WHERE actual_delivery_date IS NOT NULL
),
with_lead AS (
    SELECT
        *,
        LEAD(is_otif, 1) OVER (
            PARTITION BY vendor_code
            ORDER BY actual_delivery_date
        ) AS next_delivery_otif,
        LEAD(is_otif, 2) OVER (
            PARTITION BY vendor_code
            ORDER BY actual_delivery_date
        ) AS next_delivery_2_otif,
        LEAD(is_otif, 3) OVER (
            PARTITION BY vendor_code
            ORDER BY actual_delivery_date
        ) AS next_delivery_3_otif
    FROM base
)
SELECT
    vendor_code,
    actual_delivery_date,
    is_otif,
    next_delivery_otif,
    CASE
        WHEN is_otif = 0 AND next_delivery_otif = 0 THEN 'IMMINENT_STREAK'
        WHEN is_otif = 0 AND next_delivery_otif = 1 THEN 'RECOVERING'
        WHEN is_otif = 1 AND next_delivery_otif = 0 THEN 'IMPENDING_FAILURE'
        ELSE 'STABLE'
    END AS forward_look_status,
    -- If the next 2 deliveries after a current failure also fail, flag high alert
    CASE
        WHEN is_otif = 0 AND next_delivery_otif = 0 AND next_delivery_2_otif = 0
            THEN 'ESCALATE'
        ELSE 'MONITOR'
    END AS escalation_flag
FROM with_lead;

COMMENT ON VIEW v_consecutive_failures_lead IS
    'Uses LEAD() to look ahead and flag impending failure streaks or recovery.';


-- ---------------------------------------------------------
-- 3. v_dwell_times
-- Tracks time elapsed between order processing milestones
-- using LAG() and LEAD() for gate-to-gate analysis.
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_dwell_times;

CREATE VIEW v_dwell_times AS
WITH order_timeline AS (
    SELECT
        o.order_number,
        o.order_date,
        o.requested_delivery_date,
        MIN(s.planned_ship_date)                              AS planned_ship_date,
        MIN(s.actual_ship_date)                               AS actual_ship_date,
        MIN(s.actual_delivery_date)                           AS actual_delivery_date
    FROM orders o
    LEFT JOIN shipments s ON s.order_number = o.order_number
    GROUP BY o.order_number, o.order_date, o.requested_delivery_date
)
SELECT
    order_number,
    order_date,
    requested_delivery_date,
    actual_ship_date,
    actual_delivery_date,

    -- Days from order to actual ship
    CASE
        WHEN actual_ship_date IS NOT NULL AND order_date IS NOT NULL
            THEN (actual_ship_date - order_date)
        ELSE NULL
    END                                                       AS order_to_ship_days,

    -- Days from actual ship to actual delivery
    CASE
        WHEN actual_delivery_date IS NOT NULL AND actual_ship_date IS NOT NULL
            THEN (actual_delivery_date - actual_ship_date)
        ELSE NULL
    END                                                       AS ship_to_delivery_days,

    -- Days from planned ship to actual ship (schedule adherence)
    CASE
        WHEN actual_ship_date IS NOT NULL AND planned_ship_date IS NOT NULL
            THEN (actual_ship_date - planned_ship_date)
        ELSE NULL
    END                                                       AS ship_variance_days,

    -- Days from order to actual delivery (total order-to-delivery)
    CASE
        WHEN actual_delivery_date IS NOT NULL AND order_date IS NOT NULL
            THEN (actual_delivery_date - order_date)
        ELSE NULL
    END                                                       AS total_lead_time_days,

    -- Delayed flag
    CASE
        WHEN actual_delivery_date > requested_delivery_date THEN 1
        ELSE 0
    END                                                       AS is_delayed

FROM order_timeline;

COMMENT ON VIEW v_dwell_times IS
    'Order processing dwell time: order-to-ship, ship-to-delivery, total lead time.';


-- ---------------------------------------------------------
-- 4. v_dwell_time_trends
-- Rolling averages of dwell times using running window
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_dwell_time_trends;

CREATE VIEW v_dwell_time_trends AS
SELECT
    DATE_TRUNC('week', order_date)                            AS order_week,
    COUNT(*)                                                  AS order_count,
    ROUND(AVG(order_to_ship_days), 1)                         AS avg_order_to_ship,
    ROUND(AVG(ship_to_delivery_days), 1)                      AS avg_ship_to_delivery,
    ROUND(AVG(total_lead_time_days), 1)                       AS avg_total_lead_time,
    ROUND(AVG(ship_variance_days), 1)                         AS avg_ship_variance,

    -- 4-week rolling averages
    ROUND(
        AVG(AVG(order_to_ship_days))
            OVER (ORDER BY DATE_TRUNC('week', order_date)
                  ROWS BETWEEN 3 PRECEDING AND CURRENT ROW),
        1
    )                                                          AS rolling_4wk_order_to_ship,

    ROUND(
        AVG(AVG(ship_to_delivery_days))
            OVER (ORDER BY DATE_TRUNC('week', order_date)
                  ROWS BETWEEN 3 PRECEDING AND CURRENT ROW),
        1
    )                                                          AS rolling_4wk_ship_to_delivery,

    -- Delay rate trend
    ROUND(
        100.0 * SUM(is_delayed) / NULLIF(COUNT(*), 0), 1
    )                                                          AS delay_rate_pct

FROM v_dwell_times
GROUP BY DATE_TRUNC('week', order_date)
ORDER BY order_week DESC;

COMMENT ON VIEW v_dwell_time_trends IS
    'Weekly dwell time averages with 4-week rolling trends and delay rate.';


-- ---------------------------------------------------------
-- 5. v_backorder_running_costs
-- Running total of backorder costs using SUM() OVER(...)
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_backorder_running_costs;

CREATE VIEW v_backorder_running_costs AS
WITH base AS (
    SELECT
        bo.backorder_id,
        bo.order_number,
        bo.line_number,
        bo.product_id,
        bo.backorder_qty,
        bo.status,
        bo.created_at                                       AS backorder_date,
        p.unit_price,
        ROUND(bo.backorder_qty * p.unit_price, 2)            AS backorder_cost
    FROM backorders bo
    JOIN delivery_lines dl ON dl.order_number = bo.order_number
                          AND dl.line_number = bo.line_number
    JOIN products p ON p.sku = dl.sku
)
SELECT
    backorder_id,
    order_number,
    line_number,
    product_id,
    backorder_qty,
    backorder_cost,
    backorder_date,
    status,

    -- Running total of open backorder costs over time
    ROUND(
        SUM(CASE WHEN status = 'open' THEN backorder_cost ELSE 0 END)
            OVER (ORDER BY backorder_date
                  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
        2
    )                                                                 AS cumulative_open_cost,

    -- Running total of ALL backorder costs (including fulfilled)
    ROUND(
        SUM(backorder_cost)
            OVER (ORDER BY backorder_date
                  ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW),
        2
    )                                                                 AS cumulative_total_cost,

    -- Daily backorder cost with 7-day rolling sum
    ROUND(
        SUM(backorder_cost)
            OVER (ORDER BY backorder_date
                  ROWS BETWEEN 6 PRECEDING AND CURRENT ROW),
        2
    )                                                                 AS rolling_7d_backorder_cost

FROM base;

COMMENT ON VIEW v_backorder_running_costs IS
    'Backorder costs with cumulative running totals and 7-day rolling window.';


-- ---------------------------------------------------------
-- 6. v_order_state_sequence
-- Tracks chronological sequence of order states using LEAD()
-- to identify abnormal transitions or stalled orders.
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_order_state_sequence;

CREATE VIEW v_order_state_sequence AS
SELECT
    order_number,
    order_status,
    order_date,
    requested_delivery_date,

    -- Previous status in the order lifecycle
    LEAD(order_status) OVER (
        PARTITION BY order_number
        ORDER BY order_date DESC
    ) AS previous_status,

    -- Is this order stalled? (not progressed beyond placed in >14 days)
    CASE
        WHEN order_status IN ('pending', 'confirmed')
             AND order_date < (SELECT max(actual_delivery_date) FROM v_otif_line_level) - INTERVAL '14 days'
        THEN 1
        ELSE 0
    END AS is_stalled,

    -- Rush flag: requested delivery within 3 days of order
    CASE
        WHEN requested_delivery_date - order_date <= 3 THEN 1
        ELSE 0
    END AS is_rush_order

FROM orders;

COMMENT ON VIEW v_order_state_sequence IS
    'Order state sequencing with stall detection and rush order flagging.';
