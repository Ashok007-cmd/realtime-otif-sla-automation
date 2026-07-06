# OTIF Monitoring — Task Runner
.PHONY: help install lint typecheck clean generate-sqlite generate-csv views-sqlite validate deploy test

help:
	@echo "OTIF Monitoring — Available commands:"
	@echo "  install         Install Python dependencies in venv"
	@echo "  lint            Lint Python code (ruff)"
	@echo "  typecheck       Type check Python code (mypy)"
	@echo "  format          Format Python code (black)"
	@echo "  generate-sqlite Generate seed data to SQLite"
	@echo "  generate-csv    Generate seed data to CSV"
	@echo "  views-sqlite    Create portable OTIF views in data/otif_seed.db (dev path)"
	@echo "  validate        Run end-to-end validation (SQLite)"
	@echo "  deploy          Setup Docker, Postgres, seed data, and refresh views"
	@echo "  test            Run simulate_alerts.py"
	@echo "  clean           Remove generated files"

install:
	python3 -m venv venv
	./venv/bin/pip install --upgrade pip
	./venv/bin/pip install -r requirements.txt

lint:
	./venv/bin/ruff check sql/02_seed_data_generator.py refresh_views.py simulate_alerts.py

typecheck:
	./venv/bin/python -m mypy --ignore-missing-imports sql/02_seed_data_generator.py refresh_views.py simulate_alerts.py

format:
	./venv/bin/black sql/02_seed_data_generator.py refresh_views.py simulate_alerts.py

generate-sqlite:
	./venv/bin/python sql/02_seed_data_generator.py --db sqlite --connection data/otif_seed.db --orders 5000 --seed 42

generate-csv:
	./venv/bin/python sql/02_seed_data_generator.py --db csv --output-dir ./data --orders 5000 --seed 42

views-sqlite:
	./venv/bin/python -c "import sqlite3; c = sqlite3.connect('data/otif_seed.db'); c.executescript(open('sql/03b_views_otif_sqlite.sql').read()); c.close(); print('Views created in data/otif_seed.db')"

validate:
	./venv/bin/python -c "import sqlite3; c = sqlite3.connect('data/otif_seed.db'); \
		print('Orders:', c.execute('SELECT COUNT(*) FROM orders').fetchone()[0]); \
		print('Lines:', c.execute('SELECT COUNT(*) FROM order_lines').fetchone()[0]); \
		print('Shipments:', c.execute('SELECT COUNT(*) FROM shipments').fetchone()[0]); \
		print('Delivery lines:', c.execute('SELECT COUNT(*) FROM delivery_lines').fetchone()[0]); \
		print('Backorders:', c.execute('SELECT COUNT(*) FROM backorders').fetchone()[0]); \
		c.close()"

deploy:
	./setup.sh

test:
	./venv/bin/python simulate_alerts.py

clean:
	rm -f data/*.db data/*.csv
	rm -rf venv
