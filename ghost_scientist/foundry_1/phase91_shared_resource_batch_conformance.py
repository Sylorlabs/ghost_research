#!/usr/bin/env python3
"""Falsification gate for shared resource receipt batch assembly."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib

from independent_shared_resource_batch import (
    IndependentBatchReject,
    verify as independent_verify,
)
from shared_resource_batch import (
    assemble,
    canonical,
    verify_batch_primary,
)


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/SHARED_RESOURCE_RECEIPT_OVERLAY_V1.json"
)
RESULT = HERE / "results/phase91_shared_resource_batch_conformance.json"


def rejected_twice(batch: dict) -> bool:
    primary = independent = False
    try:
        verify_batch_primary(batch)
    except (ValueError, KeyError, TypeError):
        primary = True
    try:
        independent_verify(batch)
    except (IndependentBatchReject, ValueError, KeyError, TypeError):
        independent = True
    return primary and independent


def run() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    batches = {arm_id: assemble(arm_id) for arm_id in ("A3", "A9")}
    verification = {
        arm_id: {
            "primary": verify_batch_primary(batch),
            "independent": independent_verify(batch),
        }
        for arm_id, batch in batches.items()
    }
    hostile = []

    def attack(name: str, mutate) -> None:
        value = copy.deepcopy(batches["A3"])
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
    attack(
        "changed_receipt_body",
        lambda value: value["shared_resource_receipts"][0]["body"].update(
            wall_ns=1
        ),
    )
    attack(
        "missing_binding",
        lambda value: value["artifact_bindings"].pop(),
    )
    attack(
        "duplicate_artifact",
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
        "changed_resource_projection",
        lambda value: value["artifact_bindings"][0]["output"][
            "resources"
        ].update(peak_group_rss_kib=1),
    )
    attack(
        "resource_multiplier_23",
        lambda value: value["aggregate_accounting"].update(
            resource_multiplier_applied=23
        ),
    )
    attack(
        "prospective_claim_true",
        lambda value: value.update(prospective_trial_authorized=True),
    )
    attack(
        "unknown_batch_field",
        lambda value: value.update(unbound_claim=True),
    )
    all_bindings = [
        row for batch in batches.values() for row in batch["artifact_bindings"]
    ]
    receipt_ids = {
        arm_id: batch["shared_resource_receipts"][0]["receipt_id"]
        for arm_id, batch in batches.items()
    }
    checks = {
        "protocol_prefrozen": protocol["frozen_before_batch_assembly"],
        "both_primary_verifiers_accept": all(
            row["primary"]["status"]
            == "PRIMARY_SHARED_RESOURCE_BATCH_PASS"
            for row in verification.values()
        ),
        "both_independent_verifiers_accept": all(
            row["independent"]["status"]
            == "INDEPENDENT_SHARED_RESOURCE_BATCH_PASS"
            for row in verification.values()
        ),
        "46_base_contract_pairs_accept": (
            len(all_bindings) == 46
            and sum(
                batch["base_contract_primary_accepts"]
                for batch in batches.values()
            )
            == 46
            and sum(
                batch["base_contract_independent_accepts"]
                for batch in batches.values()
            )
            == 46
        ),
        "one_unique_receipt_per_arm": all(
            batch["aggregate_accounting"][
                "unique_resource_receipts_charged"
            ]
            == 1
            and batch["aggregate_accounting"][
                "resource_receipt_references"
            ]
            == 23
            and batch["aggregate_accounting"][
                "resource_multiplier_applied"
            ]
            == 1
            for batch in batches.values()
        ),
        "arm_receipts_are_distinct": len(set(receipt_ids.values())) == 2,
        "all_binding_digests_unique": (
            len({row["input_sha256"] for row in all_bindings}) == 46
            and len({row["output_sha256"] for row in all_bindings}) == 46
        ),
        "nine_hostile_batches_rejected_twice": (
            len(hostile) == 9
            and all(row["rejected_twice"] for row in hostile)
        ),
        "integration_advances_exactly_two_arms": (
            protocol["claim_boundary"][
                "production_integrated_arms_before_pass"
            ]
            == 2
            and protocol["claim_boundary"][
                "production_integrated_arms_after_pass"
            ]
            == 4
        ),
        "P3_still_incomplete": all(
            batch["P3_complete"] is False for batch in batches.values()
        ),
        "validation_v6_unread": all(
            batch["validation_v6_accessed"] is False
            for batch in batches.values()
        ),
        "prospective_unauthorized": all(
            batch["prospective_trial_authorized"] is False
            for batch in batches.values()
        ),
    }
    if not all(checks.values()):
        raise RuntimeError(
            "shared resource batch conformance failed: "
            + json.dumps(
                {
                    "failed": [
                        name for name, passed in checks.items() if not passed
                    ],
                    "hostile": hostile,
                },
                sort_keys=True,
            )
        )
    payload = {
        "version": "FOUNDRY_SHARED_RESOURCE_BATCH_CONFORMANCE_V1",
        "status": "SHARED_RESOURCE_BATCH_CONFORMANCE_PASS",
        "checks": checks,
        "verification": verification,
        "receipt_ids": receipt_ids,
        "hostile_rejections": hostile,
        "batch_sha256": {
            arm_id: hashlib.sha256(canonical(batch)).hexdigest()
            for arm_id, batch in batches.items()
        },
        "integration": {
            "A3": "PRODUCTION_INTEGRATED_CALIBRATION_ARM",
            "A9": "PRODUCTION_INTEGRATED_CALIBRATION_ARM",
            "production_integrated_arms": 4,
            "required_arms": 10,
        },
        "P3": {
            "shared_resource_receipt_identity_ready": True,
            "A3_A9_complete_contract_batches_ready": True,
            "all_required_arms_integrated_and_metered": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload).decode() + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE91_SHARED_RESOURCE_BATCH"
        f" status={payload['status']}"
        " base_pairs=46/46 shared_receipts=1/1,1/1"
        " hostile=9/9 integrated=4/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    run()
