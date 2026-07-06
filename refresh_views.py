#!/usr/bin/env python3
"""
Refreshes materialized views in PostgreSQL to keep OTIF metrics updated.
Usage: python refresh_views.py
"""
import os
import sys

try:
    import psycopg2
except ImportError:
    print("psycopg2 is required. Run: pip install psycopg2-binary", file=sys.stderr)
    sys.exit(1)

from dotenv import load_dotenv

VIEWS = [
    "mv_otif_rolling_7d",
    "mv_otif_vendor_hierarchy",
    "mv_otif_carrier_scorecard",
    "mv_alert_dashboard_summary",
]


def build_connection_string() -> str:
    host = os.getenv("OTIF_DB_HOST", "localhost")
    port = os.getenv("OTIF_DB_PORT", "5432")
    dbname = os.getenv("OTIF_DB_NAME", "otif_monitoring")
    user = os.getenv("OTIF_DB_USER", "otif_user")
    password = os.getenv("OTIF_DB_PASSWORD", "changeme")
    return f"host={host} port={port} dbname={dbname} user={user} password={password}"


def main() -> None:
    load_dotenv()
    conn_str = build_connection_string()

    print("Connecting to database...")
    try:
        conn = psycopg2.connect(conn_str)
    except psycopg2.Error as e:
        print(f"Error: could not connect to database: {e}", file=sys.stderr)
        sys.exit(1)
    # Required for REFRESH MATERIALIZED VIEW CONCURRENTLY, which must not
    # run inside a multi-statement transaction block.
    conn.autocommit = True

    failures = []
    try:
        with conn.cursor() as cursor:
            for view in VIEWS:
                print(f"Refreshing materialized view: {view}...")
                try:
                    # CONCURRENTLY avoids locking out dashboard readers during
                    # refresh. Requires the unique index each view already
                    # defines in sql/07_materialized_views.sql.
                    cursor.execute(f"REFRESH MATERIALIZED VIEW CONCURRENTLY {view};")
                except psycopg2.Error as e:
                    print(f"  -> FAILED: {e}", file=sys.stderr)
                    failures.append(view)
    finally:
        conn.close()

    if failures:
        print(f"Refresh completed with failures: {', '.join(failures)}", file=sys.stderr)
        sys.exit(1)

    print("Successfully refreshed all materialized views.")


if __name__ == "__main__":
    main()
