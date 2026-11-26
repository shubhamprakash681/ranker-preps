# Runbook: Latency Fast Burn (`page-latency-fast-burn`)

## Trigger
- **AWS:** `nwo-<username>-dev-page-latency-fast-burn` (ALB `TargetResponseTime` p99 > `500 ms` across 5m AND 1h windows).
- **GCP:** `nwo-<username>-dev-page-latency-fast-burn` (`select_slo_burn_rate` on latency SLO > `14.4x` across 5m AND 1h windows).

## First Action (Do This Within 2 Minutes)
1. **Measure live `/orders` vs `/healthz` vs `/metrics` latency** to isolate DB/CPU slowdown from network/edge latency:
   ```bash
   curl -w "time_total=%{time_total}s\n" -s -o /dev/null https://<cloudfront_domain_name>/healthz
   curl -w "time_total=%{time_total}s\n" -s -o /dev/null https://<cloudfront_domain_name>/orders
   curl -s https://<cloudfront_domain_name>/metrics | grep db_query_duration_seconds
   ```

## Triage & Diagnosis
1. **Check CloudWatch / Cloud Monitoring Dashboard (`nwo-<username>-dev-dashboard`):**
   - **High `db_query_duration_seconds` + normal RDS CPU:** Artificial/lock/DB-layer latency (`db_latency_ms`) or connection pool contention.
   - **High ECS/Cloud Run CPU (`> 80%`) with normal `db_query_duration_seconds`:** CPU-bound loop (`cpu_burn_ms`) or traffic spike — check `ECSServiceAverageCPUUtilization` and task count.
   - **Rising ECS/Cloud Run Memory (`> 85%`, `cause-ecs-api-memory`):** Memory leak (`memory_leak_kb`) causing GC pauses and OOM restarts.
2. **Check structured API logs** (`duration_ms` field on `"request"` entries) to see whether reads (`/orders`) and writes (`/orders` POST) are both slow.

## Mitigation
- Scale out ECS desired count / Cloud Run max instances if CPU saturation is traffic-driven.
- If a container is leaking memory (`OOMKilled` / >85% memory), recycle tasks via rolling restart while diagnosing the leak source.
- Complete the blameless postmortem within **60 minutes** of resolution.
