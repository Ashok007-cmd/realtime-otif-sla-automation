#!/bin/bash
set -e

if [ ! -f .env ]; then
  echo "ERROR: .env not found. Copy .env.example to .env and set OTIF_DB_PASSWORD first." >&2
  exit 1
fi
set -a
source .env
set +a
: "${OTIF_DB_PASSWORD:?OTIF_DB_PASSWORD must be set in .env}"

echo "1. Installing Python dependencies..."
make install

echo "2. Starting PostgreSQL with Docker Compose..."
docker compose up -d

echo "3. Waiting for PostgreSQL to be ready..."
sleep 5
until docker exec otif-postgres pg_isready -U otif_user -d otif_monitoring; do
  echo "Waiting for postgres..."
  sleep 2
done
# Wait an additional few seconds for init scripts to complete
sleep 5

echo "4. Generating seed data (this may take a moment)..."
./venv/bin/python sql/02_seed_data_generator.py --db postgresql --connection "host=localhost dbname=otif_monitoring user=otif_user password=${OTIF_DB_PASSWORD}" --orders 5000

echo "5. Refreshing materialized views..."
./venv/bin/python refresh_views.py

echo "6. Setup complete! Project is fully functional."
echo "You can now run 'make test' to see real-time OTIF alerts."
