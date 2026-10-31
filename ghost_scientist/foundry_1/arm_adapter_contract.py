#!/usr/bin/env python3
"""Strict primary parser for evaluator-owned arm adapter envelopes."""

from __future__ import annotations

import json
import math
import pathlib
import re
from typing import Any


HERE = pathlib.Path(__file__).resolve().parent
CONTRACT = json.loads(
    (HERE / "ARM_ADAPTER_CONTRACT_V1.json").read_text(encoding="utf-8")
)
SHA256 = re.compile(r"^[0-9a-f]{64}$")


class AdapterContractReject(ValueError):
    pass


def exact_keys(value: dict, expected: list[str], label: str) -> None:
    if set(value) != set(expected):
        raise AdapterContractReject(f"{label} fields mismatch")


def nonnegative_int(value: Any, label: str) -> int:
    if type(value) is not int or value < 0:
        raise AdapterContractReject(f"{label} must be nonnegative integer")
    return value


def positive_int(value: Any, label: str) -> int:
    result = nonnegative_int(value, label)
    if result == 0:
        raise AdapterContractReject(f"{label} must be positive")
    return result


def digest(value: Any, label: str) -> str:
    if not isinstance(value, str) or not SHA256.fullmatch(value):
        raise AdapterContractReject(f"{label} malformed")
    return value


def text(value: Any, label: str) -> str:
    if not isinstance(value, str) or not value or len(value) > 256:
        raise AdapterContractReject(f"{label} malformed")
    return value


def parse_input(raw: bytes) -> dict:
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise AdapterContractReject("input must be object")
    schema = CONTRACT["input_schema"]
    exact_keys(value, schema["required_fields"], "input")
    if value["version"] != schema["version"]:
        raise AdapterContractReject("input version mismatch")
    if value["arm_id"] not in CONTRACT["required_arms"]:
        raise AdapterContractReject("unknown or optional arm")
    artifact = value["artifact"]
    exact_keys(
        artifact, schema["artifact_required_fields"], "artifact"
    )
    text(artifact["artifact_id"], "artifact_id")
    digest(artifact["source_sha256"], "source_sha256")
    digest(artifact["graph_ir_sha256"], "graph_ir_sha256")
    digest(artifact["shape_seed_sha256"], "shape_seed_sha256")
    for field in ("family", "repository", "semantic_domain"):
        text(artifact[field], field)
    budgets = value["budgets"]
    exact_keys(budgets, schema["budget_required_fields"], "budgets")
    for field in schema["budget_required_fields"]:
        positive_int(budgets[field], field)
    execution = value["execution"]
    exact_keys(execution, list(schema["execution_exact"]), "execution")
    if execution != schema["execution_exact"]:
        raise AdapterContractReject("execution schedule mismatch")
    sealed = value["sealed_inputs"]
    exact_keys(
        sealed, schema["sealed_input_required_fields"], "sealed_inputs"
    )
    for field in schema["sealed_input_required_fields"]:
        digest(sealed[field], field)
    return value


def parse_output(raw: bytes, expected_input: dict) -> dict:
    value = json.loads(raw)
    if not isinstance(value, dict):
        raise AdapterContractReject("output must be object")
    schema = CONTRACT["output_schema"]
    exact_keys(value, schema["required_fields"], "output")
    if value["version"] != schema["version"]:
        raise AdapterContractReject("output version mismatch")
    if value["arm_id"] != expected_input["arm_id"]:
        raise AdapterContractReject("arm identity mismatch")
    if value["artifact_id"] != expected_input["artifact"]["artifact_id"]:
        raise AdapterContractReject("artifact identity mismatch")
    if value["status"] not in schema["status_values"]:
        raise AdapterContractReject("unknown output status")
    state = value["state_policy"]
    exact_keys(
        state,
        [
            "state_before_sha256",
            "state_after_sha256",
            "library_retained_across_artifacts",
        ],
        "state_policy",
    )
    digest(state["state_before_sha256"], "state_before_sha256")
    digest(state["state_after_sha256"], "state_after_sha256")
    if type(state["library_retained_across_artifacts"]) is not bool:
        raise AdapterContractReject("retention flag must be boolean")
    if expected_input["arm_id"] in {"A3", "A9"} and (
        state["library_retained_across_artifacts"]
        or state["state_before_sha256"] != state["state_after_sha256"]
    ):
        raise AdapterContractReject("state-reset arm retained state")
    tools = value["tool_receipts"]
    if not isinstance(tools, list):
        raise AdapterContractReject("tool_receipts must be list")
    for row in tools:
        exact_keys(
            row,
            ["tool_sha256", "action", "direct_use_count"],
            "tool_receipt",
        )
        digest(row["tool_sha256"], "tool_sha256")
        if row["action"] not in {"created", "reused", "removed", "none"}:
            raise AdapterContractReject("unknown tool action")
        nonnegative_int(row["direct_use_count"], "direct_use_count")
    ledger = value["cost_ledger"]
    exact_keys(ledger, schema["cost_fields"], "cost_ledger")
    for field in schema["cost_fields"]:
        nonnegative_int(ledger[field], field)
    component_sum = sum(
        ledger[field] for field in schema["cost_fields"][:-1]
    )
    if component_sum != ledger["total_cpu_ns"]:
        raise AdapterContractReject("CPU ledger does not sum")
    correctness = value["correctness"]
    exact_keys(
        correctness, schema["correctness_fields"], "correctness"
    )
    receipts = correctness["invocation_receipts"]
    if not isinstance(receipts, list):
        raise AdapterContractReject("invocation_receipts must be list")
    for row in receipts:
        exact_keys(
            row, ["ordinal", "output_sha256", "correct"], "invocation"
        )
        positive_int(row["ordinal"], "ordinal")
        digest(row["output_sha256"], "output_sha256")
        if type(row["correct"]) is not bool:
            raise AdapterContractReject("correct must be boolean")
    if type(correctness["all_invocations_correct"]) is not bool:
        raise AdapterContractReject("correctness flag must be boolean")
    error = correctness["max_abs_error"]
    if (
        not isinstance(error, (int, float))
        or isinstance(error, bool)
        or not math.isfinite(error)
        or error < 0
    ):
        raise AdapterContractReject("max_abs_error malformed")
    if type(correctness["alias_storage_checks_passed"]) is not bool:
        raise AdapterContractReject("alias flag must be boolean")
    resources = value["resources"]
    exact_keys(resources, schema["resource_fields"], "resources")
    for field in (
        "wall_ns",
        "peak_group_rss_kib",
        "observed_process_count",
    ):
        nonnegative_int(resources[field], field)
    if type(resources["process_group_reaped"]) is not bool:
        raise AdapterContractReject("reaped flag must be boolean")
    if resources["termination"] not in {
        "natural",
        "wall_timeout",
        "cpu_limit",
        "rss_limit",
        "signal",
    }:
        raise AdapterContractReject("termination malformed")
    provenance = value["provenance"]
    exact_keys(provenance, schema["provenance_fields"], "provenance")
    digest(provenance["adapter_sha256"], "adapter_sha256")
    digest(
        provenance["artifact_source_sha256"],
        "artifact_source_sha256",
    )
    digest(
        provenance["protocol_freeze_sha256"],
        "protocol_freeze_sha256",
    )
    if (
        provenance["artifact_source_sha256"]
        != expected_input["artifact"]["source_sha256"]
        or provenance["protocol_freeze_sha256"]
        != expected_input["sealed_inputs"]["protocol_freeze_sha256"]
    ):
        raise AdapterContractReject("provenance digest mismatch")
    if type(provenance["validation_v6_outcome_mounted"]) is not bool:
        raise AdapterContractReject("mount flag must be boolean")
    if value["status"] == "PASS":
        if not (
            len(receipts) == 3
            and [row["ordinal"] for row in receipts] == [1, 2, 3]
            and all(row["correct"] for row in receipts)
            and correctness["all_invocations_correct"]
            and error <= 1.0e-5
            and correctness["alias_storage_checks_passed"]
            and resources["termination"] == "natural"
            and resources["process_group_reaped"]
            and provenance["validation_v6_outcome_mounted"] is False
        ):
            raise AdapterContractReject("PASS invariants failed")
    return value
