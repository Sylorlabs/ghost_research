#!/usr/bin/env python3
"""Independent fail-closed verifier for an A5 shared-resource batch."""

from __future__ import annotations

import hashlib
import json

from independent_arm_adapter_contract import verify as verify_pair


class IndependentA5BatchReject(ValueError):
    pass


def _canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def _hash(value: object) -> str:
    return hashlib.sha256(_canonical(value)).hexdigest()


def _exact(value: dict, keys: set[str], label: str) -> None:
    if type(value) is not dict or set(value) != keys:
        raise IndependentA5BatchReject(label)


def verify(batch: dict) -> dict:
    _exact(
        batch,
        {
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
        },
        "batch fields",
    )
    if (
        batch["version"] != "FOUNDRY_A5_ARM_ADAPTER_BATCH_V1"
        or batch["arm_id"] != "A5"
        or type(batch["shared_resource_receipts"]) is not list
        or len(batch["shared_resource_receipts"]) != 1
        or type(batch["artifact_bindings"]) is not list
        or len(batch["artifact_bindings"]) != 23
    ):
        raise IndependentA5BatchReject("batch header")
    shared = batch["shared_resource_receipts"][0]
    _exact(shared, {"receipt_id", "body"}, "shared fields")
    body = shared["body"]
    _exact(
        body,
        {
            "version",
            "arm_id",
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
        _hash(body) == shared["receipt_id"]
        and body["version"]
        == "FOUNDRY_SHARED_PROCESS_RESOURCE_RECEIPT_V1"
        and body["arm_id"] == "A5"
        and body["termination"] == "natural"
        and body["process_group_reaped"] is True
        and type(body["observed_process_count"]) is int
        and body["observed_process_count"] >= 2
    ):
        raise IndependentA5BatchReject("shared receipt")
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
    artifacts: set[str] = set()
    input_hashes: set[str] = set()
    output_hashes: set[str] = set()
    library_hashes: set[str] = set()
    protocol_hashes: set[str] = set()
    fixed_hashes: set[str] = set()
    tool_hashes: set[str] = set()
    use_total = 0
    charge_count = 0
    for binding in batch["artifact_bindings"]:
        _exact(
            binding,
            {
                "artifact_id",
                "shared_resource_receipt_id",
                "input_sha256",
                "output_sha256",
                "input",
                "output",
            },
            "binding fields",
        )
        raw_input = _canonical(binding["input"])
        raw_output = _canonical(binding["output"])
        verify_pair(raw_input, raw_output)
        if not (
            binding["shared_resource_receipt_id"] == shared["receipt_id"]
            and hashlib.sha256(raw_input).hexdigest()
            == binding["input_sha256"]
            and hashlib.sha256(raw_output).hexdigest()
            == binding["output_sha256"]
            and binding["artifact_id"]
            == binding["input"]["artifact"]["artifact_id"]
            == binding["output"]["artifact_id"]
            and binding["output"]["resources"] == projection
        ):
            raise IndependentA5BatchReject("binding relation")
        if (
            binding["input"]["arm_id"] != "A5"
            or binding["output"]["arm_id"] != "A5"
            or binding["output"]["status"] != "PASS"
        ):
            raise IndependentA5BatchReject("arm status")
        sealed = binding["input"]["sealed_inputs"]
        policy = binding["output"]["state_policy"]
        if not (
            policy["state_before_sha256"]
            == policy["state_after_sha256"]
            == sealed["candidate_library_sha256"]
            and policy["library_retained_across_artifacts"] is True
            and binding["output"]["provenance"][
                "protocol_freeze_sha256"
            ]
            == sealed["protocol_freeze_sha256"]
            and binding["output"]["provenance"][
                "validation_v6_outcome_mounted"
            ]
            is False
        ):
            raise IndependentA5BatchReject("sealed state")
        tools = binding["output"]["tool_receipts"]
        if type(tools) is not list or len(tools) != 1:
            raise IndependentA5BatchReject("tool cardinality")
        tool = tools[0]
        if not (
            type(tool["direct_use_count"]) is int
            and tool["direct_use_count"] >= 0
            and tool["action"]
            == ("reused" if tool["direct_use_count"] else "none")
        ):
            raise IndependentA5BatchReject("tool action")
        uses = tool["direct_use_count"]
        ledger = binding["output"]["cost_ledger"]
        use_total += uses
        charge_count += ledger["candidate_generation_cpu_ns"] > 0
        artifacts.add(binding["artifact_id"])
        input_hashes.add(binding["input_sha256"])
        output_hashes.add(binding["output_sha256"])
        library_hashes.add(sealed["candidate_library_sha256"])
        protocol_hashes.add(sealed["protocol_freeze_sha256"])
        fixed_hashes.add(sealed["fixed_portfolio_sha256"])
        tool_hashes.add(tool["tool_sha256"])
    if not (
        len(artifacts)
        == len(input_hashes)
        == len(output_hashes)
        == 23
        and len(library_hashes)
        == len(protocol_hashes)
        == len(fixed_hashes)
        == len(tool_hashes)
        == 1
        and use_total == 329
        and charge_count == 1
    ):
        raise IndependentA5BatchReject("batch aggregation")
    if batch["aggregate_accounting"] != {
        "artifact_outputs": 23,
        "unique_resource_receipts_charged": 1,
        "resource_receipt_references": 23,
        "resource_multiplier_applied": 1,
        "direct_structural_uses": 329,
        "candidate_generation_charged_artifacts": 1,
    }:
        raise IndependentA5BatchReject("aggregate receipt accounting")
    if batch["scientific_boundary"] != {
        "normalized_rewrite_reversibility": True,
        "rewritten_tensor_runtime_executed": False,
        "tensor_primitive_invented": False,
        "heldout_generalization_measured": False,
        "fixed_portfolio_beaten": False,
    }:
        raise IndependentA5BatchReject("scientific overclaim")
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
        raise IndependentA5BatchReject("claim boundary")
    return {
        "status": "A5_SHARED_RESOURCE_BATCH_INDEPENDENT_PASS",
        "artifacts": 23,
        "direct_structural_uses": 329,
        "unique_resource_receipts_charged": 1,
    }
