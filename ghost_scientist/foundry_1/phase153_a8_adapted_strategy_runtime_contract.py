#!/usr/bin/env python3
"""Meter, falsify, and integrate the frozen adapted A8 strategy batch."""

from __future__ import annotations

import hashlib
import json
import pathlib
import sys

from a8_adapted_strategy_runtime_mount import run as run_mount
from arm_adapter_contract import parse_input, parse_output
from independent_arm_adapter_contract import verify as independent_verify
from phase151_a6_typed_anti_unification_runtime_contract import hostile_batch
from resource_meter_v2 import run_metered_tree, selftest


HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A8_ADAPTED_STRATEGY_RUNTIME_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/a8_adapted_strategy_runtime_v1_freeze.json"
FIXED = HERE / "results/forged_diversity_tools.json"
ADAPTER = HERE / "a8_adapted_strategy_runtime_mount.py"
INDEPENDENT = HERE / "independent_a8_strategy_runtime.py"
HOSTILE_PROVIDER = (
    HERE / "phase151_a6_typed_anti_unification_runtime_contract.py"
)
WORKER_RESULT = (
    HERE / "results/phase153_a8_adapted_strategy_runtime_worker.json"
)
RESULT = (
    HERE / "results/phase153_a8_adapted_strategy_runtime_contract.json"
)


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
        "FOUNDRY_PHASE153_WORKER"
        f" graphs={payload['summary']['graphs']}"
        f" applications={payload['summary']['eligible_strategy_applications']}"
        f" executions={payload['summary']['whole_graph_executions']}"
        f" tool_uses={payload['summary']['strategy_tool_direct_uses']}"
    )


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
        and freeze["selected_strategy"] == protocol["selected_strategy"]
        and freeze["surface"] == protocol["surface"]
        and freeze["runtime_policy"] == protocol["runtime_policy"]
        and freeze["acceptance"] == protocol["acceptance"]
        and freeze["pristine_preregistration"] is False
    )
    python = pathlib.Path(sys.executable).resolve()
    meter_test = selftest(str(python), ROOT)
    frozen_limits = protocol["resource_limits"]
    limits = {
        "wall_limit_seconds": frozen_limits["wall_seconds"],
        "cpu_limit_seconds": frozen_limits["cpu_seconds"],
        "rss_limit_kib": frozen_limits["rss_kib"],
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
        and "FOUNDRY_PHASE153_WORKER" in receipt["stdout_text"]
    )
    mount = (
        json.loads(WORKER_RESULT.read_text())
        if natural and WORKER_RESULT.exists()
        else {}
    )
    resource_body = {
        "version": "FOUNDRY_SHARED_PROCESS_RESOURCE_RECEIPT_V1",
        "arm_id": "A8",
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
    receipt_id = hashlib.sha256(canonical(resource_body)).hexdigest()
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
        "candidate_library_sha256": mount.get(
            "library_sha256", "0" * 64
        ),
        "fixed_portfolio_sha256": fixed["fixed_portfolio_sha256"],
        "protocol_freeze_sha256": sha(PROTOCOL),
    }
    bindings = []
    primary_accepts = independent_accepts = 0
    if natural:
        for row in mount["rows"]:
            request = {
                "version": "FOUNDRY_ARM_ADAPTER_INPUT_V1",
                "arm_id": "A8",
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
                    "wall_limit_seconds": limits["wall_limit_seconds"],
                    "cpu_limit_seconds": limits["cpu_limit_seconds"],
                    "rss_limit_kib": limits["rss_limit_kib"],
                    "search_unit_limit": 40320,
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
                "arm_id": "A8",
                "artifact_id": row["artifact_id"],
                "status": "PASS",
                "state_policy": {
                    "state_before_sha256": row["state_before_sha256"],
                    "state_after_sha256": row["state_after_sha256"],
                    "library_retained_across_artifacts": True,
                },
                "tool_receipts": [
                    {
                        "tool_sha256": item["tool_sha256"],
                        "action": item["action"],
                        "direct_use_count": item["direct_use_count"],
                    }
                    for item in row["tool_receipts"]
                ],
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
                    "shared_resource_receipt_id": receipt_id,
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
            mount.get("status") == "A8_ADAPTED_STRATEGY_RUNTIME_MOUNT_PASS"
            and summary.get("graphs") == expected["graphs"]
            and summary.get("call_function_invocations")
            == expected["call_function_invocations"]
            and summary.get("historically_unsupported_or_failed")
            == expected["historically_unsupported_or_failed"]
        ),
        "exact_frozen_strategy_surface": (
            summary.get("eligible_graphs") == expected["eligible_graphs"]
            and summary.get("eligible_strategy_applications")
            == expected["eligible_strategy_applications"]
            and summary.get("covered_graph_nodes")
            == expected["covered_graph_nodes"]
        ),
        "independent_recipe_audits_pass": all(
            row["transform_receipt"]["independent_audit"]["executor_nodes"]
            == row["strategy_applications"]
            and row["transform_receipt"]["independent_audit"][
                "graph_lint_passed"
            ]
            for row in mount.get("rows", [])
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
        "exactly_60_strategy_tool_calls": (
            summary.get("strategy_tool_direct_uses")
            == expected["strategy_tool_direct_uses"]
            and sum(
                item["strategy_tool_executions"]
                for row in mount.get("rows", [])
                for item in row["invocation_receipts"]
            )
            == expected["strategy_tool_direct_uses"]
        ),
        "all_outputs_within_frozen_error": (
            summary.get("maximum_absolute_error", float("inf"))
            <= protocol["runtime_correctness"]["maximum_absolute_error"]
        ),
        "strategy_synthesis_charged_once": (
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
        "retained_strategy_immutable": all(
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
                row["shared_resource_receipt_id"] == receipt_id
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
            "new_adapted_control_not_EggMind": True,
            "post_exploratory_not_pristine": True,
            "unchanged_strong_fixed_tool_grammar": True,
            "strategy_order_beats_supplied_order_on_applications_only": True,
            "fixed_tool_portfolio_beaten": False,
            "real_selected_paths_replaced": True,
            "strategy_transformed_whole_graphs_executed": True,
            "new_tool_constructed": False,
            "heldout_generalization_measured": False,
        },
        "validation_v6_unread": mount.get("validation_v6_accessed") is False,
        "prospective_unauthorized": mount.get(
            "prospective_trial_authorized"
        )
        is False,
    }
    valid = all(checks.values())
    payload = {
        "version": "FOUNDRY_A8_ADAPTED_STRATEGY_RUNTIME_CONTRACT_V1",
        "status": (
            "A8_ADAPTED_STRATEGY_RUNTIME_CONTRACT_PASS"
            if valid
            else "A8_ADAPTED_STRATEGY_RUNTIME_CONTRACT_INVALID"
        ),
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "runner_records": [
            {"path": pathlib.Path(__file__).name, "sha256": sha(pathlib.Path(__file__))},
            {"path": ADAPTER.name, "sha256": sha(ADAPTER)},
            {"path": INDEPENDENT.name, "sha256": sha(INDEPENDENT)},
            {"path": HOSTILE_PROVIDER.name, "sha256": sha(HOSTILE_PROVIDER)},
        ],
        "limits": limits,
        "meter_selftest": meter_test,
        "shared_resource_receipt": {
            "receipt_id": receipt_id,
            "body": resource_body,
        },
        "resource_receipt_multiplier": 1,
        "checks": checks,
        "operationally_valid": valid,
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
            "strategy_tool_direct_uses": summary.get(
                "strategy_tool_direct_uses", 0
            ),
            "strategy_synthesis_charged_artifacts": sum(
                row["cost_ledger"]["candidate_generation_cpu_ns"] > 0
                for row in mount.get("rows", [])
            ),
        },
        "integration": {
            "A8": (
                "PRODUCTION_INTEGRATED_NEW_ADAPTED_STRATEGY_CONTROL"
                if valid
                else "INCOMPLETE_PARTIAL_BOUNDARY_NOT_ADAPTED"
            ),
            "production_integrated_arms": 10 if valid else 9,
            "required_arms": 10,
        },
        "P3": {
            "A8_complete_contract_batch_ready": valid,
            "all_required_arms_integrated_and_metered": valid,
            "complete": valid,
        },
        "claim_boundary": protocol["claim_boundary"],
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_bytes(canonical(payload) + b"\n")
    print(
        "FOUNDRY_PHASE153_A8_RUNTIME_CONTRACT"
        f" status={payload['status']}"
        f" base_pairs={primary_accepts}/{independent_accepts}"
        f" applications={summary.get('eligible_strategy_applications', 0)}"
        f" executions={summary.get('whole_graph_executions', 0)}"
        f" tool_uses={summary.get('strategy_tool_direct_uses', 0)}"
        f" hostile={sum(row['rejected_by_primary_and_independent'] for row in hostile)}/22"
        f" integrated={payload['integration']['production_integrated_arms']}/10"
        " prospective=false"
    )
    if not valid:
        raise RuntimeError(
            "A8 runtime contract invalid: "
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
