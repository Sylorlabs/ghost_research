#!/usr/bin/env python3
"""Falsification gate for A4 contract batch and shared resource identity."""

from __future__ import annotations

import copy
import hashlib
import json
import pathlib

from a4_shared_resource_batch import (
    assemble,
    canonical,
    verify_primary,
)
from independent_a4_shared_resource_batch import (
    IndependentA4BatchReject,
    verify as verify_independent,
)


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE / "arm_adapter_fixtures/A4_SHARED_RESOURCE_BATCH_PROTOCOL_V1.json"
)
RESULT = HERE / "results/phase97_a4_shared_resource_batch_conformance.json"


def rejected_twice(batch: dict) -> bool:
    primary = independent = False
    try:
        verify_primary(batch)
    except (ValueError, KeyError, TypeError):
        primary = True
    try:
        verify_independent(batch)
    except (IndependentA4BatchReject, ValueError, KeyError, TypeError):
        independent = True
    return primary and independent


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
        "changed_resource_projection",
        lambda value: value["artifact_bindings"][0]["output"][
            "resources"
        ].update(peak_group_rss_kib=1),
    )
    attack(
        "changed_retained_state",
        lambda value: value["artifact_bindings"][0]["output"][
            "state_policy"
        ].update(state_after_sha256="e" * 64),
    )
    attack(
        "wrong_zero_use_action",
        lambda value: next(
            item
            for binding in value["artifact_bindings"]
            for item in binding["output"]["tool_receipts"]
            if item["direct_use_count"] == 0
        ).update(action="reused"),
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
    bindings = batch["artifact_bindings"]
    checks = {
        "protocol_prefrozen": protocol["frozen_before_batch_assembly"],
        "primary_accepts": primary["status"]
        == "A4_SHARED_RESOURCE_BATCH_PRIMARY_PASS",
        "independent_accepts": independent["status"]
        == "A4_SHARED_RESOURCE_BATCH_INDEPENDENT_PASS",
        "23_base_contract_pairs_accept": (
            len(bindings) == 23
            and batch["base_contract_primary_accepts"] == 23
            and batch["base_contract_independent_accepts"] == 23
        ),
        "one_unique_receipt_charged": batch["aggregate_accounting"]
        == {
            "artifact_outputs": 23,
            "unique_resource_receipts_charged": 1,
            "resource_receipt_references": 23,
            "resource_multiplier_applied": 1,
        },
        "all_binding_digests_unique": (
            len({row["input_sha256"] for row in bindings}) == 23
            and len({row["output_sha256"] for row in bindings}) == 23
        ),
        "retained_state_consistent": len(
            {
                row["output"]["state_policy"]["state_before_sha256"]
                for row in bindings
            }
        )
        == 1,
        "all_three_tools_visible_per_artifact": all(
            len(row["output"]["tool_receipts"]) == 3
            for row in bindings
        ),
        "eleven_hostile_batches_rejected_twice": (
            len(hostile) == 11
            and all(row["rejected_twice"] for row in hostile)
        ),
        "integration_advances_exactly_one_arm": (
            protocol["claim_boundary"][
                "production_integrated_arms_before_pass"
            ]
            == 4
            and protocol["claim_boundary"][
                "production_integrated_arms_after_pass"
            ]
            == 5
        ),
        "P3_still_incomplete": batch["P3_complete"] is False,
        "validation_v6_unread": batch["validation_v6_accessed"] is False,
        "prospective_unauthorized": batch[
            "prospective_trial_authorized"
        ]
        is False,
    }
    if not all(checks.values()):
        raise RuntimeError(
            "A4 shared batch conformance failed: "
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
        "version": "FOUNDRY_A4_SHARED_RESOURCE_BATCH_CONFORMANCE_V1",
        "status": "A4_SHARED_RESOURCE_BATCH_CONFORMANCE_PASS",
        "checks": checks,
        "primary": primary,
        "independent": independent,
        "receipt_id": batch["shared_resource_receipts"][0]["receipt_id"],
        "batch_sha256": hashlib.sha256(canonical(batch)).hexdigest(),
        "hostile_rejections": hostile,
        "integration": {
            "A4": "PRODUCTION_INTEGRATED_CALIBRATION_ARM",
            "production_integrated_arms": 5,
            "required_arms": 10,
        },
        "P3": {
            "A4_complete_contract_batch_ready": True,
            "all_required_arms_integrated_and_metered": False,
            "complete": False,
        },
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(canonical(payload).decode() + "\n", encoding="utf-8")
    print(
        "FOUNDRY_PHASE97_A4_SHARED_RESOURCE_BATCH"
        f" status={payload['status']}"
        " base_pairs=23/23 shared_receipts=1/1 hostile=11/11"
        " integrated=5/10 P3=false prospective=false"
    )


if __name__ == "__main__":
    main()
