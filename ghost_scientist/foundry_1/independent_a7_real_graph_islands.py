#!/usr/bin/env python3
"""Independent serializer for the A7 add/mul/relu real-graph islands."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any

from torch.fx import Graph, Node


MAPPING = {
    "aten.add.Tensor": "+",
    "aten.mul.Tensor": "*",
    "aten.relu.default": "relu",
}


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def clean(value: str) -> str:
    return re.sub(r"[^a-z0-9_]+", "_", value.lower()).strip("_") or "empty"


def value_type(value: Any) -> str:
    if hasattr(value, "shape") and hasattr(value, "dtype"):
        return f"tensor_r{len(value.shape)}_{clean(str(value.dtype))}_{clean(str(value.layout))}"
    return clean(type(value).__name__)


def leaf(value: Any) -> str:
    if isinstance(value, Node):
        record = {
            "kind": "node",
            "name": value.name,
            "op": value.op,
            "target": str(value.target),
            "type": value_type(value.meta.get("val")),
        }
    else:
        record = {
            "kind": "literal",
            "type": type(value).__name__,
            "value": repr(value),
        }
    return "v_" + hashlib.sha256(canonical(record).encode()).hexdigest()[:16]


def valid(node: Node) -> bool:
    target = str(node.target)
    if target == "aten.add.Tensor":
        return (
            len(node.args) == 2
            and set(node.kwargs) <= {"alpha"}
            and node.kwargs.get("alpha", 1) == 1
        )
    if target == "aten.mul.Tensor":
        return len(node.args) == 2 and not node.kwargs
    if target == "aten.relu.default":
        return len(node.args) == 1 and not node.kwargs
    return False


def extract(graph: Graph) -> list[dict[str, str]]:
    encoded: dict[Node, str] = {}
    output: list[dict[str, str]] = []
    for node in graph.nodes:
        if node.op != "call_function" or str(node.target) not in MAPPING:
            continue
        if not valid(node):
            raise ValueError(f"mapped operator has unsupported signature: {node.target}")
        arguments = [
            encoded[value] if isinstance(value, Node) and value in encoded else leaf(value)
            for value in node.args
        ]
        expression = (
            "(" + MAPPING[str(node.target)] + " " + " ".join(arguments) + ")"
        )
        encoded[node] = expression
        output.append(
            {
                "root_node": node.name,
                "target": str(node.target),
                "expression": expression,
            }
        )
    return output
