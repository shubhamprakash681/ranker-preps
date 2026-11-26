import datetime as dt
from decimal import Decimal
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "scripts" / "migration"))

from load_legacy import parse_legacy_dump  # noqa: E402
from validate_legacy import checksum_customers, checksum_invoices  # noqa: E402
from app.settlement import build_settlement_csv, settlement_window_utc  # noqa: E402


def test_legacy_dump_parsing_and_data_quality_rules():
    parsed = parse_legacy_dump("legacy/legacy_dump.sql")
    assert parsed.stats["customers"] == 500
    assert parsed.stats["invoices"] == 8000
    assert parsed.stats["null_emails"] == 9
    assert parsed.stats["duplicate_normalized_emails"] == 12
    assert parsed.stats["dirty_statuses_normalized"] == 37
    assert parsed.stats["dst_gap_timestamps_handled"] == 1
    assert parsed.customers_seq == 637
    assert parsed.invoices_seq == 12200

    # Checksums are deterministic
    assert checksum_customers(parsed.customers) == checksum_customers(list(reversed(parsed.customers)))
    assert checksum_invoices(parsed.invoices) == checksum_invoices(list(reversed(parsed.invoices)))


def test_settlement_csv_and_ny_window():
    start_utc, end_utc = settlement_window_utc(dt.date(2024, 3, 10))
    # 2024-03-10 is US spring-forward day (23 hours long in America/New_York)
    assert (end_utc - start_utc).total_seconds() == 23 * 3600

    csv_bytes = build_settlement_csv(
        [(10, "", Decimal("42.50"), "USD", dt.datetime(2024, 3, 10, 12, 0, tzinfo=dt.timezone.utc))]
    ).decode("utf-8")
    assert "invoice_id,email,amount,currency,issued_at" in csv_bytes
    assert "10,,42.50,USD,2024-03-10T12:00:00+00:00" in csv_bytes
