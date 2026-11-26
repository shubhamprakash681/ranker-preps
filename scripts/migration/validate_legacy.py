#!/usr/bin/env python3
"""Validate that source (legacy/legacy_dump.sql) and target (PostgreSQL 16) agree.

Checks:
- Exact row counts (customers, invoices, counts by status and currency)
- Canonical SHA-256 content checksums for all customers and invoices
- Foreign key integrity (zero orphan invoices)
- Sequence high-water marks preserved
- All discovered data-quality issues verified on target

Usage:
    python3 scripts/migration/validate_legacy.py [--dump legacy/legacy_dump.sql] [--dsn ...]
"""
import argparse
import datetime as dt
import hashlib
import os
import sys

import psycopg

from load_legacy import parse_legacy_dump, resolve_dsn


def _fmt_utc(val: dt.datetime) -> str:
    if val.tzinfo is None:
        val = val.replace(tzinfo=dt.timezone.utc)
    return val.astimezone(dt.timezone.utc).isoformat()


def checksum_customers(rows: list[tuple]) -> str:
    h = hashlib.sha256()
    for cid, name, email, email_norm, country, created_utc in sorted(rows, key=lambda r: r[0]):
        line = f"{cid}|{name}|{email or ''}|{email_norm or ''}|{country.strip()}|{_fmt_utc(created_utc)}\n"
        h.update(line.encode("utf-8"))
    return h.hexdigest()


def checksum_invoices(rows: list[tuple]) -> str:
    h = hashlib.sha256()
    for iid, cid, amount, currency, status, issued_utc in sorted(rows, key=lambda r: r[0]):
        line = f"{iid}|{cid}|{amount:.2f}|{currency.strip()}|{status}|{_fmt_utc(issued_utc)}\n"
        h.update(line.encode("utf-8"))
    return h.hexdigest()


def validate(dump_path: str, dsn: str) -> list[str]:
    parsed = parse_legacy_dump(dump_path)
    src_cust_hash = checksum_customers(parsed.customers)
    src_inv_hash = checksum_invoices(parsed.invoices)

    errors: list[str] = []
    with psycopg.connect(dsn) as conn, conn.cursor() as cur:
        cur.execute(
            "SELECT id, name, email, email_normalized, country, created_at FROM customers ORDER BY id"
        )
        tgt_customers = cur.fetchall()

        cur.execute(
            "SELECT id, customer_id, amount, currency, status, issued_at FROM invoices ORDER BY id"
        )
        tgt_invoices = cur.fetchall()

        cur.execute("SELECT last_value FROM customers_id_seq")
        tgt_cust_seq = cur.fetchone()[0]

        cur.execute("SELECT last_value FROM invoices_id_seq")
        tgt_inv_seq = cur.fetchone()[0]

        cur.execute(
            "SELECT COUNT(*) FROM invoices i LEFT JOIN customers c ON c.id = i.customer_id WHERE c.id IS NULL"
        )
        orphan_count = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM customers WHERE email IS NULL")
        tgt_null_emails = cur.fetchone()[0]

        cur.execute("SELECT COUNT(*) FROM invoices WHERE status <> UPPER(TRIM(status))")
        tgt_dirty_status = cur.fetchone()[0]

        cur.execute("SELECT status, COUNT(*) FROM invoices GROUP BY status ORDER BY status")
        tgt_by_status = dict(cur.fetchall())

    tgt_cust_hash = checksum_customers(tgt_customers)
    tgt_inv_hash = checksum_invoices(tgt_invoices)

    if len(tgt_customers) != len(parsed.customers):
        errors.append(f"Customer row count mismatch: src={len(parsed.customers)} tgt={len(tgt_customers)}")
    if len(tgt_invoices) != len(parsed.invoices):
        errors.append(f"Invoice row count mismatch: src={len(parsed.invoices)} tgt={len(tgt_invoices)}")
    if src_cust_hash != tgt_cust_hash:
        errors.append(f"Customers SHA-256 mismatch: src={src_cust_hash} tgt={tgt_cust_hash}")
    if src_inv_hash != tgt_inv_hash:
        errors.append(f"Invoices SHA-256 mismatch: src={src_inv_hash} tgt={tgt_inv_hash}")
    if tgt_cust_seq != parsed.customers_seq:
        errors.append(f"customers_id_seq mismatch: src={parsed.customers_seq} tgt={tgt_cust_seq}")
    if tgt_inv_seq != parsed.invoices_seq:
        errors.append(f"invoices_id_seq mismatch: src={parsed.invoices_seq} tgt={tgt_inv_seq}")
    if orphan_count != 0:
        errors.append(f"Found {orphan_count} orphan invoices without matching customer")
    if tgt_dirty_status != 0:
        errors.append(f"Found {tgt_dirty_status} unnormalized invoice statuses in target")
    if tgt_null_emails != parsed.stats["null_emails"]:
        errors.append(f"NULL email count mismatch: src={parsed.stats['null_emails']} tgt={tgt_null_emails}")

    print("Validation Summary:")
    print(f"  customers: count={len(tgt_customers)} sha256={tgt_cust_hash}")
    print(f"  invoices : count={len(tgt_invoices)} sha256={tgt_inv_hash}")
    print(f"  sequences: customers_id_seq={tgt_cust_seq}, invoices_id_seq={tgt_inv_seq}")
    print(f"  by_status: {tgt_by_status}")
    print(f"  data_quality: null_emails={tgt_null_emails}, dirty_statuses_remaining={tgt_dirty_status}, orphans={orphan_count}")
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description="Validate migrated billing data against legacy_dump.sql")
    parser.add_argument("--dump", default="legacy/legacy_dump.sql", help="Path to legacy_dump.sql")
    parser.add_argument("--dsn", default=None, help="PostgreSQL connection string")
    args = parser.parse_args()

    dsn = resolve_dsn(args.dsn)
    errors = validate(args.dump, dsn)
    if errors:
        print("VALIDATION FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print("VALIDATION PASSED: source and target agree on row counts, SHA-256 checksums, sequences, and data quality.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
