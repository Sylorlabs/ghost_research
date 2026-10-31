#!/usr/bin/env python3
"""Phase 8: meter representative forge, fixed, verifier, compiler, and corpus arms."""

from __future__ import annotations

import json
import pathlib
import sys

from independent_evaluator import canonical_json
from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULTS = HERE / "results"


def run() -> None:
    meter_test = selftest(sys.executable, ROOT)
    arms = {}
    expectations = {
        "forge": "METERED_FORGE_PASS",
        "fixed": "METERED_FIXED_PASS",
        "verifier": "METERED_VERIFIER_PASS",
        "compiler": "METERED_COMPILER_PASS",
        "corpus": "METERED_CORPUS_PASS",
    }
    for name, expected in expectations.items():
        receipt = run_metered_tree(
            [sys.executable, str(HERE / "metered_arm.py"), name],
            cwd=ROOT,
            wall_limit_seconds=90,
            cpu_limit_seconds=75,
            # Development calibration only: the first run killed TorchInductor
            # at 2,028,412 KiB under a provisional 2,000,000 KiB ceiling.
            # The prospective limit must be frozen independently.
            rss_limit_kib=4_000_000,
            environment=(
                {
                    "TORCHINDUCTOR_COMPILE_THREADS": "1",
                    "OMP_NUM_THREADS": "1",
                    "MKL_NUM_THREADS": "1",
                }
                if name == "compiler"
                else None
            ),
        )
        receipt["expected_status_seen"] = expected in receipt["stdout_text"]
        arms[name] = receipt
    gates = {
        "meter_hostile_selftest": meter_test["pass"],
        "all_representative_arms_complete": all(
            item["returncode"] == 0 and item["termination"] == "natural"
            for item in arms.values()
        ),
        "all_statuses_bound": all(item["expected_status_seen"] for item in arms.values()),
        "all_cpu_charged": all(
            item["rusage_user_cpu_ns"] + item["rusage_system_cpu_ns"] > 0
            for item in arms.values()
        ),
        "all_rss_sampled": all(item["peak_group_rss_kib"] > 0 for item in arms.values()),
        "all_groups_reaped": all(item["process_group_reaped"] for item in arms.values()),
    }
    payload = {
        "version": "FOUNDRY_RESOURCE_INTEGRATION_AUDIT_V2",
        "status": "RESOURCE_COMPONENT_READY" if all(gates.values()) else "RESOURCE_COMPONENT_FAIL",
        "gates": gates,
        "meter_selftest": meter_test,
        "arms": arms,
        "P3": {
            "representative_local_arms_integrated": all(gates.values()),
            "external_controls_integrated": False,
            "all_future_trial_arms_integrated": False,
            "complete": False,
        },
        "limits": [
            "external control executables do not yet exist and therefore cannot be metered",
            "the final freeze must deny new sessions or use a writable cgroup",
            "representative-arm coverage is not the final v6 arm matrix",
        ],
    }
    RESULTS.mkdir(parents=True, exist_ok=True)
    (RESULTS / "phase8_resource_audit.json").write_text(
        canonical_json(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE8_RESOURCE_AUDIT"
        f" status={payload['status']} arms={len(arms)}"
        f" p3_complete={str(payload['P3']['complete']).lower()}"
    )


if __name__ == "__main__":
    run()
