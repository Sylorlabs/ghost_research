#!/usr/bin/env python3
"""Freeze the post-exploratory A8 adapted strategy protocol."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A8_ADAPTED_STRATEGY_REACHABILITY_PROTOCOL_V1.json"
)
RESULT = HERE / "results/a8_adapted_strategy_reachability_v1_freeze.json"


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
            "frozen_before_formal_enumerator_implementation_or_execution"
        ]
        is True
        and protocol["pristine_preregistration"] is False
        and protocol["tool_grammar"]["candidate_strategies"] == 40320
        and protocol["decision_rule"]["this_phase_never_integrates_A8"]
        is True
    ):
        raise RuntimeError("A8 strategy protocol cannot be frozen")
    payload = {
        "version": "FOUNDRY_A8_ADAPTED_STRATEGY_REACHABILITY_FREEZE_V1",
        "status": "FROZEN_AFTER_DISCLOSED_EXPLORATORY_PROBE",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "tool_grammar": protocol["tool_grammar"],
        "match_and_execution_policy": protocol[
            "match_and_execution_policy"
        ],
        "repository_policy": protocol["repository_policy"],
        "objective": protocol["objective"],
        "decision_rule": protocol["decision_rule"],
        "resource_limits": protocol["resource_limits"],
        "pristine_preregistration": False,
        "frozen_before_formal_enumerator_implementation_or_execution": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_A8_STRATEGY_FREEZE"
        f" status={payload['status']}"
        f" protocol_sha256={payload['protocol_sha256']}"
    )


if __name__ == "__main__":
    main()
