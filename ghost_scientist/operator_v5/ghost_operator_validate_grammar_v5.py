#!/usr/bin/env python3
"""Evaluate a development grammar and fixed controls on validation outcomes."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
import random
from collections import defaultdict
from typing import Any

from ghost_operator_core_v5 import canonical_json, file_sha256, load_artifact
from ghost_operator_development_v5 import load_manifest
from ghost_operator_egraph_v5 import extract as egraph_extract
from ghost_operator_egraph_v5 import semantic_program_key
from ghost_operator_learn_v5 import load_outcomes, tree_predict
from ghost_operator_synthesis_v5 import enumerate_plans, structural_signature


def geometric(values: list[float]) -> float:
    return math.exp(sum(math.log(item) for item in values) / len(values))


def replay_choice(
    signature: str,
    features: dict[str, int],
    fixed_portfolio: dict[str, Any],
) -> int:
    feature_names = (
        "input_elements",
        "parameter_elements",
        "reuse_calls",
        "input_last_dim",
        "output_last_dim",
        "association_right_cheaper",
    )
    candidates = [
        item
        for item in fixed_portfolio.get("replay_examples", [])
        if item["structural_signature_sha256"] == signature
    ]
    if not candidates:
        return 0
    scored = []
    for item in candidates:
        distance = 0.0
        for name in feature_names:
            left = int(features.get(name, 0))
            right = int(item["features"].get(name, 0))
            if name == "association_right_cheaper":
                distance += 4.0 * float(left != right)
            else:
                distance += abs(math.log1p(max(left, 0)) - math.log1p(max(right, 0)))
        scored.append((distance, item["opaque_id"], int(item["oracle_plan_index"])))
    return min(scored)[2]


def validate(
    manifest: pathlib.Path,
    outcomes_path: pathlib.Path,
    grammar_path: pathlib.Path,
    output_path: pathlib.Path,
    phase: str,
    fixed_portfolio_path: pathlib.Path | None,
) -> None:
    artifacts: dict[str, tuple[Any, bytes]] = {}
    for path in load_manifest(manifest, phase):
        artifact, raw = load_artifact(path)
        artifacts[artifact.opaque_id] = (artifact, raw)
    outcomes = load_outcomes(outcomes_path, artifacts)
    grammar = json.loads(grammar_path.read_text(encoding="utf-8"))
    fixed_portfolio = (
        json.loads(fixed_portfolio_path.read_text(encoding="utf-8"))
        if fixed_portfolio_path is not None
        else {"rules": {}}
    )

    methods: dict[str, list[float]] = defaultdict(list)
    exact = 0
    wins = ties = losses = 0
    misses: list[dict[str, object]] = []
    receipts: list[dict[str, object]] = []
    for opaque_id, (artifact, _raw) in sorted(artifacts.items()):
        rows = outcomes[opaque_id]
        signature = hashlib.sha256(structural_signature(artifact).encode()).hexdigest()
        tree = grammar["rules"].get(signature, {"kind": "leaf", "plan_index": 0})
        selected = tree_predict(tree, artifact.public_features())
        if selected not in rows:
            selected = 0
        oracle = min(rows, key=lambda index: rows[index]["score"])
        fixed_rewrite = 1 if 1 in rows else 0
        fixed_compute = min(
            rows,
            key=lambda index: (
                rows[index]["metrics"]["logical_matmul_ops"]
                + rows[index]["metrics"]["logical_conv_ops"]
                + rows[index]["metrics"]["logical_reduction_ops"]
                + rows[index]["metrics"]["logical_normalization_ops"],
                rows[index]["metrics"]["runtime_node_count"],
                index,
            ),
        )
        seed = int(hashlib.sha256(opaque_id.encode()).hexdigest()[:16], 16)
        random_index = random.Random(seed).choice(sorted(rows))
        fixed_signature = int(fixed_portfolio["rules"].get(signature, 0))
        if fixed_signature not in rows:
            fixed_signature = 0
        replay_memory = replay_choice(
            signature, artifact.public_features(), fixed_portfolio
        )
        if replay_memory not in rows:
            replay_memory = 0
        egraph_plan, egraph_receipt = egraph_extract(artifact)
        egraph_key = semantic_program_key(egraph_plan["program"])
        enumerated = enumerate_plans(artifact)
        egraph_matches = [
            index
            for index, plan in enumerate(enumerated)
            if semantic_program_key(plan["program"]) == egraph_key
        ]
        if not egraph_matches:
            raise ValueError(f"egraph plan is outside outcomes for {opaque_id}")
        equality_saturation = egraph_matches[0]
        choices = {
            "candidate": selected,
            "stock_reference": 0,
            "fixed_first_rewrite": fixed_rewrite,
            "fixed_compute": fixed_compute,
            "fixed_signature_portfolio": fixed_signature,
            "equality_saturation": equality_saturation,
            "replay_memory": replay_memory,
            "no_probe_fixed_portfolio": fixed_signature,
            "no_memory_egraph": equality_saturation,
            "random": random_index,
            "exhaustive_oracle": oracle,
            "autotuning_exhaustive": oracle,
        }
        for method, index in choices.items():
            methods[method].append(float(rows[index]["score"]))
        exact += selected == oracle
        candidate_score = float(rows[selected]["score"])
        reference_score = float(rows[0]["score"])
        tolerance = 1.0e-9
        if candidate_score < reference_score - tolerance:
            wins += 1
        elif candidate_score > reference_score + tolerance:
            losses += 1
        else:
            ties += 1
        if selected != oracle:
            misses.append(
                {
                    "opaque_id": opaque_id,
                    "features": artifact.public_features(),
                    "selected_plan_index": selected,
                    "oracle_plan_index": oracle,
                    "selected_score": candidate_score,
                    "oracle_score": rows[oracle]["score"],
                    "regret_ratio": candidate_score / float(rows[oracle]["score"]),
                }
            )
        receipts.append(
            {
                "opaque_id": opaque_id,
                "structural_signature_sha256": signature,
                "choices": choices,
                "scores": {
                    method: rows[index]["score"] for method, index in choices.items()
                },
                "equality_saturation_receipt": egraph_receipt,
            }
        )
    aggregates = {method: geometric(values) for method, values in methods.items()}
    count = len(artifacts)
    result = {
        "status": "GHOST_OPERATOR_VALIDATION_V5_PASS",
        "phase": phase,
        "artifact_count": count,
        "outcomes_sha256": file_sha256(outcomes_path),
        "grammar_sha256": file_sha256(grammar_path),
        "candidate_exact_oracle_count": exact,
        "candidate_exact_oracle_rate": exact / count,
        "candidate_wins_vs_reference": wins,
        "candidate_ties_vs_reference": ties,
        "candidate_losses_vs_reference": losses,
        "geometric_scores": aggregates,
        "candidate_regret_vs_oracle": aggregates["candidate"]
        / aggregates["exhaustive_oracle"],
        "candidate_improvement_vs_reference": 1.0
        - aggregates["candidate"] / aggregates["stock_reference"],
        "misses": misses,
        "receipts": receipts,
    }
    output_path.write_text(canonical_json(result) + "\n", encoding="utf-8")
    print(
        "GHOST_OPERATOR_VALIDATION_V5 PASS"
        f" phase={phase} artifacts={count} exact_oracle={exact}_of_{count}"
        f" wins_ties_losses={wins}_{ties}_{losses}"
        f" candidate_score={aggregates['candidate']:.6f}"
        f" reference_score={aggregates['stock_reference']:.6f}"
        f" fixed_rewrite_score={aggregates['fixed_first_rewrite']:.6f}"
        f" fixed_compute_score={aggregates['fixed_compute']:.6f}"
        f" fixed_signature_score={aggregates['fixed_signature_portfolio']:.6f}"
        f" egraph_score={aggregates['equality_saturation']:.6f}"
        f" replay_score={aggregates['replay_memory']:.6f}"
        f" oracle_score={aggregates['exhaustive_oracle']:.6f}"
        f" regret={result['candidate_regret_vs_oracle']:.6f}"
        f" output_sha256={file_sha256(output_path)}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument("outcomes", type=pathlib.Path)
    parser.add_argument("grammar", type=pathlib.Path)
    parser.add_argument("output", type=pathlib.Path)
    parser.add_argument(
        "--phase",
        choices=("VALIDATION", "CONFIRMATION", "PREFREEZE", "HELDOUT"),
        default="VALIDATION",
    )
    parser.add_argument("--fixed-portfolio", type=pathlib.Path)
    args = parser.parse_args()
    validate(
        args.manifest,
        args.outcomes,
        args.grammar,
        args.output,
        args.phase,
        args.fixed_portfolio,
    )


if __name__ == "__main__":
    main()
