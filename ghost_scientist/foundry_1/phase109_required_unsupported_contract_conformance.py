#!/usr/bin/env python3
"""Falsify the strict four-arm required-unsupported contract batch."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib

from independent_required_unsupported_contract_batch import (
    IndependentUnsupportedBatchReject,
    verify as verify_independent,
)
from required_unsupported_contract_batch import (
    MATRIX,
    assemble,
    canonical,
    digest,
    verify_primary,
)


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/"
    "REQUIRED_UNSUPPORTED_CONTRACT_BATCH_PROTOCOL_V1.json"
)
RESULT = (
    HERE
    / "results/phase109_required_unsupported_contract_conformance.json"
)


def rejected_twice(batch: dict, matrix: dict) -> bool:
    primary = independent = False
    try:
        verify_primary(batch)
    except (ValueError, KeyError, TypeError):
        primary = True
    try:
        verify_independent(batch, matrix)
    except (
        IndependentUnsupportedBatchReject,
        ValueError,
        KeyError,
        TypeError,
    ):
        independent = True
    return primary and independent


def reseal_input(binding: dict) -> None:
    binding["input_sha256"] = hashlib.sha256(
        canonical(binding["input"])
    ).hexdigest()


def reseal_output(binding: dict) -> None:
    binding["output_sha256"] = hashlib.sha256(
        canonical(binding["output"])
    ).hexdigest()


def reseal_receipt(batch: dict) -> None:
    shared = batch["shared_resource_receipts"][0]
    shared["receipt_id"] = digest(shared["body"])
    for binding in batch["artifact_bindings"]:
        binding["shared_resource_receipt_id"] = shared["receipt_id"]


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    matrix = json.loads(MATRIX.read_text())
    batch = assemble()
    primary = verify_primary(batch)
    independent = verify_independent(batch, matrix)
    hostile = []

    def attack(name: str, mutate) -> None:
        value = copy.deepcopy(batch)
        mutate(value)
        hostile.append(
            {
                "name": name,
                "rejected_twice": rejected_twice(value, matrix),
            }
        )

    attack(
        "changed_receipt_id",
        lambda value: value["shared_resource_receipts"][0].update(
            receipt_id="0" * 64
        ),
    )

    def receipt_body(value: dict) -> None:
        value["shared_resource_receipts"][0]["body"]["wall_ns"] = 1
        reseal_receipt(value)

    attack("changed_receipt_body_resealed", receipt_body)
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
        "changed_pair_arm",
        lambda value: value["artifact_bindings"][0].update(arm_id="A6"),
    )
    attack(
        "changed_reason",
        lambda value: value["artifact_bindings"][0].update(
            reason="GENERIC_FAILURE"
        ),
    )
    attack(
        "changed_evidence_digest",
        lambda value: value["artifact_bindings"][0].update(
            evidence_sha256="f" * 64
        ),
    )

    def candidate_evidence(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["input"]["sealed_inputs"][
            "candidate_library_sha256"
        ] = "e" * 64
        reseal_input(binding)

    attack("changed_candidate_evidence_resealed", candidate_evidence)

    def status_pass(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["output"]["status"] = "PASS"
        reseal_output(binding)

    attack("unsupported_relabelled_PASS", status_pass)

    def tool_receipt(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["output"]["tool_receipts"] = [
            {
                "tool_sha256": "d" * 64,
                "action": "none",
                "direct_use_count": 0,
            }
        ]
        reseal_output(binding)

    attack("unsupported_with_tool_receipt", tool_receipt)

    def invocation_receipt(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["output"]["correctness"]["invocation_receipts"] = [
            {"ordinal": 1, "output_sha256": "c" * 64, "correct": False}
        ]
        reseal_output(binding)

    attack("unsupported_with_invocation_receipt", invocation_receipt)

    def retained_state(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["output"]["state_policy"][
            "library_retained_across_artifacts"
        ] = True
        reseal_output(binding)

    attack("unsupported_with_retained_state", retained_state)

    def resource_projection(value: dict) -> None:
        binding = value["artifact_bindings"][0]
        binding["output"]["resources"]["peak_group_rss_kib"] = 1
        reseal_output(binding)

    attack("changed_resource_projection_resealed", resource_projection)
    attack(
        "changed_output_digest",
        lambda value: value["artifact_bindings"][0].update(
            output_sha256="b" * 64
        ),
    )
    attack(
        "changed_input_digest",
        lambda value: value["artifact_bindings"][0].update(
            input_sha256="a" * 64
        ),
    )

    def duplicate_cpu(value: dict) -> None:
        binding = next(
            row
            for row in value["artifact_bindings"]
            if row["arm_id"] == "A1"
            and row["output"]["cost_ledger"]["total_cpu_ns"] == 0
        )
        binding["output"]["cost_ledger"]["verification_cpu_ns"] = 1
        binding["output"]["cost_ledger"]["total_cpu_ns"] = 1
        reseal_output(binding)

    attack("duplicated_cpu_charge_resealed", duplicate_cpu)

    def omitted_cpu(value: dict) -> None:
        binding = next(
            row
            for row in value["artifact_bindings"]
            if row["arm_id"] == "A1"
            and row["output"]["cost_ledger"]["total_cpu_ns"] > 0
        )
        binding["output"]["cost_ledger"]["verification_cpu_ns"] = 0
        binding["output"]["cost_ledger"]["total_cpu_ns"] = 0
        reseal_output(binding)

    attack("omitted_cpu_charge_resealed", omitted_cpu)
    attack(
        "changed_aggregate_cpu",
        lambda value: value["aggregate_accounting"].update(
            allocated_ledger_cpu_ns=1
        ),
    )
    attack(
        "resource_multiplier_92",
        lambda value: value["aggregate_accounting"].update(
            resource_multiplier_applied=92
        ),
    )
    attack(
        "new_conformance_claim",
        lambda value: value["outcome_classification"].update(
            newly_conformant_arms=4
        ),
    )
    attack(
        "new_integration_claim",
        lambda value: value["outcome_classification"].update(
            newly_production_integrated_arms=4,
            production_integrated_arms=10,
        ),
    )
    attack(
        "P3_claim_removed",
        lambda value: value.update(P3_complete_resource_meter=False),
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
    checks = {
        "protocol_prefrozen": protocol["frozen_before_batch_assembly"],
        "primary_accepts": primary["status"]
        == "REQUIRED_UNSUPPORTED_BATCH_PRIMARY_PASS",
        "independent_accepts": independent["status"]
        == "REQUIRED_UNSUPPORTED_BATCH_INDEPENDENT_PASS",
        "92_base_contract_pairs_accept": (
            primary["pairs"] == independent["pairs"] == 92
            and batch["base_contract_primary_accepts"] == 92
            and batch["base_contract_independent_accepts"] == 92
        ),
        "one_unique_receipt_charged": (
            batch["aggregate_accounting"][
                "unique_resource_receipts_charged"
            ]
            == 1
            and batch["aggregate_accounting"][
                "resource_multiplier_applied"
            ]
            == 1
        ),
        "CPU_reconciles_exactly": (
            batch["aggregate_accounting"]["measured_process_cpu_ns"]
            == batch["aggregate_accounting"]["allocated_ledger_cpu_ns"]
            == primary["allocated_cpu_ns"]
            == independent["allocated_cpu_ns"]
            and batch["aggregate_accounting"]["cpu_charged_bindings"] == 4
        ),
        "exact_four_by_23_matrix": (
            batch["aggregate_accounting"]["arms"] == 4
            and batch["aggregate_accounting"]["artifacts_per_arm"] == 23
            and batch["aggregate_accounting"][
                "required_unsupported_outputs"
            ]
            == 92
        ),
        "twenty_five_hostile_batches_rejected_twice": (
            len(hostile) == 25
            and all(row["rejected_twice"] for row in hostile)
        ),
        "no_conformance_or_integration_inflation": (
            batch["outcome_classification"]["newly_conformant_arms"] == 0
            and batch["outcome_classification"][
                "newly_production_integrated_arms"
            ]
            == 0
            and batch["outcome_classification"][
                "production_integrated_arms"
            ]
            == 6
        ),
        "P3_resource_matrix_complete": batch[
            "P3_complete_resource_meter"
        ]
        is True,
        "validation_v6_unread": batch["validation_v6_accessed"] is False,
        "prospective_unauthorized": batch[
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "required-unsupported contract conformance failed: "
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
        "version": (
            "FOUNDRY_REQUIRED_UNSUPPORTED_CONTRACT_CONFORMANCE_V1"
        ),
        "status": "REQUIRED_UNSUPPORTED_CONTRACT_CONFORMANCE_PASS",
        "checks": checks,
        "primary": primary,
        "independent": independent,
        "receipt_id": batch["shared_resource_receipts"][0]["receipt_id"],
        "batch_sha256": hashlib.sha256(canonical(batch)).hexdigest(),
        "hostile_rejections": hostile,
        "integration": {
            "explicit_required_unsupported_arms": 4,
            "newly_conformant_arms": 0,
            "newly_production_integrated_arms": 0,
            "production_integrated_arms": 6,
            "required_arms": 10,
        },
        "P3": {
            "all_ten_required_arm_resource_paths_explicit": True,
            "complete_resource_meter": True,
            "complete": True,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload).decode() + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE109_REQUIRED_UNSUPPORTED_CONTRACT"
        f" status={payload['status']}"
        " pairs=92/92 receipt=1/1 CPU=EXACT hostile=25/25"
        " integrated=6/10 P3=true prospective=false"
    )


if __name__ == "__main__":
    main()
