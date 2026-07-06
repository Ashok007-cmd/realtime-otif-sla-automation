# Real-Time OTIF Monitoring & Event-Driven SLA Automation

[![CI](https://github.com/Ashok007-cmd/realtime-otif-sla-automation/actions/workflows/ci.yml/badge.svg)](https://github.com/Ashok007-cmd/realtime-otif-sla-automation/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Python](https://img.shields.io/badge/python-3.9%2B-blue)
![PostgreSQL](https://img.shields.io/badge/postgres-16-blue)

A supply-chain analytics pipeline that turns raw order/shipment data into **On-Time-In-Full (OTIF)** SLA metrics using advanced SQL window functions, then pushes real-time breach notifications to Teams, Outlook, and Slack via Power BI data-driven alerts and Power Automate — with zero manual dashboard watching.

```
ERP / DW Data → SQL Views (window functions) → Power BI Dashboard → Data-Driven Alert
                                                                          │
                                                                          ▼
                                                                 Power Automate Flow
                                                                          │
                                                            ┌─────────────┼─────────────┐
                                                            ▼             ▼             ▼
                                                         Teams         Outlook        Slack
```

## What it demonstrates

- **Window-function SQL**: rolling 7/30-day OTIF %, `LAG()`/`LEAD()` consecutive-failure detection, running backorder-cost totals, vendor/region ranking
- **Materialized views + Row-Level Security** for dashboard performance and region-scoped data access
- **Event-driven automation**: Power BI alert → Power Automate → severity-routed Teams/Email/Slack notifications with escalation timers and an audit trail
- **Dual data-source design**: a generic data-warehouse schema plus a SAP-ERP-shaped reference schema (VBAK/VBAP/LIKP/LIPS) mapped onto the same views

## Quickstart

Two setup paths are supported. Pick one.

### Path A — SQLite (fastest, no license needed)

```bash
make install
make generate-sqlite   # 5,000 synthetic orders, 210 days of history
make views-sqlite       # creates the portable OTIF views
make validate
```

Then explore it:

```bash
./venv/bin/python -c "
import sqlite3
c = sqlite3.connect('data/otif_seed.db')
for r in c.execute('''
    SELECT vendor_code, COUNT(*) failures
    FROM v_otif_line_level WHERE is_otif = 0
    GROUP BY vendor_code ORDER BY failures DESC LIMIT 5
'''):
    print(r)
"
```

> The SQLite path covers the core OTIF calculation, 7-day rolling %, consecutive-failure detection, and threshold alerts (`sql/03b_views_otif_sqlite.sql`). Materialized views, Row-Level Security, and the SAP transformation layer are PostgreSQL-only features — use Path B for those.

### Path B — PostgreSQL + Docker (full feature set)

```bash
cp .env.example .env        # then edit OTIF_DB_PASSWORD to something real
./setup.sh                  # docker compose up, seed data, refresh materialized views
make test                   # runs simulate_alerts.py against live alert views
```

`setup.sh` starts Postgres via Docker Compose, waits for it to become healthy, applies every file under `sql/` (schema → views → RLS → materialized views → SAP mapping), generates 5,000 orders of seed data, and refreshes the materialized views. See [`docs/setup_guide.md`](docs/setup_guide.md) for the manual step-by-step version, including Power BI and Power Automate configuration.

## Project structure

```
sql/
  01_schema/
    generic_dw_tables.sql       Core schema (orders, shipments, alert_history, ...)
    sap_erp_tables.sql          SAP-shaped reference schema (VBAK/VBAP/LIKP/LIPS)
  02_seed_data_generator.py     Synthetic data generator (SQLite / PostgreSQL / CSV)
  03_views_otif.sql             Core OTIF views (PostgreSQL — window functions)
  03b_views_otif_sqlite.sql     Portable OTIF view subset for the SQLite dev path
  04_views_analytics.sql        Consecutive failures, dwell times, running totals
  05_views_alerts.sql           Threshold-breach alert views (feeds Power BI)
  06_security_rls.sql           Row-Level Security policies (region isolation)
  07_materialized_views.sql     Cached views + refresh procedure for dashboards
  08_views_sap_transformation.sql   Maps the SAP schema onto the generic view layer
docker-compose.yml / docker-init/   PostgreSQL + pgAdmin, auto-applies all SQL on first boot
power_bi/                      DAX measures + dashboard layout + alert configuration
power_automate/                Teams/Email/Slack flow designs + orchestration logic
docs/                          Architecture, setup guide, SLA threshold reference
refresh_views.py               Refreshes materialized views (CONCURRENTLY)
simulate_alerts.py             Simulates a Power Automate trigger locally; logs to alert_history
```

## SLA thresholds

| Metric | Target | Warning | Breached | Critical |
|---|---|---|---|---|
| Rolling 7-day OTIF | ≥ 92% | < 92% | < 88% | < 85% |
| Carrier on-time (4-wk rolling) | ≥ 85% | — | < 85% | < 80% |
| Consecutive failures (vendor) | 0 | 2 | 3 | 4+ |
| Backorder cost (vendor / aggregate) | $0 | — | > $10K | > $50K |

Full definitions, tolerance windows, and escalation matrix: [`docs/thresholds.md`](docs/thresholds.md).

## Development

```bash
make lint        # ruff
make typecheck    # mypy
make format       # black
make validate     # row-count sanity check against data/otif_seed.db
make clean        # remove generated data + venv
```

CI (`.github/workflows/ci.yml`) runs two jobs on every push: a SQLite job (generator, lint, typecheck, view sanity checks) and a `postgres-integration` job that spins up real PostgreSQL, applies the full schema/view/RLS/materialized-view stack, and asserts Row-Level Security actually restricts a region-scoped role — not just that the SQL runs without error.

## Security notes

- Row-Level Security enforces region-based access (`regional_manager`), broad read access (`reporting_user`), and audit-only access (`alert_history` via `auditor`) — each policy is scoped with an explicit `TO <role>`, since unscoped permissive policies in Postgres apply to every role and silently defeat each other.
- No real credentials are checked into this repo. Copy `.env.example` to `.env` and set your own values; `.env` is gitignored.
- `sql/02_seed_data_generator.py` only ever generates synthetic data — no real customer, vendor, or order information is included anywhere in this repository.

## License

[MIT](LICENSE)
