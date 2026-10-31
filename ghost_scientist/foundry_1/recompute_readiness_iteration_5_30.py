#!/usr/bin/env python3
"""Recompute 10/10 arm readiness after the v6 chronology incident."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_29.json"
    reachability_path = (
        RESULTS / "phase152_a8_adapted_strategy_reachability.json"
    )
    integration_path = (
        RESULTS / "phase153_a8_adapted_strategy_runtime_contract.json"
    )
    incident_path = (
        RESULTS / "phase154_validation_v6_pre_authorization_access_incident.json"
    )
    prior = json.loads(prior_path.read_text())
    reachability = json.loads(reachability_path.read_text())
    integration = json.loads(integration_path.read_text())
    incident = json.loads(incident_path.read_text())
    summary = integration["mount"]["summary"]
    if not (
        prior["authorization"]["required_arms_production_integrated"] == 9
        and reachability["status"]
        == "A8_ADAPTED_STRATEGY_REACHABILITY_POSITIVE"
        and reachability["observed"]["summary"]["candidate_strategies"]
        == 40320
        and integration["status"]
        == "A8_ADAPTED_STRATEGY_RUNTIME_CONTRACT_PASS"
        and integration["operationally_valid"] is True
        and all(integration["checks"].values())
        and integration["integration"]["production_integrated_arms"] == 10
        and summary["graphs"] == 23
        and summary["eligible_strategy_applications"] == 20
        and summary["covered_graph_nodes"] == 49
        and summary["whole_graph_executions"] == 69
        and summary["strategy_tool_direct_uses"] == 60
        and incident["status"]
        == "VALIDATION_V6_PROSPECTIVE_CHRONOLOGY_INVALIDATED"
        and incident["effects"]["prospective_trial_executed"] is False
        and incident["effects"]["V08_real_measurement_executed"] is False
    ):
        raise RuntimeError("iteration 5.30 inputs changed")
    prerequisites = {
        **prior["prerequisites"],
        "P6_unchanged_prospective_freeze": False,
    }
    progress = {
        **prior["progress"],
        "production_integrated_arms": 10,
        "A8_production_integrated": True,
        "A8_new_adapted_control_not_EggMind": True,
        "A8_post_exploratory_pristine_preregistration": False,
        "A8_candidate_strategies_enumerated": 40320,
        "A8_distinct_score_vectors": 8,
        "A8_baseline_direct_applications": 22,
        "A8_selected_direct_applications": 20,
        "A8_covered_graph_nodes": 49,
        "A8_eligible_artifacts": 12,
        "A8_whole_graph_executions": 69,
        "A8_observed_strategy_tool_calls": 60,
        "A8_contract_pairs": len(integration["contract_bindings"]),
        "A8_hostile_contract_mutations_rejected_twice": len(
            integration["hostile_rejections"]
        ),
        "A8_maximum_absolute_error": summary["maximum_absolute_error"],
        "A8_fixed_tool_portfolio_beaten": False,
        "A8_heldout_generalization_measured": False,
        "validation_v6_pre_authorization_source_accessed": True,
        "validation_v6_workloads_executed": False,
        "validation_v6_outcomes_observed": False,
        "validation_v6_retired_from_primary_prospective_claim": True,
        "V08_measurement_passed": False,
    }
    authorization = {
        **prior["authorization"],
        "prerequisites_passed": 5,
        "required_arms_production_integrated": 10,
        "active_stop_conditions": 1,
        "pending_trial_validity_measurements": 1,
        "prospective_trial_authorized": False,
    }
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_30",
        "prior_sha256": sha(prior_path),
        "A8_reachability_sha256": sha(reachability_path),
        "A8_runtime_contract_sha256": sha(integration_path),
        "validation_v6_incident_sha256": sha(incident_path),
        "prerequisites": prerequisites,
        "progress": progress,
        "authorization": authorization,
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "All ten required calibration arms are now production-integrated "
            "and metered. A8 is a new adapted LLM-free strategy control, not "
            "EggMind: two evaluators scored all 40,320 fixed-tool priority "
            "orders and selected one preserving 49 covered nodes across 12 "
            "artifacts while reducing applications from 22 to 20. Its runtime "
            "mount executed 60 generated recipe calls across 69 whole-graph "
            "trials with zero error, 23 contract pairs, and 22 hostile "
            "rejections. This only beats the supplied tool order on "
            "applications; it does not beat the fixed portfolio or establish "
            "heldout transfer. After integration, validation-v6 runtime source "
            "was opened before a new authorization record. No v6 workload, "
            "graph, or outcome was executed, but the prospective chronology is "
            "invalid. P6 therefore fails for v6, V08 remains unmeasured, and "
            "no prospective result is claimed."
        ),
        "remaining_blockers": [
            "validation-v6 prospective chronology is permanently invalid for the primary claim because its runtime source was opened before authorization",
            "P6 requires a fresh validation-v7 corpus and complete seed, adapter, evaluator, and V08 freeze before any source/runtime graph access",
            "the frozen V08 search distinction must be re-bound to v7 and measured only inside an authorized sealed trial",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "stage a fresh validation-v7 corpus through a separation "
                "boundary that exposes only immutable identities and hashes "
                "before authorization; then refreeze the exact runner, seed, "
                "all arm bindings, evaluator, and V08 receipt protocol without "
                "opening source or runtime definitions"
            ),
            "forbidden_shortcuts": [
                "do not use validation-v6 for the primary prospective claim",
                "do not erase or downgrade the phase154 chronology incident",
                "do not call 10/10 calibration integration a prospective result",
                "do not call adapted A8 EggMind",
                "do not call the post-exploratory A8 protocol pristine",
                "do not claim the fixed portfolio was beaten",
                "do not claim V08 passed before fresh real paired receipts exist",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_30.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_30"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6"
        " integrated=10/10 P6=FAILED_V6_CHRONOLOGY"
        " V08=pending prospective=false"
    )


if __name__ == "__main__":
    main()
