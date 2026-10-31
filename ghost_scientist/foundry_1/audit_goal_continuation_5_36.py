#!/usr/bin/env python3
"""Audit the full goal after exhausting the justified local remediation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
RESULT = RESULTS / "goal_continuation_audit_5_36.json"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    readiness_path = RESULTS / "readiness_iteration_5_36.json"
    utility_path = RESULTS / "phase166_local_exact_tool_utility.json"
    intake_path = RESULTS / "phase157_validation_v7_identity_only_intake_v2.json"
    provenance_path = RESULTS / "phase159_validation_v7_accountable_provenance_v2.json"
    v08_path = RESULTS / "phase134_v08_search_distinction_conformance.json"
    readiness = json.loads(readiness_path.read_text())
    utility = json.loads(utility_path.read_text())
    intake = json.loads(intake_path.read_text())
    provenance = json.loads(provenance_path.read_text())
    v08 = json.loads(v08_path.read_text())
    intake_summary = intake["observed"]["summary"]
    provenance_summary = provenance["observed"]["summary"]
    if not (
        readiness["verdict"] == "FOUNDRY_V6_NOT_READY"
        and sum(readiness["prerequisites"].values()) == 5
        and readiness["progress"]["production_integrated_arms"] == 10
        and readiness["progress"]["local_exact_tool_bounded_new_reach"] is True
        and readiness["progress"]["local_exact_tool_runtime_inventions"] == 0
        and utility["status"] == "LOCAL_EXACT_TOOL_UTILITY_POSITIVE"
        and utility["decision"]["prospective_real_world_discovery_demonstrated"]
        is False
        and v08["status"] == "V08_SEARCH_DISTINCTION_PREFLIGHT_CONFORMANCE_PASS"
        and v08["preflight_effect"]["V08_measurement_passed"] is False
        and intake_summary["real_present_required_files"] == 0
        and intake_summary["real_missing_required_files"] == 5
        and provenance_summary["real_trust_root_present"] is False
        and provenance_summary["real_bundle_files_present"] == 0
        and provenance_summary["real_provenance_files_present"] == 0
    ):
        raise RuntimeError("goal continuation audit inputs changed")
    requirements = {
        "llm_free_typed_tool_construction": {
            "status": "PROVED_BOUNDED_LOCAL",
            "evidence": "Phase163-Phase164 training-only operator and complete-body prediction",
        },
        "independent_parsing_interpretation_verification": {
            "status": "PROVED_BOUNDED_LOCAL",
            "evidence": "independent ledgers agree exactly through Phase166",
        },
        "real_value_tool_execution": {
            "status": "PROVED_BOUNDED_LOCAL",
            "evidence": "Phase165 exact 17/17 under two executors",
        },
        "native_compiler_deduplication": {
            "status": "PROVED_STOCK_DUPLICATE",
            "evidence": "three of three unique bodies normalize identically to stock",
        },
        "complete_resource_and_total_cost_accounting": {
            "status": "PROVED_BOUNDED_LOCAL",
            "evidence": "Phase166 cost 12465 candidate versus 2072 fixed plus separate process receipts",
        },
        "bounded_new_reachability": {
            "status": "PROVED_BOUNDED_LOCAL",
            "evidence": "nine candidate-only nodes across eight families",
        },
        "fresh_external_prospective_evidence": {
            "status": "MISSING_EXTERNAL_PREDECESSORS",
            "evidence": "sponsor false, bundle 0/5, provenance 0/13",
        },
        "V08_heldout_measurement": {
            "status": "PENDING_AUTHORIZED_HELDOUT",
            "evidence": "preflight passes but measurement is false",
        },
        "prospective_trial_authorization": {
            "status": "DENIED",
            "evidence": "P6 false and prerequisites 5/6",
        },
    }
    result = {
        "version": "FOUNDRY_GOAL_CONTINUATION_AUDIT_5_36",
        "status": "LOCAL_REMEDIATION_COMPLETE_WAITING_EXTERNAL_PREDECESSORS",
        "inputs": {
            "readiness_iteration_5_36_sha256": sha(readiness_path),
            "phase166_utility_sha256": sha(utility_path),
            "phase157_intake_v2_sha256": sha(intake_path),
            "phase159_provenance_v2_sha256": sha(provenance_path),
            "phase134_v08_conformance_sha256": sha(v08_path),
        },
        "requirements": requirements,
        "local_work_remaining_before_external_intake": [],
        "external_predecessors": {
            "out_of_band_verified_sponsor_fingerprint": False,
            "validation_v7_v2_bundle_present": 0,
            "validation_v7_v2_bundle_required": 5,
            "accountable_provenance_v2_present": 0,
            "accountable_provenance_v2_required": 13,
        },
        "authorization": {
            "P6_advanced": False,
            "V08_measurement_passed": False,
            "prospective_trial_authorized": False,
            "prospective_trial_executed": False,
        },
        "next_exact_action": (
            "after an out-of-band sponsor fingerprint and exact external v2 bundle "
            "plus provenance package arrive, rerun Phase157 and Phase159 unchanged; "
            "then freeze real seed, runner, forge binding, evaluator, containment, "
            "key release, and V08 receipts before decryption"
        ),
        "forbidden_manufacture": [
            "Foundry must not create, choose, approve, or sign the production sponsor identity",
            "Foundry must not synthesize curator, reviewer, or external-log provenance",
            "Foundry must not reuse the observed local corpus as fresh prospective evidence",
            "Foundry must not execute or label a prospective trial while P6 is false",
        ],
    }
    RESULT.write_text(json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n")
    print(
        "FOUNDRY_GOAL_CONTINUATION_AUDIT_5_36"
        " status=LOCAL_REMEDIATION_COMPLETE_WAITING_EXTERNAL_PREDECESSORS"
        " sponsor=false bundle=0/5 provenance=0/13"
        " V08=pending P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
