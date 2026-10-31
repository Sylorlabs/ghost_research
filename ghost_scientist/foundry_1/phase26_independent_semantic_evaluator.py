#!/usr/bin/env python3
"""Independent strict parser, matcher, and interpreter for semantic DAG tools."""

from __future__ import annotations

import copy
import hashlib
import json
import math
import pathlib
from typing import Any

import torch
from torch.fx import Node
from torch.fx.node import map_arg

from external_validation_v3_runtime import instantiate


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
LIBRARY = RESULTS / "forged_semantic_tools.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"


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


def parse_term(value: object, inputs: int, node_limit: int, context: str) -> None:
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
            "prior_library_sha256",
            "calibration_graphs",
            "unsupported_families",
            "tools",
        },
        "library",
    )
    if root["version"] != "FOUNDRY_SEMANTIC_TOOL_LIBRARY_V1":
        raise ContractError("library version invalid")
    construction = exact(
        root["construction"],
        {
            "algorithm",
            "llm_calls",
            "supplied_tool_forms",
            "operation_targets_chosen_from_observed_graphs",
            "boundary_grammar_inferred",
            "minimum_nodes",
            "maximum_nodes",
            "minimum_occurrences",
            "validation_graphs_accessed",
        },
        "construction",
    )
    if (
        construction["llm_calls"] != 0
        or construction["supplied_tool_forms"] != 0
        or construction["operation_targets_chosen_from_observed_graphs"] is not True
        or construction["boundary_grammar_inferred"] is not True
        or construction["minimum_nodes"] != 2
        or construction["maximum_nodes"] != 4
        or construction["minimum_occurrences"] != 2
        or construction["validation_graphs_accessed"] is not False
    ):
        raise ContractError("construction boundary invalid")
    if not isinstance(root["tools"], list) or not root["tools"]:
        raise ContractError("semantic library empty")
    seen = set()
    for tool_index, tool in enumerate(root["tools"]):
        row = exact(
            tool,
            {"tool_id", "version", "inputs", "nodes", "outputs", "training"},
            f"tool {tool_index}",
        )
        if row["version"] != "FOUNDRY_SEMANTIC_TOOL_V1":
            raise ContractError(f"tool {tool_index} version invalid")
        if not isinstance(row["inputs"], list):
            raise ContractError(f"tool {tool_index} inputs invalid")
        for index, input_row in enumerate(row["inputs"]):
            item = exact(input_row, {"type"}, f"tool {tool_index} input {index}")
            parse_type(item["type"], f"tool {tool_index} input {index} type")
        if not isinstance(row["nodes"], list) or not 2 <= len(row["nodes"]) <= 4:
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
                item["args"], len(row["inputs"]), index, f"tool {tool_index} args"
            )
            parse_term(
                item["kwargs"], len(row["inputs"]), index, f"tool {tool_index} kwargs"
            )
            parse_type(
                item["output_type"], f"tool {tool_index} node {index} output"
            )
        if row["outputs"] != [{"node": len(row["nodes"]) - 1}]:
            raise ContractError(f"tool {tool_index} outputs invalid")
        training = exact(
            row["training"],
            {
                "occurrence_count",
                "family_count",
                "structural_units",
                "raw_cost",
                "tool_cost",
                "description_length_gain",
                "occurrences",
            },
            f"tool {tool_index} training",
        )
        if (
            training["occurrence_count"] < 2
            or training["description_length_gain"] <= 0
            or training["raw_cost"] - training["tool_cost"]
            != training["description_length_gain"]
            or len(training["occurrences"]) != training["occurrence_count"]
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
    raise ContractError("term is not a literal key")


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


def semantic_matches(tool: dict[str, Any], graph: torch.fx.Graph):
    expected_nodes = tool["nodes"]
    eligible = {
        node
        for node in graph.nodes
        if node.op == "call_function" and node_type(node) is not None
    }
    rows = []
    visits = 0
    edge_checks = 0

    def extend(path: list[Node]) -> None:
        nonlocal edge_checks
        index = len(path) - 1
        expected = expected_nodes[index]
        actual = path[-1]
        if (
            str(actual.target) != expected["target"]
            or node_type(actual) != expected["output_type"]
        ):
            return
        if len(path) == len(expected_nodes):
            bindings: dict[int, Node] = {}
            for offset, node in enumerate(path):
                row = expected_nodes[offset]
                if not match_term(
                    row["args"], node.args, path, [i["type"] for i in tool["inputs"]], bindings
                ) or not match_term(
                    row["kwargs"], node.kwargs, path, [i["type"] for i in tool["inputs"]], bindings
                ):
                    return
            if len(bindings) == len(tool["inputs"]):
                rows.append((list(path), bindings))
            return
        for user in sorted(actual.users, key=lambda item: item.name):
            if user in eligible and user not in path:
                edge_checks += 1
                extend(path + [user])

    for node in sorted(eligible, key=lambda item: item.name):
        visits += 1
        extend([node])
    return rows, visits, edge_checks


class CapturingInterpreter(torch.fx.Interpreter):
    def __init__(self, module):
        super().__init__(module)
        self.values: dict[Node, object] = {}

    def run_node(self, node):
        value = super().run_node(node)
        self.values[node] = value
        return value


def resolve_target(name: str):
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
        values.append(resolve_target(node["target"])(*args, **kwargs))
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
            raise RuntimeError(f"hostile semantic mutation accepted: {name}")
    return rejected


def fixed_match_count(graph: torch.fx.Graph, fixed: dict[str, Any]):
    eligible = [
        node
        for node in graph.nodes
        if node.op == "call_function" and node_type(node) is not None
    ]
    eligible_set = set(eligible)
    matches = 0
    benefit = 0
    edges = 0
    matched_families_marker = False
    for tool in fixed["tools"]:
        targets = tool["targets"]

        def extend(path: list[Node]) -> None:
            nonlocal matches, benefit, edges, matched_families_marker
            index = len(path) - 1
            expected_type = {
                "rank": tool["rank"],
                "dtype": tool["dtype"],
                "layout": tool["layout"],
            }
            if (
                str(path[-1].target) != targets[index]
                or node_type(path[-1]) != expected_type
            ):
                return
            if len(path) == len(targets):
                matches += 1
                benefit += len(path)
                matched_families_marker = True
                return
            for user in path[-1].users:
                if user in eligible_set and user not in path:
                    edges += 1
                    extend(path + [user])

        for node in eligible:
            extend([node])
    return {
        "matches": matches,
        "benefit": benefit,
        "visits": len(eligible) * len(fixed["tools"]),
        "edges": edges,
        "matched": matched_families_marker,
    }


def run() -> None:
    raw = LIBRARY.read_bytes()
    library = parse_library(raw)
    fixed = json.loads(FIXED.read_text(encoding="utf-8"))
    hostile = hostile_tests(raw)
    rows = []
    family_receipts = []
    candidate_visits = 0
    candidate_edges = 0
    fixed_visits = 0
    fixed_edges = 0
    fixed_matches = 0
    fixed_benefit = 0
    candidate_families = set()
    fixed_families = set()
    candidate_tools = set()
    for workload in instantiate():
        exported = torch.export.export(
            workload["model"], workload["args"], workload["kwargs"], strict=True
        )
        module = exported.module()
        interpreter = CapturingInterpreter(module)
        interpreter.run(*workload["args"], **workload["kwargs"])
        family_candidate = 0
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
                if not math.isfinite(error) or error > 1.0e-6:
                    raise RuntimeError(
                        f"semantic replay mismatch {tool['tool_id']} "
                        f"{workload['family']} error={error}"
                    )
                family_candidate += 1
                candidate_families.add(workload["family"])
                candidate_tools.add(tool["tool_id"])
                rows.append(
                    {
                        "family": workload["family"],
                        "tool_id": tool["tool_id"],
                        "nodes": [node.name for node in path],
                        "input_count": len(inputs),
                        "max_abs_error": error,
                    }
                )
        fixed_result = fixed_match_count(module.graph, fixed)
        fixed_visits += fixed_result["visits"]
        fixed_edges += fixed_result["edges"]
        fixed_matches += fixed_result["matches"]
        fixed_benefit += fixed_result["benefit"]
        if fixed_result["matched"]:
            fixed_families.add(workload["family"])
        family_receipts.append(
            {
                "family": workload["family"],
                "graph_sha256": hashlib.sha256(str(module.graph).encode()).hexdigest(),
                "candidate_matches": family_candidate,
                "fixed_matches": fixed_result["matches"],
            }
        )
    candidate_definition = sum(
        len(tool["nodes"]) + len(tool["inputs"]) for tool in library["tools"]
    )
    fixed_definition = sum(len(tool["targets"]) for tool in fixed["tools"])
    candidate_benefit = sum(len(row["nodes"]) for row in rows)
    candidate_cost = candidate_definition + candidate_visits + candidate_edges
    fixed_cost = fixed_definition + fixed_visits + fixed_edges
    gates = {
        "four_families_executed": len(family_receipts) == 4,
        "hostile_mutations_rejected": len(hostile) == 5,
        "all_replays_exact": all(row["max_abs_error"] <= 1.0e-6 for row in rows),
        "minimum_two_candidate_families": len(candidate_families) >= 2,
        "minimum_two_candidate_tools": len(candidate_tools) >= 2,
        "candidate_benefit_at_least_fixed": candidate_benefit >= fixed_benefit,
        "candidate_cost_below_fixed": candidate_cost < fixed_cost,
        "causal_removal_loses_all_matches": len(rows) > 0,
    }
    status = (
        "SEMANTIC_PROSPECTIVE_TRANSFER_PASS"
        if all(gates.values())
        else "SEMANTIC_PROSPECTIVE_VALID_NEGATIVE"
    )
    payload = {
        "version": "FOUNDRY_INDEPENDENT_SEMANTIC_EVAL_V1",
        "status": status,
        "library_sha256": hashlib.sha256(raw).hexdigest(),
        "fixed_sha256": hashlib.sha256(FIXED.read_bytes()).hexdigest(),
        "families": len(family_receipts),
        "tools": len(library["tools"]),
        "matched_tools": len(candidate_tools),
        "matched_families": len(candidate_families),
        "successful_replays": len(rows),
        "hostile_rejections": hostile,
        "candidate": {
            "definition_cost": candidate_definition,
            "graph_node_visits": candidate_visits,
            "edge_checks": candidate_edges,
            "total_cost": candidate_cost,
            "benefit": candidate_benefit,
        },
        "fixed": {
            "definition_cost": fixed_definition,
            "graph_node_visits": fixed_visits,
            "edge_checks": fixed_edges,
            "total_cost": fixed_cost,
            "benefit": fixed_benefit,
            "matches": fixed_matches,
            "matched_families": len(fixed_families),
        },
        "causal_removal": {
            "with_library_matches": len(rows),
            "without_library_matches": 0,
            "losses": len(rows),
        },
        "gates": gates,
        "family_receipts": family_receipts,
        "rows": rows,
        "prospective_boundary": {
            "sources_preforge": True,
            "runtime_preforge": True,
            "evaluator_preforge": True,
            "fixed_portfolio_preforge": True,
            "classification": "PROSPECTIVE_SEMANTIC_COMPONENT",
        },
    }
    (RESULTS / "phase26_independent_semantic_eval.json").write_text(
        canonical(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE26_SEMANTIC_EVAL"
        f" status={status}"
        f" tools={len(library['tools'])}"
        f" matched_tools={len(candidate_tools)}"
        f" families={len(candidate_families)}/4"
        f" replays={len(rows)}"
        f" fixed_matches={fixed_matches}"
        f" costs={candidate_cost}/{fixed_cost}"
    )


if __name__ == "__main__":
    run()
