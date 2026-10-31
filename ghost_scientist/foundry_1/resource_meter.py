#!/usr/bin/env python3
"""Fail-closed child-process resource receipt component for Foundry-1."""

from __future__ import annotations

import hashlib
import resource
import subprocess
import time
from collections.abc import Sequence


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def run_metered(command: Sequence[str], timeout_seconds: float) -> dict[str, object]:
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    wall_start = time.monotonic_ns()
    timed_out = False
    try:
        result = subprocess.run(
            list(command),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
            timeout=timeout_seconds,
            env={},
        )
        returncode = result.returncode
        stdout, stderr = result.stdout, result.stderr
    except subprocess.TimeoutExpired as exc:
        timed_out = True
        returncode = None
        stdout = exc.stdout or b""
        stderr = exc.stderr or b""
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    return {
        "command_sha256": _sha("\0".join(command).encode()),
        "timeout_seconds": timeout_seconds,
        "timed_out": timed_out,
        "returncode": returncode,
        "wall_ns": time.monotonic_ns() - wall_start,
        "user_cpu_ns": int((after.ru_utime - before.ru_utime) * 1_000_000_000),
        "system_cpu_ns": int((after.ru_stime - before.ru_stime) * 1_000_000_000),
        "child_max_rss_kib": after.ru_maxrss,
        "stdout_sha256": _sha(stdout),
        "stderr_sha256": _sha(stderr),
        "stdout_bytes": len(stdout),
        "stderr_bytes": len(stderr),
    }


def selftest(python: str) -> dict[str, object]:
    success = run_metered(
        [python, "-c", "x=0\nfor i in range(200000): x=(x+i)%1000003\nprint(x)"],
        5.0,
    )
    failure = run_metered([python, "-c", "raise SystemExit(7)"], 5.0)
    timeout = run_metered([python, "-c", "import time; time.sleep(0.2)"], 0.02)
    gates = {
        "successful_child_charged": (
            success["returncode"] == 0
            and int(success["user_cpu_ns"]) + int(success["system_cpu_ns"]) > 0
        ),
        "failed_child_charged": failure["returncode"] == 7,
        "timeout_charged": timeout["timed_out"] is True and int(timeout["wall_ns"]) > 0,
        "output_bound_by_digest": all(
            len(str(item["stdout_sha256"])) == 64 and len(str(item["stderr_sha256"])) == 64
            for item in (success, failure, timeout)
        ),
    }
    return {
        "component": "FOUNDRY_RESOURCE_METER_V1",
        "gates": gates,
        "pass": all(gates.values()),
        "receipts": {"success": success, "failure": failure, "timeout": timeout},
        "limits": [
            "does not yet aggregate a process tree beyond direct children",
            "not yet integrated around compiler and every control arm",
            "peak RSS is cumulative RUSAGE_CHILDREN rather than per-child isolated RSS",
        ],
    }

