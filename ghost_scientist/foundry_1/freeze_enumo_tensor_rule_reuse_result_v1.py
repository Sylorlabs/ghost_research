#!/usr/bin/env python3
"""Create or verify the immutable Enumo tensor rule-reuse result freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULT = (
    HERE / "results/phase133_enumo_tensor_rule_reuse_competitiveness.json"
)
MANIFEST = (
    HERE / "results/enumo_tensor_rule_reuse_result_v1_freeze.json"
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def records() -> list[dict[str, str]]:
    paths = [
        "arm_adapter_fixtures/ENUMO_TENSOR_RULE_REUSE_PROTOCOL_V1.json",
        "results/enumo_tensor_rule_reuse_v1_freeze.json",
        "results/phase132_enumo_tensor_domain_feasibility.json",
        "results/enumo_tensor_feasibility_result_v1_freeze.json",
        "phase133_enumo_tensor_rule_reuse_competitiveness.py",
    ]
    return [
        {"path": path, "sha256": sha(HERE / path)}
        for path in paths
    ]


def create() -> dict[str, object]:
    result = json.loads(RESULT.read_text())
    if not (
        result["status"] == "ENUMO_TENSOR_RULE_REUSE_DOES_NOT_BEAT_FIXED"
        and result["operationally_valid"] is True
        and all(result["checks"].values())
        and result["protocol_acceptance"]["accepted"] is False
        and result["observed"]["held_out_expression_count"] == 3339
        and result["observed"]["learned_strict_wins"] == 0
        and result["observed"]["fixed_strict_wins"] == 736
        and result["observed"]["atom_cost_ties"] == 2603
        and result["observed"]["state_cap_hits"] == 0
        and result["observed"]["semantic_failures"] == []
        and result["claim_boundary"]["A7_production_integrated"] is False
        and result["claim_boundary"]["production_integrated_arms"] == 6
        and result["claim_boundary"]["validation_v6_accessed"] is False
    ):
        raise RuntimeError("phase133 is not the expected valid negative result")
    return {
        "version": "FOUNDRY_ENUMO_TENSOR_RULE_REUSE_RESULT_FREEZE_V1",
        "result_sha256": sha(RESULT),
        "records": records(),
        "status": result["status"],
        "held_out_expression_count": 3339,
        "learned_strict_wins": 0,
        "fixed_strict_wins": 736,
        "atom_cost_ties": 2603,
        "operationally_valid": True,
        "protocol_accepted": False,
        "is_frozen_boolean_A7": False,
        "A7_production_integrated": False,
        "production_integrated_arms": 6,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict[str, object]:
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"]
        == "FOUNDRY_ENUMO_TENSOR_RULE_REUSE_RESULT_FREEZE_V1"
        and payload["result_sha256"] == sha(RESULT)
        and payload["records"] == records()
        and payload["status"]
        == "ENUMO_TENSOR_RULE_REUSE_DOES_NOT_BEAT_FIXED"
        and payload["held_out_expression_count"] == 3339
        and payload["learned_strict_wins"] == 0
        and payload["fixed_strict_wins"] == 736
        and payload["atom_cost_ties"] == 2603
        and payload["operationally_valid"] is True
        and payload["protocol_accepted"] is False
        and payload["is_frozen_boolean_A7"] is False
        and payload["A7_production_integrated"] is False
        and payload["production_integrated_arms"] == 6
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("Enumo tensor rule-reuse result freeze changed")
    for row in payload["records"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"frozen reuse record mismatch: {row['path']}")
    return payload


def main() -> None:
    existed = MANIFEST.exists()
    if existed:
        payload = verify()
    else:
        payload = create()
        MANIFEST.write_text(
            json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
        )
    verify()
    print(
        "FOUNDRY_ENUMO_TENSOR_RULE_REUSE_RESULT_V1_FREEZE_PASS"
        f" learned={payload['learned_strict_wins']}"
        f" fixed={payload['fixed_strict_wins']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
