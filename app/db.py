"""Database models and session handling."""
import datetime as dt
import uuid
from functools import lru_cache

from sqlalchemy import BigInteger, DateTime, Integer, String, Text, create_engine, text
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from .config import get_settings


def utcnow() -> dt.datetime:
    return dt.datetime.now(dt.timezone.utc)


class Base(DeclarativeBase):
    pass


class Order(Base):
    __tablename__ = "orders"

    id: Mapped[str] = mapped_column(String(36), primary_key=True, default=lambda: str(uuid.uuid4()))
    customer_id: Mapped[str] = mapped_column(String(64), index=True)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    currency: Mapped[str] = mapped_column(String(3))
    # NEW -> PROCESSED | FAILED
    status: Mapped[str] = mapped_column(String(16), default="NEW", index=True)
    idempotency_key: Mapped[str | None] = mapped_column(String(128), unique=True, nullable=True)
    created_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)
    processed_at: Mapped[dt.datetime | None] = mapped_column(DateTime(timezone=True), nullable=True)


class QueueMessage(Base):
    """Backing table for the `db` queue backend (local development and tests)."""

    __tablename__ = "queue_messages"

    id: Mapped[int] = mapped_column(Integer, primary_key=True, autoincrement=True)
    payload: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(String(16), default="ready", index=True)  # ready|inflight|dead
    attempts: Mapped[int] = mapped_column(Integer, default=0)
    visible_at: Mapped[dt.datetime] = mapped_column(DateTime(timezone=True), default=utcnow)


class FaultFlag(Base):
    """Fault injection switches live in the database so every replica sees them."""

    __tablename__ = "fault_flags"

    name: Mapped[str] = mapped_column(String(64), primary_key=True)
    value: Mapped[str] = mapped_column(String(64))


@lru_cache
def get_engine():
    url = get_settings().database_url
    kwargs = {"pool_pre_ping": True}
    if url.startswith("sqlite"):
        kwargs["connect_args"] = {"check_same_thread": False}
    else:
        kwargs.update(pool_size=5, max_overflow=5, pool_recycle=300)
    return create_engine(url, **kwargs)


@lru_cache
def get_sessionmaker():
    return sessionmaker(bind=get_engine(), expire_on_commit=False)


def init_db() -> None:
    Base.metadata.create_all(get_engine())


def ping_db() -> bool:
    with get_engine().connect() as conn:
        conn.execute(text("SELECT 1"))
    return True


def session_scope() -> Session:
    return get_sessionmaker()()
