# Setup Guide — OTIF Monitoring & SLA Automation

## Prerequisites

### Software
- **PostgreSQL 16+** (production) or **SQLite 3.25+** (development)
- **Python 3.9+** with packages: `psycopg2-binary`
- **Docker + docker-compose** (optional, for containerized PostgreSQL)
- **Power BI Desktop** (free) + **Power BI Pro / Premium Per User** (for Service alerts)
- **Power Automate** (standalone or Office 365 plan)
- **Microsoft Teams** / **Outlook** / **Slack** (for notifications)

### Python Dependencies
```bash
pip install -r requirements.txt
```

---

## Step 1: Database Setup

### Option A: PostgreSQL with Docker (Recommended)

```bash
# Start PostgreSQL with schema initialization
docker compose up -d

# Generate seed data
python sql/02_seed_data_generator.py \
    --db postgresql \
    --connection "host=localhost dbname=otif_monitoring user=otif_user password=changeme" \
    --orders 10000 --days 210 --seed 42
```

### Option A2: PostgreSQL (Manual)

```bash
# Create database
createdb otif_monitoring

# Run schema
psql -d otif_monitoring -f sql/01_schema/generic_dw_tables.sql

# OR for SAP-style
psql -d otif_monitoring -f sql/01_schema/sap_erp_tables.sql

# Generate seed data
python sql/02_seed_data_generator.py \
    --db postgresql \
    --connection "host=localhost dbname=otif_monitoring user=postgres" \
    --orders 10000 --days 210 --seed 42
```

### Option B: SQLite (Development / Portable)

```bash
# Generate data directly into SQLite
python sql/02_seed_data_generator.py \
    --db sqlite \
    --connection data/otif_seed.db \
    --orders 5000 --days 210 --seed 42

# Create the portable OTIF views (core subset only — see note below)
make views-sqlite
```

> **Note:** The full view set in `sql/03_views_otif.sql` through
> `sql/08_views_sap_transformation.sql` uses PostgreSQL-only syntax
> (`INTERVAL` arithmetic, `DATE_TRUNC`, `LATERAL` joins) plus
> materialized views and Row-Level Security, none of which SQLite
> supports. `sql/03b_views_otif_sqlite.sql` provides a portable subset
> (`v_otif_line_level`, `v_otif_rolling_7d`, `v_consecutive_failures`,
> `v_alert_otif_below_threshold`) so the fast/no-license dev path has
> working views to query. For the full feature set (carrier scorecards,
> dwell-time trends, backorder running totals, materialized views, RLS),
> use the PostgreSQL path (Option A).

### Option C: CSV (Portable / Any Database)

```bash
python sql/02_seed_data_generator.py \
    --db csv \
    --output-dir ./data \
    --orders 10000 --days 210 --seed 42
```

---

## Step 2: Create SQL Views

After populating the database, run the view creation scripts **in order**:

```bash
# PostgreSQL
psql -d otif_monitoring -f sql/03_views_otif.sql
psql -d otif_monitoring -f sql/04_views_analytics.sql
psql -d otif_monitoring -f sql/05_views_alerts.sql

# Verify views exist
psql -d otif_monitoring -c "\dv"
```

### (Optional) Step 2b: Create Materialized Views

For production dashboards, materialized views cache expensive window function computations:

```bash
psql -d otif_monitoring -f sql/07_materialized_views.sql
```

Schedule the refresh procedure via pg_cron or your scheduler:

```bash
# Every 30 minutes
SELECT cron.schedule('refresh-otif-views', '*/30 * * * *',
    'SELECT refresh_otif_materialized_views();');
```

### (Optional) Step 2c: Enable Row-Level Security

For multi-tenant deployments with regional data isolation:

```bash
psql -d otif_monitoring -f sql/06_security_rls.sql

# Create roles
psql -d otif_monitoring -c "CREATE ROLE regional_manager;"
psql -d otif_monitoring -c "CREATE ROLE reporting_user;"
psql -d otif_monitoring -c "CREATE ROLE auditor;"
```

Then grant roles to users and set the app region:
```sql
SET app.region = 'NE';  -- Regional manager sees only NE data
```

---

## Step 3: Power BI Setup

### Import Data
1. Open Power BI Desktop
2. Get Data → PostgreSQL Database (or SQLite via ODBC, or CSV Folder)
3. Select connection mode:
   - **Import**: Better performance, scheduled refresh
   - **DirectQuery**: Real-time, queries source on every interaction
4. Load the following tables:
   - `orders`, `order_lines`, `shipments`, `delivery_lines`, `vendors`, `carriers`, `products`, `backorders`
   - All `v_*` views (optional for DirectQuery; imported views for Import mode)

### Create Relationships
Set up the data model relationships per `dashboard_layout.md`:
- `orders[order_number]` → `shipments[order_number]` (1:N)
- `shipments[shipment_number]` → `delivery_lines[shipment_number]` (1:N)
- `delivery_lines[order_number, line_number]` → `order_lines[order_number, line_number]` (N:1)

### Add Measures
Copy all measures from `power_bi/measures.dax` into the DAX editor.

### Build Dashboard
Follow `power_bi/dashboard_layout.md` for visual placement.

### Publish to Service
1. Save the `.pbix` file
2. Publish to a shared workspace (requires Power BI Pro license)
3. Pin key visuals to a dashboard named **"OTIF SLA Monitoring"**
4. Configure scheduled refresh (every 30 min minimum)

---

## Step 4: Configure Data-Driven Alerts

Follow `power_bi/alerts_config.md` to create alerts on:
- **7D Rolling OTIF %** card → Less than 0.92
- **Total Open Backorder Cost** → Greater than 10000
- **Consecutive Failures** table → Greater than 2

---

## Step 5: Build Power Automate Flows

### Create the Alert Trigger Flow
1. Go to https://make.powerautomate.com
2. Create → Automated cloud flow
3. Search for "Power BI" → **When a data-driven alert is triggered**
4. Select your dashboard and alert

### Add Notification Steps

#### Teams Adaptive Card
1. Add action: **Compose** → Build the Adaptive Card JSON (see `power_automate/flow_teams.json`)
2. Add action: **Post message in a chat or channel** (Microsoft Teams connector)
3. Select team: "Logistics Operations", channel: "SLA Alerts"

#### Outlook Email
1. Add action: **Send an email (V2)** (Office 365 Outlook connector)
2. Use the HTML template from `power_automate/flow_email.html`
3. Replace `<!--@metricValue-->`, `<!--@alertTitle-->`, etc. with dynamic content from the trigger

#### Slack Webhook
1. Add action: **HTTP** → POST
2. URL: Your Slack webhook URL
3. Body: Block Kit JSON from `power_automate/flow_slack.md`

### Use the Orchestration Flow
1. Follow `power_automate/flow_orchestrator.md` for the complete flow design
2. Add a **Switch** action to route by severity (Critical / Breached / Warning)
3. Use **Parallel Branches** for simultaneous Teams + Email + Slack delivery
4. Add error handling: **Configure Run After** → if one channel fails, continue others
5. Add **Delay** (30 min) → check acknowledgment → manager escalation for Critical alerts
6. Optionally log to database via PostgreSQL connector to populate `alert_history`

---

## Step 6: Test End-to-End

```bash
# 1. Generate data with Makefile
make generate-sqlite

# 2. Validate row counts
make validate

# 3. Create the portable OTIF views (see Option B note above)
make views-sqlite

# 4. Query alert views (SQLite example)
python -c "
import sqlite3
c = sqlite3.connect('data/otif_seed.db')
cur = c.cursor()

# Check low-OTIF vendors (V006, V009 should appear near the top)
print('=== Low OTIF Vendors ===')
for r in cur.execute('''
    SELECT vendor_code, COUNT(*) as failures
    FROM v_otif_line_level
    WHERE is_otif = 0
    GROUP BY vendor_code
    ORDER BY failures DESC
    LIMIT 5
'''):
    print(f'  {r[0]}: {r[1]} failures')
c.close()
"
```

4. Verify Power BI imports reflect data
5. Temporarily adjust alert condition to trigger immediately
6. Verify Teams card, email, and Slack message arrive with correct dynamic values
7. Verify deep link URL opens the correct Power BI report page

---

## Environment Quick Reference

| Environment | Database | Power BI | Notes |
|-------------|----------|----------|-------|
| **Development** | SQLite `otif_seed.db` | Desktop only | Fast iteration, no license needed |
| **Staging** | PostgreSQL (Docker) | Desktop + Service | `docker compose up`, test alerts |
| **Production** | PostgreSQL (cloud) | Service + Alerts | Live monitoring, 30-min refresh, RLS enabled |

## Makefile Commands

```bash
make install          # Install Python dependencies
make lint             # Lint generator code
make format           # Format generator code
make generate-sqlite  # Generate 5K orders to SQLite
make generate-csv     # Generate 5K orders to CSV files
make validate         # Verify SQLite row counts
make clean            # Remove generated data
```
