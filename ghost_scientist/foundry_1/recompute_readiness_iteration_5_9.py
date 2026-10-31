#!/usr/bin/env python3
"""Recompute readiness after the graphviz-rust closure census."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_8.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v9_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["locked_packages"] == 77
        and freeze["exact_cached_archives"] == 57
        and freeze["next_stop"] == "graphviz-rust"
    ):
        raise RuntimeError("iteration 5.9 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_9",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_graphviz_locked_closure_packages": 77,
            "isamore_graphviz_exact_cached_archives": 57,
            "isamore_graphviz_missing_exact_archives": 20,
            "isamore_offline_build_stop_before_phase": "graphviz-rust",
            "isamore_offline_build_stop_after_phase": "graphviz-rust",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The graphviz-rust frontier is now exact: 57 of 77 locked closure "
            "packages have checksum-authenticated archives and 20 do not. No "
            "stop advanced, algorithm compiled, control executed, or v6 data opened."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "twenty exact graphviz-rust closure archives are absent",
            "the pinned nightly and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "acquire the graphviz-specific package family first, preserving "
                "archive-versus-tag provenance"
            ),
            "forbidden_shortcuts": [
                "do not count tag source as archive identity",
                "do not call a closure census compilation or execution",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_9.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_9"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 graphviz_closure=57/77"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
