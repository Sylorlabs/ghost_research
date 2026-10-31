#!/usr/bin/env python3
"""Recompute readiness after the three-root env_logger bridge."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_7.json"
    freeze_path = RESULTS / "isamore_dependency_bridge_v8_freeze.json"
    prior = json.loads(prior_path.read_text())
    freeze = json.loads(freeze_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and freeze["root_versions"] == 3
        and freeze["next_stop"] == "graphviz-rust"
        and freeze["control_executed"] is False
    ):
        raise RuntimeError("iteration 5.8 inputs changed")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_8",
        "prior_sha256": sha(prior_path),
        "isamore_dependency_bridge_freeze_sha256": sha(freeze_path),
        "prerequisites": prior["prerequisites"],
        "progress": {
            **prior["progress"],
            "isamore_env_logger_tag_roots_mounted": 3,
            "isamore_env_logger_tag_records": 37,
            "isamore_offline_build_stop_before_phase": "env_logger",
            "isamore_offline_build_stop_after_phase": "graphviz-rust",
        },
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "All three exact env_logger release-tag roots mount simultaneously "
            "through package aliases, advancing the metered resolver stop to "
            "graphviz-rust. No ISAMORE algorithm compiled or executed."
        ),
        "remaining_blockers": [
            "P1 still lacks the fourth executed source-faithful control",
            "the offline build now stops at graphviz-rust",
            "official-tag bridges are not crates.io archive identity",
            "the pinned nightly and Coin-OR CBC remain absent",
            "the production arm matrix remains 6/10",
        ],
        "remediation": {
            "required": True,
            "next_action": "audit the exact locked graphviz-rust closure",
            "forbidden_shortcuts": [
                "do not collapse three env_logger generations into one",
                "do not call resolver progress compilation or execution",
                "do not open validation-v6 before authorization",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_8.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_8"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " controls=3/4 integrated=6/10"
        " build_stop=env_logger_to_graphviz-rust prospective=false"
    )


if __name__ == "__main__":
    main()
