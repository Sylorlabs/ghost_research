#!/usr/bin/env python3
"""Freeze A6 typed anti-unification reachability before implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A6_TYPED_ANTI_UNIFICATION_REACHABILITY_PROTOCOL_V1.json"
)
RESULT = (
    HERE
    / "results/a6_typed_anti_unification_reachability_v1_freeze.json"
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    if any(
        sha(HERE / row["path"]) != row["sha256"]
        for row in protocol["provider_records"]
    ):
        raise RuntimeError("A6 reachability provider mismatch")
    domain = protocol["typed_term_domain"]
    if not (
        domain["expected_roots"] == 337
        and domain["expected_unordered_root_pairs"] == 56616
        and domain["maximum_recursive_operator_depth"] == 4
        and protocol["hostile_requirements"]["cases"] == 12
        and protocol["decision_rule"]["this_phase_never_integrates_A6"]
        is True
    ):
        raise RuntimeError("A6 reachability frozen surface mismatch")
    payload = {
        "version": "FOUNDRY_A6_TYPED_ANTI_UNIFICATION_REACHABILITY_FREEZE_V1",
        "classification": "FROZEN_BEFORE_ENUMERATOR_IMPLEMENTATION_OR_EXECUTION",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "typed_term_domain": domain,
        "candidate_contract": protocol["candidate_contract"],
        "selection_rule": protocol["selection_rule"],
        "decision_rule": protocol["decision_rule"],
        "frozen_before_enumerator_implementation_or_execution": True,
        "validation_v6_accessed": False,
        "prospective_trial_authorized": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_FREEZE_A6_TYPED_ANTI_UNIFICATION_REACHABILITY"
        f" protocol={payload['protocol_sha256']}"
        " roots=337 pairs=56616 depth=4"
    )


if __name__ == "__main__":
    main()
