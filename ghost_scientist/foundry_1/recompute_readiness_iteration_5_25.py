#!/usr/bin/env python3
"""Recompute readiness after the adapted A7 production contract batch."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_24.json"
    transfer_path = RESULTS / "phase140_a7_enumo_real_graph_transfer.json"
    mount_path = RESULTS / "phase141_a7_enumo_runtime_conformance.json"
    resource_path = RESULTS / "phase144_a7_shared_resource_batch_resource_audit.json"
    prior = json.loads(prior_path.read_text())
    transfer = json.loads(transfer_path.read_text())
    mount = json.loads(mount_path.read_text())
    resource = json.loads(resource_path.read_text())
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["authorization"]["prerequisites_passed"] == 6
        and prior["authorization"]["required_arms_production_integrated"] == 6
        and transfer["status"] == "A7_ENUMO_REAL_GRAPH_TRANSFER_PASS"
        and transfer["decision"]["A7_production_integrated"] is False
        and mount["status"] == "A7_ENUMO_RUNTIME_CONFORMANCE_PASS"
        and mount["runtime_receipt"]["summary"][
            "unique_selected_transformations"
        ]
        == 12
        and resource["status"]
        == "A7_SHARED_RESOURCE_BATCH_RESOURCE_PASS"
        and resource["integration"]["A7_production_integrated"] is True
        and resource["integration"]["production_integrated_arms"] == 7
    ):
        raise RuntimeError("iteration 5.25 inputs changed")
    summary = mount["runtime_receipt"]["summary"]
    progress = {
        **prior["progress"],
        "A7_production_integrated": True,
        "A7_adapted_tensor_domain": True,
        "A7_real_graph_eligible_graphs": summary["eligible_graphs"],
        "A7_real_graph_eligible_calls": summary["eligible_calls"],
        "A7_learned_root_matches": summary["learned_root_matches"],
        "A7_raw_selected_rule_applications": summary[
            "raw_selected_rule_applications"
        ],
        "A7_unique_selected_transformations": summary[
            "unique_selected_transformations"
        ],
        "A7_whole_graph_executions": summary["whole_graph_executions"],
        "A7_unique_rewrite_concrete_checks": summary[
            "unique_rewrite_concrete_checks"
        ],
        "A7_contract_pairs": 23,
        "A7_hostile_batches_rejected": 22,
        "A7_strict_atom_cost_reductions": 0,
        "A7_fixed_portfolio_beaten": False,
        "A7_heldout_generalization_measured": False,
    }
    authorization = {
        **prior["authorization"],
        "required_arms_production_integrated": 7,
        "prospective_trial_authorized": False,
    }
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_25",
        "prior_sha256": sha(prior_path),
        "A7_transfer_sha256": sha(transfer_path),
        "A7_mount_sha256": sha(mount_path),
        "A7_batch_resource_sha256": sha(resource_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": authorization,
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "A7 is now a complete production-integrated adapted calibration "
            "rule-inference control. The frozen 18-rule evaluator-authored "
            "Enumo tensor domain intersects 53 calls across 17 real calibration "
            "graphs. It produces 282 root matches and 24 raw selected rule "
            "applications, which deduplicate to 12 equal-atom-cost operand "
            "canonicalizations. All 69 whole-graph executions and 36 concrete "
            "rewrite checks are exact. Twenty-three strict contract pairs, one "
            "shared process receipt, two base-contract verifiers, and 22 hostile "
            "batch mutations pass. This is valid comparator integration, not a "
            "win: there are zero strict atom-cost reductions, no fixed-portfolio "
            "victory, no rewritten whole-graph execution, and no heldout transfer. "
            "The production matrix advances from 6/10 to 7/10. Validation-v6 "
            "remains sealed because A1, A6, and A8 are still absent and V08 is pending."
        ),
        "remaining_blockers": [
            "the production arm matrix remains 7/10: A1, A6, and A8 are not production-integrated",
            "A1 requires a complete typed lowering and a genuine frozen-constructor alternative rather than opaque fallback",
            "A6 still requires the exact ISAMORE locked/native execution closure or an equally distinct pre-registered anti-unification control",
            "A8 still lacks a faithful upstream implementation or a distinctly pre-registered adapted production control with all outcome-determining policies frozen",
            "the frozen V08 search distinction remains unmeasured until full arm authorization",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "keep validation-v6 sealed; begin the A1 typed-lowering bridge "
                "with a pre-frozen subgraph/signature reachability audit that "
                "must demonstrate at least one genuine v5.1 nonreference "
                "constructor opportunity before implementing the full 41-target runtime"
            ),
            "forbidden_shortcuts": [
                "do not call A7 a fixed-portfolio win or strict cost reduction",
                "do not relabel the adapted tensor domain as the frozen Boolean A7",
                "do not count empirical calibration commutativity as universal floating-point soundness",
                "do not lower the required arm count below ten",
                "do not call the pending V08 measurement passed",
                "do not open validation-v6 before the full arm and validity authorization passes",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_25.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_25"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=6/6"
        " integrated=7/10 A7=ADAPTED_CONTROL_PASS"
        " reductions=0 V08=pending prospective=false"
    )


if __name__ == "__main__":
    main()
