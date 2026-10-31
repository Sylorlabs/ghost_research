#!/usr/bin/env python3
"""Recompute readiness after source-faithful Stitch conformance."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_stitch_source_result_v1 import verify as verify_source_freeze


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    raw = (RESULTS / name).read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    source_freeze = verify_source_freeze()
    prior, prior_sha = load(
        "readiness_iteration_2_3.json", "FOUNDRY_READINESS_ITERATION_2_3"
    )
    control, control_sha = load(
        "phase35_stitch_source_control.json",
        "FOUNDRY_STITCH_SOURCE_CONTROL_V1",
    )
    resource, resource_sha = load(
        "phase36_stitch_source_resource_audit.json",
        "FOUNDRY_STITCH_SOURCE_RESOURCE_AUDIT_V1",
    )
    if (
        control["status"] != "STITCH_SOURCE_CONTROL_CONFORMANCE_PASS"
        or resource["status"] != "STITCH_SOURCE_CONTROL_RESOURCE_PASS"
    ):
        raise RuntimeError("source-faithful Stitch result is not passing")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_2_4",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "source_result_records_sha256": source_freeze["records_sha256"],
        "source_control_sha256": control_sha,
        "source_resource_sha256": resource_sha,
        "progress": {
            "upstream_stitch_algorithm_blobs_exact": 12,
            "upstream_lambdas_blobs_exact": 16,
            "upstream_algorithm_source_executed": True,
            "official_fixture_conformance_passed": True,
            "official_wheel_executed": False,
            "official_binding_executed": False,
            "source_control_arm_metered": True,
            "source_faithful_controls_reproduced": 1,
            "official_binary_controls_reproduced": 0,
            "controls_required": 4,
            "P1_complete": False,
            "P3_complete": False,
        },
        "interpretation": (
            "Byte-exact upstream Stitch and Lambdas algorithm sources built "
            "and executed the already-frozen official fixture. The exact "
            "abstraction, rewrites, costs, utility, and use count matched. "
            "The build and execution were process-tree metered. Local shims "
            "replace unavailable Clap parsing and terminal coloring, and "
            "itertools 0.12.1 replaces upstream 0.10.x, so this is one "
            "source-faithful control reproduction rather than an official "
            "wheel or binding reproduction."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "execute the pre-frozen renamed and reordered metamorphic "
                "fixture, then pursue a second independent public control"
            ),
            "forbidden_shortcuts": [
                "do not label the source build as the official wheel",
                "do not hide dependency substitutions",
                "do not infer heterogeneous performance from one fixture",
                "do not count one control as the required four",
            ],
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_2_4.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_2_4_NOT_READY"
        " source_control=PASS controls=1/4"
        " official_wheel=false metered=true"
    )


if __name__ == "__main__":
    run()
