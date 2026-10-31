#!/usr/bin/env python3
"""Recompute readiness after pre-frozen Babble metamorphic validation."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_babble_metamorphic_result_v1 import (
    verify as verify_metamorphic_result,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    raw = (RESULTS / name).read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    result_freeze = verify_metamorphic_result()
    prior, prior_sha = load(
        "readiness_iteration_2_8.json", "FOUNDRY_READINESS_ITERATION_2_8"
    )
    control, control_sha = load(
        "phase43_babble_metamorphic_control.json",
        "FOUNDRY_BABBLE_METAMORPHIC_CONTROL_V1",
    )
    resource, resource_sha = load(
        "phase44_babble_metamorphic_resource_audit.json",
        "FOUNDRY_BABBLE_METAMORPHIC_RESOURCE_AUDIT_V1",
    )
    if (
        control["status"] != "BABBLE_METAMORPHIC_CONTROL_PASS"
        or resource["status"] != "BABBLE_METAMORPHIC_RESOURCE_PASS"
    ):
        raise RuntimeError("Babble metamorphic result is not passing")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_2_9",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "babble_metamorphic_records_sha256": result_freeze["records_sha256"],
        "babble_metamorphic_control_sha256": control_sha,
        "babble_metamorphic_resource_sha256": resource_sha,
        "progress": {
            "babble_metamorphic_prefrozen": True,
            "published_values_reused": False,
            "published_order_reused": False,
            "metamorphic_relation_passed": True,
            "metamorphic_process_tree_metered": True,
            "source_faithful_controls_reproduced": 2,
            "controls_required": 4,
            "P1_complete": False,
            "P3_complete": False,
        },
        "interpretation": (
            "Before execution, the Babble build, fixture, exact expected "
            "relation, and limits were frozen. The source then learned the same "
            "triple-repetition abstraction for new values in a new order and "
            "produced the exact predeclared rewrite at invariant costs 29 to "
            "22. The eight-process tree passed accounting. This rules out "
            "literal README-value hardcoding, but the motif is unchanged and "
            "the experiment remains one control arm."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "pursue a third independent control through a measured "
                "executable-closure audit; do not add more same-motif Babble "
                "fixtures unless they test a distinct failure hypothesis"
            ),
            "forbidden_shortcuts": [
                "do not count the metamorphic fixture as a third control",
                "do not call same-motif robustness heterogeneous performance",
                "do not start the v6 prospective trial at 2/4 controls",
            ],
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_2_9.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_2_9_NOT_READY"
        " babble_metamorphic=PASS controls=2/4"
        " verdict=FOUNDRY_V6_NOT_READY"
    )


if __name__ == "__main__":
    run()
