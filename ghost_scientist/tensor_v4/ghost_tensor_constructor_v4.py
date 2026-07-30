#!/usr/bin/env python3
"""Development-only conditional tensor grammar constructor.

The constructor enumerates every exact set partition of each three-projection
cluster, measures each plan with CPU TorchInductor, and learns a small decision
tree that minimizes measured development latency.  It has no held-out input.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import pathlib
from collections.abc import Mapping, Sequence
from typing import Any

from ghost_tensor_core_v4 import (
    canonical_json,
    identity_partition,
    load_artifact,
    measure_plan,
    packed_partition,
    plan_key,
    plan_payload,
    set_partitions,
)


GRAMMAR_VERSION = "GHOST_TENSOR_GRAMMAR_V4"
FEATURE_NAMES = (
    "batch",
    "sequence",
    "tokens",
    "in_features",
    "total_out",
    "projection_count",
    "work",
    "has_bias",
    "heterogeneous_out",
)


def file_sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def load_manifest(path: pathlib.Path, required_phase: str) -> list[pathlib.Path]:
    lines = path.read_text(encoding="utf-8").splitlines()
    expected_header = (
        "opaque_id\tphase\tartifact_path\tartifact_sha256\tinput_shape\tprojection_outs"
    )
    if not lines or lines[0] != expected_header:
        raise ValueError("manifest header mismatch")
    result: list[pathlib.Path] = []
    seen: set[str] = set()
    for number, line in enumerate(lines[1:], 2):
        fields = line.split("\t")
        if len(fields) != 6:
            raise ValueError(f"manifest line {number} has wrong field count")
        opaque_id, phase, artifact_path_text, expected_sha, _shape, _outputs = fields
        if phase != required_phase or opaque_id in seen:
            raise ValueError(f"manifest line {number} phase/id violation")
        seen.add(opaque_id)
        artifact_path = pathlib.Path(artifact_path_text)
        if not artifact_path.is_absolute():
            # The extractor records workspace-relative paths for portable
            # manifests.  Accept those from the invocation working directory,
            # while retaining manifest-relative support for copied bundles.
            if artifact_path.exists():
                artifact_path = artifact_path.resolve()
            else:
                artifact_path = (path.parent / artifact_path).resolve()
        if file_sha(artifact_path) != expected_sha:
            raise ValueError(f"manifest line {number} artifact digest mismatch")
        result.append(artifact_path)
    if not result:
        raise ValueError("empty development manifest")
    return result


def measure_development(
    manifest_path: pathlib.Path,
    output_path: pathlib.Path,
    *,
    backend: str,
    repetitions: int,
    inner_iterations: int | None,
) -> None:
    artifact_paths = load_manifest(manifest_path, "DEVELOPMENT")
    rows: list[str] = []
    for artifact_index, artifact_path in enumerate(artifact_paths):
        artifact, raw = load_artifact(artifact_path)
        partitions = set_partitions(len(artifact.projections))
        for partition_index, groups in enumerate(partitions):
            import torch

            torch._dynamo.reset()
            metrics = measure_plan(
                artifact,
                groups,
                repetitions=repetitions,
                inner_iterations=inner_iterations,
                compile_backend=backend,
            )
            row = {
                "status": "GHOST_TENSOR_DEVELOPMENT_OUTCOME_V4",
                "opaque_id": artifact.opaque_id,
                "artifact_sha256": hashlib.sha256(raw).hexdigest(),
                "features": artifact.features(),
                "plan": plan_payload(groups, len(artifact.projections)),
                "plan_key": plan_key(groups, len(artifact.projections)),
                "partition_index": partition_index,
                "latency_us_median": metrics["latency_us_median"],
                "latency_us_mad": metrics["latency_us_mad"],
                "compile_ms": metrics["compile_ms"],
                "logical_gemm_kernels": metrics["logical_gemm_kernels"],
                "peak_rss_kb": metrics["peak_rss_kb"],
                "rss_delta_kb": metrics["rss_delta_kb"],
                "max_abs_error": metrics["max_abs_error"],
                "compiled_max_abs_error": metrics["compiled_max_abs_error"],
            }
            rows.append(canonical_json(row))
        print(
            "GHOST_TENSOR_DEVELOPMENT_PROGRESS_V4"
            f" artifact={artifact.opaque_id}"
            f" index={artifact_index + 1}_of_{len(artifact_paths)}"
            f" partitions={len(partitions)}"
        )
    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text("\n".join(rows) + "\n", encoding="utf-8")
    print(
        "GHOST_TENSOR_DEVELOPMENT_V4 PASS"
        f" artifacts={len(artifact_paths)} outcomes={len(rows)}"
        f" backend={backend} output_sha256={file_sha(output_path)}"
    )


def load_outcomes(path: pathlib.Path):
    artifacts: dict[str, dict[str, Any]] = {}
    for number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            row = json.loads(line)
        except json.JSONDecodeError as exc:
            raise ValueError(f"outcomes line {number} is invalid JSON") from exc
        if row.get("status") != "GHOST_TENSOR_DEVELOPMENT_OUTCOME_V4":
            raise ValueError(f"outcomes line {number} has wrong status")
        opaque_id = row["opaque_id"]
        entry = artifacts.setdefault(
            opaque_id,
            {
                "features": row["features"],
                "artifact_sha256": row["artifact_sha256"],
                "plans": {},
            },
        )
        if entry["features"] != row["features"]:
            raise ValueError("feature drift within artifact outcomes")
        key = row["plan_key"]
        if key in entry["plans"]:
            raise ValueError("duplicate plan outcome")
        entry["plans"][key] = {
            "plan": row["plan"],
            "latency": float(row["latency_us_median"]),
        }
    if not artifacts:
        raise ValueError("empty development outcomes")
    plan_sets = {tuple(sorted(entry["plans"])) for entry in artifacts.values()}
    if len(plan_sets) != 1:
        raise ValueError("development artifacts do not share a complete plan grammar")
    return artifacts


def leaf_choice(
    ids: Sequence[str],
    artifacts: Mapping[str, dict[str, Any]],
) -> tuple[str, float]:
    plan_keys = sorted(artifacts[ids[0]]["plans"])
    scored = []
    for key in plan_keys:
        total = sum(artifacts[opaque_id]["plans"][key]["latency"] for opaque_id in ids)
        scored.append((total, key))
    total, key = min(scored)
    return key, total


def build_tree(
    ids: Sequence[str],
    artifacts: Mapping[str, dict[str, Any]],
    *,
    depth: int,
    max_depth: int,
    min_leaf: int,
) -> tuple[dict[str, Any], float]:
    leaf_key, leaf_cost = leaf_choice(ids, artifacts)
    leaf = {
        "kind": "leaf",
        "plan": artifacts[ids[0]]["plans"][leaf_key]["plan"],
    }
    if depth >= max_depth or len(ids) < min_leaf * 2:
        return leaf, leaf_cost
    best: tuple[float, str, int, list[str], list[str]] | None = None
    for feature in FEATURE_NAMES:
        values = sorted({int(artifacts[opaque_id]["features"][feature]) for opaque_id in ids})
        thresholds = [
            (left + right) // 2 for left, right in zip(values, values[1:])
        ]
        for threshold in thresholds:
            left_ids = [
                opaque_id
                for opaque_id in ids
                if int(artifacts[opaque_id]["features"][feature]) <= threshold
            ]
            right_ids = [opaque_id for opaque_id in ids if opaque_id not in set(left_ids)]
            if len(left_ids) < min_leaf or len(right_ids) < min_leaf:
                continue
            _left_key, left_cost = leaf_choice(left_ids, artifacts)
            _right_key, right_cost = leaf_choice(right_ids, artifacts)
            cost = left_cost + right_cost
            candidate = (cost, feature, threshold, left_ids, right_ids)
            if best is None or candidate[:3] < best[:3]:
                best = candidate
    if best is None or best[0] >= leaf_cost:
        return leaf, leaf_cost
    _cost, feature, threshold, left_ids, right_ids = best
    left_tree, left_cost = build_tree(
        left_ids,
        artifacts,
        depth=depth + 1,
        max_depth=max_depth,
        min_leaf=min_leaf,
    )
    right_tree, right_cost = build_tree(
        right_ids,
        artifacts,
        depth=depth + 1,
        max_depth=max_depth,
        min_leaf=min_leaf,
    )
    return (
        {
            "kind": "split",
            "feature": feature,
            "threshold": threshold,
            "left": left_tree,
            "right": right_tree,
        },
        left_cost + right_cost,
    )


def evaluate_tree(node: dict[str, Any], features: Mapping[str, int]) -> dict[str, Any]:
    current = node
    while current["kind"] == "split":
        current = (
            current["left"]
            if int(features[current["feature"]]) <= int(current["threshold"])
            else current["right"]
        )
    return current["plan"]


def learn_grammar(
    outcomes_path: pathlib.Path,
    grammar_path: pathlib.Path,
    ledger_path: pathlib.Path,
    *,
    max_depth: int,
    min_leaf: int,
) -> None:
    artifacts = load_outcomes(outcomes_path)
    ids = sorted(artifacts)
    projection_counts = {entry["features"]["projection_count"] for entry in artifacts.values()}
    if len(projection_counts) != 1:
        raise ValueError("mixed projection counts need separate grammars")
    projection_count = projection_counts.pop()
    tree, tree_cost = build_tree(
        ids,
        artifacts,
        depth=0,
        max_depth=max_depth,
        min_leaf=min_leaf,
    )
    identity_key = plan_key(identity_partition(projection_count), projection_count)
    packed_key = plan_key(packed_partition(projection_count), projection_count)
    identity_cost = sum(
        artifacts[opaque_id]["plans"][identity_key]["latency"] for opaque_id in ids
    )
    packed_cost = sum(
        artifacts[opaque_id]["plans"][packed_key]["latency"] for opaque_id in ids
    )
    exhaustive_cost = sum(
        min(plan["latency"] for plan in artifacts[opaque_id]["plans"].values())
        for opaque_id in ids
    )
    selected_cost = 0.0
    ledger_lines = [
        "opaque_id\tselected_plan_sha256\tselected_latency_us\tidentity_latency_us"
        "\tpack_all_latency_us\texhaustive_latency_us\tregret_us"
    ]
    for opaque_id in ids:
        selected_plan = evaluate_tree(tree, artifacts[opaque_id]["features"])
        selected_key = canonical_json(selected_plan)
        selected_latency = artifacts[opaque_id]["plans"][selected_key]["latency"]
        best_latency = min(
            plan["latency"] for plan in artifacts[opaque_id]["plans"].values()
        )
        selected_cost += selected_latency
        ledger_lines.append(
            f"{opaque_id}\t{hashlib.sha256(selected_key.encode()).hexdigest()}"
            f"\t{selected_latency:.9f}"
            f"\t{artifacts[opaque_id]['plans'][identity_key]['latency']:.9f}"
            f"\t{artifacts[opaque_id]['plans'][packed_key]['latency']:.9f}"
            f"\t{best_latency:.9f}\t{selected_latency - best_latency:.9f}"
        )
    receipt = {
        "outcomes_sha256": file_sha(outcomes_path),
        "artifact_count": len(ids),
        "outcome_count": sum(len(entry["plans"]) for entry in artifacts.values()),
        "max_depth": max_depth,
        "min_leaf": min_leaf,
        "selected_latency_sum_us": selected_cost,
        "tree_recomputed_cost_us": tree_cost,
        "identity_latency_sum_us": identity_cost,
        "pack_all_latency_sum_us": packed_cost,
        "exhaustive_latency_sum_us": exhaustive_cost,
    }
    grammar = {
        "version": GRAMMAR_VERSION,
        "projection_count": projection_count,
        "feature_names": list(FEATURE_NAMES),
        "tree": tree,
        "development_receipt": receipt,
    }
    grammar_path.parent.mkdir(parents=True, exist_ok=True)
    ledger_path.parent.mkdir(parents=True, exist_ok=True)
    grammar_path.write_text(canonical_json(grammar) + "\n", encoding="utf-8")
    ledger_path.write_text("\n".join(ledger_lines) + "\n", encoding="utf-8")
    print(
        "GHOST_TENSOR_GRAMMAR_V4 PASS"
        f" artifacts={len(ids)} selected_sum_us={selected_cost:.6f}"
        f" identity_sum_us={identity_cost:.6f}"
        f" pack_all_sum_us={packed_cost:.6f}"
        f" exhaustive_sum_us={exhaustive_cost:.6f}"
        f" grammar_sha256={file_sha(grammar_path)}"
    )


def selftest() -> None:
    plan_identity = {
        "version": "GHOST_TENSOR_PLAN_V4",
        "groups": [[0], [1], [2]],
    }
    plan_packed = {
        "version": "GHOST_TENSOR_PLAN_V4",
        "groups": [[0, 1, 2]],
    }
    identity_key = canonical_json(plan_identity)
    packed_key = canonical_json(plan_packed)
    artifacts = {}
    for index, work in enumerate((16, 32, 64, 1024, 2048, 4096)):
        artifacts[f"a{index}"] = {
            "features": {
                name: (
                    work
                    if name == "work"
                    else 3
                    if name == "projection_count"
                    else 0
                )
                for name in FEATURE_NAMES
            },
            "plans": {
                identity_key: {
                    "plan": plan_identity,
                    "latency": 1.0 if work < 100 else 3.0,
                },
                packed_key: {
                    "plan": plan_packed,
                    "latency": 2.0 if work < 100 else 1.0,
                },
            },
        }
    tree, cost = build_tree(
        sorted(artifacts),
        artifacts,
        depth=0,
        max_depth=2,
        min_leaf=2,
    )
    if tree["kind"] != "split" or tree["feature"] != "work" or cost != 6.0:
        raise AssertionError("conditional outcome learning failed")
    print(
        "GHOST_TENSOR_CONSTRUCTOR_V4_SELFTEST PASS"
        " conditional_split=true outcome_selected=true"
    )


def main(argv: Sequence[str] | None = None) -> None:
    parser = argparse.ArgumentParser()
    subparsers = parser.add_subparsers(dest="command", required=True)
    measure = subparsers.add_parser("measure-development")
    measure.add_argument("manifest")
    measure.add_argument("output")
    measure.add_argument("--backend", choices=("eager", "inductor"), default="inductor")
    measure.add_argument("--repetitions", type=int, default=7)
    measure.add_argument("--inner-iterations", type=int)
    learn = subparsers.add_parser("learn")
    learn.add_argument("outcomes")
    learn.add_argument("grammar")
    learn.add_argument("ledger")
    learn.add_argument("--max-depth", type=int, default=2)
    learn.add_argument("--min-leaf", type=int, default=2)
    subparsers.add_parser("selftest")
    args = parser.parse_args(argv)
    if args.command == "selftest":
        selftest()
    elif args.command == "measure-development":
        measure_development(
            pathlib.Path(args.manifest),
            pathlib.Path(args.output),
            backend=args.backend,
            repetitions=args.repetitions,
            inner_iterations=args.inner_iterations,
        )
    else:
        learn_grammar(
            pathlib.Path(args.outcomes),
            pathlib.Path(args.grammar),
            pathlib.Path(args.ledger),
            max_depth=args.max_depth,
            min_leaf=args.min_leaf,
        )


if __name__ == "__main__":
    main()
