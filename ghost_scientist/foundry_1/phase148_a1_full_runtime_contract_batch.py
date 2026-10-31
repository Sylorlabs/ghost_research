#!/usr/bin/env python3
"""Meter, assemble, falsify, and integrate the frozen A1 runtime batch."""

from __future__ import annotations

import copy
import hashlib
import json
import math
import pathlib
import sys
from typing import Any

from a1_full_runtime_mount import run as run_mount
from arm_adapter_contract import parse_input, parse_output
from independent_arm_adapter_contract import (
    IndependentAdapterReject,
    verify as independent_verify,
)
from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PROTOCOL = HERE / "arm_adapter_fixtures/A1_FULL_RUNTIME_CONTRACT_PROTOCOL_V1.json"
FREEZE = HERE / "results/a1_full_runtime_contract_v1_freeze.json"
FIXED = HERE / "results/forged_diversity_tools.json"
ADAPTER = HERE / "a1_full_runtime_mount.py"
WORKER_RESULT = HERE / "results/phase148_a1_full_runtime_mount_worker.json"
RESULT = HERE / "results/phase148_a1_full_runtime_contract_batch.json"


def canonical(value: object) -> bytes:
    return json.dumps(
        value, sort_keys=True, separators=(",", ":")
    ).encode()


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def worker() -> None:
    payload = run_mount()
    WORKER_RESULT.write_bytes(canonical(payload) + b"\n")
    print(
        "FOUNDRY_PHASE148_WORKER"
        f" graphs={payload['summary']['graphs']}"
        f" executions={payload['summary']['whole_graph_executions']}"
        f" folds={payload['summary']['fold_checks']}"
    )


def rejected_twice(request: dict, output: dict) -> bool:
    raw_input = canonical(request)
    raw_output = canonical(output)
    primary = independent = False
    try:
        parsed = parse_input(raw_input)
        parse_output(raw_output, parsed)
    except (ValueError, KeyError, TypeError, json.JSONDecodeError):
        primary = True
    try:
        independent_verify(raw_input, raw_output)
    except (
        IndependentAdapterReject,
        ValueError,
        KeyError,
        TypeError,
        json.JSONDecodeError,
    ):
        independent = True
    return primary and independent


def hostile_batch(binding: dict[str, Any]) -> list[dict[str, Any]]:
    base_request = binding["input"]
    base_output = binding["output"]
    records = []

    def attack(name: str, mutate) -> None:
        request = copy.deepcopy(base_request)
        output = copy.deepcopy(base_output)
        mutate(request, output)
        records.append(
            {
                "name": name,
                "rejected_by_primary_and_independent": rejected_twice(
                    request, output
                ),
            }
        )

    attack(
        "unknown_output_field",
        lambda request, output: output.update(unbound=True),
    )
    attack(
        "arm_identity_mismatch",
        lambda request, output: output.update(arm_id="A2"),
    )
    attack(
        "artifact_identity_mismatch",
        lambda request, output: output.update(artifact_id="changed"),
    )
    attack(
        "output_version_changed",
        lambda request, output: output.update(version="changed"),
    )
    attack(
        "negative_cost",
        lambda request, output: output["cost_ledger"].update(
            verification_cpu_ns=-1
        ),
    )
    attack(
        "cost_total_mismatch",
        lambda request, output: output["cost_ledger"].update(total_cpu_ns=0),
    )
    attack(
        "adapter_digest_malformed",
        lambda request, output: output["provenance"].update(
            adapter_sha256="bad"
        ),
    )
    attack(
        "source_digest_mismatch",
        lambda request, output: output["provenance"].update(
            artifact_source_sha256="a" * 64
        ),
    )
    attack(
        "protocol_digest_mismatch",
        lambda request, output: output["provenance"].update(
            protocol_freeze_sha256="b" * 64
        ),
    )
    attack(
        "missing_invocation",
        lambda request, output: output["correctness"][
            "invocation_receipts"
        ].pop(),
    )
    attack(
        "invocation_ordinal_changed",
        lambda request, output: output["correctness"][
            "invocation_receipts"
        ][0].update(ordinal=9),
    )
    attack(
        "invocation_correct_false",
        lambda request, output: output["correctness"][
            "invocation_receipts"
        ][0].update(correct=False),
    )
    attack(
        "all_invocations_false",
        lambda request, output: output["correctness"].update(
            all_invocations_correct=False
        ),
    )
    attack(
        "absolute_error_over_limit",
        lambda request, output: output["correctness"].update(
            max_abs_error=0.00002
        ),
    )
    attack(
        "nonfinite_error",
        lambda request, output: output["correctness"].update(
            max_abs_error=float("nan")
        ),
    )
    attack(
        "alias_check_false",
        lambda request, output: output["correctness"].update(
            alias_storage_checks_passed=False
        ),
    )
    attack(
        "termination_not_natural",
        lambda request, output: output["resources"].update(
            termination="cpu_limit"
        ),
    )
    attack(
        "process_group_not_reaped",
        lambda request, output: output["resources"].update(
            process_group_reaped=False
        ),
    )
    attack(
        "validation_outcome_mounted",
        lambda request, output: output["provenance"].update(
            validation_v6_outcome_mounted=True
        ),
    )
    attack(
        "execution_schedule_changed",
        lambda request, output: request["execution"].update(invocations=2),
    )
    attack(
        "unknown_input_field",
        lambda request, output: request.update(unbound=True),
    )
    attack(
        "input_version_changed",
        lambda request, output: request.update(version="changed"),
    )
    return records


def main() -> None:
    if "--worker" in sys.argv:
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    providers_exact = all(
        sha(HERE / row["path"]) == row["sha256"]
        for row in protocol["provider_records"]
    )
    freeze_exact = (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == protocol["provider_records"]
        and freeze["surface"] == protocol["surface"]
        and freeze["acceptance"] == protocol["acceptance"]
        and freeze[
            "frozen_before_mount_or_contract_runner_implementation_or_execution"
        ]
        is True
    )
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    limits = {
        "wall_limit_seconds": 120,
        "cpu_limit_seconds": 100,
        "rss_limit_kib": 4_500_000,
    }
    receipt = run_metered_tree(
        [str(python), str(__file__), "--worker"],
        cwd=HERE,
        environment={
            "PYTHONHASHSEED": "0",
            "PYTHONWARNINGS": "ignore",
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
        },
        **limits,
    )
    natural = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"] is True
        and "FOUNDRY_PHASE148_WORKER" in receipt["stdout_text"]
    )
    mount = (
        json.loads(WORKER_RESULT.read_text())
        if natural and WORKER_RESULT.exists()
        else {}
    )
    resource_body = {
        "version": "FOUNDRY_SHARED_PROCESS_RESOURCE_RECEIPT_V1",
        "arm_id": "A1",
        "command_sha256": receipt["command_sha256"],
        "cwd_sha256": receipt["cwd_sha256"],
        "wall_ns": receipt["wall_ns"],
        "rusage_user_cpu_ns": receipt["rusage_user_cpu_ns"],
        "rusage_system_cpu_ns": receipt["rusage_system_cpu_ns"],
        "peak_group_rss_kib": receipt["peak_group_rss_kib"],
        "observed_process_count": receipt["observed_process_count"],
        "process_group_reaped": receipt["process_group_reaped"],
        "termination": receipt["termination"],
        "limits": receipt["limits"],
        "stdout_sha256": receipt["stdout_sha256"],
        "stderr_sha256": receipt["stderr_sha256"],
    }
    resource_receipt_id = hashlib.sha256(
        canonical(resource_body)
    ).hexdigest()
    projection = {
        key: resource_body[key]
        for key in (
            "wall_ns",
            "peak_group_rss_kib",
            "observed_process_count",
            "process_group_reaped",
            "termination",
        )
    }
    fixed = json.loads(FIXED.read_text())
    sealed = {
        "candidate_library_sha256": mount.get("library_sha256", "0" * 64),
        "fixed_portfolio_sha256": fixed["fixed_portfolio_sha256"],
        "protocol_freeze_sha256": sha(PROTOCOL),
    }
    bindings = []
    primary_accepts = independent_accepts = 0
    if natural:
        for row in mount["rows"]:
            request = {
                "version": "FOUNDRY_ARM_ADAPTER_INPUT_V1",
                "arm_id": "A1",
                "artifact": {
                    "artifact_id": row["artifact_id"],
                    "source_sha256": row["source_record_sha256"],
                    "family": row["family"],
                    "repository": row["repository"],
                    "semantic_domain": row["semantic_domain"],
                    "graph_ir_sha256": row["graph_sha256"],
                    "shape_seed_sha256": row["shape_seed_sha256"],
                },
                "budgets": {
                    "wall_limit_seconds": 120,
                    "cpu_limit_seconds": 100,
                    "rss_limit_kib": 4_500_000,
                    "search_unit_limit": 3,
                },
                "execution": {
                    "invocations": 3,
                    "pairing_unit": "artifact",
                    "retain_individual_invocation_receipts": True,
                },
                "sealed_inputs": sealed,
            }
            output = {
                "version": "FOUNDRY_ARM_ADAPTER_OUTPUT_V1",
                "arm_id": "A1",
                "artifact_id": row["artifact_id"],
                "status": "PASS",
                "state_policy": {
                    "state_before_sha256": row["state_before_sha256"],
                    "state_after_sha256": row["state_after_sha256"],
                    "library_retained_across_artifacts": True,
                },
                "tool_receipts": row["tool_receipts"],
                "cost_ledger": row["cost_ledger"],
                "correctness": {
                    "invocation_receipts": [
                        {
                            "ordinal": item["ordinal"],
                            "output_sha256": item["actual_sha256"],
                            "correct": item["correct"],
                        }
                        for item in row["invocation_receipts"]
                    ],
                    "all_invocations_correct": all(
                        item["correct"]
                        for item in row["invocation_receipts"]
                    ),
                    "max_abs_error": row["max_abs_error"],
                    "alias_storage_checks_passed": row[
                        "alias_storage_checks_passed"
                    ],
                },
                "resources": projection,
                "provenance": {
                    "adapter_sha256": sha(ADAPTER),
                    "artifact_source_sha256": row[
                        "source_record_sha256"
                    ],
                    "protocol_freeze_sha256": sha(PROTOCOL),
                    "validation_v6_outcome_mounted": False,
                },
            }
            raw_input = canonical(request)
            raw_output = canonical(output)
            parsed = parse_input(raw_input)
            parse_output(raw_output, parsed)
            primary_accepts += 1
            independent_verify(raw_input, raw_output)
            independent_accepts += 1
            bindings.append(
                {
                    "artifact_id": row["artifact_id"],
                    "shared_resource_receipt_id": resource_receipt_id,
                    "input_sha256": hashlib.sha256(raw_input).hexdigest(),
                    "output_sha256": hashlib.sha256(raw_output).hexdigest(),
                    "input": request,
                    "output": output,
                }
            )
    hostile = hostile_batch(bindings[0]) if bindings else []
    summary = mount.get("summary", {})
    expected = protocol["surface"]
    checks = {
        "protocol_freeze_and_providers_exact": providers_exact and freeze_exact,
        "meter_hostile_selftest": meter_test["pass"],
        "complete_process_tree_cpu_rss_wall_and_reaping": (
            natural
            and receipt["observed_process_count"] >= 1
            and receipt["peak_group_rss_kib"] > 0
            and receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "all_23_graph_rows_pass": (
            mount.get("status") == "A1_FULL_RUNTIME_MOUNT_COMPONENT_PASS"
            and summary.get("graphs") == expected["graphs"]
            and summary.get("call_function_invocations")
            == expected["call_function_invocations"]
            and summary.get("historically_unsupported_or_failed")
            == expected["historically_unsupported_or_failed"]
        ),
        "selection_and_fallback_surface_exact": (
            summary.get("eligible_graphs") == expected["eligible_graphs"]
            and summary.get("eligible_fold_sites")
            == expected["eligible_fold_sites"]
            and sum(not row["tool_receipts"] for row in mount.get("rows", []))
            == 22
        ),
        "all_69_whole_graph_executions_pass": (
            summary.get("whole_graph_executions")
            == expected["whole_graph_executions"]
            and all(
                item["correct"]
                for row in mount.get("rows", [])
                for item in row["invocation_receipts"]
            )
        ),
        "all_9_fold_checks_pass": (
            summary.get("fold_checks") == expected["fold_checks"]
            and all(
                item["max_abs_error"]
                <= protocol["runtime_correctness"][
                    "maximum_absolute_error"
                ]
                and item["alias_storage_checks_passed"]
                for row in mount.get("rows", [])
                for item in row["fold_receipts"]
            )
        ),
        "exactly_three_tool_uses_on_one_artifact": (
            summary.get("tool_direct_uses")
            == protocol["accounting"]["tool_direct_uses"]
            and sum(bool(row["tool_receipts"]) for row in mount.get("rows", []))
            == 1
        ),
        "candidate_generation_charged_once": (
            sum(
                row["cost_ledger"]["candidate_generation_cpu_ns"] > 0
                for row in mount.get("rows", [])
            )
            == 1
        ),
        "all_cost_ledgers_sum_and_are_positive": all(
            row["cost_ledger"]["total_cpu_ns"]
            == sum(
                value
                for key, value in row["cost_ledger"].items()
                if key != "total_cpu_ns"
            )
            and row["cost_ledger"]["total_cpu_ns"] > 0
            for row in mount.get("rows", [])
        ),
        "retained_library_immutable": all(
            row["state_before_sha256"]
            == row["state_after_sha256"]
            == mount.get("library_sha256")
            for row in mount.get("rows", [])
        ),
        "all_23_primary_contract_pairs_accept": primary_accepts == 23,
        "all_23_independent_contract_pairs_accept": independent_accepts == 23,
        "all_binding_digests_unique": (
            len({row["input_sha256"] for row in bindings}) == 23
            and len({row["output_sha256"] for row in bindings}) == 23
        ),
        "single_shared_resource_receipt_multiplier_one": (
            len(bindings) == 23
            and all(
                row["shared_resource_receipt_id"] == resource_receipt_id
                for row in bindings
            )
        ),
        "all_22_hostile_contract_mutations_rejected_by_both": (
            len(hostile) == 22
            and all(
                row["rejected_by_primary_and_independent"]
                for row in hostile
            )
        ),
        "scientific_boundary_preserved": mount.get("scientific_boundary")
        == {
            "post_failure_numerical_amendment_disclosed": True,
            "adapted_calibration_control_not_unchanged_v5_1": True,
            "exactly_one_calibration_signature_added": True,
            "real_matched_subgraphs_executed": True,
            "whole_transformed_graph_materialized": False,
            "heldout_generalization_measured": False,
            "fixed_portfolio_beaten": False,
        },
        "validation_v6_unread": mount.get("validation_v6_accessed") is False,
        "prospective_unauthorized": mount.get(
            "prospective_trial_authorized"
        )
        is False,
    }
    operationally_valid = all(checks.values())
    payload = {
        "version": "FOUNDRY_A1_FULL_RUNTIME_CONTRACT_RESULT_V1",
        "status": (
            "A1_FULL_RUNTIME_CONTRACT_BATCH_PASS"
            if operationally_valid
            else "A1_FULL_RUNTIME_CONTRACT_BATCH_INVALID"
        ),
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "runner_records": [
            {
                "path": pathlib.Path(__file__).name,
                "sha256": sha(pathlib.Path(__file__)),
            },
            {
                "path": ADAPTER.name,
                "sha256": sha(ADAPTER),
            },
        ],
        "limits": limits,
        "meter_selftest": meter_test,
        "shared_resource_receipt": {
            "receipt_id": resource_receipt_id,
            "body": resource_body,
        },
        "resource_receipt_multiplier": 1,
        "checks": checks,
        "operationally_valid": operationally_valid,
        "mount": mount,
        "contract_bindings": bindings,
        "hostile_rejections": hostile,
        "aggregate_accounting": {
            "artifact_outputs": len(bindings),
            "primary_accepts": primary_accepts,
            "independent_accepts": independent_accepts,
            "unique_resource_receipts_charged": 1 if natural else 0,
            "resource_receipt_references": len(bindings),
            "resource_multiplier_applied": 1,
            "tool_direct_uses": summary.get("tool_direct_uses", 0),
            "candidate_generation_charged_artifacts": sum(
                row["cost_ledger"]["candidate_generation_cpu_ns"] > 0
                for row in mount.get("rows", [])
            ),
        },
        "integration": {
            "A1": "PRODUCTION_INTEGRATED_ADAPTED_V5_1_FOLD_CONTROL",
            "production_integrated_arms": 8 if operationally_valid else 7,
            "required_arms": 10,
            "phase146_remains_failed": True,
            "phase147_post_failure_remediation_passed": True,
        },
        "P3": {
            "A1_complete_contract_batch_ready": operationally_valid,
            "all_required_arms_integrated_and_metered": False,
            "complete": False,
        },
        "claim_boundary": protocol["claim_boundary"],
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_bytes(canonical(payload) + b"\n")
    print(
        "FOUNDRY_PHASE148_A1_FULL_RUNTIME_CONTRACT"
        f" status={payload['status']}"
        f" base_pairs={primary_accepts}/{independent_accepts}"
        f" executions={summary.get('whole_graph_executions', 0)}"
        f" folds={summary.get('fold_checks', 0)}"
        f" hostile={sum(row['rejected_by_primary_and_independent'] for row in hostile)}/22"
        f" integrated={payload['integration']['production_integrated_arms']}/10"
        " prospective=false"
    )
    if not operationally_valid:
        raise RuntimeError(
            "A1 full runtime contract invalid: "
            + canonical(
                {
                    "failed": [
                        key for key, value in checks.items() if not value
                    ],
                    "stderr": receipt["stderr_text"],
                }
            ).decode()
        )


if __name__ == "__main__":
    main()
