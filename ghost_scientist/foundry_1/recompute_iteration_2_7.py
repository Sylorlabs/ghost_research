#!/usr/bin/env python3
"""Recompute readiness after selecting the control-two recovery route."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_control_two_route_v1 import verify as verify_route_freeze


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    raw = (RESULTS / name).read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    route_freeze = verify_route_freeze()
    prior, prior_sha = load(
        "readiness_iteration_2_6.json", "FOUNDRY_READINESS_ITERATION_2_6"
    )
    route, route_sha = load(
        "phase40_control_two_route_audit.json",
        "FOUNDRY_CONTROL_TWO_ROUTE_AUDIT_V1",
    )
    if route["status"] != "CONTROL_TWO_ROUTE_SELECTED_NOT_EXECUTABLE":
        raise RuntimeError("control-two route result is not expected")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_2_7",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "route_records_sha256": route_freeze["records_sha256"],
        "route_sha256": route_sha,
        "progress": {
            "babble_branch_resolved_to_commit": True,
            "babble_manifest_and_lock_pinned": True,
            "babble_dependencies_available": 13,
            "babble_dependencies_total": 21,
            "enumo_dependencies_available": 10,
            "enumo_dependencies_total": 21,
            "selected_control_two_route": "babble_popl23",
            "control_two_executed": False,
            "source_faithful_controls_reproduced": 1,
            "controls_required": 4,
            "P1_complete": False,
            "P3_complete": False,
        },
        "interpretation": (
            "The Babble POPL23 branch resolves to commit "
            "09ff03fd485a3e24178c1d706a5944a230123ba1 and its lockfile pins "
            "the required Egg fork to caf623cad25cacba83193464dcf0d3dd4161ba7a. "
            "Babble has 13/21 required direct dependencies locally available, "
            "a smaller missing closure than Enumo's 10/21 availability. "
            "ISAMORE is larger still, with four path workspaces, a Git Egg "
            "fork, a pinned nightly toolchain, and JLM. Babble is selected for "
            "recovery, but no second control has executed."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "recover the complete byte-exact Babble source, its local "
                "babble-macros workspace, and pinned Egg fork, then close the "
                "eight missing direct packages before freezing conformance"
            ),
            "forbidden_shortcuts": [
                "do not count route selection as execution",
                "do not substitute stock Egg for the pinned fork",
                "do not omit the local macro workspace",
                "do not increment the control count",
            ],
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_2_7.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_2_7_NOT_READY"
        " selected=babble_popl23 babble_deps=13/21"
        " control_two_executed=false controls=1/4"
    )


if __name__ == "__main__":
    run()
