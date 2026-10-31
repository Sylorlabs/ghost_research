#!/usr/bin/env python3
"""Meter A3 and A9 control kernels under identical calibration ceilings."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = HERE / "results/phase73_per_instance_resource_audit.json"
CONFORMANCE = HERE / "results/phase72_per_instance_control_conformance.json"


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
    arms = {}
    for arm in ("A3_NO_LIBRARY", "A9_PER_INSTANCE"):
        receipt = run_metered_tree(
            [
                str(python),
                str(HERE / "per_instance_controls.py"),
                "--mode",
                arm,
                "--summary",
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
            f"mode={arm}" in receipt["stdout_text"]
            and "graphs=23" in receipt["stdout_text"]
            and "search=969" in receipt["stdout_text"]
            and "validation_v6_accessed=false" in receipt["stdout_text"]
        )
        arms[arm] = receipt
    conformance = json.loads(CONFORMANCE.read_text(encoding="utf-8"))
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "identical_declared_resource_ceilings": True,
        "identical_abstract_search_budget": (
            conformance["A3"]["summary"]["search_construction_units"]
            == conformance["A9"]["summary"]["search_construction_units"]
            == 969
        ),
        "both_arms_natural": all(
            row["returncode"] == 0 and row["termination"] == "natural"
            for row in arms.values()
        ),
        "both_statuses_bound": all(
            row["expected_status_seen"] for row in arms.values()
        ),
        "both_cpu_charged": all(
            row["rusage_user_cpu_ns"] + row["rusage_system_cpu_ns"] > 0
            for row in arms.values()
        ),
        "both_rss_sampled": all(
            row["peak_group_rss_kib"] > 0 for row in arms.values()
        ),
        "both_groups_reaped": all(
            row["process_group_reaped"] for row in arms.values()
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("per-instance resource audit failed")
    payload = {
        "version": "FOUNDRY_PER_INSTANCE_RESOURCE_AUDIT_V1",
        "status": "PER_INSTANCE_CONTROL_RESOURCE_COMPONENT_READY",
        "classification": "CALIBRATION_METERED_NOT_HELDOUT_EXECUTED",
        "limits": limits,
        "meter_selftest": meter_test,
        "arms": arms,
        "checks": checks,
        "P3": {
            "A3_process_tree_metered": True,
            "A9_process_tree_metered": True,
            "prospective_arm_integration_complete": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE73_PER_INSTANCE_RESOURCE"
        f" status={payload['status']}"
        f" arms={len(arms)}/2"
        " prospective=false"
    )


if __name__ == "__main__":
    run()
