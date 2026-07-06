# Architecture — Real-Time OTIF Monitoring & Event-Driven SLA Automation

## System Overview

End-to-end architecture for monitoring On-Time In-Full (OTIF) delivery performance and pushing real-time notifications when SLAs are breached.

```
┌──────────────────────────────────────────────────────────────────┐
│                     DATA SOURCE LAYER                            │
│                                                                  │
│  ┌────────────┐  ┌──────────────┐  ┌──────────────────┐        │
│  │ SAP ERP    │  │ PostgreSQL   │  │ SQLite (dev)     │        │
│  │ Simulated  │  │ Production   │  │ Portable test    │        │
│  └────────────┘  └──────────────┘  └──────────────────┘        │
└──────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────────────────┐
│                     SQL VIEW LAYER                               │
│                                                                  │
│  ┌──────────────┐  ┌────────────────┐  ┌──────────────────┐    │
│  │ OTIF Views   │  │ Analytics Views│  │ Alert Views      │    │
│  │ v_otif_base  │  │ consec_failure │  │ threshold_breach │    │
│  │ rolling_7d   │  │ dwell_times    │  │ backorder_cost   │    │
│  │ rolling_30d  │  │ backorder_cost │  │ carrier_perf     │    │
│  │ vendor_hier  │  │ state_sequence │  │ dashboard_summary│    │
│  └──────────────┘  └────────────────┘  └──────────────────┘    │
│                                                                  │
│  ┌───────────────────┐  ┌──────────────────┐                     │
│  │ Materialized Views│  │ Security (RLS)   │                     │
│  │ mv_otif_7d        │  │ region_access    │                     │
│  │ mv_vendor_hier    │  │ read_only        │                     │
│  │ mv_carrier_score  │  │ audit_read       │                     │
│  └───────────────────┘  └──────────────────┘                     │
└──────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────────────────┐
│                     POWER BI LAYER                               │
│                                                                  │
│  ┌────────────────────────────────────────────────────────┐     │
│  │  OTIF Monitoring Dashboard                             │     │
│  │  ┌──────┐ ┌──────┐ ┌──────────┐ ┌──────────────┐     │     │
│  │  │ OTIF │ │ 7D   │ │ Backorder│ │ Avg Lead     │     │     │
│  │  │ %    │ │Roll% │ │ Cost    │ │ Time          │     │     │
│  │  └──────┘ └──────┘ └──────────┘ └──────────────┘     │     │
│  │  ┌─────────────────┐ ┌────────────────────────┐      │     │
│  │  │ Trend + SLA Line│ │ Vendor/Carrier Heatmap │      │     │
│  │  └─────────────────┘ └────────────────────────┘      │     │
│  │  ┌─────────────────┐ ┌────────────────────────┐      │     │
│  │  │ Alert Summary   │ │ Region Breakdown       │      │     │
│  │  └─────────────────┘ └────────────────────────┘      │     │
│  └────────────────────────────────────────────────────────┘     │
│                                                                  │
│  ⚡ Data-Driven Alerts (Service)                                 │
│  • 7D Rolling OTIF < 92%                                        │
│  • Backorder Cost > $10K / $50K                                 │
│  • Consecutive Failures ≥ 3                                     │
│  • Carrier On-Time < 85%                                        │
└──────────────────────────────────────────────────────────────────┘
                        │
                        ▼
┌──────────────────────────────────────────────────────────────────┐
│                  POWER AUTOMATE LAYER                            │
│                                                                  │
│  Trigger: When a data-driven alert is triggered                  │
│                │                                                 │
│                ▼                                                 │
│  ┌──────────────────────────────────────────────────────┐       │
│  │         Alert Orchestrator (flow_orchestrator.md)     │       │
│  │                                                      │       │
│  │  ┌──────────────┐                                    │       │
│  │  │ Parse Payload│                                    │       │
│  │  └──────┬───────┘                                    │       │
│  │         ▼                                            │       │
│  │  ┌──────────────┐                                    │       │
│  │  │ Compute Sev  │                                    │       │
│  │  └──────┬───────┘                                    │       │
│  │         ▼                                            │       │
│  │  Critical ──► Teams + Email + Slack (Parallel)       │       │
│  │  Breached ──► Teams + Email (Parallel)               │       │
│  │  Warning  ──► Email Only                             │       │
│  └──────────────────────────────────────────────────────┘       │
│                │                                                 │
│                ▼                                                 │
│  ┌──────────┐  ┌──────────────┐  ┌──────────────────┐          │
│  │ Teams    │  │ Outlook      │  │ Slack            │          │
│  │Adaptive  │  │ HTML Email   │  │ Block Kit Msg    │          │
│  │Card      │  │ Formatted    │  │ Webhook POST     │          │
│  └──────────┘  └──────────────┘  └──────────────────┘          │
│                │                                                 │
│         ┌──────┴──────┐                                         │
│         ▼              ▼                                         │
│  ┌─────────────┐  ┌────────────────────────┐                    │
│  │ Error Handler│  │ Escalation Timer      │                    │
│  │ Retry/log   │  │ 30 min → Manager Msg  │                    │
│  └─────────────┘  └────────────────────────┘                    │
│                                                                  │
│  ┌─────────────────────────────────────────────────────────┐    │
│  │ Alert History (alert_history table)                      │    │
│  │ Logs all notifications with severity, channel, ack      │    │
│  └─────────────────────────────────────────────────────────┘    │
└──────────────────────────────────────────────────────────────────┘
```

## Technology Stack

| Layer | Technology | Purpose |
|-------|-----------|---------|
| Data Source | PostgreSQL (prod via Docker), SQLite (dev), SAP-style schema (ref) | Stores order-to-delivery records |
| SQL Views | PostgreSQL 13+ with window functions | Computes OTIF, rolling metrics, alert triggers |
| Materialized Views | PostgreSQL `CREATE MATERIALIZED VIEW` + pg_cron | Cached for dashboard performance |
| Security | PostgreSQL Row-Level Security (RLS) | Region-based access, read-only roles, audit |
| Data Generator | Python 3.9+ with `executemany` batch inserts | Generates realistic seed data |
| BI & Visualization | Power BI Desktop + Power BI Service | Dashboards, KPIs, data-driven alerts |
| Workflow Automation | Power Automate (cloud flows) | Routes alerts to notification channels |
| Notifications | Microsoft Teams Adaptive Cards, Outlook HTML email, Slack Block Kit | Delivers real-time actionable alerts |
| Alert History | `alert_history` table in same DB | Audit log for all notifications, acknowledgments |

## Data Flow

```
1. ERP / DW data is stored in relational tables (orders, shipments, deliveries)
2. SQL views transform raw data into OTIF metrics using window functions
3. Materialized views cache expensive aggregations for dashboard performance
4. Row-Level Security enforces region-based data access at the DB layer
5. Power BI imports or connects via DirectQuery to the (materialized) views
6. Power BI Service data-driven alerts monitor KPI thresholds
7. When breached, Power Automate receives a JSON payload
8. The orchestrator parses payload, computes severity, selects notification channels
9. Notifications sent with live dynamic content + deep links back to the report
10. All notifications logged in `alert_history` table with acknowledgment tracking
```

## Design Decisions

| Decision | Rationale |
|----------|-----------|
| **SQL views over stored procedures** | Views are queryable, composable, and work with Power BI DirectQuery/Import |
| **Window functions over temp tables** | Single-pass computation, no staging overhead, real-time capable |
| **Materialized views for dashboards** | Avoid recomputing expensive window chains on every Power BI refresh |
| **Row-Level Security** | Enforce region-based data access without application-layer filtering |
| **Power BI Service alerts** | Native integration with Power Automate via built-in connector |
| **Teams Adaptive Cards** | Rich interactive cards with action buttons (Open Report, Acknowledge, Escalate) |
| **HTML email template** | Works across all email clients; conditional formatting for severity |
| **Slack Block Kit** | Structured message blocks with interactive buttons |
| **Dual schema (SAP + generic)** | SAP ERP reference for enterprise readers; generic DW for rapid prototyping |
| **alert_history audit table** | Centralized logging for compliance, escalation tracking, and SLA performance measurement |
