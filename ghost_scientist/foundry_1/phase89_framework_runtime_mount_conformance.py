#!/usr/bin/env python3
"""Independently check the 23-graph A3/A9 framework-runtime mount."""

from __future__ import annotations

import hashlib
import json
import pathlib

from framework_runtime_mount import EMPTY_STATE_SHA256, canonical, run_arm


HERE = pathlib.Path(__file__).resolve().parent
FIXTURES = HERE / "arm_adapter_fixtures"
RESULT = HERE / "results/phase89_framework_runtime_mount_conformance.json"


def sha256(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run() -> None:
    protocol = json.loads(
        (FIXTURES / "FRAMEWORK_RUNTIME_MOUNT_PROTOCOL_V1.json").read_text()
    )
    arms = {arm_id: run_arm(arm_id) for arm_id in ("A3", "A9")}
    expected = protocol["expected_surface"]
    all_rows = [
        row for receipt in arms.values() for row in receipt["rows"]
    ]
    provider_hashes = {
        row["path"]: sha256(HERE / row["path"])
        for row in protocol["provider_records"]
    }
    expected_hashes = {
        row["path"]: row["sha256"] for row in protocol["provider_records"]
    }

    surface_checks = {}
    for arm_id, receipt in arms.items():
        summary = receipt["summary"]
        arm_expected = expected[arm_id]
        surface_checks[arm_id] = {
            "status_pass": (
                receipt["status"] == "FRAMEWORK_RUNTIME_MOUNT_ARM_PASS"
            ),
            "mount_id_bound": receipt["mount_id"] == protocol["mount_id"],
            "providers_authenticated": (
                receipt["provider_records_authenticated"]
                == len(protocol["provider_records"])
            ),
            "graphs_23": summary["graphs"] == expected["graphs"],
            "operators_41": (
                summary["unique_operator_targets"]
                == expected["unique_operator_targets"]
            ),
            "calls_337": (
                summary["call_function_invocations"]
                == expected["call_function_invocations"]
            ),
            "executions_69": (
                summary["framework_executions"]
                == expected["total_framework_executions_per_arm"]
            ),
            "unsupported_1": (
                summary["unsupported_or_failed"]
                == expected["unsupported_or_failed"]
                == len(receipt["unsupported_or_failed"])
            ),
            "paths_expected": summary["paths"] == arm_expected["paths"],
            "groups_expected": summary["groups"] == arm_expected["groups"],
            "tools_expected": summary["tools"] == arm_expected["tools"],
            "coverage_expected": (
                summary["coverage"] == arm_expected["unique_nodes_covered"]
            ),
            "zero_numerical_error": summary["max_abs_error"] == 0.0,
        }

    checks = {
        "protocol_prefrozen": protocol["frozen_before_mount_execution"],
        "provider_hashes_authentic": provider_hashes == expected_hashes,
        "both_surfaces_exact": all(
            all(row.values()) for row in surface_checks.values()
        ),
        "all_46_rows_present": len(all_rows) == 46,
        "every_row_three_correct_invocations": all(
            len(row["invocation_receipts"]) == 3
            and [item["ordinal"] for item in row["invocation_receipts"]]
            == [1, 2, 3]
            and all(
                item["correct"]
                and item["max_abs_error"] == 0.0
                and item["expected_sha256"] == item["actual_sha256"]
                for item in row["invocation_receipts"]
            )
            for row in all_rows
        ),
        "every_row_alias_checked": all(
            row["alias_storage_checks_passed"] for row in all_rows
        ),
        "every_selected_tool_independently_matched": all(
            (
                row["tools_selected"] == 0
                and row["independent_matches"] == 0
            )
            or (
                row["tools_selected"] > 0
                and row["independent_matches"] > 0
                and row["independent_node_visits"] > 0
            )
            for row in all_rows
        ),
        "every_CPU_ledger_complete": all(
            row["cost_ledger"]["total_cpu_ns"]
            == sum(
                value
                for key, value in row["cost_ledger"].items()
                if key != "total_cpu_ns"
            )
            and row["cost_ledger"]["total_cpu_ns"] > 0
            for row in all_rows
        ),
        "empty_state_per_artifact": all(
            row["state_before_sha256"]
            == row["state_after_sha256"]
            == EMPTY_STATE_SHA256
            and row["library_retained_across_artifacts"] is False
            for row in all_rows
        ),
        "same_artifacts_and_graphs_across_arms": [
            (
                row["artifact_id"],
                row["graph_sha256"],
                row["source_record_sha256"],
                row["shape_seed_sha256"],
            )
            for row in arms["A3"]["rows"]
        ]
        == [
            (
                row["artifact_id"],
                row["graph_sha256"],
                row["source_record_sha256"],
                row["shape_seed_sha256"],
            )
            for row in arms["A9"]["rows"]
        ],
        "arms_behaviorally_distinct": (
            arms["A3"]["summary"]["tools"] != arms["A9"]["summary"]["tools"]
            and arms["A3"]["summary"]["coverage"]
            != arms["A9"]["summary"]["coverage"]
            and arms["A3"]["summary"]["matches"]
            != arms["A9"]["summary"]["matches"]
        ),
        "contract_resource_assembly_explicitly_deferred": protocol[
            "resource_rules"
        ]["per_artifact_contract_resource_assembly_deferred"],
        "integration_truth_not_inflated": protocol["claim_boundary"][
            "production_integrated_arms_after_pass"
        ]
        == 2,
        "P3_still_incomplete": protocol["claim_boundary"][
            "P3_complete_after_pass"
        ]
        is False,
        "validation_v6_unread": all(
            receipt["validation_v6_accessed"] is False
            for receipt in arms.values()
        ),
        "prospective_unauthorized": protocol["claim_boundary"][
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "framework runtime mount conformance failed: "
            + json.dumps(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ],
                    "surfaces": surface_checks,
                },
                sort_keys=True,
            )
        )
    payload = {
        "version": "FOUNDRY_FRAMEWORK_RUNTIME_MOUNT_CONFORMANCE_V1",
        "status": "FRAMEWORK_RUNTIME_MOUNT_COMPONENT_PASS",
        "classification": (
            "A3_A9_CALIBRATION_RUNTIME_MOUNT_NOT_PROSPECTIVE_INTEGRATION"
        ),
        "checks": checks,
        "surface_checks": surface_checks,
        "provider_hashes": provider_hashes,
        "arms": arms,
        "integration": {
            "calibration_graphs_mounted": 23,
            "calibration_operator_targets_executed": 41,
            "A3_A9_runtime_mount_component_ready": True,
            "full_contract_resource_assembly_ready": False,
            "production_integrated_arms": 2,
            "required_arms": 10,
        },
        "P3": {
            "A3_A9_runtime_mount_component_ready": True,
            "all_required_arms_runtime_mounted": False,
            "all_required_prospective_arms_metered": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE89_FRAMEWORK_RUNTIME_MOUNT"
        f" status={payload['status']}"
        " graphs=23 ops=41 calls=337 executions=69/69"
        " tools=76/83 coverage=126/226 error=0"
        " integrated=2/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
