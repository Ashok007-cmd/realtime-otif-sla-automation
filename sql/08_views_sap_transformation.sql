-- =============================================================
-- SAP ERP → Generic DW Transformation Views
-- Maps sap_erp.* tables to generic_dw_tables.* shape so that
-- OTIF views can run against SAP data without schema changes.
-- Compatible with PostgreSQL 13+ only (uses sap_erp schema).
-- =============================================================

-- ---------------------------------------------------------
-- 1. v_sap_customers
-- Maps KNA1 (customer master) → generic customers
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_sap_customers;

CREATE VIEW v_sap_customers AS
SELECT
    kunnr                                          AS customer_code,
    name1                                          AS customer_name,
    COALESCE(regio, 'N/A')                         AS region,
    COALESCE(land1, 'US')                          AS country
FROM sap_erp.kna1;

COMMENT ON VIEW v_sap_customers IS
    'SAP KNA1 mapped to generic customer shape.';

-- ---------------------------------------------------------
-- 2. v_sap_vendors
-- Maps LFA1 (vendor master) → generic vendors
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_sap_vendors;

CREATE VIEW v_sap_vendors AS
SELECT
    lifnr                                          AS vendor_code,
    name1                                          AS vendor_name,
    COALESCE(regio, 'N/A')                         AS region,
    COALESCE(land1, 'US')                          AS country,
    'standard'                                     AS tier
FROM sap_erp.lfa1;

COMMENT ON VIEW v_sap_vendors IS
    'SAP LFA1 mapped to generic vendor shape.';

-- ---------------------------------------------------------
-- 3. v_sap_products
-- Maps MARA (material master) → generic products
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_sap_products;

CREATE VIEW v_sap_products AS
SELECT
    matnr                                          AS sku,
    COALESCE(maktx, matnr)                         AS product_name,
    matkl                                          AS category,
    CASE WHEN meins = '' THEN 'EA' ELSE meins END  AS unit_of_measure
FROM sap_erp.mara;

COMMENT ON VIEW v_sap_products IS
    'SAP MARA mapped to generic product shape.';

-- ---------------------------------------------------------
-- 4. v_sap_orders
-- Maps VBAK (sales header) + KNA1 → generic orders.
-- Vendor assignment is not native to SAP sales docs;
-- this view leaves it for the shipment/link stage.
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_sap_orders;

CREATE VIEW v_sap_orders AS
SELECT
    vbak.vbeln                                    AS order_number,
    vbak.erdat                                    AS order_date,
    COALESCE(vbep.edatu, vbak.erdat)              AS requested_delivery_date,
    vbak.netwr                                    AS total_value,
    vbak.waerk                                    AS currency,
    vbak.vkorg                                    AS sales_org,
    'completed'                                   AS order_status,
    vbak.kunnr                                    AS customer_code
FROM sap_erp.vbak
LEFT JOIN LATERAL (
    SELECT edatu
    FROM sap_erp.vbep
    WHERE vbep.mandt = vbak.mandt
      AND vbep.vbeln = vbak.vbeln
    ORDER BY vbep.etenr
    LIMIT 1
) vbep ON true;

COMMENT ON VIEW v_sap_orders IS
    'SAP VBAK + VBEP mapped to generic order shape.';

-- ---------------------------------------------------------
-- 5. v_sap_order_lines
-- Maps VBAP (sales items) + VBEP (schedule lines) + MARA
-- → generic order_lines.
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_sap_order_lines;

CREATE VIEW v_sap_order_lines AS
SELECT
    vbap.vbeln                                    AS order_number,
    vbap.posnr                                    AS line_number,
    vbap.matnr                                    AS sku,
    vbap.matkl                                    AS category,
    vbap.kwmeng                                   AS ordered_qty,
    COALESCE(vbep.lmeng, vbap.kwmeng)             AS confirmed_qty,
    COALESCE(vbep.wmeng, vbap.kwmeng)             AS delivered_qty,
    'EA'                                          AS unit_of_measure,
    vbap.pmgcn                                    AS partial_delivery_flag
FROM sap_erp.vbap
LEFT JOIN LATERAL (
    SELECT lmeng, wmeng
    FROM sap_erp.vbep
    WHERE vbep.mandt = vbap.mandt
      AND vbep.vbeln = vbap.vbeln
      AND vbep.posnr = vbap.posnr
    ORDER BY vbep.etenr
    LIMIT 1
) vbep ON true;

COMMENT ON VIEW v_sap_order_lines IS
    'SAP VBAP + VBEP mapped to generic order line shape.';

-- ---------------------------------------------------------
-- 6. v_sap_shipments
-- Maps LIKP (delivery header) + VBFA (doc flow) + LFA1
-- → generic shipments. Derives order_number from VBFA.
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_sap_shipments;

CREATE VIEW v_sap_shipments AS
SELECT
    likp.vbeln                                    AS shipment_number,
    vbfa.vbeln_v                                  AS order_number,
    likp.wadat                                    AS planned_ship_date,
    likp.lfdat                                    AS planned_delivery_date,
    likp.wadat_ist                                AS actual_ship_date,
    likp.podat                                    AS actual_delivery_date,
    'delivered'                                   AS shipment_status,
    likp.vstel                                    AS shipping_point,
    likp.route                                    AS route,
    likp.inco1                                    AS incoterm,
    COALESCE(likp.lfart, 'LF')                    AS delivery_type,
    NULL                                          AS carrier_code,
    NULL                                          AS carrier_name,
    NULL                                          AS carrier_mode,
    NULL                                          AS vendor_code,
    NULL                                          AS vendor_region
FROM sap_erp.likp
JOIN sap_erp.vbfa ON vbfa.mandt = likp.mandt
                 AND vbfa.vbeln  = likp.vbeln
                 AND vbfa.vbtyp_n = 'J'
                 AND vbfa.vbtyp_v = 'C'
WHERE likp.podat IS NOT NULL;

COMMENT ON VIEW v_sap_shipments IS
    'SAP LIKP + VBFA mapped to generic shipment shape. Carrier and vendor fields require external mapping.';

-- ---------------------------------------------------------
-- 7. v_sap_delivery_lines
-- Maps LIPS (delivery items) + VBFA + MARA
-- → generic delivery_lines.
-- ---------------------------------------------------------
DROP VIEW IF EXISTS v_sap_delivery_lines;

CREATE VIEW v_sap_delivery_lines AS
SELECT
    lips.vbeln                                    AS shipment_number,
    vbfa.vbeln_v                                  AS order_number,
    lips.posnr                                    AS line_number,
    lips.matnr                                    AS sku,
    lips.lfimg                                    AS delivered_qty,
    0                                             AS damage_qty,
    'EA'                                          AS unit_of_measure
FROM sap_erp.lips
JOIN sap_erp.vbfa ON vbfa.mandt = lips.mandt
                 AND vbfa.vbeln  = lips.vbeln
                 AND vbfa.posnn  = lips.posnr
                 AND vbfa.vbtyp_n = 'J'
                 AND vbfa.vbtyp_v = 'C';

COMMENT ON VIEW v_sap_delivery_lines IS
    'SAP LIPS + VBFA mapped to generic delivery line shape.';
