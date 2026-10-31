#!/usr/bin/env python3
"""Freeze full-body prediction before implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/LOCAL_EXACT_BODY_PREDICTION_PROTOCOL_V1.json"
RESULT = HERE / "results/local_exact_body_prediction_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    phase163 = json.loads((HERE / "results/phase163_local_operator_prediction.json").read_text())
    summary = phase163["observed"]["summary"]
    if not (
        all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
        and phase163["status"] == "LOCAL_OPERATOR_PREDICTION_POSITIVE"
        and summary["candidate_exact_sequences"] == 18
        and summary["candidate_exact_families"] == 11
        and summary["candidate_exact_folds"] == 5
        and summary["heldout_target_leakage_events"] == 0
        and protocol["decision_rule"][
            "positive_requires_execution_causal_and_native_dedup_next"
        ]
        is True
        and len(protocol["hostile_requirements"]["must_cover"]) == 14
    ):
        raise RuntimeError("exact-body protocol cannot freeze")
    result = {
        "version": "FOUNDRY_LOCAL_EXACT_BODY_PREDICTION_FREEZE_V1",
        "status": "FROZEN_BEFORE_EXACT_BODY_PREDICTION_IMPLEMENTATION_OR_OUTCOME",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "split": protocol["split"],
        "candidate": protocol["candidate"],
        "controls": protocol["controls"],
        "decision_rule": protocol["decision_rule"],
        "hostile_requirements": protocol["hostile_requirements"],
        "resource_limits": protocol["resource_limits"],
        "claim_boundary": protocol["claim_boundary"],
        "exact_body_prediction_outcome_known_before_freeze": False
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_LOCAL_EXACT_BODY_PREDICTION_FREEZE"
        " status=FROZEN_BEFORE_EXACT_BODY_PREDICTION_IMPLEMENTATION_OR_OUTCOME"
        " folds=5 operator_upper_bound=18"
    )


if __name__ == "__main__":
    main()
