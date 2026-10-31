#!/usr/bin/env python3
"""Recompute readiness after the env_logger union-closure census."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_6.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v7_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["authorization"]["prerequisites_passed"] == 5
        and freeze["next_stop"] == "env_logger"
        and freeze["root_versions"] == 3
        and freeze["control_executed"] is False
    ):
        raise RuntimeError("iteration 5.7 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_7",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_env_logger_root_versions": 3,
            "isamore_env_logger_union_closure_packages": 31,
            "isamore_env_logger_exact_cached_archives": 14,
            "isamore_env_logger_missing_exact_archives": 17,
            "isamore_offline_build_stop_before_phase": "env_logger",
            "isamore_offline_build_stop_after_phase": "env_logger",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The env_logger stop expands to three locked generations and a "
            "31-package union closure. Fourteen exact archives are locally "
            "authenticated and seventeen are absent. A single-version patch "
            "was rejected, no build stop advanced, and v6 remains sealed."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "seventeen exact archives in the three-version env_logger union closure are absent",
            "the pinned nightly-2024-12-25 toolchain and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
            "no candidate runtime invention survives native compiler deduplication",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "acquire the three exact env_logger roots and unresolved "
                "0.11.9 closure with authenticated source and package aliases"
            ),
            "forbidden_shortcuts": [
                "do not patch only one of three locked env_logger versions",
                "do not label official Git tag source as crates.io archive identity",
                "do not call closure enumeration algorithm execution",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    path = RESULTS / "readiness_iteration_5_7.json"
    path.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_7"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 env_logger_closure=14/31"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
