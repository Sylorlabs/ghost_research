#!/usr/bin/env python3
"""Assemble strict v1 outputs under one hash-bound arm resource receipt."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib

from arm_adapter_contract import parse_input, parse_output
from independent_arm_adapter_contract import verify as independent_verify


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/SHARED_RESOURCE_RECEIPT_OVERLAY_V1.json"
)
MOUNT_RESULT = (
    HERE / "results/phase89_framework_runtime_mount_conformance.json"
)
RESOURCE_RESULT = (
    HERE / "results/phase90_framework_runtime_mount_resource_audit.json"
)
ADAPTER_SHA256 = hashlib.sha256(
    (HERE / "framework_runtime_mount.py").read_bytes()
).hexdigest()


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def digest(value: object) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def file_sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def authenticate(protocol: dict) -> None:
    for row in protocol["provider_records"]:
        if file_sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider hash mismatch: {row['path']}")


def shared_receipt(arm_id: str, meter: dict) -> dict:
    body = {
        "version": "FOUNDRY_SHARED_PROCESS_RESOURCE_RECEIPT_V1",
        "arm_id": arm_id,
        "command_sha256": meter["command_sha256"],
        "cwd_sha256": meter["cwd_sha256"],
        "wall_ns": meter["wall_ns"],
        "rusage_user_cpu_ns": meter["rusage_user_cpu_ns"],
        "rusage_system_cpu_ns": meter["rusage_system_cpu_ns"],
        "peak_group_rss_kib": meter["peak_group_rss_kib"],
        "observed_process_count": meter["observed_process_count"],
        "process_group_reaped": meter["process_group_reaped"],
        "termination": meter["termination"],
        "limits": meter["limits"],
        "stdout_sha256": meter["stdout_sha256"],
        "stderr_sha256": meter["stderr_sha256"],
    }
    return {"receipt_id": digest(body), "body": body}


def request_for(arm_id: str, row: dict, protocol: dict) -> dict:
    sealed = json.loads(
        (
            HERE
            / "arm_adapter_fixtures/FRAMEWORK_RUNTIME_MOUNT_PROTOCOL_V1.json"
        ).read_text()
    )["sealed_inputs"]
    return {
        "version": "FOUNDRY_ARM_ADAPTER_INPUT_V1",
        "arm_id": arm_id,
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
        "sealed_inputs": {
            "candidate_library_sha256": sealed[
                "candidate_library_sha256"
            ],
            "fixed_portfolio_sha256": sealed["fixed_portfolio_sha256"],
            "protocol_freeze_sha256": sealed["protocol_freeze_sha256"],
        },
    }


def output_for(
    arm_id: str, row: dict, request: dict, resource: dict
) -> dict:
    return {
        "version": "FOUNDRY_ARM_ADAPTER_OUTPUT_V1",
        "arm_id": arm_id,
        "artifact_id": row["artifact_id"],
        "status": "PASS",
        "state_policy": {
            "state_before_sha256": row["state_before_sha256"],
            "state_after_sha256": row["state_after_sha256"],
            "library_retained_across_artifacts": row[
                "library_retained_across_artifacts"
            ],
        },
        "tool_receipts": [
            {
                "tool_sha256": item["tool_sha256"],
                "action": "reused",
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
        "resources": {
            "wall_ns": resource["wall_ns"],
            "peak_group_rss_kib": resource["peak_group_rss_kib"],
            "observed_process_count": resource["observed_process_count"],
            "process_group_reaped": resource["process_group_reaped"],
            "termination": resource["termination"],
        },
        "provenance": {
            "adapter_sha256": ADAPTER_SHA256,
            "artifact_source_sha256": request["artifact"]["source_sha256"],
            "protocol_freeze_sha256": request["sealed_inputs"][
                "protocol_freeze_sha256"
            ],
            "validation_v6_outcome_mounted": False,
        },
    }


def verify_batch_primary(batch: dict) -> dict:
    expected_fields = {
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
    }
    if set(batch) != expected_fields:
        raise ValueError("batch fields mismatch")
    if (
        batch["version"] != "FOUNDRY_ARM_ADAPTER_BATCH_OVERLAY_V1"
        or batch["arm_id"] not in {"A3", "A9"}
        or len(batch["shared_resource_receipts"]) != 1
        or len(batch["artifact_bindings"]) != 23
    ):
        raise ValueError("batch identity or cardinality")
    shared = batch["shared_resource_receipts"][0]
    if set(shared) != {"receipt_id", "body"}:
        raise ValueError("shared receipt fields")
    receipt_id = digest(shared["body"])
    if shared["receipt_id"] != receipt_id:
        raise ValueError("shared receipt digest")
    body = shared["body"]
    if not (
        body["arm_id"] == batch["arm_id"]
        and body["termination"] == "natural"
        and body["process_group_reaped"] is True
        and body["wall_ns"] > 0
        and body["peak_group_rss_kib"] > 0
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
    artifact_ids = set()
    output_digests = set()
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
        if (
            binding["shared_resource_receipt_id"] != receipt_id
            or hashlib.sha256(raw_input).hexdigest()
            != binding["input_sha256"]
            or hashlib.sha256(raw_output).hexdigest()
            != binding["output_sha256"]
            or binding["artifact_id"]
            != binding["input"]["artifact"]["artifact_id"]
            or binding["artifact_id"] != binding["output"]["artifact_id"]
            or binding["output"]["resources"] != projection
        ):
            raise ValueError("binding relation")
        parsed = parse_input(raw_input)
        parse_output(raw_output, parsed)
        artifact_ids.add(binding["artifact_id"])
        output_digests.add(binding["output_sha256"])
    if len(artifact_ids) != 23 or len(output_digests) != 23:
        raise ValueError("duplicate artifact or output")
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
        "status": "PRIMARY_SHARED_RESOURCE_BATCH_PASS",
        "arm_id": batch["arm_id"],
        "artifacts": 23,
        "unique_resource_receipts_charged": 1,
    }


def assemble(arm_id: str) -> dict:
    if arm_id not in {"A3", "A9"}:
        raise ValueError("overlay permits only A3/A9")
    protocol = json.loads(PROTOCOL.read_text())
    authenticate(protocol)
    mount = json.loads(MOUNT_RESULT.read_text())
    metered = json.loads(RESOURCE_RESULT.read_text())
    arm = mount["arms"][arm_id]
    meter = metered["arms"][arm_id]
    shared = shared_receipt(arm_id, meter)
    projection = {
        key: shared["body"][key]
        for key in (
            "wall_ns",
            "peak_group_rss_kib",
            "observed_process_count",
            "process_group_reaped",
            "termination",
        )
    }
    bindings = []
    for row in arm["rows"]:
        request = request_for(arm_id, row, protocol)
        output = output_for(arm_id, row, request, projection)
        raw_input = canonical(request)
        raw_output = canonical(output)
        parsed_input = parse_input(raw_input)
        parse_output(raw_output, parsed_input)
        independent_verify(raw_input, raw_output)
        bindings.append(
            {
                "artifact_id": row["artifact_id"],
                "shared_resource_receipt_id": shared["receipt_id"],
                "input_sha256": hashlib.sha256(raw_input).hexdigest(),
                "output_sha256": hashlib.sha256(raw_output).hexdigest(),
                "input": request,
                "output": output,
            }
        )
    batch = {
        "version": protocol["overlay_version"],
        "arm_id": arm_id,
        "shared_resource_receipts": [shared],
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
    verify_batch_primary(batch)
    return batch


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--arm", choices=("A3", "A9"), required=True)
    parser.add_argument("--summary-only", action="store_true")
    args = parser.parse_args()
    batch = assemble(args.arm)
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
