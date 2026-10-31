#!/usr/bin/env python3
"""Refit v5.1 grammar and controls from multiple preserved v5 phases."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
import sys
from collections import defaultdict
from typing import Any


V5 = pathlib.Path(__file__).resolve().parents[1] / "operator_v5"
sys.path.insert(0, str(V5))

from ghost_operator_core_v5 import canonical_json, file_sha256, load_artifact  # noqa: E402
from ghost_operator_development_v5 import load_manifest  # noqa: E402
from ghost_operator_learn_v5 import (  # noqa: E402
    build_tree,
    leaf_choice,
    load_outcomes,
    tree_predict,
)
from ghost_operator_synthesis_v5 import structural_signature  # noqa: E402


def refit(
    sources: list[tuple[pathlib.Path, pathlib.Path, str]],
    grammar_path: pathlib.Path,
    controls_path: pathlib.Path,
    summary_path: pathlib.Path,
) -> None:
    import ghost_operator_learn_v5 as learner

    # v5.1 permits exactly the algebraic predicate plus tensor scale.  The
    # former is preferred; input_elements can split only signatures where the
    # algebraic predicate is constant (notably explicit normalization).
    learner.FEATURE_NAMES = (
        "association_right_cheaper",
        "input_elements",
    )
    artifacts: dict[str, tuple[Any, bytes]] = {}
    outcomes: dict[str, dict[int, dict[str, Any]]] = {}
    source_receipts = []
    for manifest, outcome_path, phase in sources:
        local: dict[str, tuple[Any, bytes]] = {}
        for path in load_manifest(manifest, phase):
            artifact, raw = load_artifact(path)
            if artifact.opaque_id in artifacts:
                raise ValueError("source artifact ids overlap")
            local[artifact.opaque_id] = (artifact, raw)
        local_outcomes = load_outcomes(outcome_path, local)
        artifacts.update(local)
        outcomes.update(local_outcomes)
        source_receipts.append(
            {
                "phase": phase,
                "manifest_sha256": file_sha256(manifest),
                "outcomes_sha256": file_sha256(outcome_path),
                "artifact_count": len(local),
            }
        )

    groups: dict[str, list[str]] = defaultdict(list)
    for opaque_id, (artifact, _raw) in artifacts.items():
        signature = hashlib.sha256(structural_signature(artifact).encode()).hexdigest()
        groups[signature].append(opaque_id)

    rules = {}
    fixed_rules = {}
    training_receipts = []
    replay_examples = []
    exact = 0
    selected_log = oracle_log = fixed_log = 0.0
    for signature, ids in sorted(groups.items()):
        ids = sorted(ids)
        tree, _cost = build_tree(
            ids,
            artifacts,
            outcomes,
            depth=0,
            max_depth=1,
            min_leaf=2,
        )
        fixed_index, fixed_cost = leaf_choice(ids, outcomes)
        rules[signature] = tree
        fixed_rules[signature] = fixed_index
        for opaque_id in ids:
            artifact = artifacts[opaque_id][0]
            predicted = tree_predict(tree, artifact.public_features())
            oracle = min(
                outcomes[opaque_id],
                key=lambda index: outcomes[opaque_id][index]["score"],
            )
            exact += predicted == oracle
            selected_log += math.log(float(outcomes[opaque_id][predicted]["score"]))
            oracle_log += math.log(float(outcomes[opaque_id][oracle]["score"]))
            fixed_log += math.log(float(outcomes[opaque_id][fixed_index]["score"]))
            receipt = {
                "opaque_id": opaque_id,
                "structural_signature_sha256": signature,
                "features": artifact.public_features(),
                "predicted_plan_index": predicted,
                "oracle_plan_index": oracle,
                "plan_count": len(outcomes[opaque_id]),
            }
            training_receipts.append(receipt)
            replay_examples.append(
                {
                    "opaque_id": opaque_id,
                    "structural_signature_sha256": signature,
                    "features": artifact.public_features(),
                    "oracle_plan_index": oracle,
                }
            )

    grammar = {
        "version": "GHOST_OPERATOR_GRAMMAR_V5",
        "status": "V5_1_CALIBRATED_NOT_FROZEN",
        "score_version": "GHOST_OPERATOR_MULTI_OBJECTIVE_SCORE_V5_DEV1",
        "allowed_branch_features": [
            "association_right_cheaper",
            "input_elements",
        ],
        "max_depth": 1,
        "min_leaf": 2,
        "default_plan_index": 0,
        "sources": source_receipts,
        "rules": rules,
        "training_receipts": training_receipts,
    }
    controls = {
        "version": "GHOST_OPERATOR_FIXED_PORTFOLIO_V5",
        "status": "V5_1_CALIBRATED_NOT_FROZEN",
        "conditional_features": False,
        "sources": source_receipts,
        "rules": fixed_rules,
        "replay_examples": replay_examples,
        "receipts": [
            {
                "structural_signature_sha256": signature,
                "artifact_count": len(ids),
                "fixed_plan_index": fixed_rules[signature],
            }
            for signature, ids in sorted(groups.items())
        ],
    }
    grammar_path.parent.mkdir(parents=True, exist_ok=True)
    grammar_path.write_text(canonical_json(grammar) + "\n", encoding="utf-8")
    controls_path.write_text(canonical_json(controls) + "\n", encoding="utf-8")
    count = len(artifacts)
    summary = {
        "status": "GHOST_OPERATOR_REFIT_V5_1_PASS",
        "artifact_count": count,
        "structural_signature_count": len(groups),
        "exact_oracle_count": exact,
        "exact_oracle_rate": exact / count,
        "candidate_geometric_score": math.exp(selected_log / count),
        "oracle_geometric_score": math.exp(oracle_log / count),
        "fixed_geometric_score": math.exp(fixed_log / count),
        "grammar_sha256": file_sha256(grammar_path),
        "controls_sha256": file_sha256(controls_path),
        "sources": source_receipts,
    }
    summary_path.write_text(canonical_json(summary) + "\n", encoding="utf-8")
    print(
        "GHOST_OPERATOR_REFIT_V5_1 PASS"
        f" artifacts={count} signatures={len(groups)}"
        f" exact_oracle={exact}_of_{count}"
        f" candidate_score={summary['candidate_geometric_score']:.6f}"
        f" fixed_score={summary['fixed_geometric_score']:.6f}"
        f" grammar_sha256={summary['grammar_sha256']}"
        f" controls_sha256={summary['controls_sha256']}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--source",
        nargs=3,
        action="append",
        metavar=("MANIFEST", "OUTCOMES", "PHASE"),
        required=True,
    )
    parser.add_argument("--grammar", type=pathlib.Path, required=True)
    parser.add_argument("--controls", type=pathlib.Path, required=True)
    parser.add_argument("--summary", type=pathlib.Path, required=True)
    args = parser.parse_args()
    sources = [
        (pathlib.Path(manifest), pathlib.Path(outcomes), phase)
        for manifest, outcomes, phase in args.source
    ]
    refit(sources, args.grammar, args.controls, args.summary)


if __name__ == "__main__":
    main()

