#!/usr/bin/env python3
"""Repeatable, idempotent loader for legacy/legacy_dump.sql into PostgreSQL 16.

Handles all discovered data-quality anomalies explicitly:
1. Preserves 9 NULL customer emails (nullable email column; logs count).
2. Preserves all 500 customer PKs despite 12 case-insensitive duplicate emails
   (stores non-unique email_normalized instead of failing a unique constraint).
3. Normalizes 37 dirty invoice statuses ('paid ' -> 'PAID') via UPPER(TRIM(status)).
4. Converts naive America/New_York timestamps to UTC TIMESTAMPTZ deterministically,
   including the spring-forward DST gap timestamp (2024-03-10 02:38:50 -> fold=0).
5. Preserves sequence high-water marks (customers_id_seq=637, invoices_id_seq=12200)
   and attaches DEFAULT nextval(...) to both primary keys.

Usage:
    python3 scripts/migration/load_legacy.py [--dump legacy/legacy_dump.sql] [--dsn ...]
"""
import argparse
import datetime as dt
import os
import re
import sys
from dataclasses import dataclass
from decimal import Decimal
from zoneinfo import ZoneInfo

import psycopg

NY_TZ = ZoneInfo("America/New_York")

TARGET_DDL = """
CREATE SEQUENCE IF NOT EXISTS customers_id_seq;
CREATE SEQUENCE IF NOT EXISTS invoices_id_seq;

CREATE TABLE IF NOT EXISTS customers (
    id               integer PRIMARY KEY DEFAULT nextval('customers_id_seq'),
    name             text NOT NULL,
    email            text,
    email_normalized text,
    country          char(2) NOT NULL,
    created_at       timestamptz NOT NULL
);

CREATE TABLE IF NOT EXISTS invoices (
    id          integer PRIMARY KEY DEFAULT nextval('invoices_id_seq'),
    customer_id integer NOT NULL REFERENCES customers(id),
    amount      numeric(12,2) NOT NULL CHECK (amount >= 0),
    currency    char(3) NOT NULL,
    status      text NOT NULL CHECK (status IN ('PAID', 'FAILED', 'REFUNDED', 'PENDING')),
    issued_at   timestamptz NOT NULL
);

CREATE INDEX IF NOT EXISTS customers_email_norm_idx ON customers(email_normalized);
CREATE INDEX IF NOT EXISTS invoices_customer_idx ON invoices(customer_id);
CREATE INDEX IF NOT EXISTS invoices_issued_idx ON invoices(issued_at);
"""


@dataclass
class ParsedDump:
    customers: list[tuple]
    invoices: list[tuple]
    customers_seq: int
    invoices_seq: int
    stats: dict


def ny_wall_to_utc(ts_str: str) -> tuple[dt.datetime, bool]:
    """Convert naive America/New_York timestamp to UTC, flagging non-existent DST gap timestamps."""
    naive = dt.datetime.strptime(ts_str, "%Y-%m-%d %H:%M:%S")
    aware = naive.replace(tzinfo=NY_TZ, fold=0)
    utc_dt = aware.astimezone(dt.timezone.utc)
    roundtrip = utc_dt.astimezone(NY_TZ).replace(tzinfo=None)
    return utc_dt, (roundtrip != naive)


def parse_legacy_dump(dump_path: str) -> ParsedDump:
    with open(dump_path, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\n") for line in f]

    mode = None
    customers: list[tuple] = []
    invoices: list[tuple] = []
    customers_seq = 1
    invoices_seq = 1

    null_emails = 0
    seen_emails: dict[str, int] = {}
    dup_emails = 0
    dirty_statuses = 0
    dst_gap_timestamps = 0

    for line in lines:
        if line.startswith("COPY customers "):
            mode = "customers"
            continue
        if line.startswith("COPY invoices "):
            mode = "invoices"
            continue
        if line == r"\.":
            mode = None
            continue

        if mode is None:
            m_cust = re.match(r"SELECT setval\('customers_id_seq',\s*(\d+)\);", line)
            if m_cust:
                customers_seq = int(m_cust.group(1))
            m_inv = re.match(r"SELECT setval\('invoices_id_seq',\s*(\d+)\);", line)
            if m_inv:
                invoices_seq = int(m_inv.group(1))
            continue

        parts = line.split("\t")
        if mode == "customers":
            cid, name, raw_email, country, created_str = parts
            if raw_email == r"\N" or not raw_email.strip():
                email = None
                email_norm = None
                null_emails += 1
            else:
                email = raw_email.strip()
                email_norm = email.lower()
                if email_norm in seen_emails:
                    dup_emails += 1
                seen_emails[email_norm] = seen_emails.get(email_norm, 0) + 1
            created_utc, is_dst_gap = ny_wall_to_utc(created_str)
            if is_dst_gap:
                dst_gap_timestamps += 1
            customers.append((int(cid), name, email, email_norm, country.strip(), created_utc))

        elif mode == "invoices":
            iid, cid, amount_str, currency, raw_status, issued_str = parts
            norm_status = raw_status.strip().upper()
            if norm_status != raw_status:
                dirty_statuses += 1
            issued_utc, is_dst_gap = ny_wall_to_utc(issued_str)
            if is_dst_gap:
                dst_gap_timestamps += 1
            invoices.append(
                (int(iid), int(cid), Decimal(amount_str), currency.strip().upper(), norm_status, issued_utc)
            )

    stats = {
        "customers": len(customers),
        "invoices": len(invoices),
        "null_emails": null_emails,
        "duplicate_normalized_emails": dup_emails,
        "dirty_statuses_normalized": dirty_statuses,
        "dst_gap_timestamps_handled": dst_gap_timestamps,
        "customers_seq": customers_seq,
        "invoices_seq": invoices_seq,
    }
    return ParsedDump(customers, invoices, customers_seq, invoices_seq, stats)


def resolve_dsn(cli_dsn: str | None) -> str:
    if cli_dsn:
        return cli_dsn
    env_url = os.getenv("DATABASE_URL", "")
    if env_url:
        return env_url.replace("postgresql+psycopg://", "postgresql://")
    host = os.getenv("DB_HOST", "localhost")
    port = os.getenv("DB_PORT", "5432")
    name = os.getenv("DB_NAME", "orders")
    user = os.getenv("DB_USER", "orders")
    password = os.getenv("DB_PASSWORD", "orders")
    return f"postgresql://{user}:{password}@{host}:{port}/{name}"


def load_into_postgres(parsed: ParsedDump, dsn: str) -> None:
    with psycopg.connect(dsn) as conn:
        with conn.cursor() as cur:
            cur.execute(TARGET_DDL)
            # Repeatable rehearsal: truncate cleanly inside the transaction before reloading
            cur.execute("TRUNCATE TABLE invoices, customers RESTART IDENTITY CASCADE")
            cur.executemany(
                """
                INSERT INTO customers (id, name, email, email_normalized, country, created_at)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                parsed.customers,
            )
            cur.executemany(
                """
                INSERT INTO invoices (id, customer_id, amount, currency, status, issued_at)
                VALUES (%s, %s, %s, %s, %s, %s)
                """,
                parsed.invoices,
            )
            cur.execute("SELECT setval('customers_id_seq', %s, true)", (parsed.customers_seq,))
            cur.execute("SELECT setval('invoices_id_seq', %s, true)", (parsed.invoices_seq,))
        conn.commit()


def main() -> int:
    parser = argparse.ArgumentParser(description="Repeatable legacy billing dump loader")
    parser.add_argument("--dump", default="legacy/legacy_dump.sql", help="Path to legacy_dump.sql")
    parser.add_argument("--dsn", default=None, help="PostgreSQL connection string")
    args = parser.parse_args()

    parsed = parse_legacy_dump(args.dump)
    dsn = resolve_dsn(args.dsn)
    load_into_postgres(parsed, dsn)

    print("Repeatable load complete:")
    for k, v in parsed.stats.items():
        print(f"  {k}: {v}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
