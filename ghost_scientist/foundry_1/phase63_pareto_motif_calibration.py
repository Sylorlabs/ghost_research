#!/usr/bin/env python3
"""Enumerate full typed recurring motifs across the 23 calibration graphs."""

from __future__ import annotations

import collections
import hashlib
import importlib
import json
import pathlib
import sys
from typing import Any

import torch
from torch.fx import Node


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
POOL = RESULTS / "pareto_tool_pool.json"
RESULT = RESULTS / "phase63_pareto_motif_calibration.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"
FORBIDDEN_FRAGMENT = "external_validation_" + "v6"
MIN_NODES = 2
MAX_NODES = 4
MIN_FAMILIES = 2
MIN_REPOSITORIES = 2
opened_paths: list[str] = []


def audit(event: str, args: tuple[object, ...]) -> None:
    if event == "open" and args and isinstance(args[0], (str, bytes)):
        opened_paths.append(str(args[0]))


sys.addaudithook(audit)


class UnsupportedTerm(ValueError):
    pass


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def digest(value: object) -> str:
    return hashlib.sha256(canonical(value).encode()).hexdigest()


def tensor_type(value: object) -> dict[str, object] | None:
    if not isinstance(value, torch.Tensor):
        return None
    return {
        "rank": len(value.shape),
        "dtype": str(value.dtype),
        "layout": str(value.layout),
    }


def encode_literal(value: object) -> dict[str, object]:
    if value is None or type(value) in {bool, int, float, str}:
        return {"literal": value}
    if isinstance(value, torch.dtype):
        return {"torch_dtype": str(value)}
    if isinstance(value, torch.device):
        return {"torch_device": str(value)}
    raise UnsupportedTerm(f"unsupported literal {type(value).__name__}")


def encode_term(
    value: object,
    internal: dict[Node, int],
    external: dict[Node, int],
    inputs: list[dict[str, object]],
) -> dict[str, object]:
    if isinstance(value, Node):
        if value in internal:
            return {"node": internal[value]}
        kind = tensor_type(value.meta.get("val"))
        if kind is None:
            raise UnsupportedTerm("external node is not a typed tensor")
        if value not in external:
            external[value] = len(inputs)
            inputs.append({"type": kind})
        return {"input": external[value]}
    if isinstance(value, list):
        return {
            "list": [
                encode_term(item, internal, external, inputs) for item in value
            ]
        }
    if isinstance(value, tuple):
        return {
            "tuple": [
                encode_term(item, internal, external, inputs) for item in value
            ]
        }
    if isinstance(value, dict):
        return {
            "dict": [
                [
                    encode_literal(key),
                    encode_term(item, internal, external, inputs),
                ]
                for key, item in sorted(value.items(), key=lambda pair: str(pair[0]))
            ]
        }
    return encode_literal(value)


def construct_body(path: list[Node]) -> dict[str, object]:
    internal = {node: index for index, node in enumerate(path)}
    external: dict[Node, int] = {}
    inputs: list[dict[str, object]] = []
    nodes = []
    for node in path:
        kind = tensor_type(node.meta.get("val"))
        if kind is None or not str(node.target).startswith("aten."):
            raise UnsupportedTerm("path contains non-typed or non-ATen node")
        nodes.append(
            {
                "target": str(node.target),
                "args": encode_term(node.args, internal, external, inputs),
                "kwargs": encode_term(node.kwargs, internal, external, inputs),
                "output_type": kind,
            }
        )
    return {
        "version": "FOUNDRY_PARETO_TOOL_V1",
        "inputs": inputs,
        "nodes": nodes,
        "outputs": [{"node": len(nodes) - 1}],
    }


def paths(graph: torch.fx.Graph) -> list[list[Node]]:
    eligible = {
        node
        for node in graph.nodes
        if node.op == "call_function"
        and str(node.target).startswith("aten.")
        and tensor_type(node.meta.get("val")) is not None
    }
    found: list[list[Node]] = []

    def extend(path: list[Node]) -> None:
        if len(path) >= MIN_NODES:
            found.append(list(path))
        if len(path) == MAX_NODES:
            return
        for user in sorted(path[-1].users, key=lambda item: item.name):
            if user in eligible and user not in path:
                extend(path + [user])

    for node in sorted(eligible, key=lambda item: item.name):
        extend([node])
    return found


def old_repository(suite: str, family: str) -> str:
    if suite == "validation_v4":
        return {
            "healthcare_dense_graph_convolution": "sunlabuiuc/PyHealth",
            "robust_gaussian_graph_convolution": "DSE-MSU/DeepRobust",
        }.get(family, "pytorch/examples")
    return "pytorch/examples"


def workloads() -> tuple[list[tuple[str, dict[str, Any]]], list[dict[str, str]]]:
    rows: list[tuple[str, dict[str, Any]]] = []
    unsupported: list[dict[str, str]] = []
    for suite, module_name in (
        ("original_external", "phase15_external_application_trace"),
        ("validation_v1", "external_validation_runtime"),
        ("validation_v3", "external_validation_v3_runtime"),
        ("validation_v4", "external_validation_v4_runtime"),
    ):
        module = importlib.import_module(module_name)
        rows.extend((suite, item) for item in module.instantiate())
    v2 = importlib.import_module("external_validation_v2_2_runtime")
    for family, construct in v2.constructors():
        try:
            rows.append(("validation_v2", construct()))
        except Exception as exc:
            unsupported.append(
                {
                    "suite": "validation_v2",
                    "family": family,
                    "exception_type": type(exc).__name__,
                }
            )
    v5 = importlib.import_module("external_validation_v5_runtime")
    rows.extend(("validation_v5_calibration", item) for item in v5.instantiate())
    return rows, unsupported


def run() -> None:
    fixed_raw = FIXED.read_bytes()
    fixed = json.loads(fixed_raw)
    fixed_sequences = {
        tuple(item["targets"]): item["name"] for item in fixed["tools"]
    }
    result_freeze = json.loads(
        (RESULTS / "diversity_result_v1_freeze.json").read_text()
    )
    if result_freeze["classification"] != "PROSPECTIVE_VALID_NEGATIVE":
        raise RuntimeError("v5 is not frozen before calibration reuse")

    groups: dict[str, dict[str, Any]] = {}
    graphs = []
    instantiated, unsupported = workloads()
    for suite, workload in instantiated:
        family = workload["family"]
        repository = workload.get(
            "repository", old_repository(suite, family)
        )
        domain = workload.get("semantic_domain", family)
        try:
            exported = torch.export.export(
                workload["model"],
                workload["args"],
                workload["kwargs"],
                strict=True,
            )
            graph = exported.module().graph
        except Exception as exc:
            unsupported.append(
                {
                    "suite": suite,
                    "family": family,
                    "exception_type": type(exc).__name__,
                }
            )
            continue
        graph_id = f"{suite}:{family}"
        graph_paths = paths(graph)
        graphs.append(
            {
                "graph_id": graph_id,
                "suite": suite,
                "family": family,
                "repository": repository,
                "semantic_domain": domain,
                "graph_sha256": hashlib.sha256(
                    str(graph).encode()
                ).hexdigest(),
                "eligible_nodes": sum(
                    node.op == "call_function"
                    and str(node.target).startswith("aten.")
                    and tensor_type(node.meta.get("val")) is not None
                    for node in graph.nodes
                ),
                "paths_enumerated": len(graph_paths),
            }
        )
        for path in graph_paths:
            try:
                body = construct_body(path)
            except UnsupportedTerm:
                continue
            tool_id = digest(body)
            group = groups.setdefault(
                tool_id, {"body": body, "occurrences": []}
            )
            group["occurrences"].append(
                {
                    "graph_id": graph_id,
                    "suite": suite,
                    "family": family,
                    "repository": repository,
                    "semantic_domain": domain,
                    "nodes": [node.name for node in path],
                }
            )

    tools = []
    rejections: collections.Counter[str] = collections.Counter()
    for tool_id, group in sorted(groups.items()):
        occurrences = group["occurrences"]
        families = sorted({item["family"] for item in occurrences})
        repositories = sorted(
            {item["repository"] for item in occurrences}
        )
        domains = sorted(
            {item["semantic_domain"] for item in occurrences}
        )
        suites = sorted({item["suite"] for item in occurrences})
        body = group["body"]
        structural_units = len(body["nodes"]) + len(body["inputs"])
        raw_cost = structural_units * len(occurrences)
        tool_cost = structural_units + len(occurrences)
        gain = raw_cost - tool_cost
        if len(families) < MIN_FAMILIES:
            rejections["fewer_than_two_families"] += 1
            continue
        if len(repositories) < MIN_REPOSITORIES:
            rejections["fewer_than_two_repositories"] += 1
            continue
        if gain <= 0:
            rejections["nonpositive_description_length_gain"] += 1
            continue
        sequence = tuple(node["target"] for node in body["nodes"])
        tools.append(
            {
                "tool_id": tool_id,
                **body,
                "training": {
                    "occurrence_count": len(occurrences),
                    "family_count": len(families),
                    "repository_count": len(repositories),
                    "semantic_domain_count": len(domains),
                    "suite_count": len(suites),
                    "structural_units": structural_units,
                    "raw_cost": raw_cost,
                    "tool_cost": tool_cost,
                    "description_length_gain": gain,
                    "fixed_target_sequence_duplicate": sequence
                    in fixed_sequences,
                    "fixed_name": fixed_sequences.get(sequence),
                    "families": families,
                    "repositories": repositories,
                    "semantic_domains": domains,
                    "suites": suites,
                    "occurrences": occurrences,
                },
            }
        )
    tools.sort(
        key=lambda item: (
            -item["training"]["description_length_gain"],
            -item["training"]["repository_count"],
            item["tool_id"],
        )
    )
    forbidden_opens = sorted(
        {path for path in opened_paths if FORBIDDEN_FRAGMENT in path}
    )
    if forbidden_opens:
        raise RuntimeError("validation-v6 path accessed during calibration")
    pool = {
        "version": "FOUNDRY_PARETO_TOOL_POOL_V1",
        "construction": {
            "algorithm": "all_connected_typed_dag_motifs_mdl",
            "llm_calls": 0,
            "supplied_tool_forms": 0,
            "minimum_nodes": MIN_NODES,
            "maximum_nodes": MAX_NODES,
            "minimum_families": MIN_FAMILIES,
            "minimum_repositories": MIN_REPOSITORIES,
            "validation_v6_accessed": False,
        },
        "fixed_portfolio_sha256": hashlib.sha256(fixed_raw).hexdigest(),
        "calibration_graphs": graphs,
        "unsupported_families": unsupported,
        "tools": tools,
    }
    POOL.write_text(canonical(pool) + "\n")
    payload = {
        "version": "FOUNDRY_PARETO_MOTIF_CALIBRATION_V1",
        "status": "PARETO_MOTIF_POOL_READY",
        "classification": "TWENTY_THREE_GRAPH_CALIBRATION_ONLY",
        "graphs": len(graphs),
        "repositories": len({item["repository"] for item in graphs}),
        "semantic_domains": len(
            {item["semantic_domain"] for item in graphs}
        ),
        "paths_enumerated": sum(
            item["paths_enumerated"] for item in graphs
        ),
        "exact_body_groups": len(groups),
        "eligible_tools": len(tools),
        "fixed_sequence_duplicates": sum(
            item["training"]["fixed_target_sequence_duplicate"]
            for item in tools
        ),
        "unsupported_families": unsupported,
        "pool_sha256": hashlib.sha256(POOL.read_bytes()).hexdigest(),
        "rejections": dict(sorted(rejections.items())),
        "access_audit": {
            "file_open_events": len(opened_paths),
            "forbidden_path_fragment": FORBIDDEN_FRAGMENT,
            "forbidden_open_count": 0,
        },
        "prospective_claim_allowed": False,
    }
    RESULT.write_text(canonical(payload) + "\n")
    print(
        "FOUNDRY_PHASE63_PARETO_MOTIF_CALIBRATION_PASS"
        f" graphs={len(graphs)}"
        f" paths={payload['paths_enumerated']}"
        f" groups={len(groups)}"
        f" tools={len(tools)}"
        f" fixed_duplicates={payload['fixed_sequence_duplicates']}"
    )


if __name__ == "__main__":
    run()
