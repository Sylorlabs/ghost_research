#!/usr/bin/env python3
"""Scoped, genuine equality saturation control for Operator v5.

The e-graph handles associative dense/sparse matrix chains and commutative
addition.  It uses hash-consed e-nodes, union-find e-classes, congruence
rebuilding, saturation to a fixed point, and cost extraction.  Unsupported
operator graphs fail closed to the original program.
"""

from __future__ import annotations

import dataclasses
import json
from collections import Counter
from collections.abc import Mapping
from typing import Any

from ghost_operator_core_v5 import (
    Artifact,
    ContractError,
    TensorType,
    broadcast_shape,
    canonical_json,
    load_plan_text,
    plan_payload,
)


@dataclasses.dataclass(frozen=True, order=True)
class ENode:
    op: str
    children: tuple[int, ...]
    attrs_json: str

    @property
    def attrs(self) -> dict[str, object]:
        return json.loads(self.attrs_json)


class EGraph:
    def __init__(self) -> None:
        self.parent: list[int] = []
        self.classes: dict[int, set[ENode]] = {}
        self.memo: dict[ENode, int] = {}
        self.unions = 0
        self.proofs: list[str] = []

    def find(self, value: int) -> int:
        parent = self.parent[value]
        if parent != value:
            self.parent[value] = self.find(parent)
        return self.parent[value]

    def add(self, op: str, children=(), attrs: Mapping[str, object] | None = None) -> int:
        canonical_children = tuple(self.find(item) for item in children)
        enode = ENode(op, canonical_children, canonical_json(dict(attrs or {})))
        if enode in self.memo:
            return self.find(self.memo[enode])
        class_id = len(self.parent)
        self.parent.append(class_id)
        self.classes[class_id] = {enode}
        self.memo[enode] = class_id
        return class_id

    def union(self, left: int, right: int, proof: str) -> int:
        left, right = self.find(left), self.find(right)
        if left == right:
            return left
        if len(self.classes[left]) < len(self.classes[right]):
            left, right = right, left
        self.parent[right] = left
        self.classes[left].update(self.classes.pop(right))
        self.unions += 1
        self.proofs.append(proof)
        return left

    def rebuild(self) -> bool:
        changed = False
        while True:
            new_memo: dict[ENode, int] = {}
            collision = None
            for class_id in sorted(list(self.classes)):
                root = self.find(class_id)
                if root != class_id:
                    continue
                canonical_nodes = {
                    ENode(
                        node.op,
                        tuple(self.find(child) for child in node.children),
                        node.attrs_json,
                    )
                    for node in self.classes[root]
                }
                self.classes[root] = canonical_nodes
                for node in sorted(canonical_nodes):
                    previous = new_memo.get(node)
                    if previous is not None and self.find(previous) != root:
                        collision = (previous, root)
                        break
                    new_memo[node] = root
                if collision:
                    break
            if collision is None:
                self.memo = new_memo
                return changed
            self.union(collision[0], collision[1], "congruence")
            changed = True

    def roots(self) -> list[int]:
        return sorted(class_id for class_id in self.classes if self.find(class_id) == class_id)

    @property
    def enode_count(self) -> int:
        return sum(len(nodes) for nodes in self.classes.values())


def _graph_applicable(artifact: Artifact) -> bool:
    counts = Counter(node["op"] for node in artifact.reference_program["nodes"])
    return counts == Counter(
        {"parameter": 3, "matmul": 2, "input": 1, "sparse_mm": 1, "add": 1}
    ) or counts == Counter({"parameter": 2, "matmul": 2, "input": 1})


def _build(artifact: Artifact) -> tuple[EGraph, int, dict[int, TensorType]]:
    graph = EGraph()
    environment: dict[str, int] = {}
    types: dict[int, TensorType] = {}
    input_types = {item.name: item.type for item in artifact.inputs}
    parameter_types = {item.name: item.type for item in artifact.parameters}
    for node in artifact.reference_program["nodes"]:
        op, attrs = node["op"], node["attrs"]
        children = tuple(environment[arg] for arg in node["args"])
        class_id = graph.add(op, children, attrs)
        if op == "input":
            result_type = input_types[attrs["name"]]
        elif op == "parameter":
            result_type = parameter_types[attrs["name"]]
        elif op in ("matmul", "sparse_mm"):
            left, right = (types[graph.find(item)] for item in children)
            result_type = TensorType(
                left.shape[:-1] + (right.shape[-1],), left.dtype
            )
        elif op == "add":
            left, right = (types[graph.find(item)] for item in children)
            result_type = TensorType(
                broadcast_shape(left.shape, right.shape), left.dtype
            )
        else:
            raise ContractError("scoped egraph received an unsupported node")
        previous = types.get(graph.find(class_id))
        if previous is not None and previous != result_type:
            raise ContractError("egraph type collision")
        types[graph.find(class_id)] = result_type
        environment[node["id"]] = class_id
    return graph, environment[artifact.reference_program["outputs"][0]], types


def _propagate_type(
    graph: EGraph,
    types: dict[int, TensorType],
    class_id: int,
    expected: TensorType,
) -> None:
    root = graph.find(class_id)
    previous = types.get(root)
    if previous is not None and previous != expected:
        raise ContractError("equality saturation attempted an ill-typed union")
    types[root] = expected


def saturate(artifact: Artifact, max_iterations: int = 12):
    if not _graph_applicable(artifact):
        return None, {
            "status": "GHOST_OPERATOR_EGRAPH_V5_NOT_APPLICABLE",
            "reason": "operator graph is outside scoped matrix-chain equality theory",
        }
    graph, output_class, types = _build(artifact)
    iterations = 0
    for iteration in range(max_iterations):
        iterations = iteration + 1
        union_before = graph.unions
        snapshot = [
            (root, tuple(graph.classes[root])) for root in graph.roots()
        ]
        for root, enodes in snapshot:
            root = graph.find(root)
            expected = types[root]
            for enode in enodes:
                if enode.op == "add":
                    swapped = graph.add("add", tuple(reversed(enode.children)))
                    _propagate_type(graph, types, swapped, expected)
                    graph.union(root, swapped, "add_commutativity")
                if enode.op == "matmul":
                    left_class, right_class = enode.children
                    for left_node in tuple(graph.classes[graph.find(left_class)]):
                        if left_node.op not in ("matmul", "sparse_mm"):
                            continue
                        a_class, x_class = left_node.children
                        x_type = types[graph.find(x_class)]
                        right_type = types[graph.find(right_class)]
                        if x_type.shape[-1] != right_type.shape[-2]:
                            continue
                        inner_type = TensorType(
                            x_type.shape[:-1] + (right_type.shape[-1],),
                            x_type.dtype,
                        )
                        inner = graph.add("matmul", (x_class, right_class))
                        _propagate_type(graph, types, inner, inner_type)
                        associated = graph.add(left_node.op, (a_class, inner))
                        _propagate_type(graph, types, associated, expected)
                        graph.union(
                            root,
                            associated,
                            f"{left_node.op}_matmul_associativity_forward",
                        )
                if enode.op in ("matmul", "sparse_mm"):
                    left_class, right_class = enode.children
                    for right_node in tuple(graph.classes[graph.find(right_class)]):
                        if right_node.op != "matmul":
                            continue
                        x_class, w_class = right_node.children
                        left_type = types[graph.find(left_class)]
                        x_type = types[graph.find(x_class)]
                        if left_type.shape[-1] != x_type.shape[-2]:
                            continue
                        inner_type = TensorType(
                            left_type.shape[:-1] + (x_type.shape[-1],),
                            left_type.dtype,
                        )
                        inner = graph.add(enode.op, (left_class, x_class))
                        _propagate_type(graph, types, inner, inner_type)
                        associated = graph.add("matmul", (inner, w_class))
                        _propagate_type(graph, types, associated, expected)
                        graph.union(
                            root,
                            associated,
                            f"{enode.op}_matmul_associativity_reverse",
                        )
        graph.rebuild()
        # Re-key type facts after unions.
        types = {graph.find(class_id): spec for class_id, spec in types.items()}
        output_class = graph.find(output_class)
        if graph.unions == union_before:
            break
    else:
        raise ContractError("equality saturation did not reach a fixed point")
    return (graph, output_class, types), {
        "status": "GHOST_OPERATOR_EGRAPH_V5_SATURATED",
        "iterations": iterations,
        "eclasses": len(graph.roots()),
        "enodes": graph.enode_count,
        "unions": graph.unions,
        "proof_rules": dict(sorted(Counter(graph.proofs).items())),
        "fixed_point": True,
    }


def _density_by_parameter(artifact: Artifact) -> dict[str, float]:
    return {
        item.name: float(item.init["density"])
        for item in artifact.parameters
        if item.type.storage == "sparse_csr"
    }


def extract(artifact: Artifact):
    saturated, receipt = saturate(artifact)
    if saturated is None:
        return {
            "version": "GHOST_OPERATOR_PLAN_V5",
            "parameter_program": {"nodes": []},
            "program": artifact.reference_program,
        }, receipt
    graph, output_class, types = saturated
    density = _density_by_parameter(artifact)
    memo: dict[int, tuple[float, ENode, tuple[Any, ...]]] = {}
    visiting: set[int] = set()

    def best(class_id: int):
        root = graph.find(class_id)
        if root in memo:
            return memo[root]
        if root in visiting:
            return None
        visiting.add(root)
        candidates = []
        for enode in graph.classes[root]:
            children = []
            valid = True
            for child in enode.children:
                item = best(child)
                if item is None:
                    valid = False
                    break
                children.append(item)
            if not valid:
                continue
            child_cost = sum(item[0] for item in children)
            result_type = types[root]
            if enode.op in ("input", "parameter"):
                local_cost = 0.0
            elif enode.op == "add":
                local_cost = float(result_type.elements)
            elif enode.op == "matmul":
                left_type = types[graph.find(enode.children[0])]
                local_cost = float(result_type.elements * left_type.shape[-1])
            elif enode.op == "sparse_mm":
                left_choice = children[0][1]
                left_name = (
                    left_choice.attrs.get("name")
                    if left_choice.op == "parameter"
                    else None
                )
                left_type = types[graph.find(enode.children[0])]
                right_type = types[graph.find(enode.children[1])]
                nnz = (
                    left_type.elements * density.get(str(left_name), 1.0)
                )
                local_cost = float(nnz * right_type.shape[-1])
            else:
                continue
            candidates.append(
                (
                    child_cost + local_cost,
                    canonical_json(
                        {
                            "op": enode.op,
                            "children": [item[0] for item in children],
                            "attrs": enode.attrs,
                        }
                    ),
                    enode,
                    tuple(children),
                )
            )
        visiting.remove(root)
        if not candidates:
            return None
        cost, _key, enode, children = min(candidates)
        memo[root] = (cost, enode, children)
        return memo[root]

    chosen = best(output_class)
    if chosen is None:
        raise ContractError("egraph extraction failed")
    runtime_nodes: list[dict[str, object]] = []

    def emit_tree(choice) -> str:
        _cost, enode, children = choice
        child_ids = [emit_tree(item) for item in children]
        node_id = f"e{len(runtime_nodes)}"
        runtime_nodes.append(
            {
                "id": node_id,
                "op": enode.op,
                "args": child_ids,
                "attrs": enode.attrs,
            }
        )
        return node_id

    output_id = emit_tree(chosen)
    result = plan_payload([], {"nodes": runtime_nodes, "outputs": [output_id]})
    validated = load_plan_text(canonical_json(result), artifact)
    receipt = {
        **receipt,
        "extracted_cost": chosen[0],
        "extracted_runtime_nodes": len(runtime_nodes),
    }
    return validated, receipt


def semantic_program_key(program: Mapping[str, object]) -> str:
    """Canonical expression key ignoring SSA ids/order and add commutation."""
    environment: dict[str, object] = {}
    for node in program["nodes"]:  # type: ignore[index]
        op = node["op"]
        children = [environment[item] for item in node["args"]]
        if op == "add":
            children = sorted(children, key=canonical_json)
        attrs = {
            key: value
            for key, value in node["attrs"].items()
            if not (op in ("input", "parameter") and key == "name")
        }
        if op in ("input", "parameter"):
            attrs["name"] = node["attrs"]["name"]
        environment[node["id"]] = {
            "op": op,
            "children": children,
            "attrs": attrs,
        }
    return canonical_json([environment[item] for item in program["outputs"]])  # type: ignore[index]
