# Legacy Billing Database & Settlement Job Migration Plan (Task 6)

## 1. Migration Strategy (6Rs) & Target Cloud Decisions

### Component 1: On-Premises PostgreSQL 11 Billing Database
- **Target Cloud:** **AWS (`us-east-1`)** — RDS PostgreSQL 16 (Multi-AZ, KMS-encrypted, private data subnets).
- **6Rs Strategy:** **Replatform**
- **Justification (~10 lines):**
  We choose **Replatform** onto our primary AWS RDS PostgreSQL 16 instance rather than *Rehost* (an EC2 PostgreSQL 11 VM is disallowed by CI IAM guardrails and leaves EOL PG 11 unpatched) or *Refactor* (rewriting billing into DynamoDB/NoSQL would break relational `customers`/`invoices` joins, transactions, and numeric currency precision). Keeping the relational schema intact while upgrading PostgreSQL 11 → 16 on managed Multi-AZ RDS eliminates OS/database patching, gains CMK encryption at rest, enforces `rds.force_ssl = 1` in transit, and automatically inherits our Task 5 10-minute immutable cross-cloud DR backups to GCP. Co-locating billing on AWS (`us-east-1`) rather than GCP keeps all authoritative transactional data in the primary cloud with zero cross-cloud latency for the settlement query. During the repeatable load we apply targeted schema hygiene (normalizing dirty statuses, converting naive wall-clock timestamps to `TIMESTAMPTZ`, and preserving sequence high-water marks) without altering application semantics.

### Component 2: Legacy Nightly Settlement Cron (`legacy/nightly_settlement.py`)
- **Target Cloud:** **AWS (`us-east-1`)** — ECS Fargate scheduled task (`app.settlement`) via EventBridge Scheduler + S3.
- **6Rs Strategy:** **Refactor (targeted) / Replatform**
- **Justification (~10 lines):**
  We choose a targeted **Refactor/Replatform** into a stateless container task (`python -m app.settlement`) scheduled by EventBridge Scheduler (`cron(30 1 * * ? *)`, `America/New_York`) rather than *Rehost* (running cron on a VM retains single-host paths `/var/settlements`, plaintext DSN password `billing123`, and unreachable on-prem webhook `10.20.30.40:9000`) or *Retire/Repurchase* (SaaS billing replacement exceeds scope and breaks existing CSV consumers). Injecting `DB_PASSWORD` from Secrets Manager, querying UTC-bounded `America/New_York` windows on normalized `UPPER(TRIM(status)) = 'PAID'`, handling `NULL` emails safely, and writing `settlements/settlement_YYYYMMDD.csv` to KMS-encrypted versioned S3 removes all host assumptions. It reuses our existing `northwind-orders` image, task IAM role, and CloudWatch log group (`nwo-<username>-dev-settlement`) at near-zero incremental cost (~$\$0.05$/month).

---

## 2. Data-Quality Findings & Explicit Decisions (`legacy/legacy_dump.sql`)

Inspecting all 500 `customers` and 8,000 `invoices` rows in `legacy/legacy_dump.sql` uncovered **5 schema/data anomalies** (plus host assumptions in `legacy/nightly_settlement.py`):

| # | Anomaly Found in Source | Exact Count / Example | Impact of Naive Load / Run | Explicit Decision & Handling |
|---|---|---|---|---|
| 1 | **NULL `email` values (`\N`)** | **9 customers** (e.g., IDs `53, 106, 159, 212, 265, 318, 371, 424, 477`) | `NOT NULL` constraint would fail load; `settlement` could emit `None` or crash | Keep `customers.email` nullable (`TEXT NULL`) so all 500 customers and their invoices load cleanly; `app.settlement` uses `COALESCE(c.email, '')`. |
| 2 | **Case-insensitive duplicate emails** | **12 duplicate pairs** (e.g., ID `41` `USER21@Example.com` vs ID `21` `user21@example.com`) | Adding `UNIQUE(LOWER(email))` would fail the load; merging IDs silently would corrupt `invoices.customer_id` audit trail | Preserve all 500 customer PKs unchanged, add non-unique indexed column `email_normalized = LOWER(TRIM(email))`, and flag the 12 pairs for post-cutover business reconciliation. |
| 3 | **Dirty invoice `status` (`'paid '`)** | **37 invoices** have lowercase + trailing space `'paid '` (`3,942` `'PAID'` + `37` `'paid '` = **`3,979`** paid total) | `legacy/nightly_settlement.py` (`WHERE i.status = 'PAID'`) **silently omitted 37 paid invoices** from settlement CSVs! | Normalize `status` on load (`UPPER(TRIM(status))`), enforce `CHECK (status IN ('PAID','FAILED','REFUNDED','PENDING'))`, and normalize inside `app.settlement` query too. |
| 4 | **Naive `America/New_York` timestamps + 1 non-existent DST gap timestamp** | All `created_at` / `issued_at` are `timestamp without time zone`; invoice `id` at line 4700 has **`2024-03-10 02:38:50`** (US spring-forward gap `02:00–02:59` never existed!) | Naive UTC conversion or strict `ZoneInfo` parsing fails/shifts inconsistently; local `dt.date.today()` in settlement misses NY midnight boundaries | Convert to `TIMESTAMPTZ` (UTC) deterministically with `America/New_York` (`fold=0` → `2024-03-10 07:38:50+00`), and compute settlement day windows in `America/New_York` converted to UTC (`23h` on spring-forward, `25h` on fall-back). |
| 5 | **Sequence high-water marks > `MAX(id)` & missing `DEFAULT`** | `customers_id_seq = 637` (`MAX(id)=500`); `invoices_id_seq = 12200` (`MAX(id)=8000`); no `DEFAULT nextval(...)` on `id` | Resetting sequence to `MAX(id)` risks colliding with historical/archived IDs; missing `DEFAULT` breaks future `INSERT` without explicit `id` | Attach `DEFAULT nextval(...)` on both PKs and explicitly execute `setval(..., 637)` and `setval(..., 12200)` after load. |
| 6 | **Hardcoded host paths & secrets in `nightly_settlement.py`** | Plaintext `billing123`, local `/var/settlements`, unreachable `10.20.30.40:9000` | Fails completely on ECS Fargate / Cloud Run and violates Rule 6 (no secrets in code) | Replaced with `app/settlement.py` reading Secrets Manager `DB_PASSWORD`, writing CSVs to KMS-encrypted S3, and running on EventBridge Scheduler. |

---

## 3. Repeatable Load & Validation Scripts
- **Repeatable Loader:** [`scripts/migration/load_legacy.py`](../scripts/migration/load_legacy.py) — idempotent DDL + transactional `TRUNCATE ... RESTART IDENTITY CASCADE` + normalized load + sequence restore. Can be re-run safely any number of times during rehearsal.
- **Validation Script:** [`scripts/migration/validate_legacy.py`](../scripts/migration/validate_legacy.py) — compares `legacy/legacy_dump.sql` directly against target PostgreSQL:
  - Exact row counts (`customers = 500`, `invoices = 8000`) and status/currency breakdown (`PAID = 3979`, `FAILED = 1368`, `REFUNDED = 1333`, `PENDING = 1320`).
  - Canonical **SHA-256 content checksums** for all 500 customers and 8,000 invoices.
  - Sequence verification (`637` and `12200`), foreign-key orphan check (`0` orphans), and dirty-status/NULL-email verification.

---

## 4. Cutover & Rollback Plan

### Cutover Timeline (Total Maintenance Window: 30 Minutes)
| Time | Step | Owner / Command |
|---|---|---|
| **T-24h** | Rehearsal dry-run on non-prod / staging DB (`load_legacy.py` + `validate_legacy.py` + `app.settlement`) | Platform Eng |
| **T-15m** | Disable on-prem nightly settlement cron & place legacy billing app in read-only mode | Platform Eng |
| **T-10m** | Take final consistent `pg_dump` from on-prem PG 11 and transfer to encrypted S3 staging | Platform Eng |
| **T-08m** | Run repeatable loader (`python3 scripts/migration/load_legacy.py --dump ...`) into target RDS PG 16 | Platform Eng |
| **T-04m** | Run validation (`python3 scripts/migration/validate_legacy.py --dump ...`) and dry-run `python -m app.settlement <yesterday>` | Platform Eng |
| **T-00 (GO / NO-GO)** | **Go/No-Go Checkpoint:** Proceed ONLY if row counts (`500` / `8000`), SHA-256 checksums, sequences (`637` / `12200`), `0` orphans, and settlement S3 CSV all pass. If ANY check fails → **NO-GO**: keep on-prem DB/cron active, abort cutover, investigate offline. | On-call Lead |
| **T+00m** | Enable EventBridge schedule `nwo-<username>-dev-settlement-nightly` (`01:30 America/New_York`) and switch traffic canary (`10% → 50% → 100%`) | Platform Eng |
| **T+30m** | Verify live settlement CSV in S3, monitor RDS/ECS dashboards and CloudWatch alarms; decommission legacy cron | On-call Lead |

### Rollback & Point of No Return
- **Before Point of No Return (T-15m to T+00m):** Keep on-prem PG 11 untouched and read-only. If validation fails or Go/No-Go is NO-GO, re-enable writes on on-prem PG 11 and re-enable on-prem cron (`0` data loss, `< 5 min` rollback).
- **Canary Rollback (during `10%` / `50%` shift before exclusive writes):** Revert CloudFront KeyValueStore immediately via `gh workflow run traffic-switch.yml -f aws_percentage=100` (or `0` / previous split).
- **Point of No Return:** Once post-cutover live billing writes (new `customers` / `invoices` inserts or mutations using sequences `> 637` / `> 12200`) are accepted exclusively on target RDS PG 16 and the first cloud settlement job runs/distributes CSVs, rolling back to the legacy PG 11 host would discard new production invoices unless a reverse delta extract is executed first.

---

## 5. Stretch: Canary Traffic Shift (`10% → 50% → 100%`) Using Existing Controls
Using the CloudFront Function + KeyValueStore control built in Task 3 (zero Terraform apply, `< 5s` propagation across all HTTP methods):
1. **10% Canary:** `gh workflow run traffic-switch.yml -f aws_percentage=90` (or `.github/scripts/traffic_switch.sh "$KVS_ARN" 90` — routes 10% of requests to the canary origin, 90% to baseline) → monitor `/version`, CloudWatch/Cloud Monitoring error-rate & p99 latency dashboards for 10 minutes.
2. **50% Canary:** `gh workflow run traffic-switch.yml -f aws_percentage=50` → verify equal split across origins, DB connection counts, and `db_query_duration_seconds` SLO headroom for 10 minutes.
3. **100% Cutover:** `gh workflow run traffic-switch.yml -f aws_percentage=0` (or `100` when shifting back to primary AWS) → confirm `100%` responses from target cloud and healthy `/readyz`.
