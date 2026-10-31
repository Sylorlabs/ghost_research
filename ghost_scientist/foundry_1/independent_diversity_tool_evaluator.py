#!/usr/bin/env python3
"""Independent strict parser, matcher, and interpreter for diversity tools."""

from __future__ import annotations

import copy
import hashlib
import importlib
import json
import math
import pathlib
from typing import Any

import torch
from torch.fx import Node


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
LIBRARY = RESULTS / "forged_diversity_tools.json"


class ContractError(ValueError):
    pass


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def exact(value: object, keys: set[str], context: str) -> dict[str, Any]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ContractError(f"{context} fields are not exact")
    return value


def parse_type(value: object, context: str) -> None:
    row = exact(value, {"rank", "dtype", "layout"}, context)
    if type(row["rank"]) is not int or not 0 <= row["rank"] <= 8:
        raise ContractError(f"{context} rank invalid")
    if row["dtype"] not in {
        "torch.float16",
        "torch.float32",
        "torch.float64",
        "torch.int32",
        "torch.int64",
        "torch.bool",
    }:
        raise ContractError(f"{context} dtype invalid")
    if row["layout"] not in {
        "torch.strided",
        "torch.sparse_coo",
        "torch.sparse_csr",
    }:
        raise ContractError(f"{context} layout invalid")


def parse_term(
    value: object, inputs: int, node_limit: int, context: str
) -> None:
    if not isinstance(value, dict) or len(value) != 1:
        raise ContractError(f"{context} term is not tagged")
    tag, item = next(iter(value.items()))
    if tag == "input":
        if type(item) is not int or not 0 <= item < inputs:
            raise ContractError(f"{context} input reference invalid")
    elif tag == "node":
        if type(item) is not int or not 0 <= item < node_limit:
            raise ContractError(f"{context} node reference invalid")
    elif tag == "literal":
        if item is not None and type(item) not in {bool, int, float, str}:
            raise ContractError(f"{context} literal invalid")
    elif tag == "torch_dtype":
        if item not in {
            "torch.float16",
            "torch.float32",
            "torch.float64",
            "torch.int32",
            "torch.int64",
            "torch.bool",
        }:
            raise ContractError(f"{context} torch dtype invalid")
    elif tag == "torch_device":
        if not isinstance(item, str) or len(item) > 64:
            raise ContractError(f"{context} torch device invalid")
    elif tag in {"list", "tuple"}:
        if not isinstance(item, list):
            raise ContractError(f"{context} sequence invalid")
        for index, child in enumerate(item):
            parse_term(child, inputs, node_limit, f"{context} {tag} {index}")
    elif tag == "dict":
        if not isinstance(item, list):
            raise ContractError(f"{context} dict invalid")
        for index, pair in enumerate(item):
            if not isinstance(pair, list) or len(pair) != 2:
                raise ContractError(f"{context} dict pair invalid")
            parse_term(pair[0], inputs, node_limit, f"{context} key {index}")
            parse_term(pair[1], inputs, node_limit, f"{context} value {index}")
    else:
        raise ContractError(f"{context} tag invalid")


def parse_library(raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ContractError("library is not JSON") from exc
    root = exact(
        value,
        {
            "version",
            "construction",
            "calibration_result_sha256",
            "calibration_freeze_records_sha256",
            "fixed_portfolio_sha256",
            "tools",
        },
        "library",
    )
    if root["version"] != "FOUNDRY_DIVERSITY_TOOL_LIBRARY_V1":
        raise ContractError("library version invalid")
    construction = exact(
        root["construction"],
        {
            "algorithm",
            "llm_calls",
            "supplied_tool_forms",
            "source_motifs",
            "minimum_families",
            "minimum_suites",
            "validation_source_or_runtime_accessed",
        },
        "construction",
    )
    if (
        construction["algorithm"]
        != "frozen_diversity_motif_exact_boundary_mdl"
        or construction["llm_calls"] != 0
        or construction["supplied_tool_forms"] != 0
        or construction["source_motifs"] != 6
        or construction["minimum_families"] != 3
        or construction["minimum_suites"] != 2
        or construction["validation_source_or_runtime_accessed"] is not False
    ):
        raise ContractError("construction boundary invalid")
    if not isinstance(root["tools"], list) or not root["tools"]:
        raise ContractError("diversity library empty")
    seen = set()
    for tool_index, tool in enumerate(root["tools"]):
        row = exact(
            tool,
            {"tool_id", "version", "inputs", "nodes", "outputs", "training"},
            f"tool {tool_index}",
        )
        if row["version"] != "FOUNDRY_DIVERSITY_TOOL_V1":
            raise ContractError(f"tool {tool_index} version invalid")
        if not isinstance(row["inputs"], list):
            raise ContractError(f"tool {tool_index} inputs invalid")
        for index, input_row in enumerate(row["inputs"]):
            item = exact(input_row, {"type"}, f"tool {tool_index} input {index}")
            parse_type(item["type"], f"tool {tool_index} input {index} type")
        if not isinstance(row["nodes"], list) or not 2 <= len(row["nodes"]) <= 3:
            raise ContractError(f"tool {tool_index} nodes invalid")
        for index, node in enumerate(row["nodes"]):
            item = exact(
                node,
                {"target", "args", "kwargs", "output_type"},
                f"tool {tool_index} node {index}",
            )
            if (
                not isinstance(item["target"], str)
                or not item["target"].startswith("aten.")
                or len(item["target"]) > 128
            ):
                raise ContractError(f"tool {tool_index} target invalid")
            parse_term(
                item["args"],
                len(row["inputs"]),
                index,
                f"tool {tool_index} args {index}",
            )
            parse_term(
                item["kwargs"],
                len(row["inputs"]),
                index,
                f"tool {tool_index} kwargs {index}",
            )
            parse_type(
                item["output_type"], f"tool {tool_index} output {index}"
            )
        if row["outputs"] != [{"node": len(row["nodes"]) - 1}]:
            raise ContractError(f"tool {tool_index} outputs invalid")
        training = exact(
            row["training"],
            {
                "source_pattern_sha256",
                "occurrence_count",
                "family_count",
                "suite_count",
                "structural_units",
                "raw_cost",
                "tool_cost",
                "description_length_gain",
                "families",
                "suites",
                "occurrences",
            },
            f"tool {tool_index} training",
        )
        if (
            not isinstance(training["source_pattern_sha256"], str)
            or len(training["source_pattern_sha256"]) != 64
            or training["family_count"] < 3
            or training["suite_count"] < 2
            or training["occurrence_count"] != len(training["occurrences"])
            or training["family_count"] != len(training["families"])
            or training["suite_count"] != len(training["suites"])
            or training["raw_cost"] - training["tool_cost"]
            != training["description_length_gain"]
            or training["description_length_gain"] <= 0
        ):
            raise ContractError(f"tool {tool_index} training invalid")
        body = {
            "version": row["version"],
            "inputs": row["inputs"],
            "nodes": row["nodes"],
            "outputs": row["outputs"],
        }
        identity = hashlib.sha256(canonical(body).encode()).hexdigest()
        if row["tool_id"] != identity or identity in seen:
            raise ContractError(f"tool {tool_index} identity invalid")
        seen.add(identity)
    return root


def node_type(node: Node) -> dict[str, object] | None:
    value = node.meta.get("val")
    if not isinstance(value, torch.Tensor):
        return None
    return {
        "rank": len(value.shape),
        "dtype": str(value.dtype),
        "layout": str(value.layout),
    }


def literal_value(term: dict[str, object]) -> object:
    tag, value = next(iter(term.items()))
    if tag == "literal":
        return value
    if tag == "torch_dtype":
        return getattr(torch, str(value).split(".", 1)[1])
    if tag == "torch_device":
        return torch.device(str(value))
    raise ContractError("term is not a literal")


def match_term(
    expected: dict[str, object],
    actual: object,
    path: list[Node],
    input_types: list[dict[str, object]],
    bindings: dict[int, Node],
) -> bool:
    tag, value = next(iter(expected.items()))
    if tag == "input":
        if not isinstance(actual, Node) or actual in path:
            return False
        slot = int(value)
        if node_type(actual) != input_types[slot]:
            return False
        if slot in bindings:
            return bindings[slot] is actual
        bindings[slot] = actual
        return True
    if tag == "node":
        return isinstance(actual, Node) and actual is path[int(value)]
    if tag in {"literal", "torch_dtype", "torch_device"}:
        expected_value = literal_value(expected)
        return type(actual) is type(expected_value) and actual == expected_value
    if tag == "list":
        return isinstance(actual, list) and len(actual) == len(value) and all(
            match_term(item, child, path, input_types, bindings)
            for item, child in zip(value, actual)
        )
    if tag == "tuple":
        return isinstance(actual, tuple) and len(actual) == len(value) and all(
            match_term(item, child, path, input_types, bindings)
            for item, child in zip(value, actual)
        )
    if tag == "dict":
        if not isinstance(actual, dict) or len(actual) != len(value):
            return False
        for key_term, child_term in value:
            key = literal_value(key_term)
            if key not in actual or not match_term(
                child_term, actual[key], path, input_types, bindings
            ):
                return False
        return True
    raise ContractError("unknown parsed term")


def semantic_matches(
    tool: dict[str, Any], graph: torch.fx.Graph
) -> tuple[list[tuple[list[Node], dict[int, Node]]], int, int]:
    expected_nodes = tool["nodes"]
    eligible = {
        node
        for node in graph.nodes
        if node.op == "call_function" and node_type(node) is not None
    }
    rows = []
    visits = 0
    edges = 0

    def extend(path: list[Node]) -> None:
        nonlocal edges
        expected = expected_nodes[len(path) - 1]
        actual = path[-1]
        if (
            str(actual.target) != expected["target"]
            or node_type(actual) != expected["output_type"]
        ):
            return
        if len(path) == len(expected_nodes):
            bindings: dict[int, Node] = {}
            input_types = [item["type"] for item in tool["inputs"]]
            for offset, node in enumerate(path):
                row = expected_nodes[offset]
                if not match_term(
                    row["args"], node.args, path, input_types, bindings
                ) or not match_term(
                    row["kwargs"], node.kwargs, path, input_types, bindings
                ):
                    return
            if len(bindings) == len(tool["inputs"]):
                rows.append((list(path), bindings))
            return
        for user in sorted(actual.users, key=lambda item: item.name):
            if user in eligible and user not in path:
                edges += 1
                extend(path + [user])

    for node in sorted(eligible, key=lambda item: item.name):
        visits += 1
        extend([node])
    return rows, visits, edges


class CapturingInterpreter(torch.fx.Interpreter):
    def __init__(self, module: torch.fx.GraphModule):
        super().__init__(module)
        self.values: dict[Node, object] = {}

    def run_node(self, node: Node) -> object:
        value = super().run_node(node)
        self.values[node] = value
        return value


def resolve_target(name: str) -> object:
    namespace, operation, overload = name.split(".")
    if namespace != "aten":
        raise ContractError("execution target is not ATen")
    return getattr(getattr(torch.ops.aten, operation), overload)


def execute_term(
    term: dict[str, object],
    inputs: list[object],
    nodes: list[object],
) -> object:
    tag, value = next(iter(term.items()))
    if tag == "input":
        return inputs[int(value)]
    if tag == "node":
        return nodes[int(value)]
    if tag in {"literal", "torch_dtype", "torch_device"}:
        return literal_value(term)
    if tag == "list":
        return [execute_term(item, inputs, nodes) for item in value]
    if tag == "tuple":
        return tuple(execute_term(item, inputs, nodes) for item in value)
    if tag == "dict":
        return {
            literal_value(key): execute_term(item, inputs, nodes)
            for key, item in value
        }
    raise ContractError("unknown execution term")


def execute_tool(tool: dict[str, Any], inputs: list[object]) -> object:
    values = []
    for node in tool["nodes"]:
        args = execute_term(node["args"], inputs, values)
        kwargs = execute_term(node["kwargs"], inputs, values)
        target = resolve_target(node["target"])
        values.append(target(*args, **kwargs))
    return values[tool["outputs"][0]["node"]]


def max_error(left: object, right: object) -> float:
    if isinstance(left, torch.Tensor) and isinstance(right, torch.Tensor):
        if left.shape != right.shape:
            return math.inf
        if left.numel() == 0:
            return 0.0
        if left.dtype == torch.bool or not left.dtype.is_floating_point:
            return 0.0 if torch.equal(left, right) else math.inf
        return float(torch.max(torch.abs(left - right)).item())
    return 0.0 if left == right else math.inf


def hostile_tests(raw: bytes) -> list[str]:
    source = json.loads(raw)
    mutations = []
    extra = copy.deepcopy(source)
    extra["tools"][0]["extra"] = True
    mutations.append(("extra_field", extra))
    bad_id = copy.deepcopy(source)
    bad_id["tools"][0]["tool_id"] = "0" * 64
    mutations.append(("bad_identity", bad_id))
    forward = copy.deepcopy(source)
    forward["tools"][0]["nodes"][0]["args"] = {"node": 0}
    mutations.append(("forward_node_reference", forward))
    untyped = copy.deepcopy(source)
    untyped["tools"][0]["inputs"][0]["type"]["rank"] = "two"
    mutations.append(("untyped_input", untyped))
    target = copy.deepcopy(source)
    target["tools"][0]["nodes"][0]["target"] = "python.eval"
    mutations.append(("non_aten_target", target))
    rejected = []
    for name, mutation in mutations:
        try:
            parse_library(canonical(mutation).encode())
        except ContractError:
            rejected.append(name)
        else:
            raise RuntimeError(f"hostile diversity mutation accepted: {name}")
    return rejected


def historical_workloads() -> tuple[
    list[tuple[str, dict[str, Any]]], list[dict[str, str]]
]:
    rows = []
    unsupported = []
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
    return rows, unsupported
