#!/usr/bin/env python3
"""Fully charged local utility and reachability comparison."""

from __future__ import annotations

import hashlib
import json
import pathlib
from typing import Any

from local_grammar_emergence_core_v1 import (
    canonical,
    eligible_nodes,
    enumerate_motifs,
    load_graphs,
    tensor_type,
)


HERE = pathlib.Path(__file__).resolve().parent
P163 = HERE / "results/phase163_local_operator_prediction.json"
P164 = HERE / "results/phase164_local_exact_body_prediction.json"
P165 = HERE / "results/phase165_local_exact_tool_execution.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"


def digest(value: Any) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def topology_units(topology: dict[str, Any]) -> int:
    return (
        topology["node_count"]
        + len(topology["internal_edges"])
        + sum(topology["external_input_uses"])
        + len(topology["output_indices"])
    )


def fixed_matches(graph, fixed: dict[str, Any]) -> tuple[list[dict[str, Any]], int, int]:
    nodes = eligible_nodes(graph)
    allowed = set(nodes)
    rows = []
    edge_checks = 0
    for tool in fixed["tools"]:
        expected = {
            "rank": tool["rank"],
            "dtype": tool["dtype"],
            "layout": tool["layout"],
        }

        def extend(path) -> None:
            nonlocal edge_checks
            index = len(path) - 1
            if (
                str(path[-1].target) != tool["targets"][index]
                or tensor_type(path[-1].meta.get("val")) != expected
            ):
                return
            if len(path) == len(tool["targets"]):
                rows.append({"tool": tool["name"], "node_names": [node.name for node in path]})
                return
            for user in sorted(path[-1].users, key=lambda item: item.name):
                if user in allowed and user not in path:
                    edge_checks += 1
                    extend(path + [user])

        for node in nodes:
            extend([node])
    return rows, len(nodes) * len(fixed["tools"]), edge_checks


def resource_row(result: dict[str, Any]) -> dict[str, Any]:
    receipt = result["receipt"]
    return {
        "version": result["version"],
        "result_sha256": digest(result),
        "user_cpu_ns": receipt["rusage_user_cpu_ns"],
        "system_cpu_ns": receipt["rusage_system_cpu_ns"],
        "wall_ns": receipt["wall_ns"],
        "peak_group_rss_kib": receipt["peak_group_rss_kib"],
        "process_group_reaped": receipt["process_group_reaped"],
        "termination": receipt["termination"],
    }


def run_utility() -> dict[str, Any]:
    p163 = json.loads(P163.read_text())
    p164 = json.loads(P164.read_text())
    p165 = json.loads(P165.read_text())
    body_ledger = p164["observed"]["ledger"]
    execution = p165["observed"]["ledger"]
    records = [enumerate_motifs(row) for row in load_graphs()]
    topology_map = {
        motif["topology_sha256"]: motif["topology"]
        for row in records
        for motif in row["motifs"]
    }
    total_motifs = sum(row["encoded_motifs"] for row in records)
    training_scans = total_motifs * 4
    heldout_scans = total_motifs
    model_definition = sum(
        topology_units(topology_map[row["topology_sha256"]])
        + len(row["candidate_body"]["nodes"])
        + len(row["candidate_body"]["inputs"])
        for row in body_ledger["prediction_records"]
    )
    exact_comparisons = body_ledger["summary"]["eligible_heldout_motifs"]
    dispatch = sum(
        len(
            next(
                row["candidate_body"]["nodes"]
                for row in body_ledger["prediction_records"]
                if row["fold"] == match["fold"]
                and row["topology_sha256"] == match["topology_sha256"]
            )
        )
        for match in body_ledger["exact_match_rows"]
    )
    unique_bodies = {
        row["candidate_body_sha256"]: row["candidate_body"]
        for row in body_ledger["prediction_records"]
        if row["candidate_body_sha256"]
        in {match["candidate_body_sha256"] for match in body_ledger["exact_match_rows"]}
    }
    compile_units = 2 * sum(len(body["nodes"]) for body in unique_bodies.values())
    candidate_components = {
        "training_motif_scans": training_scans,
        "heldout_motif_scans": heldout_scans,
        "model_definition": model_definition,
        "exact_comparisons": exact_comparisons,
        "dispatch": dispatch,
        "native_compile_units": compile_units,
    }
    candidate_total = sum(candidate_components.values())
    fixed = json.loads(FIXED.read_text())
    fixed_definition = sum(len(tool["targets"]) for tool in fixed["tools"])
    fixed_visits = 0
    fixed_edges = 0
    fixed_rows = []
    fixed_coverage = set()
    family_by_graph = {row["graph_id"]: row["family"] for row in records}
    for record in records:
        matches, visits, edges = fixed_matches(record["graph"], fixed)
        fixed_visits += visits
        fixed_edges += edges
        for match in matches:
            row = {"graph_id": record["graph_id"], **match}
            fixed_rows.append(row)
            fixed_coverage.update(
                f"{record['graph_id']}:{name}" for name in match["node_names"]
            )
    fixed_components = {
        "definition": fixed_definition,
        "match_visits": fixed_visits,
        "edge_checks": fixed_edges,
    }
    fixed_total = sum(fixed_components.values())
    candidate_coverage = {
        f"{row['graph_id']}:{name}"
        for row in body_ledger["exact_match_rows"]
        for name in row["node_names"]
    }
    candidate_only = candidate_coverage - fixed_coverage
    fixed_only = fixed_coverage - candidate_coverage
    candidate_only_families = sorted(
        {
            family_by_graph[node_id.rsplit(":", 1)[0]]
            for node_id in candidate_only
        }
    )
    resources = [
        resource_row(p163),
        resource_row(p164),
        resource_row(p165),
    ]
    compile_cpu = [
        {
            "body_sha256": row["body_sha256"],
            "candidate_cpu_ns": row["candidate"]["cpu_ns"],
            "stock_cpu_ns": row["stock"]["cpu_ns"],
        }
        for row in execution["native_rows"]
    ]
    candidate_efficiency = len(candidate_coverage) / candidate_total
    fixed_efficiency = len(fixed_coverage) / fixed_total
    summary = {
        "graphs": len(records),
        "encoded_motifs": total_motifs,
        "prediction_records": len(body_ledger["prediction_records"]),
        "candidate_matches": len(body_ledger["exact_match_rows"]),
        "candidate_tools": len(unique_bodies),
        "candidate_total_cost": candidate_total,
        "fixed_tools": len(fixed["tools"]),
        "fixed_matches": len(fixed_rows),
        "fixed_total_cost": fixed_total,
        "candidate_unique_nodes": len(candidate_coverage),
        "fixed_unique_nodes": len(fixed_coverage),
        "candidate_only_nodes": len(candidate_only),
        "fixed_only_nodes": len(fixed_only),
        "candidate_only_families": len(candidate_only_families),
        "candidate_benefit_per_cost": candidate_efficiency,
        "fixed_benefit_per_cost": fixed_efficiency,
        "candidate_cheaper": candidate_total < fixed_total,
        "candidate_more_efficient": candidate_efficiency > fixed_efficiency,
        "causal_candidate_nodes_after_remove_all": 0,
        "causal_candidate_only_nodes_after_remove_all": 0,
    }
    return {
        "version": "FOUNDRY_LOCAL_EXACT_TOOL_UTILITY_LEDGER_V1",
        "candidate_cost_components": candidate_components,
        "fixed_cost_components": fixed_components,
        "candidate_node_ids": sorted(candidate_coverage),
        "fixed_node_ids": sorted(fixed_coverage),
        "candidate_only_node_ids": sorted(candidate_only),
        "fixed_only_node_ids": sorted(fixed_only),
        "candidate_only_families": candidate_only_families,
        "fixed_match_rows": fixed_rows,
        "resource_receipts": resources,
        "native_compile_cpu": compile_cpu,
        "summary": summary,
        "claims": {
            "local_cross_validation_only": True,
            "previously_observed_corpus_not_fresh_external_evidence": True,
            "abstract_cost_not_wall_clock_speedup": True,
            "complete_search_prediction_compilation_dispatch_charged": True,
            "locally_newly_reachable_nodes": len(candidate_only) > 0,
            "prospective_real_world_discovery": False,
            "whole_graph_replacement_demonstrated": False,
            "lower_wall_clock_cost_demonstrated": False,
            "runtime_primitive_invented": False,
            "validation_v6_or_v7_accessed": False,
            "P2_advanced": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "prospective_trial_executed": False,
        },
    }


class ExactToolUtilityReject(ValueError):
    pass


_EXPECTED: dict[str, Any] | None = None


def verify_ledger(ledger: dict[str, Any], protocol: dict[str, Any]) -> None:
    if (
        protocol.get("version") != "FOUNDRY_LOCAL_EXACT_TOOL_UTILITY_PROTOCOL_V1"
        or protocol.get("status")
        != "PREFROZEN_BEFORE_TOTAL_COST_OR_REACHABILITY_IMPLEMENTATION"
    ):
        raise ExactToolUtilityReject("protocol identity")
    global _EXPECTED
    if _EXPECTED is None:
        _EXPECTED = run_utility()
    if set(ledger) != set(_EXPECTED):
        raise ExactToolUtilityReject("ledger schema")
    changed = [
        key for key in sorted(_EXPECTED)
        if canonical(ledger[key]) != canonical(_EXPECTED[key])
    ]
    if changed:
        raise ExactToolUtilityReject("recomputed ledger mismatch: " + ",".join(changed))


if __name__ == "__main__":
    result = run_utility()
    print(json.dumps(result["summary"], sort_keys=True))
