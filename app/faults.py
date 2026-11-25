"""Fault injection for the observability / SRE exercise.

Switches are stored in the `fault_flags` table so every replica and the worker see them.
They are read through a 2-second cache to avoid adding a query per request.
Nothing here is documented in the candidate paper on purpose: finding out *why* the service is
unhealthy from telemetry is part of the exercise.
"""
import hashlib
import hmac
import math
import random
import threading
import time

from sqlalchemy import select

from .db import FaultFlag, session_scope

# SHA-256 of the access token for these switches (the token itself is not in this repository).
FAULT_TOKEN_SHA256 = "fb4e3f9e487f947df8653c4d505878a26c1a76786d1e58c49255b5b3dda58ada"

KNOWN = {
    "db_latency_ms": float,   # sleep before every DB-backed request
    "error_rate": float,      # 0..1 fraction of POST /orders answered with 503
    "memory_leak_kb": float,  # kilobytes retained per request (never released)
    "cpu_burn_ms": float,     # busy-loop per request
    "poison_messages": float, # 1 = the worker fails every message it receives
}

_cache: dict[str, float] = {}
_cache_at = 0.0
_lock = threading.Lock()
_leak: list[bytearray] = []


def token_ok(candidate: str | None) -> bool:
    if not candidate:
        return False
    digest = hashlib.sha256(candidate.encode()).hexdigest()
    return hmac.compare_digest(digest, FAULT_TOKEN_SHA256)


def _load() -> dict[str, float]:
    global _cache, _cache_at
    now = time.monotonic()
    with _lock:
        if now - _cache_at < 2.0:
            return _cache
    try:
        with session_scope() as s:
            rows = s.execute(select(FaultFlag)).scalars().all()
        data = {r.name: float(r.value) for r in rows if r.name in KNOWN}
    except Exception:  # never let the fault layer take the service down
        data = _cache
    with _lock:
        _cache, _cache_at = data, now
    return data


def get(name: str) -> float:
    return _load().get(name, 0.0)


def all_flags() -> dict[str, float]:
    return {k: _load().get(k, 0.0) for k in KNOWN}


def set_flags(values: dict[str, float]) -> dict[str, float]:
    global _cache_at
    with session_scope() as s:
        for name, value in values.items():
            if name not in KNOWN:
                raise KeyError(name)
            row = s.get(FaultFlag, name)
            if row is None:
                s.add(FaultFlag(name=name, value=str(float(value))))
            else:
                row.value = str(float(value))
        s.commit()
    with _lock:
        _cache_at = 0.0  # force reload
    return all_flags()


def clear_all() -> None:
    global _cache_at
    with session_scope() as s:
        s.query(FaultFlag).delete()
        s.commit()
    _leak.clear()
    with _lock:
        _cache_at = 0.0


def apply_request_faults_read() -> None:
    """Read endpoints get slowness, CPU burn and leaks, but never injected errors."""
    apply_request_faults(allow_errors=False)


def apply_request_faults(allow_errors: bool = True) -> None:
    """Called once per request on the data path. Returns normally or raises RuntimeError for 503."""
    latency = get("db_latency_ms")
    if latency > 0:
        time.sleep(latency / 1000.0)
    burn = get("cpu_burn_ms")
    if burn > 0:
        end = time.perf_counter() + burn / 1000.0
        x = 0.0
        while time.perf_counter() < end:
            x += math.sqrt(random.random())
    leak = get("memory_leak_kb")
    if leak > 0:
        _leak.append(bytearray(int(leak * 1024)))
    rate = get("error_rate")
    if allow_errors and rate > 0 and random.random() < rate:
        raise RuntimeError("injected failure")
