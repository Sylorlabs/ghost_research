#!/usr/bin/env python3
"""Calibration-only mechanism audit of the frozen prospective negative."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
RESULT = RESULTS / "phase61_diversity_failure_calibration.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def run() -> None:
    result_freeze_raw = (
        RESULTS / "diversity_result_v1_freeze.json"
    ).read_bytes()
    result_freeze = json.loads(result_freeze_raw)
    trial = json.loads(
        (RESULTS / "phase59_prospective_diversity_trial.json").read_text()
    )
    calibration = json.loads(
        (RESULTS / "phase53_diversity_calibration_audit.json").read_text()
    )
    forge = json.loads(
        (RESULTS / "phase55_diversity_tool_forge.json").read_text()
    )
    library = json.loads(
        (RESULTS / "forged_diversity_tools.json").read_text()
    )
    if (
        result_freeze["classification"] != "PROSPECTIVE_VALID_NEGATIVE"
        or trial["status"] != "DIVERSITY_PROSPECTIVE_VALID_NEGATIVE"
    ):
        raise RuntimeError("failure audit is not bound to frozen negative")

    prospective_only_candidate_cost = (
        trial["candidate"]["definition_cost"]
        + trial["candidate"]["prospective_graph_node_visits"]
        + trial["candidate"]["prospective_edge_checks"]
    )
    prospective_only_fixed_cost = trial["fixed"]["total_cost"]
    repeated_cohort_break_even = None
    for cohorts in range(1, 101):
        candidate_cost = (
            trial["candidate"]["calibration_search_cost"]
            + prospective_only_candidate_cost * cohorts
        )
        fixed_cost = prospective_only_fixed_cost * cohorts
        candidate_benefit = (
            trial["candidate"]["unique_node_benefit"] * cohorts
        )
        fixed_benefit = trial["fixed"]["unique_node_benefit"] * cohorts
        candidate_efficiency = candidate_benefit / candidate_cost
        fixed_efficiency = fixed_benefit / fixed_cost
        if (
            candidate_cost < fixed_cost
            and candidate_efficiency > fixed_efficiency
        ):
            repeated_cohort_break_even = cohorts
            break

    matched_ids = {row["tool_id"] for row in trial["candidate_rows"]}
    tool_rows = []
    for tool in library["tools"]:
        sequence = [node["target"] for node in tool["nodes"]]
        tool_rows.append(
            {
                "tool_id": tool["tool_id"],
                "target_sequence": sequence,
                "transferred": tool["tool_id"] in matched_ids,
                "training_family_count": tool["training"]["family_count"],
                "training_occurrence_count": tool["training"][
                    "occurrence_count"
                ],
            }
        )
    fixed_duplicates_discarded = sum(
        item["fixed_target_sequence_duplicate"]
        for item in calibration["selected"]
    )
    novel_considered = len(calibration["novel"])
    gates_failed = sorted(
        name for name, passed in trial["gates"].items() if not passed
    )
    mechanisms = {
        "coverage_deficit": {
            "candidate_unique_nodes": trial["candidate"][
                "unique_node_benefit"
            ],
            "fixed_unique_nodes": trial["fixed"]["unique_node_benefit"],
            "deficit": trial["fixed"]["unique_node_benefit"]
            - trial["candidate"]["unique_node_benefit"],
            "largest_family_deficit": "lenet_image_classification",
            "largest_family_candidate_nodes": 5,
            "largest_family_fixed_nodes": 9,
        },
        "upfront_search_amortization": {
            "calibration_search_cost": trial["candidate"][
                "calibration_search_cost"
            ],
            "candidate_prospective_only_cost": prospective_only_candidate_cost,
            "fixed_prospective_cost": prospective_only_fixed_cost,
            "candidate_prospective_only_cheaper": prospective_only_candidate_cost
            < prospective_only_fixed_cost,
            "repeated_equal_cohort_efficiency_break_even": repeated_cohort_break_even,
        },
        "novelty_only_portfolio_constraint": {
            "selected_calibration_motifs": len(calibration["selected"]),
            "machine_rediscovered_fixed_sequences_discarded": fixed_duplicates_discarded,
            "novel_sequences_considered": novel_considered,
            "source_motifs_represented_by_executable_tools": forge[
                "represented_source_motifs"
            ],
            "prospective_tools_transferred": len(matched_ids),
        },
        "uncovered_sequence_domain": {
            "family": "lstm_language_model",
            "candidate_matches": 0,
            "fixed_matches": 0,
            "newly_reachable": False,
        },
    }
    remediation = {
        "next_forge": "machine_selected_pareto_portfolio",
        "inputs": (
            "all recurring typed motifs across the now-calibration-only "
            "23-graph corpus, including machine rediscoveries of fixed forms"
        ),
        "objective": (
            "maximize unique-node coverage and repository-domain reach while "
            "minimizing definition, calibration, visit, and edge costs"
        ),
        "required_ablation": (
            "compare novelty-only, all-motif, and Pareto-selected machine "
            "portfolios without changing the strong fixed baseline"
        ),
        "prospective_requirement": (
            "freeze a new repository-disjoint source intake before building "
            "the selected executable portfolio"
        ),
        "forbidden": [
            "do not reuse v5 as prospective evidence",
            "do not remove fixed tools to manufacture a win",
            "do not label stock composites native inventions",
            "do not manually choose the winning portfolio",
        ],
    }
    payload = {
        "version": "FOUNDRY_DIVERSITY_FAILURE_CALIBRATION_V1",
        "status": "DIVERSITY_FAILURE_MECHANISM_AUDIT_COMPLETE",
        "classification": "POST_PROSPECTIVE_CALIBRATION_ONLY",
        "result_freeze_sha256": hashlib.sha256(
            result_freeze_raw
        ).hexdigest(),
        "failed_gates": gates_failed,
        "mechanisms": mechanisms,
        "tool_transfer_rows": tool_rows,
        "remediation": remediation,
        "prospective_claim_allowed": False,
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE61_DIVERSITY_FAILURE_CALIBRATION_PASS"
        f" failed_gates={len(gates_failed)}"
        f" transferred={len(matched_ids)}/{len(library['tools'])}"
        f" break_even={repeated_cohort_break_even}"
        f" discarded_fixed={fixed_duplicates_discarded}"
    )


if __name__ == "__main__":
    run()
