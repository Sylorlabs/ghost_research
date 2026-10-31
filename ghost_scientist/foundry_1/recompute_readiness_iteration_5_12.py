#!/usr/bin/env python3
"""Recompute readiness after the official-tag indicatif-family bridge."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_11.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v12_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["bridged_packages"] == 4
        and freeze["source_records"] == 35
        and freeze["next_stop"] == "kiddo"
    ):
        raise RuntimeError("iteration 5.12 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_12",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_indicatif_family_packages_bridged": 4,
            "isamore_indicatif_family_source_records": 35,
            "isamore_offline_build_stop_before_phase": "indicatif",
            "isamore_offline_build_stop_after_phase": "kiddo",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "Four exact official-tag indicatif-family packages match 35 Git "
            "blobs and move the identical resolver stop to kiddo. No algorithm "
            "compilation, execution, or validation access occurred."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "the offline build now stops at missing kiddo",
            "the pinned nightly and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": "audit the exact locked kiddo closure",
            "forbidden_shortcuts": [
                "do not count tag source as archive identity",
                "do not call resolver progress compilation or execution",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_12.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_12"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 next_stop=kiddo"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
