#!/usr/bin/env python3
"""Independent A7 shared-resource batch relation checker."""

from __future__ import annotations

import hashlib
import json
import pathlib

from independent_arm_adapter_contract import verify as verify_envelope


class IndependentA7BatchReject(ValueError):
    pass


HERE = pathlib.Path(__file__).resolve().parent


def packed(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def hexdigest(value: object) -> str:
    return hashlib.sha256(packed(value)).hexdigest()


def verify(batch: dict) -> dict:
    learned = json.loads(
        (
            HERE / "results/phase132_enumo_tensor_domain_feasibility.json"
        ).read_text()
    )["observed"]["learned_rules"]
    allowed_tools = {
        hashlib.sha256(rule.encode()).hexdigest() for rule in learned
    }
    required = {
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
    }
    if set(batch) != required:
        raise IndependentA7BatchReject("top fields")
    if batch.get("version") != "FOUNDRY_A7_ARM_ADAPTER_BATCH_V1":
        raise IndependentA7BatchReject("version")
    receipts = batch.get("shared_resource_receipts")
    bindings = batch.get("artifact_bindings")
    if not isinstance(receipts, list) or len(receipts) != 1:
        raise IndependentA7BatchReject("receipt cardinality")
    if not isinstance(bindings, list) or len(bindings) != 23:
        raise IndependentA7BatchReject("binding cardinality")
    shared = receipts[0]
    if set(shared) != {"receipt_id", "body"}:
        raise IndependentA7BatchReject("receipt fields")
    if hexdigest(shared["body"]) != shared["receipt_id"]:
        raise IndependentA7BatchReject("receipt hash")
    body = shared["body"]
    if (
        body.get("arm_id") != "A7"
        or body.get("termination") != "natural"
        or body.get("process_group_reaped") is not True
    ):
        raise IndependentA7BatchReject("resource validity")
    resource_projection = {
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
    request_hashes = set()
    response_hashes = set()
    state = protocol = None
    raw_uses = unique_uses = generation_charges = 0
    for binding in bindings:
        if set(binding) != {
            "artifact_id",
            "shared_resource_receipt_id",
            "unique_selected_transformations",
            "input_sha256",
            "output_sha256",
            "input",
            "output",
        }:
            raise IndependentA7BatchReject("binding fields")
        request = packed(binding["input"])
        response = packed(binding["output"])
        if (
            hashlib.sha256(request).hexdigest() != binding["input_sha256"]
            or hashlib.sha256(response).hexdigest() != binding["output_sha256"]
            or binding["shared_resource_receipt_id"] != shared["receipt_id"]
        ):
            raise IndependentA7BatchReject("binding hashes")
        verify_envelope(request, response)
        output = binding["output"]
        candidate = binding["input"]["sealed_inputs"][
            "candidate_library_sha256"
        ]
        freeze = binding["input"]["sealed_inputs"]["protocol_freeze_sha256"]
        policy = output["state_policy"]
        if (
            policy["state_before_sha256"] != candidate
            or policy["state_after_sha256"] != candidate
            or policy["library_retained_across_artifacts"] is not True
            or output["resources"] != resource_projection
        ):
            raise IndependentA7BatchReject("state or resource projection")
        for tool in output["tool_receipts"]:
            if (
                tool["action"] != "reused"
                or tool["direct_use_count"] <= 0
                or tool["tool_sha256"] not in allowed_tools
            ):
                raise IndependentA7BatchReject("tool relation")
            raw_uses += tool["direct_use_count"]
        unique = binding["unique_selected_transformations"]
        if type(unique) is not int or unique < 0:
            raise IndependentA7BatchReject("unique transformation count")
        unique_uses += unique
        generation_charges += (
            output["cost_ledger"]["candidate_generation_cpu_ns"] > 0
        )
        state = candidate if state is None else state
        protocol = freeze if protocol is None else protocol
        if state != candidate or protocol != freeze:
            raise IndependentA7BatchReject("sealed state drift")
        artifacts.add(binding["artifact_id"])
        request_hashes.add(binding["input_sha256"])
        response_hashes.add(binding["output_sha256"])
    if not (
        len(artifacts) == len(request_hashes) == len(response_hashes) == 23
        and raw_uses == 24
        and unique_uses == 12
        and generation_charges == 1
    ):
        raise IndependentA7BatchReject("aggregate relation")
    expected = {
        "artifact_outputs": 23,
        "unique_resource_receipts_charged": 1,
        "resource_receipt_references": 23,
        "resource_multiplier_applied": 1,
        "raw_selected_rule_uses": 24,
        "unique_selected_transformations": 12,
        "candidate_generation_charged_artifacts": 1,
    }
    if batch["aggregate_accounting"] != expected:
        raise IndependentA7BatchReject("accounting")
    boundary = batch["scientific_boundary"]
    if not (
        boundary.get("adapted_evaluator_authored_tensor_domain") is True
        and boundary.get("equal_cost_operand_canonicalization_only") is True
        and boundary.get("strict_atom_cost_reduction") is False
        and boundary.get("rewritten_whole_tensor_graph_executed") is False
        and boundary.get("universal_floating_point_soundness") is False
        and boundary.get("heldout_generalization_measured") is False
        and boundary.get("fixed_portfolio_beaten") is False
        and len(boundary) == 7
    ):
        raise IndependentA7BatchReject("scientific boundary")
    if not (
        batch["base_contract_primary_accepts"]
        == batch["base_contract_independent_accepts"]
        == 23
        and batch["production_integration_classification"]
        == "PRODUCTION_INTEGRATED_ADAPTED_CALIBRATION_RULE_CONTROL"
        and batch["P3_complete"] is False
        and batch["validation_v6_accessed"] is False
        and batch["prospective_trial_authorized"] is False
    ):
        raise IndependentA7BatchReject("claims")
    return {
        "status": "A7_SHARED_RESOURCE_BATCH_INDEPENDENT_PASS",
        "artifacts": 23,
        "raw_selected_rule_uses": 24,
        "unique_selected_transformations": 12,
    }
