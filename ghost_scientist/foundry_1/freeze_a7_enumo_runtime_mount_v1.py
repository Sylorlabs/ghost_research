#!/usr/bin/env python3
"""Freeze the A7 Enumo runtime mount before implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/A7_ENUMO_RUNTIME_MOUNT_PROTOCOL_V1.json"
RESULT = HERE / "results/a7_enumo_runtime_mount_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    payload = {
        "version": "FOUNDRY_A7_ENUMO_RUNTIME_MOUNT_FREEZE_V1",
        "classification": "FROZEN_BEFORE_MOUNT_IMPLEMENTATION_OR_EXECUTION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "expected": protocol["expected"],
        "frozen_before_mount_implementation_or_execution": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_FREEZE_A7_ENUMO_RUNTIME_MOUNT"
        f" protocol={payload['protocol_sha256']}"
        f" providers={len(protocol['provider_records'])}"
    )


if __name__ == "__main__":
    main()
