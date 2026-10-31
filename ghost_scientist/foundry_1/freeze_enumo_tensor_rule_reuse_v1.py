#!/usr/bin/env python3
"""Create or verify the pre-execution Enumo tensor rule-reuse freeze."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/ENUMO_TENSOR_RULE_REUSE_PROTOCOL_V1.json"
)
MANIFEST = HERE / "results/enumo_tensor_rule_reuse_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def validate_protocol(protocol: dict[str, object]) -> None:
    for row in protocol["frozen_inputs"]:
        if sha(HERE / row["path"]) != row["sha256"]:
            raise RuntimeError(f"frozen input mismatch: {row['path']}")
    if not (
        protocol["frozen_before_reuse_runner_implementation_or_execution"] is True
        and protocol["identity"]["is_frozen_boolean_A7"] is False
        and protocol["identity"]["may_promote_A7"] is False
        and protocol["identity"][
            "may_increase_production_integrated_arm_count"
        ]
        is False
        and protocol["held_out_generator"]["exact_atom_count"] == 5
        and protocol["held_out_generator"]["expected_expression_count"] == 3339
        and len(protocol["strong_fixed_portfolio"]) == 13
        and protocol["acceptance"][
            "learned_portfolio_strict_wins_over_fixed_must_be_positive"
        ]
        is True
        and protocol["claim_boundary"]["generated_not_real_artifacts"] is True
        and protocol["claim_boundary"][
            "validation_v6_source_runtime_graph_or_outcome_accessed"
        ]
        is False
    ):
        raise RuntimeError("Enumo tensor rule-reuse protocol invalid")


def create() -> dict[str, object]:
    protocol = json.loads(PROTOCOL.read_text())
    validate_protocol(protocol)
    return {
        "version": "FOUNDRY_ENUMO_TENSOR_RULE_REUSE_FREEZE_V1",
        "protocol_sha256": sha(PROTOCOL),
        "frozen_inputs": protocol["frozen_inputs"],
        "frozen_before_reuse_runner_implementation_or_execution": True,
        "experiment_name": "ENUMO_TENSOR_RULE_REUSE_COMPETITIVENESS",
        "held_out_exact_atom_count": 5,
        "held_out_expression_count": 3339,
        "fixed_portfolio_rule_count": 13,
        "learned_strict_wins_required": 1,
        "is_frozen_boolean_A7": False,
        "may_promote_A7": False,
        "may_increase_production_integrated_arm_count": False,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }


def verify() -> dict[str, object]:
    protocol = json.loads(PROTOCOL.read_text())
    validate_protocol(protocol)
    payload = json.loads(MANIFEST.read_text())
    if not (
        payload["version"] == "FOUNDRY_ENUMO_TENSOR_RULE_REUSE_FREEZE_V1"
        and payload["protocol_sha256"] == sha(PROTOCOL)
        and payload["frozen_inputs"] == protocol["frozen_inputs"]
        and payload["frozen_before_reuse_runner_implementation_or_execution"]
        is True
        and payload["held_out_exact_atom_count"] == 5
        and payload["held_out_expression_count"] == 3339
        and payload["fixed_portfolio_rule_count"] == 13
        and payload["learned_strict_wins_required"] == 1
        and payload["is_frozen_boolean_A7"] is False
        and payload["may_promote_A7"] is False
        and payload["may_increase_production_integrated_arm_count"] is False
        and payload["validation_v6_accessed"] is False
        and payload["prospective_trial_authorized"] is False
    ):
        raise RuntimeError("Enumo tensor rule-reuse freeze changed")
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
        "FOUNDRY_ENUMO_TENSOR_RULE_REUSE_V1_FREEZE_PASS"
        f" heldout={payload['held_out_expression_count']}"
        f" fixed={payload['fixed_portfolio_rule_count']}"
        f" mode={'VERIFY' if existed else 'CREATE'}"
    )


if __name__ == "__main__":
    main()
