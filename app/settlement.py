"""Cloud-native nightly settlement job (migrated from legacy/nightly_settlement.py).

Removes all host assumptions:
- Reads DB credentials from environment / Secrets Manager (no hardcoded DSN/password).
- Queries UTC-bounded America/New_York business day over normalized status = 'PAID'.
- Handles NULL customer emails cleanly without crashing.
- Writes settlement CSV durably to S3 / GCS / local via app.storage.get_storage().
- Optionally posts completion event to SETTLEMENT_WEBHOOK_URL when configured.

Usage:
    python -m app.settlement [YYYY-MM-DD]
"""
import csv
import datetime as dt
import io
import logging
import os
import sys
import urllib.request
from zoneinfo import ZoneInfo

import psycopg

from .config import get_settings
from .logging_conf import configure_logging, log
from .storage import get_storage

logger = logging.getLogger("orders-settlement")
NY_TZ = ZoneInfo("America/New_York")


def _pg_dsn() -> str:
    url = os.getenv("DATABASE_URL")
    if url:
        return url.replace("postgresql+psycopg://", "postgresql://")
    host = os.environ["DB_HOST"]
    port = os.getenv("DB_PORT", "5432")
    name = os.getenv("DB_NAME", "orders")
    user = os.getenv("DB_USER", "orders")
    password = os.environ["DB_PASSWORD"]
    return f"postgresql://{user}:{password}@{host}:{port}/{name}"


def settlement_window_utc(day: dt.date) -> tuple[dt.datetime, dt.datetime]:
    start_ny = dt.datetime.combine(day, dt.time.min, tzinfo=NY_TZ)
    end_ny = dt.datetime.combine(day + dt.timedelta(days=1), dt.time.min, tzinfo=NY_TZ)
    return start_ny.astimezone(dt.timezone.utc), end_ny.astimezone(dt.timezone.utc)


def build_settlement_csv(rows: list[tuple]) -> bytes:
    buf = io.StringIO()
    writer = csv.writer(buf)
    writer.writerow(["invoice_id", "email", "amount", "currency", "issued_at"])
    for inv_id, email, amount, currency, issued_at in rows:
        writer.writerow([inv_id, email or "", f"{amount:.2f}", currency.strip(), issued_at.isoformat()])
    return buf.getvalue().encode("utf-8")


def run_settlement(day: dt.date, dsn: str | None = None) -> tuple[str, int]:
    start_utc, end_utc = settlement_window_utc(day)
    conn_dsn = dsn or _pg_dsn()
    with psycopg.connect(conn_dsn) as conn, conn.cursor() as cur:
        cur.execute(
            """
            SELECT i.id, COALESCE(c.email, ''), i.amount, i.currency, i.issued_at
            FROM invoices i
            JOIN customers c ON c.id = i.customer_id
            WHERE UPPER(TRIM(i.status)) = 'PAID'
              AND i.issued_at >= %s
              AND i.issued_at < %s
            ORDER BY i.id
            """,
            (start_utc, end_utc),
        )
        rows = cur.fetchall()

    csv_bytes = build_settlement_csv(rows)
    object_key = f"settlements/settlement_{day:%Y%m%d}.csv"
    get_storage().put(object_key, csv_bytes)

    webhook = os.getenv("SETTLEMENT_WEBHOOK_URL", "").strip()
    if webhook:
        req = urllib.request.Request(webhook, data=object_key.encode("utf-8"), method="POST")
        urllib.request.urlopen(req, timeout=5)  # noqa: S310 - URL explicitly configured by operator

    log(
        logger,
        logging.INFO,
        "settlement complete",
        day=day.isoformat(),
        rows=len(rows),
        storage_backend=get_settings().storage_backend,
        storage_target=get_settings().storage_target,
        key=object_key,
    )
    return object_key, len(rows)


def main() -> int:
    configure_logging()
    default_day = dt.datetime.now(NY_TZ).date() - dt.timedelta(days=1)
    day = dt.date.fromisoformat(sys.argv[1]) if len(sys.argv) > 1 else default_day
    run_settlement(day)
    return 0


if __name__ == "__main__":
    sys.exit(main())
