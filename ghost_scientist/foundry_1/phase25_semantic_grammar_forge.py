#!/usr/bin/env python3
"""LLM-free demand-driven construction of executable typed DAG tool grammar."""

from __future__ import annotations

import collections
import hashlib
import json
import pathlib
from typing import Any

import torch
from torch.fx import Node

from external_validation_v2_2_runtime import constructors
from independent_aten_tool_evaluator import parse_library
from phase21_prospective_aten_trial import match_with_cost


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
PRIOR_LIBRARY = RESULTS / "forged_aten_tools.json"
OUTPUT_LIBRARY = RESULTS / "forged_semantic_tools.json"
MIN_NODES = 2
MAX_NODES = 4
MIN_OCCURRENCES = 2


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
        return {"list": [encode_term(item, internal, external, inputs) for item in value]}
    if isinstance(value, tuple):
        return {
            "tuple": [encode_term(item, internal, external, inputs) for item in value]
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
    for index, node in enumerate(path):
        if not str(node.target).startswith("aten."):
            raise UnsupportedTerm("semantic node target is not ATen")
        args = encode_term(node.args, internal, external, inputs)
        kwargs = encode_term(node.kwargs, internal, external, inputs)
        for term in (args, kwargs):
            raw = canonical(term)
            for later in range(index, len(path)):
                if f'"node":{later}' in raw:
                    raise UnsupportedTerm("forward node reference")
        output_type = tensor_type(node.meta.get("val"))
        if output_type is None:
            raise UnsupportedTerm("semantic node output is not a typed tensor")
        nodes.append(
            {
                "target": str(node.target),
                "args": args,
                "kwargs": kwargs,
                "output_type": output_type,
            }
        )
    return {
        "version": "FOUNDRY_SEMANTIC_TOOL_V1",
        "inputs": inputs,
        "nodes": nodes,
        "outputs": [{"node": len(nodes) - 1}],
    }


def paths(graph: torch.fx.Graph, uncovered: set[Node]) -> list[list[Node]]:
    eligible = {
        node
        for node in graph.nodes
        if node.op == "call_function"
        and str(node.target).startswith("aten.")
        and tensor_type(node.meta.get("val")) is not None
        and node in uncovered
    }
    found = []

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


def run() -> None:
    prior_raw = PRIOR_LIBRARY.read_bytes()
    prior = parse_library(prior_raw)
    groups: dict[str, dict[str, Any]] = {}
    graphs = []
    unsupported_families = []
    total_uncovered = 0
    total_covered = 0
    for family, construct in constructors():
        try:
            workload = construct()
            exported = torch.export.export(
                workload["model"], workload["args"], workload["kwargs"], strict=True
            )
            module = exported.module()
        except Exception as exc:
            unsupported_families.append(
                {"family": family, "exception_type": type(exc).__name__}
            )
            continue
        covered: set[Node] = set()
        for old_tool in prior["tools"]:
            matches, _, _ = match_with_cost(old_tool, module.graph)
            for match in matches:
                covered.update(match)
        eligible = {
            node
            for node in module.graph.nodes
            if node.op == "call_function"
            and str(node.target).startswith("aten.")
            and tensor_type(node.meta.get("val")) is not None
        }
        uncovered = eligible - covered
        total_covered += len(eligible & covered)
        total_uncovered += len(uncovered)
        graphs.append(
            {
                "family": family,
                "graph_sha256": hashlib.sha256(str(module.graph).encode()).hexdigest(),
                "eligible_nodes": len(eligible),
                "prior_covered_nodes": len(eligible & covered),
                "uncovered_nodes": len(uncovered),
            }
        )
        for path in paths(module.graph, uncovered):
            try:
                body = construct_body(path)
            except UnsupportedTerm:
                continue
            key = digest(body)
            group = groups.setdefault(key, {"body": body, "occurrences": []})
            group["occurrences"].append(
                {
                    "family": family,
                    "nodes": [node.name for node in path],
                }
            )

    candidates = []
    rejections = collections.Counter()
    for key, group in sorted(groups.items()):
        body = group["body"]
        occurrences = group["occurrences"]
        if len(occurrences) < MIN_OCCURRENCES:
            rejections["insufficient_occurrences"] += 1
            continue
        structural_units = len(body["nodes"]) + len(body["inputs"])
        raw_cost = structural_units * len(occurrences)
        tool_cost = structural_units + len(occurrences)
        gain = raw_cost - tool_cost
        if gain <= 0:
            rejections["nonpositive_description_length_gain"] += 1
            continue
        candidates.append(
            {
                "tool_id": key,
                **body,
                "training": {
                    "occurrence_count": len(occurrences),
                    "family_count": len(
                        {item["family"] for item in occurrences}
                    ),
                    "structural_units": structural_units,
                    "raw_cost": raw_cost,
                    "tool_cost": tool_cost,
                    "description_length_gain": gain,
                    "occurrences": occurrences,
                },
            }
        )
    candidates.sort(
        key=lambda item: (
            -item["training"]["description_length_gain"],
            -len(item["nodes"]),
            item["tool_id"],
        )
    )
    # Retain overlapping positive-gain grammars. The prospective ledger charges
    # every definition, so nested alternatives cannot create free coverage.
    selected = candidates
    if not selected:
        raise RuntimeError("semantic grammar forge produced no selected tool")

    library = {
        "version": "FOUNDRY_SEMANTIC_TOOL_LIBRARY_V1",
        "construction": {
            "algorithm": "uncovered_connected_dag_boundary_inference_mdl",
            "llm_calls": 0,
            "supplied_tool_forms": 0,
            "operation_targets_chosen_from_observed_graphs": True,
            "boundary_grammar_inferred": True,
            "minimum_nodes": MIN_NODES,
            "maximum_nodes": MAX_NODES,
            "minimum_occurrences": MIN_OCCURRENCES,
            "validation_graphs_accessed": False,
        },
        "prior_library_sha256": hashlib.sha256(prior_raw).hexdigest(),
        "calibration_graphs": graphs,
        "unsupported_families": unsupported_families,
        "tools": selected,
    }
    OUTPUT_LIBRARY.write_text(canonical(library) + "\n", encoding="utf-8")
    result = {
        "version": "FOUNDRY_SEMANTIC_GRAMMAR_FORGE_RESULT_V1",
        "status": "SEMANTIC_GRAMMAR_FORGE_READY",
        "candidate_patterns": len(groups),
        "positive_gain_candidates": len(candidates),
        "tools_forged": len(selected),
        "description_length_gain": sum(
            tool["training"]["description_length_gain"] for tool in selected
        ),
        "calibration_families": len(graphs),
        "prior_covered_nodes": total_covered,
        "uncovered_nodes": total_uncovered,
        "library_sha256": hashlib.sha256(OUTPUT_LIBRARY.read_bytes()).hexdigest(),
        "rejections": dict(sorted(rejections.items())),
        "autonomy_boundary": {
            "llm_calls": 0,
            "supplied_tool_forms": 0,
            "targets_chosen_by_machine": True,
            "argument_grammar_constructed_by_machine": True,
            "validation_accessed": False,
        },
    }
    (RESULTS / "phase25_semantic_grammar_forge.json").write_text(
        canonical(result) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE25_SEMANTIC_FORGE_PASS"
        f" candidates={len(groups)}"
        f" positive={len(candidates)}"
        f" tools={len(selected)}"
        f" gain={result['description_length_gain']}"
        f" uncovered={total_uncovered}"
    )


if __name__ == "__main__":
    run()
