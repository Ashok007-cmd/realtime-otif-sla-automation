#!/usr/bin/env python3
"""
Simulates the Power Automate / Event-Driven SLA automation integration.
Fetches active alerts from mv_alert_dashboard_summary, simulates payload
posting, and records each alert in alert_history for audit tracking.
Usage: python simulate_alerts.py
"""
import json
import os
import sys
import datetime

try:
    import psycopg2
except ImportError:
    print("psycopg2 is required. Run: pip install psycopg2-binary", file=sys.stderr)
    sys.exit(1)

from dotenv import load_dotenv

ACTIVE_SEVERITIES = ("CRITICAL", "BREACHED", "HIGH", "WARNING")


def json_serial(obj):
    """JSON serializer for objects not serializable by default json code"""
    if isinstance(obj, (datetime.datetime, datetime.date)):
        return obj.isoformat()
    raise TypeError(f"Type {type(obj)} not serializable")


def build_connection_string() -> str:
    host = os.getenv("OTIF_DB_HOST", "localhost")
    port = os.getenv("OTIF_DB_PORT", "5432")
    dbname = os.getenv("OTIF_DB_NAME", "otif_monitoring")
    user = os.getenv("OTIF_DB_USER", "otif_user")
    password = os.getenv("OTIF_DB_PASSWORD", "changeme")
    return f"host={host} port={port} dbname={dbname} user={user} password={password}"


def channels_for_severity(severity: str) -> str:
    if severity in ("CRITICAL",):
        return "Teams,Email,Slack"
    if severity in ("BREACHED", "HIGH"):
        return "Teams,Email"
    return "Email"


def main() -> None:
    load_dotenv()
    conn_str = build_connection_string()

    try:
        conn = psycopg2.connect(conn_str)
    except psycopg2.Error as e:
        print(f"Error: could not connect to database: {e}", file=sys.stderr)
        sys.exit(1)

    try:
        with conn.cursor() as cursor:
            cursor.execute(
                "SELECT * FROM mv_alert_dashboard_summary WHERE alert_severity = ANY(%s);",
                (list(ACTIVE_SEVERITIES),),
            )
            columns = [desc[0] for desc in cursor.description]
            alerts = [dict(zip(columns, row)) for row in cursor.fetchall()]

            if not alerts:
                print("No active SLA breaches or alerts found.")
                return

            print(f"Found {len(alerts)} active alerts. Simulating Power Automate event trigger...\n")

            for alert in alerts:
                severity = alert["alert_severity"]
                channels = channels_for_severity(severity)
                payload = {
                    "EventContext": {
                        "AlertType": alert["alert_type"],
                        "Severity": severity,
                        "TriggerTime": alert["alert_generated_at"],
                    },
                    "Payload": {
                        "EntityID": alert["entity"],
                        "MetricValue": float(alert["metric_value"]) if alert["metric_value"] is not None else None,
                        "Threshold": float(alert["sla_threshold"]) if alert["sla_threshold"] is not None else None,
                        "Gap": float(alert["gap_to_threshold"]) if alert["gap_to_threshold"] is not None else None,
                        "Message": alert["alert_description"],
                    },
                }

                print(f"--- POSTING ALERT FOR: {alert['entity']} ---")
                print(json.dumps(payload, indent=2, default=json_serial))
                print(f"  -> channels: {channels}")
                print("-" * 50 + "\n")

                # alert_history_id has no engine-level auto-increment: in
                # SQLite, "INTEGER PRIMARY KEY" is a rowid alias that
                # self-assigns; in PostgreSQL it's a plain NOT NULL column
                # with no default. The schema is intentionally shared
                # verbatim between both engines (single source of truth —
                # see sql/02_seed_data_generator.py), so the ID is computed
                # here instead of diverging the DDL per engine. Safe for
                # this script's single-writer, single-transaction use;
                # not a pattern for concurrent writers.
                cursor.execute(
                    """
                    INSERT INTO alert_history
                        (alert_history_id, alert_type, entity, severity,
                         metric_value, threshold_value, alert_description, channels)
                    SELECT COALESCE(MAX(alert_history_id), 0) + 1, %s, %s, %s, %s, %s, %s, %s
                    FROM alert_history
                    """,
                    (
                        alert["alert_type"],
                        alert["entity"],
                        severity,
                        alert["metric_value"],
                        alert["sla_threshold"],
                        alert["alert_description"],
                        channels,
                    ),
                )

            conn.commit()
            print(f"Logged {len(alerts)} alert(s) to alert_history.")
            print("Simulation complete. These payloads would normally trigger Microsoft Teams / Outlook workflows.")
    finally:
        conn.close()


if __name__ == "__main__":
    main()
