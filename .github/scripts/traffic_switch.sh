#!/usr/bin/env bash
set -euo pipefail

# Instant cross-cloud traffic switch via CloudFront KeyValueStore (no Terraform, < 60s global propagation).
# Usage: ./traffic_switch.sh <kvs_arn> <aws_percentage: 0..100>

if [ "$#" -ne 2 ]; then
  echo "Usage: $0 <kvs_arn> <aws_percentage: 0..100>" >&2
  exit 2
fi

KVS_ARN="$1"
AWS_PCT="$2"

if ! [[ "$AWS_PCT" =~ ^[0-9]+$ ]] || [ "$AWS_PCT" -lt 0 ] || [ "$AWS_PCT" -gt 100 ]; then
  echo "ERROR: aws_percentage must be an integer between 0 and 100 (got '$AWS_PCT')." >&2
  exit 2
fi

GCP_PCT=$((100 - AWS_PCT))
ETAG=$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn "$KVS_ARN" --query 'ETag' --output text)

aws cloudfront-keyvaluestore put-key \
  --kvs-arn "$KVS_ARN" \
  --if-match "$ETAG" \
  --key "aws_weight" \
  --value "$AWS_PCT" >/dev/null

echo "Updated CloudFront KeyValueStore: AWS=${AWS_PCT}% / GCP=${GCP_PCT}%"
