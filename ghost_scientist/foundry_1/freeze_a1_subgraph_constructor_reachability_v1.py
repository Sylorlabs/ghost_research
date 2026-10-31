#!/usr/bin/env python3
"""Freeze the A1 subgraph reachability audit before runner implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_PROTOCOL_V1.json"
)
RESULT = HERE / "results/a1_subgraph_constructor_reachability_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    payload = {
        "version": "FOUNDRY_A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_FREEZE_V1",
        "classification": "FROZEN_BEFORE_RUNNER_IMPLEMENTATION_OR_EXECUTION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "constructor_histograms": protocol["frozen_constructor_histograms"],
        "frozen_before_runner_implementation_or_execution": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_FREEZE_A1_SUBGRAPH_REACHABILITY"
        f" protocol={payload['protocol_sha256']}"
        f" constructors={len(payload['constructor_histograms'])}"
    )


if __name__ == "__main__":
    main()
