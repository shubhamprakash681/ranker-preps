# Service Level Objectives (SLOs) & Error-Budget Policy

## 1. Service Level Indicators (SLIs) & Objectives (SLOs)

| Dimension | SLI Definition | 30-Day SLO Target | Error Budget (30d) | Justification |
|---|---|---|---|---|
| **Availability** | Ratio of non-5xx HTTP responses (`status < 500`) to total valid HTTP requests served across `/orders`, `/orders/{id}`, `/orders/stats`, `/readyz`, `/version`, and `/` | **99.9%** | **0.1%** (~43.2 min downtime equivalent) | Order intake is customer-facing and backed by idempotent `Idempotency-Key` retries; `99.9%` is realistic over Multi-AZ RDS + 2 ECS tasks without paying for active-active synchronous multi-cloud database replication. |
| **Latency** | Proportion of valid HTTP requests completing in **≤ 500 ms** (measured at ALB `TargetResponseTime` p99 on AWS and Cloud Run `request_latencies` on GCP) | **99.0%** | **1.0%** slow requests | A normal `POST /orders` performs 1 PostgreSQL insert + 1 SQS/PubSub publish (~15–45 ms). A 500 ms threshold tolerates occasional cold-path/Multi-AZ commit jitter while alerting fast if `db_latency_ms` or `cpu_burn_ms` faults occur. |

---

## 2. Error-Budget Policy (Consequences When Burning or Spent)

| Remaining 30-Day Budget | State | Required Action |
|---|---|---|
| **> 50%** | Healthy | Normal feature & infrastructure deployments proceed via standard CI/CD gates. |
| **20% – 50%** | Burning (Slow burn triggered) | Prioritize reliability/latency fixes; require explicit review of any schema or runtime change before merge. |
| **< 20% or 0% (Exhausted)** | Budget Spent / Freeze | **Deployment freeze** on non-critical changes to `app/` and infrastructure until root cause is mitigated and reliability work restores headroom; only incident mitigations, rollbacks, or DR failovers may deploy. |
| **Single incident consumes > 20% budget** | Major Incident | Mandatory **blameless postmortem** within 60 minutes of mitigation with concrete action items tracked before lifting the freeze. |

---

## 3. Alerting Philosophy: Page for Symptoms, Ticket for Causes

- **Page (Immediate Action, Multi-Window Burn Rate):**
  - **Availability Fast Burn (`14.4x`, 5m AND 1h windows):** Consumes 2% of the 30-day error budget in 1 hour (`> 1.44%` 5xx rate). Dual-window confirmation prevents transient 1-minute blips from paging while catching sustained outages fast.
  - **Latency Fast Burn (`p99 > 500 ms` across 5m AND 1h windows on AWS; `14.4x` burn across 5m AND 1h on GCP):** Pages only when latency degrades user-visible p99 sustainably across both short and long windows.
  - **Synthetic Endpoint Down (`public-uptime`):** Pages if `/version` or `/readyz` through the public CloudFront hostname fails for > 2 minutes.
- **Ticket Only (Proactive Cause Investigation, No Page):**
  - **SQS / Pub/Sub Queue Age > 120s** (early warning of worker slowdown before customers notice missing receipts).
  - **SQS / Pub/Sub DLQ Depth > 0** (poison message parked after 5 failed attempts; requires triage without waking on-call if API intake is still up).
  - **ECS / Cloud Run Memory > 85%** (catches gradual memory leaks before OOM crashes cause 5xxs).
  - **RDS / Cloud SQL CPU > 80%** (catches query/CPU saturation early before p99 latency breaches 500 ms).
