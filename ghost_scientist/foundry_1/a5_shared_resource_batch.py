#!/usr/bin/env python3
"""Assemble A5 outputs under one hash-bound process resource receipt."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib

from arm_adapter_contract import parse_input, parse_output
from independent_arm_adapter_contract import verify as independent_verify


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/A5_SHARED_RESOURCE_BATCH_PROTOCOL_V1.json"
)
MOUNT = HERE / "results/phase101_a5_stitch_runtime_conformance.json"
RESOURCE = (
    HERE / "results/phase102_a5_stitch_runtime_resource_audit.json"
)
LIBRARY = HERE / "results/a5_stitch_calibration_library_v1.json"
FIXED = HERE / "results/forged_diversity_tools.json"
ADAPTER = HERE / "a5_stitch_runtime_mount.py"


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value: object) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def authenticate(protocol: dict) -> None:
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")


def assemble() -> dict:
    protocol = json.loads(PROTOCOL.read_text())
    authenticate(protocol)
    mount = json.loads(MOUNT.read_text())["runtime_receipt"]
    resource = json.loads(RESOURCE.read_text())["mount_receipt"]
    fixed = json.loads(FIXED.read_text())
    resource_body = {
        "version": "FOUNDRY_SHARED_PROCESS_RESOURCE_RECEIPT_V1",
        "arm_id": "A5",
        "command_sha256": resource["command_sha256"],
        "cwd_sha256": resource["cwd_sha256"],
        "wall_ns": resource["wall_ns"],
        "rusage_user_cpu_ns": resource["rusage_user_cpu_ns"],
        "rusage_system_cpu_ns": resource["rusage_system_cpu_ns"],
        "peak_group_rss_kib": resource["peak_group_rss_kib"],
        "observed_process_count": resource["observed_process_count"],
        "process_group_reaped": resource["process_group_reaped"],
        "termination": resource["termination"],
        "limits": resource["limits"],
        "stdout_sha256": resource["stdout_sha256"],
        "stderr_sha256": resource["stderr_sha256"],
    }
    receipt_id = digest(resource_body)
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
    sealed = {
        "candidate_library_sha256": sha(LIBRARY),
        "fixed_portfolio_sha256": fixed["fixed_portfolio_sha256"],
        "protocol_freeze_sha256": sha(PROTOCOL),
    }
    bindings = []
    for row in mount["rows"]:
        request = {
            "version": "FOUNDRY_ARM_ADAPTER_INPUT_V1",
            "arm_id": "A5",
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
                "wall_limit_seconds": 90,
                "cpu_limit_seconds": 75,
                "rss_limit_kib": 4500000,
                "search_unit_limit": 2000,
            },
            "execution": {
                "invocations": 3,
                "pairing_unit": "artifact",
                "retain_individual_invocation_receipts": True,
            },
            "sealed_inputs": sealed,
        }
        tool = row["tool_receipts"][0]
        output = {
            "version": "FOUNDRY_ARM_ADAPTER_OUTPUT_V1",
            "arm_id": "A5",
            "artifact_id": row["artifact_id"],
            "status": "PASS",
            "state_policy": {
                "state_before_sha256": row["state_before_sha256"],
                "state_after_sha256": row["state_after_sha256"],
                "library_retained_across_artifacts": True,
            },
            "tool_receipts": [
                {
                    "tool_sha256": tool["tool_sha256"],
                    "action": (
                        "reused" if tool["direct_use_count"] else "none"
                    ),
                    "direct_use_count": tool["direct_use_count"],
                }
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
                    item["correct"] for item in row["invocation_receipts"]
                ),
                "max_abs_error": row["max_abs_error"],
                "alias_storage_checks_passed": row[
                    "alias_storage_checks_passed"
                ],
            },
            "resources": projection,
            "provenance": {
                "adapter_sha256": sha(ADAPTER),
                "artifact_source_sha256": row["source_record_sha256"],
                "protocol_freeze_sha256": sealed[
                    "protocol_freeze_sha256"
                ],
                "validation_v6_outcome_mounted": False,
            },
        }
        raw_input = canonical(request)
        raw_output = canonical(output)
        parsed = parse_input(raw_input)
        parse_output(raw_output, parsed)
        independent_verify(raw_input, raw_output)
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
    batch = {
        "version": protocol["batch_version"],
        "arm_id": "A5",
        "shared_resource_receipts": [
            {"receipt_id": receipt_id, "body": resource_body}
        ],
        "artifact_bindings": bindings,
        "aggregate_accounting": {
            "artifact_outputs": len(bindings),
            "unique_resource_receipts_charged": 1,
            "resource_receipt_references": len(bindings),
            "resource_multiplier_applied": 1,
            "direct_structural_uses": sum(
                row["output"]["tool_receipts"][0]["direct_use_count"]
                for row in bindings
            ),
            "candidate_generation_charged_artifacts": sum(
                row["output"]["cost_ledger"][
                    "candidate_generation_cpu_ns"
                ]
                > 0
                for row in bindings
            ),
        },
        "scientific_boundary": {
            "normalized_rewrite_reversibility": True,
            "rewritten_tensor_runtime_executed": False,
            "tensor_primitive_invented": False,
            "heldout_generalization_measured": False,
            "fixed_portfolio_beaten": False,
        },
        "base_contract_primary_accepts": len(bindings),
        "base_contract_independent_accepts": len(bindings),
        "production_integration_classification": (
            "PRODUCTION_INTEGRATED_CALIBRATION_STRUCTURAL_CONTROL"
        ),
        "P3_complete": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    verify_primary(batch)
    return batch


def verify_primary(batch: dict) -> dict:
    if set(batch) != {
        "version",
        "arm_id",
        "shared_resource_receipts",
        "artifact_bindings",
        "aggregate_accounting",
        "scientific_boundary",
        "base_contract_primary_accepts",
        "base_contract_independent_accepts",
        "production_integration_classification",
        "P3_complete",
        "validation_v6_accessed",
        "prospective_trial_authorized",
    }:
        raise ValueError("batch fields")
    if not (
        batch["version"] == "FOUNDRY_A5_ARM_ADAPTER_BATCH_V1"
        and batch["arm_id"] == "A5"
        and len(batch["shared_resource_receipts"]) == 1
        and len(batch["artifact_bindings"]) == 23
    ):
        raise ValueError("batch identity or cardinality")
    shared = batch["shared_resource_receipts"][0]
    if set(shared) != {"receipt_id", "body"} or digest(
        shared["body"]
    ) != shared["receipt_id"]:
        raise ValueError("shared receipt identity")
    body = shared["body"]
    if not (
        body["arm_id"] == "A5"
        and body["termination"] == "natural"
        and body["process_group_reaped"] is True
    ):
        raise ValueError("shared receipt relation")
    projection = {
        key: body[key]
        for key in (
            "wall_ns",
            "peak_group_rss_kib",
            "observed_process_count",
            "process_group_reaped",
            "termination",
        )
    }
    artifacts = set()
    inputs = set()
    outputs = set()
    state = tool = protocol_hash = None
    direct_uses = candidate_charges = 0
    for binding in batch["artifact_bindings"]:
        if set(binding) != {
            "artifact_id",
            "shared_resource_receipt_id",
            "input_sha256",
            "output_sha256",
            "input",
            "output",
        }:
            raise ValueError("binding fields")
        raw_input = canonical(binding["input"])
        raw_output = canonical(binding["output"])
        if not (
            binding["shared_resource_receipt_id"] == shared["receipt_id"]
            and hashlib.sha256(raw_input).hexdigest()
            == binding["input_sha256"]
            and hashlib.sha256(raw_output).hexdigest()
            == binding["output_sha256"]
            and binding["output"]["resources"] == projection
        ):
            raise ValueError("binding relation")
        parsed = parse_input(raw_input)
        parse_output(raw_output, parsed)
        output = binding["output"]
        policy = output["state_policy"]
        candidate = binding["input"]["sealed_inputs"][
            "candidate_library_sha256"
        ]
        if not (
            policy["state_before_sha256"]
            == policy["state_after_sha256"]
            == candidate
            and policy["library_retained_across_artifacts"] is True
        ):
            raise ValueError("A5 retained state")
        tools = output["tool_receipts"]
        if len(tools) != 1 or tools[0]["action"] != (
            "reused" if tools[0]["direct_use_count"] else "none"
        ):
            raise ValueError("A5 tool relation")
        state = state or candidate
        tool = tool or tools[0]["tool_sha256"]
        protocol_hash = protocol_hash or binding["input"]["sealed_inputs"][
            "protocol_freeze_sha256"
        ]
        if not (
            candidate == state
            and tools[0]["tool_sha256"] == tool
            and binding["input"]["sealed_inputs"][
                "protocol_freeze_sha256"
            ]
            == protocol_hash
            and output["provenance"]["protocol_freeze_sha256"]
            == protocol_hash
        ):
            raise ValueError("A5 sealed state drift")
        direct_uses += tools[0]["direct_use_count"]
        candidate_charges += (
            output["cost_ledger"]["candidate_generation_cpu_ns"] > 0
        )
        artifacts.add(binding["artifact_id"])
        inputs.add(binding["input_sha256"])
        outputs.add(binding["output_sha256"])
    if len(artifacts) != 23 or len(inputs) != 23 or len(outputs) != 23:
        raise ValueError("duplicate binding")
    expected_accounting = {
        "artifact_outputs": 23,
        "unique_resource_receipts_charged": 1,
        "resource_receipt_references": 23,
        "resource_multiplier_applied": 1,
        "direct_structural_uses": 329,
        "candidate_generation_charged_artifacts": 1,
    }
    if (
        direct_uses != 329
        or candidate_charges != 1
        or batch["aggregate_accounting"] != expected_accounting
    ):
        raise ValueError("aggregate accounting")
    if batch["scientific_boundary"] != {
        "normalized_rewrite_reversibility": True,
        "rewritten_tensor_runtime_executed": False,
        "tensor_primitive_invented": False,
        "heldout_generalization_measured": False,
        "fixed_portfolio_beaten": False,
    }:
        raise ValueError("scientific boundary")
    if not (
        batch["base_contract_primary_accepts"]
        == batch["base_contract_independent_accepts"]
        == 23
        and batch["production_integration_classification"]
        == "PRODUCTION_INTEGRATED_CALIBRATION_STRUCTURAL_CONTROL"
        and batch["P3_complete"] is False
        and batch["validation_v6_accessed"] is False
        and batch["prospective_trial_authorized"] is False
    ):
        raise ValueError("claim boundary")
    return {
        "status": "A5_SHARED_RESOURCE_BATCH_PRIMARY_PASS",
        "artifacts": 23,
        "direct_structural_uses": 329,
        "unique_resource_receipts_charged": 1,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--summary-only", action="store_true")
    args = parser.parse_args()
    batch = assemble()
    if args.summary_only:
        batch = {
            "version": batch["version"],
            "arm_id": batch["arm_id"],
            "artifact_outputs": len(batch["artifact_bindings"]),
            "aggregate_accounting": batch["aggregate_accounting"],
            "production_integration_classification": batch[
                "production_integration_classification"
            ],
            "P3_complete": batch["P3_complete"],
            "validation_v6_accessed": batch["validation_v6_accessed"],
        }
    print(canonical(batch).decode())


if __name__ == "__main__":
    main()
