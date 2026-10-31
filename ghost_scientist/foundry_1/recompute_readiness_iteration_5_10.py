#!/usr/bin/env python3
"""Recompute readiness after the graphviz-family bridge."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_9.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v10_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["bridged_packages"] == 5
        and freeze["next_stop"] == "indicatif"
        and freeze["control_executed"] is False
    ):
        raise RuntimeError("iteration 5.10 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_10",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_graphviz_family_packages_bridged": 5,
            "isamore_graphviz_family_source_records": 16,
            "isamore_offline_build_stop_before_phase": "graphviz-rust",
            "isamore_offline_build_stop_after_phase": "indicatif",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "Five exact graphviz-family package versions from two pinned "
            "official repository commits advance the metered resolver to "
            "indicatif. No tag/archive identity, compilation, or execution is claimed."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "the offline build now stops at indicatif",
            "the graphviz bridge is pinned-commit source, not release-tag or archive identity",
            "the pinned nightly and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": "audit the exact locked indicatif closure",
            "forbidden_shortcuts": [
                "do not invent a graphviz release tag",
                "do not call resolver progress compilation or execution",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_10.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_10"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10"
        " build_stop=graphviz-rust_to_indicatif prospective=false"
    )


if __name__ == "__main__":
    main()
