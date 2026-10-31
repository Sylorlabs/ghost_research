#!/usr/bin/env python3
"""Meter the full 23-graph operator-vocabulary route audit."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = (
    HERE / "results/phase88_calibration_operator_vocabulary_resource_audit.json"
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    limits = {
        "wall_limit_seconds": 90,
        "cpu_limit_seconds": 75,
        "rss_limit_kib": 4500000,
    }
    receipt = run_metered_tree(
        [
            str(python),
            str(HERE / "phase87_calibration_operator_vocabulary_audit.py"),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment={
            "PYTHONWARNINGS": "ignore",
            "TORCHINDUCTOR_COMPILE_THREADS": "1",
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
        },
    )
    receipt["expected_status_seen"] = (
        "FOUNDRY_PHASE87_OPERATOR_VOCAB" in receipt["stdout_text"]
        and "graphs=23" in receipt["stdout_text"]
        and "ops=3/41" in receipt["stdout_text"]
        and "route=FRAMEWORK_MOUNT" in receipt["stdout_text"]
    )
    audit = json.loads(
        (
            HERE / "results/phase87_calibration_operator_vocabulary_audit.json"
        ).read_text()
    )
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "natural_termination": (
            receipt["returncode"] == 0
            and receipt["termination"] == "natural"
        ),
        "status_bound": receipt["expected_status_seen"],
        "cpu_charged": (
            receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "rss_sampled": receipt["peak_group_rss_kib"] > 0,
        "process_group_reaped": receipt["process_group_reaped"],
        "all_23_graphs_in_receipt": audit["summary"]["graphs"] == 23,
        "all_41_operators_in_receipt": audit["summary"][
            "unique_operators"
        ]
        == 41,
        "manual_route_still_rejected": audit["decision"][
            "manual_typed_dag_interpreter_production_ready"
        ]
        is False,
        "validation_v6_unread": audit["validation_v6_accessed"] is False,
    }
    if not all(checks.values()):
        raise RuntimeError("operator vocabulary resource audit failed")
    payload = {
        "version": "FOUNDRY_CALIBRATION_OPERATOR_VOCAB_RESOURCE_AUDIT_V1",
        "status": "OPERATOR_VOCAB_ROUTE_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "receipt": receipt,
        "checks": checks,
        "P3": {
            "operator_route_audit_process_tree_metered": True,
            "framework_runtime_mount_implemented": False,
            "all_required_prospective_arms_metered": False,
            "complete": False,
        },
        "production_integrated_arms": 2,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE88_OPERATOR_VOCAB_RESOURCE"
        f" status={payload['status']}"
        " graphs=23 ops=41"
        " route=FRAMEWORK_MOUNT P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
