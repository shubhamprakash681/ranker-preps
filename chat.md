I have built Task 3 (GCP Platform, Cross-Cloud Edge & Instant Traffic Switch) and updated docs/architecture.md and SUBMISSION.md.

What I Wrote for Task 3

GCP Platform Module (terraform/modules/gcp-platform/) & gcp-dev (terraform/envs/gcp-dev/):

Shared Network: Read-only lookups of hu-devops-26-nov-vpc and hu-devops-26-nov-private-use4-1.
Cloud SQL PostgreSQL 16 (database.tf): db-f1-micro, explicit edition = "ENTERPRISE", ZONAL, 10 GB PD_SSD, private IP only (ipv4_enabled = false), ssl_mode = "ENCRYPTED_ONLY", automated backups + 7-day PITR, password stored in Secret Manager (<prefix>-dev-db-password).
Artifact Registry, GCS & Pub/Sub (storage.tf): Private GCS receipts bucket (public_access_prevention = "enforced", uniform access, versioned), Pub/Sub topic + subscription + dead-letter topic (max_delivery_attempts = 5) with resource-level IAM for the Pub/Sub service agent and GCP_RUNTIME_SERVICE_ACCOUNT (no service accounts created, no keys).
Cloud Run API & Worker (compute.tf): Both run as GCP_RUNTIME_SERVICE_ACCOUNT with direct VPC egress (PRIVATE_RANGES_ONLY).
API: 1 vCPU / 1 GiB, 0–3 instances, invoker_iam_disabled = true (org-policy compliant, no allUsers), /readyz startup probe and /healthz liveness probe.
Worker: 1 vCPU / 512 MiB, 1–2 instances, INGRESS_TRAFFIC_INTERNAL_ONLY, invoker_iam_disabled = false, cpu_idle = false so the Pub/Sub consumer loop runs continuously.

Cross-Cloud HTTPS Edge & Traffic Switch (terraform/modules/edge/ & terraform/envs/edge-dev/):

CloudFront + CloudFront Function (router.js) + KeyValueStore: Single public HTTPS hostname (cloudfront_default_certificate = true), Managed-CachingDisabled, Managed-AllViewerExceptHostHeader (preserves origin Host headers for ALB and *.run.app), supports all HTTP methods including POST, defaults to 100% AWS / 0% GCP.
No-Bypass Guard on AWS ALB: Added enable_edge_only = true in aws-dev/main.tf so the ALB rejects direct requests with 403 and only forwards requests carrying CloudFront's X-Origin-Verify header.
Instant Traffic Switch (< 60s, no Terraform): traffic_switch.sh and traffic-switch.yml.

Pipelines & Docs:

Added deploy-gcp.yml and deploy-edge.yml, and updated pr-checks.yml (plan-edge) and drift-detection.yml.
Added Cloud SQL zonal/PITR analysis, deliberate failover rationale, no-bypass exposure analysis, and AWS vs GCP comparison to docs/architecture.md and SUBMISSION.md (Decisions 7–8).
Step-by-Step Instructions on Your Other Device

Pull, Branch, Open PR & Check Plans

Create a branch (git checkout -b feat/t3-gcp-edge), push, and open a PR to main.
Verify PR Checks passes for aws-dev, gcp-dev, and edge-dev (including check_tags.py and Conftest).

Merge to main

Merging triggers Deploy AWS Platform (adds the X-Origin-Verify ALB rule) and Deploy GCP Platform (pushes image to Artifact Registry + creates Cloud SQL, Pub/Sub, GCS, Secret Manager, Cloud Run API & Worker; Cloud SQL takes ~5–8 min on first apply).
Once both finish, Deploy Cross-Cloud Edge automatically runs and provisions CloudFront + KeyValueStore. (If you want to run it manually anytime, trigger Actions → Deploy Cross-Cloud Edge → Run workflow.)
Note the cloudfront_domain_name output at the end of Deploy Cross-Cloud Edge.

Verify Normal State (100% AWS / 0% GCP), No-Bypass & Web UI

bash
HOST="https://<cloudfront_domain_name>"
curl -s "$HOST/version"        # should return {"cloud":"aws", ...}
curl -i "http://<alb_dns_name>/version"   # should return HTTP 403 (ALB bypass blocked)
Open https://<cloudfront_domain_name>/ in your browser and confirm the UI loads and its badge shows aws.

Test the Traffic Switch (100/0 → 0/100 → 100/0 within 60s)

Switch 100% to GCP (no Terraform, no redeploy):
bash
gh workflow run traffic-switch.yml -f aws_percentage=0
(Or trigger Actions → Cross-Cloud Traffic Switch → Run workflow with aws_percentage = 0.)
Within ~5–15 seconds, verify GCP serves GET and POST:
bash
curl -s "$HOST/version"        # should return {"cloud":"gcp", ...}
curl -s -X POST "$HOST/orders" \
  -H 'content-type: application/json' \
  -d '{"customer_id":"c-gcp-1","amount_cents":2500,"currency":"USD"}'
Confirm the order becomes PROCESSED (GET $HOST/orders/<id>) and a receipt appears in your GCS bucket nwo-<username>-dev-receipts-<project_id>.
Switch traffic back to 100% AWS (aws_percentage = 100) and record the outputs/screenshots in SUBMISSION.md.

Let me know once T3 is deployed and tested (or if any CI step hits an issue), and we'll move on to Task 4 (Observability & SRE)!