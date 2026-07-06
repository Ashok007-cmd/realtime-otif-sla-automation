#!/bin/bash
set -e

echo "Running database initialization scripts..."

# Run schema files
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /sql/01_schema/generic_dw_tables.sql
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f /sql/01_schema/sap_erp_tables.sql

# Run view files and RLS (skip python script)
for f in $(ls /sql/*.sql | sort); do
    echo "Running $f..."
    psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" -f "$f"
done

echo "Database initialization complete!"
