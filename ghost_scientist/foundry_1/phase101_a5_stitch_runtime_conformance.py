#!/usr/bin/env python3
"""Conformance gate for the A5 Stitch structural runtime mount."""

from __future__ import annotations

import json
import pathlib

from a5_stitch_runtime_mount import canonical, run
from independent_a5_stitch_semantics_audit import (
    run as independent_semantics_run,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULT = HERE / "results/phase101_a5_stitch_runtime_conformance.json"


def main() -> None:
    receipt = run()
    independent = independent_semantics_run()
    rows = receipt["rows"]
    summary = receipt["summary"]
    independent_counts = {
        row["artifact_id"]: row["abstraction_invocations"]
        for row in independent["artifacts"]
    }
    checks = {
        "runtime_mount_component_PASS": receipt["status"]
        == "A5_STITCH_RUNTIME_MOUNT_COMPONENT_PASS",
        "all_23_graphs_mounted": len(rows) == summary["graphs"] == 23,
        "complete_surface_41_337": (
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
        "all_framework_outputs_exact": (
            summary["max_graph_abs_error"] == 0.0
            and all(
                item["correct"]
                and item["expected_sha256"] == item["actual_sha256"]
                for row in rows
                for item in row["invocation_receipts"]
            )
        ),
        "normalized_reconstruction_23_raw_0": (
            summary["normalized_expansions_byte_identical"] == 23
            and summary["raw_encoder_bytes_identical"] == 0
            and all(
                row["normalized_expansion_byte_identical"]
                and row["raw_encoder_bytes_identical"] is False
                for row in rows
            )
        ),
        "exact_source_result_reproduced": (
            summary["abstractions"] == 1
            and summary["structural_rewrite_uses"] == 329
            and summary["original_cost"] == 452962
            and summary["final_cost"] == 386504
        ),
        "independent_semantics_PASS": (
            independent["status"] == "PASS"
            and all(independent["checks"].values())
        ),
        "per_artifact_use_counts_independently_equal": all(
            row["tool_receipts"][0]["direct_use_count"]
            == independent_counts[row["artifact_id"]]
            for row in rows
        ),
        "one_tool_receipt_and_total_329": (
            all(len(row["tool_receipts"]) == 1 for row in rows)
            and sum(
                row["tool_receipts"][0]["direct_use_count"]
                for row in rows
            )
            == 329
        ),
        "candidate_generation_CPU_charged_once": sum(
            row["cost_ledger"]["candidate_generation_cpu_ns"] > 0
            for row in rows
        )
        == 1,
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
        "retained_library_state_immutable": all(
            row["state_before_sha256"]
            == row["state_after_sha256"]
            == receipt["library_sha256"]
            and row["library_retained_across_artifacts"] is True
            for row in rows
        ),
        "scientific_boundary_narrow": receipt["scientific_boundary"]
        == {
            "framework_export_numerical_parity_proven": True,
            "rewritten_stitch_program_executed_as_tensor_runtime": False,
            "new_tensor_primitive_discovered": False,
            "heldout_generalization_measured": False,
            "fixed_portfolio_beaten": False,
            "normalized_textual_rewrite_reversibility_proven": True,
            "raw_encoder_byte_reversibility_proven": False,
            "normalization_only_difference": (
                "encoder nullary (dict ) applications become Stitch atom dict"
            ),
        },
        "one_unsupported_explicit": (
            summary["unsupported_or_failed"] == 1
            and len(receipt["unsupported_or_failed"]) == 1
        ),
        "integration_not_inflated": (
            receipt["integration"]["A5_production_integrated"] is False
            and receipt["integration"]["production_integrated_arms"] == 5
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
            "A5 Stitch runtime conformance failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ]
                }
            )
        )
    payload = {
        "version": "FOUNDRY_A5_STITCH_RUNTIME_CONFORMANCE_V1",
        "status": "A5_STITCH_RUNTIME_CONFORMANCE_PASS",
        "checks": checks,
        "runtime_receipt": receipt,
        "independent_semantics": independent,
        "integration": {
            "A5_runtime_mount_component_ready": True,
            "A5_contract_batch_ready": False,
            "A5_production_integrated": False,
            "production_integrated_arms": 5,
            "required_arms": 10,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE101_A5_STITCH_RUNTIME"
        f" status={payload['status']}"
        " graphs=23 ops=41 calls=337 executions=69"
        " normalized=23/23 raw=0/23 uses=329 error=0"
        " integrated=5/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
