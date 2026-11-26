# Runbook: Public Endpoint Down (`page-endpoint-down`)

## Trigger
- **GCP Uptime Check:** `nwo-<username>-dev-page-endpoint-down` (`https://<cloudfront_domain_name>/version` failed HTTP 200 / `"cloud"` match for 120s).
- **GitHub Actions Synthetic Probe:** `.github/workflows/synthetic-probe.yml` failed and opened an `incident` issue.

## First Action (Do This Within 2 Minutes)
1. **Run the synthetic probe directly** to see which cloud answered and exact HTTP status:
   ```bash
   python3 .github/scripts/probe.py https://<cloudfront_domain_name>
   ```

## Triage & Diagnosis
1. Check CloudFront KeyValueStore active weight (`aws cloudfront-keyvaluestore get-key --kvs-arn <kvs_arn> --key aws_weight`).
2. If AWS is active (`aws_weight = 100`): inspect AWS ECS running task count (`aws ecs describe-services`), ALB target health (`aws elbv2 describe-target-health`), and RDS status.
3. If GCP is active (`aws_weight = 0`): inspect Cloud Run API service status, revisions, and Cloud SQL instance state.

## Mitigation
- If one cloud is healthy while the active cloud is down, use **Cross-Cloud Traffic Switch** (`gh workflow run traffic-switch.yml -f aws_percentage=0` for GCP or `100` for AWS) after ensuring database readiness (T5 DR failover procedure).
- Complete [postmortem-template.md](../postmortem-template.md) within **60 minutes** of recovery.
