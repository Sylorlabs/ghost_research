#!/usr/bin/env python3
"""Recompute readiness after the exact locked csv-closure census."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_4.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v5_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["authorization"]["prerequisites_passed"] == 5
        and freeze["next_stop"] == "csv"
        and freeze["exact_cached_archives"] == 7
        and freeze["missing_exact_archives"] == 4
        and freeze["control_executed"] is False
    ):
        raise RuntimeError("iteration 5.5 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_5",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_csv_locked_closure_packages": 11,
            "isamore_csv_exact_cached_archives": 7,
            "isamore_csv_missing_exact_archives": 4,
            "isamore_offline_build_stop_before_phase": "csv",
            "isamore_offline_build_stop_after_phase": "csv",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The next exact dependency frontier is now bounded: seven of "
            "eleven locked csv-closure archives are locally authenticated and "
            "four are absent. No nearby version was substituted, the Cargo "
            "stop did not advance, ISAMORE did not compile or execute, and v6 "
            "remains sealed."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "csv 1.4.0, csv-core 0.1.13, itoa 1.0.17, and quote 1.0.44 exact archives are absent",
            "the pinned nightly-2024-12-25 toolchain and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
            "no candidate runtime invention survives native compiler deduplication",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "acquire the four exact csv-closure packages with authenticated "
                "provenance; reject nearby-version substitution"
            ),
            "forbidden_shortcuts": [
                "do not substitute itoa 1.0.18 for locked 1.0.17",
                "do not substitute quote 1.0.45 for locked 1.0.44",
                "do not call a closure census algorithm compilation or execution",
                "do not mock SMT, LP, or hardware scoring",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    path = RESULTS / "readiness_iteration_5_5.json"
    path.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_5"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 csv_closure=7/11"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
