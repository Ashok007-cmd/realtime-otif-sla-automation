# Thresholds Reference — OTIF SLA Configuration

## Core OTIF Metrics

| Metric | Calculation | Target | Measurement |
|--------|-------------|--------|-------------|
| **On-Time** | `delivery_date <= requested_date AND delivery_date >= requested_date - 1` | ≥ 95% | Per line item |
| **In-Full** | `qty_delivered - qty_damaged >= qty_ordered` | ≥ 98% | Per line item |
| **OTIF** | On-Time AND In-Full (same line) | ≥ 92% | Per line item |
| **On-Time (early tolerance)** | `requested_date - 1 day` | Maximum 1 day early | 0 days late |

## SLA Thresholds

| Threshold | Value | Scope | Behavior |
|-----------|-------|-------|----------|
| **OTIF Rolling 7-Day** | 92% | All vendors | Warning < 92%, Breached < 88%, Critical < 85% |
| **OTIF Rolling 30-Day** | 92% | All vendors | Trending indicator only |
| **Carrier On-Time** | 85% | Per carrier | Below triggers carrier-level alert |
| **Vendor Consecutive Failures** | 3 | Per vendor | ≥3 triggers escalation review |
| **Backorder — Vendor Level** | $10,000 | Per vendor | Single vendor exceeding threshold |
| **Backorder — Aggregate** | $50,000 | All vendors | Total backorder across all vendors |

## Alert Severity Levels

| Level | Condition | Notification Channels | Response Time |
|-------|-----------|---------------------|---------------|
| **Critical** | OTIF < 85% OR Backorder > $50K OR 5+ consecutive failures | Teams + Email + Slack | Immediate |
| **Breached** | OTIF 85%–92% OR Backorder > $10K OR 3–4 consecutive failures | Teams + Email | 2 hours |
| **Warning** | OTIF > 92% but trending down (WoW decline > 5%) | Email only | End of day |

## Rolling Window Definitions

| Window | SQL Frame | Use |
|--------|-----------|-----|
| **7-Day Rolling** | `ROWS BETWEEN 6 PRECEDING AND CURRENT ROW` | Short-term SLA monitoring |
| **30-Day Rolling** | `ROWS BETWEEN 29 PRECEDING AND CURRENT ROW` | Medium-term trend |
| **4-Week Rolling (dwell)** | `ROWS BETWEEN 27 PRECEDING AND CURRENT ROW` | Lead time trend analysis |

## Dwell Time Baselines

| Stage | Calculation | Target | Outlier Threshold |
|-------|-------------|--------|-------------------|
| **Order-to-Ship** | `shipment_date - order_date` | ≤ 2 days | > 5 days sustained |
| **Ship-to-Delivery** | `delivery_date - shipment_date` | ≤ 3 days | > 7 days sustained |
| **Total Lead Time** | `delivery_date - order_date` | ≤ 5 days | > 10 days sustained |
| **WoW Spike Detection** | `(current_avg - previous_avg) / previous_avg > 0.50` | ≤ 50% WoW increase | > 50% triggers alert |

## Power BI Alert Configuration

| Card Visual | Measure | Condition | Frequency |
|-------------|---------|-----------|-----------|
| 7D Rolling OTIF | `[Rolling 7-Day OTIF %]` | Less than 0.92 | Every refresh |
| Total Backorder Cost | `[Backorder Total Open Cost]` | Greater than 10000 | Every refresh |
| Consecutive Failures (table) | `[Consecutive Failures]` | Greater than 2 | Every refresh |
| Carrier OTIF % | `[Carrier OTIF %]` | Less than 0.85 | Every refresh |

## Escalation Matrix

| Escalation Level | Trigger | Notify | Method |
|------------------|---------|--------|--------|
| **L1** | Alert fires | Logistics Analyst | Teams + Email |
| **L2** | Not acknowledged in 30 min | Logistics Manager | Teams + Email + Slack |
| **L3** | 2+ critical alerts in 24 hours | Supply Chain Director | Email + Phone (via Teams call) |

## SLA Compliance Color Coding

| Color | Range | Meaning |
|-------|-------|---------|
| 🟢 Green | ≥ 95% | Exceeding target |
| 🟡 Yellow | 92%–94.99% | At target (needs watching) |
| 🟠 Orange | 85%–91.99% | Below target (breached) |
| 🔴 Red | < 85% | Critical failure |

## Threshold Tuning Guidelines

1. **Start conservative** — use the warning thresholds for the first 30 days
2. **Adjust per vendor** — strategic partners may get tighter targets (95%)
3. **Seasonal adjustments** — peak periods may need looser thresholds (temporarily set to 88%)
4. **Carrier thresholds** — set based on negotiated SLAs in carrier contracts (default 85%)
5. **Review quarterly** — refresh thresholds against historic performance distribution
