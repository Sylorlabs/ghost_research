#!/usr/bin/env python3
"""Recompute readiness after the native LP acquisition-channel audit."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_18.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v19_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["apt_candidate_version"] == "2.10.11+ds1-2"
        and freeze["native_cbc_downloaded"] is False
        and freeze["pinned_nightly_available"] is False
        and freeze["next_stop"] == "kiddo"
    ):
        raise RuntimeError("iteration 5.19 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_19",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_native_cbc_apt_candidate_identified": "2.10.11+ds1-2",
            "isamore_native_cbc_downloaded": False,
            "isamore_native_cbc_installed": False,
            "isamore_native_libcbc_available": False,
            "isamore_pinned_nightly_available": False,
            "isamore_native_lp_link_attempted": False,
            "isamore_coin_cbc_solver_executed": False,
            "isamore_offline_build_stop_before_phase": "kiddo",
            "isamore_offline_build_stop_after_phase": "kiddo",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The host package index exposes controlled Coin-OR CBC candidates, "
            "but a download-only probe produced no artifact because the mirror "
            "cannot resolve. No system mutation occurred. The pinned nightly "
            "also remains absent, so P1 cannot advance."
        ),
        "remaining_blockers": prior["remaining_blockers"],
        "remediation": {
            "required": True,
            "next_action": (
                "resume with authenticated local artifacts or restored "
                "transport for exact Kiddo/math crates, the pinned nightly, "
                "and controlled Coin-OR CBC packages"
            ),
            "forbidden_shortcuts": [
                "do not claim package candidates as downloaded or installed",
                "do not count Rust binding compilation as native solver execution",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_19.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_19"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 kiddo_family=4/8"
        " cbc_candidate=true downloaded=false pinned_nightly=false"
        " prospective=false"
    )


if __name__ == "__main__":
    main()
