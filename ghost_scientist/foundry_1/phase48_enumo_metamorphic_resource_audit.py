#!/usr/bin/env python3
"""Meter the pre-frozen Enumo metamorphic process tree."""

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
        [str(python), str(HERE / "phase47_enumo_metamorphic_control.py")],
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
        (RESULTS / "phase47_enumo_metamorphic_control.json").read_text(
            encoding="utf-8"
        )
    )
    receipt_ok = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and receipt["observed_process_count"] >= 6
        and "FOUNDRY_PHASE47_ENUMO_METAMORPHIC" in receipt["stdout_text"]
    )
    relation = (
        result["status"] == "ENUMO_METAMORPHIC_CONTROL_PASS"
        and result["metamorphic_relation_passed"]
        and all(result["checks"].values())
    )
    passed = meter_test["pass"] and receipt_ok and relation
    payload = {
        "version": "FOUNDRY_ENUMO_METAMORPHIC_RESOURCE_AUDIT_V1",
        "status": (
            "ENUMO_METAMORPHIC_RESOURCE_PASS"
            if passed
            else "ENUMO_METAMORPHIC_RESOURCE_FAIL"
        ),
        "meter_selftest": meter_test,
        "receipt": receipt,
        "receipt_complete": receipt_ok,
        "metamorphic_relation_passed": relation,
    }
    (RESULTS / "phase48_enumo_metamorphic_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE48_ENUMO_METAMORPHIC_RESOURCE"
        f" status={payload['status']}"
        f" processes={receipt['observed_process_count']}"
    )


if __name__ == "__main__":
    run()
