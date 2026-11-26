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
  ```bash
  # Sets traffic split anywhere from 100/0 (AWS/GCP) to 0/100 in < 60s with no Terraform/redeploy:
  gh workflow run traffic-switch.yml -f aws_percentage=0
  # Or directly via AWS CLI + helper script:
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
| 2 | **T1: AWS Platform** | Code written / `[Pending run]` | Multi-AZ RDS PG16, ECS Fargate API & Worker in private subnets, ALB (`/readyz`), SQS+DLQ, S3 receipts, CMK KMS, least-privilege IAM |
| 3 | **T3: GCP Platform & Edge** | Code written / `[Pending run]` | Cloud Run API & Worker (Direct VPC), Cloud SQL PG16 (private IP, PITR), Pub/Sub+DLQ, GCS, Secret Manager, CloudFront + Functions/KVS traffic switch |
| 4 | **T4: Observability & SRE** | Pending | After T3 |
| 5 | **T5: Business Continuity / DR** | Pending | After T3/T4 |
| 6 | **T6: Legacy Migration** | Pending | Final task |

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

*(Decisions 9–10 will be added across T4, T5, and T6.)*

---

## 5. Task Evidence & Screenshots

### T2: Infrastructure as Code & CI/CD
- **Pull Request Check Run URL:** `[PLACEHOLDER: https://github.com/Deloitte-DT-Training/hu-devops-26-nov-<username>/actions/runs/...]`
- **Blocked/Failed Tag Check PR URL (Test):** `[PLACEHOLDER: link to PR where an untagged resource failed check_tags.py / Conftest]`
- **Merge-to-Main Deploy Run URL (`dev`):** `[PLACEHOLDER: https://github.com/Deloitte-DT-Training/hu-devops-26-nov-<username>/actions/runs/...]`
- **Drift Detection Run URL:** `[PLACEHOLDER: link to scheduled/manual drift-detection run]`
- **Screenshots:**
  - `[PLACEHOLDER: Screenshot of PR checks passing + Terraform Plan PR comment]`
  - `[PLACEHOLDER: Screenshot of failed PR check when adding an untagged resource]`
  - `[PLACEHOLDER: Screenshot of S3 & GCS state buckets showing <USERNAME>/ prefix]`
- **Rollback Summary:** See [docs/ci-cd.md](docs/ci-cd.md) — `dev` deploys automatically on merge to `main`, and ECS deployment circuit breaker (`enable = true, rollback = true`) plus `/readyz` ALB health checks automatically roll back unhealthy revisions.

### T1: AWS Platform
- **Sizing & Cost Analysis:** See [docs/architecture.md](docs/architecture.md)
- **PR Run URL (`aws-dev` plan):** `[PLACEHOLDER: link to PR check run]`
- **Merge-to-Main Deploy Run URL (`aws-dev` apply + ECR push):** `[PLACEHOLDER: link to deploy-aws run]`
- **End-to-End `POST /orders` & Receipt Verification Output:**
  ```bash
  [PLACEHOLDER: paste curl POST /orders, GET /orders/{id} showing PROCESSED, and aws s3 ls s3://<receipts-bucket>/receipts/]
  ```
- **Screenshots:**
  - `[PLACEHOLDER: Screenshot of ECR repository showing pushed image + Trivy/ECR scan]`
  - `[PLACEHOLDER: Screenshot of ECS cluster showing running API (2 tasks) & Worker (1 task)]`
  - `[PLACEHOLDER: Screenshot of RDS Multi-AZ db.t4g.micro (private, KMS-encrypted)]`
  - `[PLACEHOLDER: Screenshot of S3 receipts bucket with receipts/<order_id>.json]`
  - `[PLACEHOLDER: (Stretch) HA failover test output — forced RDS failover + task kill under load]`

### T3: GCP Platform & Cross-Cloud Traffic
- **Cloud SQL Zonal/PITR, Failover Behavior, No-Bypass & Cloud Comparison:** See [docs/architecture.md](docs/architecture.md#gcp-platform--cross-cloud-edge-task-3)
- **GCP Deploy Run URL:** `[PLACEHOLDER: link to deploy-gcp run]`
- **Edge Deploy Run URL:** `[PLACEHOLDER: link to deploy-edge run]`
- **Traffic Switch Test Run URL (`100/0 -> 0/100 -> 100/0`):** `[PLACEHOLDER: link to traffic-switch run]`
- **Verification Outputs:**
  ```bash
  # Normal state (100% AWS):
  [PLACEHOLDER: curl -s https://<cloudfront_domain>/version]
  # Switched state (0/100 -> GCP within 60s) + POST /orders on GCP:
  [PLACEHOLDER: curl -s https://<cloudfront_domain>/version && curl -s -X POST https://<cloudfront_domain>/orders ...]
  # Direct ALB bypass check (403 Forbidden):
  [PLACEHOLDER: curl -i http://<alb_dns_name>/version]
  ```
- **Screenshots:**
  - `[PLACEHOLDER: Screenshot of Cloud Run services (API + internal Worker running as nwo-runtime)]`
  - `[PLACEHOLDER: Screenshot of Cloud SQL pg16 (private IP only, zonal, PITR enabled)]`
  - `[PLACEHOLDER: Screenshot of CloudFront distribution & KeyValueStore]`
  - `[PLACEHOLDER: Screenshot of web UI (https://<cloudfront_domain>/) showing AWS badge and GCP badge after switch]`

### T4: Observability & SRE (and Incident Postmortem)
- `[PLACEHOLDER: To be populated in Task 4]`

### T5: Business Continuity (DR, Restores, Game Day)
- `[PLACEHOLDER: To be populated in Task 5]`
- **Game-Day Measured RPO:** `[PLACEHOLDER]`
- **Game-Day Measured RTO:** `[PLACEHOLDER]`

### T6: Legacy Migration
- `[PLACEHOLDER: To be populated in Task 6]`

---

## 6. Incomplete Items / Known Limitations
- Tasks T1, T3, T4, T5, T6 are pending implementation (building task by task).
- `[Update before final submission with any remaining gaps or accepted constraints]`
