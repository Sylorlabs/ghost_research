#!/usr/bin/env python3
"""Freeze the A7 batch protocol before assembler implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/A7_SHARED_RESOURCE_BATCH_PROTOCOL_V1.json"
RESULT = HERE / "results/a7_shared_resource_batch_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    payload = {
        "version": "FOUNDRY_A7_SHARED_RESOURCE_BATCH_FREEZE_V1",
        "classification": "FROZEN_BEFORE_BATCH_ASSEMBLER_IMPLEMENTATION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "expected_artifacts": protocol["expected_artifacts"],
        "expected_raw_tool_uses": protocol["expected_raw_tool_uses"],
        "expected_unique_transformations": protocol[
            "expected_unique_transformations"
        ],
        "frozen_before_batch_assembler_implementation": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_FREEZE_A7_SHARED_RESOURCE_BATCH"
        f" protocol={payload['protocol_sha256']}"
        f" providers={len(protocol['provider_records'])}"
    )


if __name__ == "__main__":
    main()
