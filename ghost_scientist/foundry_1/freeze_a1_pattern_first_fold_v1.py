#!/usr/bin/env python3
"""Freeze the adapted A1 fold bridge before implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/A1_PATTERN_FIRST_FOLD_PROTOCOL_V1.json"
RESULT = HERE / "results/a1_pattern_first_fold_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    for row in protocol["provider_records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"provider mismatch: {row['path']}")
    payload = {
        "version": "FOUNDRY_A1_PATTERN_FIRST_FOLD_FREEZE_V1",
        "classification": "FROZEN_BEFORE_LOWERER_IMPLEMENTATION_OR_EXECUTION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "targets": protocol["targets"],
        "new_structural_signature_sha256": protocol["grammar_extension"][
            "new_structural_signature_sha256"
        ],
        "frozen_before_lowerer_implementation_or_execution": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_FREEZE_A1_PATTERN_FIRST_FOLD"
        f" protocol={payload['protocol_sha256']}"
        f" targets={len(payload['targets'])}"
        f" signature={payload['new_structural_signature_sha256']}"
    )


if __name__ == "__main__":
    main()
