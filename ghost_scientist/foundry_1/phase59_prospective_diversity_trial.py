#!/usr/bin/env python3
"""Frozen prospective comparison of diversity tools and strong fixed portfolio."""

from __future__ import annotations

import hashlib
import json
import math
import pathlib
from typing import Any

import torch
from torch.fx import Node

import external_validation_v5_runtime
from freeze_external_validation_v5 import verify as verify_intake
from independent_diversity_tool_evaluator import (
    CapturingInterpreter,
    LIBRARY,
    execute_tool,
    max_error,
    node_type,
    parse_library,
    semantic_matches,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"
RESULT = RESULTS / "phase59_prospective_diversity_trial.json"
CALIBRATION = RESULTS / "phase53_diversity_calibration_audit.json"
FORGE_RESULT = RESULTS / "phase55_diversity_tool_forge.json"


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


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
        targets = tool["targets"]
        expected_type = {
            "rank": tool["rank"],
            "dtype": tool["dtype"],
            "layout": tool["layout"],
        }

        def extend(path: list[Node]) -> None:
            nonlocal edges
            index = len(path) - 1
            if (
                str(path[-1].target) != targets[index]
                or node_type(path[-1]) != expected_type
            ):
                return
            if len(path) == len(targets):
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
    intake = verify_intake()
    candidate_raw = LIBRARY.read_bytes()
    candidate = parse_library(candidate_raw)
    fixed_raw = FIXED.read_bytes()
    fixed = json.loads(fixed_raw)
    calibration = json.loads(CALIBRATION.read_text())
    forge = json.loads(FORGE_RESULT.read_text())

    family_receipts = []
    candidate_rows = []
    candidate_tools = set()
    candidate_families = set()
    candidate_repositories = set()
    candidate_domains = set()
    fixed_families = set()
    candidate_visits = 0
    candidate_edges = 0
    fixed_visits = 0
    fixed_edges = 0
    candidate_unique_benefit = 0
    fixed_unique_benefit = 0
    candidate_only_families = set()
    graph_failures = []
    workloads = external_validation_v5_runtime.instantiate()
    for workload in workloads:
        family = workload["family"]
        repository = workload["repository"]
        domain = workload["semantic_domain"]
        try:
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
            module = exported.module()
            interpreter = CapturingInterpreter(module)
            interpreter.run(*workload["args"], **workload["kwargs"])
        except Exception as exc:
            graph_failures.append(
                {
                    "family": family,
                    "repository": repository,
                    "semantic_domain": domain,
                    "exception_type": type(exc).__name__,
                    "message_sha256": hashlib.sha256(
                        str(exc).encode()
                    ).hexdigest(),
                }
            )
            family_receipts.append(
                {
                    "family": family,
                    "repository": repository,
                    "semantic_domain": domain,
                    "exported": False,
                }
            )
            continue

        candidate_nodes: set[Node] = set()
        fixed_nodes: set[Node] = set()
        family_candidate_matches = 0
        for tool in candidate["tools"]:
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
                if not math.isfinite(error) or error > 1.0e-6:
                    raise RuntimeError(
                        f"prospective replay mismatch {tool['tool_id']} "
                        f"{family} error={error}"
                    )
                candidate_nodes.update(path)
                family_candidate_matches += 1
                candidate_tools.add(tool["tool_id"])
                candidate_families.add(family)
                candidate_repositories.add(repository)
                candidate_domains.add(domain)
                candidate_rows.append(
                    {
                        "family": family,
                        "repository": repository,
                        "semantic_domain": domain,
                        "tool_id": tool["tool_id"],
                        "nodes": [node.name for node in path],
                        "input_count": len(inputs),
                        "max_abs_error": error,
                    }
                )
        fixed_rows, visits, edges = fixed_matches(module.graph, fixed)
        fixed_visits += visits
        fixed_edges += edges
        for _, path in fixed_rows:
            fixed_nodes.update(path)
        if fixed_rows:
            fixed_families.add(family)
        if candidate_nodes and not fixed_nodes:
            candidate_only_families.add(family)
        candidate_unique_benefit += len(candidate_nodes)
        fixed_unique_benefit += len(fixed_nodes)
        family_receipts.append(
            {
                "family": family,
                "repository": repository,
                "semantic_domain": domain,
                "exported": True,
                "graph_sha256": hashlib.sha256(
                    str(module.graph).encode()
                ).hexdigest(),
                "call_function_nodes": sum(
                    node.op == "call_function"
                    for node in module.graph.nodes
                ),
                "candidate_matches": family_candidate_matches,
                "candidate_unique_nodes": len(candidate_nodes),
                "fixed_matches": len(fixed_rows),
                "fixed_unique_nodes": len(fixed_nodes),
                "candidate_only_nodes": len(candidate_nodes - fixed_nodes),
                "fixed_only_nodes": len(fixed_nodes - candidate_nodes),
            }
        )

    candidate_definition = sum(
        len(tool["nodes"]) + len(tool["inputs"])
        for tool in candidate["tools"]
    )
    fixed_definition = sum(len(tool["targets"]) for tool in fixed["tools"])
    calibration_search = (
        calibration["candidate_patterns_enumerated"]
        + forge["executable_body_groups"]
        + forge["calibration_families_exported"]
    )
    candidate_total_cost = (
        candidate_definition
        + calibration_search
        + candidate_visits
        + candidate_edges
    )
    fixed_total_cost = fixed_definition + fixed_visits + fixed_edges
    candidate_efficiency = (
        candidate_unique_benefit / candidate_total_cost
        if candidate_total_cost
        else 0.0
    )
    fixed_efficiency = (
        fixed_unique_benefit / fixed_total_cost if fixed_total_cost else 0.0
    )
    gates = {
        "intake_freeze_verified": intake["classification"]
        == "PROSPECTIVE_SOURCE_INTAKE_FROZEN_PRE_EXECUTION",
        "four_distinct_sources_constructed": len(workloads) == 4,
        "all_four_graphs_exported_and_executed": len(graph_failures) == 0
        and sum(item.get("exported", False) for item in family_receipts) == 4,
        "all_candidate_replays_exact": all(
            item["max_abs_error"] <= 1.0e-6 for item in candidate_rows
        ),
        "candidate_reuses_in_two_families": len(candidate_families) >= 2,
        "candidate_reuses_in_two_repositories": len(candidate_repositories) >= 2,
        "candidate_reuses_in_two_semantic_domains": len(candidate_domains) >= 2,
        "two_distinct_machine_tools_transfer": len(candidate_tools) >= 2,
        "candidate_unique_benefit_at_least_fixed": candidate_unique_benefit
        >= fixed_unique_benefit,
        "candidate_total_cost_below_fixed": candidate_total_cost
        < fixed_total_cost,
        "candidate_efficiency_above_fixed": candidate_efficiency
        > fixed_efficiency,
        "cheaper_or_newly_reachable_family": candidate_total_cost
        < fixed_total_cost
        or len(candidate_only_families) > 0,
    }
    status = (
        "DIVERSITY_PROSPECTIVE_TRANSFER_PASS"
        if all(gates.values())
        else "DIVERSITY_PROSPECTIVE_VALID_NEGATIVE"
    )
    payload = {
        "version": "FOUNDRY_PROSPECTIVE_DIVERSITY_TRIAL_V1",
        "status": status,
        "candidate_library_sha256": hashlib.sha256(
            candidate_raw
        ).hexdigest(),
        "fixed_portfolio_sha256": hashlib.sha256(fixed_raw).hexdigest(),
        "intake_freeze_records_sha256": intake["records_sha256"],
        "sources": len(workloads),
        "exported_graphs": sum(
            item.get("exported", False) for item in family_receipts
        ),
        "graph_failures": graph_failures,
        "candidate": {
            "tools": len(candidate["tools"]),
            "matched_tools": len(candidate_tools),
            "matched_families": len(candidate_families),
            "matched_repositories": len(candidate_repositories),
            "matched_semantic_domains": len(candidate_domains),
            "definition_cost": candidate_definition,
            "calibration_search_cost": calibration_search,
            "prospective_graph_node_visits": candidate_visits,
            "prospective_edge_checks": candidate_edges,
            "total_cost": candidate_total_cost,
            "unique_node_benefit": candidate_unique_benefit,
            "benefit_per_cost": candidate_efficiency,
        },
        "fixed": {
            "tools": len(fixed["tools"]),
            "matched_families": len(fixed_families),
            "definition_cost": fixed_definition,
            "prospective_graph_node_visits": fixed_visits,
            "prospective_edge_checks": fixed_edges,
            "total_cost": fixed_total_cost,
            "unique_node_benefit": fixed_unique_benefit,
            "benefit_per_cost": fixed_efficiency,
        },
        "candidate_only_families": sorted(candidate_only_families),
        "causal_removal": {
            "with_candidate_matches": len(candidate_rows),
            "without_candidate_matches": 0,
            "lost_matches": len(candidate_rows),
        },
        "gates": gates,
        "family_receipts": family_receipts,
        "candidate_rows": candidate_rows,
        "claim_boundary": {
            "native_runtime_inventions": 0,
            "search_level_reuse_only": True,
            "prospective_protocol_intervention_after_freeze": False,
        },
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE59_PROSPECTIVE_DIVERSITY"
        f" status={status}"
        f" graphs={payload['exported_graphs']}/4"
        f" tools={len(candidate_tools)}/{len(candidate['tools'])}"
        f" families={len(candidate_families)}/4"
        f" benefit={candidate_unique_benefit}/{fixed_unique_benefit}"
        f" cost={candidate_total_cost}/{fixed_total_cost}"
    )


if __name__ == "__main__":
    run()
