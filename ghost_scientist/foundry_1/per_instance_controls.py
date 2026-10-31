#!/usr/bin/env python3
"""Calibration-only A3 and A9 control kernels with no retained library."""

from __future__ import annotations

import argparse
import hashlib
import json
from typing import Any

import torch
from torch.fx import Node

from independent_diversity_tool_evaluator import semantic_matches
from phase63_pareto_motif_calibration import (
    UnsupportedTerm,
    construct_body,
    digest,
    paths,
    workloads,
)


EMPTY_STATE_SHA256 = hashlib.sha256(b"{}").hexdigest()


class ControlReject(ValueError):
    pass


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def validate_mode(mode: str) -> str:
    if mode not in {"A3_NO_LIBRARY", "A9_PER_INSTANCE"}:
        raise ControlReject("unknown control mode")
    return mode


def occurrence_nodes(path: list[Node]) -> list[str]:
    return [node.name for node in path]


def group_local_paths(graph: torch.fx.Graph) -> tuple[list[dict], int]:
    groups: dict[str, dict[str, Any]] = {}
    enumerated = 0
    for path in paths(graph):
        enumerated += 1
        try:
            body = construct_body(path)
        except UnsupportedTerm:
            continue
        identity = digest(body)
        group = groups.setdefault(
            identity,
            {"tool_id": identity, "body": body, "occurrences": []},
        )
        group["occurrences"].append(occurrence_nodes(path))
    rows = []
    for identity, group in sorted(groups.items()):
        body = group["body"]
        occurrences = group["occurrences"]
        structural_units = len(body["nodes"]) + len(body["inputs"])
        raw_cost = structural_units * len(occurrences)
        tool_cost = structural_units + len(occurrences)
        rows.append(
            {
                "tool_id": identity,
                "body": body,
                "occurrences": occurrences,
                "occurrence_count": len(occurrences),
                "structural_units": structural_units,
                "description_length_gain": raw_cost - tool_cost,
            }
        )
    return rows, enumerated


def select_local(groups: list[dict], mode: str) -> list[dict]:
    validate_mode(mode)
    if mode == "A3_NO_LIBRARY":
        eligible = [
            row
            for row in groups
            if row["occurrence_count"] >= 2
            and row["description_length_gain"] > 0
        ]
        eligible.sort(
            key=lambda row: (
                -row["description_length_gain"],
                -row["occurrence_count"],
                row["structural_units"],
                row["tool_id"],
            )
        )
        return eligible

    eligible = list(groups)
    selected = []
    covered: set[str] = set()
    remaining = {row["tool_id"]: row for row in eligible}
    while remaining:
        ranked = []
        for row in remaining.values():
            nodes = {
                node
                for occurrence in row["occurrences"]
                for node in occurrence
            }
            marginal = len(nodes - covered)
            ranked.append(
                (
                    -(marginal / row["structural_units"]),
                    -marginal,
                    row["structural_units"],
                    row["tool_id"],
                    nodes,
                    row,
                )
            )
        ranked.sort(key=lambda item: item[:4])
        _, neg_marginal, _, identity, nodes, row = ranked[0]
        if -neg_marginal == 0:
            break
        selected.append(row)
        covered.update(nodes)
        del remaining[identity]
    return selected


def run_mode(mode: str) -> dict[str, Any]:
    mode = validate_mode(mode)
    instantiated, unsupported = workloads()
    graph_receipts = []
    total_paths = 0
    total_groups = 0
    total_tools = 0
    total_matches = 0
    total_visits = 0
    total_edges = 0
    total_unique_nodes = 0
    repositories = set()
    semantic_domains = set()
    tool_ids_across_graphs: dict[str, int] = {}
    export_failures = list(unsupported)
    for suite, workload in instantiated:
        family = workload["family"]
        repository = workload.get("repository", "pytorch/examples")
        domain = workload.get("semantic_domain", family)
        try:
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
        except Exception as exc:
            export_failures.append(
                {
                    "suite": suite,
                    "family": family,
                    "exception_type": type(exc).__name__,
                }
            )
            continue
        graph = exported.module().graph
        groups, enumerated = group_local_paths(graph)
        selected = select_local(groups, mode)
        covered: set[str] = set()
        matches = visits = edges = 0
        for row in selected:
            found, row_visits, row_edges = semantic_matches(
                row["body"], graph
            )
            visits += row_visits
            edges += row_edges
            matches += len(found)
            for path, _ in found:
                covered.update(node.name for node in path)
            tool_ids_across_graphs[row["tool_id"]] = (
                tool_ids_across_graphs.get(row["tool_id"], 0) + 1
            )
        total_paths += enumerated
        total_groups += len(groups)
        total_tools += len(selected)
        total_matches += matches
        total_visits += visits
        total_edges += edges
        total_unique_nodes += len(covered)
        if selected:
            repositories.add(repository)
            semantic_domains.add(domain)
        graph_receipts.append(
            {
                "graph_id": f"{suite}:{family}",
                "graph_sha256": hashlib.sha256(
                    str(graph).encode()
                ).hexdigest(),
                "repository": repository,
                "semantic_domain": domain,
                "state_before_sha256": EMPTY_STATE_SHA256,
                "state_after_disposal_sha256": EMPTY_STATE_SHA256,
                "paths_enumerated": enumerated,
                "exact_body_groups": len(groups),
                "local_tools_selected": len(selected),
                "local_tool_ids": sorted(row["tool_id"] for row in selected),
                "independent_matches": matches,
                "independent_node_visits": visits,
                "independent_edge_checks": edges,
                "unique_nodes_covered": len(covered),
            }
        )
    repeated_digests = sorted(
        identity
        for identity, count in tool_ids_across_graphs.items()
        if count >= 2
    )
    return {
        "version": "FOUNDRY_PER_INSTANCE_CONTROL_KERNEL_V1",
        "mode": mode,
        "classification": "TWENTY_THREE_GRAPH_CALIBRATION_ONLY",
        "graphs": len(graph_receipts),
        "graph_receipts": graph_receipts,
        "unsupported_or_failed": export_failures,
        "summary": {
            "paths_enumerated": total_paths,
            "exact_body_groups": total_groups,
            "search_construction_units": total_paths + total_groups,
            "local_tools_selected": total_tools,
            "independent_matches": total_matches,
            "independent_node_visits": total_visits,
            "independent_edge_checks": total_edges,
            "unique_nodes_covered": total_unique_nodes,
            "repositories_reached": len(repositories),
            "semantic_domains_reached": len(semantic_domains),
            "same_digest_rediscovered_across_graphs": len(repeated_digests),
        },
        "state_policy": {
            "library_retained_across_graphs": False,
            "candidate_state_reset_each_graph": True,
            "cross_graph_digest_counts_evaluator_only": True,
            "empty_state_sha256": EMPTY_STATE_SHA256,
        },
        "budget_contract": {
            "search_units_definition": "typed paths plus exact body groups",
            "search_units": total_paths + total_groups,
            "application_units": total_visits + total_edges,
            "same_search_enumerator_as_A2": True,
            "full_process_resources_deferred_to_meter": True,
        },
        "validation_v6_accessed": False,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode",
        required=True,
        choices=("A3_NO_LIBRARY", "A9_PER_INSTANCE"),
    )
    parser.add_argument("--summary", action="store_true")
    args = parser.parse_args()
    payload = run_mode(args.mode)
    if args.summary:
        summary = payload["summary"]
        print(
            "FOUNDRY_PER_INSTANCE_CONTROL"
            f" mode={payload['mode']}"
            f" graphs={payload['graphs']}"
            f" search={summary['search_construction_units']}"
            f" tools={summary['local_tools_selected']}"
            f" coverage={summary['unique_nodes_covered']}"
            " validation_v6_accessed=false"
        )
    else:
        print(canonical(payload))


if __name__ == "__main__":
    main()
