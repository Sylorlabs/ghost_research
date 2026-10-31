#!/usr/bin/env python3
"""Independent fully charged utility audit for the local exact tools."""

from __future__ import annotations

import copy
import functools
import hashlib
import json
import pathlib
from typing import Any

from independent_local_grammar_emergence_v1 import (
    load,
    nodes_of,
    tensor_kind,
)


HERE = pathlib.Path(__file__).resolve().parent
PHASE163 = HERE / "results/phase163_local_operator_prediction.json"
PHASE164 = HERE / "results/phase164_local_exact_body_prediction.json"
PHASE165 = HERE / "results/phase165_local_exact_tool_execution.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"


class IndependentExactToolUtilityReject(ValueError):
    """The utility ledger disagrees with independent replay."""


def canonical(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def _digest(value: object) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def _topology_cost(topology: dict[str, Any]) -> int:
    return (
        topology["node_count"]
        + len(topology["internal_edges"])
        + sum(topology["external_input_uses"])
        + len(topology["output_indices"])
    )


def _fixed_matches(
    graph: Any, portfolio: dict[str, Any]
) -> tuple[list[dict[str, Any]], int, int]:
    nodes = nodes_of(graph)
    allowed = set(nodes)
    matches: list[dict[str, Any]] = []
    edge_checks = 0
    for tool in portfolio["tools"]:
        expected_type = {
            "rank": tool["rank"],
            "dtype": tool["dtype"],
            "layout": tool["layout"],
        }

        def walk(path: tuple[Any, ...]) -> None:
            nonlocal edge_checks
            position = len(path) - 1
            current = path[-1]
            if (
                str(current.target) != tool["targets"][position]
                or tensor_kind(current.meta.get("val")) != expected_type
            ):
                return
            if len(path) == len(tool["targets"]):
                matches.append(
                    {
                        "tool": tool["name"],
                        "node_names": [node.name for node in path],
                    }
                )
                return
            for successor in sorted(
                current.users, key=lambda node: node.name
            ):
                if successor in allowed and successor not in path:
                    edge_checks += 1
                    walk((*path, successor))

        for node in nodes:
            walk((node,))
    # Every node is presented once to every supplied fixed tool.
    visits = len(nodes) * len(portfolio["tools"])
    return matches, visits, edge_checks


def _resource_receipt(result: dict[str, Any]) -> dict[str, Any]:
    receipt = result["receipt"]
    return {
        "version": result["version"],
        "result_sha256": _digest(result),
        "user_cpu_ns": receipt["rusage_user_cpu_ns"],
        "system_cpu_ns": receipt["rusage_system_cpu_ns"],
        "wall_ns": receipt["wall_ns"],
        "peak_group_rss_kib": receipt["peak_group_rss_kib"],
        "process_group_reaped": receipt["process_group_reaped"],
        "termination": receipt["termination"],
    }


@functools.lru_cache(maxsize=1)
def _computed() -> dict[str, Any]:
    phase163 = json.loads(PHASE163.read_text())
    phase164 = json.loads(PHASE164.read_text())
    phase165 = json.loads(PHASE165.read_text())
    prediction = phase164["observed"]["ledger"]
    execution = phase165["observed"]["ledger"]
    records = load()

    topology_by_id = {
        motif["topology_sha256"]: motif["topology"]
        for record in records
        for motif in record["motifs"]
    }
    encoded_motifs = sum(record["encoded_motifs"] for record in records)
    training_scans = 4 * encoded_motifs
    heldout_scans = encoded_motifs
    model_definition = 0
    for row in prediction["prediction_records"]:
        topology_id = row["topology_sha256"]
        if topology_id not in topology_by_id:
            raise IndependentExactToolUtilityReject(
                "prediction topology absent"
            )
        model_definition += (
            _topology_cost(topology_by_id[topology_id])
            + len(row["candidate_body"]["nodes"])
            + len(row["candidate_body"]["inputs"])
        )
    exact_comparisons = prediction["summary"][
        "eligible_heldout_motifs"
    ]
    prediction_by_fold_topology = {
        (row["fold"], row["topology_sha256"]): row
        for row in prediction["prediction_records"]
    }
    if len(prediction_by_fold_topology) != len(
        prediction["prediction_records"]
    ):
        raise IndependentExactToolUtilityReject(
            "duplicate prediction identity"
        )
    dispatch = 0
    for match in prediction["exact_match_rows"]:
        row = prediction_by_fold_topology.get(
            (match["fold"], match["topology_sha256"])
        )
        if row is None:
            raise IndependentExactToolUtilityReject(
                "exact match prediction absent"
            )
        dispatch += len(row["candidate_body"]["nodes"])

    exact_body_ids = {
        row["candidate_body_sha256"]
        for row in prediction["exact_match_rows"]
    }
    unique_bodies = {
        row["candidate_body_sha256"]: row["candidate_body"]
        for row in prediction["prediction_records"]
        if row["candidate_body_sha256"] in exact_body_ids
    }
    if set(unique_bodies) != exact_body_ids:
        raise IndependentExactToolUtilityReject("exact body absent")
    native_compile_units = 2 * sum(
        len(body["nodes"]) for body in unique_bodies.values()
    )
    candidate_components = {
        "training_motif_scans": training_scans,
        "heldout_motif_scans": heldout_scans,
        "model_definition": model_definition,
        "exact_comparisons": exact_comparisons,
        "dispatch": dispatch,
        "native_compile_units": native_compile_units,
    }
    candidate_total = sum(candidate_components.values())

    portfolio = json.loads(FIXED.read_text())
    fixed_definition = sum(
        len(tool["targets"]) for tool in portfolio["tools"]
    )
    fixed_visits = 0
    fixed_edges = 0
    fixed_rows: list[dict[str, Any]] = []
    fixed_nodes: set[str] = set()
    family_by_graph = {
        record["graph_id"]: record["family"] for record in records
    }
    for record in records:
        matches, visits, edges = _fixed_matches(
            record["graph"], portfolio
        )
        fixed_visits += visits
        fixed_edges += edges
        for match in matches:
            fixed_rows.append(
                {"graph_id": record["graph_id"], **match}
            )
            fixed_nodes.update(
                f"{record['graph_id']}:{node_name}"
                for node_name in match["node_names"]
            )
    fixed_components = {
        "definition": fixed_definition,
        "match_visits": fixed_visits,
        "edge_checks": fixed_edges,
    }
    fixed_total = sum(fixed_components.values())

    candidate_nodes = {
        f"{row['graph_id']}:{node_name}"
        for row in prediction["exact_match_rows"]
        for node_name in row["node_names"]
    }
    candidate_only = candidate_nodes - fixed_nodes
    fixed_only = fixed_nodes - candidate_nodes
    candidate_only_families = sorted(
        {
            family_by_graph[node_id.rsplit(":", 1)[0]]
            for node_id in candidate_only
        }
    )
    resources = [
        _resource_receipt(phase163),
        _resource_receipt(phase164),
        _resource_receipt(phase165),
    ]
    compile_cpu = [
        {
            "body_sha256": row["body_sha256"],
            "candidate_cpu_ns": row["candidate"]["cpu_ns"],
            "stock_cpu_ns": row["stock"]["cpu_ns"],
        }
        for row in execution["native_rows"]
    ]
    candidate_efficiency = len(candidate_nodes) / candidate_total
    fixed_efficiency = len(fixed_nodes) / fixed_total
    summary = {
        "graphs": len(records),
        "encoded_motifs": encoded_motifs,
        "prediction_records": len(prediction["prediction_records"]),
        "candidate_matches": len(prediction["exact_match_rows"]),
        "candidate_tools": len(unique_bodies),
        "candidate_total_cost": candidate_total,
        "fixed_tools": len(portfolio["tools"]),
        "fixed_matches": len(fixed_rows),
        "fixed_total_cost": fixed_total,
        "candidate_unique_nodes": len(candidate_nodes),
        "fixed_unique_nodes": len(fixed_nodes),
        "candidate_only_nodes": len(candidate_only),
        "fixed_only_nodes": len(fixed_only),
        "candidate_only_families": len(candidate_only_families),
        "candidate_benefit_per_cost": candidate_efficiency,
        "fixed_benefit_per_cost": fixed_efficiency,
        "candidate_cheaper": candidate_total < fixed_total,
        "candidate_more_efficient": (
            candidate_efficiency > fixed_efficiency
        ),
        "causal_candidate_nodes_after_remove_all": 0,
        "causal_candidate_only_nodes_after_remove_all": 0,
    }
    return {
        "version": "FOUNDRY_LOCAL_EXACT_TOOL_UTILITY_LEDGER_V1",
        "candidate_cost_components": candidate_components,
        "fixed_cost_components": fixed_components,
        "candidate_node_ids": sorted(candidate_nodes),
        "fixed_node_ids": sorted(fixed_nodes),
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


def independent_run() -> dict[str, Any]:
    """Return a detached independent replay of the utility ledger."""

    return copy.deepcopy(_computed())


def verify_ledger(
    ledger: dict[str, Any], protocol: dict[str, Any]
) -> None:
    """Strictly compare a proposed ledger with the cached independent replay."""

    if not isinstance(protocol, dict):
        raise IndependentExactToolUtilityReject("protocol type")
    try:
        if (
            protocol["version"]
            != "FOUNDRY_LOCAL_EXACT_TOOL_UTILITY_PROTOCOL_V1"
            or protocol["status"]
            != "PREFROZEN_BEFORE_TOTAL_COST_OR_REACHABILITY_IMPLEMENTATION"
            or protocol["evaluation_universe"]["graphs"] != 23
            or protocol["evaluation_universe"]["folds"] != 5
            or protocol["abstract_cost"][
                "do_not_mix_cpu_nanoseconds_with_abstract_units"
            ]
            is not True
            or protocol["resource_accounting"][
                "carry_phase165_process_tree_receipt"
            ]
            is not True
            or protocol["decision_rule"][
                "positive_is_not_prospective_real_world_discovery"
            ]
            is not True
            or protocol["decision_rule"][
                "positive_does_not_advance_P2_or_P6"
            ]
            is not True
            or protocol["claim_boundary"][
                "abstract_cost_not_wall_clock_speedup"
            ]
            is not True
            or protocol["claim_boundary"][
                "stock_duplicates_not_runtime_inventions"
            ]
            is not True
            or protocol["claim_boundary"][
                "no_whole_graph_replacement_claim"
            ]
            is not True
        ):
            raise IndependentExactToolUtilityReject(
                "protocol boundary"
            )
    except (KeyError, TypeError) as error:
        raise IndependentExactToolUtilityReject(
            "protocol schema"
        ) from error

    if not isinstance(ledger, dict):
        raise IndependentExactToolUtilityReject("ledger type")
    expected = _computed()
    if canonical(ledger) != canonical(expected):
        changed = sorted(
            key
            for key in set(ledger) | set(expected)
            if ledger.get(key) != expected.get(key)
        )
        raise IndependentExactToolUtilityReject(
            "independent utility mismatch: " + ",".join(changed)
        )


if __name__ == "__main__":
    result = independent_run()
    protocol = json.loads(
        (
            HERE
            / "arm_adapter_fixtures/"
            "LOCAL_EXACT_TOOL_UTILITY_PROTOCOL_V1.json"
        ).read_text()
    )
    verify_ledger(result, protocol)
    summary = result["summary"]
    print(
        "FOUNDRY_INDEPENDENT_LOCAL_EXACT_TOOL_UTILITY"
        f" cost={summary['candidate_total_cost']}/"
        f"{summary['fixed_total_cost']}"
        f" nodes={summary['candidate_unique_nodes']}/"
        f"{summary['fixed_unique_nodes']}"
        f" candidate_only={summary['candidate_only_nodes']}"
        " prospective=false"
    )
