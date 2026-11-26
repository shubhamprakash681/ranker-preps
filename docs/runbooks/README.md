# On-Call Runbooks

Every **paging** alert links directly to one of the runbooks below:

| Paging Alert | Runbook | First Action |
|---|---|---|
| `nwo-<username>-dev-slo-avail-burn-1h` (AWS) / `page-avail-fast-burn` (GCP) | [availability-burn-rate.md](availability-burn-rate.md) | Check `/readyz`, ALB/Cloud Run 5XX breakdown, and API logs filtered by `severity="ERROR"` and `trace_id` |
| `nwo-<username>-dev-slo-latency-burn-1h` (AWS) / `page-latency-fast-burn` (GCP) | [latency-burn-rate.md](latency-burn-rate.md) | Check `/metrics` (`db_query_duration_seconds`) and RDS/ECS/Cloud Run CPU & memory |
| `nwo-<username>-dev-page-endpoint-down` | [endpoint-down.md](endpoint-down.md) | Run `python3 .github/scripts/probe.py https://<cloudfront_domain_name>` to identify failing origin |

## Following a `trace_id` End-to-End (API → Worker)
- Every HTTP response returns header `x-trace-id`.
- **AWS CloudWatch Logs Insights** (across `nwo-<username>-dev-api` and `nwo-<username>-dev-worker`):
  ```sql
  fields @timestamp, service, message, order_id, status, duration_ms, error, trace_id
  | filter trace_id = "<TRACE_ID>"
  | sort @timestamp asc
  ```
- **GCP Cloud Logging:**
  ```text
  jsonPayload.trace_id="<TRACE_ID>"
  ```
