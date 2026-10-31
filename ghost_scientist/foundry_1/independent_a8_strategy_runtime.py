#!/usr/bin/env python3
"""Independent recipe and transformed-graph audit for adapted A8."""

from __future__ import annotations

from typing import Any, Callable


class IndependentA8RuntimeReject(ValueError):
    pass


def recipe_targets(recipe: tuple[Any, ...]) -> list[str]:
    targets = []
    for row in recipe:
        if (
            type(row) is not tuple
            or len(row) != 3
            or type(row[0]) is not str
            or type(row[1]) is not tuple
            or type(row[2]) is not tuple
        ):
            raise IndependentA8RuntimeReject("recipe row")
        targets.append(row[0])
    return targets


def audit(
    module: Any,
    executor: Callable[..., Any],
    expected: list[dict[str, Any]],
    portfolio: dict[str, Any],
) -> dict[str, Any]:
    specs = {row["name"]: row for row in portfolio["tools"]}
    nodes = [
        node
        for node in module.graph.nodes
        if node.op == "call_function" and node.target is executor
    ]
    if len(nodes) != len(expected):
        raise IndependentA8RuntimeReject("executor count")
    rows = []
    for node, decision in zip(nodes, expected, strict=True):
        if len(node.args) < 2 or node.kwargs:
            raise IndependentA8RuntimeReject("executor signature")
        recipe = node.args[0]
        targets = recipe_targets(recipe)
        if targets != specs[decision["tool"]]["targets"]:
            raise IndependentA8RuntimeReject("tool target sequence")
        rows.append(
            {
                "tool": decision["tool"],
                "targets": targets,
                "external_inputs": len(node.args) - 1,
                "executor_node": node.name,
            }
        )
    module.graph.lint()
    return {
        "executor_nodes": len(nodes),
        "recipes": rows,
        "graph_lint_passed": True,
    }
