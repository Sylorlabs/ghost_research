#!/usr/bin/env python3
"""Primary typed matching and priority-strategy evaluation for adapted A8."""

from __future__ import annotations

import json
from typing import Any

import torch
from torch.fx import Node


class A8StrategyReject(ValueError):
    pass


def canonical(value: object) -> str:
    return json.dumps(value, sort_keys=True, separators=(",", ":"))


def node_type(node: Node) -> dict[str, Any] | None:
    value = node.meta.get("val")
    if not isinstance(value, torch.Tensor):
        return None
    return {
        "rank": value.dim(),
        "dtype": str(value.dtype),
        "layout": str(value.layout),
    }


def enumerate_matches(
    graph: Any, portfolio: dict[str, Any]
) -> list[dict[str, Any]]:
    eligible = [
        node
        for node in graph.nodes
        if node.op == "call_function" and node_type(node) is not None
    ]
    eligible_set = set(eligible)
    rows = []
    for tool in portfolio["tools"]:
        expected_type = {
            "rank": tool["rank"],
            "dtype": tool["dtype"],
            "layout": tool["layout"],
        }

        def extend(path: list[Node]) -> None:
            index = len(path) - 1
            if (
                str(path[-1].target) != tool["targets"][index]
                or node_type(path[-1]) != expected_type
            ):
                return
            if len(path) == len(tool["targets"]):
                rows.append(
                    {
                        "tool": tool["name"],
                        "nodes": [node.name for node in path],
                    }
                )
                return
            for user in sorted(path[-1].users, key=lambda node: node.name):
                if user in eligible_set and user not in path:
                    extend(path + [user])

        for node in eligible:
            extend([node])
    return sorted(rows, key=lambda row: (row["tool"], row["nodes"]))


def evaluate(
    order: tuple[str, ...],
    graph_matches: list[tuple[str, list[dict[str, Any]]]],
) -> dict[str, Any]:
    priority = {name: index for index, name in enumerate(order)}
    covered = set()
    selected = []
    conflict_skips = 0
    eligible_artifacts = set()
    for artifact_id, matches in graph_matches:
        used = set()
        for row in sorted(
            matches,
            key=lambda item: (priority[item["tool"]], item["nodes"]),
        ):
            nodes = set(row["nodes"])
            if nodes & used:
                conflict_skips += 1
                continue
            used.update(nodes)
            eligible_artifacts.add(artifact_id)
            selected.append(
                {
                    "artifact_id": artifact_id,
                    "tool": row["tool"],
                    "nodes": row["nodes"],
                }
            )
            covered.update((artifact_id, node) for node in row["nodes"])
    return {
        "order": list(order),
        "unique_covered_nodes": len(covered),
        "eligible_artifacts": len(eligible_artifacts),
        "direct_uses": len(selected),
        "conflict_skips": conflict_skips,
        "selected": selected,
    }


def objective_key(row: dict[str, Any]) -> tuple[Any, ...]:
    return (
        -row["unique_covered_nodes"],
        -row["eligible_artifacts"],
        row["direct_uses"],
        row["conflict_skips"],
        tuple(row["order"]),
    )


def validate_record(
    record: dict[str, Any],
    tool_names: list[str],
    graph_matches: list[tuple[str, list[dict[str, Any]]]],
) -> None:
    if set(record) != {
        "order",
        "unique_covered_nodes",
        "eligible_artifacts",
        "direct_uses",
        "conflict_skips",
        "selected",
    }:
        raise A8StrategyReject("record fields")
    if (
        not isinstance(record["order"], list)
        or len(record["order"]) != len(tool_names)
        or sorted(record["order"]) != sorted(tool_names)
    ):
        raise A8StrategyReject("order is not a complete permutation")
    expected = evaluate(tuple(record["order"]), graph_matches)
    if record != expected:
        raise A8StrategyReject("record does not reproduce")
