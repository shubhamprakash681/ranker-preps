"""Runtime configuration. Everything comes from environment variables so the same
container image runs unchanged on AWS (ECS Fargate) and GCP (Cloud Run)."""
import os
from dataclasses import dataclass
from functools import lru_cache


@dataclass(frozen=True)
class Settings:
    # Postgres in the cloud (postgresql+psycopg://user:pass@host:5432/db); sqlite is fine for unit tests.
    database_url: str
    # db | sqs | pubsub
    queue_backend: str
    # SQS queue URL, or the full Pub/Sub subscription path (projects/<p>/subscriptions/<s>)
    queue_name: str
    # Pub/Sub topic path (projects/<p>/topics/<t>) used for publishing. Ignored by other backends.
    pubsub_topic: str
    # local | s3 | gcs
    storage_backend: str
    # Bucket name for s3/gcs, directory for local
    storage_target: str
    # Poison messages are retried this many times by the worker's db backend before being parked as "dead"
    max_attempts: int
    service_name: str
    cloud: str
    log_level: str


def _database_url() -> str:
    """DATABASE_URL wins. Otherwise build it from DB_HOST/DB_NAME/DB_USER/DB_PASSWORD so the
    password can be injected on its own from Secrets Manager / Secret Manager."""
    url = os.getenv("DATABASE_URL")
    if url:
        return url
    host = os.getenv("DB_HOST")
    if host:
        from urllib.parse import quote_plus

        user = quote_plus(os.getenv("DB_USER", "orders"))
        password = quote_plus(os.getenv("DB_PASSWORD", ""))
        name = os.getenv("DB_NAME", "orders")
        port = os.getenv("DB_PORT", "5432")
        return f"postgresql+psycopg://{user}:{password}@{host}:{port}/{name}"
    return "sqlite:///./local.db"


@lru_cache
def get_settings() -> Settings:
    return Settings(
        database_url=_database_url(),
        queue_backend=os.getenv("QUEUE_BACKEND", "db"),
        queue_name=os.getenv("QUEUE_NAME", ""),
        pubsub_topic=os.getenv("PUBSUB_TOPIC", ""),
        storage_backend=os.getenv("STORAGE_BACKEND", "local"),
        storage_target=os.getenv("STORAGE_TARGET", "./receipts"),
        max_attempts=int(os.getenv("MAX_ATTEMPTS", "5")),
        service_name=os.getenv("SERVICE_NAME", "orders-api"),
        cloud=os.getenv("CLOUD", "local"),
        log_level=os.getenv("LOG_LEVEL", "INFO"),
    )
