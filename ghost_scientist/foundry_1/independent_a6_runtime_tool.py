#!/usr/bin/env python3
"""Independent match-set and transformed-graph audit for the A6 tool."""

from __future__ import annotations

from typing import Any, Callable

from independent_a6_typed_anti_unification import accepts, extract


class IndependentA6RuntimeReject(ValueError):
    pass


def selected_root_ids(
    module: Any,
    artifact_id: str,
    pattern: dict[str, Any],
    depth: int,
) -> list[str]:
    return sorted(
        row["root_id"]
        for row in extract(module, artifact_id, depth)
        if accepts(pattern, row["term"])
    )


def audit_transformed_graph(
    module: Any,
    tool: Callable[..., Any],
    expected_sites: int,
) -> dict[str, Any]:
    tool_nodes = [
        node
        for node in module.graph.nodes
        if node.op == "call_function" and node.target is tool
    ]
    if len(tool_nodes) != expected_sites:
        raise IndependentA6RuntimeReject("tool node count")
    for node in tool_nodes:
        if (
            len(node.args) != 3
            or node.kwargs
            or any(getattr(arg, "graph", None) is not module.graph for arg in node.args)
        ):
            raise IndependentA6RuntimeReject("tool node signature")
    module.graph.lint()
    return {
        "tool_nodes": len(tool_nodes),
        "tool_node_names": [node.name for node in tool_nodes],
        "three_argument_signature": True,
        "graph_lint_passed": True,
    }
