#!/usr/bin/env python3
"""Legacy nightly settlement job (runs from cron on the on-prem VM at 01:30 server time).

Reads yesterday's PAID invoices and writes a CSV to /var/settlements, then calls a webhook.
Hard-coded paths and secrets are part of the problem you are asked to migrate.

Usage: python nightly_settlement.py [YYYY-MM-DD]
"""
import csv
import datetime as dt
import os
import sys
import urllib.request

import psycopg

DSN = "host=localhost dbname=billing user=billing password=billing123"  # legacy secret in code
OUT_DIR = "/var/settlements"
WEBHOOK = "http://10.20.30.40:9000/settlement-done"  # on-prem internal address


def main() -> None:
    day = dt.date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else dt.date.today() - dt.timedelta(days=1)
    start = dt.datetime.combine(day, dt.time.min)
    end = start + dt.timedelta(days=1)

    with psycopg.connect(DSN) as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT i.id, c.email, i.amount, i.currency, i.issued_at
            FROM invoices i JOIN customers c ON c.id = i.customer_id
            WHERE i.status = 'PAID' AND i.issued_at >= %s AND i.issued_at < %s
            ORDER BY i.id
            """,
            (start, end),
        )
        rows = cur.fetchall()

    os.makedirs(OUT_DIR, exist_ok=True)
    path = os.path.join(OUT_DIR, f"settlement_{day:%Y%m%d}.csv")
    with open(path, "w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["invoice_id", "email", "amount", "currency", "issued_at"])
        w.writerows(rows)

    urllib.request.urlopen(urllib.request.Request(WEBHOOK, data=path.encode(), method="POST"), timeout=5)
    print(f"wrote {len(rows)} rows to {path}")


if __name__ == "__main__":
    main()
