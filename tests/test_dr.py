import datetime as dt
import os
import tempfile

if "DATABASE_URL" not in os.environ:
    _dr_tmp = tempfile.mkdtemp()
    os.environ["DATABASE_URL"] = f"sqlite:///{_dr_tmp}/dr_test.db"

from app import dr_backup, dr_restore  # noqa: E402
from app.db import Order, init_db, session_scope  # noqa: E402


def test_backup_export_and_restore_roundtrip_with_promotion_guard():
    init_db()
    order_id = "dr-test-order-1"
    with session_scope() as s:
        if s.get(Order, order_id) is None:
            s.add(
                Order(
                    id=order_id,
                    customer_id="c-dr",
                    amount_cents=999,
                    currency="USD",
                    status="PROCESSED",
                    processed_at=dt.datetime.now(dt.timezone.utc),
                )
            )
            s.commit()

    payload, meta = dr_backup.export_snapshot_bytes()
    assert meta["orders_count"] >= 1

    # Remove order locally, then restore from snapshot and promote
    with session_scope() as s:
        row = s.get(Order, order_id)
        if row is not None:
            s.delete(row)
            s.commit()

    res = dr_restore.restore_snapshot_bytes(payload, promote=True)
    assert res["skipped"] is False and res["promoted"] is True

    with session_scope() as s:
        restored = s.get(Order, order_id)
        assert restored is not None and restored.status == "PROCESSED"

    # Subsequent scheduled restore must NOT overwrite a promoted database
    skipped = dr_restore.restore_snapshot_bytes(payload, promote=False, allow_overwrite_promoted=False)
    assert skipped == {"skipped": True, "reason": "already_promoted"}
