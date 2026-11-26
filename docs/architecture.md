# AWS Platform Sizing, Cost & Security Notes (Task 1)

## 1. Sizing Within Approved Ceilings (`dev`)
| Component | Approved Ceiling | Configured (`dev`) | Rationale |
|---|---|---|---|
| RDS PostgreSQL 16 | `db.t4g.micro`, Multi-AZ, 20 GB gp3 (autoscale ≤ 50 GB) | `db.t4g.micro`, Multi-AZ, 20 GB gp3 (max 50 GB) | Multi-AZ is mandatory for HA failover; `db.t4g.micro` is the smallest burstable ARM instance. |
| ECS Fargate API | ≤ 0.5 vCPU / 1 GB, ≤ 4 tasks | `0.25 vCPU / 0.5 GB` (`256/512`), min `2`, max `4` | Half the per-task ceiling cuts idle compute cost by 50% while `min = 2` spans both AZs (`us-east-1a`, `us-east-1b`) for zero-downtime HA. |
| ECS Fargate Worker | ≤ 0.25 vCPU / 0.5 GB, ≤ 2 tasks | `0.25 vCPU / 0.5 GB` (`256/512`), min `1`, max `2` | Matches ceiling; scales to `2` under load. |
| Log Retention | ≤ 30 days | `14` days | Balances 2-week troubleshooting window with CloudWatch storage cost. |

*(For a `prod` environment, API would scale to `0.5 vCPU / 1 GB` (`512/1024`) with `min = 2, max = 4`, `log_retention_days = 30`, and `skip_final_snapshot = false`.)*

## 2. Estimated Monthly Idle Cost (`us-east-1`, `dev`)
- **RDS `db.t4g.micro` Multi-AZ + 20 GB gp3**: ~\$25–30/month
- **ALB (1x)**: ~\$16.20/month (plus minimal LCU)
- **ECS Fargate API (`2 × 0.25 vCPU / 0.5 GB`) + Worker (`1 × 0.25 vCPU / 0.5 GB`)**: ~\$28/month
- **KMS (1 CMK) + Secrets Manager (1 secret) + S3/SQS/ECR/CloudWatch**: ~\$2–4/month
- **Total estimated idle cost**: **~\$72–78/month** (well within the shared \$150/month AWS budget alert guardrail; destroy or scale down when idle if needed).

## 3. Shared NAT Gateway & Missing VPC Endpoints (Cost & Risk)
- **Constraint:** The shared VPC provides a single shared NAT Gateway and forbids per-candidate VPC endpoints (`s3`, `sqs`, `ecr`, `secretsmanager`, `logs`).
- **Cost impact:** All private-subnet traffic to ECR (image pulls), S3, SQS, Secrets Manager, and CloudWatch Logs traverses the NAT Gateway (incurring \$0.045/GB data processing charges on the shared account).
- **Risk:** The single shared NAT Gateway is a single-AZ dependency / shared noisy-neighbor bottleneck; losing that AZ or exhausting NAT port/bandwidth limits affects outbound AWS API calls from private ECS tasks until resolved.

## 4. IAM Least-Privilege & Wildcard Resource Justification
- **Zero wildcard actions (`*`):** Every IAM statement lists explicit API actions.
- **Single wildcard resource (`Resource: "*"`):** Used solely for `ecr:GetAuthorizationToken` in `<prefix>-<env>-task-execution` because AWS ECR authorization tokens are account/region-scoped and the IAM API rejects resource-level ARN restrictions on this action. All ECR pulls, CloudWatch log writes, Secrets Manager reads, SQS actions, S3 object calls, and KMS operations are scoped to exact named resource ARNs.

## 5. High Availability & Safer Deployments
- **Dual-signal API autoscaling:** Target tracking on `ECSServiceAverageCPUUtilization` (70%) and `ALBRequestCountPerTarget` (100 req/target/min).
- **Deployment circuit breaker:** Both API and Worker services enable `deployment_circuit_breaker { enable = true, rollback = true }` plus `wait_for_steady_state = true` and ALB `/readyz` health checks.

---

# GCP Platform & Cross-Cloud Edge (Task 3)

## 6. Cloud SQL Zonal & PITR Analysis
- **Configuration:** `db-f1-micro`, `edition = "ENTERPRISE"` (explicitly required because the shared project defaults to Enterprise Plus which rejects `db-f1-micro`), `availability_type = "ZONAL"`, `10 GB PD_SSD`, automated backups + **7-day Point-in-Time Recovery (PITR)** enabled.
- **Cost & Risk Tradeoff:** `db-f1-micro` cannot be made `REGIONAL` (HA). Enabling Cloud SQL HA would require upgrading to at least a shared/dedicated-core tier supporting HA (e.g., `db-custom-1-3840` `REGIONAL`, ~\$85–110+/month vs ~\$10–12/month for zonal `db-f1-micro`). Because GCP acts as the **warm standby** receiving `0%` of normal traffic and is promoted only during AWS regional failover (RTO 30 min) followed by an automated restore from the latest immutable backup, accepting single-zone database risk in `us-east4` saves ~\$75–100/month while staying within the shared \$150/month GCP budget guardrail.

## 7. Behaviour When One Cloud Fails (Deliberate Switch vs Automatic Failover)
- **Design Choice:** **Deliberate, operator-triggered traffic switch** (`traffic-switch.yml` / `failover.yml`) rather than automatic CloudFront origin-group failover on HTTP 5xx.
- **Why:**
  1. **Stateful split-brain risk:** AWS RDS PostgreSQL and GCP Cloud SQL PostgreSQL are separate databases across two clouds (no synchronous cross-cloud replication). If CloudFront automatically routed a subset of `POST /orders` to GCP during a transient AWS blip, orders would split across two independent databases and diverge!
  2. **RPO/Data-first ordering:** Our failover target (T5) requires restoring the latest immutable backup into Cloud SQL **first** before shifting traffic (`data first, then traffic`). Automatic edge failover would send writes to an empty/stale standby database.
  3. **Cost of each option:** Automatic origin failover is slightly faster (~10–30s) for purely stateless reads, but risks silent split-brain writes on `POST /orders`; a deliberate switch via CloudFront KeyValueStore takes `< 5s` once triggered after database readiness is confirmed.

## 8. No-Bypass Analysis (AWS vs GCP)
- **AWS ALB Protection:** `aws_lb_listener.http` defaults to `403 Forbidden` and forwards traffic **only** when the `X-Origin-Verify` header matches the `random_password.origin_verify` secret injected exclusively by CloudFront (`aws-origin`). Direct calls to `http://<alb_dns_name>/` are rejected with `403`.
- **What Remains Exposed on GCP & Why:** The Cloud Run API URL (`*.run.app`) remains directly reachable over HTTPS because the GCP organisation policy forbids `allUsers` IAM bindings, so `invoker_iam_disabled = true` + `INGRESS_TRAFFIC_ALL` are required for AWS CloudFront to invoke Cloud Run externally. Unlike ALB listener rules, Cloud Run itself does not inspect custom origin-verify headers before executing the container; fully blocking direct `*.run.app` access would require adding an external GCP Application Load Balancer + Cloud Armor in front of Cloud Run (or checking `X-Origin-Verify` inside the application, which we avoid to keep the starter app a black box). The GCP Worker (`INGRESS_TRAFFIC_INTERNAL_ONLY`, `invoker_iam_disabled = false`) and Cloud SQL (`ipv4_enabled = false`, private IP only) remain completely unreachable from the internet.

## 9. AWS vs GCP Design Comparison (3 Biggest Differences)
1. **Public Access & Org Policies (`invoker_iam_disabled` vs ALB + Security Groups):** AWS allows a public ALB in public subnets chained to private ECS tasks via security groups, with `X-Origin-Verify` header filtering. GCP forbids `allUsers` IAM bindings by org policy and routes Cloud Run without user-managed load balancers, requiring `invoker_iam_disabled = true` on the API service only while locking down the Worker with `INGRESS_TRAFFIC_INTERNAL_ONLY`.
2. **Background Worker Hosting (`ECS Fargate` vs `Cloud Run cpu_idle = false`):** AWS ECS Fargate runs `python -m app.worker` natively as a continuous headless container with no HTTP listener. Cloud Run requires an HTTP listener on `$PORT` (already built into `app/worker.py`) AND `cpu_idle = false` + `min_instance_count = 1` so Cloud Run allocates CPU continuously to pull Pub/Sub messages even when no HTTP requests arrive.
3. **Database & Private Networking (`Multi-AZ RDS` vs `Zonal Cloud SQL + Private Services Access`):** AWS uses two explicit data subnets + DB subnet group + security group ingress rules. GCP uses pre-built VPC peering (`hu-devops-26-nov-psa`) without data subnets and defaults new instances to Enterprise Plus (rejecting `db-f1-micro` unless `edition = "ENTERPRISE"` is explicitly specified).

