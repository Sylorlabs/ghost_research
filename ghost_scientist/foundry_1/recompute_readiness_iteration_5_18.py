#!/usr/bin/env python3
"""Recompute readiness after the Coin-CBC Rust-binding bridge."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_17.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v18_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and len(freeze["bridged_packages"]) == 2
        and freeze["independent_source_compilation_passed"] is True
        and freeze["native_libcbc_available"] is False
        and freeze["next_stop"] == "kiddo"
    ):
        raise RuntimeError("iteration 5.18 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_18",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_coin_cbc_rust_binding_packages_bridged": 2,
            "isamore_coin_cbc_source_records_authenticated": 7,
            "isamore_coin_cbc_rust_binding_source_compiled": True,
            "isamore_native_libcbc_available": False,
            "isamore_pinned_nightly_available": False,
            "isamore_coin_cbc_solver_executed": False,
            "isamore_kiddo_partial_family_packages_bridged": 4,
            "isamore_kiddo_root_source_acquired": False,
            "isamore_offline_build_stop_before_phase": "kiddo",
            "isamore_offline_build_stop_after_phase": "kiddo",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The two locked Coin-CBC Rust binding packages now match their "
            "official release commit and compile independently. Native libCbc "
            "and the pinned nightly remain absent, while Kiddo still prevents "
            "top-level ISAMORE compilation, so P1 does not advance."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "the exact published kiddo 5.2.4 root source is absent",
            "az 1.3.0, fixed 1.30.0, and sorted-vec 0.8.10 exact source bytes remain absent",
            "native Coin-OR CBC and the pinned nightly remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "acquire exact Kiddo root/math sources and a controlled native "
                "CBC plus pinned-nightly closure, then rerun the unchanged "
                "metered ISAMORE build"
            ),
            "forbidden_shortcuts": [
                "do not count cargo check as native CBC linking or execution",
                "do not count dependency compilation as ISAMORE execution",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_18.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_18"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10 kiddo_family=4/8"
        " coin_cbc_bindings=2 native_cbc=false prospective=false"
    )


if __name__ == "__main__":
    main()
