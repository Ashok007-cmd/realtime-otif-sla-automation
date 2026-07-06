#!/usr/bin/env python3
"""
OTIF Seed Data Generator
Generates realistic order/delivery/shipment data for OTIF monitoring.
Supports PostgreSQL, SQLite, and CSV output.

Usage:
    python seed_data_generator.py --db postgresql --connection "host=localhost dbname=otif user=postgres"
    python seed_data_generator.py --db sqlite --connection "otif_seed.db"
    python seed_data_generator.py --db csv --output-dir ./data
    python seed_data_generator.py --db sqlite --orders 50000 --seed 42
"""

import argparse
import csv
import datetime
import os
import random
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

TABLE_NAMES: List[str] = [
    "backorders",
    "delivery_lines",
    "shipments",
    "order_lines",
    "orders",
    "carriers",
    "products",
    "vendors",
    "customers",
]

TRUNCATION_ORDER: List[str] = [
    "backorders",
    "delivery_lines",
    "shipments",
    "order_lines",
    "orders",
    "carriers",
    "products",
    "vendors",
    "customers",
]

TABLE_WHITELIST: set = set(TABLE_NAMES)

DEFAULT_VENDOR_PROFILES: List[Dict[str, Any]] = [
    {"code": "V001", "name": "Precision Parts Co.",        "region": "NE",  "tier": "strategic", "otif_rate": 0.96, "on_time_rate": 0.97, "in_full_rate": 0.98},
    {"code": "V002", "name": "Global Logistics Supply",    "region": "NE",  "tier": "standard",  "otif_rate": 0.88, "on_time_rate": 0.90, "in_full_rate": 0.94},
    {"code": "V003", "name": "West Coast Manufacturing",   "region": "WC",  "tier": "strategic", "otif_rate": 0.94, "on_time_rate": 0.95, "in_full_rate": 0.97},
    {"code": "V004", "name": "Southern Industrial Supply", "region": "SE",  "tier": "standard",  "otif_rate": 0.85, "on_time_rate": 0.87, "in_full_rate": 0.93},
    {"code": "V005", "name": "Midwest Components Inc.",    "region": "MW",  "tier": "strategic", "otif_rate": 0.97, "on_time_rate": 0.98, "in_full_rate": 0.99},
    {"code": "V006", "name": "Atlantic Wholesale Goods",   "region": "SE",  "tier": "emerging",  "otif_rate": 0.72, "on_time_rate": 0.78, "in_full_rate": 0.85},
    {"code": "V007", "name": "Pacific Rim Trading Co.",    "region": "WC",  "tier": "standard",  "otif_rate": 0.82, "on_time_rate": 0.85, "in_full_rate": 0.90},
    {"code": "V008", "name": "Northern Logistics Group",   "region": "MW",  "tier": "standard",  "otif_rate": 0.90, "on_time_rate": 0.92, "in_full_rate": 0.95},
    {"code": "V009", "name": "Sunbelt Distributors",       "region": "SE",  "tier": "emerging",  "otif_rate": 0.68, "on_time_rate": 0.72, "in_full_rate": 0.82},
    {"code": "V010", "name": "East Coast Parts Supply",    "region": "NE",  "tier": "standard",  "otif_rate": 0.91, "on_time_rate": 0.93, "in_full_rate": 0.96},
]

DEFAULT_CARRIER_PROFILES: List[Dict[str, Any]] = [
    {"code": "FDX",  "name": "FedEx Freight",      "mode": "truck", "on_time_rate": 0.93},
    {"code": "UPS",  "name": "UPS Supply Chain",   "mode": "truck", "on_time_rate": 0.94},
    {"code": "JBHT", "name": "JB Hunt Transport",  "mode": "truck", "on_time_rate": 0.88},
    {"code": "SAIA", "name": "Saia LTL Freight",   "mode": "truck", "on_time_rate": 0.86},
    {"code": "XPO",  "name": "XPO Logistics",      "mode": "truck", "on_time_rate": 0.90},
    {"code": "UPSA", "name": "UPS Air",            "mode": "air",   "on_time_rate": 0.96},
    {"code": "FDXA", "name": "FedEx Air",          "mode": "air",   "on_time_rate": 0.97},
    {"code": "CSX",  "name": "CSX Rail",           "mode": "rail",  "on_time_rate": 0.82},
    {"code": "UP",   "name": "Union Pacific Rail", "mode": "rail",  "on_time_rate": 0.80},
]

DEFAULT_CUSTOMER_COUNT: int = 50
DEFAULT_PRODUCT_COUNT: int = 200
DEFAULT_ORDER_COUNT: int = 10000
DEFAULT_DAYS_HISTORY: int = 210
DEFAULT_SEED: int = 1234

CursorObj = Any  # Type alias for DB-API cursor

# ---------------------------------------------------------------------------
# Helper: weighted random selection
# ---------------------------------------------------------------------------

def weighted_choice(items: List[Any], weights: List[float]) -> Any:
    total: float = sum(weights)
    r: float = random.random() * total
    up_to: float = 0.0
    for item, weight in zip(items, weights):
        up_to += weight
        if r <= up_to:
            return item
    return items[-1]


# ---------------------------------------------------------------------------
# Data Generator Class
# ---------------------------------------------------------------------------

class OTIFDataGenerator:
    """Generates realistic OTIF test data with configurable failure profiles."""

    def __init__(
        self,
        vendor_profiles: Optional[List[Dict[str, Any]]] = None,
        carrier_profiles: Optional[List[Dict[str, Any]]] = None,
        customer_count: int = DEFAULT_CUSTOMER_COUNT,
        product_count: int = DEFAULT_PRODUCT_COUNT,
        order_count: int = DEFAULT_ORDER_COUNT,
        days_history: int = DEFAULT_DAYS_HISTORY,
        seed: int = DEFAULT_SEED,
    ) -> None:
        self.vendor_profiles: List[Dict[str, Any]] = vendor_profiles or DEFAULT_VENDOR_PROFILES
        self.carrier_profiles: List[Dict[str, Any]] = carrier_profiles or DEFAULT_CARRIER_PROFILES
        self.customer_count: int = customer_count
        self.product_count: int = product_count
        self.order_count: int = order_count
        self.days_history: int = days_history
        self.seed: int = seed

        random.seed(seed)

        self.end_date: datetime.date = datetime.date.today()
        self.start_date: datetime.date = self.end_date - datetime.timedelta(days=days_history)

        # Generated data stores
        self.customers: List[Dict[str, Any]] = []
        self.vendors: List[Dict[str, Any]] = []
        self.products: List[Dict[str, Any]] = []
        self.carriers: List[Dict[str, Any]] = []
        self.orders: List[Dict[str, Any]] = []
        self.order_lines: List[Dict[str, Any]] = []
        self.shipments: List[Dict[str, Any]] = []
        self.delivery_lines: List[Dict[str, Any]] = []
        self.backorders: List[Dict[str, Any]] = []

        self._generate_master_data()

    # ------------------------------------------------------------------
    # Master data generation
    # ------------------------------------------------------------------

    def _generate_master_data(self) -> None:
        regions: List[str] = ["NE", "SE", "MW", "WC", "SW"]
        countries: List[str] = ["US", "US", "US", "US", "MX", "CA"]

        for i in range(self.customer_count):
            code: str = f"CUST{i+1:04d}"
            self.customers.append({
                "customer_code": code,
                "customer_name": f"Customer {code}",
                "region": random.choice(regions),
                "country": random.choice(countries),
            })

        for vp in self.vendor_profiles:
            self.vendors.append(vp)

        categories: List[str] = ["Raw Materials", "Components", "Packaging", "Finished Goods", "MRO"]
        subcategories: Dict[str, List[str]] = {
            "Raw Materials": ["Steel", "Plastic", "Chemicals", "Textiles"],
            "Components": ["Fasteners", "Electronics", "Hydraulics", "Bearings"],
            "Packaging": ["Boxes", "Labels", "Film", "Pallets"],
            "Finished Goods": ["Assembly A", "Assembly B", "Consumer Kit", "Industrial Kit"],
            "MRO": ["Tools", "Lubricants", "Safety Gear", "Filters"],
        }
        units: List[str] = ["EA", "KG", "LB", "BOX", "PAL"]
        for i in range(self.product_count):
            cat: str = random.choice(categories)
            sub: str = random.choice(subcategories[cat])
            self.products.append({
                "sku": f"SKU{i+1:05d}",
                "product_name": f"{sub} - Model {i+1}",
                "category": cat,
                "subcategory": sub,
                "unit_of_measure": random.choice(units),
                "unit_price": round(random.uniform(5.0, 500.0), 2),
            })

        for cp in self.carrier_profiles:
            self.carriers.append(cp)

    # ------------------------------------------------------------------
    # Order generation
    # ------------------------------------------------------------------

    def _random_date(self) -> datetime.date:
        delta: datetime.timedelta = self.end_date - self.start_date
        offset: int = random.randint(0, delta.days)
        return self.start_date + datetime.timedelta(days=offset)

    def _random_date_before(self, ref_date: datetime.date, max_days_back: int = 14) -> datetime.date:
        offset: int = random.randint(1, max_days_back)
        return ref_date - datetime.timedelta(days=offset)

    def generate_orders(self) -> None:
        """Generate orders with lines, shipments, delivery lines."""
        channel_options: List[str] = ["direct", "wholesale", "retail", "ecommerce"]
        channel_weights: List[float] = [0.25, 0.35, 0.25, 0.15]

        status_options: List[str] = ["completed", "completed", "completed", "completed",
                                     "shipped", "pending"]
        status_weights: List[float] = [0.70, 0.10, 0.05, 0.05, 0.05, 0.05]

        lines_per_order: List[int] = [1, 1, 2, 2, 3, 3, 4, 5]
        lines_weights: List[float] = [0.20, 0.25, 0.20, 0.15, 0.08, 0.05, 0.04, 0.03]

        order_number_seq: int = 100000

        for oi in range(self.order_count):
            order_number_seq += 1
            order_date: datetime.date = self._random_date()
            customer: Dict[str, Any] = random.choice(self.customers)

            status: str = weighted_choice(status_options, status_weights)
            channel: str = weighted_choice(channel_options, channel_weights)

            order: Dict[str, Any] = {
                "order_number": str(order_number_seq),
                "customer_id": oi % self.customer_count + 1,
                "customer_code": customer["customer_code"],
                "order_date": order_date,
                "requested_delivery_date": order_date + datetime.timedelta(days=random.randint(3, 21)),
                "order_status": status,
                "channel": channel,
                "currency": "USD",
                "total_value": 0.0,
            }

            vendor: Dict[str, Any] = random.choice(self.vendors)
            carrier: Dict[str, Any] = random.choice(self.carriers)

            num_lines: int = weighted_choice(lines_per_order, lines_weights)
            order_lines_list: List[Dict[str, Any]] = []
            total_value: float = 0.0

            for li in range(num_lines):
                product: Dict[str, Any] = random.choice(self.products)
                qty: int = random.randint(1, 100)
                unit_price: float = product["unit_price"]
                confirmed_qty: float = float(qty)

                # In-full failure: some lines get confirmed qty < ordered qty
                in_full_roll: float = random.random()
                if in_full_roll > vendor["in_full_rate"]:
                    confirmed_qty = round(qty * random.uniform(0.3, 0.95), 0)

                line: Dict[str, Any] = {
                    "line_number": li + 1,
                    "product_id": ((oi * num_lines + li) % self.product_count) + 1,
                    "sku": product["sku"],
                    "product_name": product["product_name"],
                    "category": product["category"],
                    "ordered_qty": qty,
                    "confirmed_qty": confirmed_qty,
                    "unit_price": unit_price,
                    "line_total": round(confirmed_qty * unit_price, 2) if status != "pending" else round(qty * unit_price, 2),
                    "partial_delivery_allowed": random.random() > 0.2,
                }
                total_value += line["line_total"]
                order_lines_list.append(line)

            order["total_value"] = round(total_value, 2)
            self.orders.append(order)

            for line in order_lines_list:
                line["order_number"] = order["order_number"]
                self.order_lines.append(line)

            if status in ("completed", "shipped", "pending"):
                self._generate_shipments(order, order_lines_list, vendor, carrier)

    def _generate_shipments(
        self,
        order: Dict[str, Any],
        order_lines_list: List[Dict[str, Any]],
        vendor: Dict[str, Any],
        carrier: Dict[str, Any],
    ) -> None:
        """Generate 1-2 shipments for an order with delivery lines."""
        order_number: str = order["order_number"]
        order_status: str = order["order_status"]
        order_date: datetime.date = order["order_date"]
        requested_date: datetime.date = order["requested_delivery_date"]

        num_shipments: int = 1 if random.random() > 0.15 else 2
        for si in range(num_shipments):
            shipment_number: str = f"SHIP-{order_number}-{si+1}"

            # On-time tolerance matches docs/thresholds.md exactly: delivery must
            # land on the requested date or up to 1 day early. Anything after the
            # requested date is late. (Previously "not late" shipments still got
            # a +0..7 day offset, so on-time deliveries almost never actually
            # landed within the SLA window and every vendor looked like a
            # critical OTIF failure regardless of its configured otif_rate.)
            is_late: bool = random.random() > carrier["on_time_rate"]
            if is_late:
                actual_delivery: datetime.date = requested_date + datetime.timedelta(
                    days=random.randint(1, 15)
                )
            else:
                actual_delivery = requested_date - datetime.timedelta(
                    days=random.randint(0, 1)
                )

            shipment: Dict[str, Any] = {
                "shipment_number": shipment_number,
                "order_number": order_number,
                "carrier_code": carrier["code"],
                "carrier_name": carrier["name"],
                "carrier_mode": carrier["mode"],
                "vendor_code": vendor["code"],
                "vendor_region": vendor["region"],
                "shipping_point": f"WH-{random.choice(['EAST','CENTRAL','WEST','SOUTH'])}",
                "route": f"RTE-{random.randint(10,99)}",
                "planned_ship_date": order_date + datetime.timedelta(days=random.randint(1, 5)),
                "planned_delivery_date": requested_date,
                "actual_ship_date": order_date + datetime.timedelta(days=random.randint(1, 8)),
                "actual_delivery_date": actual_delivery if order_status != "pending" else None,
                "shipment_status": "delivered" if order_status == "completed" else "shipped" if order_status == "shipped" else "pending",
                "delivery_type": "outbound",
                "incoterm": random.choice(["FOB", "CIF", "DDP", "EXW"]),
            }
            self.shipments.append(shipment)

            if order_status in ("completed", "shipped"):
                for line in order_lines_list:
                    delivered_qty: float = float(line["confirmed_qty"])

                    if random.random() > vendor["in_full_rate"]:
                        delivered_qty = round(delivered_qty * random.uniform(0.3, 0.95), 0)

                    damage_qty: float = 0.0
                    if random.random() > 0.95:
                        damage_qty = round(delivered_qty * random.uniform(0.01, 0.15), 0)

                    dl: Dict[str, Any] = {
                        "shipment_number": shipment_number,
                        "order_number": order_number,
                        "line_number": line["line_number"],
                        "product_id": line["product_id"],
                        "sku": line["sku"],
                        "delivered_qty": delivered_qty,
                        "damage_qty": damage_qty,
                    }
                    self.delivery_lines.append(dl)

                    shortfall: float = float(line["confirmed_qty"]) - float(delivered_qty)
                    if shortfall > 0 and random.random() > 0.4:
                        self.backorders.append({
                            "order_number": order_number,
                            "line_number": line["line_number"],
                            "product_id": line["product_id"],
                            "backorder_qty": shortfall,
                            "estimated_fill_date": actual_delivery + datetime.timedelta(days=random.randint(3, 30)),
                            "status": "open",
                            "created_at": actual_delivery,
                        })

    # ------------------------------------------------------------------
    # Database helpers
    # ------------------------------------------------------------------

    @staticmethod
    def _truncate_tables(cursor: CursorObj) -> None:
        """Truncate all tables in dependency order (children first)."""
        for t in TRUNCATION_ORDER:
            if t not in TABLE_WHITELIST:
                raise ValueError(f"Unknown table name: {t}")
            cursor.execute(f"DELETE FROM {t}")

    # Single source of truth for DDL: sql/01_schema/generic_dw_tables.sql.
    # Keeping schema defined in exactly one place prevents drift between
    # the Postgres/SQLite bootstrap path and this generator's own tables.
    _SCHEMA_FILE: Path = Path(__file__).resolve().parent / "01_schema" / "generic_dw_tables.sql"

    @classmethod
    def _create_generic_tables(cls, cursor: CursorObj) -> None:
        sql = cls._SCHEMA_FILE.read_text()
        if hasattr(cursor, 'executescript'):
            cursor.executescript(sql)
        else:
            cursor.execute(sql)

    @staticmethod
    def _get_insert_batches(generator: "OTIFDataGenerator") -> Dict[str, List[Tuple]]:
        """Prepare data as lists of tuples for batch insertion."""
        return {
            "customers": [
                (i + 1, c["customer_code"], c["customer_name"], c["region"], c["country"])
                for i, c in enumerate(generator.customers)
            ],
            "vendors": [
                (i + 1, v["code"], v["name"], v["region"], "US",
                 v["tier"], v["otif_rate"], v["on_time_rate"], v["in_full_rate"])
                for i, v in enumerate(generator.vendors)
            ],
            "products": [
                (i + 1, p["sku"], p["product_name"], p["category"],
                 p["subcategory"], p["unit_of_measure"], p["unit_price"])
                for i, p in enumerate(generator.products)
            ],
            "carriers": [
                (i + 1, c["code"], c["name"], c["mode"], c["on_time_rate"])
                for i, c in enumerate(generator.carriers)
            ],
            "orders": [
                (i + 1, o["order_number"], o["customer_code"],
                 o["order_date"].isoformat(), o["requested_delivery_date"].isoformat(),
                 o["order_status"], o["channel"], o["currency"], o["total_value"])
                for i, o in enumerate(generator.orders)
            ],
            "order_lines": [
                (i + 1, ol["order_number"], ol["line_number"], ol["sku"],
                 ol["product_name"], ol["category"], ol["ordered_qty"],
                 ol["confirmed_qty"], ol["unit_price"], ol["line_total"],
                 1 if ol["partial_delivery_allowed"] else 0)
                for i, ol in enumerate(generator.order_lines)
            ],
            "shipments": [
                (i + 1, s["shipment_number"], s["order_number"], s["carrier_code"],
                 s["carrier_name"], s["carrier_mode"], s["vendor_code"], s["vendor_region"],
                 s["shipping_point"], s["route"],
                 str(s["planned_ship_date"]) if s["planned_ship_date"] else None,
                 str(s["planned_delivery_date"]) if s["planned_delivery_date"] else None,
                 str(s["actual_ship_date"]) if s["actual_ship_date"] else None,
                 str(s["actual_delivery_date"]) if s["actual_delivery_date"] else None,
                 s["shipment_status"], s["delivery_type"], s["incoterm"])
                for i, s in enumerate(generator.shipments)
            ],
            "delivery_lines": [
                (i + 1, dl["shipment_number"], dl["order_number"], dl["line_number"],
                 dl["product_id"], dl["sku"], dl["delivered_qty"], dl["damage_qty"])
                for i, dl in enumerate(generator.delivery_lines)
            ],
            "backorders": [
                (i + 1, bo["order_number"], bo["line_number"], bo["product_id"],
                 bo["backorder_qty"],
                 str(bo["estimated_fill_date"]) if bo["estimated_fill_date"] else None,
                 bo["status"],
                 str(bo["created_at"]) if bo["created_at"] else None)
                for i, bo in enumerate(generator.backorders)
            ],
        }

    SQL_INSERT_TEMPLATES: Dict[str, str] = {
        "customers": "INSERT INTO customers VALUES (?,?,?,?,?)",
        "vendors": "INSERT INTO vendors VALUES (?,?,?,?,?,?,?,?,?)",
        "products": "INSERT INTO products VALUES (?,?,?,?,?,?,?)",
        "carriers": "INSERT INTO carriers VALUES (?,?,?,?,?)",
        "orders": "INSERT INTO orders VALUES (?,?,?,?,?,?,?,?,?)",
        "order_lines": "INSERT INTO order_lines VALUES (?,?,?,?,?,?,?,?,?,?,?)",
        "shipments": "INSERT INTO shipments VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
        "delivery_lines": "INSERT INTO delivery_lines VALUES (?,?,?,?,?,?,?,?)",
        "backorders": "INSERT INTO backorders VALUES (?,?,?,?,?,?,?,?)",
    }

    # ------------------------------------------------------------------
    # Output methods
    # ------------------------------------------------------------------

    def to_sqlite(self, db_path: str) -> None:
        """Write data to SQLite database."""
        import sqlite3
        conn: sqlite3.Connection = sqlite3.connect(db_path)
        cursor: sqlite3.Cursor = conn.cursor()

        self._create_generic_tables(cursor)

        cursor.execute("SELECT COUNT(*) FROM customers")
        if cursor.fetchone()[0] > 0:
            print(f"  -> Database at {db_path} already has data. Truncating.")
            self._truncate_tables(cursor)

        self._insert_all_batches(cursor, paramstyle="qmark")
        conn.commit()
        conn.close()
        print(f"  -> Wrote to SQLite: {db_path}")

    def to_postgresql(self, connection_string: str) -> None:
        """Write data to PostgreSQL database."""
        import psycopg2
        conn: Any = psycopg2.connect(connection_string)
        cursor: Any = conn.cursor()

        self._create_generic_tables(cursor)

        cursor.execute("SELECT COUNT(*) FROM customers")
        if cursor.fetchone()[0] > 0:
            self._truncate_tables(cursor)

        self._insert_all_batches(cursor, paramstyle="format")
        conn.commit()
        conn.close()
        print(f"  -> Wrote to PostgreSQL: {connection_string}")

    def _insert_all_batches(self, cursor: CursorObj, paramstyle: str = "qmark") -> None:
        """Insert all data using batch executemany.

        SQL_INSERT_TEMPLATES are authored in sqlite3's qmark style ("?").
        psycopg2 requires pyformat style ("%s"), so translate placeholders
        for the postgres path — the two drivers are not paramstyle-compatible.
        """
        batches: Dict[str, List[Tuple]] = self._get_insert_batches(self)
        for table in TABLE_NAMES:
            rows: List[Tuple] = batches[table]
            if rows:
                stmt: str = self.SQL_INSERT_TEMPLATES[table]
                if paramstyle == "format":
                    stmt = stmt.replace("?", "%s")
                cursor.executemany(stmt, rows)

    def to_csv(self, output_dir: str) -> None:
        """Write data to CSV files."""
        os.makedirs(output_dir, exist_ok=True)

        self._write_csv(os.path.join(output_dir, "customers.csv"),
                        ["customer_code", "customer_name", "region", "country"],
                        self.customers)
        self._write_csv(os.path.join(output_dir, "vendors.csv"),
                        ["vendor_code", "vendor_name", "region", "tier", "otif_rate", "on_time_rate", "in_full_rate"],
                        self.vendors)
        self._write_csv(os.path.join(output_dir, "products.csv"),
                        ["sku", "product_name", "category", "subcategory", "unit_of_measure", "unit_price"],
                        self.products)
        self._write_csv(os.path.join(output_dir, "carriers.csv"),
                        ["carrier_code", "carrier_name", "mode", "on_time_rate"],
                        self.carriers)
        self._write_csv(os.path.join(output_dir, "orders.csv"),
                        ["order_number", "customer_code", "order_date", "requested_delivery_date",
                         "order_status", "channel", "currency", "total_value"],
                        self.orders)
        self._write_csv(os.path.join(output_dir, "order_lines.csv"),
                        ["order_number", "line_number", "sku", "product_name", "category",
                         "ordered_qty", "confirmed_qty", "unit_price", "line_total",
                         "partial_delivery_allowed"],
                        self.order_lines)
        self._write_csv(os.path.join(output_dir, "shipments.csv"),
                        ["shipment_number", "order_number", "carrier_code", "carrier_name",
                         "carrier_mode", "vendor_code", "vendor_region", "shipping_point", "route",
                         "planned_ship_date", "planned_delivery_date", "actual_ship_date",
                         "actual_delivery_date", "shipment_status", "delivery_type", "incoterm"],
                        self.shipments)
        self._write_csv(os.path.join(output_dir, "delivery_lines.csv"),
                        ["shipment_number", "order_number", "line_number", "product_id", "sku",
                         "delivered_qty", "damage_qty"],
                        self.delivery_lines)
        self._write_csv(os.path.join(output_dir, "backorders.csv"),
                        ["order_number", "line_number", "product_id", "backorder_qty",
                         "estimated_fill_date", "status", "created_at"],
                        self.backorders)
        print(f"  -> Wrote CSV files to {output_dir}/")

    def _write_csv(self, path: str, fieldnames: List[str], rows: List[Dict[str, Any]]) -> None:
        with open(path, "w", newline="") as f:
            writer: csv.DictWriter = csv.DictWriter(f, fieldnames=fieldnames)
            writer.writeheader()
            for row in rows:
                writer.writerow({k: row.get(k) for k in fieldnames})
        print(f"    Created: {path}")

    def summary(self) -> None:
        print(f"\nGenerated: {len(self.orders):,} orders")
        print(f"           {len(self.order_lines):,} order lines")
        print(f"           {len(self.shipments):,} shipments")
        print(f"           {len(self.delivery_lines):,} delivery lines")
        print(f"           {len(self.backorders):,} backorders")
        print(f"           {len(self.customers)} customers, {len(self.vendors)} vendors, "
              f"{len(self.products)} products, {len(self.carriers)} carriers")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def validate_positive(value: str) -> int:
    """Argparse type: validate positive integer."""
    ival: int = int(value)
    if ival <= 0:
        raise argparse.ArgumentTypeError(f"Must be positive: {value}")
    return ival


def main() -> None:
    parser: argparse.ArgumentParser = argparse.ArgumentParser(
        description="Generate OTIF seed data for PostgreSQL, SQLite, or CSV."
    )
    parser.add_argument("--db", choices=["sqlite", "postgresql", "csv"],
                        default="sqlite", help="Output format")
    parser.add_argument("--connection", default="otif_seed.db",
                        help="SQLite path or PostgreSQL connection string")
    parser.add_argument("--output-dir", default="./data",
                        help="CSV output directory (only for --db csv)")
    parser.add_argument("--orders", type=validate_positive, default=DEFAULT_ORDER_COUNT,
                        help=f"Number of orders to generate (default: {DEFAULT_ORDER_COUNT})")
    parser.add_argument("--days", type=validate_positive, default=DEFAULT_DAYS_HISTORY,
                        help=f"Days of history (default: {DEFAULT_DAYS_HISTORY})")
    parser.add_argument("--seed", type=validate_positive, default=DEFAULT_SEED,
                        help=f"Random seed (default: {DEFAULT_SEED})")
    parser.add_argument("--customers", type=validate_positive, default=DEFAULT_CUSTOMER_COUNT)
    parser.add_argument("--products", type=validate_positive, default=DEFAULT_PRODUCT_COUNT)

    args: argparse.Namespace = parser.parse_args()

    print("OTIF Seed Data Generator")
    print(f"  Orders:   {args.orders:,}")
    print(f"  History:  {args.days} days")
    print(f"  Seed:     {args.seed}")
    print(f"  Output:   {args.db}")

    try:
        print("  Generating master data...")
        gen: OTIFDataGenerator = OTIFDataGenerator(
            order_count=args.orders,
            days_history=args.days,
            seed=args.seed,
            customer_count=args.customers,
            product_count=args.products,
        )

        print("  Generating orders with shipments...")
        gen.generate_orders()
        gen.summary()

        print("\nWriting data...")
        if args.db == "sqlite":
            gen.to_sqlite(args.connection)
        elif args.db == "postgresql":
            gen.to_postgresql(args.connection)
        else:
            gen.to_csv(args.output_dir)

        print("Done.")
    except Exception as e:
        print(f"ERROR: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
