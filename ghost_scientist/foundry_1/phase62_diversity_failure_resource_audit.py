#!/usr/bin/env python3
"""Meter the post-prospective failure-mechanism calibration audit."""

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
        [str(python), str(HERE / "phase61_diversity_failure_calibration.py")],
        cwd=HERE,
        wall_limit_seconds=60,
        cpu_limit_seconds=45,
        rss_limit_kib=1_000_000,
    )
    result = json.loads(
        (
            RESULTS / "phase61_diversity_failure_calibration.json"
        ).read_text()
    )
    complete = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and "FOUNDRY_PHASE61_DIVERSITY_FAILURE_CALIBRATION_PASS"
        in receipt["stdout_text"]
        and result["status"] == "DIVERSITY_FAILURE_MECHANISM_AUDIT_COMPLETE"
        and result["classification"] == "POST_PROSPECTIVE_CALIBRATION_ONLY"
        and result["prospective_claim_allowed"] is False
    )
    passed = meter_test["pass"] and complete
    payload = {
        "version": "FOUNDRY_DIVERSITY_FAILURE_RESOURCE_AUDIT_V1",
        "status": (
            "DIVERSITY_FAILURE_RESOURCE_PASS"
            if passed
            else "DIVERSITY_FAILURE_RESOURCE_FAIL"
        ),
        "meter_selftest": meter_test,
        "receipt": receipt,
        "receipt_complete": complete,
        "prospective_claim_allowed": False,
    }
    (
        RESULTS / "phase62_diversity_failure_resource_audit.json"
    ).write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE62_DIVERSITY_FAILURE_RESOURCE"
        f" status={payload['status']}"
        f" processes={receipt['observed_process_count']}"
    )


if __name__ == "__main__":
    run()
