#!/usr/bin/env python3
"""Freeze the A8 selected-strategy runtime protocol before implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A8_ADAPTED_STRATEGY_RUNTIME_PROTOCOL_V1.json"
)
RESULT = HERE / "results/a8_adapted_strategy_runtime_v1_freeze.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    if not (
        all(
            sha(HERE / row["path"]) == row["sha256"]
            for row in protocol["provider_records"]
        )
        and protocol[
            "frozen_before_mount_or_contract_runner_implementation_or_execution"
        ]
        is True
        and protocol["pristine_preregistration"] is False
        and protocol["surface"]["eligible_strategy_applications"] == 20
        and protocol["surface"]["strategy_tool_direct_uses"] == 60
    ):
        raise RuntimeError("A8 runtime protocol cannot be frozen")
    payload = {
        "version": "FOUNDRY_A8_ADAPTED_STRATEGY_RUNTIME_FREEZE_V1",
        "status": "FROZEN_POST_EXPLORATORY_BEFORE_RUNTIME_IMPLEMENTATION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "selected_strategy": protocol["selected_strategy"],
        "surface": protocol["surface"],
        "runtime_policy": protocol["runtime_policy"],
        "acceptance": protocol["acceptance"],
        "resource_limits": protocol["resource_limits"],
        "pristine_preregistration": False,
        "frozen_before_mount_or_contract_runner_implementation_or_execution": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_A8_RUNTIME_FREEZE"
        f" status={payload['status']}"
        f" protocol_sha256={payload['protocol_sha256']}"
    )


if __name__ == "__main__":
    main()
