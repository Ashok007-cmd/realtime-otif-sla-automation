# Power BI Dashboard Layout — OTIF Real-Time Monitoring

## Overview

A 6-tile main dashboard plus a secondary detail page. Designed at 1920×1080 resolution for wall-mounted logistics center displays and desktop consumption.

---

## Page 1: Executive OTIF Overview (Main Dashboard)

### Top Row — KPI Bar (full-width, 160px height)

| # | Visual Type | Data | Notes |
|---|-------------|------|-------|
| 1.1 | **Card** | `OTIF %` formatted as percentage | Conditional formatting: green (≥95%), yellow (≥92%), red (<92%) |
| 1.2 | **Card** | `7D Rolling OTIF %` | The primary SLA metric; triggers alerts |
| 1.3 | **Card** | `Total Open Backorder Cost` | Currency format $K |
| 1.4 | **Card** | `Total Delivery Lines` today | Count of lines delivered today |
| 1.5 | **Card** | `Avg Total Lead Time Days` | Rounded to 1 decimal |

**Conditional formatting on cards:**
- OTIF %: `#27AE60` (green) if ≥ 95%, `#F39C12` (amber) if ≥ 92%, `#E74C3C` (red) if < 92%
- Backorder Cost: green if < $10K, amber if < $50K, red if ≥ $50K

### Middle Row — Charts (2×2 grid)

| # | Visual Type | Data | Filters |
|---|-------------|------|---------|
| 2.1 | **Line & Clustered Column Chart** | Columns: daily deliveries; Line: `7D Rolling OTIF %` with SLA threshold line at 92% | Last 90 days X-axis |
| 2.2 | **Heatmap Matrix** (table with conditional formatting) | Rows: vendor name; Columns: delivery week; Values: `7D Rolling OTIF %` | Top 15 vendors by volume |
| 2.3 | **Gauge** | `7D Rolling OTIF %` with Target=92%, Max=100% | Current vendor in scope |
| 2.4 | **Treemap** | Area: `Total Open Backorder Cost` by vendor | Only open backorders |

### Bottom Row — Detail Grids (2×2 grid)

| # | Visual Type | Data | Notes |
|---|-------------|------|-------|
| 3.1 | **Table** | Vendor: vendor_code, 7D OTIF %, Total Lines, SLA Status, Consecutive Failures | Sorted by OTIF asc (worst first). Row-level conditional formatting |
| 3.2 | **Table** | Carrier: carrier_code, On Time %, Total Deliveries, Mode | Sorted by On Time % asc |
| 3.3 | **Bar Chart** | `7D Rolling OTIF %` by region (NE, SE, MW, WC, SW) | Horizontal bars |
| 3.4 | **Donut Chart** | Active alerts by severity (Critical, Breached, Warning) from `v_alert_dashboard_summary` | Only last 7 days |

### Slicers (top ribbon, collapsed when not in use)

| Slicer | Type | Default |
|--------|------|---------|
| Date range | Relative date slicer | Last 90 days |
| Vendor | Dropdown | All |
| Region | Dropdown | All |
| Carrier | Dropdown | All |
| SLA Status | Dropdown | All |

---

## Page 2: Vendor Deep Dive

### Left Panel
- **Vendor profile card**: vendor name, tier, region, overall OTIF %
- **Gauge**: `7D Rolling OTIF %` vs 92% SLA target
- **Table**: Recent deliveries (last 30) with per-line OTIF flags and reasons

### Right Panel
- **Line chart**: OTIF % trend over last 6 months
- **Waterfall chart**: Breakdown of on-time vs in-full failures
- **Matrix**: Consecutive failure history with dates and reasons (from `v_consecutive_failures`)

---

## Page 3: Backorder Analysis

- **Table**: All open backorders with vendor, SKU, qty, cost, est. fill date
- **Area chart**: Running cumulative backorder cost over time
- **Card**: Days to fill (average open backorder age)
- **Slicers**: Status, Vendor, Date range

---

## Data Model Relationships

```
orders (order_number) ────1:N──── order_lines (order_number)
orders (order_number) ────1:N──── shipments (order_number)
shipments (shipment_number) ──1:N── delivery_lines (shipment_number)
order_lines (order_number, line_number) ──1:1── delivery_lines (order_number, line_number)
backorders (order_number, line_number) ──1:1── order_lines
```

## Power Query Notes

1. **Date table**: Generate using `CALENDAR(MIN(shipments[actual_delivery_date]), MAX(shipments[actual_delivery_date]))`
2. **Relationships**: Set as single-direction filters from dimensions to facts
3. **Refresh**: Configure scheduled refresh (every 30 min recommended for real-time monitoring)
