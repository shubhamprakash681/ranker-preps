# Capacity Statement (Task 4 Stretch)

## Current `dev` Platform Envelope
- **AWS Compute:** ECS Fargate API (`0.25 vCPU / 0.5 GB`, 2–4 tasks behind ALB); Worker (`0.25 vCPU / 0.5 GB`, 1–2 tasks).
- **AWS Database:** RDS PostgreSQL 16 `db.t4g.micro` (2 vCPU burstable, 1 GiB RAM, Multi-AZ, `max_connections` ~87).
- **GCP Standby Compute:** Cloud Run API (`1 vCPU / 1 GiB`, 0–3 instances); Worker (`1 vCPU / 512 MiB`, 1–2 instances).
- **GCP Standby Database:** Cloud SQL `db-f1-micro` (shared vCPU, 614 MiB RAM, `max_connections` ~25–50).

## Where the Design Stops Meeting the SLO (and How We Know)
1. **Primary AWS Bottleneck — RDS `db.t4g.micro` CPU Credits & Connections (~40–60 RPS sustained writes):**
   - Each `POST /orders` executes a synchronous Multi-AZ PostgreSQL commit plus SQS `SendMessage`. With SQLAlchemy `pool_size=5, max_overflow=5` (up to 10 connections per container), 4 API tasks + 2 Worker tasks = up to **60 concurrent DB connections**, approaching `db.t4g.micro`'s ~87-connection ceiling, and sustained > 20% baseline CPU drains `t4g` CPU credits until latency exceeds the **500 ms p99 SLO**.
   - **Telemetry proof:** `AWS/RDS CPUUtilization`, `DatabaseConnections`, `ReadLatency`/`WriteLatency`, and application Prometheus metric `db_query_duration_seconds` on `/metrics`.
2. **Secondary Bottleneck — Worker Throughput (~15–25 orders/sec max across 2 tasks):**
   - Each Worker task polls up to 10 messages (`run_once`) sequentially, updates PostgreSQL, and writes to S3 (`PutObject` ~20–40 ms). Beyond ~25 orders/sec sustained, `ApproximateAgeOfOldestMessage` climbs past 120s (`cause-sqs-queue-age` alert fires).
3. **GCP Standby Bottleneck — Cloud SQL `db-f1-micro` (~10–15 RPS sustained):**
   - Shared-core CPU and 614 MiB RAM saturate quickly under sustained write load; keeping Cloud Run API `max_instance_count = 3` prevents exhausting Cloud SQL's connection limit (~25–50) during failover.
