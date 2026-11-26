# Northwind Orders — Multi-Cloud Platform Submission

> **Note:** This document is updated incrementally as each task (T2 → T1 → T3 → T4 → T5 → T6) is built and verified. Replace `[PLACEHOLDER: ...]` blocks with actual outputs, URLs, and screenshots from your execution environment.

---

## 1. Public Endpoint & Traffic Switch Summary
- **Public Hostname:** `[PLACEHOLDER: https://<cloudfront_domain_name> (copy from deploy-edge output)]`
- **`curl https://<hostname>/version` output:**
  ```json
  [PLACEHOLDER: paste output from curl https://<cloudfront_domain_name>/version]
  ```
- **Traffic Switch Command / Workflow:**
  - **Web UI (Recommended):** GitHub Repo → **Actions → Cross-Cloud Traffic Switch → Run workflow** → set `aws_percentage` (`0` to `100`, takes effect in `< 60s` with no Terraform/redeploy).
  - **CLI equivalent:**
    ```bash
    gh workflow run traffic-switch.yml -f aws_percentage=0
    ```
    ```bash
    ./.github/scripts/traffic_switch.sh "<kvs_arn>" 0
    ```

---

## 2. Architecture Sketch

```text
                        Clients (HTTPS)
                               |
                               v
         +-------------------------------------------+
         |  AWS CloudFront (Single Public Hostname)  |  <- Task 3
         |  CloudFront Function + KeyValueStore      |
         |  Traffic Split: 100/0 <-> 0/100 (< 60s)   |
         +---------------------+---------------------+
                               |
          +--------------------+--------------------+
          | 100% normal                             | 0% normal / 100% failover
          v                                         v
+-------------------+                     +-------------------+
| AWS (us-east-1)   |                     | GCP (us-east4)    |
| Shared VPC        |                     | Shared VPC        |
|                   |                     |                   |
| Public Subnets:   |                     | Cloud Run API     |
|  ALB (/readyz)    |                     | (Direct VPC Egress|
|                   |                     |  no allUsers)     |
| Private Subnets:  |                     |                   |
|  ECS Fargate API  |                     | Cloud Run Worker  |
|  ECS Fargate Wrkr |                     | (internal only)   |
|  SQS + DLQ        |                     | Pub/Sub + DLQ     |
|  S3 Receipts (KMS)|                     | GCS Receipts      |
|  Secrets + KMS    |                     | Secret Manager    |
|                   |                     |                   |
| Data Subnets:     |                     | Private PSA:      |
|  RDS PG16 MultiAZ |                     |  Cloud SQL PG16   |
|                   |                     |  (zonal, PITR)    |
| Backup Fargate -> | === WIF nwo-aws ==> | GCS Backup Bucket |
| S3 Object Lock    |     (immutable)     | + Cloud Run       |
|                   |                     |   Restore Job     |
+-------------------+                     +-------------------+
```

---

## 3. Build Order & Task Progress

| Order | Task | Status | Notes |
|---|---|---|---|
| 1 | **T2: IaC & CI/CD Foundation** | Code written / `[Pending run]` | PR checks, OIDC/WIF, S3 native lock & GCS backends, `dev` deploy on merge, tag/OPA checks, drift workflow |
| 2 | **T1: AWS Platform** | Deployed & verified | Multi-AZ RDS PG16, ECS Fargate API & Worker in private subnets, ALB (`/readyz`), SQS+DLQ, S3 receipts, CMK KMS, least-privilege IAM |
| 3 | **T3: GCP Platform & Edge** | Code written / `[Pending verify]` | Cloud Run API & Worker (Direct VPC), Cloud SQL PG16 (private IP, PITR), Pub/Sub+DLQ, GCS, Secret Manager, CloudFront + Functions/KVS traffic switch |
| 4 | **T4: Observability & SRE** | Code written / `[Pending incident]` | SLOs & error-budget policy, CloudWatch & Cloud Monitoring dashboards + multi-window burn-rate & cause alerts, API→Worker `trace_id`, `db_query_duration_seconds`, synthetic probe, runbooks |
| 5 | **T5: Business Continuity / DR** | Code written / `[Pending game day]` | 10-min immutable S3 Object Lock + GCS retention backups via `nwo-aws` WIF, Cloud Run restore job + Scheduler (`dr_state` promotion guard), automated `failover.yml` printing RPO/RTO |
| 6 | **T6: Legacy Migration** | Code written / `[Pending verify]` | 6Rs plan (`docs/migration-plan.md`), repeatable loader & SHA-256 validator handling 6 dump/job issues, cutover/rollback plan, containerized `app.settlement` + nightly EventBridge schedule |

---

## 4. Decision Log (Target: 8–10 Key Decisions)

### Decision 1 (T2): Build CI/CD & IaC Foundation (T2) Before Cloud Infrastructure (T1)
- **Choice:** Implemented the modular Terraform structure, remote state backends (`use_lockfile = true` on S3, native locking on GCS), OIDC/WIF keyless workflows, and tag/security gates first.
- **Alternatives Rejected:**
  - *Provisioning AWS manually or via local `terraform apply` first and adding CI/CD later:* Violates Ground Rule 1 ("Everything is code... deployed by GitHub Actions from `main`") and risks untagged resources or state drift from day one.

### Decision 2 (T2): S3 Native State Locking (`use_lockfile = true`) with Terraform `>= 1.10`
- **Choice:** Used Terraform 1.10.5 with S3 native `.tflock` locking (`use_lockfile = true`) and GCS native object-generation locking, dynamically passing `<USERNAME>/<stack>/terraform.tfstate` at `terraform init`.
- **Alternatives Rejected:**
  - *DynamoDB lock table:* Explicitly forbidden by the shared AWS CI role permissions (no `dynamodb:*` permissions).
  - *Hardcoded backend keys in `backend.tf`:* Would expose candidate usernames or require editing code per candidate instead of parameterizing via GitHub Variables.

### Decision 3 (T2): Immutable Image Digest Tagging (`@sha256:...`) in `dev` Deployment
- **Choice:** Built and Trivy-scanned the container image once, pushed to `dev` ECR, and deployed ECS tasks referencing the immutable `@sha256:...` digest rather than a mutable tag.
- **Alternatives Rejected:**
  - *Deploying `:latest` mutable tags:* Makes rollbacks ambiguous and risks deploying unverified builds.
  - *(Note: `prod` environment was omitted for this `dev`-only deployment; if `prod` is added later, digest promotion via `crane copy` can be enabled without rebuilding.)*

### Decision 4 (T2): Dual Tag & Security Enforcement (Python Plan Validator + OPA/Conftest)
- **Choice:** Enforced the mandatory `username` tag/label and security baselines (no public DBs, no `0.0.0.0/0` except ALB 80/443, no `allUsers`) directly against `terraform show -json` plan output using `.github/scripts/check_tags.py` and `.github/policy/tags.rego` (Conftest).
- **Alternatives Rejected:**
  - *Regex/grep on `.tf` files:* Easily bypassed by `default_tags`, modules, or dynamic blocks; inspecting the resolved Terraform plan JSON guarantees every actual AWS/GCP resource change is checked accurately.

### Decision 5 (T1): ECS Fargate on Shared Private Subnets with Chained Security Groups
- **Choice:** Deployed API (`0.25 vCPU / 0.5 GB`, 2–4 tasks) and Worker (`0.25 vCPU / 0.5 GB`, 1–2 tasks) on ECS Fargate in the shared private subnets behind an ALB in the public subnets, with RDS Multi-AZ in the data subnets and strict chained security groups (`ALB -> ECS -> RDS`).
- **Alternatives Rejected:**
  - *EC2-backed ECS or EKS:* Forbidden by the shared CI role (`ec2:RunInstances` denied) and unnecessary operational overhead for two stateless containers.
  - *Single API task (`min = 1`):* Would cause downtime during rolling deploys or AZ loss; `min = 2` spans both `us-east-1a` and `us-east-1b` while keeping per-task CPU/memory at half the ceiling (`256/512`).

### Decision 6 (T1): HTTP Listener on ALB with CloudFront HTTPS Edge Compensation (Rule 6 Exception)
- **Choice:** Exposed the ALB on HTTP port 80 (no custom domain/ACM cert is available for the ALB's default AWS hostname) and documented this as an accepted Rule 6 risk, compensated by placing CloudFront HTTPS in front (T3), enforcing TLS-only (`rds.force_ssl=1`, S3/SQS `aws:SecureTransport=true`) internally, and locking down ECS/RDS ingress strictly to upstream security groups.
- **Alternatives Rejected:**
  - *Self-signed certificate on ALB:* Untrusted by standard clients and unnecessary once CloudFront terminates public TLS.

### Decision 7 (T3): AWS CloudFront + CloudFront Function + KeyValueStore for Cross-Cloud Edge & Traffic Switch
- **Choice:** Used a single AWS CloudFront distribution (`cloudfront_default_certificate = true`) fronting both AWS ALB (`http-only` + `X-Origin-Verify` header) and GCP Cloud Run (`https-only`) with `Managed-CachingDisabled`, `Managed-AllViewerExceptHostHeader`, and a `cloudfront-js-2.0` viewer-request function reading `aws_weight` (`0..100`) from CloudFront KeyValueStore.
- **Alternatives Rejected:**
  - *Route 53 weighted DNS:* No domain/DNS zone is provided, DNS TTL caching violates `< 60s` deterministic switching, and ALB/Cloud Run hostnames would be exposed or require custom TLS certs.
  - *Updating CloudFront origin weights via Terraform apply:* Slow (minutes for distribution deploy) and violates T3 requirement 5 ("without applying Terraform or redeploying, and take effect within 60 seconds"). KeyValueStore updates propagate globally in ~1–5 seconds across all HTTP methods including `POST`.

### Decision 8 (T3): Deliberate Traffic Switch (No Automatic Failover) & Per-Service Cloud Run Invoker Setting
- **Choice:** Kept cross-cloud failover deliberate (operator/workflow-triggered) to prevent stateful PostgreSQL split-brain between AWS RDS and GCP Cloud SQL, and used `invoker_iam_disabled = true` on Cloud Run API only (with Worker internal-only) to comply with GCP's `allUsers` org-policy ban.
- **Alternatives Rejected:**
  - *Automatic CloudFront origin-group failover on 5xx:* Would route writes to an un-restored/stale Cloud SQL database during transient errors, causing split-brain data divergence.
  - *Deploying a GCP External HTTPS Load Balancer + Cloud Armor:* Adds significant idle cost and complexity to mask `*.run.app` when CloudFront already terminates public TLS; documented as an accepted GCP exposure tradeoff in [docs/architecture.md](docs/architecture.md).

### Decision 9 (T4): Propagate API Request `trace_id` Through Queue Payloads & Add `db_query_duration_seconds`
- **Choice:** Updated [app/main.py](app/main.py) (`create_order`) to include `trace_id` in the published queue message, updated [app/worker.py](app/worker.py) to bind `trace_id_var` from `msg.payload.get("trace_id")` and log `"order processed"`, and added `db_query_duration_seconds` Prometheus histogram in [app/metrics.py](app/metrics.py).
- **Alternatives Rejected:**
  - *Leaving the starter app unchanged:* The starter worker bound `trace_id_var` to the queue `msg.id` (SQS/PubSub message ID) rather than the API HTTP request `trace_id`, making it impossible to correlate a client request's `trace_id` across API and worker logs as required by T4.

### Decision 10 (T5): Keyless WIF Cross-Cloud Immutable Backups & Promotion-Guarded Restore
- **Choice:** Scheduled an ECS Fargate backup task every 10 minutes (`rate(10 minutes)`) running as `AWS_BACKUP_TASK_ROLE_ARN` (`nwo-backup-task`), writing timestamped gzipped snapshots to an S3 Object Lock (`GOVERNANCE`, 7d) bucket and federating via `nwo-aws` WIF (`external_account` using Fargate STS creds) to a GCS bucket with a 7-day retention policy; paired with a Cloud Run restore job (`app.dr_restore`) that checks/sets `dr_state.promoted = 'true'` to block scheduled overwrites after failover.
- **Alternatives Rejected:**
  - *Cross-cloud PostgreSQL streaming replication over public internet or VPN:* Requires long-lived network/tunnel changes prohibited in the shared VPC and exceeds shared budget guardrails.
  - *Installing `pg_dump` in the app image:* Expands OS CVE scan surface (`debian` packages) and risks version mismatch; pure-Python `psycopg` logical snapshots + `init_db()` work uniformly in the single existing image and allow application-level `dr_state` promotion protection.

---

## 5. Task Evidence & Screenshots

> **100% Web-Based Verification (No Local AWS/GCP/GitHub CLI Required):** Every operational and verification task can be triggered directly from **GitHub → Actions → Run workflow** and inspected via the generated **Job Summary**, **Browser (`https://<cloudfront_domain_name>/`)**, **AWS Console**, and **GCP Console**:
> - **T1 & T3 Endpoints + Receipts + 403 No-Bypass:** Actions → **Web Verification Toolbox** → `mode = t1-t3-endpoints`
> - **T3 Traffic Switch (`100/0` ↔ `0/100`):** Actions → **Cross-Cloud Traffic Switch** → `aws_percentage = 0` (or `100`)
> - **T4 Synthetic Probe, Trace ID & DB Metrics:** Actions → **Web Verification Toolbox** → `mode = t4-trace-and-probe` (and **Synthetic Probe** workflow)
> - **T5 Backup Immutability & Standby Restore:** Actions → **Web Verification Toolbox** → `mode = t5-backup-and-restore-test`
> - **T5 Full DR Failover (Data First, Then Traffic + RTO/RPO):** Actions → **DR Failover (AWS -> GCP)** → Run workflow
> - **T6 Repeatable Load, SHA-256 Validation & Settlement:** Actions → **Task 6 Legacy Migration Rehearsal** → Run workflow (and `mode = t6-ecs-settlement` in **Web Verification Toolbox**)

### T2: Infrastructure as Code & CI/CD
- **Pull Request Check Run URL:** `[PLACEHOLDER: https://github.com/Deloitte-DT-Training/hu-devops-26-nov-<username>/actions/runs/...]`
- **Blocked/Failed Tag Check PR URL (Test):** `[PLACEHOLDER: link to PR where an untagged resource failed check_tags.py / Conftest]`
- **Merge-to-Main Deploy Run URL (`dev`):** `[PLACEHOLDER: https://github.com/Deloitte-DT-Training/hu-devops-26-nov-<username>/actions/runs/...]`
- **Drift Detection Run URL:** `[PLACEHOLDER: link to scheduled/manual drift-detection run]`
- **Verification Commands (standalone, run one by one):**
  1. Trigger drift check manually:
     ```bash
     gh workflow run drift-detection.yml
     ```
  2. Check AWS & GCP remote state prefixes:
     ```bash
     aws s3 ls s3://<TF_STATE_BUCKET>/<USERNAME>/
     ```
     ```bash
     gcloud storage ls gs://<GCP_TF_STATE_BUCKET>/<USERNAME>/
     ```
- **Verification Outputs & Screenshots:**
  - `[PLACEHOLDER: Screenshot — GitHub Actions PR Checks passing + Terraform Plan PR comment]`
  - `[PLACEHOLDER: Screenshot — Failed PR Check when adding an untagged resource (check_tags.py / Conftest)]`
  - `[PLACEHOLDER: Screenshot — S3 & GCS state buckets showing <USERNAME>/ prefix]`
  - `[PLACEHOLDER: Screenshot — Drift Detection run]`
- **Rollback Summary:** See [docs/ci-cd.md](docs/ci-cd.md) — `dev` deploys automatically on merge to `main`, and ECS deployment circuit breaker (`enable = true, rollback = true`) plus `/readyz` ALB health checks automatically roll back unhealthy revisions.

### T1: AWS Platform
- **Sizing & Cost Analysis:** See [docs/architecture.md](docs/architecture.md)
- **PR Run URL (`aws-dev` plan):** `[PLACEHOLDER: link to PR check run]`
- **Merge-to-Main Deploy Run URL (`aws-dev` apply + ECR push):** `[PLACEHOLDER: link to deploy-aws run]`
- **Verification Commands (standalone, run one by one):**
  1. Check ALB DNS name:
     ```bash
     aws elbv2 describe-load-balancers --region us-east-1 --names nwo-<username>-dev-alb --query LoadBalancers[0].DNSName --output text
     ```
  2. Verify readiness, order creation, processing, and S3 receipt (via CloudFront once T3 is active, or ALB before `enable_edge_only`):
     ```bash
     curl -s https://<cloudfront_domain_name>/readyz
     ```
     ```bash
     curl -s -X POST https://<cloudfront_domain_name>/orders -H "Content-Type: application/json" -d "{\"customer_id\":\"c-t1-aws\",\"amount_cents\":1999,\"currency\":\"USD\"}"
     ```
     ```bash
     curl -s https://<cloudfront_domain_name>/orders/<order_id>
     ```
     ```bash
     aws s3 ls s3://nwo-<username>-dev-receipts-<account_id>/receipts/
     ```
  3. Verify ECR image scan, ECS tasks, SQS + DLQ, and Multi-AZ RDS:
     ```bash
     aws ecr describe-images --region us-east-1 --repository-name nwo-<username>-dev-orders
     ```
     ```bash
     aws ecs list-tasks --region us-east-1 --cluster nwo-<username>-dev-cluster
     ```
     ```bash
     aws sqs get-queue-attributes --region us-east-1 --queue-url <sqs_queue_url> --attribute-names RedrivePolicy KmsMasterKeyId
     ```
     ```bash
     aws rds describe-db-instances --region us-east-1 --db-instance-identifier nwo-<username>-dev-pg --query "DBInstances[0].{MultiAZ:MultiAZ,Public:PubliclyAccessible,Encrypted:StorageEncrypted,Engine:Engine}"
     ```
- **End-to-End `POST /orders` & Receipt Verification Output:**

  ![POST/order](images/post_order.png)

  ![GET/order](images/check_order_status.png)

- **Screenshots:**
  - ECR repository showing pushed image + KMS / scan:

    ![Screenshot of ECR repository showing pushed image](images/ECR_image-KMS.png)

    ![Screenshot of ECR repository showing pushed image](images/ECR_image.png)

  - ECS cluster showing running API (2 tasks) & Worker (1 task):

    ![Screenshot of ECS cluster showing running API (2 tasks) & Worker (1 task)](images/ECS_cluster_running.png)

  - RDS Multi-AZ `db.t4g.micro` (private, KMS-encrypted):

    ![Screenshot of RDS Multi-AZ db.t4g.micro](images/RDS.png)

  - S3 receipts bucket with `receipts/<order_id>.json`:

    ![S3 Receipt](images/s3_receipts.png)

  - `[PLACEHOLDER: Screenshot — SQS queue + DLQ redrive policy]`
  - `[PLACEHOLDER: (Stretch) HA failover test output — forced RDS failover + task kill under load]`

### T3: GCP Platform & Cross-Cloud Traffic
- **Cloud SQL Zonal/PITR, Failover Behavior, No-Bypass & Cloud Comparison:** See [docs/architecture.md](docs/architecture.md#gcp-platform--cross-cloud-edge-task-3)
- **GCP Deploy Run URL:** `[PLACEHOLDER: link to deploy-gcp run]`
- **Edge Deploy Run URL:** `[PLACEHOLDER: link to deploy-edge run]`
- **Traffic Switch Test Run URL (`100/0 -> 0/100 -> 100/0`):** `[PLACEHOLDER: link to traffic-switch run]`
- **Verification Commands (standalone, run one by one):**
  1. Check normal state (`100% AWS / 0% GCP`):
     ```bash
     curl -s https://<cloudfront_domain_name>/version
     ```
  2. Check readiness via public hostname:
     ```bash
     curl -s https://<cloudfront_domain_name>/readyz
     ```
  3. Create an order on AWS through CloudFront & verify `PROCESSED`:
     ```bash
     curl -s -X POST https://<cloudfront_domain_name>/orders -H "Content-Type: application/json" -d "{\"customer_id\":\"c-t3-aws\",\"amount_cents\":1500,\"currency\":\"USD\"}"
     ```
     ```bash
     curl -s https://<cloudfront_domain_name>/orders/<order_id>
     ```
  4. Verify Stretch (No-bypass) — direct ALB request must return `403`:
     ```bash
     curl -i http://<alb_dns_name>/version
     ```
  5. Switch `100%` traffic to GCP (`0/100`) without Terraform/redeploy:
     ```bash
     gh workflow run traffic-switch.yml -f aws_percentage=0
     ```
  6. Verify `gcp` answers within 60 seconds:
     ```bash
     curl -s https://<cloudfront_domain_name>/version
     ```
  7. Create an order on GCP through CloudFront, verify `PROCESSED`, and verify GCS receipt:
     ```bash
     curl -s -X POST https://<cloudfront_domain_name>/orders -H "Content-Type: application/json" -d "{\"customer_id\":\"c-t3-gcp\",\"amount_cents\":2500,\"currency\":\"USD\"}"
     ```
     ```bash
     curl -s https://<cloudfront_domain_name>/orders/<order_id>
     ```
     ```bash
     gcloud storage ls gs://nwo-<username>-dev-receipts-<gcp_project_id>/receipts/
     ```
  8. Switch traffic back to `100%` AWS (`100/0`) and confirm `aws`:
     ```bash
     gh workflow run traffic-switch.yml -f aws_percentage=100
     ```
     ```bash
     curl -s https://<cloudfront_domain_name>/version
     ```
- **Verification Outputs:**
  ```text
  [PLACEHOLDER: paste outputs from commands 1–8 above]
  ```
- **Screenshots:**
  - `[PLACEHOLDER: Screenshot — Cloud Run services (API + internal Worker running as nwo-runtime)]`
  - `[PLACEHOLDER: Screenshot — Cloud SQL pg16 (private IP only, zonal, PITR enabled)]`
  - `[PLACEHOLDER: Screenshot — GCS receipts bucket with receipts/<order_id>.json]`
  - `[PLACEHOLDER: Screenshot — CloudFront distribution & KeyValueStore]`
  - `[PLACEHOLDER: Screenshot — Web UI (https://<cloudfront_domain_name>/) showing AWS badge]`
  - `[PLACEHOLDER: Screenshot — Web UI (https://<cloudfront_domain_name>/) showing GCP badge after traffic switch]`
  - `[PLACEHOLDER: Screenshot — Direct ALB curl returning 403 Forbidden]`

### T4: Observability & SRE (and Incident Postmortem)
- **SLO Document & Error-Budget Policy:** [docs/slo.md](docs/slo.md)
- **Capacity Statement (Stretch):** [docs/capacity.md](docs/capacity.md)
- **On-Call Runbooks:** [docs/runbooks/README.md](docs/runbooks/README.md) ([availability](docs/runbooks/availability-burn-rate.md), [latency](docs/runbooks/latency-burn-rate.md), [endpoint-down](docs/runbooks/endpoint-down.md))
- **Postmortem Template / Report:** [docs/postmortem-template.md](docs/postmortem-template.md)
- **Verification Commands (standalone, run one by one):**
  1. Run the synthetic probe against the public hostname:
     ```bash
     python3 .github/scripts/probe.py https://<cloudfront_domain_name>
     ```
  2. Trigger the scheduled synthetic probe workflow manually:
     ```bash
     gh workflow run synthetic-probe.yml
     ```
  3. Create an order with an explicit trace header to verify end-to-end `trace_id` across API and Worker logs:
     ```bash
     curl -i -X POST https://<cloudfront_domain_name>/orders -H "Content-Type: application/json" -H "X-Cloud-Trace-Context: trace-verify-t4-001/1;o=1" -d "{\"customer_id\":\"c-trace-t4\",\"amount_cents\":1200,\"currency\":\"USD\"}"
     ```
  4. Query AWS CloudWatch Logs (`nwo-<username>-dev-api` & `nwo-<username>-dev-worker`) for `trace_id`:
     ```bash
     aws logs filter-log-events --region us-east-1 --log-group-name nwo-<username>-dev-api --filter-pattern "{ $.trace_id = \"trace-verify-t4-001\" }"
     ```
     ```bash
     aws logs filter-log-events --region us-east-1 --log-group-name nwo-<username>-dev-worker --filter-pattern "{ $.trace_id = \"trace-verify-t4-001\" }"
     ```
  5. Check extra `db_query_duration_seconds` Prometheus instrumentation on `/metrics`:
     ```bash
     curl -s https://<cloudfront_domain_name>/metrics
     ```
- **Verification Outputs & Screenshots:**
  - `[PLACEHOLDER: Screenshot — AWS CloudWatch Dashboard (nwo-<username>-dev-dashboard)]`
  - `[PLACEHOLDER: Screenshot — AWS CloudWatch Composite Burn-Rate & Cause Alarms]`
  - `[PLACEHOLDER: Screenshot — GCP Cloud Monitoring Dashboard & SLOs (99.9% avail, 99% latency)]`
  - `[PLACEHOLDER: Screenshot — GCP Uptime Check & Multi-Window Burn-Rate Alerts]`
  - `[PLACEHOLDER: Screenshot — API & Worker logs sharing identical trace_id]`
  - `[PLACEHOLDER: Screenshot — Synthetic probe output showing active cloud & visible failure test]`
- **Live Incident Postmortem (Fill Within 60 Min of Fault Injection):**
  - `[PLACEHOLDER: paste link or full postmortem once evaluators inject the fault]`

### T5: Business Continuity (DR, Restores, Game Day)
- **DR Runbook, Standby Safety, Failback & Cost Analysis:** [docs/runbooks/dr-failover.md](docs/runbooks/dr-failover.md)
- **Game-Day Report Template:** [docs/game-day-report-template.md](docs/game-day-report-template.md)
- **Failover Workflow Run URL:** `[PLACEHOLDER: link to failover.yml run]`
- **Game-Day Measured RPO:** `[PLACEHOLDER: e.g. 240s (Target <= 900s / 15m)]`
- **Game-Day Measured RTO:** `[PLACEHOLDER: e.g. 75s (Target <= 1800s / 30m)]`
- **Verification Commands (standalone, run one by one):**
  1. Confirm immutable backups exist in S3 (`Object Lock`) and GCS (`retentionPolicy`):
     ```bash
     aws s3 ls s3://nwo-<username>-dev-backups-<account_id>/backups/
     ```
     ```bash
     aws s3api get-object-lock-configuration --bucket nwo-<username>-dev-backups-<account_id>
     ```
     ```bash
     gcloud storage ls gs://nwo-<username>-dev-backups-<gcp_project_id>/backups/
     ```
     ```bash
     gcloud storage buckets describe gs://nwo-<username>-dev-backups-<gcp_project_id> --format="yaml(retentionPolicy)"
     ```
  2. Manually trigger a backup task immediately on ECS (optional, otherwise runs every 10 min):
     ```bash
     aws ecs run-task --region us-east-1 --cluster nwo-<username>-dev-cluster --launch-type FARGATE --task-definition nwo-<username>-dev-backup --network-configuration "awsvpcConfiguration={subnets=[<private_subnet_1>,<private_subnet_2>],securityGroups=[<ecs_sg_id>],assignPublicIp=DISABLED}"
     ```
  3. Prove restorability (run Cloud Run restore job into Cloud SQL):
     ```bash
     gcloud run jobs execute nwo-<username>-dev-restore --region us-east4 --wait
     ```
  4. Run automated DR failover (data first, then traffic, prints measured RTO & RPO):
     ```bash
     gh workflow run failover.yml
     ```
  5. Verify post-failover GCP serving & end-to-end order processing:
     ```bash
     curl -s https://<cloudfront_domain_name>/version
     ```
     ```bash
     curl -s -X POST https://<cloudfront_domain_name>/orders -H "Content-Type: application/json" -d "{\"customer_id\":\"c-dr-verify\",\"amount_cents\":3300,\"currency\":\"USD\"}"
     ```
     ```bash
     curl -s https://<cloudfront_domain_name>/orders/<order_id>
     ```
- **Restore Evidence & Game-Day Output:**
  ```text
  [PLACEHOLDER: paste restore job logs, failover.yml RTO/RPO summary, and post-failover order output]
  ```
- **Screenshots:**
  - `[PLACEHOLDER: Screenshot — S3 backups bucket with Object Lock + GCS backups bucket with retention policy]`
  - `[PLACEHOLDER: Screenshot — Cloud Run restore job execution log showing orders restored into Cloud SQL]`
  - `[PLACEHOLDER: Screenshot — failover.yml run summary printing Measured RPO & RTO]`
  - `[PLACEHOLDER: Screenshot — Post-failover order PROCESSED on GCP]`

### T6: Legacy Migration
- **6Rs Strategy, Data-Quality Findings, Cutover/Rollback & Canary Plan:** [docs/migration-plan.md](docs/migration-plan.md)
- **Repeatable Loader:** [scripts/migration/load_legacy.py](scripts/migration/load_legacy.py)
- **Validation Script:** [scripts/migration/validate_legacy.py](scripts/migration/validate_legacy.py)
- **Cloud-Native Settlement Job (Stretch):** [app/settlement.py](app/settlement.py) + [terraform/modules/aws-platform/migration.tf](terraform/modules/aws-platform/migration.tf)
- **Data-Quality Problems Found & Explicit Decisions:**
  1. **9 NULL customer emails (`\N`)** → kept `email` nullable and `COALESCE(c.email, '')` in `app.settlement`.
  2. **12 case-insensitive duplicate emails (`USER21@Example.com` vs `user21@example.com`)** → preserved all 500 PKs, added non-unique `email_normalized` index, logged duplicates for business cleanup.
  3. **37 dirty invoice statuses (`'paid '`)** → normalized via `UPPER(TRIM(status))` (restoring all `3,979` `PAID` invoices) + added `CHECK` constraint.
  4. **Naive `America/New_York` timestamps + 1 DST spring-forward gap timestamp (`2024-03-10 02:38:50` at line 4700)** → deterministic conversion to UTC `TIMESTAMPTZ` (`fold=0`) and NY-timezone settlement window bounds.
  5. **Sequence high-water marks > `MAX(id)` (`637`, `12200`) & missing `DEFAULT`** → added `DEFAULT nextval(...)` and preserved `setval` values.
  6. **Host assumptions in `legacy/nightly_settlement.py`** → migrated to `app.settlement` on ECS Fargate + EventBridge (`01:30 America/New_York`), Secrets Manager password, S3 CSV output.
- **Verification Commands (standalone, run one by one):**
  1. Run local PostgreSQL container (if rehearsing locally via `docker compose`):
     ```bash
     docker compose up -d db
     ```
  2. Run repeatable loader twice to prove idempotency:
     ```bash
     python3 scripts/migration/load_legacy.py --dump legacy/legacy_dump.sql
     ```
     ```bash
     python3 scripts/migration/load_legacy.py --dump legacy/legacy_dump.sql
     ```
  3. Run validation script (proves row counts, SHA-256 checksums, sequences, and data quality match):
     ```bash
     python3 scripts/migration/validate_legacy.py --dump legacy/legacy_dump.sql
     ```
  4. Run settlement job locally against rehearsed DB:
     ```bash
     python -m app.settlement 2024-06-15
     ```
  5. Run unit tests for migration & settlement:
     ```bash
     python -m pytest -v
     ```
  6. *(Stretch on AWS)* Run settlement task on ECS Fargate (writes CSV to S3 `receipts` bucket under `settlements/`):
     ```bash
     aws ecs run-task --region us-east-1 --cluster nwo-<username>-dev-cluster --launch-type FARGATE --task-definition nwo-<username>-dev-settlement --network-configuration "awsvpcConfiguration={subnets=[<private_subnet_1>,<private_subnet_2>],securityGroups=[<ecs_sg_id>],assignPublicIp=DISABLED}"
     ```
     ```bash
     aws s3 ls s3://nwo-<username>-dev-receipts-<account_id>/settlements/
     ```
- **Load & Validation Output:**
  ```text
  [PLACEHOLDER: paste output of load_legacy.py and validate_legacy.py]
  ```
- **Screenshots:**
  - `[PLACEHOLDER: Screenshot — Repeatable load + validate_legacy.py showing VALIDATION PASSED and SHA-256 agreement]`
  - `[PLACEHOLDER: Screenshot — (Stretch) S3 settlements/settlement_YYYYMMDD.csv & EventBridge nightly schedule]`

---

## 6. Incomplete Items / Known Limitations
- All tasks T1–T6 are implemented in code; `[update with any remaining live test runs, postmortem, or game-day outputs before final hand-in]`.
- **Shared AWS CI Role (`github-oidc-role`) IAM Limitation on CloudWatch:** The shared `github-oidc-role` returns `AccessDenied` for `cloudwatch:PutCompositeAlarm` and `cloudwatch:PutDashboard` (global dashboard ARN `arn:aws:cloudwatch::015230892207:dashboard/...`). As an alternative, AWS multi-window burn-rate alerts are deployed as paired `aws_cloudwatch_metric_alarm` resources (`5m`/`1h` fast burn & `30m`/`6h` slow burn, with SNS paging + runbook links), `aws_cloudwatch_dashboard.main` is gated behind `var.create_cloudwatch_dashboard = false`, the dashboard definition is versioned in [docs/dashboards/aws-cloudwatch-dashboard.json](docs/dashboards/aws-cloudwatch-dashboard.json), and GCP Cloud Monitoring hosts the full live dashboard (`nwo-<username>-dev-dashboard`), SLOs, and composite multi-window burn-rate alert policies.
- `prod` environment stacks were omitted for this `dev`-only configuration.
- `[Update before final submission with any remaining gaps or accepted constraints]`
