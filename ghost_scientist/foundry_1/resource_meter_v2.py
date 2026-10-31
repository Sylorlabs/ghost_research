#!/usr/bin/env python3
"""Linux process-group meter with CPU, wall, RSS, failure, and timeout receipts."""

from __future__ import annotations

import hashlib
import os
import pathlib
import resource
import signal
import subprocess
import tempfile
import time
from collections.abc import Mapping, Sequence


def _sha(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def _group_snapshot(pgid: int) -> tuple[set[int], int, int]:
    pids: set[int] = set()
    rss_kib = 0
    cpu_ticks = 0
    for entry in pathlib.Path("/proc").iterdir():
        if not entry.name.isdigit():
            continue
        try:
            stat = (entry / "stat").read_text(encoding="utf-8").split()
            if int(stat[4]) != pgid:
                continue
            pids.add(int(entry.name))
            cpu_ticks += int(stat[13]) + int(stat[14])
            for line in (entry / "status").read_text(encoding="utf-8").splitlines():
                if line.startswith("VmRSS:"):
                    rss_kib += int(line.split()[1])
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError, ValueError):
            continue
    return pids, rss_kib, cpu_ticks


def run_metered_tree(
    command: Sequence[str],
    *,
    cwd: pathlib.Path,
    wall_limit_seconds: float,
    cpu_limit_seconds: float,
    rss_limit_kib: int,
    environment: Mapping[str, str] | None = None,
) -> dict[str, object]:
    if not command or not pathlib.Path(command[0]).is_absolute():
        raise ValueError("metered command executable must be absolute")
    if min(wall_limit_seconds, cpu_limit_seconds) <= 0 or rss_limit_kib <= 0:
        raise ValueError("resource limits must be positive")
    env = {
        "PATH": "/usr/bin:/bin",
        "PYTHONHASHSEED": "0",
        "PYTHONDONTWRITEBYTECODE": "1",
        **dict(environment or {}),
    }
    before = resource.getrusage(resource.RUSAGE_CHILDREN)
    started = time.monotonic_ns()
    observed: set[int] = set()
    peak_rss = 0
    peak_ticks = 0
    termination = "natural"
    with tempfile.TemporaryFile() as stdout_file, tempfile.TemporaryFile() as stderr_file:
        process = subprocess.Popen(
            list(command),
            cwd=cwd,
            stdin=subprocess.DEVNULL,
            stdout=stdout_file,
            stderr=stderr_file,
            env=env,
            start_new_session=True,
        )
        pgid = process.pid
        clock_ticks = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
        while process.poll() is None:
            pids, rss, ticks = _group_snapshot(pgid)
            observed.update(pids)
            peak_rss = max(peak_rss, rss)
            peak_ticks = max(peak_ticks, ticks)
            elapsed = (time.monotonic_ns() - started) / 1_000_000_000
            if elapsed > wall_limit_seconds:
                termination = "wall_limit"
            elif ticks / clock_ticks > cpu_limit_seconds:
                termination = "cpu_limit"
            elif rss > rss_limit_kib:
                termination = "rss_limit"
            if termination != "natural":
                os.killpg(pgid, signal.SIGKILL)
                break
            time.sleep(0.005)
        returncode = process.wait()
        pids, rss, ticks = _group_snapshot(pgid)
        observed.update(pids)
        peak_rss = max(peak_rss, rss)
        peak_ticks = max(peak_ticks, ticks)
        stdout_file.seek(0)
        stderr_file.seek(0)
        stdout = stdout_file.read()
        stderr = stderr_file.read()
    after = resource.getrusage(resource.RUSAGE_CHILDREN)
    try:
        os.killpg(pgid, 0)
        group_reaped = False
    except ProcessLookupError:
        group_reaped = True
    return {
        "version": "FOUNDRY_RESOURCE_RECEIPT_V2",
        "command_sha256": _sha("\0".join(command).encode()),
        "cwd_sha256": _sha(str(cwd.resolve()).encode()),
        "returncode": returncode,
        "termination": termination,
        "wall_ns": time.monotonic_ns() - started,
        "rusage_user_cpu_ns": int((after.ru_utime - before.ru_utime) * 1_000_000_000),
        "rusage_system_cpu_ns": int((after.ru_stime - before.ru_stime) * 1_000_000_000),
        "sampled_group_cpu_ticks": peak_ticks,
        "clock_ticks_per_second": clock_ticks,
        "peak_group_rss_kib": peak_rss,
        "observed_process_count": len(observed),
        "process_group_reaped": group_reaped,
        "limits": {
            "wall_seconds": wall_limit_seconds,
            "cpu_seconds": cpu_limit_seconds,
            "rss_kib": rss_limit_kib,
        },
        "stdout_sha256": _sha(stdout),
        "stderr_sha256": _sha(stderr),
        "stdout_bytes": len(stdout),
        "stderr_bytes": len(stderr),
        "stdout_text": stdout.decode("utf-8", "replace")[:4096],
        "stderr_text": stderr.decode("utf-8", "replace")[:4096],
    }


def selftest(python: str, cwd: pathlib.Path) -> dict[str, object]:
    nested_code = (
        "import subprocess,sys;"
        "subprocess.run([sys.executable,'-c',"
        "'x=0\\nfor i in range(800000): x=(x+i)%1000003\\nprint(x)'],check=True)"
    )
    nested = run_metered_tree(
        [python, "-c", nested_code],
        cwd=cwd,
        wall_limit_seconds=10,
        cpu_limit_seconds=5,
        rss_limit_kib=512_000,
    )
    failure = run_metered_tree(
        [python, "-c", "raise SystemExit(7)"],
        cwd=cwd,
        wall_limit_seconds=5,
        cpu_limit_seconds=2,
        rss_limit_kib=256_000,
    )
    timeout_code = (
        "import subprocess,sys,time;"
        "subprocess.Popen([sys.executable,'-c','import time;time.sleep(5)']);"
        "time.sleep(5)"
    )
    timeout = run_metered_tree(
        [python, "-c", timeout_code],
        cwd=cwd,
        wall_limit_seconds=0.05,
        cpu_limit_seconds=2,
        rss_limit_kib=256_000,
    )
    gates = {
        "nested_descendant_observed": nested["observed_process_count"] >= 2,
        "nested_cpu_charged": (
            nested["rusage_user_cpu_ns"] + nested["rusage_system_cpu_ns"] > 0
        ),
        "failed_process_charged": failure["returncode"] == 7,
        "timeout_tree_killed": (
            timeout["termination"] == "wall_limit"
            and timeout["process_group_reaped"] is True
            and timeout["observed_process_count"] >= 2
        ),
        "rss_sampled": nested["peak_group_rss_kib"] > 0,
        "all_groups_reaped": all(
            item["process_group_reaped"] for item in (nested, failure, timeout)
        ),
    }
    return {
        "version": "FOUNDRY_RESOURCE_METER_SELFTEST_V2",
        "pass": all(gates.values()),
        "gates": gates,
        "receipts": {"nested": nested, "failure": failure, "timeout": timeout},
        "boundary": [
            "processes that deliberately create a new session could escape the process group",
            "candidate containment must deny setsid and process creation where not required",
            "cgroup v2 is present but not writable in the current environment",
        ],
    }

