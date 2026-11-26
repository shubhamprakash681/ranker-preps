# Incident Postmortem Template (Blameless)

- **Incident Title:** `[e.g., Elevated 503 Error Rate / Latency Degradation on Northwind Orders]`
- **Date / Duration:** `[YYYY-MM-DD HH:MM UTC – HH:MM UTC (Total: XX min)]`
- **Severity / Alert Triggered:** `[e.g., nwo-<username>-dev-page-avail-fast-burn / synthetic-probe]`
- **Authors:** `[On-call engineer]`

## 1. Executive Summary
`[2–3 sentences summarizing customer impact, active cloud, root cause, and resolution.]`

## 2. Impact in Error-Budget Terms
- **Affected SLO:** `[Availability 99.9% / Latency 99% <= 500ms]`
- **30-Day Error Budget:** `43.2 minutes` (Availability) / `1.0% requests` (Latency)
- **Error Budget Consumed by Incident:** `[e.g., X.X minutes / X.X% of 30d budget; exact calculation from failed requests / total requests or outage duration]`
- **Remaining Budget:** `[XX.X%]`

## 3. Timeline (All Times UTC)
| Time (UTC) | Event / Telemetry Observed |
|---|---|
| `HH:MM` | Fault / trigger began |
| `HH:MM` | Detected via `[alarm / synthetic probe / dashboard]` (**TTD: X min**) |
| `HH:MM` | Root cause confirmed using `[logs trace_id / /metrics / CloudWatch]` |
| `HH:MM` | Mitigation applied (`[...]`) |
| `HH:MM` | Service verified healthy via probe & `/readyz` (**TTR: X min**) |

## 4. Root Cause
`[Technical explanation tied directly to observed metrics and structured logs (include sample trace_id).]`

## 5. What Went Well / What Surprised Us
- **Went well:** `[...]`
- **Surprised us:** `[...]`

## 6. Action Items (Preventive & Detective)
| Action | Owner | Target Date |
|---|---|---|
| `[Concrete code, alert, runbook, or capacity fix]` | `[Owner]` | `[Date]` |
