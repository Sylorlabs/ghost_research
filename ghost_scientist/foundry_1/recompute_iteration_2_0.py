#!/usr/bin/env python3
"""Recompute readiness after the frozen ATen prospective-v2.2 component."""

from __future__ import annotations

import hashlib
import json
import pathlib

from freeze_aten_prospective_v2 import verify as verify_v2
from freeze_aten_prospective_v2_1 import verify as verify_v21
from freeze_aten_prospective_v2_2 import verify as verify_v22


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def load(name: str, version: str) -> tuple[dict, str]:
    raw = (RESULTS / name).read_bytes()
    value = json.loads(raw)
    if value["version"] != version:
        raise RuntimeError(f"{name} version mismatch")
    return value, hashlib.sha256(raw).hexdigest()


def run() -> None:
    freeze_v2 = verify_v2()
    freeze_v21 = verify_v21()
    freeze_v22 = verify_v22()
    prior, prior_sha = load(
        "readiness_iteration_1_9.json", "FOUNDRY_READINESS_ITERATION_1_9"
    )
    infra, infra_sha = load(
        "phase22_v2_infrastructure_failure.json",
        "FOUNDRY_ATEN_PROSPECTIVE_INFRA_FAILURE_V2",
    )
    resource_v21, resource_v21_sha = load(
        "phase22_1_prospective_resource_audit.json",
        "FOUNDRY_ATEN_PROSPECTIVE_RESOURCE_AUDIT_V2_1",
    )
    result, result_sha = load(
        "phase23_prospective_aten_trial_v2_2.json",
        "FOUNDRY_ATEN_PROSPECTIVE_RESULT_V2_2",
    )
    resource, resource_sha = load(
        "phase24_prospective_resource_v2_2.json",
        "FOUNDRY_ATEN_PROSPECTIVE_RESOURCE_AUDIT_V2_2",
    )
    if (
        infra["status"] != "PROSPECTIVE_V2_INFRASTRUCTURE_FAILURE"
        or infra["candidate_outcomes_observed"] is not False
        or resource_v21["status"] != "PROSPECTIVE_RESOURCE_FAIL"
        or result["status"] != "PROSPECTIVE_COMPONENT_VALID_NEGATIVE"
        or resource["status"] != "PROSPECTIVE_RESOURCE_PASS"
    ):
        raise RuntimeError("prospective-v2 evidence is not the expected sequence")
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_2_0",
        "verdict": "FOUNDRY_V6_NOT_READY",
        "prior_sha256": prior_sha,
        "v2_freeze_records_sha256": freeze_v2["records_sha256"],
        "v2_1_freeze_records_sha256": freeze_v21["records_sha256"],
        "v2_2_freeze_records_sha256": freeze_v22["records_sha256"],
        "v2_infrastructure_failure_sha256": infra_sha,
        "v2_1_resource_failure_sha256": resource_v21_sha,
        "prospective_result_sha256": result_sha,
        "prospective_resource_sha256": resource_sha,
        "progress": {
            "prospective_protocol_fully_prefrozen": True,
            "outcome_driven_interventions": 0,
            "supported_families": result["supported_families"],
            "candidate_matches": result["ledgers"]["candidate"]["matches"],
            "fixed_matches": result["ledgers"]["fixed"]["matches"],
            "candidate_matched_families": result["ledgers"]["candidate"][
                "matched_families"
            ],
            "candidate_distinct_matched_tools": result["ledgers"]["candidate"][
                "distinct_matched_tools"
            ],
            "candidate_total_cost": result["ledgers"]["candidate"]["total_cost"],
            "fixed_total_cost": result["ledgers"]["fixed"]["total_cost"],
            "candidate_replays_exact": result["gates"][
                "all_candidate_replays_exact"
            ],
            "prospective_arm_metered": resource["P3_component_metered"],
            "P2_component_complete": result["P2_component_complete"],
            "P3_complete": resource["P3_complete"],
            "P5_admitted": result["P5_runtime_invention_admitted"],
        },
        "interpretation": (
            "The fully frozen trial produced a valid negative. Three families "
            "ran and one candidate macro replayed exactly. Candidate and fixed "
            "arms covered the same two nodes, while the candidate used 175 "
            "predeclared ledger units versus 235 for the larger fixed "
            "portfolio. The candidate nevertheless reached only one tool in "
            "one family, failing both breadth gates; P2 therefore remains "
            "incomplete."
        ),
        "remediation": {
            "required": True,
            "next_action": (
                "separate search macros from semantic tool construction and "
                "freeze an autonomous demand-driven grammar-extension phase "
                "whose training signal comes from unsupported or repeatedly "
                "uncovered real graph fragments, with reserved applications "
                "and the same strong fixed and cost controls"
            ),
            "forbidden_shortcuts": [
                "do not call equal benefit a discovery win",
                "do not remove breadth gates after seeing sparse reach",
                "do not treat the missing torchvision family as a pass",
                "do not admit macros as runtime inventions",
            ],
        },
        "remaining_blockers": prior["remaining_blockers"],
    }
    (RESULTS / "readiness_iteration_2_0.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n",
        encoding="utf-8",
    )
    print(
        "FOUNDRY_2_0_NOT_READY"
        f" supported={result['supported_families']}/4"
        f" candidate_matches={result['ledgers']['candidate']['matches']}"
        f" fixed_matches={result['ledgers']['fixed']['matches']}"
        f" costs={result['ledgers']['candidate']['total_cost']}"
        f"/{result['ledgers']['fixed']['total_cost']}"
        " p2_component=false"
    )


if __name__ == "__main__":
    run()
