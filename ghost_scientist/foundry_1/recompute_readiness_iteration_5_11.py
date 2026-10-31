#!/usr/bin/env python3
"""Recompute readiness after the indicatif closure census."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_10.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v11_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["locked_packages"] == 31
        and freeze["exact_cached_archives"] == 18
        and freeze["next_stop"] == "indicatif"
    ):
        raise RuntimeError("iteration 5.11 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_11",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_indicatif_locked_closure_packages": 31,
            "isamore_indicatif_exact_cached_archives": 18,
            "isamore_indicatif_missing_exact_archives": 13,
            "isamore_offline_build_stop_before_phase": "indicatif",
            "isamore_offline_build_stop_after_phase": "indicatif",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The indicatif frontier is exact: 18 of 31 locked closure packages "
            "have checksum-authenticated archives and 13 do not. No resolver "
            "advance, compilation, execution, or validation access occurred."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "thirteen exact indicatif closure archives are absent",
            "the pinned nightly and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "acquire the indicatif-specific package family before generic "
                "platform dependencies"
            ),
            "forbidden_shortcuts": [
                "do not count tag source as archive identity",
                "do not call a closure census compilation or execution",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_11.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_11"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 indicatif_closure=18/31"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
