"""Northwind Orders API."""
import logging
import time
import uuid
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from pathlib import Path

from fastapi import FastAPI, Header, HTTPException, Request, Response
from fastapi.responses import FileResponse
from prometheus_client import CONTENT_TYPE_LATEST, generate_latest
from pydantic import BaseModel, Field, field_validator
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError

from . import faults
from .config import get_settings
from .db import Order, init_db, ping_db, session_scope
from .logging_conf import configure_logging, log, trace_id_var
from .metrics import DB_QUERY_LATENCY, HTTP_LATENCY, HTTP_REQUESTS, ORDERS_CREATED, QUEUE_DEPTH
from .queueing import get_queue

logger = logging.getLogger("orders-api")


@asynccontextmanager
async def lifespan(_: FastAPI):
    configure_logging()
    init_db()
    log(logger, logging.INFO, "startup complete", queue=get_settings().queue_backend,
        storage=get_settings().storage_backend)
    yield


app = FastAPI(title="Northwind Orders", version="1.0.0", lifespan=lifespan)


class OrderIn(BaseModel):
    customer_id: str = Field(min_length=1, max_length=64)
    amount_cents: int = Field(gt=0, le=100_000_000)
    currency: str = Field(min_length=3, max_length=3)

    @field_validator("currency")
    @classmethod
    def upper(cls, v: str) -> str:
        return v.upper()


def _order_json(o: Order) -> dict:
    return {
        "id": o.id,
        "customer_id": o.customer_id,
        "amount_cents": o.amount_cents,
        "currency": o.currency,
        "status": o.status,
        "created_at": o.created_at.isoformat(),
        "processed_at": o.processed_at.isoformat() if o.processed_at else None,
    }


@app.middleware("http")
async def observe(request: Request, call_next):
    trace_id = (
        request.headers.get("x-cloud-trace-context", "").split("/")[0]
        or request.headers.get("x-amzn-trace-id", "")
        or uuid.uuid4().hex
    )
    trace_id_var.set(trace_id)
    start = time.perf_counter()
    status = 500
    try:
        response = await call_next(request)
        status = response.status_code
        response.headers["x-trace-id"] = trace_id
        return response
    finally:
        elapsed = time.perf_counter() - start
        route = request.scope.get("route")
        route_path = getattr(route, "path", "unmatched")
        if route_path not in ("/metrics", "/healthz"):
            HTTP_REQUESTS.labels(request.method, route_path, str(status)).inc()
            HTTP_LATENCY.labels(request.method, route_path).observe(elapsed)
            log(logger, logging.INFO, "request", method=request.method, path=request.url.path,
                route=route_path, status=status, duration_ms=round(elapsed * 1000, 1))


@app.get("/", include_in_schema=False)
def web_page():
    """A small single-page UI: create orders, see recent orders and counts, and which cloud answered."""
    return FileResponse(Path(__file__).parent / "static" / "index.html", media_type="text/html",
                        headers={"Cache-Control": "no-store"})


@app.get("/healthz")
def healthz():
    """Liveness: the process is up. Never touches dependencies."""
    return {"status": "ok"}


@app.get("/readyz")
def readyz(response: Response):
    """Readiness: dependencies reachable."""
    try:
        ping_db()
    except Exception as exc:  # noqa: BLE001
        log(logger, logging.ERROR, "readiness failed", error=str(exc))
        response.status_code = 503
        return {"status": "unavailable", "db": "down"}
    return {"status": "ready", "db": "up"}


@app.get("/metrics")
def metrics():
    try:
        QUEUE_DEPTH.set(get_queue().depth())
    except Exception:  # noqa: BLE001 - metrics must not fail because the queue is unreachable
        QUEUE_DEPTH.set(-1)
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)


@app.get("/version")
def version():
    s = get_settings()
    return {"service": s.service_name, "cloud": s.cloud, "version": app.version}


@app.post("/orders", status_code=201)
def create_order(body: OrderIn, idempotency_key: str | None = Header(default=None)):
    try:
        faults.apply_request_faults()
    except RuntimeError as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc

    db_start = time.perf_counter()
    with session_scope() as s:
        if idempotency_key:
            existing = s.execute(select(Order).where(Order.idempotency_key == idempotency_key)).scalar_one_or_none()
            if existing:
                DB_QUERY_LATENCY.labels("create_order").observe(time.perf_counter() - db_start)
                return _order_json(existing)
        order = Order(
            customer_id=body.customer_id,
            amount_cents=body.amount_cents,
            currency=body.currency,
            idempotency_key=idempotency_key,
        )
        s.add(order)
        try:
            s.commit()
        except IntegrityError:
            s.rollback()
            existing = s.execute(select(Order).where(Order.idempotency_key == idempotency_key)).scalar_one()
            DB_QUERY_LATENCY.labels("create_order").observe(time.perf_counter() - db_start)
            return _order_json(existing)
        payload = {"order_id": order.id, "trace_id": trace_id_var.get()}
        result = _order_json(order)
    DB_QUERY_LATENCY.labels("create_order").observe(time.perf_counter() - db_start)
    get_queue().publish(payload)
    ORDERS_CREATED.inc()
    log(logger, logging.INFO, "order created", order_id=result["id"], amount_cents=body.amount_cents)
    return result


# NOTE: declared before "/orders/{order_id}" so that "stats" is not taken as an order id.
@app.get("/orders/stats")
def order_stats():
    """Counts per status, for the web page and for operators. Aggregates only: no customer data."""
    faults.apply_request_faults_read()
    db_start = time.perf_counter()
    with session_scope() as s:
        rows = s.execute(select(Order.status, func.count()).group_by(Order.status)).all()
        by_status = {status: count for status, count in rows}
        oldest_new = s.execute(select(func.min(Order.created_at)).where(Order.status == "NEW")).scalar_one_or_none()
        latest = s.execute(select(func.max(Order.created_at))).scalar_one_or_none()
    DB_QUERY_LATENCY.labels("order_stats").observe(time.perf_counter() - db_start)
    age = None
    if oldest_new is not None:
        if oldest_new.tzinfo is None:  # SQLite returns naive datetimes
            oldest_new = oldest_new.replace(tzinfo=timezone.utc)
        age = max(0, int((datetime.now(timezone.utc) - oldest_new).total_seconds()))
    return {
        "total": sum(by_status.values()),
        "by_status": by_status,
        "oldest_new_age_seconds": age,
        "latest_created_at": latest.isoformat() if latest else None,
    }


@app.get("/orders/{order_id}")
def get_order(order_id: str):
    faults.apply_request_faults_read()
    with session_scope() as s:
        order = s.get(Order, order_id)
        if not order:
            raise HTTPException(status_code=404, detail="order not found")
        return _order_json(order)


@app.get("/orders")
def list_orders(limit: int = 20, status: str | None = None):
    faults.apply_request_faults_read()
    limit = max(1, min(limit, 100))
    with session_scope() as s:
        q = select(Order).order_by(Order.created_at.desc()).limit(limit)
        if status:
            q = q.where(Order.status == status)
        return {"items": [_order_json(o) for o in s.execute(q).scalars()]}


# ---- internal fault-injection endpoints (token protected; used for failure-mode testing) ----
def _require_token(token: str | None) -> None:
    if not faults.token_ok(token):
        raise HTTPException(status_code=404, detail="Not Found")  # look like any other missing route


@app.get("/_internal/chaos", include_in_schema=False)
def chaos_get(x_fault_token: str | None = Header(default=None)):
    _require_token(x_fault_token)
    return faults.all_flags()


@app.post("/_internal/chaos", include_in_schema=False)
def chaos_set(values: dict[str, float], x_fault_token: str | None = Header(default=None)):
    _require_token(x_fault_token)
    try:
        return faults.set_flags(values)
    except KeyError as exc:
        raise HTTPException(status_code=400, detail=f"unknown fault {exc}") from exc


@app.delete("/_internal/chaos", include_in_schema=False)
def chaos_clear(x_fault_token: str | None = Header(default=None)):
    _require_token(x_fault_token)
    faults.clear_all()
    return {"cleared": True}
