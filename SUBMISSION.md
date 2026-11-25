# Northwind Orders — Multi-Cloud Platform Submission

> **Note:** This document is updated incrementally as each task (T2 → T1 → T3 → T4 → T5 → T6) is built and verified. Replace `[PLACEHOLDER: ...]` blocks with actual outputs, URLs, and screenshots from your execution environment.

---

## 1. Public Endpoint & Traffic Switch Summary
- **Public Hostname:** `[PLACEHOLDER: https://dxxxxxxxxxxxx.cloudfront.net (from T3)]`
- **`curl https://<hostname>/version` output:**
  ```json
  [PLACEHOLDER: paste output from T3]
  ```
- **Traffic Switch Command / Workflow:** `[PLACEHOLDER: exact gh workflow run / CLI command from T3]`

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
| 3 | **T3: GCP Platform & Edge** | Pending | After T1 |
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

*(Decisions 7–10 will be added across T3, T4, T5, and T6.)*

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
- `[PLACEHOLDER: To be populated in Task 3]`

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
