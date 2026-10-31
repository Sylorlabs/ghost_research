#!/usr/bin/env python3
"""Freeze A7 real-graph transfer inputs before runner implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A7_ENUMO_REAL_GRAPH_TRANSFER_PROTOCOL_V1.json"
)
RESULT = HERE / "results/a7_enumo_real_graph_transfer_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    providers = protocol["provider_records"]
    for row in providers:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    payload = {
        "version": "FOUNDRY_A7_ENUMO_REAL_GRAPH_TRANSFER_FREEZE_V1",
        "classification": "FROZEN_BEFORE_RUNNER_IMPLEMENTATION_OR_EXECUTION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": providers,
        "learned_rule_count_expected": protocol["acceptance"][
            "learned_rule_count"
        ],
        "fixed_rule_count_expected": protocol["acceptance"]["fixed_rule_count"],
        "frozen_before_runner_implementation_or_execution": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_FREEZE_A7_ENUMO_REAL_GRAPH_TRANSFER"
        f" protocol={payload['protocol_sha256']}"
        f" providers={len(providers)} validation_v6=false"
    )


if __name__ == "__main__":
    main()
