#!/usr/bin/env python3
"""Independent strict verifier for shared-resource arm batches."""

from __future__ import annotations

import hashlib
import json
import re

from independent_arm_adapter_contract import verify as verify_base


HEX = re.compile(r"[0-9a-f]{64}\Z")


class IndependentBatchReject(ValueError):
    pass


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


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
        raise IndependentBatchReject("batch fields")
    if (
        batch["version"] != "FOUNDRY_ARM_ADAPTER_BATCH_OVERLAY_V1"
        or batch["arm_id"] not in {"A3", "A9"}
        or len(batch["shared_resource_receipts"]) != 1
        or len(batch["artifact_bindings"]) != 23
    ):
        raise IndependentBatchReject("batch cardinality")
    shared = batch["shared_resource_receipts"][0]
    if set(shared) != {"receipt_id", "body"}:
        raise IndependentBatchReject("shared receipt fields")
    actual_id = hashlib.sha256(canonical(shared["body"])).hexdigest()
    if shared["receipt_id"] != actual_id or not HEX.fullmatch(actual_id):
        raise IndependentBatchReject("shared receipt identity")
    body = shared["body"]
    if (
        body.get("arm_id") != batch["arm_id"]
        or body.get("termination") != "natural"
        or body.get("process_group_reaped") is not True
        or type(body.get("wall_ns")) is not int
        or body["wall_ns"] <= 0
        or type(body.get("peak_group_rss_kib")) is not int
        or body["peak_group_rss_kib"] <= 0
    ):
        raise IndependentBatchReject("shared receipt relation")
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
    for binding in batch["artifact_bindings"]:
        if set(binding) != {
            "artifact_id",
            "shared_resource_receipt_id",
            "input_sha256",
            "output_sha256",
            "input",
            "output",
        }:
            raise IndependentBatchReject("binding fields")
        raw_input = canonical(binding["input"])
        raw_output = canonical(binding["output"])
        if (
            binding["shared_resource_receipt_id"] != actual_id
            or hashlib.sha256(raw_input).hexdigest()
            != binding["input_sha256"]
            or hashlib.sha256(raw_output).hexdigest()
            != binding["output_sha256"]
            or binding["artifact_id"]
            != binding["input"].get("artifact", {}).get("artifact_id")
            or binding["artifact_id"]
            != binding["output"].get("artifact_id")
            or binding["output"].get("resources") != projection
        ):
            raise IndependentBatchReject("binding relation")
        base = verify_base(raw_input, raw_output)
        if base["status"] != "PASS":
            raise IndependentBatchReject("base contract status")
        artifacts.add(binding["artifact_id"])
        outputs.add(binding["output_sha256"])
    if len(artifacts) != 23 or len(outputs) != 23:
        raise IndependentBatchReject("duplicate artifact or output")
    aggregate = batch["aggregate_accounting"]
    if aggregate != {
        "artifact_outputs": 23,
        "unique_resource_receipts_charged": 1,
        "resource_receipt_references": 23,
        "resource_multiplier_applied": 1,
    }:
        raise IndependentBatchReject("aggregate accounting")
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
        raise IndependentBatchReject("claim boundary")
    return {
        "status": "INDEPENDENT_SHARED_RESOURCE_BATCH_PASS",
        "arm_id": batch["arm_id"],
        "artifacts": 23,
        "unique_resource_receipts_charged": 1,
    }
