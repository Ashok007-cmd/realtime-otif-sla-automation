-- =============================================================
-- SAP ERP-Style Schema for OTIF Monitoring
-- Simulates VBAK, VBAP, VBEP, LIKP, LIPS tables
-- Compatible with PostgreSQL 13+
-- =============================================================

CREATE SCHEMA IF NOT EXISTS sap_erp;

-- ---------------------------------------------------------
-- 1. Customer Master
-- ---------------------------------------------------------
CREATE TABLE sap_erp.kna1 (
    mandt     INT          NOT NULL DEFAULT 100,
    kunnr     VARCHAR(10)  NOT NULL,
    name1     VARCHAR(35)  NOT NULL,
    ort01     VARCHAR(35),
    regio     VARCHAR(3),
    land1     CHAR(3)      DEFAULT 'US',
    PRIMARY KEY (mandt, kunnr)
);

-- ---------------------------------------------------------
-- 2. Vendor / Supplier Master
-- ---------------------------------------------------------
CREATE TABLE sap_erp.lfa1 (
    mandt     INT          NOT NULL DEFAULT 100,
    lifnr     VARCHAR(10)  NOT NULL,
    name1     VARCHAR(35)  NOT NULL,
    regio     VARCHAR(3),
    land1     CHAR(3)      DEFAULT 'US',
    PRIMARY KEY (mandt, lifnr)
);

-- ---------------------------------------------------------
-- 3. Material Master
-- ---------------------------------------------------------
CREATE TABLE sap_erp.mara (
    mandt     INT          NOT NULL DEFAULT 100,
    matnr     VARCHAR(18)  NOT NULL,
    maktx     VARCHAR(40),
    meins     VARCHAR(3)   DEFAULT 'EA',
    mtart     VARCHAR(4),
    matkl     VARCHAR(9),
    PRIMARY KEY (mandt, matnr)
);

-- ---------------------------------------------------------
-- 4. Sales Document Header (Orders)
-- ---------------------------------------------------------
CREATE TABLE sap_erp.vbak (
    mandt     INT          NOT NULL DEFAULT 100,
    vbeln     VARCHAR(10)  NOT NULL,
    erdat     DATE         NOT NULL,
    erzet     TIME,
    audat     DATE,                        -- pricing/document date
    vkorg     VARCHAR(4),                  -- sales organization
    vtweg     VARCHAR(2),                  -- distribution channel
    spart     VARCHAR(2),                  -- division
    kunnr     VARCHAR(10),                 -- sold-to party
    kunwe     VARCHAR(10),                 -- ship-to party
    kunag     VARCHAR(10),                 -- payer
    vbtyp     CHAR(1)      DEFAULT 'C',    -- C = order
    auart     VARCHAR(4)   DEFAULT 'OR',   -- order type
    netwr     DECIMAL(15,2),               -- net value
    waerk     VARCHAR(3)   DEFAULT 'USD',
    PRIMARY KEY (mandt, vbeln)
);

-- ---------------------------------------------------------
-- 5. Sales Document Items
-- ---------------------------------------------------------
CREATE TABLE sap_erp.vbap (
    mandt     INT          NOT NULL DEFAULT 100,
    vbeln     VARCHAR(10)  NOT NULL,
    posnr     NUMERIC(6)   NOT NULL,
    matnr     VARCHAR(18),
    matkl     VARCHAR(9),
    kwmeng    DECIMAL(15,3) NOT NULL,       -- order qty
    vrkme     VARCHAR(3)   DEFAULT 'EA',
    meins     VARCHAR(3)   DEFAULT 'EA',
    netwr     DECIMAL(15,2),
    pmgcn     CHAR(1)      DEFAULT '',      -- partial delivery (blank=allowed, X=not allowed)
    werks     VARCHAR(4),                    -- plant
    PRIMARY KEY (mandt, vbeln, posnr)
);

-- ---------------------------------------------------------
-- 6. Schedule Line Data
-- ---------------------------------------------------------
CREATE TABLE sap_erp.vbep (
    mandt     INT          NOT NULL DEFAULT 100,
    vbeln     VARCHAR(10)  NOT NULL,
    posnr     NUMERIC(6)   NOT NULL,
    etenr     NUMERIC(4)   NOT NULL,
    edatu     DATE         NOT NULL,         -- requested delivery date
    ezeit     TIME,
    wmeng     DECIMAL(15,3),                 -- ordered qty in sales units
    lmeng     DECIMAL(15,3),                 -- confirmed qty
    bmeng     DECIMAL(15,3),                 -- cumulative delivered qty
    PRIMARY KEY (mandt, vbeln, posnr, etenr)
);

-- ---------------------------------------------------------
-- 7. Delivery Header
-- ---------------------------------------------------------
CREATE TABLE sap_erp.likp (
    mandt     INT          NOT NULL DEFAULT 100,
    vbeln     VARCHAR(10)  NOT NULL,
    erdat     DATE,
    erzet     TIME,
    lfdat     DATE,                          -- planned delivery date
    wadat     DATE,                          -- planned goods movement date
    wadat_ist DATE,                          -- actual goods movement date (PGI)
    lfuhr     TIME,
    podat     DATE,                          -- proof of delivery date
    potim     TIME,
    vstel     VARCHAR(4),                    -- shipping point
    vkorg     VARCHAR(4),
    kunnr     VARCHAR(10),                   -- customer
    kunwe     VARCHAR(10),                   -- ship-to party
    lfart     VARCHAR(4)  DEFAULT 'LF',      -- delivery type
    route     VARCHAR(6),                    -- route
    inco1     VARCHAR(3),                    -- incoterms
    vsart     VARCHAR(2),                    -- shipping condition
    PRIMARY KEY (mandt, vbeln)
);

-- ---------------------------------------------------------
-- 8. Delivery Item Data
-- ---------------------------------------------------------
CREATE TABLE sap_erp.lips (
    mandt     INT          NOT NULL DEFAULT 100,
    vbeln     VARCHAR(10)  NOT NULL,
    posnr     NUMERIC(6)   NOT NULL,
    matnr     VARCHAR(18),
    matkl     VARCHAR(9),
    lfimg     DECIMAL(15,3),                 -- actual delivered qty
    vrkme     VARCHAR(3)   DEFAULT 'EA',
    pstyv     VARCHAR(4),                    -- item category
    vgbel     VARCHAR(10),                   -- reference document (order#)
    vgpos     NUMERIC(6),                    -- reference item
    uepos     NUMERIC(6),                    -- higher-level item
    werks     VARCHAR(4),                    -- plant
    PRIMARY KEY (mandt, vbeln, posnr)
);

-- ---------------------------------------------------------
-- 9. Document Flow
-- ---------------------------------------------------------
CREATE TABLE sap_erp.vbfa (
    mandt     INT          NOT NULL DEFAULT 100,
    vbeln     VARCHAR(10)  NOT NULL,          -- subsequent doc
    posnn     NUMERIC(6)   NOT NULL,
    vbeln_v   VARCHAR(10),                    -- preceding doc
    posnv     NUMERIC(6),                     -- preceding item
    vbtyp_n   VARCHAR(1),                     -- subsequent doc category
    vbtyp_v   VARCHAR(1),                     -- preceding doc category
    rfmng     DECIMAL(15,3),                  -- reference qty
    PRIMARY KEY (mandt, vbeln, posnn)
);

-- ---------------------------------------------------------
-- Indexes for performance
-- ---------------------------------------------------------
CREATE INDEX idx_vbap_order   ON sap_erp.vbap (mandt, vbeln);
CREATE INDEX idx_vbep_line    ON sap_erp.vbep (mandt, vbeln, posnr);
CREATE INDEX idx_lips_vgbel   ON sap_erp.lips (mandt, vgbel);
CREATE INDEX idx_lips_vbeln   ON sap_erp.lips (mandt, vbeln);
CREATE INDEX idx_likp_wadat   ON sap_erp.likp (mandt, wadat_ist);
CREATE INDEX idx_vbfa_chain   ON sap_erp.vbfa (mandt, vbeln_v, vbtyp_v, vbtyp_n);
