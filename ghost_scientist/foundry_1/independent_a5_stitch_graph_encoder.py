#!/usr/bin/env python3
"""Independent iterative typed graph encoder for A5 Stitch."""

from __future__ import annotations

import hashlib
import json
import re
from typing import Any

import torch
from torch.fx import Node


def clean(text: str) -> str:
    result = re.sub("[^a-z0-9_]+", "_", text.lower()).strip("_")
    return result if result else "empty"


def kind(value: Any) -> str:
    if torch.is_tensor(value):
        return "tensor_r{}_{}_{}".format(
            value.dim(), clean(str(value.dtype)), clean(str(value.layout))
        )
    if isinstance(value, (tuple, list, dict)):
        return f"{type(value).__name__}_{len(value)}"
    return "none" if value is None else clean(type(value).__name__)


def leaf(value: Any) -> str:
    payload = json.dumps(
        {"type": type(value).__name__, "value": str(value)},
        separators=(",", ":"),
        sort_keys=True,
    )
    return "lit_" + hashlib.sha256(payload.encode()).hexdigest()[0:16]


def encode_graph(graph: torch.fx.Graph) -> tuple[str, dict]:
    nodes = tuple(item for item in graph.nodes if item.op == "call_function")
    index_by_node = dict(zip(nodes, range(len(nodes))))

    def render(item: Any, boundary: int) -> str:
        if isinstance(item, Node):
            earlier = index_by_node.get(item)
            if earlier is not None and earlier < boundary:
                return "(ref back_{})".format(boundary - earlier)
            return "(external {} {})".format(
                clean(item.op), kind(item.meta.get("val"))
            )
        if isinstance(item, tuple):
            return "(tuple {})".format(
                " ".join(render(child, boundary) for child in item)
            )
        if isinstance(item, list):
            return "(list {})".format(
                " ".join(render(child, boundary) for child in item)
            )
        if isinstance(item, dict):
            pieces = []
            for key in sorted(item.keys(), key=lambda value: str(value)):
                pieces.append(
                    "(pair {} {})".format(
                        leaf(key), render(item[key], boundary)
                    )
                )
            return "(dict {})".format(" ".join(pieces))
        return leaf(item)

    descriptions = []
    for ordinal, node in enumerate(nodes):
        descriptions.append(
            "(call {} {} {} {})".format(
                clean(str(node.target)),
                kind(node.meta.get("val")),
                render(node.args, ordinal),
                render(node.kwargs, ordinal),
            )
        )
    output_node = [item for item in graph.nodes if item.op == "output"][0]
    encoded = "(outputs {})".format(
        render(output_node.args, len(nodes))
    )
    for description in descriptions[::-1]:
        encoded = "(seq {} {})".format(description, encoded)
    targets = sorted(set(map(lambda node: str(node.target), nodes)))
    counts = {}
    for target in targets:
        counts[target] = len(
            [node for node in nodes if str(node.target) == target]
        )
    return encoded, {
        "call_nodes": len(nodes),
        "operators": targets,
        "operator_counts": counts,
        "program_sha256": hashlib.sha256(encoded.encode()).hexdigest(),
        "program_bytes": len(encoded.encode()),
    }
