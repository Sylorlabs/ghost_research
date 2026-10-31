#!/usr/bin/env python3
"""Freeze the A6 selected-pattern runtime protocol before implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A6_TYPED_ANTI_UNIFICATION_RUNTIME_PROTOCOL_V1.json"
)
RESULT = HERE / "results/a6_typed_anti_unification_runtime_v1_freeze.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    providers_exact = all(
        sha(HERE / row["path"]) == row["sha256"]
        for row in protocol["provider_records"]
    )
    if not (
        providers_exact
        and protocol[
            "frozen_before_mount_or_contract_runner_implementation_or_execution"
        ]
        is True
        and protocol["selected_candidate"]["pattern_sha256"]
        == "1e98cc9eb3e3a7fb7a428708caae15963e3a37ad076b52674aa2eb916c5c791e"
        and protocol["surface"]["eligible_tool_sites"] == 12
        and protocol["surface"]["eligible_graphs"] == 10
        and protocol["surface"]["tool_direct_uses"] == 36
    ):
        raise RuntimeError("A6 runtime protocol cannot be frozen")
    payload = {
        "version": "FOUNDRY_A6_TYPED_ANTI_UNIFICATION_RUNTIME_FREEZE_V1",
        "status": "FROZEN_BEFORE_MOUNT_OR_CONTRACT_IMPLEMENTATION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "selected_candidate": protocol["selected_candidate"],
        "surface": protocol["surface"],
        "acceptance": protocol["acceptance"],
        "resource_limits": protocol["resource_limits"],
        "frozen_before_mount_or_contract_runner_implementation_or_execution": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_A6_RUNTIME_FREEZE"
        f" status={payload['status']}"
        f" protocol_sha256={payload['protocol_sha256']}"
    )


if __name__ == "__main__":
    main()
