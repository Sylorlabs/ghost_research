#!/usr/bin/env python3
"""Freeze the Phase162 informativeness ablation before implementation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = HERE / "arm_adapter_fixtures/LOCAL_TEMPLATE_INFORMATIVENESS_PROTOCOL_V1.json"
RESULT = HERE / "results/local_template_informativeness_v1_freeze.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    phase161 = json.loads(
        (HERE / "results/phase161_local_typed_template_transfer.json").read_text()
    )
    summary = phase161["observed"]["summary"]
    if not (
        all(sha(HERE / row["path"]) == row["sha256"] for row in protocol["provider_records"])
        and phase161["status"] == "LOCAL_TYPED_TEMPLATE_TRANSFER_POSITIVE"
        and summary["selected_templates"] == 1
        and summary["heldout_template_matches"] == 2
        and summary["operator_holes"] == 2
        and summary["recipe_holes"] == 2
        and phase161["decision"]["concrete_exact_tool_reuse_demonstrated"] is False
        and len(protocol["hostile_requirements"]["must_cover"]) == 12
        and protocol["decision_rule"]["never_call_structural_only_transfer_concrete_tool_reuse"] is True
    ):
        raise RuntimeError("template-informativeness protocol cannot freeze")
    result = {
        "version": "FOUNDRY_LOCAL_TEMPLATE_INFORMATIVENESS_FREEZE_V1",
        "status": "FROZEN_BEFORE_ABLATION_IMPLEMENTATION_OR_OUTCOME",
        "protocol_sha256": sha(PROTOCOL),
        "provider_records": protocol["provider_records"],
        "candidate": protocol["candidate"],
        "controls": protocol["controls"],
        "primary_endpoints": protocol["primary_endpoints"],
        "decision_rule": protocol["decision_rule"],
        "hostile_requirements": protocol["hostile_requirements"],
        "resource_limits": protocol["resource_limits"],
        "claim_boundary": protocol["claim_boundary"],
        "phase161_outcome_known_before_freeze": True,
        "ablation_outcome_known_before_freeze": False
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_LOCAL_TEMPLATE_INFORMATIVENESS_FREEZE"
        " status=FROZEN_BEFORE_ABLATION_IMPLEMENTATION_OR_OUTCOME"
        " phase161_matches=2"
    )


if __name__ == "__main__":
    main()
