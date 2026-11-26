"""DR restore job: loads the newest immutable backup from GCS into Cloud SQL.

Includes promotion protection so a scheduled restore never overwrites live data
after GCP has been promoted during a failover.
"""
import datetime as dt
import gzip
import json
import logging
import os
import sys

from sqlalchemy import text

from .db import FaultFlag, Order, get_engine, init_db, session_scope
from .logging_conf import configure_logging, log

logger = logging.getLogger("orders-restore")

DR_STATE_DDL = """
CREATE TABLE IF NOT EXISTS dr_state (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    updated_at TIMESTAMPTZ NOT NULL
)
"""


def _parse_dt(val: str | None) -> dt.datetime | None:
    if not val:
        return None
    parsed = dt.datetime.fromisoformat(val)
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed


def ensure_dr_state_table() -> None:
    dialect = get_engine().dialect.name
    ddl = DR_STATE_DDL
    if dialect == "sqlite":
        ddl = "CREATE TABLE IF NOT EXISTS dr_state (key TEXT PRIMARY KEY, value TEXT NOT NULL, updated_at TEXT NOT NULL)"
    with get_engine().begin() as conn:
        conn.execute(text(ddl))


def is_promoted() -> bool:
    ensure_dr_state_table()
    with get_engine().connect() as conn:
        row = conn.execute(text("SELECT value FROM dr_state WHERE key = 'promoted'")).fetchone()
    return bool(row and row[0] == "true")


def mark_promoted() -> None:
    ensure_dr_state_table()
    now = dt.datetime.now(dt.timezone.utc).isoformat()
    with get_engine().begin() as conn:
        conn.execute(
            text(
                "INSERT INTO dr_state (key, value, updated_at) VALUES ('promoted', 'true', :ts) "
                "ON CONFLICT (key) DO UPDATE SET value = 'true', updated_at = :ts"
            ),
            {"ts": now},
        )


def restore_snapshot_bytes(
    payload: bytes,
    *,
    promote: bool = False,
    allow_overwrite_promoted: bool = False,
) -> dict:
    """Restore a gzipped snapshot into the configured database."""
    init_db()
    ensure_dr_state_table()

    if is_promoted() and not allow_overwrite_promoted:
        log(logger, logging.WARNING, "skipping restore: standby already promoted")
        return {"skipped": True, "reason": "already_promoted"}

    doc = json.loads(gzip.decompress(payload).decode("utf-8"))
    orders = doc.get("orders", [])
    fault_flags = doc.get("fault_flags", [])

    with session_scope() as s:
        for item in orders:
            existing = s.get(Order, item["id"])
            if existing is None:
                s.add(
                    Order(
                        id=item["id"],
                        customer_id=item["customer_id"],
                        amount_cents=item["amount_cents"],
                        currency=item["currency"],
                        status=item["status"],
                        idempotency_key=item.get("idempotency_key"),
                        created_at=_parse_dt(item.get("created_at")) or dt.datetime.now(dt.timezone.utc),
                        processed_at=_parse_dt(item.get("processed_at")),
                    )
                )
            else:
                existing.status = item["status"]
                existing.processed_at = _parse_dt(item.get("processed_at"))

        for flag in fault_flags:
            existing_flag = s.get(FaultFlag, flag["name"])
            if existing_flag is None:
                s.add(FaultFlag(name=flag["name"], value=flag["value"]))
            else:
                existing_flag.value = flag["value"]
        s.commit()

    if promote:
        mark_promoted()

    return {
        "skipped": False,
        "backup_timestamp_utc": doc.get("backup_timestamp_utc"),
        "restored_orders": len(orders),
        "promoted": promote,
    }


def fetch_latest_from_gcs(bucket: str) -> tuple[str, bytes]:
    from google.cloud import storage

    client = storage.Client()
    blobs = sorted(
        (b for b in client.list_blobs(bucket, prefix="backups/orders-") if b.name.endswith(".json.gz")),
        key=lambda b: b.name,
    )
    if not blobs:
        raise RuntimeError(f"No backups found in gs://{bucket}/backups/")
    latest = blobs[-1]
    return latest.name, latest.download_as_bytes()


def main() -> int:
    configure_logging()
    bucket = os.environ["GCP_BACKUP_BUCKET"]
    promote = os.getenv("PROMOTE_ON_RESTORE", "false").lower() == "true"
    allow_overwrite = os.getenv("ALLOW_RESTORE_OVERWRITE", "false").lower() == "true"

    key, payload = fetch_latest_from_gcs(bucket)
    result = restore_snapshot_bytes(
        payload,
        promote=promote,
        allow_overwrite_promoted=allow_overwrite,
    )
    log(logger, logging.INFO, "restore finished", bucket=bucket, key=key, **result)
    return 0


if __name__ == "__main__":
    sys.exit(main())
