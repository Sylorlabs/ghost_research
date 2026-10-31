#!/usr/bin/env python3
"""Independent brute-combination verifier for local grammar emergence."""

from __future__ import annotations

import hashlib
import itertools
import json
import pathlib
import re
from typing import Any

import torch
from torch.fx import Node

from phase63_pareto_motif_calibration import old_repository, workloads


HERE = pathlib.Path(__file__).resolve().parent


class IndependentGrammarReject(ValueError):
    pass


def encode(value: object) -> bytes:
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n"


def digest(value: object) -> str:
    return hashlib.sha256(encode(value)).hexdigest()


def tensor_kind(value: object) -> dict[str, object] | None:
    if not isinstance(value, torch.Tensor):
        return None
    return {
        "rank": len(value.shape),
        "dtype": str(value.dtype),
        "layout": str(value.layout),
    }


def literal(value: object) -> dict[str, object]:
    if value is None or type(value) in {bool, int, float, str}:
        return {"literal": value}
    if isinstance(value, torch.dtype):
        return {"torch_dtype": str(value)}
    if isinstance(value, torch.device):
        return {"torch_device": str(value)}
    raise IndependentGrammarReject("unsupported literal")


def term(
    value: object,
    internal: dict[Node, int],
    external: dict[Node, int],
    inputs: list[dict[str, object]],
) -> dict[str, object]:
    if isinstance(value, Node):
        if value in internal:
            return {"node": internal[value]}
        kind = tensor_kind(value.meta.get("val"))
        if kind is None:
            raise IndependentGrammarReject("untyped external")
        if value not in external:
            external[value] = len(inputs)
            inputs.append({"type": kind})
        return {"input": external[value]}
    if isinstance(value, tuple):
        return {
            "tuple": [
                term(item, internal, external, inputs) for item in value
            ]
        }
    if isinstance(value, list):
        return {
            "list": [
                term(item, internal, external, inputs) for item in value
            ]
        }
    if isinstance(value, dict):
        return {
            "dict": [
                [
                    literal(key),
                    term(item, internal, external, inputs),
                ]
                for key, item in sorted(value.items(), key=lambda pair: str(pair[0]))
            ]
        }
    return literal(value)


def graph_assignment(graph_id: str) -> str:
    raw = hashlib.sha256(
        ("ghost-foundry:grammar-v1:" + graph_id).encode()
    ).digest()
    return "heldout" if int.from_bytes(raw, "big") % 5 == 0 else "training"


def nodes_of(graph: torch.fx.Graph) -> list[Node]:
    return [
        node
        for node in graph.nodes
        if node.op == "call_function"
        and str(node.target).startswith("aten.")
        and tensor_kind(node.meta.get("val")) is not None
    ]


def connected_combinations(nodes: list[Node]) -> list[tuple[int, ...]]:
    position = {node: index for index, node in enumerate(nodes)}
    adjacency = [set() for _ in nodes]
    for right, node in enumerate(nodes):
        for dependency in node.all_input_nodes:
            if dependency in position:
                left = position[dependency]
                adjacency[left].add(right)
                adjacency[right].add(left)
    found = []
    for size in range(2, 6):
        for indices in itertools.combinations(range(len(nodes)), size):
            allowed = set(indices)
            reached = {indices[0]}
            pending = [indices[0]]
            while pending:
                current = pending.pop()
                for neighbor in adjacency[current] & allowed - reached:
                    reached.add(neighbor)
                    pending.append(neighbor)
            if reached == allowed:
                found.append(indices)
    return found


def describe(nodes: list[Node], indices: tuple[int, ...]) -> tuple[dict, dict]:
    selected = [nodes[index] for index in indices]
    internal = {node: index for index, node in enumerate(selected)}
    selected_set = set(selected)
    edges = []
    external_uses = []
    for consumer_index, node in enumerate(selected):
        outside = 0
        for dependency in node.all_input_nodes:
            if dependency in internal:
                edges.append([internal[dependency], consumer_index])
            elif tensor_kind(dependency.meta.get("val")) is not None:
                outside += 1
        external_uses.append(outside)
    outputs = [
        index
        for index, node in enumerate(selected)
        if not node.users or any(user not in selected_set for user in node.users)
    ]
    topology = {
        "node_count": len(selected),
        "internal_edges": sorted(edges),
        "external_input_uses": external_uses,
        "output_indices": outputs,
    }
    external: dict[Node, int] = {}
    inputs: list[dict[str, object]] = []
    body_nodes = []
    for node in selected:
        body_nodes.append(
            {
                "target": str(node.target),
                "args": term(node.args, internal, external, inputs),
                "kwargs": term(node.kwargs, internal, external, inputs),
                "output_type": tensor_kind(node.meta.get("val")),
            }
        )
    body = {
        "version": "FOUNDRY_LOCAL_EXACT_DAG_TOOL_V1",
        "inputs": inputs,
        "nodes": body_nodes,
        "outputs": [{"node": index} for index in outputs],
    }
    return topology, body


def chain(topology: dict[str, Any]) -> bool:
    count = topology["node_count"]
    return (
        topology["output_indices"] == [count - 1]
        and topology["internal_edges"]
        == [[index, index + 1] for index in range(count - 1)]
    )


def load() -> list[dict[str, Any]]:
    expected_pool = json.loads((HERE / "results/pareto_tool_pool.json").read_text())
    expected = {row["graph_id"]: row for row in expected_pool["calibration_graphs"]}
    rows, unsupported = workloads()
    historical = json.loads(
        (HERE / "results/phase63_pareto_motif_calibration.json").read_text()
    )
    if unsupported != historical["unsupported_families"]:
        raise IndependentGrammarReject("unsupported workload census")
    result = []
    for suite, workload in rows:
        family = workload["family"]
        graph_id = f"{suite}:{family}"
        exported = torch.export.export(
            workload["model"], workload["args"], workload["kwargs"], strict=True
        )
        graph = exported.module().graph
        graph_sha = hashlib.sha256(str(graph).encode()).hexdigest()
        if graph_id not in expected or graph_sha != expected[graph_id]["graph_sha256"]:
            raise IndependentGrammarReject("graph identity")
        nodes = nodes_of(graph)
        motifs = []
        unsupported_count = 0
        for indices in connected_combinations(nodes):
            try:
                topology, body = describe(nodes, indices)
            except IndependentGrammarReject:
                unsupported_count += 1
                continue
            motifs.append(
                {
                    "node_names": [nodes[index].name for index in indices],
                    "topology": topology,
                    "topology_sha256": digest(topology),
                    "body": body,
                    "body_sha256": digest(body),
                    "fixed_chain": chain(topology),
                }
            )
        result.append(
            {
                "graph_id": graph_id,
                "suite": suite,
                "family": family,
                "repository": workload.get(
                    "repository", old_repository(suite, family)
                ),
                "semantic_domain": workload.get("semantic_domain", family),
                "assignment": graph_assignment(graph_id),
                "graph_sha256": graph_sha,
                "eligible_nodes": len(nodes),
                "connected_subsets": len(motifs) + unsupported_count,
                "encoded_motifs": len(motifs),
                "unsupported_motifs": unsupported_count,
                "motifs": motifs,
                "graph": graph,
            }
        )
    return sorted(result, key=lambda row: row["graph_id"])


def units(body: dict[str, Any]) -> int:
    return len(body["nodes"]) + len(body["inputs"]) + len(body["outputs"])


def independent_run() -> dict[str, Any]:
    records = load()
    training = [row for row in records if row["assignment"] == "training"]
    heldout = [row for row in records if row["assignment"] == "heldout"]
    topology_rows: dict[str, dict[str, Any]] = {}
    for row in training:
        for motif in row["motifs"]:
            group = topology_rows.setdefault(
                motif["topology_sha256"],
                {"value": motif["topology"], "count": 0, "families": set()},
            )
            group["count"] += 1
            group["families"].add(row["family"])
    productions = {}
    for identifier, group in topology_rows.items():
        value = group["value"]
        structural = (
            value["node_count"]
            + len(value["internal_edges"])
            + len(value["output_indices"])
        )
        gain = group["count"] * structural - (structural + group["count"])
        if group["count"] >= 3 and len(group["families"]) >= 2 and gain > 0:
            productions[identifier] = value
    body_rows: dict[str, dict[str, Any]] = {}
    for row in training:
        for motif in row["motifs"]:
            if motif["topology_sha256"] not in productions:
                continue
            group = body_rows.setdefault(
                motif["body_sha256"],
                {
                    "body": motif["body"],
                    "topology": motif["topology_sha256"],
                    "count": 0,
                    "families": set(),
                },
            )
            group["count"] += 1
            group["families"].add(row["family"])
    tools = {}
    for identifier, group in body_rows.items():
        gain = group["count"] * units(group["body"]) - (
            units(group["body"]) + group["count"]
        )
        if group["count"] >= 2 and len(group["families"]) >= 2 and gain > 0:
            tools[identifier] = group
    chain_tools = {
        key: value
        for key, value in tools.items()
        if chain(productions[value["topology"]])
    }
    candidate_matches = []
    chain_matches = []
    for row in heldout:
        for motif in row["motifs"]:
            if motif["body_sha256"] in tools:
                candidate_matches.append(
                    (row["graph_id"], motif["body_sha256"], motif["node_names"])
                )
            if motif["body_sha256"] in chain_tools:
                chain_matches.append(
                    (row["graph_id"], motif["body_sha256"], motif["node_names"])
                )
    fixed = json.loads((HERE / "ATEN_FIXED_PORTFOLIO_V2.json").read_text())
    fixed_sequences = {tuple(tool["targets"]) for tool in fixed["tools"]}
    fixed_coverage: set[str] = set()
    fixed_count = 0
    for row in heldout:
        nodes = nodes_of(row["graph"])
        allowed = set(nodes)
        for tool in fixed["tools"]:
            kind = {
                "rank": tool["rank"],
                "dtype": tool["dtype"],
                "layout": tool["layout"],
            }

            def walk(path: list[Node]) -> None:
                nonlocal fixed_count
                index = len(path) - 1
                if (
                    str(path[-1].target) != tool["targets"][index]
                    or tensor_kind(path[-1].meta.get("val")) != kind
                ):
                    return
                if len(path) == len(tool["targets"]):
                    fixed_count += 1
                    fixed_coverage.update(
                        f"{row['graph_id']}:{node.name}" for node in path
                    )
                    return
                for user in sorted(path[-1].users, key=lambda item: item.name):
                    if user in allowed and user not in path:
                        walk(path + [user])

            for node in nodes:
                walk([node])
    candidate_coverage = {
        f"{graph_id}:{node}"
        for graph_id, _, names in candidate_matches
        for node in names
    }
    chain_coverage = {
        f"{graph_id}:{node}"
        for graph_id, _, names in chain_matches
        for node in names
    }
    candidate_only = sorted(
        identifier
        for identifier, tool in tools.items()
        if not chain(productions[tool["topology"]])
        and any(match[1] == identifier for match in candidate_matches)
        and tuple(node["target"] for node in tool["body"]["nodes"])
        not in fixed_sequences
    )
    candidate_only_matches = [
        match for match in candidate_matches if match[1] in candidate_only
    ]
    candidate_only_nodes = candidate_coverage - chain_coverage - fixed_coverage
    return {
        "graph_record_digest": digest(
            [
                {
                    key: value
                    for key, value in row.items()
                    if key not in {"graph", "motifs"}
                }
                for row in records
            ]
        ),
        "production_ids": sorted(productions),
        "non_chain_production_ids": sorted(
            key for key, value in productions.items() if not chain(value)
        ),
        "multi_output_production_ids": sorted(
            key
            for key, value in productions.items()
            if len(value["output_indices"]) > 1
        ),
        "tool_ids": sorted(tools),
        "chain_tool_ids": sorted(chain_tools),
        "candidate_only_tool_ids": candidate_only,
        "candidate_only_node_ids": sorted(candidate_only_nodes),
        "summary": {
            "training_graphs": len(training),
            "heldout_graphs": len(heldout),
            "training_connected_subsets": sum(
                row["connected_subsets"] for row in training
            ),
            "heldout_connected_subsets": sum(
                row["connected_subsets"] for row in heldout
            ),
            "topology_groups": len(topology_rows),
            "selected_productions": len(productions),
            "selected_non_chain_productions": sum(
                not chain(value) for value in productions.values()
            ),
            "selected_multi_output_productions": sum(
                len(value["output_indices"]) > 1
                for value in productions.values()
            ),
            "selected_tools": len(tools),
            "selected_non_chain_tools": sum(
                not chain(productions[tool["topology"]])
                for tool in tools.values()
            ),
            "chain_control_tools": len(chain_tools),
            "heldout_candidate_matches": len(candidate_matches),
            "heldout_chain_matches": len(chain_matches),
            "heldout_fixed_matches": fixed_count,
            "candidate_only_heldout_tools": len(candidate_only),
            "candidate_only_heldout_matches": len(candidate_only_matches),
            "candidate_unique_heldout_nodes": len(candidate_coverage),
            "chain_unique_heldout_nodes": len(chain_coverage),
            "fixed_unique_heldout_nodes": len(fixed_coverage),
            "candidate_only_heldout_nodes": len(candidate_only_nodes),
        },
    }


def verify_ledger(ledger: dict[str, Any], protocol: dict[str, Any]) -> None:
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
    if set(ledger) != expected_fields or ledger["version"] != "FOUNDRY_LOCAL_GRAMMAR_EMERGENCE_LEDGER_V1":
        raise IndependentGrammarReject("ledger schema")
    records = ledger["graph_records"]
    expected_graphs = {
        row["graph_id"]: row["graph_sha256"]
        for row in json.loads(
            (HERE / "results/pareto_tool_pool.json").read_text()
        )["calibration_graphs"]
    }
    if (
        len(records) != 23
        or {row["graph_id"] for row in records} != set(expected_graphs)
        or any(
            row["graph_sha256"] != expected_graphs[row["graph_id"]]
            for row in records
        )
        or sum(row["assignment"] == "training" for row in records) != 16
        or sum(row["assignment"] == "heldout" for row in records) != 7
        or sorted(
            row["graph_id"] for row in records if row["assignment"] == "heldout"
        )
        != sorted(protocol["split"]["heldout_graph_ids"])
    ):
        raise IndependentGrammarReject("split ledger")
    for key in (
        "production_ids",
        "non_chain_production_ids",
        "multi_output_production_ids",
        "tool_ids",
        "chain_tool_ids",
        "candidate_only_tool_ids",
        "candidate_only_node_ids",
    ):
        values = ledger[key]
        if values != sorted(set(values)) or any(
            re.fullmatch(r"[0-9a-f]{64}", value) is None for value in values
        ):
            raise IndependentGrammarReject(f"identifier list {key}")
    production_map = {}
    for row in ledger["production_records"]:
        if (
            set(row) != {"topology_sha256", "topology", "fixed_chain"}
            or row["topology_sha256"] != digest(row["topology"])
            or row["topology_sha256"] in production_map
        ):
            raise IndependentGrammarReject("production record")
        value = row["topology"]
        if set(value) != {
            "node_count",
            "internal_edges",
            "external_input_uses",
            "output_indices",
        }:
            raise IndependentGrammarReject("topology fields")
        count = value["node_count"]
        edges = value["internal_edges"]
        outputs = value["output_indices"]
        if (
            type(count) is not int
            or not 2 <= count <= 5
            or len(value["external_input_uses"]) != count
            or any(
                type(item) is not int or item < 0
                for item in value["external_input_uses"]
            )
            or edges
            != [list(edge) for edge in sorted({tuple(edge) for edge in edges})]
            or any(
                type(edge) is not list
                or len(edge) != 2
                or not all(type(item) is int for item in edge)
                or not 0 <= edge[0] < edge[1] < count
                for edge in edges
            )
            or outputs != sorted(set(outputs))
            or any(type(item) is not int or not 0 <= item < count for item in outputs)
        ):
            raise IndependentGrammarReject("topology values")
        connected = {0}
        while True:
            expanded = connected | {
                right
                for left, right in edges
                if left in connected
            } | {
                left
                for left, right in edges
                if right in connected
            }
            if expanded == connected:
                break
            connected = expanded
        sinks = {
            index
            for index in range(count)
            if all(left != index for left, _ in edges)
        }
        if (
            len(connected) != count
            or not sinks <= set(outputs)
            or row["fixed_chain"] != chain(value)
        ):
            raise IndependentGrammarReject("topology connectivity")
        production_map[row["topology_sha256"]] = row
    if sorted(production_map) != ledger["production_ids"]:
        raise IndependentGrammarReject("production record set")
    tool_map = {}

    def refs(value: object, label: str) -> set[int]:
        if isinstance(value, dict):
            result = {value[label]} if set(value) == {label} else set()
            for child in value.values():
                result.update(refs(child, label))
            return result
        if isinstance(value, list):
            result: set[int] = set()
            for child in value:
                result.update(refs(child, label))
            return result
        return set()

    for row in ledger["tool_records"]:
        if (
            set(row)
            != {
                "body_sha256",
                "body",
                "topology_sha256",
                "fixed_chain",
            }
            or row["body_sha256"] != digest(row["body"])
            or row["body_sha256"] in tool_map
            or row["topology_sha256"] not in production_map
        ):
            raise IndependentGrammarReject("tool record")
        body = row["body"]
        derived = {
            "node_count": len(body["nodes"]),
            "internal_edges": sorted(
                [producer, consumer]
                for consumer, node in enumerate(body["nodes"])
                for producer in (
                    refs(node["args"], "node")
                    | refs(node["kwargs"], "node")
                )
            ),
            "external_input_uses": [
                len(
                    refs(node["args"], "input")
                    | refs(node["kwargs"], "input")
                )
                for node in body["nodes"]
            ],
            "output_indices": [item["node"] for item in body["outputs"]],
        }
        if (
            derived != production_map[row["topology_sha256"]]["topology"]
            or row["fixed_chain"]
            != production_map[row["topology_sha256"]]["fixed_chain"]
        ):
            raise IndependentGrammarReject("tool topology")
        tool_map[row["body_sha256"]] = row
    if sorted(tool_map) != ledger["tool_ids"]:
        raise IndependentGrammarReject("tool record set")
    heldout = {
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
            or match["graph_id"] not in heldout
            or match["body_sha256"] not in tool_map
            or match["topology_sha256"]
            != tool_map[match["body_sha256"]]["topology_sha256"]
            or len(match["node_names"])
            != len(tool_map[match["body_sha256"]]["body"]["nodes"])
            or len(match["node_names"]) != len(set(match["node_names"]))
        ):
            raise IndependentGrammarReject("heldout match")
    candidate_only_ids = set(ledger["candidate_only_tool_ids"])
    if (
        not candidate_only_ids <= set(tool_map)
        or any(tool_map[identifier]["fixed_chain"] for identifier in candidate_only_ids)
        or ledger["candidate_only_matches"]
        != [
            match
            for match in ledger["heldout_matches"]
            if match["body_sha256"] in candidate_only_ids
        ]
    ):
        raise IndependentGrammarReject("candidate-only match relation")
    if not set(ledger["non_chain_production_ids"]) <= set(
        ledger["production_ids"]
    ) or not set(ledger["chain_tool_ids"]) <= set(ledger["tool_ids"]):
        raise IndependentGrammarReject("set relation")
    summary = ledger["summary"]
    relations = {
        "training_graphs": 16,
        "heldout_graphs": 7,
        "selected_productions": len(ledger["production_ids"]),
        "selected_non_chain_productions": len(
            ledger["non_chain_production_ids"]
        ),
        "selected_multi_output_productions": len(
            ledger["multi_output_production_ids"]
        ),
        "selected_tools": len(ledger["tool_ids"]),
        "chain_control_tools": len(ledger["chain_tool_ids"]),
        "heldout_candidate_matches": len(ledger["heldout_matches"]),
        "candidate_only_heldout_tools": len(
            ledger["candidate_only_tool_ids"]
        ),
        "candidate_only_heldout_matches": len(
            ledger["candidate_only_matches"]
        ),
        "candidate_only_heldout_nodes": len(
            ledger["candidate_only_node_ids"]
        ),
        "causal_candidate_only_matches_after_non_chain_removal": 0,
    }
    if any(summary.get(key) != value for key, value in relations.items()):
        raise IndependentGrammarReject("summary relation")
    if (
        set(ledger["per_tool_causal_losses"])
        != set(ledger["candidate_only_tool_ids"])
        or any(
            value <= 0 for value in ledger["per_tool_causal_losses"].values()
        )
        or ledger["claims"]
        != {
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
    ):
        raise IndependentGrammarReject("causal or claim relation")
