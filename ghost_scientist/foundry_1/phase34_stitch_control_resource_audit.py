#!/usr/bin/env python3
"""Meter the frozen Stitch conformance execution, including infrastructure failure."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULTS = HERE / "results"


def run() -> None:
    protocol = json.loads(
        (HERE / "CONTROL_EXECUTION_PROTOCOL_V1.json").read_text(
            encoding="utf-8"
        )
    )
    limits = protocol["resource_limits"]
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    receipt = run_metered_tree(
        [str(python), str(HERE / "phase33_stitch_control_conformance.py")],
        cwd=HERE,
        wall_limit_seconds=limits["wall_seconds"],
        cpu_limit_seconds=limits["cpu_seconds"],
        rss_limit_kib=limits["rss_kib"],
        environment={},
    )
    result = json.loads(
        (RESULTS / "phase33_stitch_control_conformance.json").read_text(
            encoding="utf-8"
        )
    )
    receipt_ok = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and "FOUNDRY_PHASE33_STITCH_CONTROL" in receipt["stdout_text"]
        and receipt["process_group_reaped"]
    )
    conformance_passed = (
        result["status"] == "STITCH_CONTROL_CONFORMANCE_PASS"
        and result["artifact_sha256_verified"]
        and result["official_backend_executed"]
        and result["conformance_executed"]
        and result["conformance_passed"]
    )
    payload = {
        "version": "FOUNDRY_STITCH_CONTROL_RESOURCE_AUDIT_V1",
        "status": (
            "STITCH_CONTROL_RESOURCE_PASS"
            if receipt_ok and conformance_passed
            else "STITCH_CONTROL_RESOURCE_INFRASTRUCTURE_FAILURE"
            if receipt_ok
            and result["status"] == "STITCH_CONTROL_INFRASTRUCTURE_FAILURE"
            else "STITCH_CONTROL_RESOURCE_FAIL"
        ),
        "meter_selftest": meter_test,
        "receipt": receipt,
        "control_result_status": result["status"],
        "receipt_complete": receipt_ok,
        "control_conformance_passed": conformance_passed,
        "P1": {
            "stitch_reproduced": conformance_passed,
            "controls_reproduced": 1 if conformance_passed else 0,
            "controls_required": 4,
            "complete": False,
        },
        "P3": {
            "stitch_control_arm_integrated": receipt_ok,
            "external_controls_integrated": conformance_passed,
            "complete": False,
        },
    }
    (RESULTS / "phase34_stitch_control_resource_audit.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_PHASE34_STITCH_RESOURCE"
        f" status={payload['status']}"
        f" receipt_complete={str(receipt_ok).lower()}"
        f" conformance_passed={str(conformance_passed).lower()}"
    )


if __name__ == "__main__":
    run()
