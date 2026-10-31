#!/usr/bin/env python3
"""Independent verifier for the A4 shared-resource contract batch."""

from __future__ import annotations

import hashlib

from independent_arm_adapter_contract import verify as verify_base
from a4_shared_resource_batch import canonical, digest


class IndependentA4BatchReject(ValueError):
    pass


def verify(batch: dict) -> dict:
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
        raise IndependentA4BatchReject("batch fields")
    if (
        batch.get("version") != "FOUNDRY_A4_ARM_ADAPTER_BATCH_V1"
        or batch.get("arm_id") != "A4"
        or len(batch.get("shared_resource_receipts", [])) != 1
        or len(batch.get("artifact_bindings", [])) != 23
    ):
        raise IndependentA4BatchReject("identity or cardinality")
    shared = batch["shared_resource_receipts"][0]
    body = shared.get("body", {})
    receipt_id = digest(body)
    if (
        shared.get("receipt_id") != receipt_id
        or body.get("arm_id") != "A4"
        or body.get("termination") != "natural"
        or body.get("process_group_reaped") is not True
    ):
        raise IndependentA4BatchReject("shared receipt")
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
    states = set()
    for binding in batch["artifact_bindings"]:
        raw_input = canonical(binding["input"])
        raw_output = canonical(binding["output"])
        if (
            binding.get("shared_resource_receipt_id") != receipt_id
            or hashlib.sha256(raw_input).hexdigest()
            != binding.get("input_sha256")
            or hashlib.sha256(raw_output).hexdigest()
            != binding.get("output_sha256")
            or binding["output"].get("resources") != projection
        ):
            raise IndependentA4BatchReject("binding")
        if verify_base(raw_input, raw_output)["status"] != "PASS":
            raise IndependentA4BatchReject("base output")
        policy = binding["output"].get("state_policy", {})
        if (
            policy.get("state_before_sha256")
            != policy.get("state_after_sha256")
            or policy.get("state_before_sha256")
            != binding["input"]["sealed_inputs"][
                "candidate_library_sha256"
            ]
            or policy.get("library_retained_across_artifacts") is not True
        ):
            raise IndependentA4BatchReject("retained state")
        tools = binding["output"].get("tool_receipts", [])
        if len(tools) != 3 or any(
            item.get("action")
            != (
                "reused"
                if item.get("direct_use_count", 0) > 0
                else "none"
            )
            for item in tools
        ):
            raise IndependentA4BatchReject("tool action relation")
        states.add(policy["state_before_sha256"])
        artifacts.add(binding["artifact_id"])
        outputs.add(binding["output_sha256"])
    if len(states) != 1 or len(artifacts) != 23 or len(outputs) != 23:
        raise IndependentA4BatchReject("uniqueness")
    if batch.get("aggregate_accounting") != {
        "artifact_outputs": 23,
        "unique_resource_receipts_charged": 1,
        "resource_receipt_references": 23,
        "resource_multiplier_applied": 1,
    }:
        raise IndependentA4BatchReject("accounting")
    if not (
        batch.get("base_contract_primary_accepts")
        == batch.get("base_contract_independent_accepts")
        == 23
        and batch.get("production_integration_classification")
        == "PRODUCTION_INTEGRATED_CALIBRATION_ARM"
        and batch.get("P3_complete") is False
        and batch.get("validation_v6_accessed") is False
        and batch.get("prospective_trial_authorized") is False
    ):
        raise IndependentA4BatchReject("claims")
    return {
        "status": "A4_SHARED_RESOURCE_BATCH_INDEPENDENT_PASS",
        "artifacts": 23,
        "unique_resource_receipts_charged": 1,
    }
