#!/usr/bin/env python3
"""Meter the frozen prospective diversity candidate/fixed comparison."""

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
        [str(python), str(HERE / "phase59_prospective_diversity_trial.py")],
        cwd=HERE,
        wall_limit_seconds=180,
        cpu_limit_seconds=150,
        rss_limit_kib=4_500_000,
        environment={
            "TORCHINDUCTOR_COMPILE_THREADS": "1",
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
        },
    )
    result_path = RESULTS / "phase59_prospective_diversity_trial.json"
    result = json.loads(result_path.read_text()) if result_path.exists() else {}
    receipt_complete = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"]
        and receipt["observed_process_count"] >= 1
        and "FOUNDRY_PHASE59_PROSPECTIVE_DIVERSITY"
        in receipt["stdout_text"]
    )
    result_complete = result.get("status") in {
        "DIVERSITY_PROSPECTIVE_TRANSFER_PASS",
        "DIVERSITY_PROSPECTIVE_VALID_NEGATIVE",
    }
    passed = meter_test["pass"] and receipt_complete and result_complete
    payload = {
        "version": "FOUNDRY_PROSPECTIVE_DIVERSITY_RESOURCE_AUDIT_V1",
        "status": (
            "PROSPECTIVE_DIVERSITY_RESOURCE_PASS"
            if passed
            else "PROSPECTIVE_DIVERSITY_RESOURCE_FAIL"
        ),
        "meter_selftest": meter_test,
        "receipt": receipt,
        "receipt_complete": receipt_complete,
        "result_complete": result_complete,
        "prospective_result_status": result.get("status"),
    }
    (
        RESULTS / "phase60_prospective_diversity_resource_audit.json"
    ).write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_PHASE60_PROSPECTIVE_DIVERSITY_RESOURCE"
        f" status={payload['status']}"
        f" processes={receipt['observed_process_count']}"
    )


if __name__ == "__main__":
    run()
