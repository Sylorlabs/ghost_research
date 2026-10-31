#!/usr/bin/env python3
"""Meter the historical-corpus diversity calibration audit."""

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
        [str(python), str(HERE / "phase53_diversity_calibration_audit.py")],
        cwd=HERE,
        wall_limit_seconds=240,
        cpu_limit_seconds=180,
        rss_limit_kib=4_500_000,
        environment={
            "TORCHINDUCTOR_COMPILE_THREADS": "1",
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
        },
    )
    result = json.loads(
        (RESULTS / "phase53_diversity_calibration_audit.json").read_text()
    )
    receipt_ok = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and receipt["observed_process_count"] >= 1
        and "FOUNDRY_PHASE53_DIVERSITY_CALIBRATION"
        in receipt["stdout_text"]
    )
    completed = (
        result["status"] == "DIVERSITY_CALIBRATION_AUDIT_COMPLETE"
        and result["classification"]
        == "HISTORICAL_OUTCOMES_CALIBRATION_ONLY"
        and result["autonomy_boundary"]["prospective_claim_allowed"]
        is False
    )
    passed = meter_test["pass"] and receipt_ok and completed
    payload = {
        "version": "FOUNDRY_DIVERSITY_CALIBRATION_RESOURCE_AUDIT_V1",
        "status": (
            "DIVERSITY_CALIBRATION_RESOURCE_PASS"
            if passed
            else "DIVERSITY_CALIBRATION_RESOURCE_FAIL"
        ),
        "meter_selftest": meter_test,
        "receipt": receipt,
        "receipt_complete": receipt_ok,
        "calibration_completed": completed,
        "prospective_claim_allowed": False,
    }
    (
        RESULTS / "phase54_diversity_calibration_resource_audit.json"
    ).write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE54_DIVERSITY_CALIBRATION_RESOURCE"
        f" status={payload['status']}"
        f" processes={receipt['observed_process_count']}"
    )


if __name__ == "__main__":
    run()
