"""Queue consumer: marks orders PROCESSED and writes a receipt object.

Run as a separate process/service from the same image:  python -m app.worker
"""
import json
import logging
import os
import signal
import sys
import time

from . import faults
from .config import get_settings
from .db import Order, init_db, session_scope, utcnow
from .logging_conf import configure_logging, log, trace_id_var
from .metrics import ORDERS_PROCESSED
from .queueing import Message, get_queue
from .storage import get_storage

logger = logging.getLogger("orders-worker")
_running = True


def _stop(*_):
    global _running
    _running = False


def process(msg: Message) -> None:
    if faults.get("poison_messages") >= 1:
        raise RuntimeError("injected poison message failure")
    order_id = msg.payload["order_id"]
    with session_scope() as s:
        order = s.get(Order, order_id)
        if order is None:
            raise LookupError(f"order {order_id} not found")
        if order.status == "PROCESSED":  # idempotent redelivery
            return
        order.status = "PROCESSED"
        order.processed_at = utcnow()
        receipt = {
            "order_id": order.id,
            "customer_id": order.customer_id,
            "amount_cents": order.amount_cents,
            "currency": order.currency,
            "processed_at": order.processed_at.isoformat(),
        }
        s.commit()
    get_storage().put(f"receipts/{order_id}.json", json.dumps(receipt).encode())


def run_once(queue=None, wait_s: int = 5) -> int:
    queue = queue or get_queue()
    max_attempts = get_settings().max_attempts
    handled = 0
    for msg in queue.receive(max_messages=10, wait_s=wait_s):
        trace_id_var.set(msg.payload.get("trace_id") or msg.id)
        try:
            process(msg)
            queue.ack(msg)
            ORDERS_PROCESSED.labels("ok").inc()
            log(logger, logging.INFO, "order processed", order_id=msg.payload.get("order_id"), message_id=msg.id)
            handled += 1
        except Exception as exc:  # noqa: BLE001
            ORDERS_PROCESSED.labels("error").inc()
            log(logger, logging.ERROR, "message failed", message_id=msg.id, attempts=msg.attempts, error=str(exc))
            if msg.attempts >= max_attempts:
                queue.dead_letter(msg)
                log(logger, logging.ERROR, "message dead-lettered", message_id=msg.id)
    return handled


def _serve_health(port: int) -> None:
    """Cloud Run services must listen on $PORT. When PORT is set the worker answers 200 on it."""
    import threading
    from http.server import BaseHTTPRequestHandler, HTTPServer

    class H(BaseHTTPRequestHandler):
        def do_GET(self):  # noqa: N802
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"ok")

        def log_message(self, *_):
            pass

    threading.Thread(target=HTTPServer(("0.0.0.0", port), H).serve_forever, daemon=True).start()


def main() -> None:
    configure_logging()
    init_db()
    if os.getenv("PORT"):
        _serve_health(int(os.environ["PORT"]))
    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)
    log(logger, logging.INFO, "worker started", queue=get_settings().queue_backend)
    while _running:
        try:
            if run_once() == 0:
                time.sleep(1)
        except Exception as exc:  # noqa: BLE001 - keep the loop alive through transient outages
            log(logger, logging.ERROR, "worker loop error", error=str(exc))
            time.sleep(5)
    log(logger, logging.INFO, "worker stopped")
    sys.exit(0)


if __name__ == "__main__":
    main()
