# Runbook: Cross-Cloud DR Failover (AWS → GCP)

## Targets
- **RPO:** ≤ 15 minutes (EventBridge Scheduler runs `app.dr_backup` every **10 minutes**, writing immutable snapshots to S3 Object Lock and GCS Retention Policy via `nwo-aws` WIF).
- **RTO:** ≤ 30 minutes (automated **data-first, then traffic** failover via `.github/workflows/failover.yml`).

---

## 1. Pre-Failover Checks (Detect & Decide)
1. Confirm AWS `us-east-1` outage via synthetic probe (`python3 .github/scripts/probe.py https://<cloudfront_domain_name>`) or AWS Health / CloudWatch alarms (`page-endpoint-down`, `page-avail-fast-burn`).
2. Confirm newest backup timestamp in GCS (`gs://nwo-<username>-dev-backups-<gcp_project_id>/backups/`) is within RPO (`<= 15m`).

---

## 2. Execute Failover (`Data First, Then Traffic`)
Trigger the automated failover workflow:
```bash
gh workflow run failover.yml
```
*(Or GitHub UI: **Actions → DR Failover (AWS -> GCP) → Run workflow**.)*

What it executes in order:
1. **Stale Standby Guard:** Reads the newest backup timestamp and verifies `RPO <= 900s` (aborts unless `force_stale=true` is explicitly selected).
2. **Data Restore & Promote:** Executes Cloud Run job `nwo-<username>-dev-restore` with `PROMOTE_ON_RESTORE=true`, loading the latest backup into Cloud SQL and marking `dr_state.promoted = 'true'`.
3. **Traffic Switch:** Calls `.github/scripts/traffic_switch.sh` to set CloudFront KeyValueStore `aws_weight = 0` (`100%` GCP).
4. **Verification & Metrics:** Verifies `/version` returns `"cloud":"gcp"` and `/readyz` returns `ready`, then prints measured **RPO** and **RTO**.

---

## 3. Stretch: Standby Promotion Safety & Overwrite Protection
1. **What stops a stale standby from being promoted by mistake:**
   - Failover is deliberate (no automatic CloudFront failover on 5xx) AND `failover.yml` checks `RPO_SECONDS <= 900` before restoring/promoting; if the newest backup is older than 15 minutes, the workflow aborts unless an operator explicitly sets `force_stale=true`.
2. **What stops a scheduled restore from overwriting live data after promotion:**
   - `failover.yml` sets `PROMOTE_ON_RESTORE=true`, which persists `dr_state(key='promoted', value='true')` inside Cloud SQL.
   - Cloud Scheduler's periodic `*/15` runs execute with `PROMOTE_ON_RESTORE=false` and `ALLOW_RESTORE_OVERWRITE=false`; `app/dr_restore.py` checks `is_promoted()` first and immediately skips without touching `orders` when `promoted == 'true'`.

---

## 4. Stretch: Failback Plan (GCP → AWS Without Losing Writes)
Once AWS `us-east-1` recovers:
1. **Freeze new writes on GCP briefly OR run incremental delta sync:**
   - Trigger a manual backup from Cloud SQL (using `pg_dump` / `app.dr_backup` pointing to Cloud SQL) to capture all orders created on GCP while AWS was down.
   - Restore that snapshot into recovered AWS RDS (or upsert rows created after `failover_start_time` into AWS RDS so zero GCP-accepted orders are lost).
2. **Verify AWS readiness:** Check `aws ecs describe-services`, RDS Multi-AZ health, and `/readyz`.
3. **Canary traffic back to AWS:**
   - Shift `10%` → `50%` → `100%` back to AWS (`gh workflow run traffic-switch.yml -f aws_percentage=10`, then `50`, then `100`).
4. **Reset standby state:** Once AWS is at `100%` and backups are flowing again, clear `dr_state.promoted` on Cloud SQL (`DELETE FROM dr_state WHERE key='promoted'`) and re-enable AWS → GCP backup sync.

---

## 5. Stretch: Monthly DR Cost vs Cost of 1 Hour of Downtime
- **Incremental DR & Warm Standby Monthly Cost (`dev`):**
  - Cloud SQL `db-f1-micro` zonal + 10 GB SSD + PITR: ~\$11/month
  - Cloud Run API (`min = 0`) + Worker (`min = 1`, `cpu_idle = false`) + Restore Job: ~\$18–22/month
  - GCS Backup & Receipts buckets + S3 Backup bucket (< 1 GB) + EventBridge/Cloud Scheduler + AWS Backup Fargate (`256/512` running ~30s every 10m = ~2.2 hrs/month): ~\$1–2/month
  - **Total DR/Standby Cost:** **~\$30–35/month** (~$\$1.10$/day).
- **Assumed Cost of 1 Hour of Downtime:**
  - Assumption: Northwind processes ~500 orders/hour at an average order value of \$40 (\$20,000/hour gross revenue) + ~\$1,500/hour SLA/support & engineering incident cost ≈ **\$21,500 per hour of downtime** (even for a small storefront at 50 orders/hour, 1 hour = ~\$2,000).
- **ROI:** Keeping warm standby + 10-minute immutable backups running costs ~\$35/month — less than **0.2%–2%** of a single hour of downtime.
