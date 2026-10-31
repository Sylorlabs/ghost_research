#!/usr/bin/env python3
"""Independent minimal verifier for arm adapter envelope relations."""

from __future__ import annotations

import json
import math
import re


HEX = re.compile(r"[0-9a-f]{64}\Z")
ARMS = {f"A{index}" for index in range(10)}


class IndependentAdapterReject(ValueError):
    pass


def verify(raw_input: bytes, raw_output: bytes) -> dict:
    request = json.loads(raw_input)
    response = json.loads(raw_output)
    if set(request) != {
        "version",
        "arm_id",
        "artifact",
        "budgets",
        "execution",
        "sealed_inputs",
    }:
        raise IndependentAdapterReject("input fields")
    if set(response) != {
        "version",
        "arm_id",
        "artifact_id",
        "status",
        "state_policy",
        "tool_receipts",
        "cost_ledger",
        "correctness",
        "resources",
        "provenance",
    }:
        raise IndependentAdapterReject("output fields")
    if request.get("version") != "FOUNDRY_ARM_ADAPTER_INPUT_V1":
        raise IndependentAdapterReject("input version")
    if request.get("arm_id") not in ARMS:
        raise IndependentAdapterReject("arm")
    if request.get("execution") != {
        "invocations": 3,
        "pairing_unit": "artifact",
        "retain_individual_invocation_receipts": True,
    }:
        raise IndependentAdapterReject("schedule")
    if response.get("version") != "FOUNDRY_ARM_ADAPTER_OUTPUT_V1":
        raise IndependentAdapterReject("output version")
    if response.get("arm_id") != request["arm_id"]:
        raise IndependentAdapterReject("arm identity")
    if response.get("artifact_id") != request["artifact"]["artifact_id"]:
        raise IndependentAdapterReject("artifact identity")
    costs = response.get("cost_ledger", {})
    names = (
        "candidate_generation_cpu_ns",
        "verification_cpu_ns",
        "compiler_cpu_ns",
        "selector_cpu_ns",
        "executed_workload_cpu_ns",
        "failed_attempt_cpu_ns",
    )
    if any(type(costs.get(name)) is not int or costs[name] < 0 for name in names):
        raise IndependentAdapterReject("cost component")
    if costs.get("total_cpu_ns") != sum(costs[name] for name in names):
        raise IndependentAdapterReject("cost sum")
    provenance = response.get("provenance", {})
    for name in (
        "adapter_sha256",
        "artifact_source_sha256",
        "protocol_freeze_sha256",
    ):
        if not isinstance(provenance.get(name), str) or not HEX.fullmatch(
            provenance[name]
        ):
            raise IndependentAdapterReject("digest")
    if (
        provenance["artifact_source_sha256"]
        != request["artifact"]["source_sha256"]
        or provenance["protocol_freeze_sha256"]
        != request["sealed_inputs"]["protocol_freeze_sha256"]
    ):
        raise IndependentAdapterReject("provenance")
    if request["arm_id"] in {"A3", "A9"}:
        state = response.get("state_policy", {})
        if state.get("library_retained_across_artifacts") is not False:
            raise IndependentAdapterReject("retained state")
        if state.get("state_before_sha256") != state.get(
            "state_after_sha256"
        ):
            raise IndependentAdapterReject("state mismatch")
    if response.get("status") == "PASS":
        correctness = response.get("correctness", {})
        rows = correctness.get("invocation_receipts", [])
        error = correctness.get("max_abs_error")
        resources = response.get("resources", {})
        if not (
            len(rows) == 3
            and [row.get("ordinal") for row in rows] == [1, 2, 3]
            and all(row.get("correct") is True for row in rows)
            and correctness.get("all_invocations_correct") is True
            and isinstance(error, (int, float))
            and not isinstance(error, bool)
            and math.isfinite(error)
            and 0 <= error <= 1.0e-5
            and correctness.get("alias_storage_checks_passed") is True
            and resources.get("termination") == "natural"
            and resources.get("process_group_reaped") is True
            and provenance.get("validation_v6_outcome_mounted") is False
        ):
            raise IndependentAdapterReject("PASS relation")
    return {
        "arm_id": request["arm_id"],
        "artifact_id": request["artifact"]["artifact_id"],
        "invocations": 3,
        "total_cpu_ns": costs["total_cpu_ns"],
        "status": response["status"],
    }
