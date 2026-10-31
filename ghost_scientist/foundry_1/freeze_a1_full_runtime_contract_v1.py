#!/usr/bin/env python3
"""Freeze the A1 full runtime contract batch before implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/A1_FULL_RUNTIME_CONTRACT_PROTOCOL_V1.json"
RESULT = HERE / "results/a1_full_runtime_contract_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    if any(
        sha(HERE / row["path"]) != row["sha256"]
        for row in protocol["provider_records"]
    ):
        raise RuntimeError("A1 full runtime provider mismatch")
    if not (
        protocol["surface"]["base_contract_pairs"] == 23
        and protocol["surface"]["whole_graph_executions"] == 69
        and protocol["surface"]["fold_checks"] == 9
        and protocol["claim_boundary"][
            "production_integrated_arms_before_pass"
        ]
        == 7
        and protocol["claim_boundary"][
            "production_integrated_arms_after_pass"
        ]
        == 8
    ):
        raise RuntimeError("A1 full runtime frozen cardinality mismatch")
    payload = {
        "version": "FOUNDRY_A1_FULL_RUNTIME_CONTRACT_FREEZE_V1",
        "classification": "FROZEN_BEFORE_MOUNT_AND_CONTRACT_EXECUTION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "surface": protocol["surface"],
        "acceptance": protocol["acceptance"],
        "frozen_before_mount_or_contract_runner_implementation_or_execution": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_FREEZE_A1_FULL_RUNTIME_CONTRACT"
        f" protocol={payload['protocol_sha256']}"
        " graphs=23 executions=69 folds=9 integrated=7-to-8"
    )


if __name__ == "__main__":
    main()
