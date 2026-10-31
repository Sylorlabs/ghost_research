#!/usr/bin/env python3
"""Freeze the typed-template follow-up before implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/LOCAL_TYPED_TEMPLATE_TRANSFER_PROTOCOL_V1.json"
)
RESULT = HERE / "results/local_typed_template_transfer_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    phase160 = json.loads(
        (HERE / "results/phase160_local_grammar_emergence.json").read_text()
    )
    summary = phase160["observed"]["summary"]
    if not (
        all(
            sha(HERE / row["path"]) == row["sha256"]
            for row in protocol["provider_records"]
        )
        and phase160["status"] == "LOCAL_GRAMMAR_EMERGENCE_VALID_NEGATIVE"
        and summary["selected_non_chain_productions"] == 3
        and summary["selected_non_chain_tools"] == 2
        and summary["candidate_only_heldout_tools"] == 0
        and protocol["classification"]["post_outcome_diagnostic_not_pristine"]
        is True
        and protocol["typed_anti_unification"]["llm_calls"] == 0
        and protocol["decision_rule"][
            "never_call_template_transfer_concrete_tool_reuse_or_runtime_invention"
        ]
        is True
        and protocol["decision_rule"][
            "never_advance_P6_or_authorize_prospective_trial"
        ]
        is True
        and len(protocol["hostile_requirements"]["must_cover"]) == 16
    ):
        raise RuntimeError("typed-template transfer protocol cannot freeze")
    result = {
        "version": "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_FREEZE_V1",
        "status": "FROZEN_BEFORE_TEMPLATE_OR_MATCH_IMPLEMENTATION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "training_scope": protocol["training_scope"],
        "typed_anti_unification": protocol["typed_anti_unification"],
        "heldout_match": protocol["heldout_match"],
        "controls": protocol["controls"],
        "primary_endpoints": protocol["primary_endpoints"],
        "causal_tests": protocol["causal_tests"],
        "decision_rule": protocol["decision_rule"],
        "hostile_requirements": protocol["hostile_requirements"],
        "resource_limits": protocol["resource_limits"],
        "claim_boundary": protocol["claim_boundary"],
        "phase160_outcome_known_before_freeze": True,
        "validation_v6_or_v7_accessed": False,
        "prospective_trial_authorized": False
    }
    RESULT.write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_LOCAL_TYPED_TEMPLATE_TRANSFER_FREEZE"
        f" status={result['status']}"
        " non_chain_productions=3 post_outcome=true"
    )


if __name__ == "__main__":
    main()
