#!/usr/bin/env python3
"""Assemble A4 v1 outputs under one hash-bound process resource receipt."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib

from arm_adapter_contract import parse_input, parse_output
from independent_arm_adapter_contract import verify as independent_verify


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/A4_SHARED_RESOURCE_BATCH_PROTOCOL_V1.json"
)
MOUNT = HERE / "results/phase95_a4_replay_runtime_conformance.json"
RESOURCE = HERE / "results/phase96_a4_replay_runtime_resource_audit.json"
FREEZE = HERE / "results/pareto_remediation_v9_freeze.json"
LIBRARY = HERE / "results/forged_diversity_tools.json"
ADAPTER = HERE / "a4_replay_runtime_mount.py"


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
    library = json.loads(LIBRARY.read_text())
    resource_body = {
        "version": "FOUNDRY_SHARED_PROCESS_RESOURCE_RECEIPT_V1",
        "arm_id": "A4",
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
        "fixed_portfolio_sha256": library["fixed_portfolio_sha256"],
        "protocol_freeze_sha256": sha(FREEZE),
    }
    bindings = []
    for row in mount["rows"]:
        request = {
            "version": "FOUNDRY_ARM_ADAPTER_INPUT_V1",
            "arm_id": "A4",
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
        output = {
            "version": "FOUNDRY_ARM_ADAPTER_OUTPUT_V1",
            "arm_id": "A4",
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
                    "action": (
                        "reused" if item["direct_use_count"] else "none"
                    ),
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
        "arm_id": "A4",
        "shared_resource_receipts": [
            {"receipt_id": receipt_id, "body": resource_body}
        ],
        "artifact_bindings": bindings,
        "aggregate_accounting": {
            "artifact_outputs": len(bindings),
            "unique_resource_receipts_charged": 1,
            "resource_receipt_references": len(bindings),
            "resource_multiplier_applied": 1,
        },
        "base_contract_primary_accepts": len(bindings),
        "base_contract_independent_accepts": len(bindings),
        "production_integration_classification": (
            "PRODUCTION_INTEGRATED_CALIBRATION_ARM"
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
        "base_contract_primary_accepts",
        "base_contract_independent_accepts",
        "production_integration_classification",
        "P3_complete",
        "validation_v6_accessed",
        "prospective_trial_authorized",
    }:
        raise ValueError("batch fields")
    if (
        batch["version"] != "FOUNDRY_A4_ARM_ADAPTER_BATCH_V1"
        or batch["arm_id"] != "A4"
        or len(batch["shared_resource_receipts"]) != 1
        or len(batch["artifact_bindings"]) != 23
    ):
        raise ValueError("batch identity or cardinality")
    shared = batch["shared_resource_receipts"][0]
    if (
        set(shared) != {"receipt_id", "body"}
        or digest(shared["body"]) != shared["receipt_id"]
    ):
        raise ValueError("shared receipt identity")
    body = shared["body"]
    if not (
        body["arm_id"] == "A4"
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
    outputs = set()
    state = None
    for binding in batch["artifact_bindings"]:
        raw_input = canonical(binding["input"])
        raw_output = canonical(binding["output"])
        if (
            binding["shared_resource_receipt_id"] != shared["receipt_id"]
            or hashlib.sha256(raw_input).hexdigest()
            != binding["input_sha256"]
            or hashlib.sha256(raw_output).hexdigest()
            != binding["output_sha256"]
            or binding["output"]["resources"] != projection
        ):
            raise ValueError("binding relation")
        parsed = parse_input(raw_input)
        parse_output(raw_output, parsed)
        policy = binding["output"]["state_policy"]
        if not (
            policy["state_before_sha256"]
            == policy["state_after_sha256"]
            == binding["input"]["sealed_inputs"][
                "candidate_library_sha256"
            ]
            and policy["library_retained_across_artifacts"] is True
        ):
            raise ValueError("A4 retained state")
        tools = binding["output"]["tool_receipts"]
        if len(tools) != 3 or any(
            item["action"]
            != ("reused" if item["direct_use_count"] else "none")
            for item in tools
        ):
            raise ValueError("A4 tool action relation")
        state = state or policy["state_before_sha256"]
        if policy["state_before_sha256"] != state:
            raise ValueError("A4 library changed across artifacts")
        artifacts.add(binding["artifact_id"])
        outputs.add(binding["output_sha256"])
    if len(artifacts) != 23 or len(outputs) != 23:
        raise ValueError("duplicate binding")
    if batch["aggregate_accounting"] != {
        "artifact_outputs": 23,
        "unique_resource_receipts_charged": 1,
        "resource_receipt_references": 23,
        "resource_multiplier_applied": 1,
    }:
        raise ValueError("aggregate accounting")
    if not (
        batch["base_contract_primary_accepts"]
        == batch["base_contract_independent_accepts"]
        == 23
        and batch["production_integration_classification"]
        == "PRODUCTION_INTEGRATED_CALIBRATION_ARM"
        and batch["P3_complete"] is False
        and batch["validation_v6_accessed"] is False
        and batch["prospective_trial_authorized"] is False
    ):
        raise ValueError("claim boundary")
    return {
        "status": "A4_SHARED_RESOURCE_BATCH_PRIMARY_PASS",
        "artifacts": 23,
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
            "shared_resource_receipt_id": batch[
                "shared_resource_receipts"
            ][0]["receipt_id"],
            "aggregate_accounting": batch["aggregate_accounting"],
            "base_contract_primary_accepts": batch[
                "base_contract_primary_accepts"
            ],
            "base_contract_independent_accepts": batch[
                "base_contract_independent_accepts"
            ],
            "production_integration_classification": batch[
                "production_integration_classification"
            ],
            "P3_complete": batch["P3_complete"],
            "validation_v6_accessed": batch["validation_v6_accessed"],
        }
    print(canonical(batch).decode())


if __name__ == "__main__":
    main()
