#!/usr/bin/env python3
"""Recompute readiness after Babble source structural conformance."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_babble_source_result_v1 import verify as verify_babble_result


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    raw = (RESULTS / name).read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    result_freeze = verify_babble_result()
    prior, prior_sha = load(
        "readiness_iteration_2_7.json", "FOUNDRY_READINESS_ITERATION_2_7"
    )
    control, control_sha = load(
        "phase41_babble_source_control.json",
        "FOUNDRY_BABBLE_SOURCE_CONTROL_V1",
    )
    resource, resource_sha = load(
        "phase42_babble_source_resource_audit.json",
        "FOUNDRY_BABBLE_SOURCE_RESOURCE_AUDIT_V1",
    )
    if (
        control["status"] != "BABBLE_SOURCE_CONTROL_STRUCTURAL_PASS"
        or resource["status"] != "BABBLE_SOURCE_CONTROL_RESOURCE_PASS"
    ):
        raise RuntimeError("Babble source result is not passing")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_2_8",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "babble_result_records_sha256": result_freeze["records_sha256"],
        "babble_control_sha256": control_sha,
        "babble_resource_sha256": resource_sha,
        "progress": {
            "babble_revision_pinned": True,
            "babble_egg_revision_pinned": True,
            "verified_upstream_git_blobs": 62,
            "babble_core_executed": True,
            "babble_structural_conformance_passed": True,
            "babble_readme_numeric_claim_exact": False,
            "babble_process_tree_metered": True,
            "source_faithful_controls_reproduced": 2,
            "controls_required": 4,
            "P1_complete": False,
            "P3_complete": False,
        },
        "interpretation": (
            "Pinned Babble POPL23 and its lockfile-selected Egg fork now execute "
            "from 62 exact upstream Git blobs under a deterministic build "
            "adaptation. The source learns the published repeated-triple "
            "library and rewrites the four examples with one library. Its "
            "AstSize result is 29 to 22, while the README says 29 to 23; that "
            "numeric discrepancy remains explicit. The complete build and "
            "control process tree passed accounting with nine processes. This "
            "closes a second source-faithful control, not the 4/4 prerequisite."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "freeze and run an independently transformed Babble fixture, "
                "then pursue a third executable pinned control"
            ),
            "forbidden_shortcuts": [
                "do not relabel the reduced build as the full official CLI",
                "do not silently change README cost 23 to source cost 22",
                "do not count one control twice for two fixtures",
                "do not start the v6 prospective trial at 2/4 controls",
            ],
        },
        "remaining_blockers": [
            "obtain two more executable pinned independent controls",
            "run paper-derived conformance fixtures for remaining controls",
            "add heterogeneous application workloads and an independent invocation trace",
            "integrate the complete final resource and native-dedup arm matrix",
            "resolve the strong-fixed tie without weakening the fixed portfolio",
        ],
    }
    (RESULTS / "readiness_iteration_2_8.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_2_8_NOT_READY"
        " babble_structural=PASS readme_cost_exact=false"
        " controls=2/4 verdict=FOUNDRY_V6_NOT_READY"
    )


if __name__ == "__main__":
    run()
