#!/usr/bin/env python3
"""Independent verifier for the four-arm required-unsupported batch."""

from __future__ import annotations

import hashlib
import json
from collections import Counter

from independent_arm_adapter_contract import verify as verify_pair


class IndependentUnsupportedBatchReject(ValueError):
    pass


ARMS = ("A1", "A6", "A7", "A8")
REASONS = {
    "A1": "INCOMPLETE_IR_SURFACE",
    "A6": "TOP_LEVEL_ISAMORE_CONTROL_UNAVAILABLE",
    "A7": "NEW_TENSOR_SYNTH_LANGUAGE_REQUIRED",
    "A8": "UPSTREAM_EGGMIND_NOT_DISCOVERED_PARTIAL_BOUNDARY_ONLY",
}


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def object_hash(value: object) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def exact(value: object, keys: set[str], label: str) -> dict:
    if type(value) is not dict or set(value) != keys:
        raise IndependentUnsupportedBatchReject(label)
    return value


def verify(batch: dict, matrix: dict) -> dict:
    exact(
        batch,
        {
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
        },
        "batch fields",
    )
    if not (
        batch["version"] == "FOUNDRY_REQUIRED_UNSUPPORTED_ARM_BATCH_V1"
        and batch["arms"] == list(ARMS)
        and type(batch["shared_resource_receipts"]) is list
        and len(batch["shared_resource_receipts"]) == 1
        and type(batch["artifact_bindings"]) is list
        and len(batch["artifact_bindings"]) == 92
    ):
        raise IndependentUnsupportedBatchReject("batch header")
    shared = exact(
        batch["shared_resource_receipts"][0],
        {"receipt_id", "body"},
        "receipt fields",
    )
    body = exact(
        shared["body"],
        {
            "version",
            "matrix_id",
            "command_sha256",
            "cwd_sha256",
            "wall_ns",
            "rusage_user_cpu_ns",
            "rusage_system_cpu_ns",
            "peak_group_rss_kib",
            "observed_process_count",
            "process_group_reaped",
            "termination",
            "limits",
            "stdout_sha256",
            "stderr_sha256",
        },
        "receipt body fields",
    )
    if not (
        object_hash(body) == shared["receipt_id"]
        and body["version"]
        == "FOUNDRY_SHARED_PROCESS_RESOURCE_RECEIPT_V1"
        and body["matrix_id"] == "A1_A6_A7_A8_REQUIRED_UNSUPPORTED_V1"
        and body["termination"] == "natural"
        and body["process_group_reaped"] is True
        and type(body["observed_process_count"]) is int
        and body["observed_process_count"] >= 1
    ):
        raise IndependentUnsupportedBatchReject("receipt relation")
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
    artifacts = {row["artifact_id"] for row in matrix["artifacts"]}
    expected_pairs = {
        (arm_id, artifact_id)
        for arm_id in ARMS
        for artifact_id in artifacts
    }
    evidence_hashes = {
        arm_id: object_hash(matrix["evidence"][arm_id])
        for arm_id in ARMS
    }
    empty_state = object_hash({})
    seen_pairs = set()
    input_hashes = set()
    output_hashes = set()
    charged = Counter()
    allocated = 0
    protocol_hashes = set()
    fixed_hashes = set()
    for binding in batch["artifact_bindings"]:
        exact(
            binding,
            {
                "arm_id",
                "artifact_id",
                "reason",
                "evidence_sha256",
                "shared_resource_receipt_id",
                "input_sha256",
                "output_sha256",
                "input",
                "output",
            },
            "binding fields",
        )
        raw_input = canonical(binding["input"])
        raw_output = canonical(binding["output"])
        base = verify_pair(raw_input, raw_output)
        if not (
            binding["shared_resource_receipt_id"] == shared["receipt_id"]
            and hashlib.sha256(raw_input).hexdigest()
            == binding["input_sha256"]
            and hashlib.sha256(raw_output).hexdigest()
            == binding["output_sha256"]
            and binding["arm_id"] == base["arm_id"]
            and binding["artifact_id"] == base["artifact_id"]
            and binding["output"]["resources"] == projection
        ):
            raise IndependentUnsupportedBatchReject("binding hash relation")
        arm_id = binding["arm_id"]
        if arm_id not in ARMS:
            raise IndependentUnsupportedBatchReject("unknown arm")
        request = binding["input"]
        output = binding["output"]
        exact(
            output["state_policy"],
            {
                "state_before_sha256",
                "state_after_sha256",
                "library_retained_across_artifacts",
            },
            "state fields",
        )
        exact(
            output["correctness"],
            {
                "invocation_receipts",
                "all_invocations_correct",
                "max_abs_error",
                "alias_storage_checks_passed",
            },
            "correctness fields",
        )
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
                "state_before_sha256": empty_state,
                "state_after_sha256": empty_state,
                "library_retained_across_artifacts": False,
            }
            and output["provenance"][
                "validation_v6_outcome_mounted"
            ]
            is False
            and binding["reason"] == REASONS[arm_id]
            and binding["evidence_sha256"] == evidence_hashes[arm_id]
            and request["sealed_inputs"]["candidate_library_sha256"]
            == evidence_hashes[arm_id]
        ):
            raise IndependentUnsupportedBatchReject(
                "unsupported evidence relation"
            )
        total = output["cost_ledger"]["total_cpu_ns"]
        if type(total) is not int or total < 0:
            raise IndependentUnsupportedBatchReject("ledger total")
        allocated += total
        charged[arm_id] += total > 0
        protocol_hashes.add(
            request["sealed_inputs"]["protocol_freeze_sha256"]
        )
        fixed_hashes.add(request["sealed_inputs"]["fixed_portfolio_sha256"])
        seen_pairs.add((arm_id, binding["artifact_id"]))
        input_hashes.add(binding["input_sha256"])
        output_hashes.add(binding["output_sha256"])
    measured = body["rusage_user_cpu_ns"] + body[
        "rusage_system_cpu_ns"
    ]
    if not (
        seen_pairs == expected_pairs
        and len(input_hashes) == len(output_hashes) == 92
        and charged == Counter({arm_id: 1 for arm_id in ARMS})
        and allocated == measured
        and len(protocol_hashes) == len(fixed_hashes) == 1
    ):
        raise IndependentUnsupportedBatchReject(
            "Cartesian or resource allocation"
        )
    if batch["aggregate_accounting"] != {
        "arms": 4,
        "artifacts_per_arm": 23,
        "artifact_outputs": 92,
        "required_unsupported_outputs": 92,
        "unique_resource_receipts_charged": 1,
        "resource_receipt_references": 92,
        "resource_multiplier_applied": 1,
        "measured_process_cpu_ns": measured,
        "allocated_ledger_cpu_ns": measured,
        "cpu_charged_bindings": 4,
    }:
        raise IndependentUnsupportedBatchReject("aggregate accounting")
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
        raise IndependentUnsupportedBatchReject("claim boundary")
    return {
        "status": "REQUIRED_UNSUPPORTED_BATCH_INDEPENDENT_PASS",
        "pairs": 92,
        "arms": 4,
        "allocated_cpu_ns": allocated,
        "unique_resource_receipts_charged": 1,
    }
