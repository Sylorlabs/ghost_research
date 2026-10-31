#!/usr/bin/env python3
"""Conformance and hostile tests for the evaluator-owned arm contract."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib

from arm_adapter_contract import (
    AdapterContractReject,
    parse_input,
    parse_output,
)
from independent_arm_adapter_contract import (
    IndependentAdapterReject,
    verify as independent_verify,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULT = HERE / "results/phase83_arm_adapter_contract_conformance.json"
EMPTY = hashlib.sha256(b"{}").hexdigest()
H = "a" * 64


def canonical(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode()


def fixture() -> tuple[dict, dict]:
    request = {
        "version": "FOUNDRY_ARM_ADAPTER_INPUT_V1",
        "arm_id": "A3",
        "artifact": {
            "artifact_id": "synthetic-contract-fixture",
            "source_sha256": H,
            "family": "contract_fixture",
            "repository": "local/evaluator",
            "semantic_domain": "typed_dag_contract",
            "graph_ir_sha256": H,
            "shape_seed_sha256": H,
        },
        "budgets": {
            "wall_limit_seconds": 10,
            "cpu_limit_seconds": 8,
            "rss_limit_kib": 262144,
            "search_unit_limit": 1000,
        },
        "execution": {
            "invocations": 3,
            "pairing_unit": "artifact",
            "retain_individual_invocation_receipts": True,
        },
        "sealed_inputs": {
            "candidate_library_sha256": H,
            "fixed_portfolio_sha256": H,
            "protocol_freeze_sha256": H,
        },
    }
    response = {
        "version": "FOUNDRY_ARM_ADAPTER_OUTPUT_V1",
        "arm_id": "A3",
        "artifact_id": "synthetic-contract-fixture",
        "status": "PASS",
        "state_policy": {
            "state_before_sha256": EMPTY,
            "state_after_sha256": EMPTY,
            "library_retained_across_artifacts": False,
        },
        "tool_receipts": [],
        "cost_ledger": {
            "candidate_generation_cpu_ns": 10,
            "verification_cpu_ns": 20,
            "compiler_cpu_ns": 30,
            "selector_cpu_ns": 40,
            "executed_workload_cpu_ns": 50,
            "failed_attempt_cpu_ns": 0,
            "total_cpu_ns": 150,
        },
        "correctness": {
            "invocation_receipts": [
                {"ordinal": index, "output_sha256": H, "correct": True}
                for index in (1, 2, 3)
            ],
            "all_invocations_correct": True,
            "max_abs_error": 0.0,
            "alias_storage_checks_passed": True,
        },
        "resources": {
            "wall_ns": 200,
            "peak_group_rss_kib": 1000,
            "observed_process_count": 1,
            "process_group_reaped": True,
            "termination": "natural",
        },
        "provenance": {
            "adapter_sha256": H,
            "artifact_source_sha256": H,
            "protocol_freeze_sha256": H,
            "validation_v6_outcome_mounted": False,
        },
    }
    return request, response


def rejected(request: dict, response: dict) -> bool:
    raw_request = canonical(request)
    raw_response = canonical(response)
    primary = independent = False
    try:
        parsed = parse_input(raw_request)
        parse_output(raw_response, parsed)
    except (AdapterContractReject, ValueError, KeyError, TypeError):
        primary = True
    try:
        independent_verify(raw_request, raw_response)
    except (
        IndependentAdapterReject,
        ValueError,
        KeyError,
        TypeError,
    ):
        independent = True
    return primary and independent


def run() -> None:
    contract = json.loads(
        (HERE / "ARM_ADAPTER_CONTRACT_V1.json").read_text()
    )
    request, response = fixture()
    parsed = parse_input(canonical(request))
    accepted = parse_output(canonical(response), parsed)
    independent = independent_verify(
        canonical(request), canonical(response)
    )
    hostile = []

    def attack(name: str, mutate) -> None:
        req, out = copy.deepcopy(request), copy.deepcopy(response)
        mutate(req, out)
        hostile.append({"name": name, "rejected_twice": rejected(req, out)})

    attack("unknown_arm", lambda req, out: req.update(arm_id="A11"))
    attack("extra_input_field", lambda req, out: req.update(leak=True))
    attack(
        "negative_cost",
        lambda req, out: out["cost_ledger"].update(selector_cpu_ns=-1),
    )
    attack(
        "bad_cost_sum",
        lambda req, out: out["cost_ledger"].update(total_cpu_ns=151),
    )
    attack(
        "wrong_invocation_count",
        lambda req, out: req["execution"].update(invocations=2),
    )
    attack(
        "incorrect_PASS",
        lambda req, out: out["correctness"].update(
            all_invocations_correct=False
        ),
    )
    attack(
        "retained_A3_state",
        lambda req, out: out["state_policy"].update(
            library_retained_across_artifacts=True
        ),
    )
    attack(
        "artifact_identity_mismatch",
        lambda req, out: out.update(artifact_id="different"),
    )
    attack(
        "mounted_private_outcome",
        lambda req, out: out["provenance"].update(
            validation_v6_outcome_mounted=True
        ),
    )
    checks = {
        "ten_required_arms_named": contract["required_arms"]
        == [f"A{index}" for index in range(10)],
        "fixture_primary_accepts": accepted["status"] == "PASS",
        "fixture_independent_accepts": independent["status"] == "PASS",
        "nine_hostile_mutations_rejected_twice": (
            len(hostile) == 9
            and all(row["rejected_twice"] for row in hostile)
        ),
        "three_invocation_schedule_bound": (
            independent["invocations"] == 3
        ),
        "cost_sum_bound": independent["total_cpu_ns"] == 150,
        "A3_empty_state_bound": (
            accepted["state_policy"]["state_before_sha256"]
            == accepted["state_policy"]["state_after_sha256"]
            == EMPTY
        ),
        "integration_truth_not_inflated": (
            sum(
                value == "PRODUCTION_INTEGRATED"
                for value in contract["current_integration_truth"].values()
            )
            == 2
        ),
        "validation_v6_unread": contract[
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False,
        "prospective_unauthorized": contract[
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError("arm adapter contract conformance failed")
    payload = {
        "version": "FOUNDRY_ARM_ADAPTER_CONFORMANCE_V1",
        "status": "ARM_ADAPTER_CONTRACT_CONFORMANCE_PASS",
        "checks": checks,
        "hostile_rejections": hostile,
        "fixture": {
            "arm_id": independent["arm_id"],
            "artifact_id": independent["artifact_id"],
            "invocations": independent["invocations"],
            "total_cpu_ns": independent["total_cpu_ns"],
        },
        "integration": {
            "contract_ready": True,
            "required_arms_named": 10,
            "production_integrated_arms": 2,
            "all_required_adapters_implemented": False,
        },
        "P3": {
            "evaluator_owned_contract_ready": True,
            "all_required_prospective_arms_metered": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload).decode() + "\n")
    print(
        "FOUNDRY_PHASE83_ARM_ADAPTER_CONFORMANCE"
        f" status={payload['status']}"
        " arms=10 hostile=9/9"
        " integrated=2/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
