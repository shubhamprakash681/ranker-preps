# Northwind Orders (starter application)

```
docker compose up --build            # API on http://localhost:8080, worker, Postgres
curl -s localhost:8080/readyz
curl -s -X POST localhost:8080/orders -H 'content-type: application/json' \
     -d '{"customer_id":"c-1","amount_cents":1999,"currency":"EUR"}'
curl -s localhost:8080/orders            # wait a few seconds: status becomes PROCESSED
curl -s localhost:8080/metrics | head
curl -s localhost:8080/orders/stats    # counts per status
```

Open http://localhost:8080/ for a small web page: create orders, see recent orders and the counts per status, and which cloud answered (`/version`). It uses only the public API.

Tests: `pip install -r requirements-dev.txt && pytest`.

| Path | Purpose |
|---|---|
| `app/` | the service (API in `main.py`, queue consumer in `worker.py`, backends in `queueing.py` and `storage.py`, the web page in `static/index.html`) |
| `Dockerfile` | one image, two entry points |
| `legacy/` | legacy billing dump (`legacy_dump.sql`) and its nightly job, for the migration task |

Notes
- The API and the worker need the same configuration (database, queue, storage).
- `/healthz` is liveness and never touches dependencies. `/readyz` checks the database.
- Logs are one JSON object per line on stdout, carrying a `trace_id`.
