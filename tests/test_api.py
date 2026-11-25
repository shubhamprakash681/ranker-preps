import os
import tempfile

import pytest

_tmp = tempfile.mkdtemp()
os.environ["DATABASE_URL"] = f"sqlite:///{_tmp}/test.db"
os.environ["STORAGE_TARGET"] = f"{_tmp}/receipts"
os.environ["QUEUE_BACKEND"] = "db"
os.environ["STORAGE_BACKEND"] = "local"

from fastapi.testclient import TestClient  # noqa: E402

from app import faults, worker  # noqa: E402
from app.main import app  # noqa: E402

# The real token is not in this repo; tests patch the check instead.


@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c


def test_health_and_ready(client):
    assert client.get("/healthz").json() == {"status": "ok"}
    r = client.get("/readyz")
    assert r.status_code == 200 and r.json()["db"] == "up"


def test_create_get_and_process_order(client):
    r = client.post("/orders", json={"customer_id": "c-1", "amount_cents": 1999, "currency": "usd"})
    assert r.status_code == 201
    order = r.json()
    assert order["status"] == "NEW" and order["currency"] == "USD"

    assert worker.run_once(wait_s=0) == 1
    got = client.get(f"/orders/{order['id']}").json()
    assert got["status"] == "PROCESSED" and got["processed_at"]
    assert os.path.exists(os.path.join(os.environ["STORAGE_TARGET"], "receipts", f"{order['id']}.json"))


def test_idempotency_key(client):
    body = {"customer_id": "c-2", "amount_cents": 500, "currency": "EUR"}
    a = client.post("/orders", json=body, headers={"Idempotency-Key": "k-1"}).json()
    b = client.post("/orders", json=body, headers={"Idempotency-Key": "k-1"}).json()
    assert a["id"] == b["id"]


def test_validation(client):
    assert client.post("/orders", json={"customer_id": "c", "amount_cents": 0, "currency": "USD"}).status_code == 422
    assert client.post("/orders", json={"customer_id": "c", "amount_cents": 5, "currency": "US"}).status_code == 422


def test_not_found(client):
    assert client.get("/orders/does-not-exist").status_code == 404


def test_metrics_exposed(client):
    client.get("/orders")
    text = client.get("/metrics").text
    assert "http_requests_total" in text and "http_request_duration_seconds_bucket" in text


def test_web_page_is_served(client):
    r = client.get("/")
    assert r.status_code == 200 and r.headers["content-type"].startswith("text/html")
    assert "Northwind" in r.text and "/orders/stats" in r.text  # the page uses only the public API
    assert r.headers["cache-control"] == "no-store"


def test_stats_counts_orders_by_status(client):
    before = client.get("/orders/stats").json()
    assert set(before) == {"total", "by_status", "oldest_new_age_seconds", "latest_created_at"}
    client.post("/orders", json={"customer_id": "c-stats", "amount_cents": 700, "currency": "GBP"})
    mid = client.get("/orders/stats").json()
    assert mid["total"] == before["total"] + 1
    assert mid["by_status"].get("NEW", 0) == before["by_status"].get("NEW", 0) + 1
    assert mid["oldest_new_age_seconds"] is not None and mid["oldest_new_age_seconds"] >= 0
    worker.run_once(wait_s=0)
    after = client.get("/orders/stats").json()
    assert after["total"] == mid["total"]
    assert after["by_status"].get("PROCESSED", 0) >= mid["by_status"].get("PROCESSED", 0) + 1


def test_stats_is_not_mistaken_for_an_order_id(client):
    assert client.get("/orders/stats").status_code == 200  # not a 404 from /orders/{order_id}
    assert client.get("/orders/stats-but-not-really").status_code == 404


def test_stats_exposes_no_customer_data(client):
    text = client.get("/orders/stats").text
    assert "c-stats" not in text and "customer" not in text


def test_chaos_endpoint_hidden_without_token(client):
    assert client.get("/_internal/chaos").status_code == 404
    assert client.get("/_internal/chaos", headers={"X-Fault-Token": "wrong"}).status_code == 404


def test_error_rate_fault_and_poison(client, monkeypatch):
    monkeypatch.setattr(faults, "token_ok", lambda t: t == "ok")
    h = {"X-Fault-Token": "ok"}
    assert client.post("/_internal/chaos", json={"error_rate": 1.0}, headers=h).status_code == 200
    r = client.post("/orders", json={"customer_id": "c-3", "amount_cents": 100, "currency": "USD"})
    assert r.status_code == 503
    assert client.get("/orders").status_code == 200  # reads are not failed by error_rate
    client.delete("/_internal/chaos", headers=h)

    # poison messages: worker fails the message and eventually dead-letters it
    while worker.run_once(wait_s=0):  # drain messages left by earlier tests
        pass
    created =client.post("/orders", json={"customer_id": "c-4", "amount_cents": 100, "currency": "USD"})
    assert created.status_code == 201
    client.post("/_internal/chaos", json={"poison_messages": 1}, headers=h)
    from app.db import QueueMessage, session_scope
    import datetime as dt
    for _ in range(5):
        worker.run_once(wait_s=0)
        with session_scope() as s:  # make the in-flight message visible again immediately
            for m in s.query(QueueMessage).filter(QueueMessage.status == "inflight"):
                m.visible_at = dt.datetime.now(dt.timezone.utc) - dt.timedelta(seconds=1)
            s.commit()
    with session_scope() as s:
        assert s.query(QueueMessage).filter(QueueMessage.status == "dead").count() == 1
    client.delete("/_internal/chaos", headers=h)
