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
