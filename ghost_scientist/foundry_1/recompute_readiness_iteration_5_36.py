#!/usr/bin/env python3
"""Recompute readiness after fully charged local utility evaluation."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_35.json"
    utility_path = RESULTS / "phase166_local_exact_tool_utility.json"
    prior = json.loads(prior_path.read_text())
    utility = json.loads(utility_path.read_text())
    summary = utility["observed"]["summary"]
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and utility["status"] == "LOCAL_EXACT_TOOL_UTILITY_POSITIVE"
        and utility["operationally_valid"] is True
        and summary["candidate_total_cost"] == 12465
        and summary["fixed_total_cost"] == 2072
        and summary["candidate_unique_nodes"] == 31
        and summary["fixed_unique_nodes"] == 51
        and summary["candidate_only_nodes"] == 9
        and summary["candidate_only_families"] == 8
        and summary["candidate_cheaper"] is False
        and summary["candidate_more_efficient"] is False
        and utility["decision"]["P6_advanced"] is False
    ):
        raise RuntimeError("iteration 5.36 inputs changed")
    progress = {
        **prior["progress"],
        "local_exact_tool_total_utility_executed": True,
        "local_exact_tool_candidate_total_cost": 12465,
        "local_exact_tool_fixed_total_cost": 2072,
        "local_exact_tool_candidate_unique_nodes": 31,
        "local_exact_tool_fixed_unique_nodes": 51,
        "local_exact_tool_candidate_only_nodes": 9,
        "local_exact_tool_candidate_only_families": 8,
        "local_exact_tool_candidate_cheaper": False,
        "local_exact_tool_candidate_more_efficient": False,
        "local_exact_tool_bounded_new_reach": True,
        "local_exact_tool_prospective_discovery": False,
    }
    result = {
        "version": "FOUNDRY_READINESS_ITERATION_5_36",
        "prior_sha256": sha(prior_path),
        "phase166_local_utility_sha256": sha(utility_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The fully charged local comparison closes the final local utility "
            "question without inflating it. Candidate construction, prediction, "
            "matching, dispatch, and compilation cost 12,465 abstract units versus "
            "2,072 for the unchanged supplied portfolio. Candidate benefit per cost "
            "is lower by about an order of magnitude and total coverage is 31 versus "
            "51 nodes. Nevertheless, the three executed exact tools reach nine nodes "
            "across eight families that the fixed portfolio does not. Two independent "
            "implementations agree exactly. This is bounded local newly reachable "
            "coverage on a previously observed cross-validation corpus, not cheaper "
            "execution, a runtime invention, fresh external discovery, P2/P6 progress, "
            "or prospective authorization."
        ),
        "remaining_blockers": prior["remaining_blockers"],
        "remediation": {
            "required": True,
            "next_action": (
                "retain the now trial-ready local forge unchanged and wait for the "
                "external sponsor trust root, corrected v2 bundle/provenance chain, "
                "and remaining V08/authorization freezes before any fresh trial"
            ),
            "forbidden_shortcuts": [
                "do not call bounded local candidate-only nodes a prospective real-world discovery",
                "do not omit the roughly sixfold candidate total-cost disadvantage",
                "do not call stock native duplicates runtime inventions",
                "do not access validation-v6/v7 or advance P2/P6 without the external gates",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_36.json").write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_36"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6 integrated=10/10"
        " cost=12465/2072 nodes=31/51 candidate_only=9 families=8"
        " prospective=false P6=false"
    )


if __name__ == "__main__":
    main()
