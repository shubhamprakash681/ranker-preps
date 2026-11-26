#!/usr/bin/env python3
"""Synthetic probe against the public Northwind Orders HTTPS hostname.

Checks GET /version (reports which cloud answered) and GET /readyz.
Exits non-zero (fails visibly) when either endpoint is unhealthy or unreachable.

Usage:
    python3 probe.py https://<cloudfront_domain_name>
"""
import json
import sys
import time
import urllib.error
import urllib.request


def fetch_json(url: str, timeout: float = 10.0) -> tuple[int, dict, float]:
    start = time.perf_counter()
    req = urllib.request.Request(url, headers={"User-Agent": "northwind-synthetic-probe/1.0"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            elapsed_ms = round((time.perf_counter() - start) * 1000, 1)
            body = json.loads(resp.read().decode("utf-8"))
            return resp.status, body, elapsed_ms
    except urllib.error.HTTPError as exc:
        elapsed_ms = round((time.perf_counter() - start) * 1000, 1)
        raw = exc.read().decode("utf-8", errors="replace")
        try:
            body = json.loads(raw)
        except json.JSONDecodeError:
            body = {"raw": raw}
        return exc.code, body, elapsed_ms


def main() -> int:
    if len(sys.argv) != 2:
        print("Usage: probe.py <base_url>", file=sys.stderr)
        return 2

    base = sys.argv[1].rstrip("/")
    try:
        v_status, v_body, v_ms = fetch_json(f"{base}/version")
        r_status, r_body, r_ms = fetch_json(f"{base}/readyz")
    except Exception as exc:  # noqa: BLE001
        print(f"PROBE FAILED: {base} unreachable ({exc})", file=sys.stderr)
        return 1

    cloud = v_body.get("cloud", "unknown")
    trace_note = f"version_ms={v_ms} readyz_ms={r_ms}"
    print(f"probe target={base} cloud={cloud} version_status={v_status} readyz_status={r_status} {trace_note}")

    if v_status != 200 or cloud not in ("aws", "gcp"):
        print(f"PROBE FAILED: /version returned status={v_status} body={v_body}", file=sys.stderr)
        return 1
    if r_status != 200 or r_body.get("status") != "ready":
        print(f"PROBE FAILED: /readyz returned status={r_status} body={r_body}", file=sys.stderr)
        return 1

    print(f"PROBE OK: active cloud is {cloud!r}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
