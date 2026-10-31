#!/usr/bin/env python3
"""Falsification gate for the A5 contract batch and shared accounting."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib

from a5_shared_resource_batch import assemble, canonical, verify_primary
from independent_a5_shared_resource_batch import (
    IndependentA5BatchReject,
    verify as verify_independent,
)


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/A5_SHARED_RESOURCE_BATCH_PROTOCOL_V1.json"
)
RESULT = (
    HERE / "results/phase103_a5_shared_resource_batch_conformance.json"
)


def rejected_twice(batch: dict) -> bool:
    primary = independent = False
    try:
        verify_primary(batch)
    except (ValueError, KeyError, TypeError):
        primary = True
    try:
        verify_independent(batch)
    except (
        IndependentA5BatchReject,
        ValueError,
        KeyError,
        TypeError,
    ):
        independent = True
    return primary and independent


def reseal_output(binding: dict) -> None:
    binding["output_sha256"] = hashlib.sha256(
        canonical(binding["output"])
    ).hexdigest()


def reseal_input(binding: dict) -> None:
    binding["input_sha256"] = hashlib.sha256(
        canonical(binding["input"])
    ).hexdigest()


def reseal_receipt(batch: dict) -> None:
    shared = batch["shared_resource_receipts"][0]
    shared["receipt_id"] = hashlib.sha256(
        canonical(shared["body"])
    ).hexdigest()
    for binding in batch["artifact_bindings"]:
        binding["shared_resource_receipt_id"] = shared["receipt_id"]


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    batch = assemble()
    primary = verify_primary(batch)
    independent = verify_independent(batch)
    hostile = []

    def attack(name: str, mutate) -> None:
        value = copy.deepcopy(batch)
        mutate(value)
        hostile.append(
            {"name": name, "rejected_twice": rejected_twice(value)}
        )

    attack(
        "changed_receipt_id",
        lambda value: value["shared_resource_receipts"][0].update(
            receipt_id="0" * 64
        ),
    )

    def changed_receipt_body(value: dict) -> None:
        value["shared_resource_receipts"][0]["body"]["wall_ns"] = 1
        reseal_receipt(value)

    attack("changed_receipt_body_resealed", changed_receipt_body)
    attack(
        "missing_binding", lambda value: value["artifact_bindings"].pop()
    )
    attack(
        "duplicate_binding",
        lambda value: value["artifact_bindings"].__setitem__(
            1, copy.deepcopy(value["artifact_bindings"][0])
        ),
    )
    attack(
        "changed_output_digest",
        lambda value: value["artifact_bindings"][0].update(
            output_sha256="f" * 64
        ),
    )
    attack(
        "changed_input_digest",
        lambda value: value["artifact_bindings"][0].update(
            input_sha256="e" * 64
        ),
    )

    def changed_projection(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["output"]["resources"]["peak_group_rss_kib"] = 1
        reseal_output(binding)

    attack("changed_resource_projection_resealed", changed_projection)

    def changed_state(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["output"]["state_policy"]["state_after_sha256"] = "d" * 64
        reseal_output(binding)

    attack("changed_retained_state_resealed", changed_state)

    def changed_library(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["input"]["sealed_inputs"][
            "candidate_library_sha256"
        ] = "c" * 64
        reseal_input(binding)

    attack("changed_candidate_library_resealed", changed_library)

    def changed_tool(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["output"]["tool_receipts"][0]["tool_sha256"] = "b" * 64
        reseal_output(binding)

    attack("changed_tool_digest_resealed", changed_tool)

    def changed_action(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["output"]["tool_receipts"][0]["action"] = "none"
        reseal_output(binding)

    attack("wrong_nonzero_action_resealed", changed_action)

    def changed_use(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["output"]["tool_receipts"][0]["direct_use_count"] += 1
        reseal_output(binding)

    attack("changed_direct_use_resealed", changed_use)
    attack(
        "changed_aggregate_uses",
        lambda value: value["aggregate_accounting"].update(
            direct_structural_uses=328
        ),
    )

    def duplicate_generation_charge(value: dict) -> None:
        first = value["artifact_bindings"][0]["output"]["cost_ledger"]
        second_binding = value["artifact_bindings"][1]
        second = second_binding["output"]["cost_ledger"]
        added = first["candidate_generation_cpu_ns"]
        second["candidate_generation_cpu_ns"] = added
        second["total_cpu_ns"] += added
        reseal_output(second_binding)

    attack("candidate_generation_charge_duplicated", duplicate_generation_charge)
    attack(
        "resource_multiplier_23",
        lambda value: value["aggregate_accounting"].update(
            resource_multiplier_applied=23
        ),
    )
    attack(
        "tensor_runtime_overclaim",
        lambda value: value["scientific_boundary"].update(
            rewritten_tensor_runtime_executed=True
        ),
    )
    attack(
        "validation_access_claim",
        lambda value: value.update(validation_v6_accessed=True),
    )
    attack(
        "prospective_claim_true",
        lambda value: value.update(prospective_trial_authorized=True),
    )
    attack(
        "unknown_batch_field",
        lambda value: value.update(unbound_claim=True),
    )
    bindings = batch["artifact_bindings"]
    checks = {
        "protocol_prefrozen": protocol["frozen_before_batch_assembly"],
        "primary_accepts": primary["status"]
        == "A5_SHARED_RESOURCE_BATCH_PRIMARY_PASS",
        "independent_accepts": independent["status"]
        == "A5_SHARED_RESOURCE_BATCH_INDEPENDENT_PASS",
        "23_base_contract_pairs_accept": (
            len(bindings) == 23
            and batch["base_contract_primary_accepts"] == 23
            and batch["base_contract_independent_accepts"] == 23
        ),
        "one_unique_receipt_charged": batch["aggregate_accounting"][
            "unique_resource_receipts_charged"
        ]
        == 1
        and batch["aggregate_accounting"]["resource_multiplier_applied"] == 1,
        "all_binding_digests_unique": (
            len({row["input_sha256"] for row in bindings}) == 23
            and len({row["output_sha256"] for row in bindings}) == 23
        ),
        "one_tool_each_329_uses": (
            all(
                len(row["output"]["tool_receipts"]) == 1
                for row in bindings
            )
            and batch["aggregate_accounting"]["direct_structural_uses"]
            == 329
        ),
        "candidate_generation_charged_once": batch[
            "aggregate_accounting"
        ]["candidate_generation_charged_artifacts"]
        == 1,
        "nineteen_hostile_batches_rejected_twice": (
            len(hostile) == 19
            and all(row["rejected_twice"] for row in hostile)
        ),
        "integration_advances_exactly_one_arm": (
            protocol["claim_boundary"][
                "production_integrated_arms_before_pass"
            ]
            == 5
            and protocol["claim_boundary"][
                "production_integrated_arms_after_pass"
            ]
            == 6
        ),
        "scientific_boundary_preserved": batch["scientific_boundary"]
        == {
            "normalized_rewrite_reversibility": True,
            "rewritten_tensor_runtime_executed": False,
            "tensor_primitive_invented": False,
            "heldout_generalization_measured": False,
            "fixed_portfolio_beaten": False,
        },
        "P3_still_incomplete": batch["P3_complete"] is False,
        "validation_v6_unread": batch["validation_v6_accessed"] is False,
        "prospective_unauthorized": batch[
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A5 shared batch conformance failed: "
            + canonical(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ],
                    "hostile": hostile,
                }
            ).decode()
        )
    payload = {
        "version": "FOUNDRY_A5_SHARED_RESOURCE_BATCH_CONFORMANCE_V1",
        "status": "A5_SHARED_RESOURCE_BATCH_CONFORMANCE_PASS",
        "checks": checks,
        "primary": primary,
        "independent": independent,
        "receipt_id": batch["shared_resource_receipts"][0]["receipt_id"],
        "batch_sha256": hashlib.sha256(canonical(batch)).hexdigest(),
        "hostile_rejections": hostile,
        "integration": {
            "A5": (
                "PRODUCTION_INTEGRATED_CALIBRATION_STRUCTURAL_CONTROL"
            ),
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3": {
            "A5_complete_contract_batch_ready": True,
            "all_required_arms_integrated_and_metered": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload).decode() + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE103_A5_SHARED_RESOURCE_BATCH"
        f" status={payload['status']}"
        " base_pairs=23/23 shared_receipts=1/1 uses=329"
        " hostile=19/19 integrated=6/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
