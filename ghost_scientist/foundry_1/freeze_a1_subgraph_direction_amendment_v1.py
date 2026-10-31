#!/usr/bin/env python3
"""Freeze the A1 direction correction before corrected execution."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
AMENDMENT = (
    HERE
    / "arm_adapter_fixtures/A1_SUBGRAPH_REACHABILITY_DIRECTION_AMENDMENT_V1.json"
)
RESULT = HERE / "results/a1_subgraph_direction_amendment_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    amendment = json.loads(AMENDMENT.read_text())
    for row in amendment["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    payload = {
        "version": "FOUNDRY_A1_SUBGRAPH_DIRECTION_AMENDMENT_FREEZE_V1",
        "classification": "FROZEN_BEFORE_CORRECTED_RUNNER_IMPLEMENTATION",
        "amendment_sha256": sha(AMENDMENT),
        "provider_records": amendment["provider_records"],
        "pristine_preregistration": False,
        "frozen_before_corrected_runner_implementation_or_execution": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_FREEZE_A1_DIRECTION_AMENDMENT"
        f" amendment={payload['amendment_sha256']}"
        " pristine=false validation_v6=false"
    )


if __name__ == "__main__":
    main()
