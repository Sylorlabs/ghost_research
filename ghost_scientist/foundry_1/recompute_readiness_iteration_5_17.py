#!/usr/bin/env python3
"""Recompute readiness after the remaining math-source channel audit."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_16.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v17_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["locked_packages_audited"] == 3
        and freeze["packages_acquired"] == 0
        and freeze["next_stop"] == "kiddo"
    ):
        raise RuntimeError("iteration 5.17 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_17",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_remaining_math_channels_audited": 3,
            "isamore_remaining_math_exact_sources_acquired": 0,
            "isamore_third_party_math_mirror_substituted": False,
            "isamore_kiddo_partial_family_packages_bridged": 4,
            "isamore_kiddo_root_source_acquired": False,
            "isamore_offline_build_stop_before_phase": "kiddo",
            "isamore_offline_build_stop_after_phase": "kiddo",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "All three remaining math package identities and official release "
            "channels are frozen, but no exact source bytes were acquired. A "
            "divergent mirror was rejected, so the Kiddo family and P1 do not "
            "advance."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "the exact published kiddo 5.2.4 root source is absent",
            "az 1.3.0, fixed 1.30.0, and sorted-vec 0.8.10 exact source bytes remain absent",
            "the pinned nightly and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "authenticate the locked coin_cbc Rust binding surface and "
                "audit the remaining native/pinned-toolchain closure"
            ),
            "forbidden_shortcuts": [
                "do not substitute a divergent third-party mirror",
                "do not count release metadata as source acquisition",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_17.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_17"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 kiddo_family=4/8"
        " math_sources=0/3 prospective=false"
    )


if __name__ == "__main__":
    main()
