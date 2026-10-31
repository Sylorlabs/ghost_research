#!/usr/bin/env python3
"""Meter the post-hoc Enumo proving-power diagnostic."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULTS = HERE / "results"


def run() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    receipt = run_metered_tree(
        [str(python), str(HERE / "phase49_enumo_power_diagnostic.py")],
        cwd=HERE,
        wall_limit_seconds=150,
        cpu_limit_seconds=120,
        rss_limit_kib=2_000_000,
        environment={
            "HOME": str(pathlib.Path.home()),
            "CARGO_HOME": "/tmp/foundry-enumo-cargo",
            "RUSTUP_HOME": str(pathlib.Path.home() / ".rustup"),
            "PATH": f"{pathlib.Path.home() / '.cargo/bin'}:/usr/bin:/bin",
        },
    )
    result = json.loads(
        (RESULTS / "phase49_enumo_power_diagnostic.json").read_text(
            encoding="utf-8"
        )
    )
    receipt_ok = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and receipt["observed_process_count"] >= 6
        and "FOUNDRY_PHASE49_ENUMO_POWER" in receipt["stdout_text"]
    )
    completed = (
        result["status"]
        in {
            "ENUMO_BOUNDED_PROVING_POWER_EQUIVALENT",
            "ENUMO_BOUNDED_PROVING_POWER_DIVERGED",
        }
        and result["source_records_exact"]
    )
    passed = meter_test["pass"] and receipt_ok and completed
    payload = {
        "version": "FOUNDRY_ENUMO_POWER_RESOURCE_AUDIT_V1",
        "status": (
            "ENUMO_POWER_DIAGNOSTIC_RESOURCE_PASS"
            if passed
            else "ENUMO_POWER_DIAGNOSTIC_RESOURCE_FAIL"
        ),
        "meter_selftest": meter_test,
        "receipt": receipt,
        "receipt_complete": receipt_ok,
        "diagnostic_completed": completed,
        "diagnostic_outcome": result["status"],
    }
    (RESULTS / "phase50_enumo_power_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE50_ENUMO_POWER_RESOURCE"
        f" status={payload['status']}"
        f" outcome={payload['diagnostic_outcome']}"
        f" processes={receipt['observed_process_count']}"
    )


if __name__ == "__main__":
    run()
