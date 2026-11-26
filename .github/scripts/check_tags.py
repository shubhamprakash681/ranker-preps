#!/usr/bin/env python3
"""Validate Terraform plan JSON for mandatory username tags/labels and security baselines.

Usage:
    python3 check_tags.py <plan.json> <expected_username>
"""
import json
import sys


def check_plan(plan_path: str, expected_username: str) -> list[str]:
    with open(plan_path, "r", encoding="utf-8") as f:
        plan = json.load(f)

    errors: list[str] = []
    expected = expected_username.strip().lower()
    if not expected:
        return ["Expected username is empty"]

    for rc in plan.get("resource_changes", []):
        actions = rc.get("change", {}).get("actions", [])
        if not any(a in ("create", "update") for a in actions):
            continue

        addr = rc.get("address", "<unknown>")
        rtype = rc.get("type", "")
        after = rc.get("change", {}).get("after") or {}
        after_unknown = rc.get("change", {}).get("after_unknown") or {}

        # 1. AWS taggable resource check
        if rtype.startswith("aws_"):
            has_tags_schema = (
                "tags_all" in after
                or "tags" in after
                or "tags_all" in after_unknown
                or "tags" in after_unknown
            )
            if has_tags_schema:
                tags_all = after.get("tags_all") or {}
                tags = after.get("tags") or {}
                actual = tags_all.get("username") or tags.get("username")
                if actual != expected:
                    errors.append(
                        f"[TAG] {addr} ({rtype}) missing or mismatched tag "
                        f"username={expected!r} (got {actual!r})"
                    )

            # Security baseline checks
            if rtype == "aws_db_instance" and after.get("publicly_accessible") is True:
                errors.append(f"[SEC] {addr} RDS instance must not be publicly_accessible")

            if rtype in ("aws_security_group_rule", "aws_vpc_security_group_ingress_rule"):
                cidr = after.get("cidr_ipv4") or ""
                cidrs = after.get("cidr_blocks") or []
                is_open = cidr == "0.0.0.0/0" or "0.0.0.0/0" in cidrs
                from_port = after.get("from_port")
                to_port = after.get("to_port")
                is_alb_port = from_port in (80, 443) and to_port in (80, 443)
                is_ingress = (
                    rtype == "aws_vpc_security_group_ingress_rule"
                    or after.get("type") == "ingress"
                )
                if is_ingress and is_open and not is_alb_port:
                    errors.append(
                        f"[SEC] {addr} opens 0.0.0.0/0 on ports {from_port}-{to_port} "
                        "(only HTTP/HTTPS 80/443 to ALB is permitted)"
                    )

        # 2. GCP labellable resource check
        if rtype.startswith("google_"):
            if rtype == "google_sql_database_instance":
                settings = (after.get("settings") or [{}])[0]
                user_labels = settings.get("user_labels") or {}
                actual = user_labels.get("username")
                if actual != expected:
                    errors.append(
                        f"[LABEL] {addr} ({rtype}) missing or mismatched user_labels.username="
                        f"{expected!r} (got {actual!r})"
                    )
                ip_cfg = (settings.get("ip_configuration") or [{}])[0]
                if ip_cfg.get("ipv4_enabled") is True:
                    errors.append(f"[SEC] {addr} Cloud SQL must not have public ipv4_enabled=true")
            elif rtype in (
                "google_monitoring_notification_channel",
                "google_monitoring_alert_policy",
                "google_monitoring_custom_service",
                "google_monitoring_uptime_check_config",
            ):
                user_labels = after.get("user_labels") or {}
                actual = user_labels.get("username")
                if actual != expected:
                    errors.append(
                        f"[LABEL] {addr} ({rtype}) missing or mismatched user_labels.username="
                        f"{expected!r} (got {actual!r})"
                    )
            else:
                has_labels_schema = (
                    "terraform_labels" in after
                    or "labels" in after
                    or "terraform_labels" in after_unknown
                    or "labels" in after_unknown
                )
                if has_labels_schema:
                    tf_labels = after.get("terraform_labels") or {}
                    labels = after.get("labels") or {}
                    actual = tf_labels.get("username") or labels.get("username")
                    if actual != expected:
                        errors.append(
                            f"[LABEL] {addr} ({rtype}) missing or mismatched label "
                            f"username={expected!r} (got {actual!r})"
                        )

            if "iam" in rtype and after.get("member") == "allUsers":
                errors.append(f"[SEC] {addr} must never grant IAM to allUsers")
            if "iam" in rtype and "allUsers" in (after.get("members") or []):
                errors.append(f"[SEC] {addr} must never grant IAM to allUsers")

    return errors


def main() -> int:
    if len(sys.argv) != 3:
        print("Usage: check_tags.py <plan.json> <expected_username>", file=sys.stderr)
        return 2

    plan_path, expected_username = sys.argv[1], sys.argv[2]
    errors = check_plan(plan_path, expected_username)
    if errors:
        print("Policy & tag check FAILED:", file=sys.stderr)
        for err in errors:
            print(f"  - {err}", file=sys.stderr)
        return 1

    print(f"Policy & tag check PASSED for username={expected_username!r}.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
