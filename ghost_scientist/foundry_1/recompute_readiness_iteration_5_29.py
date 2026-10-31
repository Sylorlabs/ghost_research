#!/usr/bin/env python3
"""Recompute readiness after the adapted A6 production contract batch."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_28.json"
    reachability_path = (
        RESULTS / "phase149_a6_typed_anti_unification_reachability.json"
    )
    integration_path = (
        RESULTS / "phase151_a6_typed_anti_unification_runtime_contract.json"
    )
    prior = json.loads(prior_path.read_text())
    reachability = json.loads(reachability_path.read_text())
    integration = json.loads(integration_path.read_text())
    summary = integration["mount"]["summary"]
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["authorization"]["required_arms_production_integrated"] == 8
        and reachability["status"]
        == "A6_TYPED_ANTI_UNIFICATION_REACHABILITY_POSITIVE"
        and reachability["observed"]["summary"]["roots"] == 337
        and reachability["observed"]["summary"]["unordered_root_pairs"]
        == 56616
        and reachability["observed"]["summary"]["contract_candidates"] == 21
        and integration["status"]
        == "A6_TYPED_ANTI_UNIFICATION_RUNTIME_CONTRACT_PASS"
        and integration["operationally_valid"] is True
        and all(integration["checks"].values())
        and integration["integration"]["production_integrated_arms"] == 9
        and summary["graphs"] == 23
        and summary["eligible_graphs"] == 10
        and summary["eligible_tool_sites"] == 12
        and summary["whole_graph_executions"] == 69
        and summary["tool_direct_uses"] == 36
    ):
        raise RuntimeError("iteration 5.29 inputs changed")
    progress = {
        **prior["progress"],
        "production_integrated_arms": 9,
        "A6_production_integrated": True,
        "A6_adapted_not_source_faithful_Babble_or_ISAMORE": True,
        "A6_anti_unification_roots": 337,
        "A6_anti_unification_unordered_pairs": 56616,
        "A6_contract_candidates": 21,
        "A6_selected_pattern_sha256": (
            "1e98cc9eb3e3a7fb7a428708caae15963e3a37ad076b52674aa2eb916c5c791e"
        ),
        "A6_selected_pattern_is_fixed_linear_relu_duplicate": True,
        "A6_selected_matching_artifacts": 10,
        "A6_selected_match_sites": 12,
        "A6_transformed_whole_graph_executions": 69,
        "A6_observed_direct_tool_uses": 36,
        "A6_contract_pairs": len(integration["contract_bindings"]),
        "A6_hostile_contract_mutations_rejected_twice": len(
            integration["hostile_rejections"]
        ),
        "A6_maximum_absolute_error": summary["maximum_absolute_error"],
        "A6_heldout_generalization_measured": False,
        "A6_fixed_portfolio_beaten": False,
    }
    authorization = {
        **prior["authorization"],
        "required_arms_production_integrated": 9,
        "prospective_trial_authorized": False,
    }
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_29",
        "prior_sha256": sha(prior_path),
        "A6_reachability_sha256": sha(reachability_path),
        "A6_runtime_contract_sha256": sha(integration_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": authorization,
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "A6 is now a production-integrated distinctly adapted typed "
            "anti-unification control, advancing the matrix from 8/10 to "
            "9/10. Two implementations enumerated all 337 real call roots "
            "and 56,616 unordered pairs, agreed on 21 valid patterns, and "
            "selected a two-operator linear-then-relu abstraction with three "
            "typed metavariables at 12 sites across 10 artifacts. The "
            "generated callable replaced those real subgraphs and executed "
            "36 times across 69 whole-graph trials with zero observed error. "
            "All 23 primary and independent contract pairs and 22 hostile "
            "mutations passed under one process-tree receipt. The selected "
            "operator sequence duplicates the strong fixed portfolio's "
            "linear_relu tool, so this establishes autonomous construction "
            "and execution, not novelty, a fixed-portfolio win, heldout "
            "transfer, source-faithful Babble/ISAMORE, or hardware selection. "
            "A8 and V08 remain pending; validation-v6 remains sealed."
        ),
        "remaining_blockers": [
            "the production arm matrix remains 9/10: A8 is not production-integrated",
            "A8 still requires a distinctly pre-registered adapted strategy synthesizer with every evaluator-authored outcome policy frozen, independently checked, runtime mounted, and contract metered",
            "the frozen V08 search distinction remains unmeasured until full arm authorization",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "keep validation-v6 sealed and pre-register a distinctly named "
                "LLM-free A8 strategy-synthesis feasibility phase over only "
                "calibration-visible typed tools, with a frozen grammar, "
                "budgets, repository policy, scoring, tie-breaking, baseline, "
                "runtime semantics, and zero-result route"
            ),
            "forbidden_shortcuts": [
                "do not call adapted A6 source-faithful Babble or ISAMORE",
                "do not call the fixed linear_relu duplicate a novel primitive",
                "do not call calibration construction heldout transfer",
                "do not call A6 a fixed-portfolio victory",
                "do not relabel a deterministic adapted A8 control as EggMind",
                "do not lower the required arm count below ten",
                "do not call the pending V08 measurement passed",
                "do not open validation-v6 before A8 and V08 authorization pass",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_29.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_29"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=6/6"
        " integrated=9/10 A6=ADAPTED_CONTROL_PASS"
        " selected=fixed_linear_relu_duplicate V08=pending prospective=false"
    )


if __name__ == "__main__":
    main()
