#!/usr/bin/env python3
"""Deterministically select a typed-tool portfolio from the frozen pool."""

from __future__ import annotations

import hashlib
import importlib
import itertools
import json
import pathlib
import sys
from typing import Any

import torch
from torch.fx import Node

from independent_diversity_tool_evaluator import (
    node_type,
    semantic_matches,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
POOL = RESULTS / "pareto_tool_pool.json"
LIBRARY = RESULTS / "forged_pareto_tools.json"
RESULT = RESULTS / "phase64_pareto_portfolio_optimizer.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"
FORBIDDEN_FRAGMENT = "external_validation_" + "v6"
opened_paths: list[str] = []


def audit(event: str, args: tuple[object, ...]) -> None:
    if event == "open" and args and isinstance(args[0], (str, bytes)):
        opened_paths.append(str(args[0]))


sys.addaudithook(audit)


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def old_repository(suite: str, family: str) -> str:
    if suite == "validation_v4":
        return {
            "healthcare_dense_graph_convolution": "sunlabuiuc/PyHealth",
            "robust_gaussian_graph_convolution": "DSE-MSU/DeepRobust",
        }.get(family, "pytorch/examples")
    return "pytorch/examples"


def workloads() -> list[tuple[str, dict[str, Any]]]:
    rows: list[tuple[str, dict[str, Any]]] = []
    for suite, module_name in (
        ("original_external", "phase15_external_application_trace"),
        ("validation_v1", "external_validation_runtime"),
        ("validation_v3", "external_validation_v3_runtime"),
        ("validation_v4", "external_validation_v4_runtime"),
    ):
        module = importlib.import_module(module_name)
        rows.extend((suite, item) for item in module.instantiate())
    v2 = importlib.import_module("external_validation_v2_2_runtime")
    for _, construct in v2.constructors():
        try:
            rows.append(("validation_v2", construct()))
        except Exception:
            continue
    v5 = importlib.import_module("external_validation_v5_runtime")
    rows.extend(("validation_v5_calibration", item) for item in v5.instantiate())
    return rows


def fixed_matches(
    graph: torch.fx.Graph, fixed: dict[str, Any]
) -> tuple[list[tuple[str, list[Node]]], int, int]:
    eligible = [
        node
        for node in graph.nodes
        if node.op == "call_function" and node_type(node) is not None
    ]
    eligible_set = set(eligible)
    rows: list[tuple[str, list[Node]]] = []
    edges = 0
    for tool in fixed["tools"]:
        expected_type = {
            "rank": tool["rank"],
            "dtype": tool["dtype"],
            "layout": tool["layout"],
        }

        def extend(path: list[Node]) -> None:
            nonlocal edges
            index = len(path) - 1
            if (
                str(path[-1].target) != tool["targets"][index]
                or node_type(path[-1]) != expected_type
            ):
                return
            if len(path) == len(tool["targets"]):
                rows.append((tool["name"], list(path)))
                return
            for user in sorted(path[-1].users, key=lambda item: item.name):
                if user in eligible_set and user not in path:
                    edges += 1
                    extend(path + [user])

        for node in eligible:
            extend([node])
    return rows, len(eligible) * len(fixed["tools"]), edges


def dominates(left: dict, right: dict) -> bool:
    benefits = (
        "unique_nodes",
        "families",
        "repositories",
        "semantic_domains",
    )
    no_worse = all(left[key] >= right[key] for key in benefits)
    no_worse = no_worse and left["total_cost"] <= right["total_cost"]
    strict = any(left[key] > right[key] for key in benefits)
    strict = strict or left["total_cost"] < right["total_cost"]
    return no_worse and strict


def run() -> None:
    pool_raw = POOL.read_bytes()
    pool = json.loads(pool_raw)
    fixed_raw = FIXED.read_bytes()
    fixed = json.loads(fixed_raw)
    if (
        pool["version"] != "FOUNDRY_PARETO_TOOL_POOL_V1"
        or pool["construction"]["validation_v6_accessed"] is not False
        or len(pool["tools"]) > 20
    ):
        raise RuntimeError("Pareto pool contract invalid")

    tool_metrics = {
        tool["tool_id"]: {
            "coverage": set(),
            "families": set(),
            "repositories": set(),
            "semantic_domains": set(),
            "visits": 0,
            "edges": 0,
            "definition": len(tool["nodes"]) + len(tool["inputs"]),
        }
        for tool in pool["tools"]
    }
    fixed_coverage = set()
    fixed_families = set()
    fixed_repositories = set()
    fixed_domains = set()
    fixed_visits = 0
    fixed_edges = 0
    graphs = []
    for suite, workload in workloads():
        family = workload["family"]
        repository = workload.get(
            "repository", old_repository(suite, family)
        )
        domain = workload.get("semantic_domain", family)
        exported = torch.export.export(
            workload["model"],
            workload["args"],
            workload["kwargs"],
            strict=True,
        )
        graph = exported.module().graph
        graph_id = f"{suite}:{family}"
        graphs.append(graph_id)
        for tool in pool["tools"]:
            matches, visits, edges = semantic_matches(tool, graph)
            metric = tool_metrics[tool["tool_id"]]
            metric["visits"] += visits
            metric["edges"] += edges
            for path, _ in matches:
                metric["coverage"].update(
                    f"{graph_id}:{node.name}" for node in path
                )
                metric["families"].add(family)
                metric["repositories"].add(repository)
                metric["semantic_domains"].add(domain)
        fixed_rows, visits, edges = fixed_matches(graph, fixed)
        fixed_visits += visits
        fixed_edges += edges
        for _, path in fixed_rows:
            fixed_coverage.update(
                f"{graph_id}:{node.name}" for node in path
            )
            fixed_families.add(family)
            fixed_repositories.add(repository)
            fixed_domains.add(domain)

    shared_construction_cost = sum(
        item["paths_enumerated"] for item in pool["calibration_graphs"]
    ) + int(
        json.loads(
            (RESULTS / "phase63_pareto_motif_calibration.json").read_text()
        )["exact_body_groups"]
    )
    tools = pool["tools"]
    portfolios = []
    for mask in range(1, 1 << len(tools)):
        selected = [
            tools[index]
            for index in range(len(tools))
            if mask & (1 << index)
        ]
        coverage = set()
        families = set()
        repositories = set()
        domains = set()
        definition = 0
        visits = 0
        edges = 0
        for tool in selected:
            metric = tool_metrics[tool["tool_id"]]
            coverage.update(metric["coverage"])
            families.update(metric["families"])
            repositories.update(metric["repositories"])
            domains.update(metric["semantic_domains"])
            definition += metric["definition"]
            visits += metric["visits"]
            edges += metric["edges"]
        portfolios.append(
            {
                "tool_ids": sorted(tool["tool_id"] for tool in selected),
                "tools": len(selected),
                "unique_nodes": len(coverage),
                "families": len(families),
                "repositories": len(repositories),
                "semantic_domains": len(domains),
                "definition_cost": definition,
                "graph_node_visits": visits,
                "edge_checks": edges,
                "shared_construction_cost": shared_construction_cost,
                "total_cost": (
                    shared_construction_cost + definition + visits + edges
                ),
            }
        )
    frontier = [
        row
        for row in portfolios
        if not any(
            dominates(other, row)
            for other in portfolios
            if other is not row
        )
    ]
    max_values = {
        key: max(row[key] for row in frontier)
        for key in (
            "unique_nodes",
            "families",
            "repositories",
            "semantic_domains",
        )
    }
    min_cost = min(row["total_cost"] for row in frontier)
    for row in frontier:
        normalized_benefits = [
            row[key] / max_values[key] if max_values[key] else 0.0
            for key in max_values
        ]
        normalized_cost = min_cost / row["total_cost"]
        row["utopia_score"] = (
            sum(normalized_benefits) + normalized_cost
        ) / 5.0
    frontier.sort(
        key=lambda row: (
            -row["utopia_score"],
            row["total_cost"],
            row["tool_ids"],
        )
    )
    selected_metrics = frontier[0]
    selected_ids = set(selected_metrics["tool_ids"])
    selected_tools = [
        tool for tool in tools if tool["tool_id"] in selected_ids
    ]

    def metrics_for(ids: set[str]) -> dict:
        return next(
            row
            for row in portfolios
            if set(row["tool_ids"]) == ids
        )

    novelty_ids = {
        tool["tool_id"]
        for tool in tools
        if not tool["training"]["fixed_target_sequence_duplicate"]
    }
    all_ids = {tool["tool_id"] for tool in tools}
    fixed_definition = sum(len(tool["targets"]) for tool in fixed["tools"])
    fixed_metrics = {
        "tools": len(fixed["tools"]),
        "unique_nodes": len(fixed_coverage),
        "families": len(fixed_families),
        "repositories": len(fixed_repositories),
        "semantic_domains": len(fixed_domains),
        "definition_cost": fixed_definition,
        "graph_node_visits": fixed_visits,
        "edge_checks": fixed_edges,
        "shared_construction_cost": 0,
        "total_cost": fixed_definition + fixed_visits + fixed_edges,
    }
    forbidden_opens = sorted(
        {path for path in opened_paths if FORBIDDEN_FRAGMENT in path}
    )
    if forbidden_opens:
        raise RuntimeError("validation-v6 path accessed by Pareto optimizer")
    library = {
        "version": "FOUNDRY_PARETO_TOOL_LIBRARY_V1",
        "construction": {
            "algorithm": "exhaustive_nonempty_subset_pareto_utopia",
            "llm_calls": 0,
            "supplied_tool_forms": 0,
            "candidate_subsets": len(portfolios),
            "frontier_portfolios": len(frontier),
            "benefit_dimensions": [
                "unique_nodes",
                "families",
                "repositories",
                "semantic_domains",
            ],
            "cost_dimensions": [
                "shared_construction_cost",
                "definition_cost",
                "graph_node_visits",
                "edge_checks",
            ],
            "utopia_weights": {
                "unique_nodes": 1,
                "families": 1,
                "repositories": 1,
                "semantic_domains": 1,
                "inverse_total_cost": 1,
            },
            "validation_v6_accessed": False,
        },
        "pool_sha256": hashlib.sha256(pool_raw).hexdigest(),
        "fixed_portfolio_sha256": hashlib.sha256(fixed_raw).hexdigest(),
        "selected_metrics": selected_metrics,
        "tools": selected_tools,
    }
    LIBRARY.write_text(canonical(library) + "\n")
    payload = {
        "version": "FOUNDRY_PARETO_PORTFOLIO_OPTIMIZER_V1",
        "status": "PARETO_PORTFOLIO_SELECTED",
        "classification": "CALIBRATION_ONLY_MACHINE_SELECTION",
        "graphs": len(graphs),
        "pool_tools": len(tools),
        "candidate_subsets": len(portfolios),
        "frontier_portfolios": len(frontier),
        "selected": selected_metrics,
        "ablations": {
            "novelty_only": metrics_for(novelty_ids),
            "all_motif": metrics_for(all_ids),
        },
        "fixed": fixed_metrics,
        "frontier": frontier,
        "library_sha256": hashlib.sha256(
            LIBRARY.read_bytes()
        ).hexdigest(),
        "access_audit": {
            "file_open_events": len(opened_paths),
            "forbidden_path_fragment": FORBIDDEN_FRAGMENT,
            "forbidden_open_count": 0,
        },
        "prospective_claim_allowed": False,
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE64_PARETO_PORTFOLIO_OPTIMIZER_PASS"
        f" pool={len(tools)}"
        f" subsets={len(portfolios)}"
        f" frontier={len(frontier)}"
        f" selected={selected_metrics['tools']}"
        f" coverage={selected_metrics['unique_nodes']}"
        f" cost={selected_metrics['total_cost']}"
        f" fixed={fixed_metrics['unique_nodes']}/{fixed_metrics['total_cost']}"
    )


if __name__ == "__main__":
    run()
