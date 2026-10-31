#!/usr/bin/env python3
"""Recompute readiness after the exact kiddo closure census."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_12.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v13_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["locked_packages"] == 56
        and freeze["exact_cached_archives"] == 34
        and freeze["next_stop"] == "kiddo"
    ):
        raise RuntimeError("iteration 5.13 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_13",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_kiddo_locked_closure_packages": 56,
            "isamore_kiddo_exact_cached_archives": 34,
            "isamore_kiddo_missing_exact_archives": 22,
            "isamore_offline_build_stop_before_phase": "kiddo",
            "isamore_offline_build_stop_after_phase": "kiddo",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The kiddo frontier is exact: 34 of 56 locked closure packages "
            "have checksum-authenticated archives and 22 do not. No resolver "
            "advance, compilation, execution, or validation access occurred."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "twenty-two exact kiddo closure archives are absent",
            "the pinned nightly and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "acquire the kiddo-specific math and data-structure family "
                "before generic tracing and platform dependencies"
            ),
            "forbidden_shortcuts": [
                "do not count tag source as archive identity",
                "do not call a closure census compilation or execution",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_13.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_13"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 kiddo_closure=34/56"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
