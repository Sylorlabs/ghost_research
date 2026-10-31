#!/usr/bin/env python3
"""Freeze the five-fold operator prediction experiment."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/LOCAL_OPERATOR_PREDICTION_PROTOCOL_V1.json"
RESULT = HERE / "results/local_operator_prediction_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    phase162 = json.loads(
        (HERE / "results/phase162_local_template_informativeness.json").read_text()
    )
    if not (
        all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
        and phase162["status"]
        == "LOCAL_TYPED_TEMPLATE_STRUCTURAL_ONLY_VALID_NEGATIVE"
        and phase162["observed"]["summary"]["typed_rejections"] == 0
        and phase162["observed"]["summary"]["candidate_information_bits"] == 0.0
        and protocol["split"]["expected_graph_counts"] == [6, 4, 4, 1, 8]
        and protocol["candidate"]["heldout_target_or_recipe_access_before_prediction"]
        is False
        and len(protocol["hostile_requirements"]["must_cover"]) == 16
        and protocol["decision_rule"][
            "recipe_and_type_prediction_required_next_if_positive"
        ]
        is True
    ):
        raise RuntimeError("operator-prediction protocol cannot freeze")
    result = {
        "version": "FOUNDRY_LOCAL_OPERATOR_PREDICTION_FREEZE_V1",
        "status": "FROZEN_BEFORE_FOLD_PREDICTION_IMPLEMENTATION_OR_OUTCOME",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "split": protocol["split"],
        "motif_universe": protocol["motif_universe"],
        "candidate": protocol["candidate"],
        "controls": protocol["controls"],
        "primary_endpoints": protocol["primary_endpoints"],
        "decision_rule": protocol["decision_rule"],
        "hostile_requirements": protocol["hostile_requirements"],
        "resource_limits": protocol["resource_limits"],
        "claim_boundary": protocol["claim_boundary"],
        "operator_prediction_outcome_known_before_freeze": False
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_LOCAL_OPERATOR_PREDICTION_FREEZE"
        " status=FROZEN_BEFORE_FOLD_PREDICTION_IMPLEMENTATION_OR_OUTCOME"
        " folds=5 counts=6,4,4,1,8"
    )


if __name__ == "__main__":
    main()
