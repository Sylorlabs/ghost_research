#!/usr/bin/env python3
"""Meter shared-resource batch assembly and its falsification gate."""

from __future__ import annotations

import json
import pathlib
import sys

from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
RESULT = HERE / "results/phase92_shared_resource_batch_resource_audit.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    limits = {
        "wall_limit_seconds": 20,
        "cpu_limit_seconds": 15,
        "rss_limit_kib": 524288,
    }
    environment = {"PYTHONWARNINGS": "ignore"}
    conformance = run_metered_tree(
        [
            str(python),
            str(HERE / "phase91_shared_resource_batch_conformance.py"),
        ],
        cwd=HERE,
        wall_limit_seconds=limits["wall_limit_seconds"],
        cpu_limit_seconds=limits["cpu_limit_seconds"],
        rss_limit_kib=limits["rss_limit_kib"],
        environment=environment,
    )
    conformance["expected_status_seen"] = (
        "FOUNDRY_PHASE91_SHARED_RESOURCE_BATCH"
        in conformance["stdout_text"]
        and "base_pairs=46/46" in conformance["stdout_text"]
        and "hostile=9/9" in conformance["stdout_text"]
        and "integrated=4/10" in conformance["stdout_text"]
    )
    arms = {}
    for arm_id in ("A3", "A9"):
        receipt = run_metered_tree(
            [
                str(python),
                str(HERE / "shared_resource_batch.py"),
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
        receipt["batch_summary"] = output
        arms[arm_id] = receipt
    all_receipts = [conformance, *arms.values()]
    checks = {
        "meter_hostile_selftest": meter_test["pass"],
        "identical_declared_ceilings": True,
        "conformance_natural": (
            conformance["returncode"] == 0
            and conformance["termination"] == "natural"
            and conformance["expected_status_seen"]
        ),
        "both_arm_batches_natural": all(
            row["returncode"] == 0 and row["termination"] == "natural"
            for row in arms.values()
        ),
        "both_arm_batch_summaries_exact": all(
            row["batch_summary"]["artifact_outputs"] == 23
            and row["batch_summary"]["base_contract_primary_accepts"] == 23
            and row["batch_summary"][
                "base_contract_independent_accepts"
            ]
            == 23
            and row["batch_summary"]["aggregate_accounting"][
                "unique_resource_receipts_charged"
            ]
            == 1
            and row["batch_summary"]["aggregate_accounting"][
                "resource_multiplier_applied"
            ]
            == 1
            and row["batch_summary"][
                "production_integration_classification"
            ]
            == "PRODUCTION_INTEGRATED_CALIBRATION_ARM"
            for row in arms.values()
        ),
        "all_process_CPU_charged": all(
            row["rusage_user_cpu_ns"] + row["rusage_system_cpu_ns"] > 0
            for row in all_receipts
        ),
        "all_process_RSS_sampled": all(
            row["peak_group_rss_kib"] > 0 for row in all_receipts
        ),
        "all_process_groups_reaped": all(
            row["process_group_reaped"] for row in all_receipts
        ),
        "validation_v6_unread": all(
            row["batch_summary"]["validation_v6_accessed"] is False
            for row in arms.values()
        ),
    }
    if not all(checks.values()):
        raise RuntimeError(
            "shared resource batch resource audit failed: "
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
        "version": "FOUNDRY_SHARED_RESOURCE_BATCH_RESOURCE_AUDIT_V1",
        "status": "SHARED_RESOURCE_BATCH_RESOURCE_PASS",
        "limits": limits,
        "meter_selftest": meter_test,
        "conformance_receipt": conformance,
        "arms": arms,
        "checks": checks,
        "integration": {
            "A3_batch_assembly_process_tree_metered": True,
            "A9_batch_assembly_process_tree_metered": True,
            "production_integrated_arms": 4,
            "required_arms": 10,
        },
        "P3": {
            "shared_resource_receipt_identity_ready": True,
            "A3_A9_complete_contract_batches_ready": True,
            "all_required_arms_integrated_and_metered": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE92_SHARED_RESOURCE_BATCH_RESOURCE"
        f" status={payload['status']}"
        " arms=2/2 base_pairs=46/46 receipts_charged=1+1"
        " integrated=4/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
