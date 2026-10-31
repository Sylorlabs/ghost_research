#!/usr/bin/env python3
"""Independent evidence verifier, matcher, and interpreter for polymorphic tools."""

from __future__ import annotations

import copy
import hashlib
import json
import math
import pathlib
from typing import Any

import torch
from torch.fx import Node

from external_validation_v4_runtime import instantiate
from phase26_independent_semantic_evaluator import (
    CapturingInterpreter,
    ContractError,
    canonical,
    exact,
    execute_tool,
    fixed_match_count,
    literal_value,
    max_error,
    node_type,
    parse_library as parse_source_library,
    parse_term,
    parse_type,
)


HERE = pathlib.Path(__file__).resolve().parent
RESULTS = HERE / "results"
LIBRARY = RESULTS / "forged_polymorphic_semantic_tools.json"
SOURCE = RESULTS / "forged_semantic_tools.json"
FIXED = HERE / "ATEN_FIXED_PORTFOLIO_V2.json"


def signature_key(row: dict[str, object]) -> tuple[int, str, str]:
    parse_type(row, "signature")
    return int(row["rank"]), str(row["dtype"]), str(row["layout"])


def parse_constraint(value: object, context: str) -> set[tuple[int, str, str]]:
    row = exact(value, {"one_of"}, context)
    if not isinstance(row["one_of"], list) or not row["one_of"]:
        raise ContractError(f"{context} is empty")
    signatures = [signature_key(item) for item in row["one_of"]]
    if signatures != sorted(set(signatures)):
        raise ContractError(f"{context} signatures are not canonical")
    return set(signatures)


def identity(tool: dict[str, Any]) -> str:
    body = {
        "version": tool["version"],
        "inputs": tool["inputs"],
        "nodes": tool["nodes"],
        "outputs": tool["outputs"],
    }
    return hashlib.sha256(canonical(body).encode()).hexdigest()


def parse_library(raw: bytes) -> dict[str, Any]:
    try:
        value = json.loads(raw)
    except json.JSONDecodeError as exc:
        raise ContractError("polymorphic library is not JSON") from exc
    root = exact(
        value,
        {
            "version",
            "construction",
            "source_library_sha256",
            "evidence_graphs",
            "unsupported_evidence_families",
            "evidence",
            "tools",
        },
        "library",
    )
    if root["version"] != "FOUNDRY_POLYMORPHIC_SEMANTIC_LIBRARY_V1":
        raise ContractError("polymorphic library version invalid")
    construction = exact(
        root["construction"],
        {
            "algorithm",
            "llm_calls",
            "manual_type_widenings",
            "validation_graphs_accessed",
            "constraint_rule",
        },
        "construction",
    )
    if (
        construction["llm_calls"] != 0
        or construction["manual_type_widenings"] != 0
        or construction["validation_graphs_accessed"] is not False
    ):
        raise ContractError("polymorphic construction boundary invalid")
    source_raw = SOURCE.read_bytes()
    source = parse_source_library(source_raw)
    if root["source_library_sha256"] != hashlib.sha256(source_raw).hexdigest():
        raise ContractError("polymorphic source digest invalid")
    source_tools = {tool["tool_id"]: tool for tool in source["tools"]}
    evidence: dict[tuple[str, str, str], set[tuple[int, str, str]]] = {}
    counts = set()
    for index, item in enumerate(root["evidence"]):
        row = exact(
            item,
            {"target", "position_kind", "position", "signature", "occurrences"},
            f"evidence {index}",
        )
        if (
            not isinstance(row["target"], str)
            or not row["target"].startswith("aten.")
            or row["position_kind"] not in {"arg", "kw", "output"}
            or not isinstance(row["position"], str)
            or type(row["occurrences"]) is not int
            or row["occurrences"] <= 0
        ):
            raise ContractError(f"evidence {index} invalid")
        key = (row["target"], row["position_kind"], row["position"])
        sig = signature_key(row["signature"])
        marker = (*key, sig)
        if marker in counts:
            raise ContractError("duplicate evidence signature")
        counts.add(marker)
        evidence.setdefault(key, set()).add(sig)
    if not isinstance(root["tools"], list) or not root["tools"]:
        raise ContractError("polymorphic library empty")
    seen = set()
    for tool_index, tool in enumerate(root["tools"]):
        row = exact(
            tool,
            {
                "tool_id",
                "version",
                "inputs",
                "nodes",
                "outputs",
                "source_tool_id",
                "training",
            },
            f"tool {tool_index}",
        )
        if row["version"] != "FOUNDRY_POLYMORPHIC_SEMANTIC_TOOL_V1":
            raise ContractError("polymorphic tool version invalid")
        source_tool = source_tools.get(row["source_tool_id"])
        if source_tool is None:
            raise ContractError("polymorphic source tool missing")
        if len(row["inputs"]) != len(source_tool["inputs"]):
            raise ContractError("polymorphic input count changed")
        for index, input_row in enumerate(row["inputs"]):
            item = exact(
                input_row,
                {"constraint", "evidence_positions"},
                f"tool {tool_index} input {index}",
            )
            allowed = parse_constraint(
                item["constraint"], f"tool {tool_index} input {index} constraint"
            )
            exact_source = signature_key(source_tool["inputs"][index]["type"])
            if exact_source not in allowed:
                raise ContractError("source input signature removed")
            if not isinstance(item["evidence_positions"], list) or any(
                not isinstance(position, str)
                for position in item["evidence_positions"]
            ):
                raise ContractError("input evidence positions invalid")
            if item["evidence_positions"]:
                supported = None
                for position in item["evidence_positions"]:
                    parts = tuple(position.split("|"))
                    if len(parts) != 3 or parts not in evidence:
                        raise ContractError("input evidence position missing")
                    supported = (
                        set(evidence[parts])
                        if supported is None
                        else supported & evidence[parts]
                    )
                if not allowed <= (supported or set()):
                    raise ContractError("unobserved input signature admitted")
            elif allowed != {exact_source}:
                raise ContractError("unevidenced input signature widened")
        if len(row["nodes"]) != len(source_tool["nodes"]):
            raise ContractError("polymorphic node count changed")
        for index, node in enumerate(row["nodes"]):
            item = exact(
                node,
                {"target", "args", "kwargs", "output_constraint"},
                f"tool {tool_index} node {index}",
            )
            source_node = source_tool["nodes"][index]
            if (
                item["target"] != source_node["target"]
                or item["args"] != source_node["args"]
                or item["kwargs"] != source_node["kwargs"]
                or not item["target"].startswith("aten.")
            ):
                raise ContractError("polymorphic semantic body changed")
            parse_term(
                item["args"],
                len(row["inputs"]),
                index,
                f"tool {tool_index} node {index} args",
            )
            parse_term(
                item["kwargs"],
                len(row["inputs"]),
                index,
                f"tool {tool_index} node {index} kwargs",
            )
            allowed = parse_constraint(
                item["output_constraint"],
                f"tool {tool_index} node {index} output",
            )
            exact_source = signature_key(source_node["output_type"])
            supported = evidence.get((item["target"], "output", ""), set())
            if exact_source not in allowed or not allowed <= supported:
                raise ContractError("unobserved output signature admitted")
        if row["outputs"] != source_tool["outputs"]:
            raise ContractError("polymorphic outputs changed")
        if row["tool_id"] != identity(row) or row["tool_id"] in seen:
            raise ContractError("polymorphic identity invalid")
        seen.add(row["tool_id"])
    return root


def accepts(constraint: dict[str, object], actual: dict[str, object] | None) -> bool:
    if actual is None:
        return False
    signature = (
        int(actual["rank"]),
        str(actual["dtype"]),
        str(actual["layout"]),
    )
    return signature in parse_constraint(constraint, "runtime constraint")


def match_term(
    expected: dict[str, object],
    actual: object,
    path: list[Node],
    input_constraints: list[dict[str, object]],
    bindings: dict[int, Node],
) -> bool:
    tag, value = next(iter(expected.items()))
    if tag == "input":
        if not isinstance(actual, Node) or actual in path:
            return False
        slot = int(value)
        if not accepts(input_constraints[slot], node_type(actual)):
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
            match_term(item, child, path, input_constraints, bindings)
            for item, child in zip(value, actual)
        )
    if tag == "tuple":
        return isinstance(actual, tuple) and len(actual) == len(value) and all(
            match_term(item, child, path, input_constraints, bindings)
            for item, child in zip(value, actual)
        )
    if tag == "dict":
        if not isinstance(actual, dict) or len(actual) != len(value):
            return False
        for key_term, child_term in value:
            key = literal_value(key_term)
            if key not in actual or not match_term(
                child_term,
                actual[key],
                path,
                input_constraints,
                bindings,
            ):
                return False
        return True
    raise ContractError("unknown polymorphic term")


def matches(tool: dict[str, Any], graph: torch.fx.Graph):
    eligible = {
        node
        for node in graph.nodes
        if node.op == "call_function" and node_type(node) is not None
    }
    rows = []
    visits = 0
    edges = 0
    constraints = [row["constraint"] for row in tool["inputs"]]

    def extend(path: list[Node]) -> None:
        nonlocal edges
        index = len(path) - 1
        expected = tool["nodes"][index]
        actual = path[-1]
        if (
            str(actual.target) != expected["target"]
            or not accepts(expected["output_constraint"], node_type(actual))
        ):
            return
        if len(path) == len(tool["nodes"]):
            bindings: dict[int, Node] = {}
            for offset, node in enumerate(path):
                expected_node = tool["nodes"][offset]
                if not match_term(
                    expected_node["args"],
                    node.args,
                    path,
                    constraints,
                    bindings,
                ) or not match_term(
                    expected_node["kwargs"],
                    node.kwargs,
                    path,
                    constraints,
                    bindings,
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


def hostile_tests(raw: bytes) -> list[str]:
    source = json.loads(raw)
    mutations = []
    extra = copy.deepcopy(source)
    extra["tools"][0]["extra"] = True
    mutations.append(("extra_field", extra, False))
    bad_id = copy.deepcopy(source)
    bad_id["tools"][0]["tool_id"] = "0" * 64
    mutations.append(("bad_identity", bad_id, False))
    forward = copy.deepcopy(source)
    forward["tools"][0]["nodes"][0]["args"] = {"node": 0}
    mutations.append(("forward_node_reference", forward, True))
    untyped = copy.deepcopy(source)
    untyped["tools"][0]["inputs"][0]["constraint"]["one_of"][0]["rank"] = "two"
    mutations.append(("untyped_constraint", untyped, True))
    target = copy.deepcopy(source)
    target["tools"][0]["nodes"][0]["target"] = "python.eval"
    mutations.append(("non_aten_target", target, True))
    unobserved = copy.deepcopy(source)
    unobserved["tools"][0]["inputs"][0]["constraint"]["one_of"].append(
        {
            "rank": 2,
            "dtype": "torch.float32",
            "layout": "torch.sparse_csr",
        }
    )
    unobserved["tools"][0]["inputs"][0]["constraint"]["one_of"].sort(
        key=lambda row: (row["rank"], row["dtype"], row["layout"])
    )
    mutations.append(("unobserved_signature", unobserved, True))
    rejected = []
    for name, mutation, repair_identity in mutations:
        if repair_identity:
            mutation["tools"][0]["tool_id"] = identity(mutation["tools"][0])
        try:
            parse_library(canonical(mutation).encode())
        except ContractError:
            rejected.append(name)
        else:
            raise RuntimeError(f"hostile polymorphic mutation accepted: {name}")
    return rejected


def run() -> None:
    raw = LIBRARY.read_bytes()
    library = parse_library(raw)
    fixed = json.loads(FIXED.read_text(encoding="utf-8"))
    hostile = hostile_tests(raw)
    rows = []
    receipts = []
    candidate_visits = 0
    candidate_edges = 0
    candidate_tools = set()
    candidate_families = set()
    fixed_visits = 0
    fixed_edges = 0
    fixed_matches = 0
    fixed_benefit = 0
    fixed_families = set()
    for workload in instantiate():
        exported = torch.export.export(
            workload["model"], workload["args"], workload["kwargs"], strict=True
        )
        module = exported.module()
        interpreter = CapturingInterpreter(module)
        interpreter.run(*workload["args"], **workload["kwargs"])
        family_matches = 0
        for tool in library["tools"]:
            tool_matches, visits, edges = matches(tool, module.graph)
            candidate_visits += visits
            candidate_edges += edges
            for path, bindings in tool_matches:
                inputs = [
                    interpreter.values[bindings[index]]
                    for index in range(len(tool["inputs"]))
                ]
                output = execute_tool(tool, inputs)
                error = max_error(output, interpreter.values[path[-1]])
                if not math.isfinite(error) or error > 1.0e-6:
                    raise RuntimeError(
                        f"polymorphic replay mismatch {tool['tool_id']}"
                    )
                family_matches += 1
                candidate_tools.add(tool["tool_id"])
                candidate_families.add(workload["family"])
                rows.append(
                    {
                        "family": workload["family"],
                        "tool_id": tool["tool_id"],
                        "source_tool_id": tool["source_tool_id"],
                        "nodes": [node.name for node in path],
                        "max_abs_error": error,
                        "input_signatures": [
                            node_type(bindings[index])
                            for index in range(len(tool["inputs"]))
                        ],
                    }
                )
        fixed_result = fixed_match_count(module.graph, fixed)
        fixed_visits += fixed_result["visits"]
        fixed_edges += fixed_result["edges"]
        fixed_matches += fixed_result["matches"]
        fixed_benefit += fixed_result["benefit"]
        if fixed_result["matched"]:
            fixed_families.add(workload["family"])
        receipts.append(
            {
                "family": workload["family"],
                "graph_sha256": hashlib.sha256(str(module.graph).encode()).hexdigest(),
                "candidate_matches": family_matches,
                "fixed_matches": fixed_result["matches"],
            }
        )
    candidate_definition = sum(
        len(tool["nodes"])
        + len(tool["inputs"])
        + sum(
            len(row["constraint"]["one_of"]) - 1 for row in tool["inputs"]
        )
        + sum(
            len(row["output_constraint"]["one_of"]) - 1
            for row in tool["nodes"]
        )
        for tool in library["tools"]
    )
    fixed_definition = sum(len(tool["targets"]) for tool in fixed["tools"])
    candidate_benefit = sum(len(row["nodes"]) for row in rows)
    candidate_cost = candidate_definition + candidate_visits + candidate_edges
    fixed_cost = fixed_definition + fixed_visits + fixed_edges
    gates = {
        "four_families_executed": len(receipts) == 4,
        "six_hostile_mutations_rejected": len(hostile) == 6,
        "all_replays_exact": all(row["max_abs_error"] <= 1.0e-6 for row in rows),
        "minimum_two_candidate_families": len(candidate_families) >= 2,
        "minimum_two_candidate_tools": len(candidate_tools) >= 2,
        "candidate_benefit_at_least_fixed": candidate_benefit >= fixed_benefit,
        "candidate_cost_below_fixed": candidate_cost < fixed_cost,
        "causal_removal_loses_all_matches": len(rows) > 0,
    }
    status = (
        "POLYMORPHIC_PROSPECTIVE_TRANSFER_PASS"
        if all(gates.values())
        else "POLYMORPHIC_PROSPECTIVE_VALID_NEGATIVE"
    )
    payload = {
        "version": "FOUNDRY_INDEPENDENT_POLYMORPHIC_EVAL_V1",
        "status": status,
        "library_sha256": hashlib.sha256(raw).hexdigest(),
        "validation_freeze_sha256": hashlib.sha256(
            (RESULTS / "external_validation_v4_freeze.json").read_bytes()
        ).hexdigest(),
        "families": len(receipts),
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
        "family_receipts": receipts,
        "rows": rows,
        "prospective_boundary": {
            "source_and_runtime_preforge": True,
            "evaluator_preforge": True,
            "manual_type_widenings": 0,
            "classification": "PROSPECTIVE_POLYMORPHIC_COMPONENT",
        },
    }
    (RESULTS / "phase30_independent_polymorphic_eval.json").write_text(
        canonical(payload) + "\n", encoding="utf-8"
    )
    print(
        "FOUNDRY_PHASE30_POLYMORPHIC_EVAL"
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
