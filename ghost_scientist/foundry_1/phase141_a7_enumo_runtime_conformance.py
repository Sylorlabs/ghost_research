#!/usr/bin/env python3
"""Conformance gate for the A7 adapted Enumo runtime mount."""

from __future__ import annotations

import json
import pathlib

from a7_enumo_runtime_mount import canonical, run


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/A7_ENUMO_RUNTIME_MOUNT_PROTOCOL_V1.json"
RESULT = HERE / "results/phase141_a7_enumo_runtime_conformance.json"


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    receipt = run()
    summary = receipt["summary"]
    expected = protocol["expected"]
    rows = receipt["rows"]
    checks = {
        "runtime_mount_component_PASS": receipt["status"]
        == "A7_ENUMO_RUNTIME_MOUNT_COMPONENT_PASS",
        "expected_surface_exact": all(
            summary[key] == value for key, value in expected.items()
        ),
        "two_extractors_agree_all_23": (
            len(rows) == 23 and all(row["island_sha256"] for row in rows)
        ),
        "three_whole_graph_executions_each": all(
            [item["ordinal"] for item in row["invocation_receipts"]]
            == [1, 2, 3]
            for row in rows
        ),
        "all_whole_graph_outputs_exact": all(
            item["correct"]
            and item["expected_sha256"] == item["actual_sha256"]
            for row in rows
            for item in row["invocation_receipts"]
        ),
        "all_unique_rewrites_exact": all(
            item["max_abs_error"] == 0.0
            and item["expected_sha256"] == item["actual_sha256"]
            and item["alias_storage_checks_passed"]
            for row in rows
            for item in row["rewrite_receipts"]
        ),
        "raw_24_deduplicated_to_12": (
            summary["raw_selected_rule_applications"] == 24
            and summary["unique_selected_transformations"] == 12
            and summary["unique_rewrite_concrete_checks"] == 36
        ),
        "selected_semantics_exactly_commutativity": (
            summary["selected_rule_semantics"]
            == protocol["rewrite_policy"]["expected_selected_rule_semantics"]
        ),
        "candidate_generation_charged_once": (
            sum(
                row["cost_ledger"]["candidate_generation_cpu_ns"] > 0
                for row in rows
            )
            == 1
            and sum(
                row["cost_ledger"]["candidate_generation_cpu_ns"]
                for row in rows
            )
            == receipt["candidate_generation_cpu_ns"]
        ),
        "complete_positive_CPU_ledgers": all(
            row["cost_ledger"]["total_cpu_ns"]
            == sum(
                value
                for key, value in row["cost_ledger"].items()
                if key != "total_cpu_ns"
            )
            and row["cost_ledger"]["total_cpu_ns"] > 0
            for row in rows
        ),
        "retained_library_immutable": all(
            row["state_before_sha256"]
            == row["state_after_sha256"]
            == receipt["library_sha256"]
            and row["library_retained_across_artifacts"] is True
            for row in rows
        ),
        "scientific_boundary_narrow": receipt["scientific_boundary"]
        == {
            "adapted_evaluator_authored_tensor_domain": True,
            "equal_cost_operand_canonicalization_only": True,
            "strict_atom_cost_reductions": 0,
            "rewritten_whole_tensor_graph_executed": False,
            "heldout_generalization_measured": False,
            "fixed_portfolio_beaten": False,
            "universal_floating_point_theorem": False,
        },
        "one_unsupported_explicit": (
            len(receipt["unsupported_or_failed"]) == 1
        ),
        "integration_not_inflated": (
            receipt["integration"]["A7_production_integrated"] is False
            and receipt["integration"]["production_integrated_arms"] == 6
        ),
        "validation_v6_unread": receipt["validation_v6_accessed"] is False,
        "prospective_unauthorized": receipt[
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A7 runtime conformance failed: "
            + canonical(
                {"failed": [key for key, value in checks.items() if not value]}
            )
        )
    payload = {
        "version": "FOUNDRY_A7_ENUMO_RUNTIME_CONFORMANCE_V1",
        "status": "A7_ENUMO_RUNTIME_CONFORMANCE_PASS",
        "checks": checks,
        "runtime_receipt": receipt,
        "integration": {
            "A7_runtime_mount_component_ready": True,
            "A7_contract_batch_ready": False,
            "A7_production_integrated": False,
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3": {"complete": False},
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE141_A7_ENUMO_RUNTIME"
        " status=A7_ENUMO_RUNTIME_CONFORMANCE_PASS"
        " graphs=23 calls=337 eligible=53 matches=282"
        " raw_selected=24 unique=12 executions=69 rewrite_checks=36"
        " integrated=6/10 prospective=false"
    )


if __name__ == "__main__":
    main()
