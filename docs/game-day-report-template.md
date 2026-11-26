# Game-Day Report (AWS Region Loss Simulation)

- **Date / Time (UTC):** `[YYYY-MM-DD HH:MM UTC]`
- **Trigger:** `[Simulated AWS us-east-1 loss by evaluators]`
- **Failover Workflow Run URL:** `[PLACEHOLDER: link to failover.yml run]`

## Measured Recovery Metrics
| Metric | Target | Measured | Pass? |
|---|---|---|---|
| **Time to Detect (TTD)** | < 5 min | `[XXs / X min]` | `[Yes/No]` |
| **Time to Decide** | < 5 min | `[XXs / X min]` | `[Yes/No]` |
| **Time to Recover (RTO)** | ≤ 30 min (1800s) | `[XXs / X min]` | `[Yes/No]` |
| **Data Lost (RPO)** | ≤ 15 min (900s) | `[XXs / X min (X orders)]` | `[Yes/No]` |

## Post-Failover End-to-End Verification
- `curl -s https://<cloudfront_domain_name>/version` → `[paste output showing "cloud":"gcp"]`
- `POST /orders` after failover → `[order_id, status: PROCESSED, GCS receipt verified]`
- Scheduled restore overwrite test → `[verified dr_state.promoted=true skipped overwrite]`

## What Surprised Us & Lessons Learned
1. `[What behaved differently than expected during the game day]`
2. `[Concrete follow-up improvement]`
