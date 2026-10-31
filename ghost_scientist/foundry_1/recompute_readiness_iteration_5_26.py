#!/usr/bin/env python3
"""Recompute readiness after A1 constructor reachability."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_25.json"
    reachability_path = (
        RESULTS / "phase145_a1_subgraph_constructor_reachability.json"
    )
    prior = json.loads(prior_path.read_text())
    reachability = json.loads(reachability_path.read_text())
    summary = reachability["observed"]["summary"]
    if not (
        prior["verdict"] == "FOUNDRY_V6_NOT_READY"
        and prior["authorization"]["required_arms_production_integrated"] == 7
        and reachability["status"]
        == "A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_POSITIVE"
        and all(reachability["checks"].values())
        and summary["semantic_candidates"] == 6
        and summary["semantic_candidate_families"]
        == ["dense_matrix_chain", "fold_conv_batch_norm"]
        and reachability["decision"]["A1_production_integrated"] is False
    ):
        raise RuntimeError("iteration 5.26 inputs changed")
    progress = {
        **prior["progress"],
        "A1_connected_subgraphs_enumerated": summary[
            "connected_subsets_2_to_6"
        ],
        "A1_histogram_candidates": summary["histogram_candidates"],
        "A1_semantic_constructor_candidates": summary["semantic_candidates"],
        "A1_semantic_candidate_artifacts": summary[
            "semantic_candidate_artifacts"
        ],
        "A1_semantic_candidate_families": summary[
            "semantic_candidate_families"
        ],
        "A1_pattern_first_lowering_justified": True,
        "A1_typed_lowering_implemented": False,
        "A1_constructor_executed": False,
        "A1_production_integrated": False,
    }
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_26",
        "prior_sha256": sha(prior_path),
        "A1_reachability_sha256": sha(reachability_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "A pre-frozen pattern-first reachability audit now justifies a "
            "bounded A1 lowering implementation. Two independent connected-"
            "subset enumerators agree on 7,093 mapped subgraphs across the "
            "complete 23-graph surface. Six exact-histogram candidates all "
            "pass their frozen dataflow-adjacency checks: three dense matrix "
            "chains and three conv-to-inference-batch-normalization folds "
            "across three artifacts. This is reachability, not constructor "
            "execution, full typed lowering, A1 conformance, or integration. "
            "The next implementation can target exactly two constructor "
            "families instead of expanding all 41 targets without evidence. "
            "The matrix remains 7/10 and validation-v6 stays sealed."
        ),
        "remaining_blockers": prior["remaining_blockers"],
        "remediation": {
            "required": True,
            "next_action": (
                "prefreeze and implement a pattern-first A1 typed lowering for "
                "dense_matrix_chain and fold_conv_batch_norm; independently "
                "check values, types, layouts, aliases, parameters, constants, "
                "reference fallback, and at least one executed nonreference plan"
            ),
            "forbidden_shortcuts": [
                "do not call adjacency reachability constructor execution",
                "do not treat the six subgraphs as six independent artifacts",
                "do not add opaque framework operations to Operator-v5 IR",
                "do not claim A1 integration before a complete contract batch",
                "do not open validation-v6 before the full arm and validity authorization passes",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_26.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_26"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=6/6"
        " integrated=7/10 A1_candidates=6 families=2"
        " A1_executed=false prospective=false"
    )


if __name__ == "__main__":
    main()
