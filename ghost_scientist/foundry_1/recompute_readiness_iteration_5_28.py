#!/usr/bin/env python3
"""Recompute readiness after the adapted A1 production contract batch."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_27.json"
    failed_path = RESULTS / "phase146_a1_pattern_first_fold_conformance.json"
    remediation_path = (
        RESULTS / "phase147_a1_fold_numerical_stability_remediation.json"
    )
    integration_path = (
        RESULTS / "phase148_a1_full_runtime_contract_batch.json"
    )
    prior = json.loads(prior_path.read_text())
    failed = json.loads(failed_path.read_text())
    remediation = json.loads(remediation_path.read_text())
    integration = json.loads(integration_path.read_text())
    mount_summary = integration["mount"]["summary"]
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["authorization"]["required_arms_production_integrated"] == 7
        and failed["status"] == "A1_ADAPTED_FOLD_CONFORMANCE_INVALID"
        and failed["operationally_valid"] is False
        and remediation["status"]
        == "A1_POST_FAILURE_NUMERICAL_REMEDIATION_PASS"
        and remediation["pristine_preregistration"] is False
        and all(remediation["checks"].values())
        and remediation["decision"]["phase146_remains_failed"] is True
        and integration["status"] == "A1_FULL_RUNTIME_CONTRACT_BATCH_PASS"
        and integration["operationally_valid"] is True
        and all(integration["checks"].values())
        and integration["integration"]["production_integrated_arms"] == 8
        and integration["integration"]["phase146_remains_failed"] is True
        and mount_summary["graphs"] == 23
        and mount_summary["eligible_fold_sites"] == 3
        and mount_summary["whole_graph_executions"] == 69
        and mount_summary["fold_checks"] == 9
    ):
        raise RuntimeError("iteration 5.28 inputs changed")
    progress = {
        **prior["progress"],
        "production_integrated_arms": 8,
        "A1_typed_lowering_implemented": True,
        "A1_constructor_executed": True,
        "A1_production_integrated": True,
        "A1_adapted_not_unchanged_v5_1": True,
        "A1_exact_added_calibration_signatures": 1,
        "A1_real_eligible_graphs": mount_summary["eligible_graphs"],
        "A1_real_fold_sites": mount_summary["eligible_fold_sites"],
        "A1_whole_graph_executions": mount_summary[
            "whole_graph_executions"
        ],
        "A1_real_fold_checks": mount_summary["fold_checks"],
        "A1_contract_pairs": len(integration["contract_bindings"]),
        "A1_hostile_contract_mutations_rejected_twice": len(
            integration["hostile_rejections"]
        ),
        "A1_runtime_maximum_absolute_error": mount_summary[
            "maximum_absolute_error"
        ],
        "A1_phase146_absolute_only_conformance_failed": True,
        "A1_post_failure_amendment_pristine_preregistration": False,
        "A1_unseen_numerical_panel_passes": remediation["observed"][
            "summary"
        ]["unseen_panel_combined_passes"],
        "A1_unseen_numerical_panel_total": remediation["observed"][
            "summary"
        ]["unseen_panel_replicates"],
        "A1_heldout_generalization_measured": False,
        "A1_fixed_portfolio_beaten": False,
    }
    authorization = {
        **prior["authorization"],
        "required_arms_production_integrated": 8,
        "prospective_trial_authorized": False,
    }
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_28",
        "prior_sha256": sha(prior_path),
        "A1_failed_conformance_sha256": sha(failed_path),
        "A1_numerical_remediation_sha256": sha(remediation_path),
        "A1_full_runtime_contract_sha256": sha(integration_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": authorization,
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "A1 is now a production-integrated adapted calibration control, "
            "advancing the matrix from 7/10 to 8/10. The first frozen "
            "absolute-only synthetic conformance run remains failed because "
            "one target measured 1.28746e-5 against a 1e-5 limit. A disclosed "
            "post-failure amendment, explicitly not pristine, then froze 48 "
            "unseen scale-aware numerical fixtures; all 48 passed while the "
            "nine real source checks retained the original 1e-5 absolute "
            "limit. The full mount passes 69 whole-graph executions, nine real "
            "fold checks, 23 primary and independent contract pairs, one "
            "shared process receipt, and 22 hostile contract mutations. Only "
            "one exact calibration signature was added; unmatched artifacts "
            "use reference fallback. This is not unchanged v5.1, heldout "
            "transfer, or a fixed-portfolio victory. A6 and A8 remain absent, "
            "so V08 and validation-v6 remain sealed."
        ),
        "remaining_blockers": [
            "the production arm matrix remains 8/10: A6 and A8 are not production-integrated",
            "A6 still requires the exact ISAMORE locked/native execution closure or an equally distinct pre-registered anti-unification control",
            "A8 still lacks a faithful upstream implementation or a distinctly pre-registered adapted production control with all outcome-determining policies frozen",
            "the frozen V08 search distinction remains unmeasured until full arm authorization",
        ],
        "remediation": {
            "required": True,
            "next_action": (
                "keep validation-v6 sealed and run a hash-bound closure ranking "
                "between A6 and A8, selecting only a route with obtainable "
                "source semantics, a distinct control mechanism, full runtime "
                "mountability, and a credible 23-pair contract path"
            ),
            "forbidden_shortcuts": [
                "do not erase or reclassify the failed phase146 absolute-only result",
                "do not call the post-failure numerical amendment pristine",
                "do not call adapted A1 unchanged v5.1 or heldout transfer",
                "do not count reference fallback as direct tool use",
                "do not lower the required arm count below ten",
                "do not call the pending V08 measurement passed",
                "do not open validation-v6 before A6, A8, and V08 authorization pass",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_28.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_28"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=6/6"
        " integrated=8/10 A1=ADAPTED_CONTROL_PASS"
        " phase146=FAILED unseen_numeric=48/48 V08=pending prospective=false"
    )


if __name__ == "__main__":
    main()
