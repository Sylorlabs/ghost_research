#!/usr/bin/env python3
"""Learn a small conditional whole-program grammar from development outcomes."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import pathlib
from collections import Counter, defaultdict
from collections.abc import Mapping, Sequence
from typing import Any

from ghost_operator_core_v5 import canonical_json, file_sha256, load_artifact
from ghost_operator_development_v5 import OUTCOME_STATUS, SCORE_VERSION, load_manifest
from ghost_operator_synthesis_v5 import enumerate_plans, structural_signature


GRAMMAR_VERSION = "GHOST_OPERATOR_GRAMMAR_V5"
FEATURE_NAMES = (
    "association_right_cheaper",
)


def load_outcomes(
    path: pathlib.Path, artifacts: Mapping[str, tuple[Any, bytes]]
) -> dict[str, dict[int, dict[str, Any]]]:
    result: dict[str, dict[int, dict[str, Any]]] = defaultdict(dict)
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        row = json.loads(line)
        if row.get("status") != OUTCOME_STATUS or row.get("score_version") != SCORE_VERSION:
            raise ValueError(f"outcome line {number} status/version mismatch")
        opaque_id = row["opaque_id"]
        if opaque_id not in artifacts:
            raise ValueError(f"outcome line {number} references an unknown artifact")
        _artifact, raw = artifacts[opaque_id]
        if hashlib.sha256(raw).hexdigest() != row["artifact_sha256"]:
            raise ValueError(f"outcome line {number} artifact digest mismatch")
        index = row["plan_index"]
        if index in result[opaque_id]:
            raise ValueError(f"outcome line {number} duplicates a plan")
        if (
            row["measurement_status"] != "MEASURED"
            or not row["numerically_valid"]
            or row["score"] is None
        ):
            raise ValueError(
                f"outcome line {number} is not eligible for grammar learning"
            )
        result[opaque_id][index] = row
    for opaque_id, (artifact, _raw) in artifacts.items():
        expected = len(enumerate_plans(artifact))
        if set(result[opaque_id]) != set(range(expected)):
            raise ValueError(f"artifact {opaque_id} outcomes are incomplete")
    return result


def leaf_choice(
    ids: Sequence[str],
    outcomes: Mapping[str, Mapping[int, Mapping[str, Any]]],
) -> tuple[int, float]:
    plan_count = len(outcomes[ids[0]])
    choices = []
    for index in range(plan_count):
        log_cost = sum(math.log(float(outcomes[item][index]["score"])) for item in ids)
        choices.append((log_cost, index))
    cost, index = min(choices)
    return index, cost


def build_tree(
    ids: Sequence[str],
    artifacts: Mapping[str, tuple[Any, bytes]],
    outcomes: Mapping[str, Mapping[int, Mapping[str, Any]]],
    *,
    depth: int,
    max_depth: int,
    min_leaf: int,
) -> tuple[dict[str, Any], float]:
    plan_index, leaf_cost = leaf_choice(ids, outcomes)
    leaf = {"kind": "leaf", "plan_index": plan_index}
    if depth >= max_depth or len(ids) < 2 * min_leaf:
        return leaf, leaf_cost
    best = None
    for feature_rank, feature in enumerate(FEATURE_NAMES):
        values = sorted({artifacts[item][0].public_features()[feature] for item in ids})
        for left_value, right_value in zip(values, values[1:]):
            midpoint = (left_value + right_value) // 2
            left = [
                item
                for item in ids
                if artifacts[item][0].public_features()[feature] <= midpoint
            ]
            right = [item for item in ids if item not in set(left)]
            if len(left) < min_leaf or len(right) < min_leaf:
                continue
            left_plan, left_cost = leaf_choice(left, outcomes)
            right_plan, right_cost = leaf_choice(right, outcomes)
            # Any unobserved integer gap fails closed to the reference plan.
            # This keeps a learned boundary from extrapolating a rewrite merely
            # because an arithmetic midpoint fell on the rewrite side.
            if left_plan == 0 and right_plan != 0:
                threshold = right_value - 1
            elif left_plan != 0 and right_plan == 0:
                threshold = left_value
            else:
                threshold = midpoint
            candidate = (
                left_cost + right_cost,
                feature_rank,
                threshold,
                feature,
                left,
                right,
            )
            if best is None or candidate[:3] < best[:3]:
                best = candidate
    if best is None or best[0] >= leaf_cost - 1.0e-12:
        return leaf, leaf_cost
    _estimated, _feature_rank, threshold, feature, left_ids, right_ids = best
    left_tree, left_cost = build_tree(
        left_ids,
        artifacts,
        outcomes,
        depth=depth + 1,
        max_depth=max_depth,
        min_leaf=min_leaf,
    )
    right_tree, right_cost = build_tree(
        right_ids,
        artifacts,
        outcomes,
        depth=depth + 1,
        max_depth=max_depth,
        min_leaf=min_leaf,
    )
    return (
        {
            "kind": "branch",
            "feature": feature,
            "threshold": threshold,
            "left": left_tree,
            "right": right_tree,
        },
        left_cost + right_cost,
    )


def tree_predict(tree: Mapping[str, Any], features: Mapping[str, int]) -> int:
    while tree["kind"] == "branch":
        tree = tree["left"] if features[tree["feature"]] <= tree["threshold"] else tree["right"]
    return int(tree["plan_index"])


def learn(
    manifest: pathlib.Path,
    outcomes_path: pathlib.Path,
    grammar_path: pathlib.Path,
    summary_path: pathlib.Path,
    *,
    max_depth: int,
    min_leaf: int,
    validation_manifest: pathlib.Path | None,
    validation_outcomes_path: pathlib.Path | None,
) -> None:
    artifact_paths = load_manifest(manifest, "DEVELOPMENT")
    artifacts: dict[str, tuple[Any, bytes]] = {}
    for path in artifact_paths:
        artifact, raw = load_artifact(path)
        artifacts[artifact.opaque_id] = (artifact, raw)
    outcomes = load_outcomes(outcomes_path, artifacts)
    source_manifests = [manifest]
    source_outcomes = [outcomes_path]
    if (validation_manifest is None) != (validation_outcomes_path is None):
        raise ValueError("validation manifest and outcomes must be supplied together")
    if validation_manifest is not None and validation_outcomes_path is not None:
        validation_artifacts: dict[str, tuple[Any, bytes]] = {}
        for path in load_manifest(validation_manifest, "VALIDATION"):
            artifact, raw = load_artifact(path)
            if artifact.opaque_id in artifacts:
                raise ValueError("development and validation ids overlap")
            validation_artifacts[artifact.opaque_id] = (artifact, raw)
        validation_outcomes = load_outcomes(
            validation_outcomes_path, validation_artifacts
        )
        artifacts.update(validation_artifacts)
        outcomes.update(validation_outcomes)
        source_manifests.append(validation_manifest)
        source_outcomes.append(validation_outcomes_path)
    groups: dict[str, list[str]] = defaultdict(list)
    for opaque_id, (artifact, _raw) in artifacts.items():
        signature_sha = hashlib.sha256(structural_signature(artifact).encode()).hexdigest()
        groups[signature_sha].append(opaque_id)

    rules: dict[str, object] = {}
    receipts: list[dict[str, object]] = []
    exact = 0
    selected_score = 0.0
    oracle_score = 0.0
    reference_score = 0.0
    negative_rewrites: list[dict[str, object]] = []
    for signature, ids in sorted(groups.items()):
        plan_counts = {len(outcomes[item]) for item in ids}
        if len(plan_counts) != 1:
            raise ValueError("one structural signature has inconsistent plan counts")
        tree, training_log_cost = build_tree(
            sorted(ids),
            artifacts,
            outcomes,
            depth=0,
            max_depth=max_depth,
            min_leaf=min_leaf,
        )
        rules[signature] = tree
        for opaque_id in sorted(ids):
            artifact = artifacts[opaque_id][0]
            predicted = tree_predict(tree, artifact.public_features())
            oracle = min(outcomes[opaque_id], key=lambda index: outcomes[opaque_id][index]["score"])
            exact += predicted == oracle
            selected_score += math.log(float(outcomes[opaque_id][predicted]["score"]))
            oracle_score += math.log(float(outcomes[opaque_id][oracle]["score"]))
            reference_score += math.log(float(outcomes[opaque_id][0]["score"]))
            rewrite_rows = [
                outcomes[opaque_id][index]
                for index in outcomes[opaque_id]
                if index != 0
            ]
            if rewrite_rows and all(
                float(row["score"]) >= float(outcomes[opaque_id][0]["score"])
                for row in rewrite_rows
            ):
                negative_rewrites.append(
                    {
                        "opaque_id": opaque_id,
                        "reference_score": outcomes[opaque_id][0]["score"],
                        "rewrite_scores": {
                            str(row["plan_index"]): row["score"] for row in rewrite_rows
                        },
                    }
                )
            receipts.append(
                {
                    "opaque_id": opaque_id,
                    "signature_sha256": signature,
                    "features": artifact.public_features(),
                    "predicted_plan_index": predicted,
                    "oracle_plan_index": oracle,
                    "plan_count": len(outcomes[opaque_id]),
                }
            )
    count = len(artifacts)
    grammar = {
        "version": GRAMMAR_VERSION,
        "status": (
            "CALIBRATED_NOT_FROZEN"
            if validation_manifest is not None
            else "DEVELOPMENT_NOT_FROZEN"
        ),
        "score_version": SCORE_VERSION,
        "manifest_sha256": [file_sha256(path) for path in source_manifests],
        "outcomes_sha256": [file_sha256(path) for path in source_outcomes],
        "max_depth": max_depth,
        "min_leaf": min_leaf,
        "default_plan_index": 0,
        "rules": rules,
        "training_receipts": receipts,
    }
    grammar_path.parent.mkdir(parents=True, exist_ok=True)
    grammar_path.write_text(canonical_json(grammar) + "\n", encoding="utf-8")
    summary = {
        "status": "GHOST_OPERATOR_LEARNING_V5_PASS",
        "artifact_count": count,
        "structural_signature_count": len(groups),
        "candidate_exact_oracle_count": exact,
        "candidate_exact_oracle_rate": exact / count,
        "candidate_geometric_score": math.exp(selected_score / count),
        "oracle_geometric_score": math.exp(oracle_score / count),
        "reference_geometric_score": math.exp(reference_score / count),
        "negative_rewrite_artifacts": negative_rewrites,
        "negative_rewrite_count": len(negative_rewrites),
        "grammar_sha256": file_sha256(grammar_path),
        "outcomes_sha256": [file_sha256(path) for path in source_outcomes],
    }
    summary_path.write_text(canonical_json(summary) + "\n", encoding="utf-8")
    print(
        "GHOST_OPERATOR_LEARN_V5 PASS"
        f" artifacts={count} signatures={len(groups)}"
        f" exact_oracle={exact}_of_{count}"
        f" candidate_score={summary['candidate_geometric_score']:.6f}"
        f" oracle_score={summary['oracle_geometric_score']:.6f}"
        f" reference_score={summary['reference_geometric_score']:.6f}"
        f" negative_rewrites={len(negative_rewrites)}"
        f" grammar_sha256={summary['grammar_sha256']}"
    )


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest", type=pathlib.Path)
    parser.add_argument("outcomes", type=pathlib.Path)
    parser.add_argument("grammar", type=pathlib.Path)
    parser.add_argument("summary", type=pathlib.Path)
    parser.add_argument("--max-depth", type=int, default=2)
    parser.add_argument("--min-leaf", type=int, default=1)
    parser.add_argument("--validation-manifest", type=pathlib.Path)
    parser.add_argument("--validation-outcomes", type=pathlib.Path)
    args = parser.parse_args()
    learn(
        args.manifest,
        args.outcomes,
        args.grammar,
        args.summary,
        max_depth=args.max_depth,
        min_leaf=args.min_leaf,
        validation_manifest=args.validation_manifest,
        validation_outcomes_path=args.validation_outcomes,
    )


if __name__ == "__main__":
    main()
