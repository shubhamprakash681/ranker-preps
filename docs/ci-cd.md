# CI/CD Pipeline, Promotion, Rollback & Least-Privilege Notes (Task 2)

## 1. Build Order Rationale
We implemented **T2 (IaC & CI/CD Foundation)** first before provisioning cloud infrastructure so that **100% of resources are deployed via GitHub Actions from `main`**, never manually from a laptop. Having PR checks, remote state locking, OIDC/WIF keyless authentication, and tag enforcement active from commit one prevents untagged resources, state corruption, and unrepeatable manual changes.

## 2. Pipeline Architecture
- **Pull Request Checks (`.github/workflows/pr-checks.yml`)**:
  - `app-tests`: Runs `pytest` unit tests for the FastAPI service and worker.
  - `static-checks`: Runs `terraform fmt -check -recursive`, `terraform validate`, `tflint` (AWS + Google rulesets), and `trivy` IaC misconfiguration scan (fails on `HIGH`/`CRITICAL`).
  - `plan-aws` / `plan-gcp`: Authenticates via AWS OIDC and GCP Workload Identity Federation, initializes isolated remote state (`<USERNAME>/<env>/terraform.tfstate`), generates `tfplan.json`, enforces mandatory `username` tags/labels and security baselines via both `.github/scripts/check_tags.py` and OPA/Conftest (`.github/policy/tags.rego`), and posts the plan diff as a PR comment.
- **Deploy on Merge (`.github/workflows/deploy-aws.yml`)**:
  - **Concurrency control**: `concurrency: { group: deploy-aws-${{ github.ref }}, cancel-in-progress: false }` guarantees two applies cannot race on the same state.
  - **Build & Scan once**: Builds the Docker image once and scans it with Trivy (`CRITICAL,HIGH` fail the build).
  - **Deploy `dev` automatically**: Pushes the image to `dev` ECR, captures the immutable `@sha256:...` digest, and runs `terraform apply` for `aws-dev`.
- **Scheduled Drift Detection (`.github/workflows/drift-detection.yml`)**:
  - Runs every 6 hours (`cron: "0 */6 * * *"`), executes `terraform plan -detailed-exitcode`, and automatically opens/updates a GitHub Issue labeled `drift` if exit code `2` is returned.

## 3. Safe Failure & Rollback
- **Image scan gate**: If Trivy finds `CRITICAL`/`HIGH` CVEs or unit tests fail, the image is never pushed.
- **ALB + `/readyz` readiness gate**: New ECS tasks must pass `/readyz` (verifying database connectivity) before the ALB routes user traffic to them.
- **ECS Deployment Circuit Breaker**: Configured with `enable = true` and `rollback = true`, combined with `wait_for_steady_state = true`. If new tasks crash or fail `/readyz`, ECS automatically rolls back to the last stable task definition revision and Terraform exits non-zero so the pipeline marks the deployment failed.

## 4. Least-Privilege Improvements for the Shared CI Role
The provided shared `AWS_ROLE_ARN` and `GCP_SERVICE_ACCOUNT` are already scoped to platform services and `us-east-1`/`us-east4`, but in a single-tenant production setup we would further narrow them by:
1. **Scoping resource ARNs to exact `${NAME_PREFIX}-*` instead of `nwo-*`**: Currently the shared role allows any `nwo-*` resource across candidates; a per-repo OIDC trust subject (`repo:Deloitte-DT-Training/hu-devops-26-nov-<username>:ref:refs/heads/main`) paired with `${NAME_PREFIX}-*` IAM conditions would prevent cross-candidate blast radius.
2. **Separating Plan (read-only) vs Apply (write) roles**: PR workflows should assume a read-only plan role (`SecurityAudit` / `ReadOnly` + S3 state read + lock write), while only `main` deploys may assume the mutating apply role.
3. **Restricting `iam:PassRole` and KMS permissions**: Scope `iam:PassRole` strictly to the exact task/execution/scheduler role ARNs and forbid `kms:ScheduleKeyDeletion` in CI.
