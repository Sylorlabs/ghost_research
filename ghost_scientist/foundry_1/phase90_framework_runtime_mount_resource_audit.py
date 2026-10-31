#!/usr/bin/env python3
"""Meter the A3/A9 framework mounts under identical process-tree ceilings."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = HERE / "results/phase90_framework_runtime_mount_resource_audit.json"


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
    environment = {
        "PYTHONWARNINGS": "ignore",
        "TORCHINDUCTOR_COMPILE_THREADS": "1",
        "OMP_NUM_THREADS": "1",
        "MKL_NUM_THREADS": "1",
    }
    arms = {}
    for arm_id in ("A3", "A9"):
        receipt = run_metered_tree(
            [
                str(python),
                str(HERE / "framework_runtime_mount.py"),
                "--arm",
                arm_id,
                "--summary-only",
            ],
            cwd=HERE,
            wall_limit_seconds=limits["wall_limit_seconds"],
            cpu_limit_seconds=limits["cpu_limit_seconds"],
            rss_limit_kib=limits["rss_limit_kib"],
            environment=environment,
        )
        output = json.loads(receipt["stdout_text"])
        receipt["mount_status"] = output["status"]
        receipt["summary"] = output["summary"]
        receipt["rows"] = output["rows"]
        receipt["state_reset"] = output["all_rows_state_reset"]
        receipt["validation_v6_accessed"] = output[
            "validation_v6_accessed"
        ]
        arms[arm_id] = receipt
    expected = {
        "A3": {"tools": 76, "coverage": 126},
        "A9": {"tools": 83, "coverage": 226},
    }
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "identical_declared_ceilings": True,
        "both_arms_natural": all(
            row["returncode"] == 0 and row["termination"] == "natural"
            for row in arms.values()
        ),
        "both_mounts_PASS": all(
            row["mount_status"] == "FRAMEWORK_RUNTIME_MOUNT_ARM_PASS"
            for row in arms.values()
        ),
        "both_full_surfaces_exact": all(
            row["rows"] == 23
            and row["summary"]["graphs"] == 23
            and row["summary"]["unique_operator_targets"] == 41
            and row["summary"]["call_function_invocations"] == 337
            and row["summary"]["framework_executions"] == 69
            and row["summary"]["unsupported_or_failed"] == 1
            and row["summary"]["paths"] == 581
            and row["summary"]["groups"] == 388
            and row["summary"]["tools"] == expected[arm_id]["tools"]
            and row["summary"]["coverage"]
            == expected[arm_id]["coverage"]
            and row["summary"]["max_abs_error"] == 0.0
            for arm_id, row in arms.items()
        ),
        "both_state_reset": all(row["state_reset"] for row in arms.values()),
        "all_process_CPU_charged": all(
            row["rusage_user_cpu_ns"] + row["rusage_system_cpu_ns"] > 0
            for row in arms.values()
        ),
        "all_process_RSS_sampled": all(
            row["peak_group_rss_kib"] > 0 for row in arms.values()
        ),
        "all_process_groups_reaped": all(
            row["process_group_reaped"] for row in arms.values()
        ),
        "validation_v6_unread": all(
            row["validation_v6_accessed"] is False
            for row in arms.values()
        ),
        "resource_accounting_boundary_preserved": True,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "framework runtime mount resource audit failed: "
            + json.dumps(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                },
                sort_keys=True,
            )
        )
    payload = {
        "version": "FOUNDRY_FRAMEWORK_RUNTIME_MOUNT_RESOURCE_AUDIT_V1",
        "status": "FRAMEWORK_RUNTIME_MOUNT_RESOURCE_COMPONENT_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "arms": arms,
        "checks": checks,
        "resource_accounting_boundary": (
            "Each complete A3/A9 mount process tree is metered once. The "
            "receipt is not copied into 23 artifact contract records because "
            "the frozen contract has no shared resource-receipt identifier."
        ),
        "P3": {
            "A3_A9_complete_mount_process_trees_metered": True,
            "per_artifact_contract_resource_assembly_ready": False,
            "all_required_prospective_arms_metered": False,
            "complete": False,
        },
        "production_integrated_arms": 2,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE90_FRAMEWORK_RUNTIME_MOUNT_RESOURCE"
        f" status={payload['status']}"
        " arms=2/2 graphs=23/23 ops=41/41 executions=69/69"
        " contract_resource_assembly=false P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
