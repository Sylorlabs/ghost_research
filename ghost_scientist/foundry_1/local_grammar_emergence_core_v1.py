#!/usr/bin/env python3
"""Primary connected-DAG grammar learner for the local Phase160 experiment."""

from __future__ import annotations

import collections
import hashlib
import json
import pathlib
from typing import Any

import torch
from torch.fx import Node

from phase63_pareto_motif_calibration import (
    UnsupportedTerm,
    encode_term,
    old_repository,
    tensor_type,
    workloads,
)


HERE = pathlib.Path(__file__).resolve().parent


def canonical(value: object) -> bytes:
    return (
        json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n"
    ).encode()


def digest(value: object) -> str:
    return hashlib.sha256(canonical(value)).hexdigest()


def split_assignment(graph_id: str) -> str:
    value = hashlib.sha256(
        ("ghost-foundry:grammar-v1:" + graph_id).encode()
    ).hexdigest()
    return "heldout" if int(value, 16) % 5 == 0 else "training"


def eligible_nodes(graph: torch.fx.Graph) -> list[Node]:
    return [
        node
        for node in graph.nodes
        if node.op == "call_function"
        and str(node.target).startswith("aten.")
        and tensor_type(node.meta.get("val")) is not None
    ]


def connected_subsets(nodes: list[Node], maximum: int = 5) -> list[tuple[int, ...]]:
    position = {node: index for index, node in enumerate(nodes)}
    node_set = set(nodes)
    neighbors: list[set[int]] = [set() for _ in nodes]
    for consumer in nodes:
        right = position[consumer]
        for producer in consumer.all_input_nodes:
            if producer in node_set:
                left = position[producer]
                neighbors[left].add(right)
                neighbors[right].add(left)
    visited: set[frozenset[int]] = set()
    accepted: set[tuple[int, ...]] = set()
    stack = [frozenset({index}) for index in range(len(nodes))]
    while stack:
        subset = stack.pop()
        if subset in visited:
            continue
        visited.add(subset)
        if len(subset) >= 2:
            accepted.add(tuple(sorted(subset)))
        if len(subset) == maximum:
            continue
        frontier = set().union(*(neighbors[index] for index in subset)) - set(
            subset
        )
        for index in sorted(frontier, reverse=True):
            expanded = frozenset((*subset, index))
            if expanded not in visited:
                stack.append(expanded)
    return sorted(accepted, key=lambda item: (len(item), item))


def topology(nodes: list[Node], indices: tuple[int, ...]) -> dict[str, Any]:
    selected = [nodes[index] for index in indices]
    internal = {node: index for index, node in enumerate(selected)}
    selected_set = set(selected)
    edges = sorted(
        [internal[producer], internal[consumer]]
        for consumer in selected
        for producer in consumer.all_input_nodes
        if producer in selected_set
    )
    external_uses = [
        sum(
            dependency not in selected_set
            and tensor_type(dependency.meta.get("val")) is not None
            for dependency in node.all_input_nodes
        )
        for node in selected
    ]
    outputs = [
        index
        for index, node in enumerate(selected)
        if any(user not in selected_set for user in node.users)
        or not node.users
    ]
    return {
        "node_count": len(selected),
        "internal_edges": edges,
        "external_input_uses": external_uses,
        "output_indices": outputs,
    }


def is_fixed_chain(production: dict[str, Any]) -> bool:
    size = production["node_count"]
    return (
        production["output_indices"] == [size - 1]
        and production["internal_edges"]
        == [[index, index + 1] for index in range(size - 1)]
    )


def construct_body(nodes: list[Node], indices: tuple[int, ...]) -> dict[str, Any]:
    selected = [nodes[index] for index in indices]
    internal = {node: index for index, node in enumerate(selected)}
    external: dict[Node, int] = {}
    inputs: list[dict[str, object]] = []
    encoded_nodes = []
    for node in selected:
        kind = tensor_type(node.meta.get("val"))
        if kind is None:
            raise UnsupportedTerm("untyped internal node")
        encoded_nodes.append(
            {
                "target": str(node.target),
                "args": encode_term(node.args, internal, external, inputs),
                "kwargs": encode_term(node.kwargs, internal, external, inputs),
                "output_type": kind,
            }
        )
    production = topology(nodes, indices)
    return {
        "version": "FOUNDRY_LOCAL_EXACT_DAG_TOOL_V1",
        "inputs": inputs,
        "nodes": encoded_nodes,
        "outputs": [{"node": index} for index in production["output_indices"]],
    }


def load_graphs() -> list[dict[str, Any]]:
    pool = json.loads((HERE / "results/pareto_tool_pool.json").read_text())
    expected = {row["graph_id"]: row for row in pool["calibration_graphs"]}
    instantiated, unsupported = workloads()
    expected_unsupported = json.loads(
        (HERE / "results/phase63_pareto_motif_calibration.json").read_text()
    )["unsupported_families"]
    if unsupported != expected_unsupported:
        raise RuntimeError(f"historical workload construction changed: {unsupported}")
    rows = []
    for suite, workload in instantiated:
        family = workload["family"]
        graph_id = f"{suite}:{family}"
        if graph_id not in expected:
            raise RuntimeError(f"unexpected graph {graph_id}")
        exported = torch.export.export(
            workload["model"], workload["args"], workload["kwargs"], strict=True
        )
        graph = exported.module().graph
        graph_sha = hashlib.sha256(str(graph).encode()).hexdigest()
        if graph_sha != expected[graph_id]["graph_sha256"]:
            raise RuntimeError(f"graph digest changed: {graph_id}")
        rows.append(
            {
                "graph_id": graph_id,
                "suite": suite,
                "family": family,
                "repository": workload.get(
                    "repository", old_repository(suite, family)
                ),
                "semantic_domain": workload.get("semantic_domain", family),
                "assignment": split_assignment(graph_id),
                "graph_sha256": graph_sha,
                "graph": graph,
            }
        )
    if len(rows) != 23 or set(expected) != {row["graph_id"] for row in rows}:
        raise RuntimeError("authenticated graph census changed")
    return sorted(rows, key=lambda row: row["graph_id"])


def enumerate_motifs(graph_row: dict[str, Any]) -> dict[str, Any]:
    nodes = eligible_nodes(graph_row["graph"])
    subsets = connected_subsets(nodes)
    motifs = []
    unsupported = 0
    for indices in subsets:
        production = topology(nodes, indices)
        try:
            body = construct_body(nodes, indices)
        except UnsupportedTerm:
            unsupported += 1
            continue
        motifs.append(
            {
                "indices": list(indices),
                "node_names": [nodes[index].name for index in indices],
                "topology": production,
                "topology_sha256": digest(production),
                "body": body,
                "body_sha256": digest(body),
                "fixed_chain": is_fixed_chain(production),
            }
        )
    return {
        **graph_row,
        "eligible_nodes": len(nodes),
        "connected_subsets": len(subsets),
        "encoded_motifs": len(motifs),
        "unsupported_motifs": unsupported,
        "motifs": motifs,
    }


def structural_units(body: dict[str, Any]) -> int:
    return len(body["nodes"]) + len(body["inputs"]) + len(body["outputs"])


def learn(records: list[dict[str, Any]]) -> dict[str, Any]:
    training = [row for row in records if row["assignment"] == "training"]
    heldout = [row for row in records if row["assignment"] == "heldout"]
    topology_groups: dict[str, dict[str, Any]] = {}
    for row in training:
        for motif in row["motifs"]:
            group = topology_groups.setdefault(
                motif["topology_sha256"],
                {
                    "topology": motif["topology"],
                    "occurrences": [],
                    "families": set(),
                },
            )
            group["occurrences"].append((row["graph_id"], motif["node_names"]))
            group["families"].add(row["family"])
    productions = {}
    for identifier, group in topology_groups.items():
        occurrence_count = len(group["occurrences"])
        family_count = len(group["families"])
        production = group["topology"]
        units = (
            production["node_count"]
            + len(production["internal_edges"])
            + len(production["output_indices"])
        )
        gain = occurrence_count * units - (units + occurrence_count)
        if occurrence_count >= 3 and family_count >= 2 and gain > 0:
            productions[identifier] = {
                "topology": production,
                "occurrence_count": occurrence_count,
                "family_count": family_count,
                "description_length_gain": gain,
                "fixed_chain": is_fixed_chain(production),
            }
    body_groups: dict[str, dict[str, Any]] = {}
    for row in training:
        for motif in row["motifs"]:
            if motif["topology_sha256"] not in productions:
                continue
            group = body_groups.setdefault(
                motif["body_sha256"],
                {
                    "body": motif["body"],
                    "topology_sha256": motif["topology_sha256"],
                    "occurrences": [],
                    "families": set(),
                    "repositories": set(),
                },
            )
            group["occurrences"].append((row["graph_id"], motif["node_names"]))
            group["families"].add(row["family"])
            group["repositories"].add(row["repository"])
    tools = {}
    for identifier, group in body_groups.items():
        count = len(group["occurrences"])
        family_count = len(group["families"])
        units = structural_units(group["body"])
        gain = count * units - (units + count)
        if count >= 2 and family_count >= 2 and gain > 0:
            tools[identifier] = {
                "body": group["body"],
                "topology_sha256": group["topology_sha256"],
                "occurrence_count": count,
                "family_count": family_count,
                "repository_count": len(group["repositories"]),
                "description_length_gain": gain,
                "fixed_chain": productions[group["topology_sha256"]][
                    "fixed_chain"
                ],
            }
    chain_tools = {
        identifier: tool
        for identifier, tool in tools.items()
        if tool["fixed_chain"]
    }
    heldout_matches = []
    chain_matches = []
    for row in heldout:
        for motif in row["motifs"]:
            if motif["body_sha256"] in tools:
                heldout_matches.append(
                    {
                        "graph_id": row["graph_id"],
                        "body_sha256": motif["body_sha256"],
                        "topology_sha256": motif["topology_sha256"],
                        "node_names": motif["node_names"],
                        "fixed_chain": motif["fixed_chain"],
                    }
                )
            if motif["body_sha256"] in chain_tools:
                chain_matches.append(
                    {
                        "graph_id": row["graph_id"],
                        "body_sha256": motif["body_sha256"],
                        "node_names": motif["node_names"],
                    }
                )
    fixed = json.loads((HERE / "ATEN_FIXED_PORTFOLIO_V2.json").read_text())
    fixed_sequences = {
        tuple(tool["targets"]) for tool in fixed["tools"]
    }
    fixed_coverage: set[str] = set()
    fixed_match_count = 0
    for row in heldout:
        nodes = eligible_nodes(row["graph"])
        node_set = set(nodes)
        for tool in fixed["tools"]:
            expected_type = {
                "rank": tool["rank"],
                "dtype": tool["dtype"],
                "layout": tool["layout"],
            }

            def extend(path: list[Node]) -> None:
                nonlocal fixed_match_count
                index = len(path) - 1
                if (
                    str(path[-1].target) != tool["targets"][index]
                    or tensor_type(path[-1].meta.get("val")) != expected_type
                ):
                    return
                if len(path) == len(tool["targets"]):
                    fixed_match_count += 1
                    fixed_coverage.update(
                        f"{row['graph_id']}:{node.name}" for node in path
                    )
                    return
                for user in sorted(path[-1].users, key=lambda item: item.name):
                    if user in node_set and user not in path:
                        extend(path + [user])

            for node in nodes:
                extend([node])
    candidate_coverage = {
        f"{match['graph_id']}:{name}"
        for match in heldout_matches
        for name in match["node_names"]
    }
    chain_coverage = {
        f"{match['graph_id']}:{name}"
        for match in chain_matches
        for name in match["node_names"]
    }
    candidate_only_tool_ids = sorted(
        identifier
        for identifier, tool in tools.items()
        if not tool["fixed_chain"]
        and any(
            match["body_sha256"] == identifier for match in heldout_matches
        )
        and tuple(node["target"] for node in tool["body"]["nodes"])
        not in fixed_sequences
    )
    candidate_only_matches = [
        match
        for match in heldout_matches
        if match["body_sha256"] in candidate_only_tool_ids
    ]
    candidate_only_nodes = candidate_coverage - chain_coverage - fixed_coverage
    removed_non_chain_matches = [
        match for match in heldout_matches if match["fixed_chain"]
    ]
    per_tool_causal = {
        identifier: sum(
            match["body_sha256"] == identifier
            for match in candidate_only_matches
        )
        for identifier in candidate_only_tool_ids
    }
    candidate_cost = (
        sum(row["connected_subsets"] for row in training)
        + sum(
            item["topology"]["node_count"]
            + len(item["topology"]["internal_edges"])
            + len(item["topology"]["output_indices"])
            for item in productions.values()
        )
        + sum(structural_units(item["body"]) for item in tools.values())
        + sum(row["connected_subsets"] for row in heldout)
    )
    chain_train = sum(
        motif["fixed_chain"]
        for row in training
        for motif in row["motifs"]
    )
    chain_heldout = sum(
        motif["fixed_chain"]
        for row in heldout
        for motif in row["motifs"]
    )
    chain_cost = (
        chain_train
        + sum(structural_units(item["body"]) for item in chain_tools.values())
        + chain_heldout
    )
    summary = {
        "training_graphs": len(training),
        "heldout_graphs": len(heldout),
        "training_connected_subsets": sum(
            row["connected_subsets"] for row in training
        ),
        "heldout_connected_subsets": sum(
            row["connected_subsets"] for row in heldout
        ),
        "topology_groups": len(topology_groups),
        "selected_productions": len(productions),
        "selected_non_chain_productions": sum(
            not item["fixed_chain"] for item in productions.values()
        ),
        "selected_multi_output_productions": sum(
            len(item["topology"]["output_indices"]) > 1
            for item in productions.values()
        ),
        "selected_tools": len(tools),
        "selected_non_chain_tools": sum(
            not item["fixed_chain"] for item in tools.values()
        ),
        "chain_control_tools": len(chain_tools),
        "heldout_candidate_matches": len(heldout_matches),
        "heldout_chain_matches": len(chain_matches),
        "heldout_fixed_matches": fixed_match_count,
        "candidate_only_heldout_tools": len(candidate_only_tool_ids),
        "candidate_only_heldout_matches": len(candidate_only_matches),
        "candidate_unique_heldout_nodes": len(candidate_coverage),
        "chain_unique_heldout_nodes": len(chain_coverage),
        "fixed_unique_heldout_nodes": len(fixed_coverage),
        "candidate_only_heldout_nodes": len(candidate_only_nodes),
        "candidate_cost": candidate_cost,
        "chain_control_cost": chain_cost,
        "causal_non_chain_matches_after_removal": len(
            removed_non_chain_matches
        ),
        "causal_candidate_only_matches_after_non_chain_removal": 0,
        "per_candidate_only_tool_causal_losses": per_tool_causal,
    }
    return {
        "version": "FOUNDRY_LOCAL_GRAMMAR_EMERGENCE_LEDGER_V1",
        "graph_records": [
            {
                key: value
                for key, value in row.items()
                if key not in {"motifs", "graph"}
            }
            for row in records
        ],
        "production_ids": sorted(productions),
        "production_records": [
            {
                "topology_sha256": identifier,
                "topology": productions[identifier]["topology"],
                "fixed_chain": productions[identifier]["fixed_chain"],
            }
            for identifier in sorted(productions)
        ],
        "non_chain_production_ids": sorted(
            key for key, item in productions.items() if not item["fixed_chain"]
        ),
        "multi_output_production_ids": sorted(
            key
            for key, item in productions.items()
            if len(item["topology"]["output_indices"]) > 1
        ),
        "tool_ids": sorted(tools),
        "tool_records": [
            {
                "body_sha256": identifier,
                "body": tools[identifier]["body"],
                "topology_sha256": tools[identifier]["topology_sha256"],
                "fixed_chain": tools[identifier]["fixed_chain"],
            }
            for identifier in sorted(tools)
        ],
        "chain_tool_ids": sorted(chain_tools),
        "heldout_matches": heldout_matches,
        "candidate_only_tool_ids": candidate_only_tool_ids,
        "candidate_only_matches": candidate_only_matches,
        "candidate_only_node_ids": sorted(candidate_only_nodes),
        "per_tool_causal_losses": per_tool_causal,
        "summary": summary,
        "claims": {
            "local_exploratory_only": True,
            "post_exploratory_not_pristine": True,
            "universal_metalanguage_evaluator_supplied": True,
            "topology_productions_machine_selected": True,
            "heldout_learning_performed": False,
            "validation_v6_or_v7_accessed": False,
            "P6_advanced": False,
            "prospective_trial_authorized": False,
            "prospective_trial_executed": False,
        },
    }


def run_experiment() -> dict[str, Any]:
    records = [enumerate_motifs(row) for row in load_graphs()]
    return learn(records)


class GrammarLedgerReject(ValueError):
    pass


def _term_refs(value: object, key: str) -> set[int]:
    if isinstance(value, dict):
        found = {value[key]} if set(value) == {key} else set()
        for item in value.values():
            found.update(_term_refs(item, key))
        return found
    if isinstance(value, list):
        found: set[int] = set()
        for item in value:
            found.update(_term_refs(item, key))
        return found
    return set()


def topology_from_body(body: dict[str, Any]) -> dict[str, Any]:
    count = len(body["nodes"])
    edges = sorted(
        [producer, consumer]
        for consumer, node in enumerate(body["nodes"])
        for producer in (
            _term_refs(node["args"], "node")
            | _term_refs(node["kwargs"], "node")
        )
    )
    external = [
        len(
            _term_refs(node["args"], "input")
            | _term_refs(node["kwargs"], "input")
        )
        for node in body["nodes"]
    ]
    return {
        "node_count": count,
        "internal_edges": edges,
        "external_input_uses": external,
        "output_indices": [row["node"] for row in body["outputs"]],
    }


def verify_ledger(
    ledger: dict[str, Any],
    protocol: dict[str, Any],
    freeze: dict[str, Any],
) -> None:
    expected_fields = {
        "version",
        "graph_records",
        "production_ids",
        "production_records",
        "non_chain_production_ids",
        "multi_output_production_ids",
        "tool_ids",
        "tool_records",
        "chain_tool_ids",
        "heldout_matches",
        "candidate_only_tool_ids",
        "candidate_only_matches",
        "candidate_only_node_ids",
        "per_tool_causal_losses",
        "summary",
        "claims",
    }
    if (
        set(ledger) != expected_fields
        or ledger["version"] != "FOUNDRY_LOCAL_GRAMMAR_EMERGENCE_LEDGER_V1"
    ):
        raise GrammarLedgerReject("ledger schema")
    frozen_graphs = {
        row["graph_id"]: row for row in freeze["split_records"]
    }
    records = ledger["graph_records"]
    if (
        len(records) != 23
        or {row["graph_id"] for row in records} != set(frozen_graphs)
        or any(
            row["graph_sha256"] != frozen_graphs[row["graph_id"]]["graph_sha256"]
            or row["assignment"]
            != frozen_graphs[row["graph_id"]]["assignment"]
            for row in records
        )
    ):
        raise GrammarLedgerReject("frozen graph split")
    production_ids = ledger["production_ids"]
    if production_ids != sorted(set(production_ids)):
        raise GrammarLedgerReject("production ids")
    production_map = {}
    for row in ledger["production_records"]:
        if set(row) != {"topology_sha256", "topology", "fixed_chain"}:
            raise GrammarLedgerReject("production schema")
        topology_value = row["topology"]
        if (
            row["topology_sha256"] != digest(topology_value)
            or row["topology_sha256"] in production_map
            or set(topology_value)
            != {
                "node_count",
                "internal_edges",
                "external_input_uses",
                "output_indices",
            }
        ):
            raise GrammarLedgerReject("production digest")
        count = topology_value["node_count"]
        edges = topology_value["internal_edges"]
        outputs = topology_value["output_indices"]
        external = topology_value["external_input_uses"]
        if (
            type(count) is not int
            or not 2 <= count <= 5
            or len(external) != count
            or any(type(value) is not int or value < 0 for value in external)
            or edges
            != [list(edge) for edge in sorted({tuple(edge) for edge in edges})]
            or any(
                type(edge) is not list
                or len(edge) != 2
                or type(edge[0]) is not int
                or type(edge[1]) is not int
                or not 0 <= edge[0] < edge[1] < count
                for edge in edges
            )
            or outputs != sorted(set(outputs))
            or any(type(value) is not int or not 0 <= value < count for value in outputs)
        ):
            raise GrammarLedgerReject("production structure")
        adjacency = [set() for _ in range(count)]
        for left, right in edges:
            adjacency[left].add(right)
            adjacency[right].add(left)
        reached = {0}
        pending = [0]
        while pending:
            current = pending.pop()
            for neighbor in adjacency[current] - reached:
                reached.add(neighbor)
                pending.append(neighbor)
        sinks = {
            index
            for index in range(count)
            if not any(edge[0] == index for edge in edges)
        }
        if (
            len(reached) != count
            or not sinks <= set(outputs)
            or row["fixed_chain"] != is_fixed_chain(topology_value)
        ):
            raise GrammarLedgerReject("production connectivity")
        production_map[row["topology_sha256"]] = row
    if sorted(production_map) != production_ids:
        raise GrammarLedgerReject("production records")
    tool_ids = ledger["tool_ids"]
    tool_map = {}
    for row in ledger["tool_records"]:
        if set(row) != {
            "body_sha256",
            "body",
            "topology_sha256",
            "fixed_chain",
        }:
            raise GrammarLedgerReject("tool schema")
        if (
            row["body_sha256"] != digest(row["body"])
            or row["body_sha256"] in tool_map
            or row["topology_sha256"] not in production_map
            or topology_from_body(row["body"])
            != production_map[row["topology_sha256"]]["topology"]
            or row["fixed_chain"]
            != production_map[row["topology_sha256"]]["fixed_chain"]
        ):
            raise GrammarLedgerReject("tool relation")
        tool_map[row["body_sha256"]] = row
    if sorted(tool_map) != tool_ids or tool_ids != sorted(set(tool_ids)):
        raise GrammarLedgerReject("tool records")
    heldout_ids = {
        row["graph_id"] for row in records if row["assignment"] == "heldout"
    }
    for match in ledger["heldout_matches"]:
        if (
            set(match)
            != {
                "graph_id",
                "body_sha256",
                "topology_sha256",
                "node_names",
                "fixed_chain",
            }
            or match["graph_id"] not in heldout_ids
            or match["body_sha256"] not in tool_map
            or match["topology_sha256"]
            != tool_map[match["body_sha256"]]["topology_sha256"]
            or len(match["node_names"])
            != len(tool_map[match["body_sha256"]]["body"]["nodes"])
            or len(set(match["node_names"])) != len(match["node_names"])
        ):
            raise GrammarLedgerReject("heldout match")
    if (
        not set(ledger["candidate_only_tool_ids"]) <= set(tool_map)
        or any(
            tool_map[identifier]["fixed_chain"]
            for identifier in ledger["candidate_only_tool_ids"]
        )
        or ledger["candidate_only_matches"]
        != [
            match
            for match in ledger["heldout_matches"]
            if match["body_sha256"] in set(ledger["candidate_only_tool_ids"])
        ]
    ):
        raise GrammarLedgerReject("candidate-only match relation")
    summary = ledger["summary"]
    if (
        summary["selected_productions"] != len(production_ids)
        or summary["selected_non_chain_productions"]
        != len(ledger["non_chain_production_ids"])
        or summary["selected_multi_output_productions"]
        != len(ledger["multi_output_production_ids"])
        or summary["selected_tools"] != len(tool_ids)
        or summary["chain_control_tools"] != len(ledger["chain_tool_ids"])
        or summary["heldout_candidate_matches"] != len(ledger["heldout_matches"])
        or summary["candidate_only_heldout_tools"]
        != len(ledger["candidate_only_tool_ids"])
        or summary["candidate_only_heldout_matches"]
        != len(ledger["candidate_only_matches"])
        or summary["candidate_only_heldout_nodes"]
        != len(ledger["candidate_only_node_ids"])
        or summary["causal_candidate_only_matches_after_non_chain_removal"] != 0
        or set(ledger["per_tool_causal_losses"])
        != set(ledger["candidate_only_tool_ids"])
        or any(value <= 0 for value in ledger["per_tool_causal_losses"].values())
    ):
        raise GrammarLedgerReject("summary or causal relation")
    expected_claims = {
        "local_exploratory_only": True,
        "post_exploratory_not_pristine": True,
        "universal_metalanguage_evaluator_supplied": True,
        "topology_productions_machine_selected": True,
        "heldout_learning_performed": False,
        "validation_v6_or_v7_accessed": False,
        "P6_advanced": False,
        "prospective_trial_authorized": False,
        "prospective_trial_executed": False,
    }
    if ledger["claims"] != expected_claims or protocol["claim_boundary"][
        "local_grammar_emergence_experiment_only"
    ] is not True:
        raise GrammarLedgerReject("claim boundary")
