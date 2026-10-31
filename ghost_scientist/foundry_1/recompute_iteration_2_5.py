#!/usr/bin/env python3
"""Recompute readiness after the pre-frozen Stitch metamorphic phase."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_stitch_metamorphic_result_v1 import (
    verify as verify_metamorphic_freeze,
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
    result_freeze = verify_metamorphic_freeze()
    prior, prior_sha = load(
        "readiness_iteration_2_4.json", "FOUNDRY_READINESS_ITERATION_2_4"
    )
    control, control_sha = load(
        "phase37_stitch_metamorphic_control.json",
        "FOUNDRY_STITCH_METAMORPHIC_CONTROL_V1",
    )
    resource, resource_sha = load(
        "phase38_stitch_metamorphic_resource_audit.json",
        "FOUNDRY_STITCH_METAMORPHIC_RESOURCE_AUDIT_V1",
    )
    if (
        control["status"] != "STITCH_METAMORPHIC_CONTROL_PASS"
        or resource["status"] != "STITCH_METAMORPHIC_RESOURCE_PASS"
    ):
        raise RuntimeError("Stitch metamorphic result is not passing")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_2_5",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "metamorphic_result_records_sha256": result_freeze[
            "records_sha256"
        ],
        "metamorphic_control_sha256": control_sha,
        "metamorphic_resource_sha256": resource_sha,
        "progress": {
            "metamorphic_protocol_pre_frozen": True,
            "alpha_renamed": True,
            "program_order_reversed": True,
            "exact_relation_passed": True,
            "metamorphic_control_arm_metered": True,
            "source_faithful_controls_reproduced": 1,
            "controls_required": 4,
            "P1_complete": False,
            "P3_complete": False,
        },
        "interpretation": (
            "The pre-execution-frozen alpha-renamed and reordered fixture "
            "preserved Stitch's abstraction body, arity, costs, utility, and "
            "use count while producing the exact renamed rewrites. This "
            "falsifies the narrow concern that the generic runner only "
            "returns the published symbols or ordering. It remains one "
            "control on one structural motif, not heterogeneous evidence."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "seek and execute a second independent public control from "
                "pinned upstream source, starting with Enumo source closure"
            ),
            "forbidden_shortcuts": [
                "do not count metamorphic variants as separate controls",
                "do not claim official wheel execution",
                "do not start the v6 trial with only one of four controls",
            ],
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_2_5.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_2_5_NOT_READY"
        " metamorphic=PASS controls=1/4"
        " next=ENUMO_SOURCE"
    )


if __name__ == "__main__":
    run()
