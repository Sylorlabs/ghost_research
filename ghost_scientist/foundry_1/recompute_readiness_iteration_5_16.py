#!/usr/bin/env python3
"""Recompute readiness after exact divrem source authentication."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_15.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v16_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["bridged_package"] == "divrem 1.0.0"
        and freeze["accumulated_kiddo_family_packages"] == 4
        and freeze["next_stop"] == "kiddo"
    ):
        raise RuntimeError("iteration 5.16 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_16",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_kiddo_partial_family_packages_bridged": 4,
            "isamore_kiddo_partial_family_source_records": 20,
            "isamore_divrem_exact_source_compiled": True,
            "isamore_kiddo_root_source_acquired": False,
            "isamore_offline_build_stop_before_phase": "kiddo",
            "isamore_offline_build_stop_after_phase": "kiddo",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "divrem 1.0.0 now matches seven exact official-tag blobs and "
            "compiles independently. The absent kiddo root still prevents "
            "ISAMORE compilation or execution, so P1 does not advance."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "the exact published kiddo 5.2.4 root source is absent",
            "az 1.3.0, fixed 1.30.0, and sorted-vec 0.8.10 remain unbridged",
            "the pinned nightly and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "authenticate exact az 1.3.0, fixed 1.30.0, and sorted-vec "
                "0.8.10 source surfaces"
            ),
            "forbidden_shortcuts": [
                "do not count independent dependency compilation as ISAMORE",
                "do not infer archive identity from release-tag source",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_16.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_16"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 kiddo_family=4/8"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
