#!/usr/bin/env python3
"""Recompute readiness after correcting A1 operand direction."""

from __future__ import annotations

import hashlib
import json
import pathlib


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    prior_path = RESULTS / "readiness_iteration_5_26.json"
    initial_path = RESULTS / "phase145_a1_subgraph_constructor_reachability.json"
    corrected_path = (
        RESULTS / "phase145_a1_subgraph_constructor_reachability_corrected.json"
    )
    amendment_path = (
        HERE
        / "arm_adapter_fixtures/A1_SUBGRAPH_REACHABILITY_DIRECTION_AMENDMENT_V1.json"
    )
    prior = json.loads(prior_path.read_text())
    initial = json.loads(initial_path.read_text())
    corrected = json.loads(corrected_path.read_text())
    summary = corrected["observed"]["summary"]
    if not (
        prior["progress"]["A1_semantic_constructor_candidates"] == 6
        and initial["observed"]["summary"]["semantic_candidates"] == 6
        and corrected["status"]
        == "A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_POSITIVE"
        and corrected["pristine_preregistration"] is False
        and all(corrected["checks"].values())
        and summary["histogram_candidates"] == 6
        and summary["direction_rejected_dense_candidates"] == 3
        and summary["semantic_candidates"] == 3
        and summary["semantic_candidate_families"]
        == ["fold_conv_batch_norm"]
        and corrected["decision"]["A1_production_integrated"] is False
    ):
        raise RuntimeError("iteration 5.27 inputs changed")
    progress = {
        **prior["progress"],
        "A1_initial_semantic_candidates_reported": 6,
        "A1_initial_dense_false_positives_preserved": 3,
        "A1_direction_rejected_dense_candidates": 3,
        "A1_semantic_constructor_candidates": 3,
        "A1_semantic_candidate_artifacts": 1,
        "A1_semantic_candidate_families": ["fold_conv_batch_norm"],
        "A1_pattern_first_lowering_justified": True,
        "A1_direction_amendment_pristine_preregistration": False,
        "A1_typed_lowering_implemented": False,
        "A1_constructor_executed": False,
        "A1_production_integrated": False,
    }
    payload = {
        "version": "FOUNDRY_READINESS_ITERATION_5_27",
        "prior_sha256": sha(prior_path),
        "A1_initial_reachability_sha256": sha(initial_path),
        "A1_corrected_reachability_sha256": sha(corrected_path),
        "A1_direction_amendment_sha256": sha(amendment_path),
        "prerequisites": prior["prerequisites"],
        "progress": progress,
        "authorization": prior["authorization"],
        "verdict": "FOUNDRY_V6_NOT_READY",
        "interpretation": (
            "The initial A1 reachability result contained three dense-chain "
            "false positives because it accepted the inner matmul in either "
            "operand position. Direct graph inspection showed every dense "
            "candidate was Adj @ (X @ W), while frozen v5.1 reassociation "
            "requires (X @ B) @ C. The initial result is preserved. A disclosed "
            "post-diagnostic amendment froze the exact argument direction before "
            "the corrected run. Both enumerators still agree on 7,093 subsets "
            "and six histogram candidates; all three dense candidates now fail "
            "direction, while three conv-to-inference-batchnorm candidates "
            "remain valid. A1 implementation is therefore justified only for "
            "fold_conv_batch_norm. No constructor has executed and integration "
            "remains 7/10."
        ),
        "remaining_blockers": prior["remaining_blockers"],
        "remediation": {
            "required": True,
            "next_action": (
                "prefreeze and implement only the three reachable "
                "fold_conv_batch_norm A1 lowerings; independently verify exact "
                "parameter/constant transport, actual-value equivalence, v5.1 "
                "nonreference plan execution, fallback, and hostile direction probes"
            ),
            "forbidden_shortcuts": [
                "do not implement or count the three rejected right-nested dense chains",
                "do not hide or overwrite the initial six-candidate false positive",
                "do not call the direction amendment pristine preregistration",
                "do not call adjacency reachability constructor execution",
                "do not claim A1 integration before a complete contract batch",
                "do not open validation-v6 before the full arm and validity authorization passes",
            ],
        },
    }
    (RESULTS / "readiness_iteration_5_27.json").write_text(
        json.dumps(payload, sort_keys=True, separators=(",", ":")) + "\n"
    )
    print(
        "FOUNDRY_READINESS_ITERATION_5_27"
        " verdict=FOUNDRY_V6_NOT_READY prerequisites=6/6"
        " integrated=7/10 A1_valid=3 A1_dense_rejected=3"
        " A1_executed=false prospective=false"
    )


if __name__ == "__main__":
    main()
