#!/usr/bin/env python3
"""Decide whether the published EggMind record defines a faithful A8 build."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
INTAKE = HERE / "external_controls/eggmind/SOURCE_INTAKE.json"
PAPER_AUDIT = (
    HERE / "external_controls/eggmind/PAPER_SPECIFICATION_AUDIT_V2.json"
)
SOURCE_ROUTE = HERE / "results/phase70_eggmind_source_route_audit.json"
ADAPTED = HERE / "results/phase71_eggmind_adapted_boundary_conformance.json"
PROTOCOL = HERE / "PARETO_PROSPECTIVE_PROTOCOL_V1.json"
RESULT = (
    HERE
    / "results/phase135_eggmind_full_reproduction_sufficiency_audit.json"
)


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def main() -> None:
    intake = json.loads(INTAKE.read_text())
    paper = json.loads(PAPER_AUDIT.read_text())
    source_route = json.loads(SOURCE_ROUTE.read_text())
    adapted = json.loads(ADAPTED.read_text())
    protocol = json.loads(PROTOCOL.read_text())
    a8 = next(row for row in protocol["arms"] if row["id"] == "A8")

    specified = paper["specified_surfaces"]
    missing = paper["missing_reproduction_surfaces"]
    checks = {
        "official_repository_still_not_discovered": (
            paper["availability_refresh"]["official_repository_discovered"]
            is False
            and paper["availability_refresh"]["arxiv_code_link_present"]
            is False
        ),
        "paper_open_source_claim_preserved": (
            intake["paper_claims"]["calls_framework_open_source"] is True
            and paper["claim_boundary"]["paper_claims_framework_open_source"]
            is True
        ),
        "published_boundary_is_substantive": (
            len(specified) == 10
            and paper["published_executable_identity"]["default_model"]
            == "Doubao-Seed-2.0-pro"
            and paper["published_executable_identity"][
                "vectorization_model_requests"
            ]
            == 53
        ),
        "missing_choices_are_outcome_determining": (
            len(missing) == 16
            and any("action-selection policy" in row for row in missing)
            and any("proof-tree local-region" in row for row in missing)
            and any("EqSatL-to-egglog lowering" in row for row in missing)
            and any("synthesized strategy artifacts" in row for row in missing)
        ),
        "paper_only_faithful_route_rejected": (
            paper["reproduction_rule"]["paper_only_route_passes"] is False
            and paper["reproduction_rule"][
                "llm_free_reimplementation_is_source_faithful"
            ]
            is False
        ),
        "prior_source_route_agrees": (
            source_route["status"]
            == "EGGMIND_UPSTREAM_SOURCE_NOT_DISCOVERED"
            and source_route["P1"]["complete"] is False
        ),
        "partial_adapted_boundary_preserved": (
            adapted["status"]
            == "EGGMIND_ADAPTED_BOUNDARY_CONFORMANCE_PASS"
            and adapted["P1"][
                "full_eggmind_style_control_conformance_passed"
            ]
            is False
        ),
        "a8_was_required_and_unready": (
            a8["required_for_validity"] is True
            and a8["conformance_ready"] is False
            and a8["production_integrated"] is False
        ),
        "validation_v6_remained_sealed": (
            paper["claim_boundary"]["validation_v6_accessed"] is False
        ),
    }
    if not all(checks.values()):
        raise RuntimeError("EggMind reproduction sufficiency audit failed")

    payload = {
        "version":
        "FOUNDRY_EGGMIND_FULL_REPRODUCTION_SUFFICIENCY_AUDIT_V1",
        "status": "EGGMIND_PAPER_ONLY_FULL_REPRODUCTION_NOT_SPECIFIED",
        "classification":
        "CURRENT_SPECIFICATION_NO_GO_NOT_PERMANENT_IMPOSSIBILITY",
        "provider_records": [
            {"path": str(path.relative_to(HERE)), "sha256": sha(path)}
            for path in [
                INTAKE,
                PAPER_AUDIT,
                SOURCE_ROUTE,
                ADAPTED,
                PROTOCOL,
            ]
        ],
        "checks": checks,
        "surface_counts": {
            "specified": len(specified),
            "missing_outcome_determining": len(missing),
        },
        "decisions": {
            "source_faithful_EggMind_build_authorized": False,
            "paper_only_A8_promotion_authorized": False,
            "partial_boundary_may_count_as_A8": False,
            "deterministic_llm_free_substitute_may_be_called_EggMind": False,
            "deterministic_llm_free_substitute_may_be_new_research": True,
            "A8_production_integrated": False,
            "P1_complete": False,
            "production_integrated_arms": 6,
            "prospective_trial_authorized": False,
        },
        "unblock_conditions": [
            "obtain an immutable official EggMind source revision and its exact workload fixtures",
            "or obtain a complete defining specification for every missing outcome-determining surface",
            "or pre-register a distinctly named LLM-free adapted control with its own independent baseline and falsification criteria, without counting it as source-faithful EggMind",
        ],
        "next_phase": {
            "route": "A6_ISAMORE",
            "reason": (
                "A6 remains the frozen independently implemented fourth-control "
                "route; unlike an invented A8 substitute, exact upstream "
                "ISAMORE source and a published workload are already identified."
            ),
            "required_external_delta": (
                "acquire the exact locked Rust archive closure plus native "
                "Coin-OR CBC and the pinned nightly, then execute the pre-frozen "
                "top-level fixture"
            ),
        },
        "claim_boundary": (
            "The paper specifies real architectural and mathematical surfaces, "
            "but not enough outcome-determining policy, lowering, proof "
            "extraction, cache, and fixture detail to reconstruct the reported "
            "system. This is a current reproducibility no-go, not a claim that "
            "the authors' system is invalid or that source cannot later appear."
        ),
        "validation_v6_accessed": False,
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE135_EGGMIND_REPRODUCTION_SUFFICIENCY"
        " status=EGGMIND_PAPER_ONLY_FULL_REPRODUCTION_NOT_SPECIFIED"
        f" specified={len(specified)} missing={len(missing)}"
        " A8=false P1=false prospective=false"
    )


if __name__ == "__main__":
    main()
