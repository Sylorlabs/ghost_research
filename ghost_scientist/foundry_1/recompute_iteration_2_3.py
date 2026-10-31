#!/usr/bin/env python3
"""Recompute readiness after the first faithful external-control attempt."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_external_control_execution_v1 import verify as verify_prefreeze
from freeze_external_control_result_v1 import verify as verify_result_freeze


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    raw = (RESULTS / name).read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    prefreeze = verify_prefreeze()
    result_freeze = verify_result_freeze()
    prior, prior_sha = load(
        "readiness_iteration_2_2.json", "FOUNDRY_READINESS_ITERATION_2_2"
    )
    control, control_sha = load(
        "phase33_stitch_control_conformance.json",
        "FOUNDRY_STITCH_CONTROL_CONFORMANCE_V1",
    )
    resource, resource_sha = load(
        "phase34_stitch_control_resource_audit.json",
        "FOUNDRY_STITCH_CONTROL_RESOURCE_AUDIT_V1",
    )
    if (
        control["status"] != "STITCH_CONTROL_INFRASTRUCTURE_FAILURE"
        or resource["status"]
        != "STITCH_CONTROL_RESOURCE_INFRASTRUCTURE_FAILURE"
    ):
        raise RuntimeError("Stitch control result is not expected")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_2_3",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "control_prefreeze_records_sha256": prefreeze["records_sha256"],
        "control_result_records_sha256": result_freeze["records_sha256"],
        "stitch_control_sha256": control_sha,
        "stitch_resource_sha256": resource_sha,
        "progress": {
            "official_control_protocol_frozen": True,
            "official_fixture_frozen": True,
            "implementation_revision_pinned": True,
            "binding_revision_pinned": True,
            "wheel_sha256_pinned": True,
            "artifact_present": control["artifact_present"],
            "artifact_sha256_verified": control[
                "artifact_sha256_verified"
            ],
            "official_backend_executed": control[
                "official_backend_executed"
            ],
            "conformance_executed": control["conformance_executed"],
            "conformance_passed": control["conformance_passed"],
            "stitch_control_arm_metered": resource["P3"][
                "stitch_control_arm_integrated"
            ],
            "controls_reproduced": resource["P1"]["controls_reproduced"],
            "controls_required": resource["P1"]["controls_required"],
            "P1_complete": resource["P1"]["complete"],
            "P3_complete": resource["P3"]["complete"],
        },
        "interpretation": (
            "The first external-control protocol is now executable and "
            "fail-closed. It pins the official Stitch implementation, official "
            "Python binding, exact manylinux wheel hash, official x-x-x "
            "fixture, expected abstraction and rewrites, and process-tree "
            "limits. Execution stopped before import because the pinned wheel "
            "was not locally available. The control was not run and remains "
            "unreproduced; the natural metered failure proves only that the "
            "harness correctly distinguishes infrastructure from a control "
            "outcome."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "seek a control whose official executable artifact is "
                "obtainable through the connected source channel; retain the "
                "frozen Stitch harness for immediate execution if the exact "
                "pinned wheel becomes locally available"
            ),
            "forbidden_shortcuts": [
                "do not count official expected output as execution",
                "do not import an unverified installed package",
                "do not substitute a local Stitch approximation",
                "do not classify missing transport as a failed algorithm",
            ],
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_2_3.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_2_3_NOT_READY"
        f" stitch_artifact_present={str(control['artifact_present']).lower()}"
        f" conformance_executed={str(control['conformance_executed']).lower()}"
        f" controls={resource['P1']['controls_reproduced']}/"
        f"{resource['P1']['controls_required']}"
        " metered=true"
    )


if __name__ == "__main__":
    run()
