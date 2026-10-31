#!/usr/bin/env python3
"""Recompute readiness after the exact official-tag csv bridge."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_5.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v6_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["authorization"]["prerequisites_passed"] == 5
        and freeze["prior_stop"] == "csv"
        and freeze["next_stop"] == "env_logger"
        and freeze["control_executed"] is False
    ):
        raise RuntimeError("iteration 5.6 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_6",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_official_tag_packages_bridged": 6,
            "isamore_official_tag_records_added": 27,
            "isamore_offline_build_stop_before_phase": "csv",
            "isamore_offline_build_stop_after_phase": "env_logger",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "Exact official release-tag source for all four missing csv-closure "
            "packages advances the metered Cargo stop to env_logger. The tag "
            "source is not mislabeled as crates.io checksum reproduction. "
            "ISAMORE has not compiled or executed and v6 remains sealed."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "the offline build now stops at missing env_logger",
            "six package bridges use exact official-tag source rather than crates.io archive identity",
            "the pinned nightly-2024-12-25 toolchain and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
            "no candidate runtime invention survives native compiler deduplication",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "audit the exact locked env_logger transitive closure and "
                "continue only with authenticated source"
            ),
            "forbidden_shortcuts": [
                "do not label official Git tag source as crates.io checksum reproduction",
                "do not call dependency resolution algorithm compilation or execution",
                "do not mock SMT, LP, or hardware scoring",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    path = RESULTS / "readiness_iteration_5_6.json"
    path.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_6"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 build_stop=csv_to_env_logger"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
