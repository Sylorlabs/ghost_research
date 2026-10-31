#!/usr/bin/env python3
"""Recompute readiness after the kiddo-root acquisition-channel audit."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_14.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v15_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["locked_root"] == "kiddo 5.2.4"
        and freeze["release_adjacent_manifest_version"] == "5.2.1"
        and freeze["next_stop"] == "kiddo"
    ):
        raise RuntimeError("iteration 5.15 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_15",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_kiddo_root_acquisition_channels_audited": True,
            "isamore_kiddo_locked_root_version": "5.2.4",
            "isamore_kiddo_release_adjacent_manifest_version": "5.2.1",
            "isamore_kiddo_root_source_acquired": False,
            "isamore_shell_registry_transport_available": False,
            "isamore_offline_build_stop_before_phase": "kiddo",
            "isamore_offline_build_stop_after_phase": "kiddo",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The exact lock and official release-adjacent repository manifest "
            "are now jointly frozen. They authenticate different versions, "
            "and no exact archive or source crossed the unavailable shell "
            "transport. No source identity was invented."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "the exact published kiddo 5.2.4 root source is absent",
            "the pinned nightly and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "continue exact direct-dependency source closure while the "
                "kiddo root acquisition boundary remains explicit"
            ),
            "forbidden_shortcuts": [
                "do not rewrite the 5.2.1 repository manifest as 5.2.4",
                "do not infer archive identity from a nearby commit",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_15.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_15"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 kiddo_root=false"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
