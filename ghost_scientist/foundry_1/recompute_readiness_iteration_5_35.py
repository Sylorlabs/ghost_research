#!/usr/bin/env python3
"""Recompute readiness after predictive exact-tool construction and execution."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_34.json"
    p163_path = RESULTS / "phase163_local_operator_prediction.json"
    p164_path = RESULTS / "phase164_local_exact_body_prediction.json"
    p165_path = RESULTS / "phase165_local_exact_tool_execution.json"
    prior = json.loads(prior_path.read_text())
    p163 = json.loads(p163_path.read_text())
    p164 = json.loads(p164_path.read_text())
    p165 = json.loads(p165_path.read_text())
    s163 = p163["observed"]["summary"]
    s164 = p164["observed"]["summary"]
    s165 = p165["observed"]["summary"]
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and p163["status"] == "LOCAL_OPERATOR_PREDICTION_POSITIVE"
        and s163["candidate_exact_sequences"] == 18
        and s163["boundary_exact_sequences"] == s163["global_exact_sequences"] == 0
        and p164["status"] == "LOCAL_EXACT_BODY_PREDICTION_POSITIVE"
        and s164["candidate_exact_bodies"] == 17
        and s164["boundary_exact_bodies"] == s164["global_exact_bodies"] == 4
        and p165["status"] == "LOCAL_EXACT_TOOL_EXECUTION_VALID_STOCK_DUPLICATE"
        and p165["operationally_valid"] is True
        and s165["candidate_exact_rows"] == s165["stock_exact_rows"] == 17
        and s165["normalized_inductor_duplicates"] == 3
        and s165["runtime_inventions_admitted"] == 0
        and p165["decision"]["P6_advanced"] is False
    ):
        raise RuntimeError("iteration 5.35 inputs changed")
    progress = {
        **prior["progress"],
        "local_operator_prediction_executed": True,
        "local_operator_exact_sequences": 18,
        "local_operator_exact_families": 11,
        "local_operator_exact_folds": 5,
        "local_exact_body_prediction_executed": True,
        "local_exact_body_predictions": 17,
        "local_exact_body_families": 10,
        "local_exact_body_folds": 4,
        "local_exact_tool_real_value_replays": 17,
        "local_exact_tool_unique_bodies": 3,
        "local_exact_tool_native_duplicates": 3,
        "local_exact_tool_runtime_inventions": 0,
        "local_exact_tool_lower_total_cost_demonstrated": False,
    }
    result = {
        "version": "FOUNDRY_READINESS_ITERATION_5_35",
        "prior_sha256": sha(prior_path),
        "phase163_operator_prediction_sha256": sha(p163_path),
        "phase164_exact_body_prediction_sha256": sha(p164_path),
        "phase165_exact_tool_execution_sha256": sha(p165_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The local remediation crossed a real boundary: on a newly frozen "
            "five-fold split, training-only topology models predicted 18 complete "
            "operator sequences across eleven families and all five folds, then "
            "predicted 17 complete canonical bodies across ten families and four "
            "folds, beating both full-body controls 17 to 4. All seventeen bodies "
            "executed exactly on captured real heldout tensor values under two "
            "executors and disappeared under causal library removal. The three "
            "unique bodies compiled on both routes, but every normalized native "
            "artifact was a stock-ATen duplicate. This demonstrates bounded "
            "LLM-free concrete exact tool construction and reuse, not new operation "
            "semantics, a runtime invention, whole-graph replacement, lower total "
            "cost, P2/P6 progress, or prospective authorization."
        ),
        "remaining_blockers": prior["remaining_blockers"],
        "remediation": {
            "required": True,
            "next_action": (
                "freeze a total-cost and newly-reachable comparison for the three "
                "executed exact tools against the strong fixed portfolio; retain "
                "the external sponsor, v2 bundle, and provenance requirements unchanged"
            ),
            "forbidden_shortcuts": [
                "do not call stock-compiler duplicates runtime inventions",
                "do not call standalone real-value replay whole-graph replacement",
                "do not omit search, prediction, compilation, or dispatch costs",
                "do not advance P2/P6 or access validation-v6/v7 from local cross-validation",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_35.json").write_text(
        json.dumps(result, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_35"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=5/6 integrated=10/10"
        " operator_predictions=18 exact_bodies=17 replay=17/17"
        " native_duplicates=3 inventions=0 P6=false prospective=false"
    )


if __name__ == "__main__":
    main()
