#!/usr/bin/env python3
"""Recompute readiness after partial kiddo-family source authentication."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_13.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v14_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["bridged_packages"] == 3
        and freeze["source_records"] == 13
        and freeze["next_stop"] == "kiddo"
    ):
        raise RuntimeError("iteration 5.14 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_14",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_kiddo_partial_family_packages_bridged": 3,
            "isamore_kiddo_partial_family_source_records": 13,
            "isamore_kiddo_root_source_acquired": False,
            "isamore_offline_build_stop_before_phase": "kiddo",
            "isamore_offline_build_stop_after_phase": "kiddo",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "Three kiddo-family packages match 13 upstream Git blobs, but the "
            "exact kiddo 5.2.4 published root remains absent and the resolver "
            "stop does not advance. No compilation, execution, or validation "
            "access occurred."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "the exact published kiddo 5.2.4 root source is absent",
            "the pinned nightly and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "obtain exact published kiddo 5.2.4 source without rewriting "
                "the upstream repository manifest"
            ),
            "forbidden_shortcuts": [
                "do not rewrite an upstream version to satisfy the lock",
                "do not count tag or commit source as archive identity",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_14.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_14"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 kiddo_partial=3"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
