# Runbook: Availability Fast Burn (`page-avail-fast-burn`)

## Trigger
- **AWS:** `nwo-<username>-dev-page-avail-fast-burn` (5m AND 1h 5XX error rate > `1.44%`, 14.4x burn on 99.9% SLO).
- **GCP:** `nwo-<username>-dev-page-avail-fast-burn` (`select_slo_burn_rate` 5m AND 1h > `14.4x`).

## First Action (Do This Within 2 Minutes)
1. **Verify active cloud & readiness** through the public endpoint:
   ```bash
   curl -i https://<cloudfront_domain_name>/version
   curl -i https://<cloudfront_domain_name>/readyz
   ```

## Triage & Diagnosis
1. **Check structured logs by `trace_id`:**
   - AWS CloudWatch Log Groups `nwo-<username>-dev-api` / `nwo-<username>-dev-worker`: filter `{ $.severity = "ERROR" }` or run Logs Insights for `trace_id` from a failing `POST /orders` `x-trace-id` header.
   - GCP Cloud Logging: filter `severity>=ERROR jsonPayload.service=("orders-api" OR "orders-worker")`.
2. **Distinguish fault modes:**
   - **`POST /orders` returns `503` while `GET /orders` & `/readyz` return `200`:** Application-level fault or injected `error_rate` flag (`"injected failure"` in error body/logs) or bad deployment.
   - **`/readyz` returns `503` (`"db": "down"`):** Database connectivity or RDS/Cloud SQL outage.
   - **Worker errors / DLQ rising (`cause-sqs-dlq-depth` or `cause-pubsub-dlq-depth`):** Poison messages or storage write failure.

## Mitigation
- If caused by a recent deployment, roll back in ECS / Cloud Run (`aws ecs update-service --force-new-deployment` or revert commit on `main`).
- If caused by an AWS regional/DB outage that cannot recover within RTO (30 min), initiate cross-cloud DR failover ([Task 5 failover runbook](README.md)).
- Once mitigated, open [postmortem-template.md](../postmortem-template.md) and complete the blameless postmortem within **60 minutes**.
