#!/usr/bin/env python3
"""Conformance gate for the A4 historical replay runtime mount."""

from __future__ import annotations

import json
import pathlib

from a4_replay_runtime_mount import canonical, run


HERE = pathlib.Path(__file__).resolve().parent
RESULT = HERE / "results/phase95_a4_replay_runtime_conformance.json"


def load(name: str) -> dict:
    return json.loads((HERE / "results" / name).read_text())


def main() -> None:
    receipt = run()
    historical = load("phase56_independent_diversity_conformance.json")
    native = load("phase57_diversity_native_dedup.json")
    resources = load("phase58_diversity_resource_audit.json")
    prospective = load("phase59_prospective_diversity_trial.json")
    rows = receipt["rows"]
    summary = receipt["summary"]
    library_sha256 = receipt["library_sha256"]
    checks = {
        "runtime_mount_component_PASS": receipt["status"]
        == "A4_REPLAY_RUNTIME_MOUNT_COMPONENT_PASS",
        "all_23_graphs_mounted": len(rows) == summary["graphs"] == 23,
        "complete_operator_surface": (
            summary["unique_operator_targets"] == 41
            and summary["call_function_invocations"] == 337
        ),
        "three_whole_graph_executions_each": (
            summary["whole_graph_executions"] == 69
            and all(
                len(row["invocation_receipts"]) == 3
                and [
                    item["ordinal"]
                    for item in row["invocation_receipts"]
                ]
                == [1, 2, 3]
                for row in rows
            )
        ),
        "all_whole_graph_outputs_exact": (
            summary["max_graph_abs_error"] == 0.0
            and all(
                item["correct"]
                and item["expected_sha256"] == item["actual_sha256"]
                for row in rows
                for item in row["invocation_receipts"]
            )
        ),
        "all_three_immutable_tools_replayed": (
            summary["immutable_tools"] == summary["tools_replayed"] == 3
            and len(summary["tool_replays_by_id"]) == 3
            and all(
                count > 0
                for count in summary["tool_replays_by_id"].values()
            )
        ),
        "all_29_tool_replays_exact": (
            summary["successful_tool_replays"] == 29
            and summary["max_tool_abs_error"] == 0.0
            and all(
                item["max_abs_error"] == 0.0
                for row in rows
                for item in row["tool_receipts"]
            )
        ),
        "retained_library_state_immutable": all(
            row["state_before_sha256"]
            == row["state_after_sha256"]
            == library_sha256
            and row["library_retained_across_artifacts"] is True
            for row in rows
        ),
        "every_CPU_ledger_complete": all(
            row["cost_ledger"]["total_cpu_ns"]
            == sum(
                value
                for key, value in row["cost_ledger"].items()
                if key != "total_cpu_ns"
            )
            and row["cost_ledger"]["total_cpu_ns"] > 0
            for row in rows
        ),
        "historical_independent_conformance_preserved": (
            historical["status"]
            == "DIVERSITY_TOOL_INDEPENDENT_CONFORMANCE_PASS"
            and historical["successful_replays"] == 21
            and historical["tools"] == 3
        ),
        "native_dedup_boundary_preserved": (
            native["status"] == "DIVERSITY_NATIVE_DEDUP_COMPLETE"
            and native["summary"]["runtime_inventions_admitted"] == 0
            and native["summary"][
                "normalized_inductor_duplicates"
            ]
            == 3
        ),
        "historical_resource_component_preserved": resources["status"]
        == "DIVERSITY_RESOURCE_COMPONENT_READY",
        "historical_valid_negative_preserved": (
            prospective["status"] == "DIVERSITY_PROSPECTIVE_VALID_NEGATIVE"
            and prospective["candidate"]["matched_tools"] == 2
            and prospective["claim_boundary"][
                "native_runtime_inventions"
            ]
            == 0
        ),
        "one_unsupported_artifact_explicit": (
            summary["unsupported_or_failed"] == 1
            and len(receipt["unsupported_or_failed"]) == 1
        ),
        "integration_not_inflated": (
            receipt["integration"]["A4_production_integrated"] is False
            and receipt["integration"]["production_integrated_arms"] == 4
        ),
        "P3_incomplete": receipt["P3_complete"] is False,
        "validation_v6_unread": receipt["validation_v6_accessed"] is False,
        "prospective_unauthorized": receipt[
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A4 replay conformance failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": "FOUNDRY_A4_REPLAY_RUNTIME_CONFORMANCE_V1",
        "status": "A4_REPLAY_RUNTIME_CONFORMANCE_PASS",
        "checks": checks,
        "runtime_receipt": receipt,
        "integration": {
            "A4_runtime_mount_component_ready": True,
            "A4_contract_batch_ready": False,
            "A4_production_integrated": False,
            "production_integrated_arms": 4,
            "required_arms": 10,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE95_A4_REPLAY_RUNTIME"
        f" status={payload['status']}"
        " graphs=23 ops=41 calls=337 executions=69"
        " tools=3/3 replays=29 error=0"
        " integrated=4/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
