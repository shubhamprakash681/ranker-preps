"""Scheduled DR backup task: dumps PostgreSQL orders & fault_flags to immutable S3 and GCS.

Runs on AWS ECS Fargate as the shared role AWS_BACKUP_TASK_ROLE_ARN (nwo-backup-task)
and federates to GCP_BACKUP_WRITER_SERVICE_ACCOUNT via GCP_AWS_WIF_PROVIDER (no keys).
"""
import datetime as dt
import gzip
import io
import json
import logging
import os
import sys
import tempfile

import boto3
from sqlalchemy import select

from .db import FaultFlag, Order, init_db, session_scope
from .logging_conf import configure_logging, log

logger = logging.getLogger("orders-backup")


def _serialize_dt(val: dt.datetime | None) -> str | None:
    if val is None:
        return None
    if val.tzinfo is None:
        val = val.replace(tzinfo=dt.timezone.utc)
    return val.astimezone(dt.timezone.utc).isoformat()


def export_snapshot_bytes(created_at: dt.datetime | None = None) -> tuple[bytes, dict]:
    """Serialize all orders and fault flags into a gzipped JSON payload."""
    init_db()
    ts = (created_at or dt.datetime.now(dt.timezone.utc)).astimezone(dt.timezone.utc)
    with session_scope() as s:
        orders = [
            {
                "id": o.id,
                "customer_id": o.customer_id,
                "amount_cents": o.amount_cents,
                "currency": o.currency,
                "status": o.status,
                "idempotency_key": o.idempotency_key,
                "created_at": _serialize_dt(o.created_at),
                "processed_at": _serialize_dt(o.processed_at),
            }
            for o in s.execute(select(Order).order_by(Order.created_at)).scalars()
        ]
        fault_flags = [
            {"name": f.name, "value": f.value}
            for f in s.execute(select(FaultFlag)).scalars()
        ]

    doc = {
        "schema_version": 1,
        "backup_timestamp_utc": ts.isoformat(),
        "orders": orders,
        "fault_flags": fault_flags,
    }
    buf = io.BytesIO()
    with gzip.GzipFile(fileobj=buf, mode="wb", mtime=0) as gz:
        gz.write(json.dumps(doc).encode("utf-8"))
    meta = {"timestamp": ts.strftime("%Y%m%dT%H%M%SZ"), "orders_count": len(orders)}
    return buf.getvalue(), meta


def upload_to_s3(bucket: str, key: str, payload: bytes) -> None:
    s3 = boto3.client("s3")
    s3.put_object(
        Bucket=bucket,
        Key=key,
        Body=payload,
        ContentType="application/gzip",
        ServerSideEncryption="aws:kms",
    )


def upload_to_gcs_wif(
    bucket: str,
    key: str,
    payload: bytes,
    wif_provider: str,
    backup_writer_sa: str,
    region: str,
) -> None:
    """Federate from AWS ECS task role to GCP via nwo-aws WIF without static keys."""
    from google.cloud import storage

    creds = boto3.Session().get_credentials()
    if creds is None:
        raise RuntimeError("No AWS credentials found for WIF federation")
    frozen = creds.get_frozen_credentials()
    os.environ["AWS_ACCESS_KEY_ID"] = frozen.access_key
    os.environ["AWS_SECRET_ACCESS_KEY"] = frozen.secret_key
    if frozen.token:
        os.environ["AWS_SESSION_TOKEN"] = frozen.token
    os.environ["AWS_REGION"] = region
    os.environ["AWS_DEFAULT_REGION"] = region

    audience = wif_provider if wif_provider.startswith("//iam.googleapis.com/") else f"//iam.googleapis.com/{wif_provider.lstrip('/')}"
    wif_config = {
        "universe_domain": "googleapis.com",
        "type": "external_account",
        "audience": audience,
        "subject_token_type": "urn:ietf:params:aws:token-type:aws4_request",
        "token_url": "https://sts.googleapis.com/v1/token",
        "service_account_impersonation_url": (
            f"https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/"
            f"{backup_writer_sa}:generateAccessToken"
        ),
        "credential_source": {
            "environment_id": "aws1",
            "regional_cred_verification_url": "https://sts.{region}.amazonaws.com?Action=GetCallerIdentity&Version=2011-06-15",
        },
    }

    with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False) as f:
        json.dump(wif_config, f)
        cred_path = f.name

    try:
        os.environ["GOOGLE_APPLICATION_CREDENTIALS"] = cred_path
        client = storage.Client()
        blob = client.bucket(bucket).blob(key)
        blob.upload_from_string(payload, content_type="application/gzip")
    finally:
        os.unlink(cred_path)


def main() -> int:
    configure_logging()
    aws_bucket = os.environ["AWS_BACKUP_BUCKET"]
    gcp_bucket = os.environ["GCP_BACKUP_BUCKET"]
    wif_provider = os.environ["GCP_AWS_WIF_PROVIDER"]
    backup_writer_sa = os.environ["GCP_BACKUP_WRITER_SERVICE_ACCOUNT"]
    region = os.getenv("AWS_DEFAULT_REGION", "us-east-1")

    payload, meta = export_snapshot_bytes()
    key = f"backups/orders-{meta['timestamp']}.json.gz"

    upload_to_s3(aws_bucket, key, payload)
    log(logger, logging.INFO, "backup written to S3", bucket=aws_bucket, key=key, orders=meta["orders_count"])

    upload_to_gcs_wif(gcp_bucket, key, payload, wif_provider, backup_writer_sa, region)
    log(logger, logging.INFO, "backup replicated to GCS", bucket=gcp_bucket, key=key, orders=meta["orders_count"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
