#!/usr/bin/env python3
"""Execute the pre-frozen A1 connected-subgraph reachability audit."""

from __future__ import annotations

import collections
import hashlib
import json
import pathlib
import sys
from typing import Iterable

import torch
from torch.fx import Graph, Node

from independent_a1_subgraph_reachability import (
    enumerate_connected as independent_enumerate,
)
from phase63_pareto_motif_calibration import old_repository, workloads
from resource_meter_v2 import run_metered_tree


HERE = pathlib.Path(__file__).resolve().parent
PROTOCOL = (
    HERE
    / "arm_adapter_fixtures/A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_PROTOCOL_V1.json"
)
FREEZE = HERE / "results/a1_subgraph_constructor_reachability_v1_freeze.json"
AMENDMENT = (
    HERE
    / "arm_adapter_fixtures/A1_SUBGRAPH_REACHABILITY_DIRECTION_AMENDMENT_V1.json"
)
AMENDMENT_FREEZE = (
    HERE / "results/a1_subgraph_direction_amendment_v1_freeze.json"
)
A1_PROTOCOL = HERE / "arm_adapter_fixtures/A1_IR_COMPATIBILITY_PROTOCOL_V1.json"
WORKER_RESULT = HERE / "results/phase145_a1_subgraph_constructor_reachability_worker.json"
RESULT = (
    HERE
    / "results/phase145_a1_subgraph_constructor_reachability_corrected.json"
)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def sha(path: pathlib.Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def primary_enumerate(
    graph: Graph, mapping: dict[str, list[object]], maximum: int = 6
) -> dict[int, set[frozenset[str]]]:
    eligible = {
        node.name: node
        for node in graph.nodes
        if node.op == "call_function"
        and str(node.target) in mapping
        and mapping[str(node.target)][1] is not None
    }
    neighbors = {name: set() for name in eligible}
    for name, node in eligible.items():
        for source in node.all_input_nodes:
            if source.name in eligible:
                neighbors[name].add(source.name)
                neighbors[source.name].add(name)
    discovered: dict[int, set[frozenset[str]]] = {
        size: set() for size in range(1, maximum + 1)
    }

    def visit(group: frozenset[str]) -> None:
        size = len(group)
        if group in discovered[size]:
            return
        discovered[size].add(group)
        if size == maximum:
            return
        frontier = set()
        for name in group:
            frontier.update(neighbors[name])
        for candidate in frontier - set(group):
            visit(group | {candidate})

    for name in eligible:
        visit(frozenset({name}))
    return discovered


def ancestors_within(node: Node, selected: set[Node]) -> set[Node]:
    found = set()
    pending = [parent for parent in node.all_input_nodes if parent in selected]
    while pending:
        current = pending.pop()
        if current in found:
            continue
        found.add(current)
        pending.extend(
            parent
            for parent in current.all_input_nodes
            if parent in selected and parent not in found
        )
    return found


def semantic_match(
    family: str,
    nodes: list[Node],
    runtime_ops: dict[Node, str],
) -> bool:
    selected = set(nodes)
    by_op: dict[str, list[Node]] = collections.defaultdict(list)
    for node in nodes:
        by_op[runtime_ops[node]].append(node)
    ancestors = {
        node: ancestors_within(node, selected) for node in nodes
    }
    if family == "dense_matrix_chain":
        left, right = by_op["matmul"]
        return (
            len(right.args) >= 1
            and right.args[0] is left
        ) or (
            len(left.args) >= 1
            and left.args[0] is right
        )
    if family == "fold_conv_batch_norm":
        conv = by_op["conv2d"][0]
        batch = by_op["batch_norm_eval"][0]
        return conv in batch.all_input_nodes
    if family == "graph_reassociation":
        sparse = by_op["sparse_mm"][0]
        add = by_op["add"][0]
        products = by_op["matmul"]
        return (
            all(product in ancestors[add] for product in products)
            and sparse in ancestors[add]
            and any(sparse in ancestors[product] for product in products)
        )
    if family == "mamba_composition":
        linears = by_op["linear"]
        splits = by_op["split_get"]
        cat = by_op["cat"][0]
        return any(
            sum(linear in ancestors[split] for split in splits) >= 1
            and any(split in ancestors[other] for split in splits)
            and other in ancestors[cat]
            for linear in linears
            for other in linears
            if other is not linear
        )
    if family == "primitive_layer_norm":
        means = by_op["reduce_mean"]
        rsqrt = by_op["rsqrt"][0]
        return (
            any(left in ancestors[right] for left in means for right in means if left is not right)
            and any(mean in ancestors[rsqrt] for mean in means)
        )
    if family == "stencil_convolution":
        rolls = by_op["roll"]
        multiplications = by_op["mul"]
        return (
            all(any(roll in ancestors[mul] for mul in multiplications) for roll in rolls)
            and all(any(roll in ancestors[mul] for roll in rolls) for mul in multiplications)
        )
    raise ValueError(f"unknown constructor family: {family}")


def worker() -> None:
    protocol = json.loads(PROTOCOL.read_text())
    a1_protocol = json.loads(A1_PROTOCOL.read_text())
    mapping = a1_protocol["operator_mapping"]
    histograms = protocol["frozen_constructor_histograms"]
    instantiated, unsupported = workloads()
    graph_rows = []
    operator_counts: collections.Counter[str] = collections.Counter()
    histogram_candidates = []
    semantic_candidates = []
    direction_rejected_candidates = []
    total_subsets = 0
    for suite, workload in instantiated:
        family = workload["family"]
        artifact_id = f"{suite}:{family}"
        exported = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        )
        graph = exported.module().graph
        calls = [
            node for node in graph.nodes if node.op == "call_function"
        ]
        operator_counts.update(str(node.target) for node in calls)
        primary = primary_enumerate(graph, mapping)
        independent = independent_enumerate(graph, mapping)
        if primary != independent:
            raise RuntimeError(f"connected enumerators disagree: {artifact_id}")
        by_name = {node.name: node for node in graph.nodes}
        runtime_ops = {
            node: str(mapping[str(node.target)][1])
            for node in calls
            if str(node.target) in mapping
            and mapping[str(node.target)][1] is not None
        }
        artifact_histogram = []
        artifact_semantic = []
        for size in range(2, 7):
            total_subsets += len(primary[size])
            for names in sorted(primary[size], key=lambda row: tuple(sorted(row))):
                nodes = [by_name[name] for name in sorted(names)]
                histogram = dict(
                    sorted(
                        collections.Counter(runtime_ops[node] for node in nodes).items()
                    )
                )
                for constructor, expected in histograms.items():
                    if histogram != expected:
                        continue
                    record = {
                        "artifact_id": artifact_id,
                        "constructor": constructor,
                        "nodes": sorted(names),
                        "runtime_histogram": histogram,
                    }
                    histogram_candidates.append(record)
                    artifact_histogram.append(record)
                    if semantic_match(constructor, nodes, runtime_ops):
                        semantic_candidates.append(record)
                        artifact_semantic.append(record)
                    elif constructor == "dense_matrix_chain":
                        direction_rejected_candidates.append(record)
        graph_rows.append(
            {
                "artifact_id": artifact_id,
                "family": family,
                "repository": workload.get(
                    "repository", old_repository(suite, family)
                ),
                "graph_sha256": hashlib.sha256(str(graph).encode()).hexdigest(),
                "call_function_invocations": len(calls),
                "eligible_mapped_calls": len(runtime_ops),
                "connected_subsets_2_to_6": sum(
                    len(primary[size]) for size in range(2, 7)
                ),
                "histogram_candidates": len(artifact_histogram),
                "semantic_candidates": len(artifact_semantic),
            }
        )
    payload = {
        "version": "FOUNDRY_A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_WORKER_V1",
        "graphs": graph_rows,
        "summary": {
            "graphs": len(graph_rows),
            "unique_targets": len(operator_counts),
            "calls": sum(operator_counts.values()),
            "unsupported_or_failed": len(unsupported),
            "eligible_mapped_calls": sum(
                row["eligible_mapped_calls"] for row in graph_rows
            ),
            "connected_subsets_2_to_6": total_subsets,
            "histogram_candidates": len(histogram_candidates),
            "semantic_candidates": len(semantic_candidates),
            "semantic_candidate_families": sorted(
                {row["constructor"] for row in semantic_candidates}
            ),
            "semantic_candidate_artifacts": len(
                {row["artifact_id"] for row in semantic_candidates}
            ),
            "direction_rejected_dense_candidates": len(
                direction_rejected_candidates
            ),
        },
        "histogram_candidates": histogram_candidates,
        "semantic_candidates": semantic_candidates,
        "direction_rejected_candidates": direction_rejected_candidates,
        "unsupported_or_failed": unsupported,
        "validation_v6_accessed": False,
    }
    WORKER_RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE145_WORKER"
        f" subsets={total_subsets}"
        f" histogram={len(histogram_candidates)}"
        f" semantic={len(semantic_candidates)}"
        f" families={len(payload['summary']['semantic_candidate_families'])}"
    )


def main() -> None:
    if "--worker" in sys.argv:
        worker()
        return
    protocol = json.loads(PROTOCOL.read_text())
    freeze = json.loads(FREEZE.read_text())
    amendment = json.loads(AMENDMENT.read_text())
    amendment_freeze = json.loads(AMENDMENT_FREEZE.read_text())
    providers_exact = all(
        sha(HERE / row["path"]) == row["sha256"]
        for row in protocol["provider_records"]
    )
    freeze_exact = (
        freeze["protocol_sha256"] == sha(PROTOCOL)
        and freeze["provider_records"] == protocol["provider_records"]
        and freeze["constructor_histograms"]
        == protocol["frozen_constructor_histograms"]
        and freeze["frozen_before_runner_implementation_or_execution"] is True
    )
    amendment_exact = (
        amendment_freeze["amendment_sha256"] == sha(AMENDMENT)
        and amendment_freeze["provider_records"]
        == amendment["provider_records"]
        and amendment_freeze[
            "frozen_before_corrected_runner_implementation_or_execution"
        ]
        is True
        and amendment_freeze["pristine_preregistration"] is False
        and sha(
            HERE
            / amendment["preserved_initial_result"]["path"]
        )
        == amendment["preserved_initial_result"]["sha256"]
    )
    limits = {
        "wall_limit_seconds": 120,
        "cpu_limit_seconds": 100,
        "rss_limit_kib": 4_500_000,
    }
    receipt = run_metered_tree(
        [str(pathlib.Path(sys.executable).resolve()), str(__file__), "--worker"],
        cwd=HERE,
        environment={
            "PYTHONHASHSEED": "0",
            "PYTHONWARNINGS": "ignore",
            "OMP_NUM_THREADS": "1",
            "MKL_NUM_THREADS": "1",
        },
        **limits,
    )
    natural = (
        receipt["returncode"] == 0
        and receipt["termination"] == "natural"
        and receipt["process_group_reaped"] is True
        and "FOUNDRY_PHASE145_WORKER" in receipt["stdout_text"]
    )
    observed = (
        json.loads(WORKER_RESULT.read_text())
        if natural and WORKER_RESULT.exists()
        else {}
    )
    summary = observed.get("summary", {})
    positive = summary.get("semantic_candidates", 0) > 0
    checks = {
        "protocol_freeze_and_providers_exact": (
            providers_exact and freeze_exact and amendment_exact
        ),
        "metered_worker_terminated_naturally": natural,
        "process_tree_cpu_rss_wall_accounted": (
            natural
            and receipt["observed_process_count"] >= 1
            and receipt["peak_group_rss_kib"] > 0
            and receipt["rusage_user_cpu_ns"]
            + receipt["rusage_system_cpu_ns"]
            > 0
        ),
        "complete_surface_exact": (
            summary.get("graphs") == 23
            and summary.get("unique_targets") == 41
            and summary.get("calls") == 337
            and summary.get("unsupported_or_failed") == 1
        ),
        "two_enumerators_agreed_all_graphs": (
            len(observed.get("graphs", [])) == 23
        ),
        "all_histogram_candidates_reported": (
            len(observed.get("histogram_candidates", []))
            == summary.get("histogram_candidates")
        ),
        "all_semantic_candidates_reported": (
            len(observed.get("semantic_candidates", []))
            == summary.get("semantic_candidates")
        ),
        "direction_correction_exact": (
            summary.get("histogram_candidates") == 6
            and summary.get("direction_rejected_dense_candidates") == 3
            and summary.get("semantic_candidates") == 3
            and summary.get("semantic_candidate_families")
            == ["fold_conv_batch_norm"]
            and len(observed.get("direction_rejected_candidates", [])) == 3
        ),
        "validation_v6_unread": observed.get("validation_v6_accessed") is False,
    }
    operationally_valid = all(checks.values())
    payload = {
        "version": "FOUNDRY_A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_RESULT_V1",
        "status": (
            "A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_POSITIVE"
            if operationally_valid and positive
            else (
                "A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_ZERO"
                if operationally_valid
                else "A1_SUBGRAPH_CONSTRUCTOR_REACHABILITY_INVALID"
            )
        ),
        "protocol_sha256": sha(PROTOCOL),
        "freeze_sha256": sha(FREEZE),
        "direction_amendment_sha256": sha(AMENDMENT),
        "direction_amendment_freeze_sha256": sha(AMENDMENT_FREEZE),
        "pristine_preregistration": False,
        "runner_records": [
            {"path": pathlib.Path(__file__).name, "sha256": sha(pathlib.Path(__file__))},
            {
                "path": "independent_a1_subgraph_reachability.py",
                "sha256": sha(HERE / "independent_a1_subgraph_reachability.py"),
            },
        ],
        "limits": limits,
        "receipt": receipt,
        "checks": checks,
        "operationally_valid": operationally_valid,
        "observed": observed,
        "decision": {
            "full_lowering_justified": operationally_valid and positive,
            "next_route": (
                "prefreeze pattern-first typed lowering for observed semantic candidate families"
                if operationally_valid and positive
                else "redesign A1 before expanding runtime vocabulary"
            ),
            "A1_production_integrated": False,
            "production_integrated_arms": 7,
        },
        "claim_boundary": {
            "constructor_reachability_only": True,
            "post_diagnostic_direction_correction": True,
            "initial_false_positive_preserved": True,
            "typed_lowering_implemented": False,
            "constructor_executed": False,
            "A1_conformant": False,
            "validation_v6_accessed": False,
            "prospective_trial_authorized": False,
        },
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE145_A1_SUBGRAPH_REACHABILITY"
        f" status={payload['status']}"
        f" histogram={summary.get('histogram_candidates', 0)}"
        f" semantic={summary.get('semantic_candidates', 0)}"
        f" families={len(summary.get('semantic_candidate_families', []))}"
        " integrated=7/10 prospective=false"
    )
    if not operationally_valid:
        raise RuntimeError(
            "A1 reachability audit invalid: "
            + canonical({"failed": [key for key, value in checks.items() if not value]})
        )


if __name__ == "__main__":
    main()
