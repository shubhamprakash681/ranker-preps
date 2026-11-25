"""Prometheus metrics exposed on /metrics."""
from prometheus_client import Counter, Gauge, Histogram

HTTP_REQUESTS = Counter(
    "http_requests_total", "HTTP requests", ["method", "route", "status"]
)
HTTP_LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency",
    ["method", "route"],
    buckets=(0.025, 0.05, 0.1, 0.2, 0.3, 0.5, 1, 2, 5, 10),
)
ORDERS_CREATED = Counter("orders_created_total", "Orders accepted")
ORDERS_PROCESSED = Counter("orders_processed_total", "Orders processed by the worker", ["outcome"])
QUEUE_DEPTH = Gauge("queue_depth", "Messages waiting (-1 when unknown)")
