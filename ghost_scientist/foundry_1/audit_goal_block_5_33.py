#!/usr/bin/env python3
"""Record the requirement-level external-state block for the active goal."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
RESULT = RESULTS / "goal_block_audit_5_33.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def non_readme_files(path: pathlib.Path) -> list[str]:
    return sorted(item.name for item in path.iterdir() if item.name != "README.md")


def main() -> None:
    readiness_path = RESULTS / "readiness_iteration_5_33.json"
    intake_path = RESULTS / "phase157_validation_v7_identity_only_intake_v2.json"
    provenance_path = RESULTS / "phase159_validation_v7_accountable_provenance_v2.json"
    readiness = json.loads(readiness_path.read_text())
    intake = json.loads(intake_path.read_text())
    provenance = json.loads(provenance_path.read_text())
    trust_files = non_readme_files(HERE / "validation_v7_external_trust_root")
    bundle_files = non_readme_files(HERE / "validation_v7_sealed_inbox")
    provenance_files = non_readme_files(HERE / "validation_v7_provenance_inbox")
    requirements = {
        "llm_free_autonomous_typed_tool_forge": {
            "status": "PROVED_FOR_FROZEN_CALIBRATION_SCOPE",
            "evidence": "readiness 5.33 preserves autonomous_typed_grammar_already_established=true",
        },
        "independent_parsing_interpretation_and_verification": {
            "status": "PROVED_FOR_IMPLEMENTED_FORGE_AND_GATES",
            "evidence": "full dossier verifier passes and v2 intake/provenance each have two implementations",
        },
        "native_compiler_deduplication": {
            "status": "PROVED_FOR_FROZEN_CANDIDATE",
            "evidence": "four stock-decomposition duplicates and zero admitted runtime inventions",
        },
        "complete_resource_accounting": {
            "status": "PROVED_FOR_FROZEN_PATHS",
            "evidence": "P3=true and current hostile/conformance workers carry process-tree receipts",
        },
        "faithful_conformance_tested_control_arms": {
            "status": "PROVED_FOR_REQUIRED_MATRIX",
            "evidence": "10/10 production-integrated calibration arms",
        },
        "independently_sourced_heterogeneous_workload_and_trace": {
            "status": "HISTORICAL_P2_PROVED_BUT_FRESH_V7_CORPUS_ABSENT",
            "evidence": "P2=true; corrected validation-v7 inbox is 0/5",
        },
        "calibration_only_adversarial_pilots": {
            "status": "PROVED_AND_KEPT_SEPARATE_FROM_PROSPECTIVE_CLAIM",
            "evidence": "readiness 5.33 preserves calibration-only results and explicit claim boundaries",
        },
        "hash_frozen_prospective_protocol": {
            "status": "NOT_ACHIEVED_FOR_FRESH_V7",
            "evidence": "P6=false; v6 chronology invalidated; exact v7 bundle and provenance predecessors absent",
        },
        "prospective_execution_without_outcome_driven_intervention": {
            "status": "NOT_AUTHORIZED_AND_NOT_EXECUTED",
            "evidence": "V08 pending and prospective_trial_authorized=false",
        },
    }
    blockers = {
        "external_sponsor_fingerprint": {
            "required": True,
            "present": bool(trust_files),
            "foundry_may_generate": False,
        },
        "external_validation_v7_v2_bundle": {
            "required_files": 5,
            "present_files": len(bundle_files),
            "foundry_may_curate": False,
        },
        "external_accountable_provenance_v2_package": {
            "required_files": 13,
            "present_files": len(provenance_files),
            "foundry_may_generate_or_self_attest": False,
        },
    }
    if not (
        readiness["verdict"] == "FOUNDRY_V6_NOT_READY"
        and sum(readiness["prerequisites"].values()) == 5
        and readiness["prerequisites"]["P6_unchanged_prospective_freeze"]
        is False
        and readiness["progress"]["production_integrated_arms"] == 10
        and intake["status"]
        == "VALIDATION_V7_IDENTITY_ONLY_INTAKE_V2_WAITING"
        and provenance["status"] == "WAITING_EXTERNAL_SPONSOR_TRUST_ROOT"
        and not trust_files
        and not bundle_files
        and not provenance_files
    ):
        raise RuntimeError("goal block audit inputs changed")
    payload = {
        "version": "FOUNDRY_GOAL_BLOCK_AUDIT_5_33_V1",
        "status": "EXTERNAL_INDEPENDENCE_BOUNDARY_REQUIRED",
        "readiness_sha256": sha(readiness_path),
        "phase157_sha256": sha(intake_path),
        "phase159_sha256": sha(provenance_path),
        "requirements": requirements,
        "blockers": blockers,
        "completion_proved": False,
        "meaningful_internal_work_remaining_before_external_state_change": False,
        "reason": (
            "Foundry cannot create, select, approve, sign, or simulate the "
            "production sponsor trust root, independent v2 corpus, curator "
            "provenance, independent review, or external log without violating "
            "the frozen independence and chronology boundary. Exact v7 trial "
            "freezing and key release necessarily follow those real artifacts."
        ),
        "resume_condition": (
            "enroll an out-of-band verified sponsor fingerprint and supply the "
            "corrected five-file v2 bundle plus thirteen-file provenance-v2 package"
        ),
        "payload_decrypted": False,
        "prospective_trial_authorized": False,
        "prospective_trial_executed": False,
    }
    RESULT.write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_GOAL_BLOCK_AUDIT_5_33"
        " status=EXTERNAL_INDEPENDENCE_BOUNDARY_REQUIRED"
        " internal_work_remaining=false trust=false bundle=0/5 provenance=0/13"
    )


if __name__ == "__main__":
    main()
