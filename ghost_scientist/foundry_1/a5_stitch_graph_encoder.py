#!/usr/bin/env python3
"""Primary complete-DAG typed S-expression encoder for A5 Stitch."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any

import torch
from torch.fx import Node


def atom(value: str) -> str:
    cleaned = re.sub(r"[^a-z0-9_]+", "_", value.lower()).strip("_")
    return cleaned or "empty"


def value_type(value: Any) -> str:
    if isinstance(value, torch.Tensor):
        return (
            f"tensor_r{len(value.shape)}_{atom(str(value.dtype))}_"
            f"{atom(str(value.layout))}"
        )
    if isinstance(value, tuple):
        return f"tuple_{len(value)}"
    if isinstance(value, list):
        return f"list_{len(value)}"
    if isinstance(value, dict):
        return f"dict_{len(value)}"
    if value is None:
        return "none"
    return atom(type(value).__name__)


def literal(value: Any) -> str:
    raw = json.dumps(
        {"type": type(value).__name__, "value": str(value)},
        sort_keys=True,
        separators=(",", ":"),
    ).encode()
    return "lit_" + hashlib.sha256(raw).hexdigest()[:16]


def encode_graph(graph: torch.fx.Graph) -> tuple[str, dict]:
    calls = [node for node in graph.nodes if node.op == "call_function"]
    positions = {node: index for index, node in enumerate(calls)}

    def term(value: Any, current: int) -> str:
        if isinstance(value, Node):
            if value in positions and positions[value] < current:
                return f"(ref back_{current - positions[value]})"
            return (
                f"(external {atom(value.op)} "
                f"{value_type(value.meta.get('val'))})"
            )
        if isinstance(value, tuple):
            return "(tuple " + " ".join(
                term(item, current) for item in value
            ) + ")"
        if isinstance(value, list):
            return "(list " + " ".join(
                term(item, current) for item in value
            ) + ")"
        if isinstance(value, dict):
            return "(dict " + " ".join(
                f"(pair {literal(key)} {term(value[key], current)})"
                for key in sorted(value, key=str)
            ) + ")"
        return literal(value)

    descriptors = []
    for index, node in enumerate(calls):
        descriptors.append(
            "(call "
            + atom(str(node.target))
            + " "
            + value_type(node.meta.get("val"))
            + " "
            + term(node.args, index)
            + " "
            + term(node.kwargs, index)
            + ")"
        )
    outputs = next(node for node in graph.nodes if node.op == "output")
    tail = "(outputs " + term(outputs.args, len(calls)) + ")"
    for descriptor in reversed(descriptors):
        tail = f"(seq {descriptor} {tail})"
    metadata = {
        "call_nodes": len(calls),
        "operators": sorted({str(node.target) for node in calls}),
        "operator_counts": {
            target: sum(str(node.target) == target for node in calls)
            for target in sorted({str(node.target) for node in calls})
        },
        "program_sha256": hashlib.sha256(tail.encode()).hexdigest(),
        "program_bytes": len(tail.encode()),
    }
    return tail, metadata
