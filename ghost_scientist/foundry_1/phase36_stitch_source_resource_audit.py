#!/usr/bin/env python3
"""Meter the source-faithful Stitch build and conformance execution."""

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
        [str(python), str(HERE / "phase35_stitch_source_control.py")],
        cwd=HERE,
        wall_limit_seconds=60,
        cpu_limit_seconds=45,
        rss_limit_kib=1_000_000,
        environment={
            "HOME": str(pathlib.Path.home()),
            "CARGO_HOME": "/tmp/foundry-stitch-cargo-home",
            "RUSTUP_HOME": str(pathlib.Path.home() / ".rustup"),
            "PATH": f"{pathlib.Path.home() / '.cargo/bin'}:/usr/bin:/bin",
        },
    )
    result = json.loads(
        (RESULTS / "phase35_stitch_source_control.json").read_text(
            encoding="utf-8"
        )
    )
    receipt_ok = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and receipt["observed_process_count"] >= 2
        and "FOUNDRY_PHASE35_STITCH_SOURCE" in receipt["stdout_text"]
    )
    conformance = (
        result["status"] == "STITCH_SOURCE_CONTROL_CONFORMANCE_PASS"
        and result["source_records_exact"]
        and result["upstream_algorithm_source_executed"]
        and result["conformance_passed"]
    )
    passed = meter_test["pass"] and receipt_ok and conformance
    payload = {
        "version": "FOUNDRY_STITCH_SOURCE_RESOURCE_AUDIT_V1",
        "status": (
            "STITCH_SOURCE_CONTROL_RESOURCE_PASS"
            if passed
            else "STITCH_SOURCE_CONTROL_RESOURCE_FAIL"
        ),
        "meter_selftest": meter_test,
        "receipt": receipt,
        "receipt_complete": receipt_ok,
        "source_conformance_passed": conformance,
        "P1": {
            "source_faithful_controls_reproduced": 1 if conformance else 0,
            "official_binary_controls_reproduced": 0,
            "controls_required": 4,
            "complete": False,
        },
        "P3": {
            "stitch_source_control_arm_integrated": receipt_ok,
            "external_controls_integrated": conformance,
            "complete": False,
        },
    }
    (RESULTS / "phase36_stitch_source_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE36_STITCH_SOURCE_RESOURCE"
        f" status={payload['status']}"
        f" conformance_passed={str(conformance).lower()}"
        f" processes={receipt['observed_process_count']}"
    )


if __name__ == "__main__":
    run()
