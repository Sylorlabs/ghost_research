#!/usr/bin/env python3
"""Independently parse, replay, and remeasure the Pareto portfolio."""

from __future__ import annotations

import hashlib
import importlib
import json
import pathlib
import sys
from typing import Any

import torch
from torch.fx import Node

from independent_pareto_tool_evaluator import (
    CapturingInterpreter,
    LIBRARY,
    canonical,
    execute_tool,
    hostile_tests,
    max_error,
    node_type,
    parse_library,
    semantic_matches,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
RESULT = RESULTS / "phase65_independent_pareto_conformance.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"
FORBIDDEN_FRAGMENT = "external_validation_" + "v6"
opened_paths: list[str] = []


def audit(event: str, args: tuple[object, ...]) -> None:
    if event == "open" and args and isinstance(args[0], (str, bytes)):
        opened_paths.append(str(args[0]))


sys.addaudithook(audit)


def old_repository(suite: str, family: str) -> str:
    if suite == "validation_v4":
        return {
            "healthcare_dense_graph_convolution": "sunlabuiuc/PyHealth",
            "robust_gaussian_graph_convolution": "DSE-MSU/DeepRobust",
        }.get(family, "pytorch/examples")
    return "pytorch/examples"


def workloads() -> list[tuple[str, dict[str, Any]]]:
    rows = []
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
    rows = []
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


def run() -> None:
    raw = LIBRARY.read_bytes()
    library = parse_library(raw)
    hostile = hostile_tests(raw)
    fixed_raw = FIXED.read_bytes()
    fixed = json.loads(fixed_raw)
    tool_receipts = {
        tool["tool_id"]: {
            "matches": 0,
            "families": set(),
            "repositories": set(),
            "semantic_domains": set(),
            "suites": set(),
            "max_abs_error": 0.0,
        }
        for tool in library["tools"]
    }
    candidate_coverage = set()
    candidate_families = set()
    candidate_repositories = set()
    candidate_domains = set()
    candidate_visits = 0
    candidate_edges = 0
    fixed_coverage = set()
    fixed_families = set()
    fixed_repositories = set()
    fixed_domains = set()
    fixed_visits = 0
    fixed_edges = 0
    rows = []
    graph_count = 0
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
        module = exported.module()
        interpreter = CapturingInterpreter(module)
        interpreter.run(*workload["args"], **workload["kwargs"])
        graph_id = f"{suite}:{family}"
        graph_count += 1
        for tool in library["tools"]:
            matches, visits, edges = semantic_matches(tool, module.graph)
            candidate_visits += visits
            candidate_edges += edges
            for path, bindings in matches:
                inputs = [
                    interpreter.values[bindings[index]]
                    for index in range(len(tool["inputs"]))
                ]
                replayed = execute_tool(tool, inputs)
                error = max_error(replayed, interpreter.values[path[-1]])
                if error > 1.0e-6:
                    raise RuntimeError(
                        f"Pareto replay mismatch {tool['tool_id']} "
                        f"{family} error={error}"
                    )
                candidate_coverage.update(
                    f"{graph_id}:{node.name}" for node in path
                )
                candidate_families.add(family)
                candidate_repositories.add(repository)
                candidate_domains.add(domain)
                receipt = tool_receipts[tool["tool_id"]]
                receipt["matches"] += 1
                receipt["families"].add(family)
                receipt["repositories"].add(repository)
                receipt["semantic_domains"].add(domain)
                receipt["suites"].add(suite)
                receipt["max_abs_error"] = max(
                    receipt["max_abs_error"], error
                )
                rows.append(
                    {
                        "graph_id": graph_id,
                        "tool_id": tool["tool_id"],
                        "nodes": [node.name for node in path],
                        "max_abs_error": error,
                    }
                )
        fixed_rows, visits, edges = fixed_matches(module.graph, fixed)
        fixed_visits += visits
        fixed_edges += edges
        for _, path in fixed_rows:
            fixed_coverage.update(
                f"{graph_id}:{node.name}" for node in path
            )
            fixed_families.add(family)
            fixed_repositories.add(repository)
            fixed_domains.add(domain)

    normalized = []
    declared = {tool["tool_id"]: tool for tool in library["tools"]}
    for tool_id, receipt in sorted(tool_receipts.items()):
        training = declared[tool_id]["training"]
        item = {
            "tool_id": tool_id,
            "matches": receipt["matches"],
            "families": sorted(receipt["families"]),
            "repositories": sorted(receipt["repositories"]),
            "semantic_domains": sorted(receipt["semantic_domains"]),
            "suites": sorted(receipt["suites"]),
            "max_abs_error": receipt["max_abs_error"],
        }
        item["training_exact"] = (
            item["matches"] == training["occurrence_count"]
            and item["families"] == training["families"]
            and item["repositories"] == training["repositories"]
            and item["semantic_domains"] == training["semantic_domains"]
            and item["suites"] == training["suites"]
        )
        normalized.append(item)
    selected = library["selected_metrics"]
    definition = sum(
        len(tool["nodes"]) + len(tool["inputs"])
        for tool in library["tools"]
    )
    observed = {
        "tools": len(library["tools"]),
        "unique_nodes": len(candidate_coverage),
        "families": len(candidate_families),
        "repositories": len(candidate_repositories),
        "semantic_domains": len(candidate_domains),
        "definition_cost": definition,
        "graph_node_visits": candidate_visits,
        "edge_checks": candidate_edges,
        "shared_construction_cost": selected["shared_construction_cost"],
        "total_cost": (
            selected["shared_construction_cost"]
            + definition
            + candidate_visits
            + candidate_edges
        ),
    }
    fixed_definition = sum(len(tool["targets"]) for tool in fixed["tools"])
    fixed_observed = {
        "tools": len(fixed["tools"]),
        "unique_nodes": len(fixed_coverage),
        "families": len(fixed_families),
        "repositories": len(fixed_repositories),
        "semantic_domains": len(fixed_domains),
        "definition_cost": fixed_definition,
        "graph_node_visits": fixed_visits,
        "edge_checks": fixed_edges,
        "total_cost": fixed_definition + fixed_visits + fixed_edges,
    }
    selected_exact = all(
        observed[key] == selected[key]
        for key in observed
        if key != "tools"
    ) and observed["tools"] == selected["tools"]
    forbidden_opens = sorted(
        {path for path in opened_paths if FORBIDDEN_FRAGMENT in path}
    )
    gates = {
        "strict_parser_accepts_library": True,
        "seven_hostile_mutations_rejected": len(hostile) == 7,
        "twenty_three_graphs_replayed": graph_count == 23,
        "all_tools_replayed": all(item["matches"] > 0 for item in normalized),
        "all_replays_exact": all(
            item["max_abs_error"] <= 1.0e-6 for item in normalized
        ),
        "training_receipts_exact": all(
            item["training_exact"] for item in normalized
        ),
        "selected_metrics_exact": selected_exact,
        "candidate_coverage_above_fixed": observed["unique_nodes"]
        > fixed_observed["unique_nodes"],
        "candidate_total_cost_below_fixed": observed["total_cost"]
        < fixed_observed["total_cost"],
        "validation_v6_not_accessed": not forbidden_opens,
    }
    status = (
        "PARETO_INDEPENDENT_CONFORMANCE_PASS"
        if all(gates.values())
        else "PARETO_INDEPENDENT_CONFORMANCE_FAIL"
    )
    payload = {
        "version": "FOUNDRY_INDEPENDENT_PARETO_CONFORMANCE_V1",
        "status": status,
        "classification": "CALIBRATION_ONLY_INDEPENDENT_CONFORMANCE",
        "library_sha256": hashlib.sha256(raw).hexdigest(),
        "fixed_sha256": hashlib.sha256(fixed_raw).hexdigest(),
        "graphs": graph_count,
        "successful_replays": len(rows),
        "hostile_rejections": hostile,
        "candidate": observed,
        "fixed": fixed_observed,
        "tool_receipts": normalized,
        "gates": gates,
        "rows": rows,
        "access_audit": {
            "file_open_events": len(opened_paths),
            "forbidden_path_fragment": FORBIDDEN_FRAGMENT,
            "forbidden_open_count": len(forbidden_opens),
        },
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE65_INDEPENDENT_PARETO_CONFORMANCE"
        f" status={status}"
        f" graphs={graph_count}"
        f" tools={len(library['tools'])}"
        f" replays={len(rows)}"
        f" coverage={observed['unique_nodes']}/{fixed_observed['unique_nodes']}"
        f" cost={observed['total_cost']}/{fixed_observed['total_cost']}"
    )


if __name__ == "__main__":
    run()
