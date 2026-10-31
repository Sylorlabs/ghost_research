#!/usr/bin/env python3
"""Freeze real-value execution, causality, and native dedup."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/LOCAL_EXACT_TOOL_EXECUTION_PROTOCOL_V1.json"
RESULT = HERE / "results/local_exact_tool_execution_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    phase164 = json.loads((HERE / "results/phase164_local_exact_body_prediction.json").read_text())
    ledger = phase164["observed"]["ledger"]
    if not (
        all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
        and phase164["status"] == "LOCAL_EXACT_BODY_PREDICTION_POSITIVE"
        and len(ledger["exact_match_rows"]) == protocol["execution"]["matches"] == 17
        and len({row["candidate_body_sha256"] for row in ledger["exact_match_rows"]})
        == protocol["execution"]["unique_predicted_bodies"]
        == 3
        and phase164["decision"]["tool_execution_demonstrated"] is False
        and phase164["decision"]["native_dedup_executed"] is False
        and protocol["decision_rule"]["never_call_standalone_replay_whole_graph_replacement"]
        is True
        and len(protocol["hostile_requirements"]["must_cover"]) == 14
    ):
        raise RuntimeError("exact-tool execution protocol cannot freeze")
    result = {
        "version": "FOUNDRY_LOCAL_EXACT_TOOL_EXECUTION_FREEZE_V1",
        "status": "FROZEN_BEFORE_TOOL_EXECUTION_CAUSALITY_OR_NATIVE_COMPILATION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "execution": protocol["execution"],
        "causal_test": protocol["causal_test"],
        "native_dedup": protocol["native_dedup"],
        "decision_rule": protocol["decision_rule"],
        "hostile_requirements": protocol["hostile_requirements"],
        "resource_limits": protocol["resource_limits"],
        "claim_boundary": protocol["claim_boundary"],
        "execution_or_native_outcome_known_before_freeze": False
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_LOCAL_EXACT_TOOL_EXECUTION_FREEZE"
        " status=FROZEN_BEFORE_TOOL_EXECUTION_CAUSALITY_OR_NATIVE_COMPILATION"
        " matches=17 unique=3"
    )


if __name__ == "__main__":
    main()
