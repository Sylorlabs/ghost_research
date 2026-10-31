#!/usr/bin/env python3
"""Assemble four required-unsupported arms under one measured receipt."""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
from collections import Counter

from arm_adapter_contract import parse_input, parse_output
from independent_arm_adapter_contract import verify as verify_pair


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/"
    "REQUIRED_UNSUPPORTED_CONTRACT_BATCH_PROTOCOL_V1.json"
)
MATRIX = HERE / "results/phase107_required_unsupported_matrix_audit.json"
RESOURCE = (
    HERE
    / "results/phase108_required_unsupported_matrix_resource_audit.json"
)
FIXED = HERE / "results/forged_diversity_tools.json"
ADAPTER = HERE / "phase107_required_unsupported_matrix_audit.py"


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
    matrix = json.loads(MATRIX.read_text())
    resource = json.loads(RESOURCE.read_text())["receipt"]
    fixed = json.loads(FIXED.read_text())
    resource_body = {
        "version": "FOUNDRY_SHARED_PROCESS_RESOURCE_RECEIPT_V1",
        "matrix_id": "A1_A6_A7_A8_REQUIRED_UNSUPPORTED_V1",
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
    measured_cpu_ns = (
        resource_body["rusage_user_cpu_ns"]
        + resource_body["rusage_system_cpu_ns"]
    )
    quotient, remainder = divmod(measured_cpu_ns, len(protocol["arms"]))
    arm_cpu = {
        arm_id: quotient + (index < remainder)
        for index, arm_id in enumerate(protocol["arms"])
    }
    empty_state_sha256 = digest({})
    evidence_hashes = {
        arm_id: digest(matrix["evidence"][arm_id])
        for arm_id in protocol["arms"]
    }
    artifact_by_id = {
        row["artifact_id"]: row for row in matrix["artifacts"]
    }
    first_artifact = matrix["artifacts"][0]["artifact_id"]
    bindings = []
    for outcome in matrix["outcomes"]:
        arm_id = outcome["arm_id"]
        artifact = artifact_by_id[outcome["artifact_id"]]
        charged = artifact["artifact_id"] == first_artifact
        sealed = {
            "candidate_library_sha256": evidence_hashes[arm_id],
            "fixed_portfolio_sha256": fixed["fixed_portfolio_sha256"],
            "protocol_freeze_sha256": sha(PROTOCOL),
        }
        request = {
            "version": "FOUNDRY_ARM_ADAPTER_INPUT_V1",
            "arm_id": arm_id,
            "artifact": {
                "artifact_id": artifact["artifact_id"],
                "source_sha256": artifact["source_sha256"],
                "family": artifact["family"],
                "repository": artifact["repository"],
                "semantic_domain": artifact["semantic_domain"],
                "graph_ir_sha256": artifact["graph_ir_sha256"],
                "shape_seed_sha256": artifact["shape_seed_sha256"],
            },
            "budgets": {
                "wall_limit_seconds": 60,
                "cpu_limit_seconds": 45,
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
        allocated_cpu = arm_cpu[arm_id] if charged else 0
        ledger = {
            "candidate_generation_cpu_ns": 0,
            "verification_cpu_ns": allocated_cpu,
            "compiler_cpu_ns": 0,
            "selector_cpu_ns": 0,
            "executed_workload_cpu_ns": 0,
            "failed_attempt_cpu_ns": 0,
            "total_cpu_ns": allocated_cpu,
        }
        output = {
            "version": "FOUNDRY_ARM_ADAPTER_OUTPUT_V1",
            "arm_id": arm_id,
            "artifact_id": artifact["artifact_id"],
            "status": "REQUIRED_UNSUPPORTED",
            "state_policy": {
                "state_before_sha256": empty_state_sha256,
                "state_after_sha256": empty_state_sha256,
                "library_retained_across_artifacts": False,
            },
            "tool_receipts": [],
            "cost_ledger": ledger,
            "correctness": {
                "invocation_receipts": [],
                "all_invocations_correct": False,
                "max_abs_error": 0.0,
                "alias_storage_checks_passed": False,
            },
            "resources": projection,
            "provenance": {
                "adapter_sha256": sha(ADAPTER),
                "artifact_source_sha256": artifact["source_sha256"],
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
        verify_pair(raw_input, raw_output)
        bindings.append(
            {
                "arm_id": arm_id,
                "artifact_id": artifact["artifact_id"],
                "reason": outcome["reason"],
                "evidence_sha256": evidence_hashes[arm_id],
                "shared_resource_receipt_id": receipt_id,
                "input_sha256": hashlib.sha256(raw_input).hexdigest(),
                "output_sha256": hashlib.sha256(raw_output).hexdigest(),
                "input": request,
                "output": output,
            }
        )
    batch = {
        "version": protocol["batch_version"],
        "arms": protocol["arms"],
        "shared_resource_receipts": [
            {"receipt_id": receipt_id, "body": resource_body}
        ],
        "artifact_bindings": bindings,
        "aggregate_accounting": {
            "arms": 4,
            "artifacts_per_arm": 23,
            "artifact_outputs": 92,
            "required_unsupported_outputs": 92,
            "unique_resource_receipts_charged": 1,
            "resource_receipt_references": 92,
            "resource_multiplier_applied": 1,
            "measured_process_cpu_ns": measured_cpu_ns,
            "allocated_ledger_cpu_ns": sum(
                row["output"]["cost_ledger"]["total_cpu_ns"]
                for row in bindings
            ),
            "cpu_charged_bindings": sum(
                row["output"]["cost_ledger"]["total_cpu_ns"] > 0
                for row in bindings
            ),
        },
        "base_contract_primary_accepts": 92,
        "base_contract_independent_accepts": 92,
        "outcome_classification": {
            "newly_conformant_arms": 0,
            "newly_production_integrated_arms": 0,
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3_complete_resource_meter": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    verify_primary(batch)
    return batch


def verify_primary(batch: dict) -> dict:
    if set(batch) != {
        "version",
        "arms",
        "shared_resource_receipts",
        "artifact_bindings",
        "aggregate_accounting",
        "base_contract_primary_accepts",
        "base_contract_independent_accepts",
        "outcome_classification",
        "P3_complete_resource_meter",
        "validation_v6_accessed",
        "prospective_trial_authorized",
    }:
        raise ValueError("batch fields")
    if not (
        batch["version"] == "FOUNDRY_REQUIRED_UNSUPPORTED_ARM_BATCH_V1"
        and batch["arms"] == ["A1", "A6", "A7", "A8"]
        and len(batch["shared_resource_receipts"]) == 1
        and len(batch["artifact_bindings"]) == 92
    ):
        raise ValueError("batch identity or cardinality")
    shared = batch["shared_resource_receipts"][0]
    if set(shared) != {"receipt_id", "body"} or digest(
        shared["body"]
    ) != shared["receipt_id"]:
        raise ValueError("shared receipt identity")
    body = shared["body"]
    if not (
        body["matrix_id"] == "A1_A6_A7_A8_REQUIRED_UNSUPPORTED_V1"
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
    protocol = json.loads(PROTOCOL.read_text())
    matrix = json.loads(MATRIX.read_text())
    expected_artifacts = {
        row["artifact_id"] for row in matrix["artifacts"]
    }
    expected_pairs = {
        (arm_id, artifact_id)
        for arm_id in protocol["arms"]
        for artifact_id in expected_artifacts
    }
    pairs = set()
    inputs = set()
    outputs = set()
    evidence_by_arm = {}
    charged_by_arm = Counter()
    allocated_cpu = 0
    empty_state_sha256 = digest({})
    for binding in batch["artifact_bindings"]:
        if set(binding) != {
            "arm_id",
            "artifact_id",
            "reason",
            "evidence_sha256",
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
            and binding["arm_id"]
            == binding["input"]["arm_id"]
            == binding["output"]["arm_id"]
            and binding["artifact_id"]
            == binding["input"]["artifact"]["artifact_id"]
            == binding["output"]["artifact_id"]
            and binding["output"]["resources"] == projection
        ):
            raise ValueError("binding relation")
        parsed = parse_input(raw_input)
        parse_output(raw_output, parsed)
        output = binding["output"]
        if not (
            output["status"] == "REQUIRED_UNSUPPORTED"
            and output["tool_receipts"] == []
            and output["correctness"]
            == {
                "invocation_receipts": [],
                "all_invocations_correct": False,
                "max_abs_error": 0.0,
                "alias_storage_checks_passed": False,
            }
            and output["state_policy"]
            == {
                "state_before_sha256": empty_state_sha256,
                "state_after_sha256": empty_state_sha256,
                "library_retained_across_artifacts": False,
            }
            and output["provenance"][
                "validation_v6_outcome_mounted"
            ]
            is False
        ):
            raise ValueError("unsupported output relation")
        arm_id = binding["arm_id"]
        evidence_sha256 = digest(matrix["evidence"][arm_id])
        if not (
            binding["reason"] == protocol["expected_reasons"][arm_id]
            and binding["evidence_sha256"] == evidence_sha256
            and binding["input"]["sealed_inputs"][
                "candidate_library_sha256"
            ]
            == evidence_sha256
        ):
            raise ValueError("evidence relation")
        evidence_by_arm.setdefault(arm_id, evidence_sha256)
        if evidence_by_arm[arm_id] != evidence_sha256:
            raise ValueError("evidence drift")
        total = output["cost_ledger"]["total_cpu_ns"]
        allocated_cpu += total
        charged_by_arm[arm_id] += total > 0
        pairs.add((arm_id, binding["artifact_id"]))
        inputs.add(binding["input_sha256"])
        outputs.add(binding["output_sha256"])
    if not (
        pairs == expected_pairs
        and len(inputs) == len(outputs) == 92
        and charged_by_arm
        == Counter({"A1": 1, "A6": 1, "A7": 1, "A8": 1})
    ):
        raise ValueError("Cartesian or CPU allocation relation")
    measured_cpu = body["rusage_user_cpu_ns"] + body[
        "rusage_system_cpu_ns"
    ]
    expected_accounting = {
        "arms": 4,
        "artifacts_per_arm": 23,
        "artifact_outputs": 92,
        "required_unsupported_outputs": 92,
        "unique_resource_receipts_charged": 1,
        "resource_receipt_references": 92,
        "resource_multiplier_applied": 1,
        "measured_process_cpu_ns": measured_cpu,
        "allocated_ledger_cpu_ns": measured_cpu,
        "cpu_charged_bindings": 4,
    }
    if (
        allocated_cpu != measured_cpu
        or batch["aggregate_accounting"] != expected_accounting
    ):
        raise ValueError("aggregate accounting")
    if not (
        batch["base_contract_primary_accepts"]
        == batch["base_contract_independent_accepts"]
        == 92
        and batch["outcome_classification"]
        == {
            "newly_conformant_arms": 0,
            "newly_production_integrated_arms": 0,
            "production_integrated_arms": 6,
            "required_arms": 10,
        }
        and batch["P3_complete_resource_meter"] is True
        and batch["validation_v6_accessed"] is False
        and batch["prospective_trial_authorized"] is False
    ):
        raise ValueError("claim boundary")
    return {
        "status": "REQUIRED_UNSUPPORTED_BATCH_PRIMARY_PASS",
        "pairs": 92,
        "arms": 4,
        "allocated_cpu_ns": allocated_cpu,
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
            "arms": batch["arms"],
            "artifact_outputs": len(batch["artifact_bindings"]),
            "aggregate_accounting": batch["aggregate_accounting"],
            "outcome_classification": batch["outcome_classification"],
            "P3_complete_resource_meter": batch[
                "P3_complete_resource_meter"
            ],
            "validation_v6_accessed": batch["validation_v6_accessed"],
        }
    print(canonical(batch).decode())


if __name__ == "__main__":
    main()
